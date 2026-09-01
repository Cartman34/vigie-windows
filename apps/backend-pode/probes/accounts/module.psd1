# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : la carte des COMPTES de la machine.
    #
    # AUCUN parametre : la carte montre TOUS les comptes utilisateurs et UNIQUEMENT eux
    # (regle utilisateur). Un compte utilisateur, c'est un compte dont le profil a deja
    # servi a ouvrir une session -- les comptes d'outils, eux, n'en ouvrent jamais.
    # SURVEILLANCE (CORE-WATCH) : a quelle cadence revoir ces sondes quand personne
    # ne regarde. Les comptes Windows changent rarement.
    Surveillance = 'basse'
    Label       = 'Comptes'
    Description = 'Les comptes Windows de cet ordinateur, et ceux qui ont Vigie.'

    # CETTE CARTE N'EST PAS LA MEME POUR TOUT LE MONDE : elle ecrit « (vous) » a cote d'un
    # nom, met ce compte en tete et n'affiche ses donnees qu'a lui. Son rendu est donc mis
    # en cache PAR COMPTE (cle « comptes.probe.ps1@<compte> »), sinon le premier a ouvrir
    # Vigie laisserait son « vous » a tous les suivants.
    PerAccount  = $true

}
