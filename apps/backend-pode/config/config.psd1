@{
    # ---------------------------------------------------------------------------
    # Configuration VERSIONNEE : generique, valable sur n'importe quelle machine.
    # Chaque valeur n'est definie qu'ICI ; tout le reste en derive (Get-AppUrl,
    # Get-ApiUrl, Get-ToolsPath dans lib/common.ps1). Ne jamais recopier une de ces
    # valeurs ailleurs dans le code.
    #
    # Pour ce qui est propre a TA machine, ne modifie pas ce fichier : cree
    # apps/backend-pode/config/config.local.psd1 (ignore par git) a partir de config.local.sample.psd1.
    # ---------------------------------------------------------------------------

    # BindAddress vient de config/common.psd1 (racine) : partagee par toutes les apps,
    # elle n'est pas recopiee ici (D15/D33). Ecoute STRICTEMENT locale.

    # Port d'ecoute. Un port fixe par projet, dans la plage locale 47600-47699.
    Port        = 47600

    # Prefixe des routes de l'API REST (voir apps/backend-pode/api/openapi.yaml).
    ApiBase     = '/api/v1'

    # Outillage externe OPTIONNEL (scripts d'administration vivant hors du depot).
    # Le verrouillage de Windows Update et son audit sont NATIFS depuis lib/common.ps1
    # (Set-UpdateLock, Invoke-UpdateAudit) : ils n'ont plus besoin de ce chemin. S'il est
    # renseigne ET contient update-mode.ps1, ce script reste prefere -- les installations
    # historiques gardent leur comportement.
    # Restent tributaires de ce chemin : bascules VBS / HVCI, action "ouvrir le dossier".
    # Vide = non configure : ces actions-la rendent un message clair au lieu d'echouer.
    # Un chemin absolu est propre a une machine : renseigne-le dans config.local.psd1.
    ToolsPath   = ''
}
