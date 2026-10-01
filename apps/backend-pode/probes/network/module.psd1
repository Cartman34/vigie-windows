# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    # Le label et la description servent a la vue de gestion des modules.
    # L'activation ne vit PAS ici : elle est un choix de l'utilisateur, dans
    # config/modules.local.psd1 (jamais versionne).
    Label       = 'Réseau'
    Description = 'Connexion, Wi-Fi, adresses et débit.'

    # CONFIG : les valeurs par defaut, versionnees (D57).
    Config = @{
        LatencyWarnMs  = 80    # au-dela : latence moyenne (warn)
        LatencyErrorMs = 200   # au-dela : latence penible (error)
        # THE PORT WATCH: reading costs 2,8 ms, so it happens at every pass; WRITING is what is rationed. Nothing is
        # kept while the reserve is idle -- at 1 % occupancy a line every thirty seconds teaches no one anything.
        PortWatchPercent = 50   # written as soon as the occupancy reaches this share
        PortWatchAfterMinutes = 15   # and during this delay after a complaint from Windows (Tcpip 4231/4266)
        # ONE PROCESS HOLDING A HEAP OF PORTS. Measured on this computer: WSL's network host held 244 ephemeral ports
        # in the morning and 841 in the evening, never giving one back; on 14/09 it held 10 426, which took every port
        # lookup from 2 ms to 26 seconds and stretched an update of Vigie from 98 to 225 seconds. A normal process
        # holds ten to sixty. Below this count, nothing is said.
        PortHogPorts = 500
    }

    Parameters = @(
        @{ Key = 'LatencyWarnMs'; Label = 'Latence moyenne dès'; Type = 'int'; Unit = 'ms'; Min = 20; Max = 300; Step = 10
           Help = 'Au-delà de ce délai d''aller-retour, la latence passe en avertissement.' }
        @{ Key = 'LatencyErrorMs'; Label = 'Latence pénible dès'; Type = 'int'; Unit = 'ms'; Min = 100; Max = 1000; Step = 25
           Help = 'Au-delà de ce délai, la latence passe en erreur : jeu en ligne et visio pénibles.' }
        @{ Key = 'PortWatchPercent'; Label = 'Noter les ports dès'; Type = 'int'; Unit = '%'; Min = 10; Max = 100; Step = 5
           Help = 'Au-delà de cette part des ports réseau temporaires occupés, Vigie note l''occupation et les processus qui en tiennent le plus. 100 ne note plus rien hors incident.' }
        @{ Key = 'PortHogPorts'; Label = 'Signaler un processus dès'; Type = 'int'; Unit = 'ports'; Min = 100; Max = 8000; Step = 100
           Help = 'Au-delà de ce nombre de ports réseau temporaires tenus par un seul processus, la carte Réseau le nomme. Un processus ordinaire en tient dix à soixante ; au-delà de quelques milliers, toutes les connexions de l''ordinateur ralentissent.' }
        @{ Key = 'PortWatchAfterMinutes'; Label = 'Noter les ports après une plainte pendant'; Type = 'int'; Unit = 'min'; Min = 0; Max = 120; Step = 5
           Help = 'Après un événement « Ports réseau épuisés » de Windows, Vigie note l''occupation à chaque passage pendant ce délai, quel que soit le seuil. 0 désactive.' }
    )

    # SENTINELLES (CORE-WATCH) : les releves bon marche que l'app serveur execute en
    # permanence, meme sans session ouverte. Quand la valeur CHANGE, les cartes citees
    # sont recalculees -- et c'est leur bascule qui produit la notification (D54).
    # Le vocabulaire suit les autres cles de ce fichier : anglais, comme Label et Config.
    Sentinels = @(
        @{ Key = 'internet'; Label = 'Connexion Internet'; Seconds = 60; Cards = @('net') }
    )

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    Notifications = @(
        @{ Key = 'offline'; Label = 'Perte de connexion Internet'
           Card = 'net'; Field = 'connected'
           Droits = 'tous'; Critique = $false
           Help = 'Vigie ne joint plus Internet.' }
        @{ Key = 'wifi-weak'; Label = 'Lien Wi-Fi dégradé'
           Card = 'net'; Field = 'wifi'
           Droits = 'tous'; Critique = $false
           Help = 'La qualité du lien radio baisse.' }
        @{ Key = 'wifi-drops'; Label = 'Coupures Wi-Fi répétées'
           Card = 'net'; Field = 'wifiStability'
           Droits = 'tous'; Critique = $false
           Help = 'L''association Wi-Fi décroche.' }
        @{ Key = 'ports-low'; Label = 'Ports réseau bientôt épuisés'
           Card = 'net'; Field = 'ports'
           Droits = 'tous'; Critique = $false
           Help = 'Les ports réseau temporaires approchent de la limite de Windows : à la limite, plus aucune application ne peut ouvrir de connexion. La bulle nomme les processus qui en tiennent le plus.' }
        @{ Key = 'dns-ko'; Label = 'Résolution DNS en échec'
           Card = 'net'; Field = 'dns'
           Droits = 'admin'; Critique = $true
           Help = 'Les noms de domaine ne se résolvent plus.' }
    )

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        @{ Key = 'net'; Probe = 'net.probe.ps1'; Cards = @('net')
           Seconds = @{ default = 300 }; MaxSeconds = 60 }
    )
}
