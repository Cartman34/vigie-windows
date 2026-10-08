# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Intent: declare what this folder of probes IS to the rest of Vigie -- its name, its
    # cards, how often they are computed and what they may notify. Nothing is measured here.
    # Usage: edit it to add a card, a setting or a notification to the module; the code that
    # measures lives in the .probe.ps1 beside it, and whether the module is enabled is the
    # user's choice, in config/modules.local.psd1.
    #
    # The MODULE's declaration (D48): a module IS this folder of probes.
    # The label and the description are what the module management view shows.
    # Whether it is enabled does NOT live here: that is the user's choice, in
    # config/modules.local.psd1, which is never versioned.
    # The default distribution is a PERSONAL setting: every account has its own.
    # The card therefore depends on who is looking, and its cache is per account (D113).
    PerAccount  = $true
    Label       = 'WSL'
    Description = 'Sous-système Linux : état et distribution.'

    # THE MEMORY OF THE VIRTUAL MACHINE above which the card says how to bound it (WSL-STATE).
    Config = @{
        VmMemoryWarnPct = 30
    }
    Parameters = @(
        @{ Key = 'VmMemoryWarnPct'; Label = 'Seuil de mémoire de WSL'; Type = 'int'; Unit = '% de la mémoire vive'; Min = 10; Max = 90; Step = 5
           Help = 'Au-delà de cette part de la mémoire vive prise par la machine virtuelle de WSL, la carte alerte et dit comment la borner dans .wslconfig.' }
    )

    # NOTIFICATIONS this module raises (D54): a named event, not a card's name.
    # What triggers the bubble is the quoted field changing state.
    Notifications = @(
        @{ Key = 'wsl-down'; Label = 'WSL arrêté'
           Card = 'wsl'; Field = 'running'
           Droits = 'tous'; Critique = $false
           Help = 'La machine virtuelle WSL ne tourne plus.' }
        @{ Key = 'wsl-memory'; Label = 'WSL occupe beaucoup de mémoire'
           Card = 'wsl'; Field = 'vmMemory'
           Droits = 'tous'; Critique = $false
           Help = 'La machine virtuelle de WSL dépasse le seuil de mémoire. La carte dit comment la borner dans .wslconfig.' }
    )

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        @{ Key = 'wsl'; Probe = 'wsl.probe.ps1'; Cards = @('wsl')
           Seconds = @{ default = 300 }; MaxSeconds = 60 }
    )
}
