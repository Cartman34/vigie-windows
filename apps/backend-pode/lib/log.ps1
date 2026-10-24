# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses: paths, var
<#
    Intent: WRITING DOWN WHAT HAPPENED, in one place and in one shape, so a log can be read without knowing who
    wrote it. The folder is created if it is missing -- logging must never fail for want of a directory.
    Usage: dot-sourced by common.ps1, never run on its own. It asks `var` where the logs live and nothing else;
    `var` does not call back, which is what keeps the two readable apart (S28).
#>

# --- Logging ----------------------------------------------------------------

function Get-LogDir {
    param([string]$Backend = (Get-BackendRoot))
    $d = Get-VarPath -Backend $Backend -Kind 'log'
    # -WhatIf:$false: creating the log folder is plumbing, not an operation the user
    # simulates. Without it, -WhatIf prevents any logging at all.
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force -WhatIf:$false | Out-Null }
    $d
}
function Write-Log {
    param(
        # AN EMPTY LINE IS A LINE. The installation log relays what each sub-script displays,
        # blank layout lines included: without this permission, every breath produced a
        # "Cannot bind argument to parameter Message" in the transcript -- red noise on an
        # installation that was going perfectly well.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [string]$Level = 'INFO',
        [string]$Name  = 'app',
        [string]$Backend = (Get-BackendRoot),
        # Write WITHOUT displaying again: the line is already on screen, we only want to keep it.
        [switch]$NoEcho
    )
    $dir  = Get-LogDir -Backend $Backend
    $file = Join-Path $dir ($Name + '_' + (Get-Date -Format 'yyyyMMdd') + '.log')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $file -Value $line -Encoding UTF8 } catch { }

    # THE SCREEN AND THE FILE DO NOT SAY THE SAME THING, and that is deliberate. The file
    # keeps the timestamp and the level: it is the one read back weeks later. The screen
    # speaks the language of every other script (scripts/lib/console-ui.ps1).
    #
    # WHY: on 28/08 an installation step failed; its ERROR came out grey among twenty grey
    # lines, and the user could not see it. A log level that does not stand out on screen is
    # no use at all.
    #
    # The fallback exists because common.ps1 is loaded by scripts that have no need of the
    # display -- the server, the probes: the dependency is not imposed on them.
    if ($NoEcho) { return }
    $hasUi = [bool](Get-Command Write-Fail -ErrorAction SilentlyContinue)
    switch ($Level) {
        'ERROR' { if ($hasUi) { Write-Fail $Message } else { Write-Host $line -ForegroundColor Red } }
        'WARN'  { if ($hasUi) { Write-Warn $Message } else { Write-Host $line -ForegroundColor Yellow } }
        default { if ($hasUi) { Write-Info $Message } else { Write-Host $line } }
    }
}

<#
    WHY IT FAILED: WE READ IT IN THE LOG, WE DO NOT GUESS IT.

    The watcher knows only an EXIT CODE. So the card displayed a failure, a date and "exit code 4": a number, to
    a person who wants to know what happened. The script, on the other hand, said it -- that an installation was
    already running, under which account and in which process -- and that sentence is in the log the watcher
    already holds in its hand.

    So the LAST failure line is taken from it, the one the console marked "[X]". It is
    general: any script of the repository using console-ui becomes readable on the card,
    without declaring anything.

    If the log holds none -- a process killed, a script that said nothing -- the exit code is
    kept: a number beats nothing.
#>
function Get-FailureReasonFromLog {
    param([Parameter(Mandatory)][string]$Log)
    if (-not $Log -or -not (Test-PathSafe $Log)) { return $null }
    <#
        WE READ IN UTF-8, AND WE CATCH OURSELVES IF IT IS NOT.

        Logs written before the display was forced to UTF-8 are in the system's code page:
        read as UTF-8, their accents become "?". It is DETECTED -- the replacement character
        U+FFFD -- and the file is read again in the default code page. An existing log must
        not become unreadable because the writing was corrected.
    #>
    $lines = $null
    try { $lines = @(Get-Content -LiteralPath $Log -Encoding UTF8 -ErrorAction Stop) } catch { return $null }
    if (($lines -join '') -match [char]0xFFFD) {
        # "-Encoding Default" NO LONGER MEANS "the system's code page": since PowerShell 7 it
        # is UTF-8, so re-reading that way gave exactly the same "?". We name the machine's
        # ANSI code page, assuming nothing.
        try {
            $ansi = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
            $lines = @([IO.File]::ReadAllText($Log, $ansi) -split "`r?`n")
        } catch { }
    }
    $reason = $null
    try {
        foreach ($line in $lines) {
            # "[X]" is console-ui's failure mark, the same everywhere.
            if ("$line" -match '\[X\]\s*(.+?)\s*$') { $reason = $Matches[1].Trim() }
        }
    } catch { }
    if ($reason) { return $reason }
    return $null
}
