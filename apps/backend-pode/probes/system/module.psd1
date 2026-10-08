# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): one module = this folder of probes.
    # Intent: say what this module is, what it computes and when, and what it may notify. The label and the
    # description serve the module management view. Usage: whether it is enabled does NOT live here: that is the
    # user's choice, in config/modules.local.psd1 (never versioned).
    Label       = 'Système'
    Description = 'Windows, ressources et disque.'

    # CONFIG: the default values, versioned (D57). A probe reads them through Get-ModuleSetting, which applies the
    # user's override first if there is one.
    Config = @{
        DiskWarnGb    = 60   # the free space (GB) below which the Disc card goes to warn
        # The analysis of what the space is used by: what bounds the DETAIL that is kept (the walk itself is
        # always complete). The greater the depth, the finer and the larger the result; the memory cost of the
        # analysis is topN^depth.
        DiskScanDepth = 3    # levels of detail kept under the root
        DiskScanTop   = 10   # elements kept per level (the rest is folded into an "others" line)
        # THE DISK ANALYSED WITHOUT BEING ASKED, when the free space falls hard. 10 GB in a day is a fall; a disk
        # that has been low for months is not. Zero switches it off.
        AutoScanDropGb   = 10   # GB lost over the window below before looking of its own accord
        AutoScanMinHours = 24   # the window, and the minimum time between two automatic analyses
        # The power supply of a laptop: what tells a normal charge from a charger that is not keeping up.
        ChargeSlowW   = 10   # the charging power (W) below which the charge is judged too slow
        BatteryLowPct = 20   # the remaining charge (%) below which the battery is reported as low
        # A FACT FROM THE LOG STOPS BEING HIGHLIGHTED (D127). Past this delay it stays in the detail, findable, but
        # carries the card's status no longer -- a blue screen included. What is CONFIRMED to be still happening
        # carries it whatever its age, and what the measure DENIES never carries it. 0 declasses nothing.
        EventHighlightMinutes = 60
    }

    # PARAMETERS: the Config keys that can be set from the app's Settings menu.
    Parameters = @(
        @{ Key = 'EventHighlightMinutes'; Label = 'Mettre en avant une erreur du journal pendant'; Type = 'int'; Unit = 'min'; Min = 0; Max = 1440; Step = 15
           Help = 'Passé ce délai, une erreur du journal Windows reste dans le détail mais ne met plus la carte en défaut. Une erreur dont Vigie vérifie qu''elle dure encore la met en défaut quel que soit son âge ; une erreur démentie par la mesure, jamais.' }
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

    # NOTIFICATIONS emitted by this module (D54): a named event, not a card's name. It is the flip of the field
    # that is cited which triggers the balloon.
    # SENTINELS: this module's permanent readings.
    # The direction of the current changes when one plugs in, when one unplugs, and when the charger stops
    # keeping up: three facts the card must state WITHOUT waiting to be refreshed. One WMI reading every thirty
    # seconds.
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
