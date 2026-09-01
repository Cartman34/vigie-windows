# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Mesurer débit/latence | immediate | info   -- affiche quand un champ cite cette action (D66)
<#
    Action : mesure latence (ping) + débit descendant (~10 Mo) + débit montant (~5 Mo).
    Fusionne le resultat dans var/cache/netmeasure.json (preserve l'IP publique).
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$measFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'netmeasure.json'

$lat = '-'
try {
    $p = Test-Connection -TargetName '1.1.1.1' -Count 3 -ErrorAction Stop
    $avg = ($p | Measure-Object -Property Latency -Average).Average
    if ($avg) { $lat = [math]::Round($avg) }
} catch { }

$down = '-'
try {
    $url = 'https://speed.cloudflare.com/__down?bytes=10000000'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    $sw.Stop()
    $bytes = $resp.RawContentLength; if (-not $bytes -or $bytes -le 0) { $bytes = 10000000 }
    $sec = $sw.Elapsed.TotalSeconds
    if ($sec -gt 0) { $down = [math]::Round($bytes * 8 / $sec / 1e6, 1) }
} catch { }

$up = '-'
try {
    $upBytes = 5000000
    $body = New-Object byte[] $upBytes
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -Uri 'https://speed.cloudflare.com/__up' -Method Post -Body $body -UseBasicParsing -TimeoutSec 30 | Out-Null
    $sw2.Stop()
    $sec2 = $sw2.Elapsed.TotalSeconds
    if ($sec2 -gt 0) { $up = [math]::Round($upBytes * 8 / $sec2 / 1e6, 1) }
} catch { }

Update-StateJson -Path $measFile -Set @{ latencyMs = $lat; downMbps = $down; upMbps = $up; at = (Get-Date).ToUniversalTime().ToString('o') } | Out-Null
@{ message = "Latence : $lat ms  |  Descendant : $down Mbps  |  Montant : $up Mbps"; result = @{ ok = $true; invalidate = @('net.probe.ps1') } }
