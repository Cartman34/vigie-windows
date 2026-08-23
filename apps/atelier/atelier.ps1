<#
.SYNOPSIS
    Atelier : app de developpement de Vigie. Sert le depot en local et ouvre la page.

.DESCRIPTION
    Demarre un petit serveur web local (serveur integre de PHP) a la racine du depot, puis
    ouvre apps/atelier/index.html dans le navigateur.

    L'ATELIER N'EST PAS VIGIE. C'est une app DISTINCTE, de developpement :
      - Vigie    : apps/backend-pode + apps/frontend-web + apps/tray, PowerShell + Pode, port 47600,
                   ELEVEE, lancee par la tache planifiee a l'ouverture de session.
      - Atelier  : cette app, PHP, port 47610, JAMAIS elevee, lancee a la main.
    L'Atelier n'expose aucune API, n'execute aucune sonde et n'a acces a aucun secret.
    Il ne doit pas tourner chez l'utilisateur final.

    POURQUOI un serveur plutot qu'un double-clic : ouverte en file://, la page ne peut pas
    lire les assets (les chemins relatifs cassent des que le fichier est deplace ou copie)
    et le navigateur refuse d'afficher l'ecran de chargement dans un cadre. Servie en http,
    elle fonctionne entierement.

    CONFIGURATION : apps/atelier/config/config.psd1 - la config de CETTE app. Elle ne lit pas celle
    du backend : chaque app est maitresse de ses propres valeurs.

.PARAMETER Status
    N'affiche que l'etat (en ligne ou non, port, PID) et sort. Ne demarre rien.

.PARAMETER Stop
    Arrete l'Atelier s'il tourne. Sans effet s'il est deja arrete.

.PARAMETER Background
    Demarre le serveur en tache de fond et rend la main immediatement, au lieu d'occuper
    la console jusqu'a Ctrl+C.

.PARAMETER NoBrowser
    Ne pas ouvrir le navigateur (utile quand un onglet est deja ouvert).

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1
    Demarre l'Atelier et ouvre le navigateur. Ctrl+C pour arreter.

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1 -Background
    Demarre en tache de fond et rend la main.

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1 -Status
    Indique si l'Atelier tourne, sur quel port et avec quel PID.

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1 -Stop
    Arrete l'Atelier.

.NOTES
    Codes de retour : 0 = succes ; 1 = prerequis manquant (php absent) ; 2 = echec.
    Documentation : apps/atelier/README.md
    Aide          : Get-Help .\apps\atelier\atelier.ps1 -Full
#>
[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Status')][switch] $Status,
    [Parameter(ParameterSetName = 'Stop')]  [switch] $Stop,
    [Parameter(ParameterSetName = 'Start')] [switch] $Background,
    [Parameter(ParameterSetName = 'Start')] [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'

# apps/atelier -> apps -> racine du depot (c'est elle qui est servie).
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Config en deux couches (D33) : config/common.psd1 (racine, partage par les apps)
# puis la config de CETTE app, qui gagne. L'Atelier ne depend PAS de la bibliotheque
# du backend : une app de developpement qui s'appuie sur l'app livree, c'est la
# frontiere percee. Lire un fichier de config commun n'est pas une dependance a une app.
$cfg = @{}
$commonPath = Join-Path $repoRoot 'config/common.psd1'
if (Test-Path -LiteralPath $commonPath) {
    try { (Import-PowerShellDataFile -Path $commonPath).GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value } }
    catch { Write-Host ("config/common.psd1 illisible : " + $_.Exception.Message) -ForegroundColor Red; exit 1 }
}
$cfgPath = Join-Path $PSScriptRoot 'config/config.psd1'
if (-not (Test-Path -LiteralPath $cfgPath)) {
    Write-Host "Configuration introuvable : $cfgPath" -ForegroundColor Red
    exit 1
}
try { (Import-PowerShellDataFile -Path $cfgPath).GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value } }
catch { Write-Host ("config.psd1 illisible : " + $_.Exception.Message) -ForegroundColor Red; exit 1 }

$address = $cfg.BindAddress
$port    = $cfg.Port
$url     = 'http://{0}:{1}{2}' -f $address, $port, $cfg.StartPage

# Le port est-il en ecoute ? (test autonome : pas de dependance a common.ps1)
function Test-PortOpen {
    param([string]$Address, [int]$Port)
    try { $c = [System.Net.Sockets.TcpClient]::new(); $c.Connect($Address, $Port); $c.Close(); return $true }
    catch { return $false }
}

# Quel processus tient le port ? (aucun fichier de PID a gerer)
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
    if ($proc) { Write-Host ("Atelier EN LIGNE  - {0}  (PID {1}, {2})" -f $url, $proc.Id, $proc.ProcessName) }
    else       { Write-Host ("Atelier ARRETE    - port {0} libre" -f $port) }
    exit 0
}

# --- Arret -------------------------------------------------------------------
if ($Stop) {
    $proc = Get-AtelierProcess
    if (-not $proc) { Write-Host "Atelier deja arrete (rien a faire)."; exit 0 }
    try {
        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        Write-Host ("Atelier arrete (PID {0})." -f $proc.Id); exit 0
    } catch {
        Write-Host ("Impossible d'arreter le PID {0} : {1}" -f $proc.Id, $_.Exception.Message) -ForegroundColor Red
        exit 2
    }
}

# --- Prerequis ---------------------------------------------------------------
$php = (Get-Command php -ErrorAction SilentlyContinue).Source
if (-not $php) {
    Write-Host "php introuvable dans le PATH : l'Atelier utilise le serveur integre de PHP." -ForegroundColor Yellow
    Write-Host ("Repli sans serveur : ouvre directement " + (Join-Path $PSScriptRoot 'index.html'))
    Write-Host "  (les icones livrees et l'ecran de chargement ne s'y afficheront pas)"
    exit 1
}

# --- Idempotence : deja en ecoute ? ------------------------------------------
if (Get-AtelierProcess) {
    Write-Host ("Atelier deja en ligne : " + $url)
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

Write-Host ("Atelier (app de developpement) : " + $url)
Write-Host ("Racine servie                  : " + $repoRoot)

$phpArgs = @('-S', ("{0}:{1}" -f $address, $port), '-t', $repoRoot)

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
        if (Test-PortOpen -Address $address -Port $port) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not (Test-PortOpen -Address $address -Port $port)) {
        Write-Host "Le serveur n'a pas repondu dans le delai imparti." -ForegroundColor Red
        exit 2
    }
    Write-Host ("Demarre en tache de fond (PID {0}). Arret : atelier.ps1 -Stop" -f $proc.Id)
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
