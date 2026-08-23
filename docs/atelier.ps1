<#
.SYNOPSIS
    Atelier de validation visuelle de Vigie : sert le depot en local et ouvre la page.

.DESCRIPTION
    Demarre un petit serveur web local (serveur integre de PHP) a la racine du depot, puis
    ouvre docs/atelier-validation.html dans le navigateur.

    POURQUOI un serveur plutot qu'un double-clic sur le fichier : ouverte en file://, la page
    ne peut pas lire les assets (les chemins relatifs cassent des que le fichier est deplace
    ou copie) et le navigateur refuse d'afficher l'ecran de chargement dans un cadre. Servie
    en http, elle fonctionne entierement.

    Le serveur ecoute STRICTEMENT en local et ne demande aucun droit administrateur.
    Il ne sert qu'a valider : il ne remplace pas le serveur applicatif (backend/start.ps1),
    tourne sur un port distinct et ne le concurrence jamais.

    CONFIGURATION - un seul endroit : l'adresse et le port viennent de backend/config.psd1
    (cles BindAddress et AtelierPort). Ne les recopie nulle part ailleurs.

.PARAMETER Status
    N'affiche que l'etat (en ligne ou non, port, PID) et sort. Ne demarre rien.

.PARAMETER Stop
    Arrete l'atelier s'il tourne. Sans effet s'il est deja arrete.

.PARAMETER Background
    Demarre le serveur en tache de fond et rend la main immediatement, au lieu d'occuper
    la console jusqu'a Ctrl+C.

.PARAMETER NoBrowser
    Ne pas ouvrir le navigateur (utile quand un onglet est deja ouvert).

.EXAMPLE
    pwsh -File .\docs\atelier.ps1
    Demarre l'atelier et ouvre le navigateur. Ctrl+C pour arreter.

.EXAMPLE
    pwsh -File .\docs\atelier.ps1 -Background
    Demarre en tache de fond et rend la main.

.EXAMPLE
    pwsh -File .\docs\atelier.ps1 -Status
    Indique si l'atelier tourne, sur quel port et avec quel PID.

.EXAMPLE
    pwsh -File .\docs\atelier.ps1 -Stop
    Arrete l'atelier.

.NOTES
    Codes de retour : 0 = succes ; 1 = prerequis manquant (php absent) ; 2 = echec de demarrage.
    Documentation complete : docs/atelier.md
    Aide : Get-Help .\docs\atelier.ps1 -Full
#>
[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Status')][switch] $Status,
    [Parameter(ParameterSetName = 'Stop')]  [switch] $Stop,
    [Parameter(ParameterSetName = 'Start')] [switch] $Background,
    [Parameter(ParameterSetName = 'Start')] [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'
$repo    = Split-Path $PSScriptRoot -Parent
$backend = Join-Path $repo 'backend'
. (Join-Path $backend 'lib/common.ps1')

# Adresse et port : UNE seule definition, dans config.psd1 (D15).
$cfg     = Get-Config -Backend $backend
$address = $cfg.BindAddress
$port    = $cfg.AtelierPort
$url     = 'http://{0}:{1}/docs/atelier-validation.html' -f $address, $port

# Quel processus tient le port ? (sert a l'etat et a l'arret : aucun fichier de PID a gerer)
function Get-AtelierProcess {
    try {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
                Select-Object -First 1
        if ($conn) { return Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue }
    } catch { }
    return $null
}

# --- Etat --------------------------------------------------------------------
if ($Status) {
    $proc = Get-AtelierProcess
    if ($proc) {
        Write-Host ("Atelier EN LIGNE  - {0}  (PID {1}, {2})" -f $url, $proc.Id, $proc.ProcessName)
    } else {
        Write-Host ("Atelier ARRETE    - port {0} libre" -f $port)
    }
    exit 0
}

# --- Arret -------------------------------------------------------------------
if ($Stop) {
    $proc = Get-AtelierProcess
    if (-not $proc) { Write-Host "Atelier deja arrete (rien a faire)."; exit 0 }
    try {
        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        Write-Host ("Atelier arrete (PID {0})." -f $proc.Id)
        exit 0
    } catch {
        Write-Host ("Impossible d'arreter le PID {0} : {1}" -f $proc.Id, $_.Exception.Message) -ForegroundColor Red
        exit 2
    }
}

# --- Prerequis ---------------------------------------------------------------
$php = (Get-Command php -ErrorAction SilentlyContinue).Source
if (-not $php) {
    Write-Host "php introuvable dans le PATH : l'atelier utilise le serveur integre de PHP." -ForegroundColor Yellow
    Write-Host ("Solution de repli, sans serveur : ouvre directement " + (Join-Path $PSScriptRoot 'atelier-validation.html'))
    Write-Host "  (les icones livrees et l'ecran de chargement ne s'y afficheront pas)"
    exit 1
}

# --- Idempotence : deja en ecoute ? ------------------------------------------
if (Get-AtelierProcess) {
    Write-Host ("Atelier deja en ligne : " + $url)
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

Write-Host ("Atelier de validation : " + $url)
Write-Host ("Racine servie         : " + $repo)

$phpArgs = @('-S', ("{0}:{1}" -f $address, $port), '-t', $repo)

# --- Tache de fond -----------------------------------------------------------
if ($Background) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $php
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    foreach ($a in $phpArgs) { [void]$psi.ArgumentList.Add($a) }
    $proc = [System.Diagnostics.Process]::Start($psi)

    for ($i = 0; $i -lt 40; $i++) {
        if (Test-ServerUp -Address $address -Port $port) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not (Test-ServerUp -Address $address -Port $port)) {
        Write-Host "Le serveur n'a pas repondu dans le delai imparti." -ForegroundColor Red
        exit 2
    }
    Write-Host ("Demarre en tache de fond (PID {0}). Arret : .\docs\atelier.ps1 -Stop" -f $proc.Id)
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

# --- Premier plan : la console montre les requetes, Ctrl+C arrete -------------
Write-Host "Ctrl+C pour arreter."
Write-Host ""

if (-not $NoBrowser) {
    # Le navigateur est lance en differe : le serveur doit d'abord ecouter.
    Start-Job -ScriptBlock {
        param($u, $a, $p)
        for ($i = 0; $i -lt 40; $i++) {
            try { $c = [System.Net.Sockets.TcpClient]::new(); $c.Connect($a, $p); $c.Close()
                  Start-Process $u; break }
            catch { Start-Sleep -Milliseconds 250 }
        }
    } -ArgumentList $url, $address, $port | Out-Null
}

& $php @phpArgs
$code = $LASTEXITCODE
Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Running' } |
    Remove-Job -ErrorAction SilentlyContinue
if ($null -eq $code) { $code = 0 }
exit $code
