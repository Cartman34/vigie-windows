# @author Florent HAZARD <f.hazard@sowapps.com>
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

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        # THE CARDS THIS PROBE REALLY PRODUCES: one per package manager present, and "pkg-none" only when there is
        # none at all. Only "pkg-none" was declared, so the cards actually shown had neither interval nor freshness:
        # they could not say their age, nor report being late (seen on 30/09).
        @{ Key = 'packages'; Probe = 'packages.probe.ps1'
           Cards = @('pkg-winget', 'pkg-choco', 'pkg-scoop', 'pkg-npm', 'pkg-pnpm', 'pkg-yarn',
                     'pkg-pip', 'pkg-pipx', 'pkg-cargo', 'pkg-gem', 'pkg-dotnet', 'pkg-none')
           Seconds = @{ default = 86400 }; MaxSeconds = 300; OnlyWhen = 'calm' }
    )
}
