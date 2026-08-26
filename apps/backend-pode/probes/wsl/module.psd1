@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    # Le label et la description servent a la vue de gestion des modules.
    # L'activation ne vit PAS ici : elle est un choix de l'utilisateur, dans
    # config/modules.local.psd1 (jamais versionne).
    Label       = 'WSL'
    Description = 'Sous-système Linux : état et distribution.'

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    Notifications = @(
        @{ Key = 'wsl-down'; Label = 'WSL arrêté'
           Card = 'wsl'; Field = 'running'
           Droits = 'tous'; Critique = $false
           Help = 'La machine virtuelle WSL ne tourne plus.' }
    )
}
