# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: TALKING TO WINDOWS, and doing it once. Am I elevated? How is a value quoted for a command line, as
    opposed to for PowerShell source? How is a native command run so that its output, its errors AND its exit
    code are all handled? Each of those has exactly one implementation here, because each of them was written
    three ways before.
    Usage: dot-sourced by common.ps1, never run on its own. It knows no path, no configuration and no state, and
    it never calls upwards (S28).
#>

<#
    RUNNING A COMMAND WITH A DEADLINE, AND KILLING IT WHOLE.

    The output is read while the command runs, not after: a pipe that fills up with nobody emptying it blocks the
    command, and we would then kill for a deadline we had caused ourselves.

    The children go with it. A tool that launches a helper -- which is what talking to a virtual machine does --
    leaves it behind when only the parent is killed, and that orphan goes on holding what it holds.
#>
function Invoke-NativeWithDeadline {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $File
    foreach ($a in @($Arguments)) { $info.ArgumentList.Add("$a") }
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    # UTF-8 BOTH WAYS: modern tools emit it, and the OEM code page turned every accent into a pair of symbols.
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $timedOut = $false
    $code = -1
    $text = ''
    try {
        $null = $process.Start()
        # READ WHILE IT RUNS: both streams at once, so neither pipe can fill and block the command.
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { $process.Kill($true) } catch { try { $process.Kill() } catch { } }
            try { $null = $process.WaitForExit(2000) } catch { }
        } else {
            $code = $process.ExitCode
        }
        $parts = @()
        foreach ($task in @($outTask, $errTask)) {
            try { if ($task.Wait(2000)) { $parts += "$($task.Result)" } } catch { }
        }
        $text = (($parts -join [Environment]::NewLine).Trim()) -replace (([char]0x1B) + '\[[0-9;]*[A-Za-z]'), ''
    } catch {
        $text = "$($_.Exception.Message)"
    } finally {
        try { $process.Dispose() } catch { }
    }
    return [pscustomobject]@{ Ok = (-not $timedOut -and $code -eq 0); ExitCode = $code; Output = $text; TimedOut = $timedOut }
}

<#
    THE TIME A PIECE OF WORK REALLY TOOK, WHICH IS NOT THE TIME ON THE CLOCK.

    Measured on 30/10, on this machine: 158 251 seconds since boot on the clock, 158 251 counted by the tick
    counter, and 111 871 of real activity -- THIRTEEN HOURS of sleep that the tick counter includes as if work had
    been happening. That is where "computed in 34 722 332 ms", nine and a half hours, came from on 16/10: the
    machine slept in the middle of a computation that had long since finished, and the overrun was logged,
    historised and shown on a card, drowning the real ones.

    Windows has the right counter for this, and only this one: unbiased interrupt time, which stops while the
    machine sleeps. It is asked for here, once, and the whole repository has one place to ask.

    WHAT MUST NOT USE IT: how long the machine has been UP, which is a clock question -- a person who left their
    PC asleep for the night expects "up for 2 days", not "up for 13 hours".

    The declaration is compiled on the FIRST call, not when this file loads: every probe loads this library, and
    none of them should pay for a compilation it will not use. Without the counter, we fall back on the tick
    counter: a biased duration beats no duration.
#>
$script:UnbiasedReady = $null
function Get-ActiveMilliseconds {
    if ($null -eq $script:UnbiasedReady) {
        $script:UnbiasedReady = $false
        try {
            if (-not ('Vigie.Clock' -as [type])) {
                Add-Type -Name 'Clock' -Namespace 'Vigie' -ErrorAction Stop -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool QueryUnbiasedInterruptTime(out ulong UnbiasedTime);
'@
            }
            $script:UnbiasedReady = [bool]('Vigie.Clock' -as [type])
        } catch { $script:UnbiasedReady = $false }
    }
    if ($script:UnbiasedReady) {
        try {
            [ulong]$ticks = 0
            if ([Vigie.Clock]::QueryUnbiasedInterruptTime([ref]$ticks)) {
                # The counter is in units of 100 nanoseconds.
                return [long]($ticks / 10000)
            }
        } catch { }
    }
    return [long][Environment]::TickCount64
}

