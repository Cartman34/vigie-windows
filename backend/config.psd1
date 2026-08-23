@{
    # ---------------------------------------------------------------------------
    # Configuration VERSIONNEE : generique, valable sur n'importe quelle machine.
    # Chaque valeur n'est definie qu'ICI ; tout le reste en derive (Get-AppUrl,
    # Get-ApiUrl, Get-ToolsPath dans lib/common.ps1). Ne jamais recopier une de ces
    # valeurs ailleurs dans le code.
    #
    # Pour ce qui est propre a TA machine, ne modifie pas ce fichier : cree
    # backend/config.local.psd1 (ignore par git) a partir de config.local.sample.psd1.
    # ---------------------------------------------------------------------------

    # Adresse d'ecoute : STRICTEMENT locale (ne jamais exposer, le back est eleve).
    BindAddress = '127.0.0.1'

    # Port d'ecoute. Un port fixe par projet, dans la plage locale 47600-47699.
    Port        = 47600

    # Prefixe des routes de l'API REST (voir api/openapi.yaml).
    ApiBase     = '/api/v1'

    # Port de l'atelier de validation (docs/atelier.ps1, serveur php temporaire).
    # Meme plage locale que le serveur, port distinct pour ne jamais le concurrencer.
    AtelierPort = 47610

    # Outillage externe OPTIONNEL (scripts d'administration vivant hors du depot :
    # verrouillage MAJ, update-mode, audits). Vide = non configure : les actions qui
    # en dependent rendent alors un message clair au lieu d'echouer.
    # Un chemin absolu est propre a une machine : renseigne-le dans config.local.psd1.
    ToolsPath   = ''
}
