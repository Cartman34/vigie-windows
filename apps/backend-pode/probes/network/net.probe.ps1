<# Sonde : réseau (connexion / nom (SSID) / qualite du lien Wi-Fi / IP LAN / IP publique /
   IPv6 / MAC / VPN + débit).
   Detection via System.Net.NetworkInformation (.NET pur, fiable dans le runspace Pode).
   Etat et qualite du Wi-Fi via l'adaptateur + le profil reseau Windows : lisibles SANS
   privilege et SANS le service de localisation, contrairement a netsh wlan.
   Seule ecriture : un court historique de debits de liaison dans var/cache/netwifi.json
   (via Update-StateJson), pour deduire une STABILITE — un releve isole n'en dit rien.
   IP publique a la demande (action net-publicip). Rien d'autre n'est modifie. #>
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

# --- Qualite et stabilite du lien Wi-Fi -------------------------------------------
# CE QUI EST REELLEMENT MESURABLE ICI (verifie en l'executant sur la machine) :
#   - le debit NEGOCIE de la liaison radio : Get-NetAdapter, ReceiveLinkSpeed et
#     TransmitLinkSpeed. La carte descend en modulation des que la reception se
#     degrade : ce debit est donc un indicateur direct de la qualite du lien, et il
#     bouge en continu (releve : 39 -> 78 Mb/s en dix secondes). Cout : ~80 ms.
#   - l'etat du media, pour distinguer une coupure d'une simple baisse.
# CE QUI N'EST PAS MESURABLE ICI (teste, et negatif) :
#   - « netsh wlan show interfaces » : erreur 5, exige le service de localisation ET
#     l'elevation. C'est ce qui faisait afficher « non connecte » a tort.
#   - la classe WMI root\wmi MSNdis_80211_ReceivedSignalStrength : le pilote de cette
#     carte repond « non pris en charge ».
#   - les compteurs de performance reseau : leur nom est traduit, donc non portable.
# Consequence assumee : AUCUNE force de signal en % ou en dBm n'est affichee. Un
# chiffre faux serait pire que pas de chiffre — le champ le dit explicitement.
$rxBps = 0L; $txBps = 0L
if ($wifiAdapter) {
    try { $rxBps = [long]$wifiAdapter.ReceiveLinkSpeed } catch { }
    try { $txBps = [long]$wifiAdapter.TransmitLinkSpeed } catch { }
}
# On retient le sens le PLUS RAPIDE des deux, et non le plus lent. Raison : la carte
# n'entretient une modulation haute que dans le sens ou du trafic circule ; le sens
# inactif retombe tres bas. Prendre le minimum, c'est mesurer l'inactivite, pas la
# qualite — verifie ici : emission a 24 Mb/s pendant que la reception tenait 78 Mb/s,
# sans que rien n'ait bouge.
$linkBps = [Math]::Max($rxBps, $txBps)
$linkMbps = if ($linkBps -gt 0) { [int][Math]::Round($linkBps / 1e6) } else { 0 }
$rxMbps   = if ($rxBps  -gt 0) { [int][Math]::Round($rxBps  / 1e6) } else { 0 }
$txMbps   = if ($txBps  -gt 0) { [int][Math]::Round($txBps  / 1e6) } else { 0 }

