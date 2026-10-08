# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): one module = this folder of probes.
    # Intent: say what this module is, what it computes and when, and what it may notify. The label and the
    # description serve the module management view. Usage: whether it is enabled does NOT live here: that is the
    # user's choice, in config/modules.local.psd1 (never versioned).
    Label       = 'Réseau'
    Description = 'Connexion, Wi-Fi, adresses et débit.'

    # CONFIG: the default values, versioned (D57).
    Config = @{
        LatencyWarnMs  = 80    # beyond this: a middling latency (warn)
        LatencyErrorMs = 200   # beyond this: a painful latency (error)
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

    # SENTINELS (CORE-WATCH): the cheap readings the server app runs permanently, even with no session open. When
    # the value CHANGES, the cards that are cited are recomputed -- and it is their flip that produces the
    # notification (D54).
    # The vocabulary follows the other keys of this file: English, like Label and Config.
    Sentinels = @(
        @{ Key = 'internet'; Label = 'Connexion Internet'; Seconds = 60; Cards = @('net') }
    )

    # NOTIFICATIONS emitted by this module (D54): a named event, not a card's name. It is the flip of the field
    # that is cited which triggers the balloon.
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
