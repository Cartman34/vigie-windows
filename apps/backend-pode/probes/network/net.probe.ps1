<# Sonde : réseau (connectivite / type / nom (SSID) / IP LAN / IP publique / IPv6 / MAC / VPN + débit).
   Detection via System.Net.NetworkInformation (.NET pur, fiable dans le runspace Pode).
   SSID / etat Wi-Fi via netsh (Invoke-Native : sortie + code de retour traites).
   IP publique a la demande (action net-publicip). LECTURE SEULE. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

function Test-InternetActive {
    param([string[]]$Hosts = @('1.1.1.1','8.8.8.8','9.9.9.9'), [int]$Port = 443, [int]$TimeoutMs = 1200)
    foreach ($h in $Hosts) {
        $c = $null
        try {
            $c = [System.Net.Sockets.TcpClient]::new()
            $iar = $c.BeginConnect($h, $Port, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                try { $c.EndConnect($iar); if ($c.Connected) { return $true } } catch { }
            }
        } catch { }
        finally { if ($c) { try { $c.Close() } catch { } } }
    }
    return $false
}
function Format-Mac {
    param($Nic)
    try {
        $raw = $Nic.GetPhysicalAddress().ToString()
        if ($raw -and $raw.Length -ge 12) { return ($raw -replace '(..)(?!$)', '$1-') }
    } catch { }
    return '-'
}

