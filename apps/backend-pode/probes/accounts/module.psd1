@{
    # Declaration du MODULE (D48) : la carte des COMPTES de la machine.
    Label       = 'Comptes'
    Description = 'Les comptes Windows de cet ordinateur, et ceux qui ont Vigie.'

    Config = @{
        # Un compte sans session depuis longtemps merite d'etre signale : c'est souvent un
        # compte oublie, parfois un compte a retirer.
        DormantDays           = 90
        # Comptes TECHNIQUES (profil jamais utilise : bacs a sable, comptes de service) :
        # masques par defaut, car ils encombrent une carte qui parle de personnes. Leur
        # nombre reste dit -- rien ne disparait en silence.
        ShowTechnicalAccounts = $false
        # Comptes que l'utilisateur ne veut pas voir. Meme principe que les paquets
        # ignores : masques, jamais silencieux.
        HiddenAccounts        = @()
    }
    Parameters = @(
        @{ Key = 'DormantDays'; Label = 'Compte dormant après'; Type = 'int'; Unit = 'jours'; Min = 30; Max = 365; Step = 30
           Help = 'Au-delà de cette durée sans ouverture de session, le compte est signalé comme dormant.' }
        @{ Key = 'ShowTechnicalAccounts'; Label = 'Afficher les comptes techniques'; Type = 'bool'
           Help = 'Les comptes dont le profil n''a jamais servi (bacs à sable, comptes de service) sont masqués par défaut.' }
        @{ Key = 'HiddenAccounts'; Label = 'Comptes à ne pas afficher'; Type = 'list'
           Help = 'Noms de comptes à masquer sur la carte. Leur nombre reste indiqué.' }
    )

    # Ce module ne signale aucun evenement : il decrit un etat.
    Notifications = @()
}
