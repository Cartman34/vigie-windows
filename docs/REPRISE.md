# Vigie — reprise du projet (à lire en premier)

Point de reprise. Après ce fichier : `docs/DECISIONS-VALIDEES.md`, `SUIVI.md`, `PRISE-EN-MAIN.md`.

## Le projet
**Vigie** : tableau de bord **local** pour un PC Windows. Dépôt : `vigie-windows`.
> ⚠️ « HYPERION » n'est **pas** un nom de code du projet : c'est le **nom de la machine** de
> l'utilisateur. Toute occurrence dans le code, les identifiants ou la doc est un **défaut de
> généricité** (valeur machine codée en dur) à éliminer, pas un héritage à conserver.
- Backend **PowerShell + Pode** (`backend/`), écoute **127.0.0.1:47600**, jeton Bearer + anti-CSRF + liste blanche d'actions.
- Frontend **HTML/JS pur** (`apps/frontend-web/index.html`), sert la maquette `apps/frontend-web/mock/state.json` si le back est absent.
- **App tray WinForms** (`apps/tray/tray.ps1`) : lance le serveur en fond, icône = statut de l'app (jauge), menu, fenêtre dédiée (Edge/Chrome `--app`).
- Fonction phare : **verrouiller Windows Update** (ACL deny SYSTEM sur les dossiers de tâches) pour bloquer les redémarrages forcés, sans masquer les vraies MAJ.

> **Ne pas confondre avec l'Atelier.** « Vigie » = l'application (PowerShell + Pode, port
> 47600, élevée). « **Atelier** » = l'outil de développement (PHP, port 47610, jamais
> élevé, `apps/atelier/`). Voir **D28**, **D29** et `apps/atelier/README.md`.

## Règles de conception (permanentes)
- **On parle français, le code est en anglais.**
- Pas de duplication (helpers partagés dans `apps/backend-pode/lib/common.ps1`).
- **Toujours** traiter erreurs + sortie + code retour (`Invoke-Native`).
- Scripts **idempotents**. **PS7 + UTF-8 avec accents** (les lanceurs restent ASCII).
- **Vérifier les prérequis en amont.** **Valider avant de dire « prêt »** (ne jamais inventer une validation).
- **Toute décision validée est consignée dans `docs/DECISIONS-VALIDEES.md`** + son support copié dans `docs/maquettes-validees/`.

## Architecture (contract-first)
- `apps/backend-pode/api/openapi.yaml` = source de vérité du contrat REST.
- Sonde = `apps/backend-pode/probes/<theme>/*.probe.ps1`, renvoie 1 module OU un tableau de modules.
- Action = `apps/backend-pode/actions/<id>.action.ps1`, renvoie `@{ message; result }`. `result.invalidate=@('x.probe.ps1')` force le recalcul.
- Agrégation + cache (mtime+TTL, single-flight, serve-stale) : `Get-State` dans `common.ps1`.
- **Tâches de fond** : `Start-DetachedAction` (worker pwsh caché) ; ex. paquets via `Start-PkgJob` + `apps/backend-pode/workers/pkg-job.worker.ps1`. Une action longue répond `result.async=$true` + `module`; le front met la carte en « busy » et l'interroge jusqu'à fin.

## État — FAIT (déployé sur la machine, validé hors-ligne)
- Socle asynchrone non bloquant (`Start-DetachedAction`, `Remove-ProbeCache`, `Update-StateJson` avec mutex inter-processus).
- Paquets : **une carte par gestionnaire**, **vérification ET mise à jour** en tâche de fond (winget/choco/scoop/npm/gem/pip), polling par carte. L'état « en cours » s'affiche dans le **liseré gauche** de la carte, qui clignote (**D46**) — le halo a été supprimé.
- Paquets, **mise à jour AU CHOIX** (jumelle de **D45**) : « Mettre à jour » ouvre une fenêtre
  de choix (`pkg-list-updates`, `kind: dialog`) ; seuls les paquets cochés sont mis à jour
  (winget par `--id`, Chocolatey et pip par nom). Un gestionnaire qui ne sait pas cibler un
  paquet (scoop, npm, gem) affiche quand même sa liste, **cochée et non décochable**, et le
  dit. Le champ `upgOne` du catalogue (`common.ps1`) est la **seule** source de cette capacité.
