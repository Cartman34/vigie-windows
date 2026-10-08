# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): the card of the computer's ACCOUNTS.
    #
    # NO setting: the card shows ALL the user accounts and ONLY those, as the owner asked.
    # A user account is one whose profile has already been used to open a session -- a
    # tool's account never opens one.
    Label       = 'Comptes'
    Description = 'Les comptes Windows de cet ordinateur, et ceux qui ont Vigie.'

    # THIS CARD IS NOT THE SAME FOR EVERYONE: it marks one name as being the reader's own, puts that
    # account first, and shows its data to that account alone. Its rendering is therefore
    # cached PER ACCOUNT (key "accounts.probe.ps1@<account>"), or the first person to open
    # Vigie would leave that mark on everyone after them.
    PerAccount  = $true

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        @{ Key = 'accounts'; Probe = 'accounts.probe.ps1'; Cards = @('accounts')
           Seconds = @{ default = 3600 }; MaxSeconds = 60 }
    )
}
