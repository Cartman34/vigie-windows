# @author Florent HAZARD <f.hazard@sowapps.com>
<# A probe: the NETWORK (connection / name (SSID) / quality of the Wi-Fi link / LAN IP / public IP / IPv6 / MAC /
   VPN + throughput).

   Intent: say whether this machine is really on the network and how well, with nothing invented -- a figure that
   cannot be measured without elevation or without the location service is not displayed at all.
   Usage: it is run by the scheduler like any probe. Detection goes through System.Net.NetworkInformation (pure
   .NET, reliable inside the Pode runspace). The Wi-Fi state and quality come from the adapter plus the Windows
   network profile: both readable WITHOUT a privilege and WITHOUT the location service, unlike netsh wlan. Its
   only write: a short history of link rates in var/cache/netwifi.json (through Update-StateJson), to deduce a
   STABILITY -- a single reading says nothing of one. The public IP is fetched on demand (the net-publicip
   action). Nothing else is changed. #>
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

# The Windows network profiles: read ONCE only. They serve both for connectivity and for the network name -- for a
# wireless interface, the profile name IS the SSID.
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
# The old version entrusted the state to netsh wlan show interfaces. That command demands the location service AND
# elevation; when it fails (the common case: WlanQueryInterface returning error 5), the state stayed empty and the
# field ASSERTED not connected while the machine was associated with a network. We no longer guess: the state
# comes from the adapter (Get-NetAdapter, with a .NET fallback) and the SSID from the network profile, both
# readable without a privilege. netsh now serves only for the bonus signal strength.
$wifiAdapter = $null
try {
    $wifiAdapter = Get-NetAdapter -Physical -ErrorAction Stop |
                   Where-Object { "$($_.PhysicalMediaType)" -match '802\.11' } | Select-Object -First 1
} catch { }

# The matching .NET interface: it is the one carrying the addresses and the gateway. The fallback sets aside the
# pseudo-adapters (filter drivers, Wi-Fi Direct): those never have a gateway.
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

# Get-NetAdapter tells not associated from disabled and from absent. Without it, all one can say is that the link
# is up, and only if the interface reports at all.
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

# --- The quality and stability of the Wi-Fi link ------------------------------
# WHAT IS REALLY MEASURABLE HERE (checked by running it on the machine):
#   - the NEGOTIATED rate of the radio link: Get-NetAdapter, ReceiveLinkSpeed and TransmitLinkSpeed. The card
#     drops its modulation as soon as reception degrades: so that rate is a direct indicator of the quality of
#     the link, and it moves continuously (measured: 39 -> 78 Mb/s in ten seconds). Cost: ~80 ms.
#   - the state of the media, to tell a cut from a mere drop.
# WHAT IS NOT MEASURABLE HERE (tried, and negative):
#   - netsh wlan show interfaces: error 5, demands the location service AND elevation. That is what made it
#     display not connected wrongly.
#   - the WMI class MSNdis_80211_ReceivedSignalStrength under the wmi root: this card driver answers not
#     supported.
#   - the network performance counters: their names are translated, so they are not portable.
# The accepted consequence: NO signal strength in % or in dBm is displayed. A wrong figure would be worse than no
# figure -- and the field says so explicitly.
$rxBps = 0L; $txBps = 0L
if ($wifiAdapter) {
    try { $rxBps = [long]$wifiAdapter.ReceiveLinkSpeed } catch { }
    try { $txBps = [long]$wifiAdapter.TransmitLinkSpeed } catch { }
}
# We keep the FASTER of the two directions, not the slower. The reason: the card only keeps a high modulation in
# the direction where traffic flows; the idle direction falls very low. Taking the minimum means measuring
# idleness, not quality -- checked here: transmission at 24 Mb/s while reception held 78 Mb/s, with nothing having
# moved.
$linkBps = [Math]::Max($rxBps, $txBps)
$linkMbps = if ($linkBps -gt 0) { [int][Math]::Round($linkBps / 1e6) } else { 0 }
$rxMbps   = if ($rxBps  -gt 0) { [int][Math]::Round($rxBps  / 1e6) } else { 0 }
$txMbps   = if ($txBps  -gt 0) { [int][Math]::Round($txBps  / 1e6) } else { 0 }

# A short history, to deduce a STABILITY: one single reading says nothing of a variation. The probe has a TTL of
# 15 s, so it passes often enough to accumulate. Writing goes through Update-StateJson: that is the only code
# allowed to write inside var/cache.
$wifiHistFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'netwifi.json'
$nowT = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$samples = @(); $best = 0L
if ($hasWifi) {
    $hist = $null
    if (Test-Path $wifiHistFile) { try { $hist = Get-Content $wifiHistFile -Raw | ConvertFrom-Json } catch { } }
    # Changing network resets the counter: the best rate of one SSID says nothing of another, and comparing the
    # two would manufacture a false degradation.
    if ($hist -and "$($hist.ssid)" -eq $ssid) {
        try { $best = [long]$hist.best } catch { }
        try {
            $samples = @(@($hist.samples) | Where-Object { $null -ne $_ -and $null -ne $_.t } |
                         ForEach-Object { @{ t = [long]$_.t; bps = [long]$_.bps; up = [int]$_.up } })
        } catch { $samples = @() }
    }
    # A sliding window: 30 minutes, 24 readings at most. Beyond that we would be describing a past state (another
    # room, another band) and not the present one.
    $samples = @($samples | Where-Object { ($nowT - $_.t) -le 1800 })
    $samples += ,@{ t = $nowT; bps = $linkBps; up = [int][bool]$wifiUp }
    if ($samples.Count -gt 24) { $samples = @($samples[($samples.Count - 24)..($samples.Count - 1)]) }
    if ($linkBps -gt $best) { $best = $linkBps }
    try { Update-StateJson -Path $wifiHistFile -Set @{ ssid = $ssid; best = $best; samples = $samples } | Out-Null } catch { }
}
$rates      = @($samples | Where-Object { $_.up -eq 1 -and $_.bps -gt 0 } | ForEach-Object { [double]$_.bps })
$dropCount  = @($samples | Where-Object { $_.up -ne 1 }).Count
$sampleCount = $samples.Count
$spanSec    = if ($sampleCount -ge 2) { $samples[$sampleCount - 1].t - $samples[0].t } else { 0 }