- Paquets, **interface graphique du gestionnaire** : bouton `pkg-open-gui` (`kind: manual`),
  ajouté **uniquement si la cible existe** sur la machine — Microsoft Store pour winget,
  Chocolatey GUI pour Chocolatey (absent ici), rien pour pip.
- Boutons de résolution : prennent le **libellé de l'action** (plus de « Résoudre » générique), n'apparaissent que si une action existe. **Icônes** (**D45**) : triangle = action immédiate ; **triangle d'avertissement orange** = confirmation ; liste cochée = fenêtre de choix ; flèche sortante = logiciel externe.
- Résolutions câblées : Latence → `net-speedtest` ; Windows Update « Détectées » → `open-windows-update` (note raccourcie).
- WSL : champ **Statut Actif/Inactif** coloré + **trio Démarrer/Redémarrer/Arrêter** (boutons pertinents). Actions `wsl-start`/`wsl-restart` + invalidation sonde.
- Topbar : **liseré coloré sous l'en-tête = état de connexion à l'API** (vert live / orange maquette / rouge erreur). À ne pas confondre avec le liseré **gauche** de chaque carte, qui porte le statut de CE module (**D46**).
- **Icône tray** : `.ico` multi-résolutions nets, design **option B validée** (anneau + graduations + aiguille à talon + point blanc), générés par `apps/tray/assets/generate-icons.py`, chargés par `tray.ps1` (`setIcon`). Le repli GDI+ a été **supprimé** (**D38**) : en cas d'échec, un simple disque de la couleur du statut, et l'échec est journalisé.
- **Rebrand interface** : « Control Panel » → **« Vigie »** (titre onglet, sous-titre, `document.title`, tray). Le titre principal reste le **nom de la machine** (dynamique).

## État — À FAIRE (backlog)
1. ~~Écran de chargement soigné~~ — **FAIT** (**D08**) : `#splash` dans le HTML statique, « Vigie » en gros,
   marque **D01** en SVG, effacement au premier chargement (durée mini 550 ms, garde-fou 90 s).
2. ~~Lien GitHub retrouvable~~ — **FAIT** (**D09**) : splash, topbar, pied de page, menu tray
   « À propos de Vigie ». URL en **constante unique** par langage (`REPO_URL` / `$RepoUrl`).
3. ~~Rendre `apps/backend-pode/config/config.psd1` générique~~ — **FAIT** (**D18**) : socle versionné générique
   + `config.local.psd1` (ignoré par git) + `config.local.sample.psd1`. `ToolsPath` optionnel,
   URL et port dérivés d'un seul endroit (`Get-AppUrl` / `Get-ApiUrl` / `Get-ToolsPath` /
   `Get-AdminRoot`), plus aucune valeur en dur (**D15**).
4. ~~Style du menu contextuel du tray~~ — **FAIT et VALIDÉ à l'œil** par l'utilisateur
   (**D19**) : coins arrondis natifs DWM, gris neutre Win11, texte centré verticalement
   (`OnRenderItemText` fixe lui-même `e.TextRectangle`), survol **pleine largeur**,
   séparateurs alignés sur le retrait du texte, palette définie une seule fois.
