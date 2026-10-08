# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): Vigie's DEPLOYMENT card.
    #
    # NO "PerAccount" HERE, AND THAT IS THE WHOLE POINT. This card speaks of nobody in particular: it compares an
    # installation with its source. So it can be deferred to the background refresh, whereas a per-account card is
    # always computed inside the request -- which made /state last up to 52 seconds.
    # THE GROUP: this card is read together with the accounts one, not in a group of its own.
    Theme       = 'accounts'
    Label       = 'Déploiement'
    Description = 'Ce que lancent les autres comptes : version en place, interpréteur, tâches de démarrage.'

    # An operation started from this card (a deployment, the installation of a dependency) can last and can FAIL.
    # "Tracking the errors is paramount": so its fate is reported like any other observation (D82).
    Notifications = @(
        @{ Key = 'operation'; Label = 'Déploiement terminé ou en échec'
           Card = 'deployment'; Field = 'lastrun'
           Droits = 'admin'; Critique = $false
           Help = 'Le déploiement ou l''installation d''une dépendance vient de se terminer, ou a échoué.' }
        @{ Key = 'pwsh-manquant'; Label = 'PowerShell 7 absent ou limité à un compte'
           Card = 'deployment'; Field = 'pwsh'
           Droits = 'admin'; Critique = $true
           Help = 'Les tâches de démarrage lancent PowerShell 7 : sans lui, Vigie ne redémarre pas.' }
    )

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        @{ Key = 'deployment'; Probe = 'deployment.probe.ps1'; Cards = @('deployment')
           Seconds = @{ default = 1800 }; MaxSeconds = 120 }
    )
}
