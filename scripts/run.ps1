# @author Florent HAZARD <f.hazard@sowapps.com>
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
# Les scripts de gestion vivent dans scripts/ : les apps sont dans apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

$needPwsh = $PSVersionTable.PSVersion.Major -lt 7
$isAdmin  = Test-Elevated
$needElev = (-not $isAdmin)   # le serveur doit tourner avec les droits (UAC si besoin)

$runLog = Join-Path (Get-LogDir -Backend $backend) ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $runLog -Force | Out-Null } catch { }
Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.run-ps1-ps-eleve' $PSVersionTable.PSVersion $isAdmin)

# --- Relance sous pwsh et/ou eleve si necessaire (fenetre maintenue) ---
if ($needPwsh -or $needElev) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message (Get-Label 'run.powershell-requis-lance-install')
        try { Stop-Transcript | Out-Null } catch { }
        return
    }
    # RAW VALUES: Start-ChildProcess is what quotes them (D116). This script may live
    # under "C:\Program Files\Sowapps\Vigie", where a bare path dies on
    # "C:\Program is not a script".
    $argList = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    if ($NoBrowser) { $argList += '-NoBrowser' }
    Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.relance-pwsh-eleve' $needElev)
    try {
        $opts = @{}
        if ($needElev) { $opts['Verb'] = 'RunAs' }
        Start-ChildProcess -FilePath $pwsh.Source -Arguments $argList -Options $opts
    } catch {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message (Get-Label 'run.relance-echouee' $_.Exception.Message)
        Write-Warn (Get-Label 'run.relance-impossible-ouvre-un')
    }
    try { Stop-Transcript | Out-Null } catch { }
    return
}

# --- Prerequis Pode : auto-installation si absent (idempotent) ---
if (-not (Get-Module -ListAvailable -Name Pode)) {
    Write-Log -Backend $backend -Name 'run' -Level 'WARN' -Message (Get-Label 'run.pode-manquant-installation-automatique')
    & (Join-Path $backend 'install.ps1')
    if (-not (Get-Module -ListAvailable -Name Pode)) {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message (Get-Label 'run.pode-toujours-absent-apres')
        try { Stop-Transcript | Out-Null } catch { }
        return
    }
}

$cfg = Get-Config -Backend $backend
$url = Get-AppUrl -Config $cfg

if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
    Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.deja-en-cours-ouverture' $url)
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
    Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.navigateur-planifie-attente-ecoute' $url)
}

try { Stop-Transcript | Out-Null } catch { }   # start.ps1 a son propre transcript
& (Join-Path $backend 'start.ps1')
