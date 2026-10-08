# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): one module = this folder of probes.
    # Intent: say what this module is, what it computes and when, and what it may notify. The label and the
    # description serve the module management view. Usage: whether it is enabled does NOT live here: that is the
    # user's choice, in config/modules.local.psd1 (never versioned).
    Label       = 'Outils & paquets'
    Description = 'Gestionnaires de paquets : winget, Chocolatey, pip.'

    # ONE CARD PER ACCOUNT (D109, D128): a manager installed in a profile belongs to that account. winget lives in
    # `AppData\Local\Microsoft\WindowsApps`, so what this card shows differs from one account to the next -- and
    # the rendering goes into state-cache.json, which is SHARED. Without this declaration, the first account to look
    # left its answer there for everyone, and the scheduler computed a single card for nobody in particular.
    PerAccount = $true

    # CONFIG: the default values, versioned (D57).
    Config = @{
        IgnoredPackages = @()   # patterns (the * joker is accepted) excluded from the update count
        PreselectAllUpdates = $true   # the updates window: everything ticked when it opens
    }

    Parameters = @(
        @{ Key = 'IgnoredPackages'; Label = 'Paquets ignorés'; Type = 'list'
           Help = 'Ces paquets ne comptent plus dans « mises à jour disponibles » (motifs, joker * accepté — ex. Microsoft.Teams*). L''équivalent d''un épinglage.' }
        @{ Key = 'PreselectAllUpdates'; Label = 'Tout cocher à l''ouverture'; Type = 'bool'
           Help = 'Dans la fenêtre « Mettre à jour » d''un gestionnaire, toutes les mises à jour sont cochées d''avance.' }
    )

    # NOTIFICATIONS emitted by this module (D54): a named event, not a card's name. It is the flip of the field
    # that is cited which triggers the balloon.
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
