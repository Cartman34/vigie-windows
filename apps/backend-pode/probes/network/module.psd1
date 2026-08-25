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
}
