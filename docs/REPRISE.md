# Vigie — reprise du projet (à lire en premier)

Point de reprise. Après ce fichier : `docs/DECISIONS-VALIDEES.md`, `SUIVI.md`, `PRISE-EN-MAIN.md`.

## Le projet
**Vigie** : tableau de bord **local** pour un PC Windows. Dépôt : `vigie-windows`.
> ⚠️ « HYPERION » n'est **pas** un nom de code du projet : c'est le **nom de la machine** de
> l'utilisateur. Toute occurrence dans le code, les identifiants ou la doc est un **défaut de
> généricité** (valeur machine codée en dur) à éliminer, pas un héritage à conserver.
- Backend **PowerShell + Pode** (`backend/`), écoute **127.0.0.1:47600**, jeton Bearer + anti-CSRF + liste blanche d'actions.
- Frontend **HTML/JS pur** (`frontend/index.html`), sert la maquette `frontend/mock/state.json` si le back est absent.
- **App tray WinForms** (`backend/tray.ps1`) : lance le serveur en fond, icône = statut de l'app (jauge), menu, fenêtre dédiée (Edge/Chrome `--app`).
- Fonction phare : **verrouiller Windows Update** (ACL deny SYSTEM sur les dossiers de tâches) pour bloquer les redémarrages forcés, sans masquer les vraies MAJ.

## Règles de conception (permanentes)
- **On parle français, le code est en anglais.**
- Pas de duplication (helpers partagés dans `backend/lib/common.ps1`).
- **Toujours** traiter erreurs + sortie + code retour (`Invoke-Native`).
- Scripts **idempotents**. **PS7 + UTF-8 avec accents** (les lanceurs restent ASCII).
- **Vérifier les prérequis en amont.** **Valider avant de dire « prêt »** (ne jamais inventer une validation).
- **Toute décision validée est consignée dans `docs/DECISIONS-VALIDEES.md`** + son support copié dans `docs/maquettes-validees/`.

## Architecture (contract-first)
- `api/openapi.yaml` = source de vérité du contrat REST.
- Sonde = `backend/probes/<theme>/*.probe.ps1`, renvoie 1 module OU un tableau de modules.
- Action = `backend/actions/<id>.action.ps1`, renvoie `@{ message; result }`. `result.invalidate=@('x.probe.ps1')` force le recalcul.
- Agrégation + cache (mtime+TTL, single-flight, serve-stale) : `Get-State` dans `common.ps1`.
- **Tâches de fond** : `Start-DetachedAction` (worker pwsh caché) ; ex. paquets via `Start-PkgJob` + `backend/workers/pkg-job.worker.ps1`. Une action longue répond `result.async=$true` + `module`; le front met la carte en « busy » et l'interroge jusqu'à fin.

## État — FAIT (déployé sur la machine, validé hors-ligne)
- Socle asynchrone non bloquant (`Start-DetachedAction`, `Remove-ProbeCache`, `Update-StateJson` avec mutex inter-processus).
- Paquets : **une carte par gestionnaire**, **vérification ET mise à jour** en tâche de fond (winget/choco/scoop/npm/gem), polling par carte, halo « en cours ».
- Boutons de résolution : prennent le **libellé de l'action** (plus de « Résoudre » générique), n'apparaissent que si une action existe. **Icônes** : boîte-flèche = logiciel externe ; fenêtre = popin.
- Résolutions câblées : Latence → `net-speedtest` ; Windows Update « Détectées » → `open-windows-update` (note raccourcie).
- WSL : champ **Statut Actif/Inactif** coloré + **trio Démarrer/Redémarrer/Arrêter** (boutons pertinents). Actions `wsl-start`/`wsl-restart` + invalidation sonde.
- Topbar : **liseré coloré = état de connexion à l'API** (vert live / orange maquette / rouge erreur) ; santé globale dans la topbar.
- **Icône tray** : `.ico` multi-résolutions nets, design **option B validée** (anneau + graduations + aiguille à talon + point blanc), générés par `backend/assets/tray/generer-icones.py`, chargés par `tray.ps1` (`setIcon`) avec repli GDI+.
- **Rebrand interface** : « Control Panel » → **« Vigie »** (titre onglet, sous-titre, `document.title`, tray). Le titre principal reste le **nom de la machine** (dynamique).

