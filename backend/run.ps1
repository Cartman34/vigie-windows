<#
    run.ps1 - Lance le panneau. IDEMPOTENT. Cible PowerShell 7.
    Journalise ses decisions dans backend/logs/run_*.log. Rebascule en pwsh si
    lance en 5.1, et s'eleve (UAC) si necessaire : le serveur doit tourner avec
    les droits admin pour lire/appliquer l'etat Windows Update. Les fenetres
    relancees gardent -NoExit (elles ne se ferment plus toutes seules en cas
    d'erreur). Si Pode manque, il est installe automatiquement (install.ps1).
    Le navigateur n'est ouvert qu'une fois le serveur reellement a l'ecoute.

    Usage :
        pwsh -File .\run.ps1              # lance + ouvre l'UI (demande UAC)
        pwsh -File .\run.ps1 -NoBrowser   # sans navigateur
#>
param(
    [switch]$Admin,      # conserve pour compat ; l'elevation est de toute facon automatique
    [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
$backend = $PSScriptRoot
. (Join-Path $backend 'lib/common.ps1')

$needPwsh = $PSVersionTable.PSVersion.Major -lt 7
$isAdmin  = Test-Elevated
$needElev = (-not $isAdmin)   # le serveur doit tourner avec les droits (UAC si besoin)

$runLog = Join-Path (Get-LogDir -Backend $backend) ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $runLog -Force | Out-Null } catch { }
Write-Log -Backend $backend -Name 'run' -Message ("run.ps1 : PS=" + $PSVersionTable.PSVersion + " eleve=" + $isAdmin)

# --- Relance sous pwsh et/ou eleve si necessaire (fenetre maintenue) ---
if ($needPwsh -or $needElev) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message "PowerShell 7 requis. Lance install.ps1."
        try { Stop-Transcript | Out-Null } catch { }
        return
    }
    $argList = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    if ($NoBrowser) { $argList += '-NoBrowser' }
    Write-Log -Backend $backend -Name 'run' -Message ("Relance pwsh (eleve=" + $needElev + ")")
    try {
        if ($needElev) { Start-Process $pwsh.Source -Verb RunAs -ArgumentList $argList }
        else           { Start-Process $pwsh.Source -ArgumentList $argList }
    } catch {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message ("Relance echouee : " + $_.Exception.Message)
        Write-Host "Relance impossible. Ouvre un terminal pwsh (admin) et lance start.ps1." -ForegroundColor Yellow
    }
    try { Stop-Transcript | Out-Null } catch { }
    return
}

# --- Prerequis Pode : auto-installation si absent (idempotent) ---
if (-not (Get-Module -ListAvailable -Name Pode)) {
    Write-Log -Backend $backend -Name 'run' -Level 'WARN' -Message "Pode manquant - installation automatique..."
    & (Join-Path $backend 'install.ps1')
    if (-not (Get-Module -ListAvailable -Name Pode)) {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message "Pode toujours absent apres install.ps1."
        try { Stop-Transcript | Out-Null } catch { }
        return
    }
}

$cfg = Get-Config -Backend $backend
$url = "http://{0}:{1}/" -f $cfg.BindAddress, $cfg.Port

if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
    Write-Log -Backend $backend -Name 'run' -Message ("Deja en cours : " + $url + " - ouverture UI.")
    if (-not $NoBrowser) { Start-Process $url }
    try { Stop-Transcript | Out-Null } catch { }
    return
}

# --- Ouverture du navigateur : on attend que le serveur ecoute reellement ---
# (job en arriere-plan car start.ps1 est bloquant ; sonde TCP jusqu'a 40 s)
if (-not $NoBrowser) {
    Start-Job -ScriptBlock {
        param($u, $addr, $port)
        for ($i = 0; $i -lt 80; $i++) {
            try {
                $c = [System.Net.Sockets.TcpClient]::new()
                $c.Connect($addr, [int]$port)
                if ($c.Connected) { $c.Close(); Start-Sleep -Milliseconds 500; Start-Process $u; return }
            } catch { Start-Sleep -Milliseconds 500 }
        }
        Start-Process $u
    } -ArgumentList $url, $cfg.BindAddress, $cfg.Port | Out-Null
    Write-Log -Backend $backend -Name 'run' -Message ("Navigateur planifie (attente ecoute) : " + $url)
}

try { Stop-Transcript | Out-Null } catch { }   # start.ps1 a son propre transcript
& (Join-Path $backend 'start.ps1')
