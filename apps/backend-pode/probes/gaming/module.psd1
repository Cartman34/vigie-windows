# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    Label       = 'Gaming'
    Description = 'Le jeu en cours, sa part de ressources, et les applis qui pompent pendant.'

    # CONFIG : les valeurs par defaut, versionnees (D57).
    Config = @{
        GameGpuMinPct   = 15   # % GPU minimal pour considerer qu'un jeu tourne
        OtherCpuWarnPct = 1    # % CPU (normalise TOUS coeurs) : 1 % ici = une vraie charge
        OtherGpuWarnPct = 15   # % GPU d'une AUTRE appli qui declenche l'avertissement
        VramWarnPct     = 90   # % de VRAM occupee au-dela duquel on avertit
        GpuTempWarnC    = 87   # temperature GPU au-dela de laquelle on avertit
        BatteryDropWarnPct = 10 # points de batterie perdus pendant la partie avant d'alerter
    }

    # PARAMETRES : les cles de Config reglables dans le menu Parametres de l'app.
    Parameters = @(
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
        @{ Key = 'game'; Label = 'Jeu en cours'; Seconds = 60; Cards = @('gaming'); Card = 'gaming'; Field = 'game' }
        # Jouer sur batterie est la seule chose de cette carte qui ne peut pas attendre
        # qu'on regarde : quand la charge fond, on veut le savoir PENDANT la partie.
        @{ Key = 'game-battery'; Label = 'Décharge pendant une partie'; Seconds = 60; Cards = @('gaming'); Card = 'gaming'; Field = 'power' }
    )

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    Notifications = @(
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
