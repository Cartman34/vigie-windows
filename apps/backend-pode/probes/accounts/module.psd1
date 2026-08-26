@{
    # Declaration du MODULE (D48) : la carte des COMPTES de la machine.
    #
    # AUCUN parametre : la carte montre TOUS les comptes utilisateurs et UNIQUEMENT eux
    # (regle utilisateur). Un compte utilisateur, c'est un compte dont le profil a deja
    # servi a ouvrir une session -- les comptes d'outils, eux, n'en ouvrent jamais.
    Label       = 'Comptes'
    Description = 'Les comptes Windows de cet ordinateur, et ceux qui ont Vigie.'

    # Ce module ne signale aucun evenement : il decrit un etat.
    Notifications = @()
}
