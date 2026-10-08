# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : la carte des COMPTES de la machine.
    #
    # AUCUN parametre : la carte montre TOUS les comptes utilisateurs et UNIQUEMENT eux
    # (regle utilisateur). Un compte utilisateur, c'est un compte dont le profil a deja
    # servi a ouvrir une session -- les comptes d'outils, eux, n'en ouvrent jamais.
    Label       = 'Comptes'
    Description = 'Les comptes Windows de cet ordinateur, et ceux qui ont Vigie.'

    # CETTE CARTE N'EST PAS LA MEME POUR TOUT LE MONDE : elle ecrit « (vous) » a cote d'un
    # nom, met ce compte en tete et n'affiche ses donnees qu'a lui. Son rendu est donc mis
    # en cache PAR COMPTE (cle « accounts.probe.ps1@<compte> »), sinon le premier a ouvrir
    # Vigie laisserait son « vous » a tous les suivants.
    PerAccount  = $true

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        @{ Key = 'accounts'; Probe = 'accounts.probe.ps1'; Cards = @('accounts')
           Seconds = @{ default = 3600 }; MaxSeconds = 60 }
    )
}
