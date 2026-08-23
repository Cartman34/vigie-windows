<#
    start.ps1 - Point d'entree du backend. IDEMPOTENT. Cible PowerShell 7.
    Journalise tout dans backend/logs/ (transcript + Write-Log + logs Pode via
    server.ps1). Bascule en pwsh si lance en 5.1. Ne relance pas si deja en cours.
    Si Pode manque, l'installe automatiquement (via install.ps1) puis re-verifie.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')

# --- Cible PowerShell 7 + droits admin (le serveur doit avoir les droits) ---
$isAdmin = Test-Elevated
if (($PSVersionTable.PSVersion.Major -lt 7) -or (-not $isAdmin)) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { Write-Host "PowerShell 7 requis. Lance d'abord install.ps1." -ForegroundColor Yellow; return }
    $relArgs = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    if (-not $isAdmin) { Start-Process $pwsh.Source -Verb RunAs -ArgumentList $relArgs }
    else               { Start-Process $pwsh.Source -ArgumentList $relArgs }
    return
}

$backend = $PSScriptRoot
. (Join-Path $backend 'lib/common.ps1')

$logDir   = Get-LogDir -Backend $backend
$startLog = Join-Path $logDir ('start_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $startLog -Force | Out-Null } catch { }

try {
    Write-Log -Backend $backend -Name 'start' -Message ("PowerShell " + $PSVersionTable.PSVersion)

    $pode = Get-Module -ListAvailable -Name Pode | Select-Object -First 1
    if (-not $pode) {
        Write-Log -Backend $backend -Name 'start' -Level 'WARN' -Message "Module Pode absent - installation automatique..."
        & (Join-Path $backend 'install.ps1')
        $pode = Get-Module -ListAvailable -Name Pode | Select-Object -First 1
        if (-not $pode) {
            Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message "Pode toujours absent apres install.ps1. Verifie la connexion PSGallery."
            return
        }
    }
    Write-Log -Backend $backend -Name 'start' -Message ("Pode " + $pode.Version)

    $cfg = Get-Config -Backend $backend
    if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
        Write-Log -Backend $backend -Name 'start' -Message ("Deja en cours sur " + (Get-AppUrl -Config $cfg) + " - abandon.")
        return
    }

    $env:VIGIE_BACKEND = $backend
    $env:VIGIE_TOKEN   = Get-ApiToken -Backend $backend
    $env:VIGIE_PORT    = "$($cfg.Port)"

    Import-Module Pode
    Write-Log -Backend $backend -Name 'start' -Message ("Demarrage : " + (Get-ApiUrl -Config $cfg))
    Write-Host ("UI  : " + (Get-AppUrl -Config $cfg))

    Start-PodeServer -Threads 3 {
        . "$env:VIGIE_BACKEND/server.ps1"
    }
}
catch {
    Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message ("FATAL: " + $_.Exception.Message)
    Write-Host ($_ | Out-String) -ForegroundColor Red
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
