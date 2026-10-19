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
