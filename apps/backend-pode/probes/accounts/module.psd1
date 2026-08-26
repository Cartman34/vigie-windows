@{
    # Declaration du MODULE (D48) : la carte des COMPTES de la machine.
    Label       = 'Comptes'
    Description = "Les comptes Windows de cet ordinateur et ceux qui ont Vigie."

    Config = @{
        # Un compte qui n'a pas ouvert de session depuis longtemps merite d'etre signale
        # comme dormant : c'est souvent un compte oublie, parfois un compte a retirer.
        DormantDays = 90
    }
    Parameters = @(
        @{ Key = 'DormantDays'; Label = 'Compte dormant après'; Type = 'int'; Unit = 'jours'; Min = 30; Max = 365; Step = 30
           Help = "Au-delà de cette durée sans ouverture de session, le compte est signalé comme dormant." }
    )
}