## État — À FAIRE (backlog)
1. ~~Écran de chargement soigné~~ — **FAIT** (**D08**) : `#splash` dans le HTML statique, « Vigie » en gros,
   marque **D01** en SVG, effacement au premier chargement (durée mini 550 ms, garde-fou 90 s).
2. ~~Lien GitHub retrouvable~~ — **FAIT** (**D09**) : splash, topbar, pied de page, menu tray
   « À propos de Vigie ». URL en **constante unique** par langage (`REPO_URL` / `$RepoUrl`).
3. ~~Rendre `backend/config.psd1` générique~~ — **FAIT** (**D18**) : socle versionné générique
   + `config.local.psd1` (ignoré par git) + `config.local.sample.psd1`. `ToolsPath` optionnel,
   URL et port dérivés d'un seul endroit (`Get-AppUrl` / `Get-ApiUrl` / `Get-ToolsPath` /
   `Get-AdminRoot`), plus aucune valeur en dur (**D15**).
4. ~~Style du menu contextuel du tray~~ — **FAIT** (**D19**) : coins arrondis natifs DWM,
   survol encarté arrondi, items de 32 px, séparateurs encartés, palette définie une seule fois.
   **À juger à l'œil** : le rendu n'a pas pu être vu depuis la session de l'agent — relancer le tray.
5. **Terminer le retrait du nom de machine** dans le code — **défaut de généricité**, pas un point
   cosmétique : le produit ne doit contenir aucune valeur propre à un PC donné.
   Fait : tâche planifiée `Vigie`, raccourci `Vigie.url`, mutex `Local\VigieState_*` et
   `Local\VigieStateRecompute` (`common.ps1`), titre openapi `Vigie API`, lanceur
   `backend/demarrer-vigie.vbs`, documentation.
   Également fait : `backend/tray.ps1` (mutex `VigieTray`, types `VigieNative` / `VigieDarkColors`)
   et les variables d'environnement `VIGIE_BACKEND` / `VIGIE_TOKEN` / `VIGIE_PORT` (ex-`HCP_*`).
   **Le nom de machine a totalement disparu du projet** (vérifié par recherche exhaustive).
   Exception : `docs/maquettes-validees/` n'est pas retouché (archive des supports de décision).
6. ~~Couleur WSL « Inactif »~~ — **FAIT** (**D20**) : champ **et** carte en rouge (la contradiction
   d'avant est levée). Rebasculable en **une seule ligne** (`$inactiveSeverity` en tête de la sonde),
   sans rien toucher au front.
7. **Migrer l'installation** (**D07**) — exige un PowerShell **administrateur**, impossible depuis
   la session de l'agent :
   `backend/install-autostart.ps1` (tâche `Vigie` pointant sur le dépôt), puis
   `backend/uninstall-legacy.ps1 -LegacyWorkspace <ancien dossier>` (**D11**) pour retirer la tâche
   et le raccourci hérités et mettre l'ancien espace de travail de côté en `.old`.
   Le lancer d'abord avec `-WhatIf` : son chemin élevé n'a pas pu être testé.
8. **Supprimer définitivement** `LocalWork/hyperion-control-panel.old` une fois la migration confirmée.
   Aucun script ne le fait : c'est une suppression, elle reste manuelle et volontaire.

## Décisions validées
Voir `docs/DECISIONS-VALIDEES.md` : icône tray = option B (graduations + talon confirmés) ; nom = dépôt « Vigie Windows » (slug `vigie-windows`), interface « Vigie » à la place de « Control Panel ».

## Dépôt GitHub (état à jour)

**La publication est faite.** Le dépôt `Cartman34/vigie-windows` est peuplé ; l'import initial est
le commit **`e45a062`** (« Vigie — import initial »), branche **`main`**.

**Source de vérité aujourd'hui** : `C:\EspaceRestreint\Workspaces\Git\vigie-windows`.
C'est le dépôt git, et c'est **là** qu'on travaille (Claude Code s'ouvre dans ce dossier).