# Is the current process elevated (administrator)?
function Test-Elevated {
    try {
        return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

<#
    ONE VALUE, ONE ARGUMENT -- whatever that value contains.

    A Windows command line is a SINGLE STRING; the child splits it again with the rules of
    CommandLineToArgvW. Start-Process joins -ArgumentList with spaces and quotes NOTHING, so
    each value handed to it must already be a valid token.

    Wrapping it by hand -- ('"' + $path + '"') -- is the trap that looks like the fix: it
    holds for "C:\Program Files\Sowapps\Vigie" and breaks on a path that ends with a
    backslash, because "C:\dir\" escapes its own closing quote and swallows the argument
    that follows.

    Three rules, and no others:
      - an empty value is not nothing, it is a pair of quotes;
      - a backslash only matters in front of a quote (the end of the value counts, since the
        closing quote comes next): there, it doubles;
      - a value carrying a space, a tab or a quote is wrapped -- anything else is passed as
        it stands, because wrapping what needs nothing hides what does.

    The sibling of ConvertTo-PSLiteral, which answers the same question for the OTHER world:
    a value inserted into PowerShell source. Neither escaping fits the other's world.
#>
function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Value)
    if ($null -eq $Value -or $Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $out = [Text.StringBuilder]::new('"')
    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') { $backslashes++; continue }
        if ($ch -eq '"') { [void]$out.Append('\' * (2 * $backslashes + 1)); [void]$out.Append('"'); $backslashes = 0; continue }
        if ($backslashes -gt 0) { [void]$out.Append('\' * $backslashes); $backslashes = 0 }
        [void]$out.Append($ch)
    }
    # Trailing backslashes sit just before the closing quote: they double, or they escape it.
    if ($backslashes -gt 0) { [void]$out.Append('\' * (2 * $backslashes)) }
    [void]$out.Append('"')
    $out.ToString()
}

<#
    STARTING A PROCESS WITH ARGUMENTS GOES THROUGH HERE, ALWAYS (D116).

    Arguments are given RAW, as values; the quoting happens here, once, for everyone. That is
    the whole point: the fault it prevents cannot be seen when rereading the line, and says
    nothing at run time -- on 02/09 the game resident died at every arming on "C:\Program is
    not a script", and only its health field ever revealed it. A rule nobody can check is a
    rule nobody keeps, so check-probes refuses a bare Start-Process everywhere but here.

    Everything else Start-Process accepts -- Wait, PassThru, Verb, WindowStyle,
    WorkingDirectory, redirections -- travels untouched through -Options.

    THE CALL OPERATOR IS ANOTHER WORLD: "& $exe @arguments" quotes each value ITSELF, so a
    value wrapped by hand arrives WITH its quotes. Invoke-Native, which uses it, therefore
    takes raw values too -- the same discipline, the opposite mechanism.
#>
function Start-ChildProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [hashtable]$Options = @{}
    )
    $splat = @{}
    foreach ($k in $Options.Keys) { $splat[$k] = $Options[$k] }
    $splat['FilePath'] = $FilePath
    if ($Arguments.Count -gt 0) {
        $splat['ArgumentList'] = @($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) })
    }
    Start-Process @splat
}

# Runs a native command handling its output AND its exit code (the rule: errors, output and
# exit codes are always handled). Returns one uniform object.
<#
    AND IT CAN BE GIVEN A DEADLINE.

    Without one, a command that never returns takes its caller with it: a card's value is computed in a
    background task, and a frozen command keeps that task, its place among the eight allowed, and the card's
    freshness. That is why the WSL card refused to ask WSL anything at all -- the tool can be slow to answer when
    its machine is cold, and there was no way to be patient without risking everything.

    With a deadline, waiting becomes a choice: the command is given its seconds, and what passes them is KILLED,
    it and its children. An expiry is said -- `TimedOut`, and an exit code of -1 -- because "it did not answer in
    thirty seconds" is an answer, where a blank is not.

    No deadline means the old road, unchanged: thirty-odd callers rely on it, and none of them had to move.
#>
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$Arguments = @(),
        # Seconds before the command is killed. 0 = wait as long as it takes, as before.
        [int]$TimeoutSeconds = 0
    )
    if ($TimeoutSeconds -gt 0) { return (Invoke-NativeWithDeadline -File $File -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds) }
    # winget, like other modern tools, emits UTF-8; PowerShell decoded it with the OEM code
    # page (850) and every accent became a pair of symbols -- including in the error messages
    # shown to the user. UTF-8 is forced for the length of the capture.
    $before = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
    try {
        $out = & $File @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        try { [Console]::OutputEncoding = $before } catch { }
    }
    # winget decorates its output with ANSI sequences for highlighting: unreadable once
    # captured, so they are stripped. [...letter is the standard CSI form.
    $text = (($out | Out-String).TrimEnd()) -replace "\[[0-9;]*[A-Za-z]", ''
    [pscustomobject]@{ Ok = ($code -eq 0); ExitCode = $code; Output = $text }
}
