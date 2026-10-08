# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): one module = this folder of probes.
    # Intent: say what this module is, what it computes and when, and what it may notify. The label and the
    # description serve the module management view. Usage: whether it is enabled does NOT live here: that is the
    # user's choice, in config/modules.local.psd1 (never versioned).
    Label       = 'Windows Update'
    Description = 'Verrouillage, historique et mises à jour du système.'

    # NOTIFICATIONS emitted by this module (D54): a named event, not a card's name. It is the flip of the field
    # that is cited which triggers the balloon.
    Notifications = @(
        @{ Key = 'wu-pending'; Label = 'Mises à jour à installer'
           Card = 'wu-pending'; Field = 'pending'
           Droits = 'admin'; Critique = $true
           Help = 'Windows a détecté des mises à jour non installées.' }
        @{ Key = 'wu-unlocked'; Label = 'Mises à jour automatiques réactivées'
           Card = 'wu-lock'; Field = 'autoUpdatesEnabled'
           Droits = 'admin'; Critique = $false
           Help = 'Le verrou de Windows Update n''est plus en place.' }
    )

    # SCHEDULED COMPUTATIONS (D124/D125). Measured 29/09: the pending list costs 10 s, and it is Windows' own offline
    # search that costs it -- twice in a row, in the same session, it costs the same. So it is never paid inside a
    # request: the server computes it in the background, four times a day, and everyone reads what is written.
    # The lock card fell from 8 417 ms to 1 077 ms the same day, so half an hour costs nothing.
    Refresh = @(
        @{ Key = 'pending'; Probe = 'pending.probe.ps1'; Cards = @('wu-pending')
           Seconds = @{ default = 21600 }; MaxSeconds = 120 }
        @{ Key = 'lock'; Probe = 'lock.probe.ps1'; Cards = @('wu-lock')
           Seconds = @{ default = 1800 }; MaxSeconds = 60 }
        @{ Key = 'history'; Probe = 'history.probe.ps1'; Cards = @('wu-history')
           Seconds = @{ default = 1800 }; MaxSeconds = 60 }
    )
}
