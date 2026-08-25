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
    }

    Parameters = @(
        @{ Key = 'IgnoredPackages'; Label = 'Paquets ignorés'; Type = 'list'
           Help = 'Ces paquets ne comptent plus dans « mises à jour disponibles » (motifs, joker * accepté — ex. Microsoft.Teams*). L''équivalent d''un épinglage.' }
    )
}
