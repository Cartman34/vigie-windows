# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : la carte du DEPLOIEMENT de Vigie.
    #
    # PAS DE « PerAccount » ICI, ET C'EST TOUT L'INTERET. Cette carte ne parle de personne
    # en particulier : elle compare une installation a sa source. Elle peut donc etre
    # differee vers le rafraichissement de fond, alors qu'une carte par compte est
    # toujours calculee dans la requete -- ce qui faisait durer /state jusqu'a 52 secondes.
    # LE GROUPE : cette carte se lit avec celle des comptes, pas dans un groupe a elle.
    Theme       = 'accounts'
    # SURVEILLANCE (CORE-WATCH) : a quelle cadence revoir ces sondes quand personne
    # ne regarde. Un commit ou une version publiee : quelques minutes de retard ne genent personne.
    Surveillance = 'normale'
    Label       = 'Déploiement'
    Description = 'Ce que lancent les autres comptes : version en place, interpréteur, tâches de démarrage.'

    # Une operation lancee depuis cette carte (deploiement, installation d'une
    # dependance) peut durer et peut ECHOUER. « Le suivi des erreurs est primordial » :
    # son sort remonte donc comme n'importe quel autre constat (D82).
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
}
