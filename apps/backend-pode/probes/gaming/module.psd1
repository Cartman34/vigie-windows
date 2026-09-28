# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    Label       = 'Gaming'
    Description = 'Le jeu en cours, sa part de ressources, et les applis qui pompent pendant.'

    # CONFIG : les valeurs par defaut, versionnees (D57).
    Config = @{
        GameGpuMinPct   = 15   # % GPU minimal pour considerer qu'un jeu tourne
        # 8 %, and no longer 1 %: the share is normalised over ALL cores, so 1 % was a sixth of one core on this
        # computer -- the window compositor crossed it just by drawing the game, and the alert fired fourteen times
        # on 16/09 for nothing. 8 % is more than one core busy, which deserves the word (owner, 28/09).
        OtherCpuWarnPct = 8    # % CPU (normalise TOUS coeurs)
        OtherGpuWarnPct = 15   # % GPU d'une AUTRE appli qui declenche l'avertissement
        VramWarnPct     = 90   # % de VRAM occupee au-dela duquel on avertit
        GpuTempWarnC    = 87   # temperature GPU au-dela de laquelle on avertit
        BatteryDropWarnPct = 10 # points de batterie perdus pendant la partie avant d'alerter
        # THE RECAP OPENS BY ITSELF at the end of a session, unless the owner says otherwise (on by default, 28/09).
        OpenRecapAtEnd  = $true
    }

    # PARAMETRES : les cles de Config reglables dans le menu Parametres de l'app.
    Parameters = @(
        @{ Key = 'OpenRecapAtEnd'; Label = 'Ouvrir le récapitulatif à la fin d''une partie'; Type = 'bool'
           Help = 'À la fin d''une partie, Vigie ouvre son récapitulatif. La fenêtre se ferme d''elle-même si une nouvelle partie commence, ou après dix minutes sans être regardée. Éteint, Vigie se contente d''une notification.' }
        @{ Key = 'GameGpuMinPct'; Label = 'Seuil de détection du jeu'; Type = 'int'; Unit = '% GPU'; Min = 5; Max = 80; Step = 5
           Help = 'En dessous de cette utilisation GPU, aucun processus n''est considéré comme un jeu.' }
        @{ Key = 'OtherCpuWarnPct'; Label = 'Alerte CPU des autres applis'; Type = 'int'; Unit = '%'; Min = 1; Max = 50; Step = 1
           Help = 'Pendant un jeu, une autre application au-delà de ce CPU déclenche un avertissement.' }
        @{ Key = 'OtherGpuWarnPct'; Label = 'Alerte GPU des autres applis'; Type = 'int'; Unit = '%'; Min = 1; Max = 80; Step = 1
           Help = 'Pendant un jeu, une autre application au-delà de ce GPU déclenche un avertissement.' }
        @{ Key = 'VramWarnPct'; Label = 'Alerte de VRAM occupée'; Type = 'int'; Unit = '%'; Min = 50; Max = 100; Step = 5
           Help = 'Au-delà de ce remplissage de la mémoire vidéo, la carte avertit : saccades probables.' }
        @{ Key = 'GpuTempWarnC'; Label = 'Alerte de température GPU'; Type = 'int'; Unit = '°C'; Min = 60; Max = 95; Step = 1
           Help = 'Au-delà de cette température, la carte graphique va brider ses fréquences.' }
        @{ Key = 'BatteryDropWarnPct'; Label = 'Alerte de décharge en jeu'; Type = 'int'; Unit = '%'; Min = 3; Max = 50; Step = 1
           Help = 'Pendant une partie sur batterie, alerte dès que la charge a baissé de tant de points depuis le début.' }
    )

    # RESIDENT : ce qui vit avec l app serveur pour savoir, a la seconde, qu un jeu a
    # demarre. Il s abonne aux demarrages de processus au lieu de mesurer le GPU.
    Residents = @(
        @{ Key = 'game'; Label = 'Détection des jeux' }
    )

    # SENTINELLES : les releves permanents de ce module. Voir
    # doc/progress/targeting/surveillance.md.
    Sentinels = @(
        # Ce que le resident a trouve : le jeu en cours, ou son absence.
        @{ Key = 'game'; Label = 'Jeu en cours'; Seconds = 60; Cards = @('gaming') }
        # Jouer sur batterie est la seule chose de cette carte qui ne peut pas attendre
        # qu'on regarde : quand la charge fond, on veut le savoir PENDANT la partie.
        @{ Key = 'game-battery'; Label = 'Décharge pendant une partie'; Seconds = 60; Cards = @('gaming') }
    )

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    Notifications = @(
        @{ Key = 'game-recap'; Label = 'Récapitulatif de partie'
           Card = 'gaming'; Field = 'last-session'
           Droits = 'tous'; Critique = $false
           Help = 'À la fin d''une partie, propose d''ouvrir son récapitulatif. Sans effet si l''ouverture automatique est activée.' }
        @{ Key = 'gpu-temp'; Label = 'Température GPU élevée'
           Card = 'gaming'; Field = 'gpu-temp'
           Droits = 'tous'; Critique = $false
           Help = 'La carte graphique chauffe au-delà du seuil, ou se bride.' }
        @{ Key = 'vram-full'; Label = 'Mémoire graphique saturée'
           Card = 'gaming'; Field = 'vram'
           Droits = 'tous'; Critique = $false
           Help = 'La VRAM est pleine : saccades à prévoir en jeu.' }
        @{ Key = 'hogs'; Label = 'Applications gourmandes pendant une partie'
           Card = 'gaming'; Field = 'hogs'
           Droits = 'tous'; Critique = $false
           Help = 'Une application consomme beaucoup pendant que le jeu tourne.' }
        @{ Key = 'battery'; Label = 'Partie sur batterie'
           Card = 'gaming'; Field = 'power'
           Droits = 'tous'; Critique = $false
           Help = 'Sur batterie, processeur et carte graphique sont bridés.' }
    )
}
