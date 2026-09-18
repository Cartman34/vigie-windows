# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    # Le label et la description servent a la vue de gestion des modules.
    # L'activation ne vit PAS ici : elle est un choix de l'utilisateur, dans
    # config/modules.local.psd1 (jamais versionne).
    # La distribution par defaut est un reglage PERSONNEL : chaque compte a la sienne.
    # La carte depend donc de qui regarde, et son cache doit etre par compte (D113).
    PerAccount  = $true
    Label       = 'WSL'
    Description = 'Sous-système Linux : état et distribution.'

    # THE MEMORY OF THE VIRTUAL MACHINE above which the card says how to bound it (WSL-STATE).
    Config = @{
        VmMemoryWarnPct = 30
    }
    Parameters = @(
        @{ Key = 'VmMemoryWarnPct'; Label = 'Seuil de mémoire de WSL'; Type = 'int'; Unit = '% de la mémoire vive'; Min = 10; Max = 90; Step = 5
           Help = 'Au-delà de cette part de la mémoire vive prise par la machine virtuelle de WSL, la carte alerte et dit comment la borner dans .wslconfig.' }
    )

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    Notifications = @(
        @{ Key = 'wsl-down'; Label = 'WSL arrêté'
           Card = 'wsl'; Field = 'running'
           Droits = 'tous'; Critique = $false
           Help = 'La machine virtuelle WSL ne tourne plus.' }
        @{ Key = 'wsl-memory'; Label = 'WSL occupe beaucoup de mémoire'
           Card = 'wsl'; Field = 'vmMemory'
           Droits = 'tous'; Critique = $false
           Help = 'La machine virtuelle de WSL dépasse le seuil de mémoire. La carte dit comment la borner dans .wslconfig.' }
    )
}
