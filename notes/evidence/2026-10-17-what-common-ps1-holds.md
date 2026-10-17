# Ce que `common.ps1` contient — mesuré avant d'en proposer le découpage

**17/10/2026.** Relevé pris pour le sujet **S28**, avant toute proposition : un découpage proposé sans mesure est
une devinette. L'outil est `local/common-map.ps1` (arbre syntaxique PowerShell pour les fonctions et leurs appels,
recherche sur tout le dépôt pour les usages extérieurs).

## La taille

`apps/backend-pode/lib/common.ps1` : **11 909 lignes, 615 Ko, 323 fonctions**. C'est le fichier que **tout** le
dépôt charge : chaque route le source, chaque sonde, chaque action, chaque tâche de fond.

## Ce qui ne sort jamais du fichier

**104 fonctions sur 323 — 2 129 lignes — ne sont nommées nulle part ailleurs.** Ce sont des aides internes : elles
pourraient devenir privées d'un morceau sans que rien du dépôt ne s'en aperçoive. Les 219 autres sont l'interface
réelle de la bibliothèque, et c'est elle qui doit rester intacte quel que soit le découpage.

> **Attention à la mesure elle-même.** Le premier passage a répondu « 323 sur 323 », ce qui aurait voulu dire que
> personne n'appelle `Get-State`. La cause : l'exclusion des dossiers était écrite en absolu, et ce plan de travail
> vit sous `.claude/worktrees/` — tous les fichiers du dépôt étaient donc jetés. Une mesure qui répond « tout » à
> une question de ce genre est une mesure cassée, pas une découverte.

## Les plus grosses fonctions

| Fonction | Lignes | Nommée dans |
|---|---|---|
| `Get-State` | 653 | 5 fichiers |
| `Get-HardwareSpecs` | 226 | 2 |
| `Get-WindowsUpdateAilments` | 220 | 1 |
| `Add-GameTallyPass` | 151 | 1 |
| `Invoke-RefreshPass` | 132 | 1 |
| `Get-PendingUpdateList` | 126 | 2 |
| `Invoke-WatchPass` | 123 | 1 |
| `Update-ClientWatch` | 122 | 2 |

## Les sujets, tels que le fichier les déclare déjà

Les bannières `# --- … ---` découpent le fichier en 40 sections. Les plus grosses :

| Lignes | Section déclarée |
|---|---|
| 2 448 | « L'arborescence du disque » — en réalité : arbre du disque, **fabriques du contrat** (`New-Field`, `New-Action`, `New-ModuleObject`), **jeux** (bibliothèques, critères, parties), **résidents**, **veilles**, **énergie et batterie**, **sentinelles**, **déclarations de l'ordonnanceur** |
| 1 629 | « Quels comptes Windows ont Vigie (D65) » |
| 1 566 | « L'historique des mesures (séries) » |
| 1 149 | « L'identité précise d'une version » |
| 503 | la section sans titre (3004–3509) |
| 496 | « Gestionnaires de paquets » |
| 381 | « Sécurité de la virtualisation (VBS / HVCI) » |

**La bannière ment sur deux des trois plus grosses sections** : elle annonce un sujet, et sept le suivent sans
nouvelle bannière. C'est la même mécanique que pour la page du panneau — on ajoute dans ce qui existe déjà.

## Ce que ça coûte aujourd'hui

C'est l'un des deux leviers nommés dans [le relevé du 15/10](2026-10-15-what-makes-check-coherence-slow.md) sur le
coût de la validation : chaque vérificateur qui cherche une déclaration dans le dépôt lit ces 615 Ko.

Et le coût qui ne se mesure pas en secondes : pour lire *une* règle, il faut ouvrir le fichier que tout le monde
charge. C'est ce qui a permis, le 16/10, qu'une fonction en appelle une autre dont elle empruntait une variable au
passage (`Write-MeasureSamples` et `$nowUtc`) — invisible dans 11 909 lignes.
