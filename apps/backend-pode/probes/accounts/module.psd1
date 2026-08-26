@{
    # Declaration du MODULE (D48) : la carte des COMPTES de la machine.
    #
    # AUCUN parametre : la carte montre TOUS les comptes utilisateurs et UNIQUEMENT eux
    # (regle utilisateur). Un compte utilisateur, c'est un compte dont le profil a deja
    # servi a ouvrir une session -- les comptes d'outils, eux, n'en ouvrent jamais.
    Label       = 'Comptes'
    Description = 'Les comptes Windows de cet ordinateur, et ceux qui ont Vigie.'

    # Une operation lancee depuis cette carte (deploiement, installation d'une
    # dependance) peut durer et peut ECHOUER. « Le suivi des erreurs est primordial » :
    # son sort remonte donc comme n'importe quel autre constat (D82).
    Notifications = @(
        @{ Key = 'operation'; Label = 'Opération des comptes terminée ou en échec'
           Card = 'accounts'; Field = 'lastrun'
           Droits = 'admin'; Critique = $false
           Help = 'Le déploiement ou l''installation d''une dépendance vient de se terminer, ou a échoué.' }
        @{ Key = 'pwsh-manquant'; Label = 'PowerShell 7 absent ou limité à un compte'
           Card = 'accounts'; Field = 'pwsh'
           Droits = 'admin'; Critique = $true
           Help = 'Les tâches de démarrage lancent PowerShell 7 : sans lui, Vigie ne redémarre pas.' }
    )
}