# We judge on the PEAK of the window, not on the instant nor on the average. A Wi-Fi card only raises its
# modulation when it has traffic to pass: at rest the negotiated rate collapses without the link having degraded
# (measured here: 6 Mb/s at rest, 116 Mb/s a few seconds earlier). The highest rate reached recently is therefore
# the only figure that says what the radio CAN do -- and poor reception does indeed cap that peak.
$peak = if ($rates.Count) { ($rates | Measure-Object -Maximum).Maximum } else { 0 }
$peakMbps = if ($peak -gt 0) { [int][Math]::Round($peak / 1e6) } else { 0 }

# Quality. Two complementary judgements, and we keep the WORSE: that is the one the user suffers. The absolute one
# says what the link can carry; the relative one compares with the best already obtained on THIS network, and so
# detects a degradation even on an intrinsically slow link. The relative one only comes into play with enough
# readings: without an established reference, a first reading taken as the maximum would be a false all-clear.
$qualRank = 0   # 0 = inconnue, 1 = bonne, 2 = moyenne, 3 = faible
if ($wifiUp -and $peak -gt 0) {
    $qualRank = if ($peakMbps -ge 100) { 1 } elseif ($peakMbps -ge 30) { 2 } else { 3 }
    if ($rates.Count -ge 4 -and $best -gt 0) {
        $ratio = $peak / $best
        $rel = if ($ratio -ge 0.70) { 1 } elseif ($ratio -ge 0.40) { 2 } else { 3 }
        if ($rel -gt $qualRank) { $qualRank = $rel }
    }
}
$qualLabel  = @('', 'Bonne', 'Moyenne', 'Faible')[$qualRank]
$qualStatus = @('neutral', 'ok', 'warn', 'error')[$qualRank]

# Stability: ONLY the continuity of the association. We first tried the dispersion of the rates -- to be thrown
# away: at rest it reaches 94 % on a perfectly healthy link, it measures traffic and not quality. A dropout, on
# the other hand, needs no interpretation. The window must also cover a real duration: four readings in five
# seconds prove nothing about how a link holds.
# Stability is a FIELD in its own right, distinct from quality: each carries its own status and its own guide. Not
# established yet = warn with an explanation, never an empty field.
$stabEstablished = ($sampleCount -ge 4 -and $spanSec -ge 120)
$spanMin = [int][Math]::Round($spanSec / 60)
# A measurement that is NOT MADE YET is not an alert: it is a wait. So it stays neutral -- alerting without a
# cause wears attention out, and there is nothing to resolve (an alert must always be able to offer a button,
# D66).
$stabLabel = ''; $stabStatus = 'neutral'
if ($stabEstablished) {
    if ($dropCount -eq 0) {
        $stabLabel = 'Aucune coupure'; $stabStatus = 'ok'
    } elseif ($dropCount -eq 1) {
        $stabLabel = "1 coupure sur les $spanMin dernières minutes"; $stabStatus = 'warn'
    } else {
        $stabLabel = "$dropCount coupures sur les $spanMin dernières minutes"; $stabStatus = 'warn'
    }
} else {
    $stabLabel = "Pas encore établie ($sampleCount relevé$(if ($sampleCount -gt 1) {'s'}) sur 4)"
}

$wifiText = if (-not $wifiUp)        { $wifiState }
            elseif ($peak -le 0)     { 'Connecté, qualité non mesurable' }
            else                     { "$qualLabel ($peakMbps Mb/s)" }

# A Wi-Fi that is switched off is not a problem in itself (an Ethernet cable is plugged in, Airplane mode is
# wanted): it is the Connection line that carries the alert. We stay neutral as long as the Internet answers by
# another road.
if (-not $wifiUp) { $qualStatus = if ($connected) { 'neutral' } else { 'warn' } }

# What Windows does NOT let us read here. Said once, in the guide, rather than an invented indicator: that is the
# only honest way of handling a missing measurement.
$noSignalNote = "À noter : la force du signal (en %) n'est pas lisible sur ce PC. « netsh wlan » la refuse sans le service de localisation ni droits administrateur, et le pilote de cette carte ne publie pas la classe WMI correspondante. Vigie s'appuie donc sur le débit négocié, qui se lit sans privilège, plutôt que d'afficher un chiffre inventé."