5. **Terminer le retrait du nom de machine** dans le code — **défaut de généricité**, pas un point
   cosmétique : le produit ne doit contenir aucune valeur propre à un PC donné.
   Fait : tâche planifiée `Vigie`, raccourci `Vigie.url`, mutex `Local\VigieState_*` et
   `Local\VigieStateRecompute` (`common.ps1`), titre openapi `Vigie API`, lanceur
   `scripts/start-vigie.vbs`, documentation.
   Également fait : `apps/tray/tray.ps1` (mutex `VigieTray`, types `VigieNative` / `VigieDarkColors`)
   et les variables d'environnement `VIGIE_BACKEND` / `VIGIE_TOKEN` / `VIGIE_PORT` (ex-`HCP_*`).
   **Le nom de machine a totalement disparu du projet** (vérifié par recherche exhaustive).
   Exception : `docs/maquettes-validees/` n'est pas retouché (archive des supports de décision).
6. ~~Couleur WSL « Inactif »~~ — **FAIT** (**D20**) : champ **et** carte en rouge (la contradiction
   d'avant est levée). Rebasculable en **une seule ligne** (`$inactiveSeverity` en tête de la sonde),
   sans rien toucher au front.
7. **Migrer l'installation** (**D07**) — exige un PowerShell **administrateur**, impossible depuis
   la session de l'agent :
   `scripts/install-autostart.ps1` (tâche `Vigie` pointant sur le dépôt), puis
   `scripts/uninstall-legacy.ps1 -LegacyWorkspace <ancien dossier>` (**D11**) pour retirer la tâche
   et le raccourci hérités et mettre l'ancien espace de travail de côté en `.old`.
   Le lancer d'abord avec `-WhatIf` : son chemin élevé n'a pas pu être testé.
8. **Supprimer définitivement** `LocalWork/hyperion-control-panel.old` une fois la migration confirmée.
   Aucun script ne le fait : c'est une suppression, elle reste manuelle et volontaire.
9. ~~Menu du tray refusé (alignement vertical, survol)~~ — **VALIDÉ** par l'utilisateur.
   Ce qui a fini par marcher : ne plus se battre contre le moteur de disposition des menus
   déroulants. Il renvoie un `ContentRectangle` incohérent (`{X=-12, Y=-5, Height=44}` pour
   un item de 34 px), ce qui rend `Padding` **inutilisable pour placer le contenu** — quatre
   tentatives s'y sont perdues. La surcharge `OnRenderItemText` fixe désormais elle-même
   `e.TextRectangle` sur toute la hauteur de l'item, avec `TextFormatFlags.VerticalCenter`.
   Le survol est pleine largeur (`InsetX = InsetY = CornerRadius = 0`), borné à la largeur
   visible du menu pour ne pas se faire rogner à droite.
10. ~~L'Atelier montre d'anciennes valeurs de menu~~ — **FAIT** (**D24**) :
    `apps/atelier/palette.php` lit les constantes dans `apps/tray/tray.ps1`, la page en part
    au chargement et signale si les curseurs s'en écartent. Plus de recopie, donc plus de
    dérive. Vérifié servi : valeurs conformes, en-tête « identique au livré », aucune erreur
    console.
11. **Traduire en anglais les commentaires internes des scripts** (**D41**). Les noms de fichiers
    et les renommages sont faits ; les commentaires portent le raisonnement derrière chaque
    choix — c'est une passe fichier par fichier, jamais un `sed`. Concerne aussi les
    identifiants encore français (`$cible`, `$ecarts`, paramètre `-Verifier` de
    `scripts/install-hooks.ps1`).
12. ~~Écran de chargement (splash) jamais validé~~ — **VU et réglé** par l'utilisateur :
    jauge montant par crans en boucle, vert fixe, sous-titre à 16 px du nom.
13. **Vue de gestion des modules** — forme **validée** (**D48**) : panneau latéral large,
    liste puis configuration, avec un menu de gestion dédié ET un menu ⋮ par carte.
    **Le découpage reste à trancher** avant d'implémenter : les questions ouvertes sont
    dans D48, pas ici — un même sujet ne se documente pas à deux endroits.

14. **Refonte de la documentation publique** — demandée, **arbitrage en attente** (Q1/Q2).

    Objectif : qu'un visiteur de GitHub comprenne ce que fait Vigie, l'installe sans
    effort, et retrouve toute l'information d'usage. Attendu :
    - un **README** qui annonce ce que fait l'application et ses **points d'attention**
      (elle verrouille Windows Update, elle tourne élevée) sans noyer le lecteur ;
    - un **guide de prise en main** : installation facile, premier lancement ;
    - la documentation **en anglais ET en français** ;
    - les détails techniques atteignables **par navigation**, pas entassés dans le README ;
    - la documentation de **développement** accessible mais **nettement séparée** de celle
      de l'utilisateur.

    Existant à reprendre plutôt qu'à refaire : `PRISE-EN-MAIN.md`, `docs/REPRISE.md`
    (interne), `docs/DECISIONS-VALIDEES.md` (interne), `apps/atelier/README.md`,
    `apps/backend-pode/actions/README.md`.

15. **Améliorations mineures repérées** (passe de cohérence du 2026-08-24, aucune bloquante) :
    - `apps/atelier/index.html` écrit son propre port dans deux messages ; `location.origin`
      supprimerait la recopie ;
    - `Invoke-Native` juge `Ok` sur « code = 0 » seul : le cas 3010 (« redémarrage requis »,
      qui est un succès) n'est traité que dans `Invoke-PkgUpgrade`. À généraliser si un autre
      appelant installe des paquets ;
    - `openapi.yaml` écrit le port dans `servers.url` — documentation, mais c'est une
      deuxième source pour une valeur qui vit dans `config.psd1` ;
    - `wu-install.json` conserve `phase = termine` indéfiniment : la carte affiche « Dernière
      installation » sans limite d'âge. Volontaire pour l'instant, à revoir si ça encombre ;
    - `.claude/settings.json` porte `disableAllHooks: true`, posé pour tenter de désactiver
      l'aperçu automatique (**D47**) : **à retester après un redémarrage de session**, et à
      retirer s'il ne sert à rien.

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
- `.gitignore` exclut déjà le jeton API (`apps/backend-pode/var/secrets/`), l'état (`apps/backend-pode/var/cache/`) et les logs.
  Avant tout commit, `git status` ne doit montrer NI `var/secrets/`, NI `var/cache/`, NI `apps/*/var/log/`, NI `*.bak-*`.

### Droits de l'agent (**D40**)
`.claude/settings.json` est **versionné** et accorde les outils au niveau de l'outil
(`"Bash"`, `"PowerShell"`, sans parenthèses) : plus aucune demande de permission, y compris
sur les commandes composées. Ne **pas** revenir à des règles par motif (`Bash(git *)`) : elles
ne couvrent que les commandes analysables statiquement, ce qui était la cause du problème.
Un hook `PreToolUse` jugeant le texte a été essayé puis **retiré** (faux positifs inévitables,
+1 s par commande) — l'historique complet est dans **D40**, ne pas le refaire.

## Contraintes environnement (importantes)

> Cette section decrit la machine de travail REELLE. Elle remplace l'ancienne, qui
> decrivait une VM Linux ephemere (Cowork/`device_bash`) et n'a plus cours : le projet
> est desormais edite directement sur la machine, dans le depot git.

### Outils presents
- **PowerShell 7** (`pwsh`) : present. C'est l'outil de validation du code PowerShell.
- **Python 3.11** : present (sert a `apps/tray/assets/generate-icons.py`).
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
- **JavaScript du front** : charger `apps/frontend-web/index.html` en `file://` dans un navigateur et
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
- `apps/backend-pode/var/secrets/` (jeton API), `apps/backend-pode/var/cache/`, `apps/*/var/log/`, `*.bak-*`.
  Le `.gitignore` les couvre deja ; verifier malgre tout `git status` avant chaque commit.
