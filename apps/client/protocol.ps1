# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    THE DOOR WINDOWS KNOCKS ON WHEN A NOTIFICATION IS CLICKED.

    A Windows notification does nothing on a click unless it names a target, and the only target Windows accepts from
    a script is a PROTOCOL. So Vigie declares "vigie://" for the account, and its notifications point at it. Clicking
    one lands here.

    This script opens nothing itself: it writes an ORDER in the account's run folder, the very mechanism the client
    app already reads every second (stop, restart). The app that owns the screen stays the one that opens windows,
    and a click while the app is restarting is simply honoured a second later.

    Called by Windows as: protocol.ps1 "vigie://session-recap"
#>
param([string]$Uri)

$clientRoot = $PSScriptRoot
$backend = Join-Path (Split-Path $clientRoot -Parent) 'backend-pode'
. (Join-Path $backend 'lib/common.ps1')

# WHAT IS ASKED, in one word: everything after the scheme, slashes and query stripped.
$what = "$Uri" -replace '^(?i)vigie:/*', ''
$what = ($what -split '[?#]')[0].Trim('/').ToLowerInvariant()
if (-not $what) { $what = 'panel' }

$runDir = Get-VarPath -Backend $clientRoot -Kind 'run'
$order = switch ($what) {
    'session-recap' { 'open-recap' }
    default         { 'open' }
}
try {
    Set-Content -LiteralPath (Join-Path $runDir $order) -Value "$Uri" -Encoding UTF8 -NoNewline
    Write-Log -Backend $clientRoot -Name 'client' -NoEcho -Message ("protocole recu : $Uri -> ordre $order")
} catch {
    Write-Log -Backend $clientRoot -Name 'client' -Level 'ERROR' -Message ("protocole refuse ($Uri) : " + $_.Exception.Message)
}
