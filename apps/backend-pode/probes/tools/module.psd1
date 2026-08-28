@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    # Le label et la description servent a la vue de gestion des modules.
    # L'activation ne vit PAS ici : elle est un choix de l'utilisateur, dans
    # config/modules.local.psd1 (jamais versionne).
    Label       = 'Outils & paquets'
    Description = 'Gestionnaires de paquets : winget, Chocolatey, pip.'

    # CONFIG : les valeurs par defaut, versionnees (D57).
    Config = @{
        IgnoredPackages = @()   # motifs (joker * accepte) exclus du decompte des MAJ
        PreselectAllUpdates = $true   # fenetre de MAJ : tout coche a l'ouverture
    }

    Parameters = @(
        @{ Key = 'IgnoredPackages'; Label = 'Paquets ignorés'; Type = 'list'
           Help = 'Ces paquets ne comptent plus dans « mises à jour disponibles » (motifs, joker * accepté — ex. Microsoft.Teams*). L''équivalent d''un épinglage.' }
        @{ Key = 'PreselectAllUpdates'; Label = 'Tout cocher à l''ouverture'; Type = 'bool'
           Help = 'Dans la fenêtre « Mettre à jour » d''un gestionnaire, toutes les mises à jour sont cochées d''avance.' }
    )

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
    Notifications = @(
        @{ Key = 'pkg-updates'; Label = 'Mises à jour de logiciels disponibles'
           Card = ''; Field = 'updates'
           Droits = 'admin'; Critique = $false
           Help = 'Un gestionnaire de paquets signale des mises à jour.' }
    )
}