# Historique court, pour deduire une STABILITE : un seul releve ne dit rien d'une
# variation. La sonde a un TTL de 15 s, elle passe donc assez souvent pour accumuler.
# Ecriture par Update-StateJson : c'est le seul code autorise a ecrire dans var/cache.
$wifiHistFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'netwifi.json'
$nowT = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$samples = @(); $best = 0L
if ($hasWifi) {
    $hist = $null
    if (Test-Path $wifiHistFile) { try { $hist = Get-Content $wifiHistFile -Raw | ConvertFrom-Json } catch { } }
    # Changer de reseau remet le compteur a zero : le meilleur debit d'un SSID ne dit
    # rien d'un autre, et comparer les deux fabriquerait une fausse degradation.
    if ($hist -and "$($hist.ssid)" -eq $ssid) {
        try { $best = [long]$hist.best } catch { }
        try {
            $samples = @(@($hist.samples) | Where-Object { $null -ne $_ -and $null -ne $_.t } |
                         ForEach-Object { @{ t = [long]$_.t; bps = [long]$_.bps; up = [int]$_.up } })
        } catch { $samples = @() }
    }
    # Fenetre glissante : 30 minutes, 24 releves au plus. Au-dela, on decrirait un
    # etat passe (autre piece, autre bande) et non celui de maintenant.
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

# On juge sur le SOMMET de la fenetre, pas sur l'instant ni sur la moyenne. Une carte
# Wi-Fi ne monte en modulation que quand elle a du trafic a passer : au repos, le debit
# negocie s'effondre sans que le lien se soit degrade (releve ici : 6 Mb/s au repos,
# 116 Mb/s quelques secondes plus tot). Le plus haut debit atteint recemment est donc le
# seul chiffre qui dise ce que la radio SAIT faire — et une mauvaise reception, elle,
# plafonne bel et bien ce sommet.
$peak = if ($rates.Count) { ($rates | Measure-Object -Maximum).Maximum } else { 0 }
$peakMbps = if ($peak -gt 0) { [int][Math]::Round($peak / 1e6) } else { 0 }

# Qualite. Deux jugements complementaires, on retient le PIRE : c'est celui que
# l'utilisateur subit. L'absolu dit ce que le lien peut porter ; le relatif compare au
# meilleur deja obtenu sur CE reseau, donc detecte une degradation meme sur un lien
# intrinsequement lent. Le relatif n'entre en jeu qu'avec assez de releves : sans
# reference etablie, « le premier releve est le maximum » serait un faux « tout va bien ».
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

# Stabilite : UNIQUEMENT la continuite de l'association. On avait d'abord essaye la
# dispersion des debits — a jeter : au repos elle atteint 94 % sur un lien parfaitement
# sain, elle mesure le trafic et non la qualite. Un decrochage, lui, ne s'interprete pas.
# Il faut aussi que la fenetre couvre une vraie duree : quatre releves en cinq secondes
# ne prouvent rien sur la tenue d'un lien.
# La stabilite est un CHAMP a part entiere, distinct de la qualite : chacun porte son
# statut et son guide. Pas encore etablie = warn avec explication, jamais un champ vide.
$stabEstablished = ($sampleCount -ge 4 -and $spanSec -ge 120)
$spanMin = [int][Math]::Round($spanSec / 60)
# Une mesure qui n'est PAS ENCORE faite n'est pas une alerte : c'est une attente. Elle
# reste donc neutre -- alerter sans cause use l'attention, et il n'y a rien a resoudre
# (une alerte doit toujours pouvoir proposer un bouton, D66).
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

# Un Wi-Fi eteint n'est pas un probleme en soi (cable Ethernet branche, mode Avion
# voulu) : c'est la ligne « Connexion » qui porte l'alerte. On reste neutre tant
# qu'Internet repond par ailleurs.
if (-not $wifiUp) { $qualStatus = if ($connected) { 'neutral' } else { 'warn' } }

# Ce que Windows ne laisse PAS lire ici. Dit une fois, dans le guide, plutot qu'un
# indicateur invente : c'est la seule facon honnete de traiter une mesure absente.
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
        default { "Le problème : le lien est très bas. Attendez-vous à des visioconférences hachées, des téléchargements lents et des pages qui traînent." }
    }) +
    $(if ($qualRank -ge 2) {
        "`n`nLes issues possibles :`n" +
        "- rapprochez-vous du point d'accès, ou retirez ce qui s'interpose (mur porteur, miroir, plancher chauffant) ;`n" +
        "- passez sur la bande 5 GHz si votre box la propose : plus rapide et moins encombrée que 2,4 GHz ;`n" +
        "- changez le canal de la box : un voisin sur le même canal se partage le débit avec vous ;`n" +
        "- éloignez les brouilleurs : four à micro-ondes, téléphone DECT, adaptateur CPL ;`n" +
        "- si le besoin est durable, un câble Ethernet règle la question définitivement."
    } else { '' }) + "`n`n" + $noSignalNote
}

