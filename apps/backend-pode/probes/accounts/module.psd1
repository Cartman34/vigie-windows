@{
    # Declaration du MODULE (D48) : la carte des COMPTES de la machine.
    Label       = 'Comptes'
    Description = "Les comptes Windows de cet ordinateur et ceux qui ont Vigie."

    Config = @{
        # Un compte qui n'a pas ouvert de session depuis longtemps merite d'etre signale :
        # c'est souvent un compte oublie, parfois un compte a retirer.
        DormantDays          = 90
        # Comptes TECHNIQUES (sans profil humain : bacs a sable, comptes de service) :
        # masques par defaut, car ils encombrent une carte qui parle de personnes. Leur
        # nombre reste dit -- rien ne disparait en silence.
        ShowTechnicalAccounts = $false
    }
    Parameters = @(
        @{ Key = 'DormantDays'; Label = 'Compte dormant apres'; Type = 'int'; Unit = 'jours'; Min = 30; Max = 365; Step = 30
           Help = "Au-dela de cette duree sans ouverture de session, le compte est signale comme dormant." }
        @{ Key = 'ShowTechnicalAccounts'; Label = 'Afficher les comptes techniques'; Type = 'bool'
           Help = "Les comptes sans profil humain (bacs a sable, comptes de service) sont masques par defaut." }
    )
}
