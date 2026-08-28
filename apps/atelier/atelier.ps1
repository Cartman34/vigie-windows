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

    SECURITE : il sert la RACINE du depot (il lui faut des fichiers de plusieurs apps),
    mais router.php refuse var/, config/, les fichiers caches, .psd1, .log et .token.
    Sans ce routeur, le jeton de l'API de Vigie serait telechargeable en HTTP.
    Le script REFUSE de demarrer si router.php est absent.

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
# Ce fichier est isole : il charge lui-meme l'affichage commun, qui apporte aussi
# les libelles (console-ui.ps1 et i18n.ps1 sont voisins).
. (Join-Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'scripts/lib') 'console-ui.ps1')


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
    catch { Write-Fail (Get-Label 'atelier.config-common-psd1-illisible' $_.Exception.Message); exit 1 }
}
$cfgPath = Join-Path $PSScriptRoot 'config/config.psd1'
if (-not (Test-Path -LiteralPath $cfgPath)) {
    Write-Fail (Get-Label 'atelier.configuration-introuvable' $cfgPath)
    exit 1
}
try { (Import-PowerShellDataFile -Path $cfgPath).GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value } }
catch { Write-Fail (Get-Label 'atelier.config-psd1-illisible' $_.Exception.Message); exit 1 }

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
    if ($proc) { Write-Host (Get-Label 'atelier.atelier-en-ligne-pid' $url $proc.Id $proc.ProcessName) }
    else       { Write-Host (Get-Label 'atelier.atelier-arrete-port-libre' $port) }
    exit 0
}

# --- Arret -------------------------------------------------------------------
if ($Stop) {
    $proc = Get-AtelierProcess
    if (-not $proc) { Write-Host (Get-Label 'atelier.atelier-deja-arrete-rien'); exit 0 }
    try {
        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        Write-Host (Get-Label 'atelier.atelier-arrete-pid' $proc.Id); exit 0
    } catch {
        Write-Fail (Get-Label 'atelier.impossible-arreter-le-pid' $proc.Id $_.Exception.Message)
        exit 2
    }
}

# --- Prerequis ---------------------------------------------------------------
$php = (Get-Command php -ErrorAction SilentlyContinue).Source
if (-not $php) {
    Write-Warn (Get-Label 'atelier.php-introuvable-dans-le')
    Write-Info (Get-Label 'atelier.repli-sans-serveur-ouvre' (Join-Path $PSScriptRoot 'index.html'))
    Write-Info (Get-Label 'atelier.les-icones-livrees-et')
    exit 1
}

# --- Idempotence : deja en ecoute ? ------------------------------------------
if (Get-AtelierProcess) {
    Write-Info (Get-Label 'atelier.atelier-deja-en-ligne' $url)
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

Write-Info (Get-Label 'atelier.atelier-app-de-developpement' $url)
Write-Info (Get-Label 'atelier.racine-servie' $repoRoot)
# Le routeur FILTRE : l'Atelier sert la racine du depot, il exposerait sinon
# apps/<app>/var/secrets/api.token, le jeton de l'API de Vigie. Voir router.php.
$router  = Join-Path $PSScriptRoot 'router.php'
if (-not (Test-Path -LiteralPath $router)) {
    Write-Fail (Get-Label 'atelier.router-php-introuvable-refus')
    Write-Info (Get-Label 'atelier.attendu' $router)
    exit 1
}
$phpArgs = @('-S', ("{0}:{1}" -f $address, $port), '-t', $repoRoot, $router)

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
        Write-Fail (Get-Label 'atelier.le-serveur-pas-repondu')
        exit 2
    }
    Write-Info (Get-Label 'atelier.demarre-en-tache-de' $proc.Id)
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

# --- Premier plan : la console montre les requetes, Ctrl+C arrete -------------
Write-Info (Get-Label 'atelier.ctrl-pour-arreter')
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