# Guide de la stabilite : champ separe, donc explication separee. Trois etats reels :
# pas encore etablie (fenetre trop courte), aucune coupure, ou des coupures — et dans ce
# dernier cas le guide propose des issues (D49).
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
    "- passez sur la bande 5 GHz si votre box la propose : plus rapide et moins encombrée que 2,4 GHz ;`n" +
    "- changez le canal de la box : un voisin sur le même canal se partage le débit avec vous ;`n" +
    "- éloignez les brouilleurs : four à micro-ondes, téléphone DECT, adaptateur CPL ;`n" +
    "- mettez à jour le pilote de la carte Wi-Fi (site du fabricant) : certains décrochent en économie d'énergie ;`n" +
    "- si le besoin est durable, un câble Ethernet règle la question définitivement."
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
# Seuils de latence : config du module, surchargeable dans Parametres (D57).
$latWarn = [int](Get-ModuleSetting -Unit 'network' -Key 'LatencyWarnMs');  if (-not $latWarn)  { $latWarn = 80 }
$latErr  = [int](Get-ModuleSetting -Unit 'network' -Key 'LatencyErrorMs'); if (-not $latErr)   { $latErr = 200 }
# --- DNS : le resolveur configure et une resolution REELLE -------------------
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
# Le nom du proxy local, si un service connu tourne (Acrylic ici) : nommer aide a agir.
$dnsProxyNom = ''
if ($dnsLocal) {
    $proxy = Get-LocalDnsProxyService
    if ($proxy) { $dnsProxyNom = "$($proxy.Name)" }
}
$dnsValeur = if ($dnsLocal) { '127.0.0.1 (résolveur local)' } else { ($dnsServeurs | Select-Object -First 2) -join ', ' }
if (-not $dnsServeurs.Count) { $dnsValeur = 'aucun serveur' }
$dnsStatut = if ($dnsOk) { 'ok' } elseif ($connected) { 'error' } else { 'warn' }
$dnsGuide = if ($dnsOk) {
    "Résolution vérifiée en $dnsMs ms." + $(if ($dnsLocal) { "`nLe trafic DNS passe par un proxy LOCAL" + $(if ($dnsProxyNom) { " (service $dnsProxyNom)" }) + " : s'il tombe, tout semble « sans internet » alors que le réseau va bien — ce champ fera la différence." } else { '' })
} elseif ($dnsLocal) {
    "La résolution de noms ÉCHOUE alors que la connexion réseau semble bonne : votre résolveur LOCAL" + $(if ($dnsProxyNom) { " ($dnsProxyNom)" }) + " ne répond plus.`nQue faire : redémarrer le service" + $(if ($dnsProxyNom) { " « $dnsProxyNom »" } else { " du proxy DNS" }) + " (services.msc), ou repasser temporairement le DNS de la carte sur la box/un DNS public."
} else {
    "La résolution de noms échoue : sans DNS, les sites ne s'ouvrent plus même si la connexion est bonne.`nQue faire : vérifier le serveur DNS de la carte réseau, ou la box."
}

$latSt = if ($lat -eq '-') { 'neutral' } elseif ([double]($lat) -lt $latWarn) { 'ok' } elseif ([double]($lat) -lt $latErr) { 'warn' } else { 'error' }
$pubGuide = if ($pubAt) { "Dernière récupération : $pubAt. Cliquez « Obtenir l'IP publique » pour actualiser." } else { "Non récupérée. Cliquez « Obtenir l'IP publique » (appel à un service externe)." }

# REGLE GENERALE de cette sonde : jamais de consigne conditionnelle (« si Non, verifiez
# X ») quand la sonde SAIT dans quel cas on est. Elle connait la reponse, elle la donne :
# un guide decrit l'etat REEL, et ne propose des verifications que si elles servent
# maintenant. Trier la consigne n'est pas le travail de l'utilisateur.

# « Connexion Internet » et « Type de connexion » disaient la meme chose en deux lignes
# (« Oui » puis « Wi-Fi »). Fusionnees : une seule ligne qui porte l'etat ET le moyen.
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
    "- votre opérateur ne fournit pas encore IPv6 : rien à faire de votre côté ;`n" +
    "- IPv6 est décoché sur la carte réseau : réactivez-le dans les propriétés de l'interface ;`n" +
    "- la box est réglée en « IPv4 seul » : l'option se change dans son interface d'administration."
}

$vpnGuide = if ($vpn) {
    "Ce que c'est : la présence d'un tunnel VPN actif sur ce PC. Ici : oui, un adaptateur de tunnel est actif.`n`n" +
    "Le problème : aucun en soi. Sachez seulement que votre trafic transite par le VPN : l'IP publique affichée est celle du fournisseur, et les débits mesurés incluent le détour."
} else {
    "Ce que c'est : la présence d'un tunnel VPN actif sur ce PC. Ici : aucun.`n`n" +
    "Le problème : aucun. Votre trafic sort directement par votre connexion, sans tunnel."
}

$latGuide = if ($lat -eq '-') {
    "Ce que c'est : le délai d'aller-retour vers un serveur public — ce qui rend une visioconférence fluide ou saccadée, et un jeu en ligne jouable ou non. Ici : pas encore mesuré.`n`n" +
    "Lancez « Mesurer débit/latence » pour obtenir la valeur."
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
    "Lancez « Mesurer débit/latence » pour obtenir la valeur. La mesure prend quelques secondes et consomme une dizaine de mégaoctets."
} else {
    "Ce que c'est : le débit réellement obtenu lors de la dernière mesure, à ne pas confondre avec le débit négocié du lien Wi-Fi (qui est un plafond théorique). Ici : $down Mb/s en réception" +
    $(if ($up -ne '-') { ", $up Mb/s en émission." } else { '.' }) + "`n`n" +
    "Le problème : à juger par rapport à votre abonnement. Un écart important tient le plus souvent au lien Wi-Fi ou à une application qui occupait la ligne pendant la mesure — relancez la mesure au calme pour comparer."
}

