<# Sonde : réseau (connectivite / type / nom (SSID) / IP LAN / IP publique / IPv6 / MAC / VPN + débit).
   Detection via System.Net.NetworkInformation (.NET pur, fiable dans le runspace Pode).
   Etat Wi-Fi et SSID via l'adaptateur + le profil reseau Windows (lisibles SANS privilege).
   netsh wlan n'apporte que la force du signal, en bonus : il exige le service de
   localisation et l'elevation, donc il echoue souvent et ne decide de rien.
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

# Profils reseau Windows : lus UNE seule fois. Ils servent a la connectivite ET au nom
# du reseau — pour une interface sans fil, le nom du profil EST le SSID.
$profiles = @()
try { $profiles = @(Get-NetConnectionProfile -ErrorAction Stop) } catch { }

$connected = (Test-InternetActive) -or [bool]($profiles |
    Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' })

$nics = @()
try {
    $nics = @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
              Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' })
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

# --- Etat Wi-Fi -------------------------------------------------------------------
# L'ancienne version confiait l'etat a « netsh wlan show interfaces ». Cette commande
# exige le service de localisation ET l'elevation ; quand elle echoue (cas courant :
# « WlanQueryInterface renvoie l'erreur 5 »), l'etat restait vide et le champ AFFIRMAIT
# « non connecté » alors que la machine etait associee a un reseau. On ne devine plus :
# l'etat vient de l'adaptateur (Get-NetAdapter, repli .NET) et le SSID du profil reseau,
# tous deux lisibles sans privilege. netsh ne sert plus qu'au bonus « force du signal ».
$wifiAdapter = $null
try {
    $wifiAdapter = Get-NetAdapter -Physical -ErrorAction Stop |
                   Where-Object { "$($_.PhysicalMediaType)" -match '802\.11' } | Select-Object -First 1
} catch { }

# Interface .NET correspondante : c'est elle qui porte adresses et passerelle. Le repli
# ecarte les pseudo-adaptateurs (pilotes de filtrage, Wi-Fi Direct) : eux n'ont jamais
# de passerelle.
$wifiNic = $null
try {
    if ($wifiAdapter) { $wifiNic = $nics | Where-Object { $_.Name -eq $wifiAdapter.Name } | Select-Object -First 1 }
    if (-not $wifiNic) {
        $wifiNic = $nics | Where-Object {
            "$($_.NetworkInterfaceType)" -eq 'Wireless80211' -and $_.GetIPProperties().GatewayAddresses.Count -gt 0
        } | Select-Object -First 1
    }
} catch { }
$hasWifi = [bool]($wifiAdapter -or $wifiNic)

$wifiAlias = if ($wifiAdapter) { "$($wifiAdapter.Name)" } elseif ($wifiNic) { "$($wifiNic.Name)" } else { '' }
$wifiProfile = if ($wifiAlias) { $profiles | Where-Object { $_.InterfaceAlias -eq $wifiAlias } | Select-Object -First 1 } else { $null }
$ssid = if ($wifiProfile) { "$($wifiProfile.Name)" } else { '' }

# Get-NetAdapter distingue « pas associe » de « desactive » et de « absent ». Sans lui,
# on ne sait dire que « le lien est actif », et seulement si l'interface remonte.
$wifiUp = $false; $wifiState = 'état inconnu'
if ($wifiAdapter) {
    switch ("$($wifiAdapter.Status)") {
        'Up'           { $wifiUp = $true; $wifiState = 'Connecté' }
        'Disconnected' { $wifiState = 'Non connecté' }
        'Disabled'     { $wifiState = 'Adaptateur désactivé' }
        'Not Present'  { $wifiState = 'Adaptateur absent' }
        default        { $wifiState = "$($wifiAdapter.Status)" }
    }
} elseif ($wifiNic) { $wifiUp = $true; $wifiState = 'Connecté' }

# Bonus : la force du signal radio n'existe que dans netsh. Son echec est previsible et
# ne doit rien changer a l'etat affiche ; on retient seulement qu'elle est indisponible.
$signal = ''; $signalReadable = $false
if ($wifiUp) {
    try {
        $w = Invoke-Native -File 'netsh.exe' -Arguments @('wlan','show','interfaces')
        if ($w.Ok) {
            $signalReadable = $true
            foreach ($line in ($w.Output -split "`r?`n")) {
                if ($line -match 'BSSID') { continue }
                if     ($line -match '^\s*Signal\s*:\s*(.+?)\s*$')            { $signal = $Matches[1] }
                elseif (-not $ssid -and $line -match '^\s*SSID\s*:\s*(.+?)\s*$') { $ssid = $Matches[1] }
            }
        }
    } catch { }
}
$linkSpeed = if ($wifiAdapter -and $wifiAdapter.LinkSpeed) { "$($wifiAdapter.LinkSpeed)" } else { '' }

$wifiText = if (-not $wifiUp)      { $wifiState }
            elseif ($ssid -and $signal) { "Connecté à $ssid ($signal)" }
            elseif ($ssid)         { "Connecté à $ssid" }
            elseif ($signal)       { "Connecté ($signal)" }
            else                   { 'Connecté' }

# Un Wi-Fi eteint n'est pas un probleme en soi (cable Ethernet branche, mode Avion
# voulu) : c'est la ligne « Connexion Internet » qui porte l'alerte. On reste neutre
# tant qu'Internet repond par ailleurs.
$wifiStatus = if ($wifiUp) { 'ok' } elseif (-not $connected) { 'warn' } else { 'neutral' }

$wifiGuide = if ($wifiUp) {
    "Ce que c'est : l'état de l'association entre l'adaptateur Wi-Fi de ce PC et un réseau sans fil." +
    $(if ($ssid) { " Ici : associé au réseau « $ssid »." } else { " Ici : associé à un réseau." }) +
    $(if ($linkSpeed) { " Débit négocié du lien radio : $linkSpeed." } else { '' }) + "`n`n" +
    "Le problème : aucun. Le lien radio est établi.`n`n" +
    $(if ($signal) {
        "Force du signal : $signal. En dessous de 50 %, rapprochez-vous du point d'accès ou changez de bande (5 GHz plus rapide, 2,4 GHz plus lointaine)."
    } elseif ($signalReadable) {
        "La force du signal n'a pas été renvoyée par Windows pour cet adaptateur ; cela n'affecte pas la connexion."
    } else {
        "La force du signal n'est pas affichée : elle ne se lit que via « netsh wlan », qui exige le service de localisation de Windows (et des droits administrateur). Pour l'obtenir : Paramètres > Confidentialité et sécurité > Localisation, puis autoriser les applications de bureau. Ce refus n'a aucun effet sur la connexion elle-même."
    })
} else {
    "Ce que c'est : l'état de l'association entre l'adaptateur Wi-Fi de ce PC et un réseau sans fil. Ici : $wifiState.`n`n" +
    "Le problème : aucun réseau sans fil n'est associé à cet adaptateur." +
    $(if ($connected) { " L'accès à Internet passe par une autre interface ($connType), donc rien n'est bloqué pour l'instant." }
      else { " Et aucune autre interface ne fournit d'accès à Internet : la machine est hors ligne." }) + "`n`n" +
    "Les issues possibles :`n" +
    "- le Wi-Fi est coupé : mode Avion, interrupteur physique ou touche Fn du clavier ;`n" +
    "- la connexion a été perdue : rouvrez la liste des réseaux (Paramètres > Réseau et Internet > Wi-Fi) et reconnectez-vous ;`n" +
    "- la box ou le point d'accès n'émet plus : vérifiez-le depuis un autre appareil ;`n" +
    "- l'adaptateur est désactivé : réactivez-le (Paramètres > Réseau et Internet > Paramètres réseau avancés) ;`n" +
    "- l'adaptateur est absent : le pilote n'est pas chargé, regardez le Gestionnaire de périphériques."
}

# Nom du reseau : le profil Windows de l'interface principale — pour du Wi-Fi, c'est le
# SSID. Une seule source, celle qui reste lisible sans autorisation de localisation.
$primaryProfile = $null
if ($primary) { $primaryProfile = $profiles | Where-Object { $_.InterfaceAlias -eq $primary.Name } | Select-Object -First 1 }
$netName = if ($primaryProfile) { "$($primaryProfile.Name)" }
           elseif ($ssid -and $connType -eq 'Wi-Fi') { $ssid }
           elseif ($primary) { $primary.Name }
           else { '-' }

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
    $fields += New-Field -Key 'wifi' -Label 'État Wi-Fi' -Value $wifiText -Kind 'text' -Status $wifiStatus `
        -Help "État de l'adaptateur Wi-Fi : réseau associé, et force du signal quand Windows en autorise la lecture." `
        -Guide $wifiGuide
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
