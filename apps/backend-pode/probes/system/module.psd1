@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    # Le label et la description servent a la vue de gestion des modules.
    # L'activation ne vit PAS ici : elle est un choix de l'utilisateur, dans
    # config/modules.local.psd1 (jamais versionne).
    Label       = 'Système'
    Description = 'Windows, ressources et disque.'

    # CONFIG : les valeurs par defaut, versionnees (D57). Une sonde les lit via
    # Get-ModuleSetting, qui applique d'abord l'eventuelle surcharge utilisateur.
    Config = @{
        DiskWarnGb = 60    # espace libre (Go) sous lequel la carte Disque passe en warn
    }

    # PARAMETRES : les cles de Config reglables dans le menu Parametres de l'app.
    Parameters = @(
        @{ Key = 'DiskWarnGb'; Label = 'Seuil d''alerte du disque'; Type = 'int'; Unit = 'Go'; Min = 20; Max = 500; Step = 10
           Help = 'En dessous de cet espace libre sur C:, la carte passe en avertissement.' }
    )
}
