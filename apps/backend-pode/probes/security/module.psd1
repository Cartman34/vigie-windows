# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): one module = this folder of probes.
    # Intent: say what this module is, what it computes and when, and what it may notify. The label and the
    # description serve the module management view. Usage: whether it is enabled does NOT live here: that is the
    # user's choice, in config/modules.local.psd1 (never versioned).
    Label       = 'Sécurité'
    Description = 'Antivirus, pare-feu et sécurité de la virtualisation.'

    # NOTIFICATIONS emitted by this module (D54): a named event, not a card's name. It is the flip of the field
    # that is cited which triggers the balloon.
    Notifications = @(
        @{ Key = 'av-off'; Label = 'Antivirus inactif'
           Card = 'antivirus'; Field = 'enabled'
           Droits = 'admin'; Critique = $true
           Help = 'La protection en temps réel n''est plus active.' }
        @{ Key = 'av-old'; Label = 'Antivirus non à jour'
           Card = 'antivirus'; Field = 'upToDate'
           Droits = 'admin'; Critique = $true
           Help = 'Les signatures de l''antivirus datent.' }
        @{ Key = 'fw-domain'; Label = 'Pare-feu : profil Domaine coupé'
           Card = 'firewall'; Field = 'domain'
           Droits = 'admin'; Critique = $true
           Help = 'Le pare-feu est désactivé sur le profil Domaine.' }
        @{ Key = 'fw-private'; Label = 'Pare-feu : profil Privé coupé'
           Card = 'firewall'; Field = 'private'
           Droits = 'admin'; Critique = $true
           Help = 'Le pare-feu est désactivé sur le profil Privé.' }
        @{ Key = 'fw-public'; Label = 'Pare-feu : profil Public coupé'
           Card = 'firewall'; Field = 'public'
           Droits = 'admin'; Critique = $true
           Help = 'Le pare-feu est désactivé sur le profil Public.' }
        @{ Key = 'vbs-off'; Label = 'Sécurité par virtualisation coupée'
           Card = 'vbs'; Field = 'vbs'
           Droits = 'admin'; Critique = $false
           Help = 'VBS n''est plus activée.' }
    )

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        @{ Key = 'defender'; Probe = 'defender.probe.ps1'; Cards = @('antivirus')
           Seconds = @{ default = 1800 }; MaxSeconds = 60 }
        @{ Key = 'firewall'; Probe = 'firewall.probe.ps1'; Cards = @('firewall')
           Seconds = @{ default = 1800 }; MaxSeconds = 60 }
        @{ Key = 'vbs'; Probe = 'vbs.probe.ps1'; Cards = @('vbs')
           Seconds = @{ default = 1800 }; MaxSeconds = 60 }
    )
}
