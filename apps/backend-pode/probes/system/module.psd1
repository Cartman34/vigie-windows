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
        DiskWarnGb    = 60   # espace libre (Go) sous lequel la carte Disque passe en warn
        # Analyse de la consommation : ce qui borne le DETAIL conserve (le parcours, lui,
        # est toujours complet). Plus la profondeur est grande, plus le resultat est fin
        # et gros ; le cout memoire de l'analyse est en topN^profondeur.
        DiskScanDepth = 3    # niveaux de detail conserves sous la racine
        DiskScanTop   = 10   # elements gardes par niveau (le reste est replie en « autres »)
    }

    # PARAMETRES : les cles de Config reglables dans le menu Parametres de l'app.
    Parameters = @(
        @{ Key = 'DiskWarnGb'; Label = 'Seuil d''alerte du disque'; Type = 'int'; Unit = 'Go'; Min = 20; Max = 500; Step = 10
           Help = 'En dessous de cet espace libre sur C:, la carte passe en avertissement.' }
        @{ Key = 'DiskScanDepth'; Label = 'Profondeur de l''analyse du disque'; Type = 'int'; Unit = 'niveaux'; Min = 1; Max = 6; Step = 1
           Help = 'Nombre de niveaux de sous-dossiers dont le détail est conservé. Le parcours reste complet : seul le détail affiché est borné.' }
        @{ Key = 'DiskScanTop'; Label = 'Éléments gardés par niveau'; Type = 'int'; Unit = 'éléments'; Min = 3; Max = 30; Step = 1
           Help = 'Nombre de dossiers et de fichiers les plus gros conservés à chaque niveau. Les autres sont regroupés dans une ligne « autres ».' }
    )

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    Notifications = @(
        @{ Key = 'disk-low'; Label = 'Espace disque faible'
           Card = 'storage'; Field = 'free'
           Help = 'Le disque système passe sous le seuil d''alerte.' }
        @{ Key = 'reboot'; Label = 'Redémarrage en attente'
           Card = 'os'; Field = 'rebootPending'
           Help = 'Windows attend un redémarrage pour finir une installation.' }
        @{ Key = 'ram-high'; Label = 'Mémoire vive saturée'
           Card = 'perf'; Field = 'ramUsed'
           Help = 'La mémoire utilisée dépasse le seuil : la machine va ralentir.' }
    )
}
