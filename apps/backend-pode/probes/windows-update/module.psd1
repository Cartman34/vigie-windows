# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    # Le label et la description servent a la vue de gestion des modules.
    # L'activation ne vit PAS ici : elle est un choix de l'utilisateur, dans
    # config/modules.local.psd1 (jamais versionne).
    Label       = 'Windows Update'
    Description = 'Verrouillage, historique et mises à jour du système.'

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
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
    )
}