$wifiGuide = if (-not $wifiUp) {
    "Ce que c'est : la qualité du lien radio entre ce PC et un point d'accès Wi-Fi. Ici : $wifiState.`n`n" +
    "Le problème : aucun réseau sans fil n'est associé à cet adaptateur." +
    $(if ($connected) { " L'accès à Internet passe par une autre interface ($connType), donc rien n'est bloqué pour l'instant." }
      else { " Et aucune autre interface ne fournit d'accès à Internet : la machine est hors ligne." }) + "`n`n" +
    "Les issues possibles :`n" +
    "- le Wi-Fi est coupé : mode Avion, interrupteur physique ou touche Fn du clavier ;`n" +
    "- la connexion a été perdue : rouvrez la liste des réseaux (Paramètres > Réseau et Internet > Wi-Fi) et reconnectez-vous ;`n" +
    "- la box ou le point d'accès n'émet plus : vérifiez-le depuis un autre appareil ;`n" +
    "- l'adaptateur est désactivé : réactivez-le (Paramètres > Réseau et Internet > Paramètres réseau avancés) ;`n" +
    "- l'adaptateur est absent : le pilote n'est pas chargé, regardez le Gestionnaire de périphériques."
} elseif ($peak -le 0) {
    "Ce que c'est : la qualité du lien radio entre ce PC et le point d'accès. Ici : le lien est établi, mais Windows ne publie aucun débit de liaison pour cet adaptateur.`n`n" +
    "Le problème : la qualité ne peut pas être évaluée. Ce n'est pas une panne du réseau — la connexion fonctionne.`n`n" +
    "Les issues possibles :`n" +
    "- le pilote de la carte ne remonte pas cette information : une mise à jour du pilote (site du fabricant) la rétablit en général ;`n" +
    "- en attendant, jugez la connexion sur la latence et le débit mesurés plus bas dans cette carte.`n`n" +
    $noSignalNote
} else {
    "Ce que c'est : la qualité du lien radio entre ce PC et le point d'accès, jugée sur le meilleur débit que la liaison a négocié au cours des 30 dernières minutes. Une mauvaise réception plafonne ce sommet ; c'est donc lui qui mesure la qualité, et non le débit de l'instant — au repos, la carte laisse retomber sa modulation faute de trafic à passer.`n`n" +
    "Retenu pour le jugement : $peakMbps Mb/s, le plus haut des $($rates.Count) relevé(s) de la fenêtre.`n" +
    "Relevé à l'instant : $linkMbps Mb/s (réception $rxMbps Mb/s, émission $txMbps Mb/s) — bas au repos, c'est normal." +
    $(if ($best -gt 0) { " Meilleur débit jamais obtenu sur ce réseau : $([int][Math]::Round($best / 1e6)) Mb/s." } else { '' }) + "`n`n" +
    $(switch ($qualRank) {
        1 { "Le problème : aucun. Le lien est au niveau de ce que ce réseau sait faire." }
        2 { "Le problème : le lien est nettement en dessous de ce qu'un Wi-Fi moderne permet. La navigation reste correcte, mais les gros téléchargements et la visioconférence en souffrent." }
        default { "Le problème : le lien est très bas. À prévoir : des visioconférences hachées, des téléchargements lents et des pages qui traînent." }
    }) +
    $(if ($qualRank -ge 2) {
        "`n`nLes issues possibles :`n" +
        "- rapprochez-vous du point d'accès, ou retirez ce qui s'interpose (mur porteur, miroir, plancher chauffant) ;`n" +
        "- passer sur la bande 5 GHz si la box la propose : plus rapide et moins encombrée que 2,4 GHz ;`n" +
        "- changer le canal de la box : un voisin sur le même canal partage le débit ;`n" +
        "- éloignez les brouilleurs : four à micro-ondes, téléphone DECT, adaptateur CPL ;`n" +
        "- si le besoin est durable, un câble Ethernet règle la question définitivement."
    } else { '' }) + "`n`n" + $noSignalNote
}

# The stability guide: a separate field, so a separate explanation. Three real states: not established yet (the
# window is too short), no cut at all, or cuts -- and in that last case the guide offers ways out (D49).
$stabGuide = if (-not $stabEstablished) {
    "Ce que c'est : la continuité de l'association Wi-Fi — le lien a-t-il décroché du point d'accès ? Un décrochage coupe une visioconférence net, même quand le débit est bon le reste du temps. Ici : pas encore mesurable.`n`n" +
    "Le problème : la mesure demande au moins 4 relevés étalés sur 2 minutes, et Vigie en a $sampleCount" +
    $(if ($spanMin -gt 0) { ", étalés sur $spanMin minute$(if ($spanMin -gt 1) {'s'})." } else { '.' }) +
    " Un relevé est enregistré à chaque rafraîchissement de la carte : laissez Vigie ouverte quelques minutes et la valeur apparaîtra d'elle-même.`n`n" +
    "Seuls les décrochages de l'association sont comptés, seul signe non ambigu : la variation du débit négocié, elle, suit le trafic et non la qualité — la retenir afficherait « instable » sur un lien parfaitement sain."
} elseif ($dropCount -eq 0) {
    "Ce que c'est : la continuité de l'association Wi-Fi — le lien a-t-il décroché du point d'accès ? Ici : aucune coupure sur les $spanMin dernières minutes ($sampleCount relevés).`n`n" +
    "Le problème : aucun. L'association n'a jamais été perdue sur la fenêtre observée.`n`n" +
    "Seuls les décrochages de l'association sont comptés, seul signe non ambigu : la variation du débit négocié, elle, suit le trafic et non la qualité — la retenir afficherait « instable » sur un lien parfaitement sain."
} else {
    "Ce que c'est : la continuité de l'association Wi-Fi — le lien a-t-il décroché du point d'accès ? Ici : $dropCount coupure$(if ($dropCount -gt 1) {'s'}) sur les $spanMin dernières minutes ($sampleCount relevés).`n`n" +
    "Le problème : le lien a perdu son association avec le point d'accès. C'est ce qui coupe une visioconférence net ou fige un téléchargement, même si le débit est bon entre deux coupures.`n`n" +
    "Les issues possibles :`n" +
    "- rapprochez-vous du point d'accès, ou retirez ce qui s'interpose (mur porteur, miroir, plancher chauffant) ;`n" +
    "- passer sur la bande 5 GHz si la box la propose : plus rapide et moins encombrée que 2,4 GHz ;`n" +
    "- changer le canal de la box : un voisin sur le même canal partage le débit ;`n" +
    "- éloignez les brouilleurs : four à micro-ondes, téléphone DECT, adaptateur CPL ;`n" +
    "- mettez à jour le pilote de la carte Wi-Fi (site du fabricant) : certains décrochent en économie d'énergie ;`n" +
    "- si le besoin est durable, un câble Ethernet règle la question définitivement."
}

