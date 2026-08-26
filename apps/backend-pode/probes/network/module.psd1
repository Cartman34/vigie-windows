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
    }

    Parameters = @(
        @{ Key = 'LatencyWarnMs'; Label = 'Latence moyenne dès'; Type = 'int'; Unit = 'ms'; Min = 20; Max = 300; Step = 10
           Help = 'Au-delà de ce délai d''aller-retour, la latence passe en avertissement.' }
        @{ Key = 'LatencyErrorMs'; Label = 'Latence pénible dès'; Type = 'int'; Unit = 'ms'; Min = 100; Max = 1000; Step = 25
           Help = 'Au-delà de ce délai, la latence passe en erreur : jeu en ligne et visio pénibles.' }
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
        @{ Key = 'dns-ko'; Label = 'Résolution DNS en échec'
           Card = 'net'; Field = 'dns'
           Droits = 'admin'; Critique = $true
           Help = 'Les noms de domaine ne se résolvent plus.' }
    )
}
