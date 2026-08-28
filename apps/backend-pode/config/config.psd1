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

    # QUEL ENVIRONNEMENT tourne sur cette machine.
    #
    #   'prod' : Vigie tourne depuis l'installation partagee (C:\Program Files\Sowapps\Vigie).
    #            C'est le defaut : une machine est en production tant qu'on n'a pas dit
    #            l'inverse.
    #   'dev'  : Vigie tourne depuis le depot. Poste de developpement.
    #
    # Ce reglage DECLARE une intention ; Vigie compare ensuite avec ce qui tourne
    # reellement et signale l'ecart. A poser dans config.local.psd1 : c'est un choix de
    # machine, comme UpdateSource.
    Environment  = 'prod'

    # D'OU VIGIE SE MET A JOUR quand on appuie sur « Mettre a jour Vigie ».
    #
    #   'auto'    : le depot est la -> on deploie ce depot (poste de developpement) ;
    #               sinon -> on telecharge la derniere version publiee. C'est le defaut,
    #               et il fait ce qu'on attend dans les deux cas.
    #   'local'   : TOUJOURS le depot local, meme si une version publiee est plus recente.
    #   'release' : TOUJOURS la derniere version publiee, meme sur un poste de
    #               developpement -- utile sur un serveur de dev qui doit se comporter
    #               comme une machine d'utilisateur.
    #   'clone'   : un clone a part, sur la reference indiquee par UpdateRef.
    #
    # A poser dans config.local.psd1 : c'est un choix de MACHINE, pas du produit.
    UpdateSource = 'auto'

    # Branche, tag ou commit a deployer quand UpdateSource vaut 'clone'. Vide = le dernier
    # tag, jamais une branche : suivre une branche reviendrait a installer du travail en
    # cours (D99).
    UpdateRef    = ''

    # Outillage externe OPTIONNEL (scripts d'administration vivant hors du depot).
    # Le verrouillage de Windows Update et son audit sont NATIFS depuis lib/common.ps1
    # (Set-UpdateLock, Invoke-UpdateAudit) : ils n'ont plus besoin de ce chemin. S'il est
    # renseigne ET contient update-mode.ps1, ce script reste prefere -- les installations
    # historiques gardent leur comportement.
    # Restent tributaires de ce chemin : bascules VBS / HVCI, action "ouvrir le dossier".
    # Vide = non configure : ces actions-la rendent un message clair au lieu d'echouer.
    # Un chemin absolu est propre a une machine : renseigne-le dans config.local.psd1.
    ToolsPath   = ''

    # --- Historique des mesures (doc/archives/conception/historique-cible.md, section 5) ------
    # Series echantillonnees au passage des sondes, stockees dans var/history/ (un
    # fichier JSONL par mesure). Resolution en couches par Get-HistoryConfig
    # (lib/common.ps1) : ces valeurs globales, puis le reglage par mesure ci-dessous.
    History = @{
        # Interrupteur general. Desactive = plus aucune ecriture (les fichiers restent).
        Enabled            = $true
        # Retention PAR DEFAUT, en jours. S'applique a toute mesure sans reglage propre.
        RetentionDays      = 90
        # Garde-fou de taille par fichier de mesure (lignes), en plus de l'age.
        MaxLinesPerMeasure = 50000
        # Reglages PAR MESURE : la cle est l'identifiant du catalogue
        # ($script:MeasureCatalog dans lib/common.ps1). Toute cle absente herite du
        # global. IntervalMinutes surcharge l'intervalle minimal du catalogue.
        # RetentionDays = 0 : ne plus echantillonner la mesure (le fichier existant
        # n'est pas supprime : detruire une archive reste un geste manuel).
        Measures = @{
            'disk.free'   = @{ RetentionDays = 365 }
            'net.latency' = @{ RetentionDays = 30 }
        }
    }
}