$connected = (Test-InternetActive) -or [bool](Get-NetConnectionProfile -ErrorAction SilentlyContinue |
    Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' })

$nics = @()
try {
    $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' }
} catch { }

$primary = $null
foreach ($n in $nics) {
    try {
        $gw = $n.GetIPProperties().GatewayAddresses
        if ($gw -and ($gw | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' })) { $primary = $n; break }
    } catch { }
}
if (-not $primary) {
    foreach ($n in $nics) {
        try { if ($n.GetIPProperties().GatewayAddresses.Count -gt 0) { $primary = $n; break } } catch { }
    }
}

$connType = '-'
if ($primary) {
    switch ("$($primary.NetworkInterfaceType)") {
        'Wireless80211'   { $connType = 'Wi-Fi' }
        'Ethernet'        { $connType = 'Ethernet' }
        'GigabitEthernet' { $connType = 'Ethernet' }
        default           { $connType = "$($primary.NetworkInterfaceType)" }
    }
}

$ip = '-'; $ip6 = '-'; $mac = '-'
if ($primary) {
    try {
        $props = $primary.GetIPProperties()
        $ipv4 = $props.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -notmatch '^169\.254\.' } | Select-Object -First 1
        if ($ipv4) { $ip = $ipv4.Address.ToString() }
        $ipv6a = $props.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetworkV6' -and -not $_.Address.IsIPv6LinkLocal } | Select-Object -First 1
        if ($ipv6a) { $ip6 = $ipv6a.Address.ToString() }
    } catch { }
    $mac = Format-Mac $primary
}

$hasWifi = [bool]($nics | Where-Object { "$($_.NetworkInterfaceType)" -eq 'Wireless80211' })
$ssid = ''; $wifiState = ''; $signal = ''
if ($hasWifi) {
    try {
        $w = Invoke-Native -File 'netsh.exe' -Arguments @('wlan','show','interfaces')
        if ($w.Ok) {
            foreach ($line in ($w.Output -split "`r?`n")) {
                if ($line -match 'BSSID') { continue }
                if     ($line -match '^\s*SSID\s*:\s*(.+?)\s*$')                { $ssid = $Matches[1] }
                elseif ($line -match '^\s*(?:État|Etat|State)\s*:\s*(.+?)\s*$') { $wifiState = $Matches[1] }
                elseif ($line -match '^\s*Signal\s*:\s*(.+?)\s*$')             { $signal = $Matches[1] }
            }
        }
    } catch { }
}
$netName = if ($ssid) { $ssid } elseif ($primary) { $primary.Name } else { '-' }
$wifiText = if ($wifiState) { if ($signal) { "$wifiState ($signal)" } else { $wifiState } } else { 'non connecté' }

$adapterLines = @()
$adapterRows  = @()
foreach ($n in $nics) {
    try {
        $ips = @($n.GetIPProperties().UnicastAddresses |
                 Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -notmatch '^169\.254\.' } |
                 ForEach-Object { $_.Address.ToString() })
        $ipTxt = if ($ips.Count) { $ips -join ', ' } else { '-' }
        $adapterLines += ("{0} [{1}] : IPv4 {2} | MAC {3}" -f $n.Name, $n.NetworkInterfaceType, $ipTxt, (Format-Mac $n))
        # Meme information, en COLONNES : c'est cette forme que l'interface affiche.
        $adapterRows  += ,@("$($n.Name)", "$($n.NetworkInterfaceType)", $ipTxt, (Format-Mac $n))
    } catch { }
}
$adapterDetail = if ($adapterLines.Count) { "Interfaces actives :`n- " + ($adapterLines -join "`n- ") } else { "Aucune interface active détectée." }

$vpn = [bool]($nics | Where-Object { $_.Description -match 'VPN|WireGuard|OpenVPN|AnyConnect|Tailscale|ZeroTier|TAP' })

$lat = '-'; $down = '-'; $up = '-'; $measAt = $null; $pubIp = '-'; $pubAt = $null
$measFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'netmeasure.json'
if (Test-Path $measFile) {
    try {
        $m = Get-Content $measFile -Raw | ConvertFrom-Json
        if ($null -ne $m.latencyMs) { $lat = "$($m.latencyMs)" }
        if ($null -ne $m.downMbps)  { $down = "$($m.downMbps)" }
        if ($null -ne $m.upMbps)    { $up   = "$($m.upMbps)" }
        $measAt = $m.at
        if ($m.publicIp)   { $pubIp = "$($m.publicIp)" }
        if ($m.publicIpAt) { $pubAt = $m.publicIpAt }
    } catch { }
}
$latSt = if ($lat -eq '-') { 'neutral' } elseif ([double]($lat) -lt 80) { 'ok' } elseif ([double]($lat) -lt 200) { 'warn' } else { 'error' }
$pubGuide = if ($pubAt) { "Dernière récupération : $pubAt. Cliquez « Obtenir l'IP publique » pour actualiser." } else { "Non récupérée. Cliquez « Obtenir l'IP publique » (appel à un service externe)." }

$fields = @(
    New-Field -Key 'connected' -Label 'Connexion Internet' -Value $connected -Kind 'bool' -Status $(if ($connected) {'ok'} else {'warn'}) `
        -Help "Connectivité vérifiée par une connexion TCP réelle (1.1.1.1 / 8.8.8.8), avec repli sur l'indicateur Windows." -Guide "Si « Non » : vérifiez wifi/câble, box/routeur."
    New-Field -Key 'connType' -Label 'Type de connexion' -Value $connType -Kind 'text' -Status 'neutral' -Help "Type de l'interface active portant la route par défaut (Wi-Fi ou Ethernet)."
    New-Field -Key 'netName'  -Label 'Réseau (nom)' -Value $netName -Kind 'text' -Status 'neutral' -Help "Nom du réseau : SSID en Wi-Fi, sinon nom de l'interface."
)
if ($hasWifi) {
    $fields += New-Field -Key 'wifi' -Label 'État Wi-Fi' -Value $wifiText -Kind 'text' -Status $(if ($wifiState -match 'connect') {'ok'} else {'neutral'}) -Help "État de l'adaptateur Wi-Fi (connecté + force du signal)."
}
$fields += @(
    New-Field -Key 'ip'  -Label 'IP locale (LAN)' -Value $ip  -Kind 'text' -Status 'neutral' -Help "Adresse IPv4 privée de l'interface portant la route par défaut (réseau local)."
    New-Field -Key 'publicIp' -Label 'IP publique' -Value $pubIp -Kind 'text' -Status 'neutral' -Help "Adresse IP publique vue depuis Internet (récupérée à la demande)." -Guide $pubGuide
    New-Field -Key 'ip6' -Label 'Adresse IPv6' -Value $ip6 -Kind 'text' -Status 'neutral' -Help "Adresse IPv6 principale (interface par défaut). « - » si non attribuée."
    New-Field -Key 'mac' -Label 'Adresse MAC'  -Value $mac -Kind 'text' -Status 'neutral' `
        -Help "Adresse MAC de l'interface principale. Cliquez pour voir toutes les interfaces actives." `
        -Table @{ columns = @('Interface', 'Type', 'IPv4', 'MAC'); rows = $adapterRows }
    New-Field -Key 'vpn' -Label 'VPN actif'    -Value $vpn -Kind 'bool' -Status 'neutral' -Help "Un adaptateur VPN est actuellement actif."
    New-Field -Key 'latency' -Label 'Latence'  -Value $(if ($lat -eq '-') {'non mesuré'} else {"$lat ms"}) -Kind 'text' -Status $latSt -Help "Latence mesurée (ping). Cliquez 'Mesurer' pour actualiser." -FixAction 'net-speedtest'
    New-Field -Key 'down'    -Label 'Débit descendant' -Value $(if ($down -eq '-') {'non mesuré'} else {"$down Mbps"}) -Kind 'text' -Status 'neutral' -Help "Débit descendant estimé. Cliquez 'Mesurer' pour actualiser."
    New-Field -Key 'up'      -Label 'Débit montant' -Value $(if ($up -eq '-') {'non mesuré'} else {"$up Mbps"}) -Kind 'text' -Status 'neutral' -Help "Débit montant estimé (upload ~5 Mo). Cliquez 'Mesurer débit/latence'."
)
if ($measAt) {
    $fields += New-Field -Key 'measAt' -Label 'Mesure du' -Value $measAt -Kind 'date' -Status 'neutral' -Help "Date de la dernière mesure débit/latence."
}
New-ModuleObject -Id 'net' -Theme 'network' -Label 'Réseau' -Status $(if ($connected) {'ok'} else {'warn'}) -Fields $fields -Actions @(
    New-Action -Id 'net-publicip'  -Label "Obtenir l'IP publique" -Kind 'immediate' -Help "Interroge un service externe (api.ipify.org...) pour connaître l'adresse IP publique. Un appel sortant est effectué."
    New-Action -Id 'net-speedtest' -Label 'Mesurer débit/latence'  -Kind 'immediate' -Help "Mesure la latence (ping) et le débit descendant en téléchargeant ~10 Mo. Prend quelques secondes et consomme un peu de data."
)