$fields = @(
    New-Field -Key 'connected' -Label 'Connexion' -Value $connValue -Kind 'text' -Status $(if ($connected) {'ok'} else {'warn'}) `
        -Help "État de l'accès à Internet et interface qui le porte. Vérifié par une connexion TCP réelle (1.1.1.1 / 8.8.8.8), avec repli sur l'indicateur Windows." `
        -Guide $connGuide
    New-Field -Key 'netName'  -Label 'Réseau (nom)' -Value $netName -Kind 'text' -Status 'neutral' -Help "Nom du réseau : SSID en Wi-Fi, sinon nom de l'interface."
)
if ($hasWifi) {
    $fields += New-Field -Key 'wifi' -Label 'Lien Wi-Fi' -Value $wifiText -Kind 'text' -Status $qualStatus `
        -Help "Qualité du lien radio, jugée sur le meilleur débit négocié de la liaison au cours des 30 dernières minutes." `
        -Guide $wifiGuide
    # La stabilite n'a de sens que si le lien est etabli : un adaptateur eteint ou non
    # associe n'a pas d'association a tenir, la ligne « Lien Wi-Fi » dit deja son etat.
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
        -Help "Adresse MAC de l'interface principale. Cliquez pour voir toutes les interfaces actives." `
        -Table @{ columns = @('Interface', 'Type', 'IPv4', 'MAC'); rows = $adapterRows }
    New-Field -Key 'dns' -Label 'DNS' -Value $dnsValeur -Kind 'text' -Status $dnsStatut `
        -FixAction $(if ($dnsStatut -ne 'ok') { 'net-dns-flush' } else { $null }) `
        -Help "Le serveur qui traduit les noms de sites en adresses. Testé par une résolution réelle à chaque passage." -Guide $dnsGuide
    New-Field -Key 'vpn' -Label 'VPN actif'    -Value $vpn -Kind 'bool' -Status 'neutral' -Help "Présence d'un adaptateur de tunnel VPN actif sur ce PC." -Guide $vpnGuide
    New-Field -Key 'latency' -Label 'Latence'  -Value $(if ($lat -eq '-') {'Non mesurée'} else {"$lat ms"}) -Kind 'text' `
        -Status $(if ($lat -eq '-') {'warn'} else {$latSt}) -FixAction $(if ($lat -eq '-') {'net-speedtest'} else {$null}) `
        -Help "Délai d'aller-retour vers un serveur public. Cliquez « Mesurer débit/latence » pour l'actualiser." -Guide $latGuide
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
# Statut de la CARTE : la connectivite d'abord, mais un lien Wi-Fi degrade ou instable
# doit se voir depuis la liste — sinon la carte reste verte alors qu'une de ses lignes
# est orange, et l'utilisateur ne la deplie jamais. La stabilite « pas encore etablie »
# ne degrade PAS la carte : c'est une attente normale, comme la latence non mesuree.
$modStatus = if (-not $connected) { 'warn' }
             elseif ($hasWifi -and $qualStatus -eq 'error') { 'error' }
             elseif ($hasWifi -and $qualStatus -eq 'warn') { 'warn' }
             elseif ($hasWifi -and $wifiUp -and $stabEstablished -and $dropCount -gt 0) { 'warn' }
             else { 'ok' }

New-ModuleObject -Id 'net' -Theme 'network' -Label 'Réseau' -Status $modStatus -Fields $fields -Actions @(
    New-Action -Id 'net-publicip'  -Label "Obtenir l'IP publique" -Kind 'immediate' -Help "Interroge un service externe (api.ipify.org...) pour connaître l'adresse IP publique. Un appel sortant est effectué."
    New-Action -Id 'net-dns-flush' -Severity 'fix' -Label 'Purger le cache DNS' -BusyLabel 'Purge…' -Kind 'confirm' -Confirm `
        -Help "Vide le cache DNS de Windows et celui du proxy local s’il en existe un (détecté sur le port 53). À utiliser quand quelques sites ne répondent plus alors qu'internet fonctionne. Coupe la résolution une à deux secondes."
    New-Action -Id 'net-speedtest' -Label 'Mesurer débit/latence'  -Kind 'immediate' -Help "Mesure la latence (ping) et le débit descendant en téléchargeant ~10 Mo. Prend quelques secondes et consomme un peu de data."
)
