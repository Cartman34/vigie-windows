@{
    # Declaration du MODULE (D48) : un module = ce dossier de sondes.
    # Le label et la description servent a la vue de gestion des modules.
    # L'activation ne vit PAS ici : elle est un choix de l'utilisateur, dans
    # config/modules.local.psd1 (jamais versionne).
    Label       = 'Sécurité'
    Description = 'Antivirus, pare-feu et sécurité de la virtualisation.'

    # NOTIFICATIONS emises par ce module (D54) : un evenement nomme, pas un nom de
    # carte. C'est la bascule du champ cite qui declenche la bulle.
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
}
