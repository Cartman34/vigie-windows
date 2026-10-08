# @author Florent HAZARD <f.hazard@sowapps.com>
<#
.SYNOPSIS
    The Atelier: Vigie's development app. It serves the repository locally and opens the page.

.DESCRIPTION
    Intent: give the developer a page served over http, so that the panel's own screens can be looked at and
    adjusted without running Vigie itself.
    Usage: it starts a small local web server (PHP's built-in one) at the root of the repository, then opens
    apps/atelier/index.html in the browser.

    THE ATELIER IS NOT VIGIE. It is a DISTINCT app, for development:
      - Vigie   : apps/backend-pode + apps/frontend-web + apps/client, PowerShell plus Pode, port 47600,
                  ELEVATED, started by the scheduled task at logon.
      - Atelier : this app, PHP, port 47610, NEVER elevated, started by hand.
    The Atelier exposes no API, runs no probe and has access to no secret. It must not run on an end user's
    machine.

    SECURITY: it serves the ROOT of the repository (it needs files from several apps), but router.php refuses
    var/, config/, the hidden files, .psd1, .log and .token. Without that router, Vigie's API token would be
    downloadable over HTTP. The script REFUSES to start if router.php is missing.

    WHY a server rather than a double click: opened through file://, the page cannot read the assets (the relative
    paths break as soon as the file is moved or copied) and the browser refuses to show the loading screen inside
    a frame. Served over http, it works entirely.

    CONFIGURATION: apps/atelier/config/config.psd1 -- the config of THIS app. It does not read the server app's:
    each app is master of its own values.

.PARAMETER Status
    Displays the state only (online or not, the port, the PID) and exits. It starts nothing.

.PARAMETER Stop
    Stops the Atelier if it is running. No effect if it is already stopped.

.PARAMETER Background
    Starts the server in the background and hands control back at once, instead of holding the console until
    Ctrl+C.

.PARAMETER NoBrowser
    Do not open the browser (useful when a tab is already open).

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1
    Starts the Atelier and opens the browser. Ctrl+C to stop.

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1 -Background
    Starts it in the background and hands control back.

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1 -Status
    Says whether the Atelier is running, on which port and with which PID.

.EXAMPLE
    pwsh -File .\apps\atelier\atelier.ps1 -Stop
    Stops the Atelier.

.NOTES
    Exit codes: 0 = success; 1 = a missing prerequisite (php absent); 2 = failure.
    Documentation: apps/atelier/README.md
    Help         : Get-Help .\apps\atelier\atelier.ps1 -Full
#>
[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Status')][switch] $Status,
    [Parameter(ParameterSetName = 'Stop')]  [switch] $Stop,
    [Parameter(ParameterSetName = 'Start')] [switch] $Background,
    [Parameter(ParameterSetName = 'Start')] [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'
# This file is isolated: it loads the common display itself, which also brings the labels (console-ui.ps1 and
# i18n.ps1 are its neighbours).
. (Join-Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'scripts/lib') 'console-ui.ps1')


# apps/atelier -> apps -> the root of the repository (which is what is served).
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# The config in two layers (D33): config/common.psd1 (at the root, shared by the apps) then THIS app's config,
# which wins. The Atelier does NOT depend on the server app's library: a development app leaning on the delivered
# app is the boundary breached. Reading a shared config file is not a dependency on an app.
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

# Is the port listening? (a self-contained test: no dependency on common.ps1)
function Test-PortOpen {
    param([string]$Address, [int]$Port)
    try { $c = [System.Net.Sockets.TcpClient]::new(); $c.Connect($Address, $Port); $c.Close(); return $true }
    catch { return $false }
}

# Which process holds the port? (no PID file to manage)
# WHO LISTENS IS ASKED OF WINDOWS DIRECTLY (scripts/lib/tcp-ports.ps1, standalone like this script): through WMI it took
# 26 seconds on 14/09.
. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) (Join-Path 'scripts' (Join-Path 'lib' 'tcp-ports.ps1')))
function Get-AtelierProcess {
    $conn = Get-PortListener -Port $port
    if ($conn) { return Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue }
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

# --- Idempotence: is it already listening? ------------------------------------
if (Get-AtelierProcess) {
    Write-Info (Get-Label 'atelier.atelier-deja-en-ligne' $url)
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

Write-Info (Get-Label 'atelier.atelier-app-de-developpement' $url)
Write-Info (Get-Label 'atelier.racine-servie' $repoRoot)
# The router FILTERS: the Atelier serves the root of the repository, so it would otherwise expose
# apps/<app>/var/secrets/api.token, Vigie's API token. See router.php.
$router  = Join-Path $PSScriptRoot 'router.php'
if (-not (Test-Path -LiteralPath $router)) {
    Write-Fail (Get-Label 'atelier.router-php-introuvable-refus')
    Write-Info (Get-Label 'atelier.attendu' $router)
    exit 1
}
$phpArgs = @('-S', ("{0}:{1}" -f $address, $port), '-t', $repoRoot, $router)

# --- In the background --------------------------------------------------------
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

# --- In the foreground: the console shows the requests, Ctrl+C stops ----------
Write-Info (Get-Label 'atelier.ctrl-pour-arreter')
if (-not $NoBrowser) {
    # The browser is started after a delay: the server must be listening first.
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
