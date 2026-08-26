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
}
