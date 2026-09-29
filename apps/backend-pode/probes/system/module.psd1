# @author Florent HAZARD <f.hazard@sowapps.com>
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
        # THE DISK ANALYSED WITHOUT BEING ASKED, when the free space falls hard. 10 GB in a day is a fall; a disk
        # that has been low for months is not. Zero switches it off.
        AutoScanDropGb   = 10   # Go perdus sur la fenetre ci-dessous avant de regarder de soi-meme
        AutoScanMinHours = 24   # la fenetre, et le temps minimal entre deux analyses automatiques
        # Alimentation d'un portable : ce qui distingue une charge normale d'un
        # chargeur qui ne suit pas.
        ChargeSlowW   = 10   # puissance de charge (W) sous laquelle la charge est jugee trop lente
        BatteryLowPct = 20   # charge restante (%) sous laquelle la batterie est signalee basse
    }

    # PARAMETRES : les cles de Config reglables dans le menu Parametres de l'app.
    Parameters = @(
        @{ Key = 'DiskWarnGb'; Label = 'Seuil d''alerte du disque'; Type = 'int'; Unit = 'Go'; Min = 20; Max = 500; Step = 10
           Help = 'En dessous de cet espace libre sur C:, la carte passe en avertissement.' }
        @{ Key = 'DiskScanDepth'; Label = 'Profondeur de l''analyse du disque'; Type = 'int'; Unit = 'niveaux'; Min = 1; Max = 6; Step = 1
           Help = 'Nombre de niveaux de sous-dossiers dont le détail est conservé. Le parcours reste complet : seul le détail affiché est borné.' }
        @{ Key = 'DiskScanTop'; Label = 'Éléments gardés par niveau'; Type = 'int'; Unit = 'éléments'; Min = 3; Max = 30; Step = 1
           Help = 'Nombre de dossiers et de fichiers les plus gros conservés à chaque niveau. Les autres sont regroupés dans une ligne « autres ».' }
        @{ Key = 'AutoScanDropGb'; Label = 'Analyse automatique du disque'; Type = 'int'; Unit = 'Go perdus'; Min = 0; Max = 200; Step = 5
           Help = 'Quand l''espace libre a chuté d''autant en 24 heures, Vigie analyse le disque d''elle-même, au plus une fois par jour et jamais pendant une partie. 0 éteint.' }
        @{ Key = 'ChargeSlowW'; Label = 'Seuil de charge lente'; Type = 'int'; Unit = 'W'; Min = 5; Max = 60; Step = 5
           Help = 'Branché au secteur et batterie loin d''être pleine : en dessous de cette puissance de charge, Vigie signale un chargeur sous-dimensionné.' }
        @{ Key = 'BatteryLowPct'; Label = 'Seuil de batterie basse'; Type = 'int'; Unit = '%'; Min = 5; Max = 50; Step = 5
           Help = 'Sur batterie, en dessous de cette charge restante, la carte Alimentation passe en avertissement.' }
    )

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    # SENTINELLES : les releves permanents de ce module.
    # Le sens du courant change quand on branche, quand on debranche, et quand le
    # chargeur cesse de suivre : trois faits que la carte doit dire SANS attendre
    # qu'on la rafraichisse. Une lecture WMI toutes les trente secondes.
    # MODES (D124): this one has its own reading -- 250 ms of processor load -- because no sentinel measures it.
    Modes = @(
        @{ Key = 'calm'; Label = 'Machine au calme'; Script = 'calm.mode.ps1'; Off = @('non', 'inconnu') }
    )

    # SCHEDULED COMPUTATIONS (D124). Measured 29/09: one pass of this probe costs 1 385 ms.
    # During a game this card says whether the machine is at its ceiling; outside one, five minutes
    # are enough to keep the memory and processor history alive with no session open.
    Refresh = @(
        @{ Key = 'perf'; Probe = 'perf.probe.ps1'; Cards = @('perf')
           Seconds = @{ default = 60; game = 30 }; MaxSeconds = 60 }
        @{ Key = 'disk'; Probe = 'disk.probe.ps1'; Cards = @('storage')
           Seconds = @{ default = 300 }; MaxSeconds = 120 }
        @{ Key = 'events'; Probe = 'events.probe.ps1'; Cards = @('events')
           Seconds = @{ default = 300 }; MaxSeconds = 60 }
        @{ Key = 'os'; Probe = 'os.probe.ps1'; Cards = @('os')
           Seconds = @{ default = 3600 }; MaxSeconds = 60 }
        @{ Key = 'power'; Probe = 'power.probe.ps1'; Cards = @('power')
           Seconds = @{ default = 300 }; MaxSeconds = 60 }
    )

    Sentinels = @(
        @{ Key = 'power'; Label = 'Sens du courant'; Seconds = 30; Cards = @('power') }
    )

    Notifications = @(
        @{ Key = 'disk-low'; Label = 'Espace disque faible'
           Card = 'storage'; Field = 'free'
           Droits = 'tous'; Critique = $false
           Help = 'Le disque système passe sous le seuil d''alerte.' }
        @{ Key = 'reboot'; Label = 'Redémarrage en attente'
           Card = 'os'; Field = 'rebootPending'
           Droits = 'tous'; Critique = $false
           Help = 'Windows attend un redémarrage pour finir une installation.' }
        @{ Key = 'ram-high'; Label = 'Mémoire vive saturée'
           Card = 'perf'; Field = 'ramUsed'
           Droits = 'tous'; Critique = $false
           Help = 'La mémoire utilisée dépasse le seuil : la machine va ralentir.' }
        @{ Key = 'commit-high'; Label = 'Mémoire engagée proche de sa limite'
           Card = 'perf'; Field = 'commit'
           Droits = 'tous'; Critique = $false
           Help = 'La mémoire promise aux applications approche de sa limite : Windows va refuser des allocations et alerter de saturation. La bulle nomme les applications qui en occupent le plus.' }
        @{ Key = 'system-errors'; Label = 'Erreur système'
           Card = 'events'; Field = 'known'
           Droits = 'tous'; Critique = $false
           Help = 'Windows a consigné une erreur grave : ports réseau ou mémoire épuisés, arrêt inattendu, pilote graphique, disque, matériel. La bulle la nomme.' }
        @{ Key = 'power-under'; Label = 'Machine sous-alimentée'
           Card = 'power'; Field = 'under'
           Droits = 'tous'; Critique = $false
           Help = 'Branchée au secteur, la machine se décharge quand même ou charge trop lentement : le chargeur ne couvre pas la consommation.' }
    )
}
