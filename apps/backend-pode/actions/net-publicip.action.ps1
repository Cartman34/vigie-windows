<# Action net-publicip : recupere l'IP publique via un service externe (a la demande).
   Fusionne le resultat dans var/cache/netmeasure.json via Update-StateJson (preserve latence/debit). #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$measFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'netmeasure.json'

$services = @('https://api.ipify.org','https://ifconfig.me/ip','https://icanhazip.com','https://checkip.amazonaws.com')
$pub = $null
foreach ($u in $services) {
    try {
        $resp = Invoke-RestMethod -Uri $u -TimeoutSec 5 -ErrorAction Stop
        $t = ("$resp").Trim()
        if ($t -match '^[0-9A-Fa-f:.]+$') { $pub = $t; break }
    } catch { }
}

$inv = @('net.probe.ps1')
if ($pub) {
    Update-StateJson -Path $measFile -Set @{ publicIp = $pub; publicIpAt = (Get-Date).ToString('s') } | Out-Null
    @{ message = "IP publique : $pub"; result = @{ ok = $true; invalidate = $inv } }
} else {
    @{ message = "Impossible de récupérer l'IP publique (aucun service joignable, ou pas d'accès Internet sortant)."; result = @{ ok = $false; invalidate = $inv } }
}