# The name of the network: the Windows profile of the main interface -- for Wi-Fi, that is the SSID. One single
# source, the one that stays readable without a location permission.
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
        # The same information, in COLUMNS: that is the form the interface displays.
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
# The latency thresholds: the module config, overridable in Settings (D57).
$latWarn = [int](Get-ModuleSetting -Unit 'network' -Key 'LatencyWarnMs');  if (-not $latWarn)  { $latWarn = 80 }
$latErr  = [int](Get-ModuleSetting -Unit 'network' -Key 'LatencyErrorMs'); if (-not $latErr)   { $latErr = 200 }
# --- DNS: the resolver that is configured, and a REAL resolution --------------
$dnsServeurs = @()
try {
    $dnsServeurs = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.ServerAddresses } |
        ForEach-Object { $_.ServerAddresses } | Select-Object -Unique)
} catch { }
$dnsLocal = ($dnsServeurs -contains '127.0.0.1')
$dnsOk = $false; $dnsMs = 0
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $dnsOk = [bool](Resolve-DnsName 'www.microsoft.com' -Type A -QuickTimeout -ErrorAction Stop)
    $sw.Stop(); $dnsMs = [int]$sw.ElapsedMilliseconds
} catch { }
# The name of the local proxy, if a known service is running (Acrylic here): naming it helps one act.
$dnsProxyName = ''
if ($dnsLocal) {
    $proxy = Get-LocalDnsProxyService
    if ($proxy) { $dnsProxyName = "$($proxy.Name)" }
}
$dnsValue = if ($dnsLocal) { '127.0.0.1 (résolveur local)' } else { ($dnsServeurs | Select-Object -First 2) -join ', ' }
if (-not $dnsServeurs.Count) { $dnsValue = 'aucun serveur' }
$dnsStatut = if ($dnsOk) { 'ok' } elseif ($connected) { 'error' } else { 'warn' }
$dnsGuide = if ($dnsOk) {
    "Résolution vérifiée en $dnsMs ms." + $(if ($dnsLocal) { "`nLe trafic DNS passe par un proxy LOCAL" + $(if ($dnsProxyName) { " (service $dnsProxyName)" }) + " : s'il tombe, tout semble « sans internet » alors que le réseau va bien — ce champ fera la différence." } else { '' })
} elseif ($dnsLocal) {
    "La résolution de noms ÉCHOUE alors que la connexion réseau semble bonne : le résolveur LOCAL" + $(if ($dnsProxyName) { " ($dnsProxyName)" }) + " ne répond plus.`nQue faire : redémarrer le service" + $(if ($dnsProxyName) { " « $dnsProxyName »" } else { " du proxy DNS" }) + " (services.msc), ou repasser temporairement le DNS de la carte sur la box/un DNS public."
} else {
    "La résolution de noms échoue : sans DNS, les sites ne s'ouvrent plus même si la connexion est bonne.`nQue faire : vérifier le serveur DNS de la carte réseau, ou la box."
}

$latSt = if ($lat -eq '-') { 'neutral' } elseif ([double]($lat) -lt $latWarn) { 'ok' } elseif ([double]($lat) -lt $latErr) { 'warn' } else { 'error' }
$pubGuide = if ($pubAt) { "Dernière récupération : $pubAt. « Obtenir l'IP publique » l'actualise." } else { "Non récupérée : « Obtenir l'IP publique » la récupère, par un appel à un service externe." }

# A GENERAL RULE of this probe: never a conditional instruction when the probe KNOWS which case we are in. It
# knows the answer, so it gives it: a guide describes the REAL state, and offers checks only if they help now.
# Sorting the instruction out is not the user job.

# The Internet connection and the type of connection said the same thing over two lines. Merged: one single line
# carrying the state AND the means.

