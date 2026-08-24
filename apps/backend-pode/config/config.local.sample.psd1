@{
    # ---------------------------------------------------------------------------
    # MODELE de configuration LOCALE. Copie ce fichier en 'config.local.psd1'
    # (meme dossier) et adapte-le : il est ignore par git et ne quitte pas ta machine.
    #
    #     Copy-Item apps/backend-pode/config/config.local.sample.psd1 apps/backend-pode/config/config.local.psd1
    #
    # Ne mets ici QUE les valeurs qui ne peuvent pas etre generiques, c'est-a-dire
    # celles qui dependent de la machine. Toute cle presente ici ecrase celle de
    # config.psd1 ; toute cle absente garde la valeur de config.psd1.
    #
    # N'y mets JAMAIS de secret : le jeton d'API vit dans backend/.secrets/.
    # ---------------------------------------------------------------------------

    # Dossier de scripts d'administration externes. FACULTATIF.
    # Le verrouillage de Windows Update et son audit sont natifs : ils fonctionnent SANS
    # cette cle. Elle ne sert plus qu'aux bascules VBS / HVCI et a l'action "ouvrir le
    # dossier", qui utilisent le dossier PARENT comme racine d'administration.
    # Si le dossier contient update-mode.ps1, ce script reste prefere pour le verrou.
    # ToolsPath = 'C:\chemin\vers\LocalAgentAdmin\tools'

    # Decommente seulement si le port par defaut est deja pris sur cette machine.
    # Port = 47601
}
