@{
    # ---------------------------------------------------------------------------
    # MODELE de configuration LOCALE. Copie ce fichier en 'config.local.psd1'
    # (meme dossier) et adapte-le : il est ignore par git et ne quitte pas ta machine.
    #
    #     Copy-Item backend/config.local.sample.psd1 backend/config.local.psd1
    #
    # Ne mets ici QUE les valeurs qui ne peuvent pas etre generiques, c'est-a-dire
    # celles qui dependent de la machine. Toute cle presente ici ecrase celle de
    # config.psd1 ; toute cle absente garde la valeur de config.psd1.
    #
    # N'y mets JAMAIS de secret : le jeton d'API vit dans backend/.secrets/.
    # ---------------------------------------------------------------------------

    # Dossier des scripts d'administration externes (audit-update-tasks.ps1,
    # update-mode.ps1). Son dossier PARENT sert de racine d'administration
    # (toggle-vbs.ps1, toggle-hvci.ps1, action "ouvrir le dossier").
    # ToolsPath = 'C:\chemin\vers\LocalAgentAdmin\tools'

    # Decommente seulement si le port par defaut est deja pris sur cette machine.
    # Port = 47601
}