$connValue = if (-not $connected) { 'Déconnecté' } elseif ($connType -ne '-') { $connType } else { 'Connecté' }
$connGuide = if ($connected) {
    "Ce que c'est : la liaison par laquelle ce PC atteint Internet, et le type d'interface qu'elle emprunte. Ici : connecté en $connValue" +
    $(if ($primary) { " via l'interface « $($primary.Name) »." } else { '.' }) + "`n`n" +
    "Le problème : aucun. La connectivité vient d'être confirmée par une vraie connexion TCP sortante (1.1.1.1, 8.8.8.8 ou 9.9.9.9) — pas par le seul indicateur de Windows, qui reste parfois au vert après une coupure."
} else {
    "Ce que c'est : la liaison par laquelle ce PC atteint Internet. Ici : aucune. Ni la connexion TCP de test (1.1.1.1, 8.8.8.8, 9.9.9.9) ni l'indicateur de Windows ne rapportent d'accès.`n`n" +
    "Le problème : ce PC est hors ligne. Tout ce qui dépend du réseau est indisponible.`n`n" +
    "Les issues possibles :`n" +
    "- vérifiez le lien physique : câble Ethernet enfoncé des deux côtés, ou Wi-Fi activé et mode Avion coupé ;`n" +
    "- redémarrez la box ou le routeur, puis laissez-lui le temps de retrouver la ligne ;`n" +
    "- testez depuis un autre appareil : s'il n'a rien non plus, la panne est chez l'opérateur ;`n" +
    $(if ($vpn) { "- un tunnel VPN est actif sur ce PC : coupez-le, il peut détourner tout le trafic vers un serveur injoignable ;`n" } else { '' }) +
    "- en dernier recours, réinitialisez la pile réseau (Paramètres > Réseau et Internet > Paramètres réseau avancés > Réinitialisation du réseau)."
}

$ip6Guide = if ($ip6 -ne '-') {
    "Ce que c'est : l'adresse IPv6 de l'interface principale, le format d'adressage moderne d'Internet. Ici : $ip6.`n`n" +
    "Le problème : aucun. IPv6 est actif ; les services qui l'exigent sont joignables."
} else {
    "Ce que c'est : l'adresse IPv6 de l'interface principale. Ici : aucune adresse IPv6 attribuée.`n`n" +
    "Le problème : rien de bloquant, IPv4 suffit à tout usage courant. Quelques services récents sont simplement un peu plus lents à joindre.`n`n" +
    "Les issues possibles :`n" +
    "- l'opérateur ne fournit pas encore IPv6 : rien à faire sur cette machine ;`n" +
    "- IPv6 est décoché sur la carte réseau : réactivez-le dans les propriétés de l'interface ;`n" +
    "- la box est réglée en « IPv4 seul » : l'option se change dans son interface d'administration."
}

$vpnGuide = if ($vpn) {
    "Ce que c'est : la présence d'un tunnel VPN actif sur ce PC. Ici : oui, un adaptateur de tunnel est actif.`n`n" +
    "Le problème : aucun en soi. Le trafic transite simplement par le VPN : l'IP publique affichée est celle du fournisseur, et les débits mesurés incluent le détour."
} else {
    "Ce que c'est : la présence d'un tunnel VPN actif sur ce PC. Ici : aucun.`n`n" +
    "Le problème : aucun. Le trafic sort directement par la connexion, sans tunnel."
}

$latGuide = if ($lat -eq '-') {
    "Ce que c'est : le délai d'aller-retour vers un serveur public — ce qui rend une visioconférence fluide ou saccadée, et un jeu en ligne jouable ou non. Ici : pas encore mesuré.`n`n" +
    "« Mesurer débit/latence » obtient la valeur."
} elseif ($latSt -eq 'ok') {
    "Ce que c'est : le délai d'aller-retour vers un serveur public. Ici : $lat ms.`n`n" +
    "Le problème : aucun. En dessous de 80 ms, visioconférence et jeu en ligne sont confortables."
} else {
    "Ce que c'est : le délai d'aller-retour vers un serveur public. Ici : $lat ms.`n`n" +
    $(if ($latSt -eq 'warn') { "Le problème : la réactivité est moyenne. La navigation reste fluide, mais les échanges en temps réel accusent un retard perceptible." }
      else { "Le problème : la latence est élevée. Visioconférence et jeu en ligne deviennent pénibles, même si le débit brut est bon." }) + "`n`n" +
    "Les issues possibles :`n" +
    "- une autre application sature la ligne (sauvegarde, téléchargement, mise à jour) : attendez qu'elle finisse ;`n" +
    $(if ($connType -eq 'Wi-Fi') { "- le lien Wi-Fi est en cause : voyez la ligne « Lien Wi-Fi » ci-dessus, ou branchez un câble Ethernet ;`n" } else { '' }) +
    $(if ($vpn) { "- le VPN actif ajoute un détour : mesurez à nouveau sans lui pour comparer ;`n" } else { '' }) +
    "- redémarrez la box : une session qui traîne depuis des semaines finit par dériver ;`n" +
    "- si la valeur reste haute en Ethernet et sans VPN, la cause est en amont, chez l'opérateur."
}
$speedGuide = if ($down -eq '-') {
    "Ce que c'est : le débit réellement obtenu, mesuré en téléchargeant un fichier de test. Ici : pas encore mesuré.`n`n" +
    "« Mesurer débit/latence » obtient la valeur. La mesure prend quelques secondes et consomme une dizaine de mégaoctets."
} else {
    "Ce que c'est : le débit réellement obtenu lors de la dernière mesure, à ne pas confondre avec le débit négocié du lien Wi-Fi (qui est un plafond théorique). Ici : $down Mb/s en réception" +
    $(if ($up -ne '-') { ", $up Mb/s en émission." } else { '.' }) + "`n`n" +
    "Le problème : à juger par rapport à l'abonnement. Un écart important tient le plus souvent au lien Wi-Fi ou à une application qui occupait la ligne pendant la mesure — relancez la mesure au calme pour comparer."
}

