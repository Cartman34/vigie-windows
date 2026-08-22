# Conventions du projet

Reference unique des conventions. Toute nouvelle convention se note ICI.

## Langue
- Echanges avec l'utilisateur : francais.
- **Code et noms de fichiers : anglais**. Commentaires : francais.

## Arborescence et nommage
- Sources : voir `../README.md`.
- Sonde : `backend/probes/<theme>/<nom>.probe.ps1`.
- Action : `backend/actions/<id>.action.ps1` (le `<id>` = valeur `type` du contrat).
- Rapports horodates : `<nom>_AAAAMMJJ_HHMMSS.txt` (+ `.json`).

## Contrat d'abord (contract-first)
- `api/openapi.yaml` est la **source de verite**. Toute evolution d'API s'y
  decide AVANT le code. Le front ne depend que du contrat ; le back est
  interchangeable.

## Modele sonde / action
- **Sonde** : LECTURE SEULE, rapide, sans effet de bord. Sort UN objet `Module`
  (schema OpenAPI). Utiliser les fabriques `New-ModuleObject` / `New-Field` /
  `New-Action` de `backend/lib/common.ps1`. Appels lents bornes par un delai.
- **Action** : effet de bord. Signature `param([string]$Module,[hashtable]$Params)`.
  Retourne `@{ message=...; result=... }`. Reutilise l'outillage existant
  (`LocalAgentAdmin/tools/`) plutot que de reimplementer.
- Statuts autorises : `ok` | `warn` | `error`.
- Types de champ (`kind`) : `bool` | `number` | `text` | `date` (+ `unit` option).

## Securite
- API en ecoute **127.0.0.1 uniquement**. Jamais exposee (le back tourne eleve).
- **Jeton Bearer** genere une fois (`backend/.secrets/api.token`), exige sur tous
  les endpoints sauf `/health`. Injecte dans la page servie (meme origine).

## Technique
- Pode isole les routes en runspaces : le contexte passe par **variables
  d'environnement** (`VIGIE_BACKEND`, `VIGIE_TOKEN`) ; chaque route re-source
  `lib/common.ps1`. (Voir `technologies.md`.)
- Scripts de tache planifiee : **idempotents** (`Register-ScheduledTask -Force`).
- Toujours **verifier les prerequis en amont** (droits, modules, runtime).

## Documentation (regle absolue)
- **Tout se documente** : chaque convention (ici), chaque techno
  (`technologies.md`), chaque fonctionnalite + son usage
  (`targeting/` + `implemented/` + `using/`).
- Doc en 4 volets, **zero doublon**, references par **ID** (voir `README.md`).
- Le **fichier de suivi** `../SUIVI.md` est tenu a jour a chaque session pour
  reprendre a tout moment.
- Le **fichier d'initialisation** porte un **nom non-standard**
  (`../PRISE-EN-MAIN.md`) pour ne pas etre charge automatiquement par les agents.

## Device bridge
- Fichiers manipules via le pont (dossier monte). **Suppression interdite** :
  deplacer (`mv`) au lieu de supprimer.

## Idempotence (regle absolue)
**Tous** les scripts sont idempotents : rejouables sans effet de bord ni erreur.
Concretement :
- Verifier l'etat AVANT d'agir ; ne rien refaire d'inutile.
- Installer seulement si absent (`install.ps1`).
- Ne pas relancer un service deja demarre (`start.ps1`/`run.ps1` testent le port
  via `Test-ServerUp`).
- Taches planifiees : `Register-ScheduledTask -Force`.
- Modifications de config : positionner la valeur cible (pas de bascule aveugle).

## Ports (organisation)
- Plage locale reservee : **47600-47699**. Registre central : `LocalWork/PORTS.md`.
- Chaque projet : **un port fixe**, configurable (ici `backend/config.psd1`),
  inscrit au registre ; verifier le registre avant d'allouer.
- Defaut de ce projet : **47600**.

## Encodage des scripts (compat PowerShell 5.1)
Windows PowerShell 5.1 lit les `.ps1`/`.psd1` en ANSI (Windows-1252), pas en
UTF-8 : tout caractere non-ASCII (accents, tiret cadratin -, guillemets
courbes) casse l'analyse des chaines. Regle : **scripts PowerShell en ASCII pur**
(commentaires francais sans accents, `-` simple, guillemets droits). Verif :
`grep -rlP '[^\x00-\x7F]' --include='*.ps1' --include='*.psd1'` doit etre vide.

## PowerShell 7 + UTF-8 (mise a jour, remplace la contrainte ASCII)
- **Cible : PowerShell 7 (pwsh)** ; les lanceurs `install/start/run.ps1`
  **rebasculent automatiquement en pwsh** s'ils sont appeles depuis la 5.1.
  `install.ps1` installe PS7 (winget) s'il manque.
- Sous PS7, les fichiers sont **UTF-8** : les **accents sont autorises** dans les
  scripts (sondes, actions, lib, server).
- **Exception** : les 3 lanceurs (`install/start/run.ps1`) restent en **ASCII**,
  car la 5.1 doit pouvoir les lire le temps de rebasculer en pwsh.
- Encodage d'ecriture recommande : UTF-8 (avec BOM si edite sous Windows).

## Journalisation (logs recuperables)
- Tout ecrit sous **`backend/logs/`** (recuperable via le pont pour diagnostic).
- `install.ps1` / `start.ps1` : transcript complet (`install_*.log`,
  `start_*.log`) + lignes `Write-Log` (helper de `lib/common.ps1`).
- Serveur Pode : logs d'erreurs et de requetes (`pode-error_*.log`,
  `pode-request_*.log`) via la journalisation Pode.
- Regle : un script qui peut echouer **journalise** son erreur sur fichier
  (pas seulement a l'ecran), pour etre diagnostique sans copier-coller.

## Regles transverses (2026-08-20)

### 1. Pas de duplication : une fonctionnalite = un seul code
Toute logique partagee vit dans `backend/lib/common.ps1` et est reutilisee, jamais recopiee.
Helpers partages en place :
- `Test-Elevated` : le processus est-il administrateur ? (utilise par run/start/install + sondes)
- `Test-UpdateTasksAclLock` : le verrou ACL (refus SYSTEM) est-il pose ? Comparaison par **SID**
  (`S-1-5-18`), independante de la langue. Utilise par `lock.probe` ET l'action `update-mode-off`.
- `Invoke-Native` : execute une commande native et renvoie `{ Ok; ExitCode; Output }`.
Cote front, le rendu d'une carte est centralise dans `cardHtml(m, groupLabel)` (reutilise par le
rendu complet ET le rafraichissement par carte).

### 2. Toujours traiter erreurs, sorties et codes de retour
Chaque appel a une commande / un service / un script doit :
- capturer la sortie (stdout + stderr, ex. `2>&1`),
- verifier le code de retour (`$LASTEXITCODE` pour les .exe, `try/catch` pour les cmdlets),
- journaliser en cas d'echec, et remonter un resultat honnete (jamais de faux succes).
Exemples : `update-mode-off` verifie reellement le verrou pose (helper) et journalise `icacls`/`takeown` ;
les actions renvoient `result.ok` reel ; le front affiche « Reussi » seulement si `result.ok` n'est pas `false`.
