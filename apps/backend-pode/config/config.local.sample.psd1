# @author Florent HAZARD <f.hazard@sowapps.com>
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

    # Historique des mesures : surcharge FACULTATIVE de la section History de config.psd1.
    # ATTENTION : une cle de premier niveau remplace la table ENTIERE -- si tu poses
    # History ici, les sous-cles absentes reprennent les defauts internes de
    # Get-HistoryConfig (Enabled=$true, RetentionDays=90, MaxLinesPerMeasure=50000,
    # Measures vide), PAS les valeurs de config.psd1. Recopie donc tout ce que tu veux garder.
    # History = @{
    #     Enabled            = $true       # $false = plus aucune ecriture (fichiers conserves)
    #     RetentionDays      = 180
    #     MaxLinesPerMeasure = 50000
    #     Measures = @{
    #         'disk.free'   = @{ RetentionDays = 365 }
    #         # IntervalMinutes surcharge l'intervalle minimal du catalogue ;
    #         # RetentionDays = 0 coupe l'echantillonnage de la mesure.
    #         'net.latency' = @{ RetentionDays = 30 }
    #     }
    # }
}