$fields = @(
    New-Field -Key 'connected' -Label 'Connexion' -Value $connValue -Kind 'text' -Status $(if ($connected) {'ok'} else {'warn'}) `
        -Help "État de l'accès à Internet et interface qui le porte. Vérifié par une connexion TCP réelle (1.1.1.1 / 8.8.8.8), avec repli sur l'indicateur Windows." `
        -Guide $connGuide
    New-Field -Key 'netName'  -Label 'Réseau (nom)' -Value $netName -Kind 'text' -Status 'neutral' -Help "Nom du réseau : SSID en Wi-Fi, sinon nom de l'interface."
)
if ($hasWifi) {
    # AN ALERT ALWAYS CARRIES ITS BUTTON (D66). The two cases where this field alerts -- a weak radio link, or a
    # Wi-Fi dropped while nothing else is giving Internet -- are resolved in the same place: the Windows list of
    # networks, where one reconnects or picks another band. Vigie does not act there in the user stead, it leads
    # them there -- that is the second family of D66 buttons.
    $fields += New-Field -Key 'wifi' -Label 'Lien Wi-Fi' -Value $wifiText -Kind 'text' -Status $qualStatus `
        -Help "Qualité du lien radio, jugée sur le meilleur débit négocié de la liaison au cours des 30 dernières minutes." `
        -FixAction $(if ($qualStatus -in @('warn', 'error')) { 'open-network-settings' } else { $null }) `
        -Guide $wifiGuide
    # Stability only means something if the link is established: an adapter that is off or not associated has no
    # association to hold, and the Wi-Fi link line already states its condition.
    if ($wifiUp) {
        $fields += New-Field -Key 'wifiStability' -Label 'Stabilité' -Value $stabLabel -Kind 'text' -Status $stabStatus `
            -Help "Continuité de l'association Wi-Fi sur les 30 dernières minutes : compte les décrochages du lien radio." `
            -FixAction $(if ($stabStatus -eq 'warn') { 'open-network-settings' } else { $null }) `
            -Guide $stabGuide
    }
}
$fields += @(
    New-Field -Key 'ip'  -Label 'IP locale (LAN)' -Value $ip  -Kind 'text' -Status 'neutral' -Help "Adresse IPv4 privée de l'interface portant la route par défaut (réseau local)."
    New-Field -Key 'publicIp' -Label 'IP publique' -Value $(if ($pubIp -eq '-') {'Non récupérée'} else {$pubIp}) -Kind 'text' `
        -Status $(if ($pubIp -eq '-') {'warn'} else {'neutral'}) `
        -Help "Adresse IP publique vue depuis Internet (récupérée à la demande)." -Guide $pubGuide `
        -FixAction $(if ($pubIp -eq '-') {'net-publicip'} else {$null})
    New-Field -Key 'ip6' -Label 'Adresse IPv6' -Value $ip6 -Kind 'text' -Status 'neutral' -Help "Adresse IPv6 principale de l'interface par défaut." -Guide $ip6Guide
    New-Field -Key 'mac' -Label 'Adresse MAC'  -Value $mac -Kind 'text' -Status 'neutral' `
        -Help "Adresse MAC de l'interface principale. Le détail montre toutes les interfaces actives." `
        -Table @{ columns = @('Interface', 'Type', 'IPv4', 'MAC'); rows = $adapterRows }
    New-Field -Key 'dns' -Label 'DNS' -Value $dnsValue -Kind 'text' -Status $dnsStatut `
        -FixAction $(if ($dnsStatut -ne 'ok') { 'net-dns-flush' } else { $null }) `
        -Help "Le serveur qui traduit les noms de sites en adresses. Testé par une résolution réelle à chaque passage." -Guide $dnsGuide
    New-Field -Key 'vpn' -Label 'VPN actif'    -Value $vpn -Kind 'bool' -Status 'neutral' -Help "Présence d'un adaptateur de tunnel VPN actif sur ce PC." -Guide $vpnGuide
    New-Field -Key 'latency' -Label 'Latence'  -Value $(if ($lat -eq '-') {'Non mesurée'} else {"$lat ms"}) -Kind 'text' `
        -Status $(if ($lat -eq '-') {'warn'} else {$latSt}) -FixAction $(if ($lat -eq '-') {'net-speedtest'} else {$null}) `
        -Help "Délai d'aller-retour vers un serveur public. « Mesurer débit/latence » l'actualise." -Guide $latGuide
    New-Field -Key 'down'    -Label 'Débit descendant' -Value $(if ($down -eq '-') {'Non mesuré'} else {"$down Mbps"}) -Kind 'text' `
        -Status $(if ($down -eq '-') {'warn'} else {'neutral'}) -FixAction $(if ($down -eq '-') {'net-speedtest'} else {$null}) `
        -Help "Débit obtenu en réception lors de la dernière mesure." -Guide $speedGuide
    New-Field -Key 'up'      -Label 'Débit montant' -Value $(if ($up -eq '-') {'Non mesuré'} else {"$up Mbps"}) -Kind 'text' `
        -Status $(if ($up -eq '-') {'warn'} else {'neutral'}) -FixAction $(if ($up -eq '-') {'net-speedtest'} else {$null}) `
        -Help "Débit obtenu en émission lors de la dernière mesure (envoi d'environ 5 Mo)." -Guide $speedGuide
)
if ($measAt) {
    $fields += New-Field -Key 'measAt' -Label 'Mesure du' -Value $measAt -Kind 'date' -Status 'neutral' -Help "Date de la dernière mesure débit/latence."
}
# THE EPHEMERAL PORTS, against Windows's limit, per protocol (NET-STATE). When one space is full, every new connection
# of every application fails: 85 exhaustions were logged from 06/07 to 17/09, the last one while Vigie showed only
# "server unreachable". The range is read with netsh (0.2 s), so it is kept an hour, and again after each start of
# Windows; the ports in use are read directly from Windows in about 20 ms (scripts/lib/tcp-ports.ps1).
# The range and its cache live in Get-EphemeralPortRanges: the permanent watch reads it too, and one reading has one
# definition (D15). It used to be written out here, where only this card could see it.
$ranges = Get-EphemeralPortRanges -Backend $backend
$portsStatus = 'neutral'
$portsValue = 'Plage inconnue'
$portsTable = $null
$portsReason = $null
$portsGuide = $null
if ($ranges -and $ranges.tcp -and $ranges.udp) {
    $usage = @{}
    foreach ($proto in 'tcp', 'udp') {
        $usage[$proto] = Get-EphemeralPortUsage -Protocol $proto -Start ([int]$ranges.$proto.Start) -Count ([int]$ranges.$proto.Count)
    }
    $parts = @()
    $worstPct = 0
    foreach ($proto in 'tcp', 'udp') {
        $u = $usage[$proto]
        if (-not $u) { $parts += ($proto.ToUpper() + ' illisible'); continue }
        $pct = [math]::Round(100 * $u.Used / $u.Limit)
        if ($pct -gt $worstPct) { $worstPct = $pct }
        $fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        $parts += ($proto.ToUpper() + ' ' + $u.Used.ToString('N0', $fr) + ' sur ' + $u.Limit.ToString('N0', $fr) + ' (' + $pct + ' %)')
    }
    $portsValue = $parts -join ' · '
    $portsStatus = if (-not $usage.tcp -or -not $usage.udp) { 'warn' } elseif ($worstPct -ge 95) { 'error' } elseif ($worstPct -ge 80) { 'warn' } else { 'ok' }
    # WHO HOLDS THEM: the processes holding the most, per protocol, named by the service they run when they host one.
    $rows = @()
    $holders = @()
    foreach ($proto in 'tcp', 'udp') {
        if (-not $usage[$proto]) { continue }
        foreach ($o in @($usage[$proto].ByProcess | Select-Object -First 5)) {
            $name = if ($o.ProcessId -eq 0) { 'Connexions en fermeture (TIME_WAIT)' } else {
                $pn = "$((Get-Process -Id $o.ProcessId -ErrorAction SilentlyContinue).ProcessName)"
                if (-not $pn) { $pn = "processus $($o.ProcessId)" }
                if ($pn -eq 'svchost') { $svc = Get-ServiceByProcessId -ProcessId $o.ProcessId; if ($svc) { $pn = "svchost ($($svc.DisplayName))" } }
                $pn
            }
            $rows += ,@($proto.ToUpper(), $name, "$($o.ProcessId)", "$($o.Count)")
            $holders += [pscustomobject]@{ Label = "$name, $($o.Count) $($proto.ToUpper())"; Count = $o.Count }
        }
    }
    if ($rows.Count) { $portsTable = @{ columns = @('Protocole', 'Processus', 'PID', 'Ports'); rows = $rows } }

    <#
        ONE PROCESS HOARDING PORTS, named before the reserve is full.

        The gauge above reads the CONNECTION tables: a port taken without a connection -- bind() called, neither
        listening nor connected -- does not appear there. That is exactly the shape of the costliest leak seen on
        this computer: WSL's network host held 244 ephemeral ports on the morning of 30/09 and 841 that evening,
        never giving one back. On 14/09 it held 10 426: every port lookup went from 2 ms to 26 seconds, and an
        update of Vigie from 98 to 225 seconds. The card, meanwhile, read 1 %.

        The complete reading costs 1,5 s, fifty times the gauge. It is taken HERE, on a card recomputed every five
        minutes, and only to answer the one question the gauge cannot ask: is a single process holding a heap?
    #>
    $hogFloor = 500
    try { $hogFloor = [int](Get-ModuleSetting -Unit 'network' -Key 'PortHogPorts' -Backend $backend) } catch { }
    $hog = $null
    if ($hogFloor -gt 0) {
        try {
            $held = Get-HeldEphemeralPorts -Start ([int]$ranges.tcp.Start)
            if ($held) {
                # PID 0 IS NOT A HOARDER: those are the closing connections (TIME_WAIT), owned by nobody, which
                # free themselves within minutes. Naming it would send someone hunting a culprit that does not exist.
                foreach ($o in @($held.ByProcess | Where-Object { [int]$_.ProcessId -ne 0 } | Select-Object -First 1)) {
                    if ([int]$o.Count -lt $hogFloor) { break }
                    $hogName = "$((Get-Process -Id ([int]$o.ProcessId) -ErrorAction SilentlyContinue).ProcessName)"
                    if (-not $hogName) { $hogName = "processus $($o.ProcessId)" }
                    <#
                        IS IT WSL? Its network host runs inside a generic dllhost, so the name says nothing: the
                        command line carries the AppID, and the modules say which DLL is loaded. Knowing it changes
                        what we can OFFER -- restarting WSL hands those ports back, and nothing else does.
                    #>
                    $isWsl = $false
                    try {
                        $cmd = "$((Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$o.ProcessId) -ErrorAction Stop).CommandLine)"
                        if ($cmd -match '(?i)\{17696EAC-9568-4CF5-BB8C-82515AAD6C09\}') { $isWsl = $true }
                    } catch { }
                    if (-not $isWsl -and $hogName -match '(?i)wsl|vmmem') { $isWsl = $true }
                    $hog = [pscustomobject]@{ Name = $(if ($isWsl) { 'WSL (hôte réseau)' } else { $hogName })
                                              ProcessId = [int]$o.ProcessId; Count = [int]$o.Count
                                              Held = [int]$held.Held; States = "$($o.States)"; IsWsl = $isWsl }
                }
            }
        } catch { }
    }
    if ($hog) {
        $hogCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        $portsValue = $portsValue + ' · ' + $hog.Name + ' en tient ' + $hog.Count.ToString('N0', $hogCulture)
        if ($portsStatus -eq 'ok') { $portsStatus = 'warn' }
        $portsReason = $hog.Name + ' (PID ' + $hog.ProcessId + ') tient ' + $hog.Count.ToString('N0', $hogCulture) +
                       ' ports temporaires sur les ' + $hog.Held.ToString('N0', $hogCulture) + ' occupés — ' + $hog.States
        $portsGuide = "Un seul processus tient $($hog.Count.ToString('N0', $hogCulture)) ports réseau temporaires. Un processus ordinaire en tient dix à soixante." +
                      [Environment]::NewLine + [Environment]::NewLine +
                      "Ces prises-là n'apparaissent pas dans le compte ci-dessus, qui ne voit que les connexions : un port pris sans connexion est invisible à cette mesure, et c'est la forme que prend une fuite." +
                      [Environment]::NewLine + [Environment]::NewLine +
                      "Tant que la réserve n'est pas pleine, rien ne casse. En s'accumulant, elles ralentissent toutes les connexions de l'ordinateur, puis les font échouer. Elles sont rendues quand le processus se termine."
    }

    if ($portsStatus -in 'warn', 'error' -and -not $hog) {
        $top = @($holders | Sort-Object Count -Descending | Select-Object -First 3)
        $portsReason = 'Surtout ' + ((@($top | ForEach-Object { $_.Label })) -join ' ; ')
        $portsGuide = "Les ports réseau temporaires approchent de la limite de Windows. Quand elle est atteinte, toutes les nouvelles connexions échouent, pour toutes les applications." +
                      [Environment]::NewLine + [Environment]::NewLine +
                      "Le tableau nomme les processus qui en tiennent le plus. Fermer ou redémarrer celui qui en tient le plus les libère ; les connexions en fermeture se libèrent seules en quelques minutes."
    }
}
# AND THE REMEDY FOLLOWS WHAT WAS FOUND. When WSL is the one hoarding, the task manager brings nothing: those takes
# are only given back by restarting WSL. So the offered gesture is the one that acts, and the window it opens leaves
# the choice between restarting, stopping, or doing nothing.
$fields += New-Field -Key 'ports' -Label 'Ports réseau temporaires' -Value $portsValue -Kind 'text' -Status $portsStatus `
    -Table $portsTable -Reason $portsReason -Guide $portsGuide `
    -FixAction $(if ($hog -and $hog.IsWsl) { 'wsl-restart' }
                 elseif ($portsStatus -in 'warn', 'error') { 'open-task-manager' }
                 else { $null }) `
    -Help "Ports que Windows prête aux connexions sortantes, face à sa limite, en TCP et en UDP. À la limite, plus aucune application ne peut ouvrir de connexion."

# The CARD status: connectivity first, but a degraded or unstable Wi-Fi link must be visible from the list --
# otherwise the card stays green while one of its lines is orange, and the user never unfolds it. A stability that
# is not established yet does NOT degrade the card: it is a normal wait, like a latency not measured yet.

$modStatus = if ($portsStatus -eq 'error') { 'error' }
             elseif (-not $connected) { 'warn' }
             elseif ($hasWifi -and $qualStatus -eq 'error') { 'error' }
             elseif ($portsStatus -eq 'warn') { 'warn' }
             elseif ($hasWifi -and $qualStatus -eq 'warn') { 'warn' }
             elseif ($hasWifi -and $wifiUp -and $stabEstablished -and $dropCount -gt 0) { 'warn' }
             else { 'ok' }

# SCOPE: the computer's interfaces and ports; no account has a network of its own.
New-ModuleObject -Id 'net' -Theme 'network' -Label 'Réseau' -Scope 'machine' -Status $modStatus -Fields $fields -Actions @(
    New-Action -Id 'net-publicip'  -Label "Obtenir l'IP publique" -Kind 'immediate' -Help "Interroge un service externe (api.ipify.org...) pour connaître l'adresse IP publique. Un appel sortant est effectué."
    New-Action -Id 'net-dns-flush' -Severity 'fix' -Label 'Purger le cache DNS' -BusyLabel 'Purge…' -Kind 'confirm' -Confirm `
        -Help "Vide le cache DNS de Windows et celui du proxy local s’il en existe un (détecté sur le port 53). À utiliser quand quelques sites ne répondent plus alors qu'internet fonctionne. Coupe la résolution une à deux secondes."
    New-Action -Id 'net-speedtest' -Label 'Mesurer débit/latence'  -Kind 'immediate' -Help "Mesure la latence (ping) et le débit descendant en téléchargeant ~10 Mo. Prend quelques secondes et consomme un peu de data."
    # A PERMANENT destination (D114): the network settings are not only of use during a breakdown.
    New-Action -Id 'open-network-settings' -Label 'Paramètres réseau' -Kind 'manual' -Severity 'info' -Help "Ouvre les paramètres réseau de Windows : choix du réseau, reconnexion, état de l'adaptateur."
)
