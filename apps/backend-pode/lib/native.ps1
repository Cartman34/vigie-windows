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
function Invoke-Native {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @())
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
