@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    Label       = 'Jeux'
    Description = 'Le jeu en cours, sa part de ressources, et les applis qui pompent pendant.'

    # CONFIG : les valeurs par defaut, versionnees (D57).
    Config = @{
        GameGpuMinPct   = 15   # % GPU minimal pour considerer qu'un jeu tourne
        OtherCpuWarnPct = 1    # % CPU (normalise TOUS coeurs) : 1 % ici = une vraie charge
        OtherGpuWarnPct = 15   # % GPU d'une AUTRE appli qui declenche l'avertissement
    }

    # PARAMETRES : les cles de Config reglables dans le menu Parametres de l'app.
    Parameters = @(
        @{ Key = 'GameGpuMinPct'; Label = 'Seuil de détection du jeu'; Type = 'int'; Unit = '% GPU'
           Help = 'En dessous de cette utilisation GPU, aucun processus n''est considéré comme un jeu.' }
        @{ Key = 'OtherCpuWarnPct'; Label = 'Alerte CPU des autres applis'; Type = 'int'; Unit = '%'
           Help = 'Pendant un jeu, une autre application au-delà de ce CPU déclenche un avertissement.' }
        @{ Key = 'OtherGpuWarnPct'; Label = 'Alerte GPU des autres applis'; Type = 'int'; Unit = '%'
           Help = 'Pendant un jeu, une autre application au-delà de ce GPU déclenche un avertissement.' }
    )
}
