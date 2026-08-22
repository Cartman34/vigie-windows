@{
    # Adresse d'ecoute : STRICTEMENT locale (ne jamais exposer, le back est eleve).
    BindAddress = '127.0.0.1'

    # Port : CONFIGURABLE. Plage reservee aux serveurs locaux de LocalWork :
    # 47600-47699 (voir le registre LocalWork/PORTS.md). Un port fixe par projet,
    # inscrit au registre. Defaut de ce projet : 47600.
    Port        = 47600

    ApiBase     = '/api/v1'

    # Outillage reutilise (verrouillage MAJ, update-mode, audits).
    ToolsPath   = 'C:\EspaceRestreint\Workspaces\AiTeam\LocalAgentAdmin\tools'
}