**Ancien espace de travail** : `C:\EspaceRestreint\Workspaces\AiTeam\LocalWork\hyperion-control-panel`
— **en cours de retrait**, il n'est plus la source. Ne plus y éditer, ne plus y recopier.
Conformément à **D07** il est **renommé** (suffixe `.old`) et non supprimé ; la suppression
n'aura lieu qu'après confirmation explicite que tout fonctionne depuis le dépôt.

### Config git / accès (toujours valable)
- `credential.helper=manager` ; `user.name` / `user.email` déjà réglés.
- Remote en **HTTPS** : `https://github.com/Cartman34/vigie-windows.git`.
- Authentification : token *fine-grained* (All repos + **Contents R/W**), mémorisé par le Credential
  Manager au 1er push. Username = `Cartman34`, Password = le **token** (pas le mot de passe GitHub).
- Alternative zéro-token : remote SSH `git@github.com:Cartman34/vigie-windows.git` avec la clé locale.
- `.gitignore` exclut déjà le jeton API (`backend/.secrets/`), l'état (`backend/.state/`) et les logs.
  Avant tout commit, `git status` ne doit montrer NI `.secrets/`, NI `.state/`, NI `logs/`, NI `*.bak-*`.

## Contraintes environnement (importantes)

> Cette section decrit la machine de travail REELLE. Elle remplace l'ancienne, qui
> decrivait une VM Linux ephemere (Cowork/`device_bash`) et n'a plus cours : le projet
> est desormais edite directement sur la machine, dans le depot git.

### Outils presents
- **PowerShell 7** (`pwsh`) : present. C'est l'outil de validation du code PowerShell.
- **Python 3.11** : present (sert a `backend/assets/tray/generer-icones.py`).
- **Chocolatey**, **git**, **php**, **composer**, **symfony-cli** : presents.
- **git** fonctionne normalement : depot, branches et worktrees operationnels. **HTTPS** vers
  GitHub, jeton memorise par le Credential Manager.

### Outils ABSENTS (et volontairement non installes)
- **Node / npm** : absent de la machine (verifie : PATH, nvm, fnm, volta, scoop, paquets
  Chocolatey, et recherche de `node.exe` sous Program Files / LOCALAPPDATA / APPDATA /
  ProgramData). Le projet n'a **aucune** dependance JS : pas de `package.json`, pas d'etape
  de build, un seul fichier HTML servi tel quel. On n'installe donc pas Node (voir **D06**).

### Comment valider (ne JAMAIS inventer une validation)
- **PowerShell** : `[System.Management.Automation.Language.Parser]::ParseFile(...)` sur chaque
  `.ps1` / `.psd1` modifie, et on rapporte la sortie reelle.
- **JavaScript du front** : charger `frontend/index.html` en `file://` dans un navigateur et
  lire la console (**D06**). Une erreur de syntaxe empeche l'execution de tout le bloc
  `<script>` : verifier qu'une constante definie en fin de script existe bien suffit a prouver
  que le fichier parse. Ce test couvre en plus les erreurs d'execution et le repli sur
  `mock/state.json`.
- **Lanceurs** (`.cmd`, `.vbs`) : doivent rester **ASCII pur** (verification octet par octet).
  Le reste du code est en **UTF-8 avec accents**.

### Privileges
- La session de l'agent n'est **pas elevee**. Toute operation sur la tache planifiee
  (enregistree en `RunLevel Highest`) exige un PowerShell administrateur lance par
  l'utilisateur : `install-autostart.ps1`, `uninstall-autostart.ps1`, `uninstall-legacy.ps1`.

### A ne jamais committer
- `backend/.secrets/` (jeton API), `backend/.state/`, `backend/logs/`, `*.bak-*`, `_to_delete/`.
  Le `.gitignore` les couvre deja ; verifier malgre tout `git status` avant chaque commit.
