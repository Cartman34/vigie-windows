# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    start.ps1 -- the server app's entry point. IDEMPOTENT. Targets PowerShell 7.

    Intent: be the ONE road into the server -- switch to pwsh if started under 5.1, elevate if needed, install
    Pode if it is missing, and refuse to start a second one if it is already running.
    Usage: it is what the scheduled task runs; by hand, pwsh -File .\apps\backend-pode\start.ps1. It logs
    everything into backend/logs/ (a transcript plus Write-Log plus Pode's own logs through server.ps1).
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')

# --- Target PowerShell 7 plus administrator rights (the server needs them) ---
$isAdmin = Test-Elevated
if (($PSVersionTable.PSVersion.Major -lt 7) -or (-not $isAdmin)) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { Write-Warn (Get-Label 'start.powershell-requis-lance-abord'); return }
    $relArgs = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    $opts = @{}
    if (-not $isAdmin) { $opts['Verb'] = 'RunAs' }
    Start-ChildProcess -FilePath $pwsh.Source -Arguments $relArgs -Options $opts
    return
}

$backend = $PSScriptRoot
. (Join-Path $backend 'lib/common.ps1')

# THE EVENT LOG'S SOURCE, if it is missing. An installation older than the traceability does not have it; the
# server is elevated, so it can lay it down. Silent: that is no reason not to start.
try { $null = Register-VigieEventSource -Quiet } catch { }

$logDir   = Get-LogDir -Backend $backend
$startLog = Join-Path $logDir ('start_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $startLog -Force | Out-Null } catch { }

try {
    Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.powershell' $PSVersionTable.PSVersion)

    $pode = Get-Module -ListAvailable -Name Pode | Select-Object -First 1
    if (-not $pode) {
        Write-Log -Backend $backend -Name 'start' -Level 'WARN' -Message (Get-Label 'start.module-pode-absent-installation')
        & (Join-Path $backend 'install.ps1')
        $pode = Get-Module -ListAvailable -Name Pode | Select-Object -First 1
        if (-not $pode) {
            Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message (Get-Label 'start.pode-toujours-absent-apres')
            return
        }
    }
    Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.pode' $pode.Version)

    $cfg = Get-Config -Backend $backend
    if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
        Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.deja-en-cours-sur' (Get-AppUrl -Config $cfg))
        return
    }

    $env:VIGIE_BACKEND = $backend
    $env:VIGIE_TOKEN   = Get-ApiToken -Backend $backend
    $env:VIGIE_PORT    = "$($cfg.Port)"

    # SELF-REPAIR OF OUR OWN TASKS, at startup (D83).
    # Explicitly authorised: "the app may self-correct the system as long as it is pure Vigie". A task aiming at
    # an interpreter that has gone starts and dies without a word; repairing it here means repairing it before
    # anybody notices. It touches no task that is not ours, and never creates anything.
    try {
        $repares = @(Repair-VigieTasks -Backend $backend)
        foreach ($r in $repares) {
            Write-Log -Backend $backend -Name 'start' -Level $(if ($r.repare) { 'INFO' } else { 'ERROR' }) `
                      -Message (Get-Label 'start.tache' $r.tache $r.mal $(if ($r.repare) { 'reparee' } else { 'ECHEC' }))
        }
    } catch {
        Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message (Get-Label 'start.auto-reparation' $_.Exception.Message)
    }

    # THE LOGS ARE KEPT 30 DAYS (Invoke-LogPurge): at each start of the server, then daily with the history purge.
    try { $null = Invoke-LogPurge -Backend $backend } catch { }

    Import-Module Pode
    Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.demarrage' (Get-ApiUrl -Config $cfg))
    Write-Info (Get-Label 'start.ui' (Get-AppUrl -Config $cfg))
    Start-PodeServer -Threads 3 {
        . "$env:VIGIE_BACKEND/server.ps1"
    }
}
catch {
    Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message (Get-Label 'start.fatal' $_.Exception.Message)
    Write-Fail ($_ | Out-String)
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
