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

### Disciplines de validation — dans cet ordre, avant toute livraison

| Ce qu'on touche | Ce qu'on lance | Ce que ça attrape |
|---|---|---|
| n'importe quel `.ps1` | `[Parser]::ParseFile` sur chaque fichier | la syntaxe, **rien de plus** |
| une **sonde** | `pwsh -File .\scripts\check-probes.ps1 -Only <sonde|module>` (dev, ciblé — D51) puis `-All` avant livraison | l'exécution réelle + les invariants **D49**/**D50** |
| `apps/frontend-web/index.html` | recharger la page **servie** (`http://127.0.0.1:47600`) et lire la console | erreurs de syntaxe et d'exécution JS |
| un contrat (`openapi.yaml`) | relecture — aucun parseur YAML sur la machine | rien d'automatique, à dire tel quel |

**Le parseur ne suffit pas** (**D50bis**) : un paramètre passé deux fois le franchit sans un
mot et fait disparaître une carte à l'exécution. C'est arrivé, livré et annoncé comme fait.

**Toute écriture scriptée d'un fichier source est ATOMIQUE** : écrire dans `fichier.tmp`,
vérifier la taille, puis `os.replace`. Un script Python qui plante en plein `write()` sur
le fichier ouvert en 'w' laisse un fichier TRONQUÉ — c'est arrivé le 24/08 (index.html à
0 octet, commité et poussé sur main par la chaîne shell qui suivait). Et ne jamais chaîner
`git commit` derrière un script par un simple retour à la ligne : `&&` uniquement.

**Un fichier rendu (`.html`) ne s'édite JAMAIS avec les outils Edit/Write** (**D47**) :
l'aperçu du panneau ouvre alors le fichier en `file://` et vole le focus de l'utilisateur.
Passer par un script de remplacement exact — et relancer ensuite le garde-fou de chaînes JS
(chaîne monoquote non terminée, expression régulière coupée par un retour à la ligne : deux
couches d'écriture ont déjà mangé des échappements).

**Redéployer** = commit sur la branche, `git merge --no-ff` dans `main` depuis le dépôt
principal, `git push` des deux, puis :
`Stop-Process` sur l'écouteur du port 47600, puis `pwsh -File scripts/tray.ps1 -Restart`.
**Relancer le tray ne relance PAS le serveur** : l'ancien devient orphelin et `$startServer`
sort aussitôt puisque le port répond — on sert alors indéfiniment du code périmé.
- **Toucher une sonde ⇒ lancer `scripts/check-probes.ps1`** : le parseur ne voit pas qu'un paramètre est passé deux fois, l'exécution si (**D50bis**).
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
- **Verrouillage Windows Update : natif** (plus aucun script hors dépôt). `lib/common.ps1`
  porte `Get-UpdateTaskCatalog` (LA liste des dossiers, tâches et services — la sonde,
  les actions et l'audit y puisent), `Get-UpdateLockState` (lecture complète),
  `Set-UpdateLock` (unique porte d'entrée en écriture, refuse sans élévation et relit
  l'état après coup) et `Invoke-UpdateAudit` (rapport texte + JSON dans `var/log/`).
  `ToolsPath` est *préféré* s'il porte `update-mode.ps1`, jamais requis.
- **VBS / intégrité mémoire : natifs** aussi. `Get-DeviceGuardCatalog` (cles + libellés),
  `Get-DeviceGuardState` (distingue `configured` / `running` / `requested` / `effective`),
  `Set-DeviceGuardFeature` (unique porte d'entrée, sauvegarde `.reg` dans `var/log`, refuse
  sans élévation, **relit le registre** — jamais l'état actif, qui ne bouge qu'au
  redémarrage) et `Invoke-DeviceGuardToggle` (décision + compte rendu, partagé par les deux
  actions). La bascule s'appuie sur `effective` : recliquer avant de redémarrer **annule**
  la demande au lieu de réécrire la même valeur.
  La carte affiche « En attente de redémarrage » et propose `system-restart` **uniquement**
  après une bascule de Vigie — pas sur un simple écart registre/actif, qui peut être
  permanent (valeur imposée par l'UEFI ; c'est le cas sur cette machine : registre VBS=0,
  VBS pourtant en cours).
- `Test-RestartCountdown` (`common.ps1`) : « un redémarrage différé court-il encore ? »,
  partagé par les cartes Windows Update et virtualisation.
- **`ToolsPath` / `Get-AdminRoot` ne conditionnent plus aucune fonction.** Seule
  `open-folder` les utilise, et la sonde `history.probe.ps1` **ne propose pas le bouton**
  si le dossier n'est pas configuré ou n'existe pas.
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
13. **Vue de gestion des modules** — **LIVRÉ** (D48, 24/08 après-midi) : `module.psd1`
    par dossier de sondes, choix utilisateur dans `config/modules.local.psd1` (ignoré par
    git, motif ajouté après un faux pas), `units[]` au contrat même désactivés,
    `GET /units` + `POST /units/{id}`, tiroir « Modules » (bouton ▦ + menu ⋮ en haut à
    droite de chaque carte, avec cases de notification par carte). Éprouvé en réel :
    WSL coupé → carte et groupe disparus ; rallumé → recalcul et retour.
    Reste ouvert : quelles CLÉS DE CONFIGURATION exposer par module (seule question
    restante de D48 — rejoint la Q1 de l'historique sur les seuils).

14. **Documentation publique** — livrée : `README.md` (EN) et `README.fr.md` (FR) se
    renvoyant l'un à l'autre, `docs/en/` et `docs/fr/` en miroir, développement séparé.
    Licence **MIT** (`LICENSE`). **Reste** : le workflow de publication n'est pas versionné,
    le jeton GitHub n'ayant pas la permission *Workflows*. Son YAML complet est dans
    `docs/en/development/README.md` et `docs/fr/developpement/README.md`, à coller via
    l'interface web de GitHub ou à débloquer en accordant la permission.

15. **Archive de distribution** — livrée : `scripts/build-release.ps1` produit
    `dist/vigie-0.1.zip` (93 fichiers). Elle exclut l'Atelier, les documents de travail
    internes et tout ce qu'ignore `.gitignore` ; un garde-fou **sort en code 2** si un
    secret est forcé dans l'index. Aucune release n'a encore été publiée.

16. **Autonomie du produit** — le verrouillage Windows Update, l'audit et les bascules
    VBS/HVCI sont **internalisés** : `ToolsPath` et `Get-AdminRoot` ne conditionnent plus
    aucune fonction. **Reste à éprouver depuis un serveur ÉLEVÉ** : aucune écriture réelle
    n'a été appliquée (pose du verrou, bascule VBS/HVCI, sauvegarde `.reg`), ni le
    comportement après un vrai redémarrage.

17. **Traduire en anglais les commentaires internes des scripts** (**D41**). Les noms de
    fichiers et les renommages sont faits ; les commentaires portent le raisonnement
    derrière chaque choix — passe fichier par fichier, jamais un `sed`. Concerne aussi les
    identifiants encore français (`$cible`, `$ecarts`, paramètre `-Verifier` de
    `scripts/install-hooks.ps1`).

18. **Trois propositions en attente d'arbitrage**, visibles dans l'Atelier (section
    « Propositions à évaluer », `http://127.0.0.1:47610/apps/atelier/index.html`) :
    étendre la vérification du contrat aux actions et au front ; garder un historique pour
    signaler les dérives ; faire alerter le tray sur changement d'état.

19. **Améliorations mineures repérées, aucune bloquante** :
    - `apps/atelier/index.html` écrit son propre port dans deux messages (`location.origin`
      supprimerait la recopie) ;
    - `Invoke-Native` juge le succès sur « code = 0 » seul ; le cas 3010 (« redémarrage
      requis », qui est un succès) n'est traité que dans `Invoke-PkgUpgrade` ;
    - `openapi.yaml` écrit le port dans `servers.url`, deuxième source pour une valeur qui
      vit dans `config.psd1` ;
    - `wu-install.json` conserve son résultat sans limite d'âge : la carte affiche
      « Dernière installation » indéfiniment ;
    - `.claude/settings.json` porte `disableAllHooks: true`, posé pour tenter de désactiver
      l'aperçu automatique (**D47**) : **sans effet constaté**, à retester après un
      redémarrage de session et à retirer s'il ne sert à rien.

## État de la machine de l'utilisateur — à savoir avant de conclure quoi que ce soit

- **Windows Update est VERROUILLÉ** (`NoAutoUpdate=1`, verrou ACL posé) : c'est voulu, c'est
  la fonction phare. Les actions de Vigie lèvent le verrou le temps d'agir puis le reposent.
- **Un redémarrage est en attente** depuis l'installation de mises à jour.
- **Écart permanent registre/actif sur VBS** : le registre dit 0, VBS tourne pourtant. Ne
  jamais en déduire une bascule en attente — la proposition de redémarrage ne doit
  apparaître qu'après une bascule faite **depuis Vigie**.
- **Edge est installé mais ne démarre pas** (sort en moins d'une seconde, sans fenêtre).
  Chrome est le navigateur par défaut et fonctionne.
- **`netsh wlan` échoue** (erreur 5) : ni force de signal, ni SSID par ce chemin.
- **git n'est que dans le PATH utilisateur**, pas machine : un processus élevé ne le trouve
  pas sans chemin résolu.
- **Node n'est pas installé** et ne le sera pas (**D06**) ; **aucun parseur YAML** non plus.


## Travailler avec des sous-agents (autorisé par l'utilisateur)

**Cadre posé par l'utilisateur** : jusqu'à **3 sous-agents**, chacun dans **son propre
worktree**, chacun **fusionne lui-même** dans `main`. Ils sont **persistants** : on leur
renvoie un sujet plutôt que d'en relancer un neuf, ils gardent leur contexte. « Ne les gave
pas » — un sujet à la fois, cadré ; le rôle de l'agent principal est l'**orchestration**.

### Répartition qui a fonctionné

Découper par **fichiers disjoints**, pas par thème : deux agents dans `common.ps1` en même
temps, c'est un conflit garanti. Répartition tenue :
sondes d'un côté · gestionnaires de paquets et backend de l'autre · documentation seule
(elle ne touche aucun `.ps1`). L'agent principal garde le front (`index.html`) et le socle.

### Ce qu'un brief doit contenir, sans exception

1. **Où lire** — `docs/REPRISE.md` puis les décisions précises (`D15`, `D43`, `D47`…), pas
   « lis la doc ».
2. **Le sujet, un seul**, avec le modèle existant à copier quand il y en a un (« étudie
   `wu-list-pending.action.ps1` avant d'écrire »).
3. **Les règles non négociables** : français accentué pour l'utilisateur, commentaires sans
   accents, identifiants en anglais, points de suspension réservés à une action en cours,
   validation par le Parser **et** `check-probes.ps1`, jamais de ligne `Co-Authored-By`.
4. **Les pièges connus**, nommés — sinon ils les retrouvent à leurs frais : `--disable-interactivity`
   pour winget, `netsh wlan` qui échoue ici, l'aperçu `file://` qui vole le focus.
5. **Ce qu'il ne doit PAS toucher** : les fichiers d'un autre agent, et le **redémarrage du
   serveur** (port 47600) que l'agent principal se réserve.
6. **La prudence machine** : « ne laisse pas la machine dans un état différent de celui où
   tu l'as trouvée » — indispensable dès qu'on touche au verrou Windows Update ou à VBS.
7. **Le format de réponse attendu** : deux ou trois phrases — ce qui a changé, ce qui a été
   vérifié **en conditions réelles**, ce qui reste incertain.

### Ce qu'ils ont apporté que je n'aurais pas trouvé seul

Ils **exécutent** au lieu de relire, et remontent ce que le brief avait de faux. Exemples
réels : `$pid` est en lecture seule et l'exception était avalée par un `catch` vide ; le
découpage des colonnes winget donnait une version comme identifiant de paquet ; une clé de
registre absente faisait échouer le verrou **en silence** sur une machine neuve ; et surtout
la correction de mon propre brief — `Get-AdminRoot` existe à côté de `Get-ToolsPath`, mon
`grep` ne voyait que le second.

**Leçon** : un agent qui conteste le brief a souvent raison. Vérifier soi-même avant de
trancher, puis lui redonner le sujet corrigé.

### Limites constatées

- L'isolation du worktree peut **refuser** les commandes git visant le dépôt partagé ; ils
  contournent alors par `git push origin HEAD:main` depuis leur worktree. Conséquence :
  **le `main` local se retrouve en retard**, faire `git pull` avant toute fusion.
- Ils ne peuvent pas juger un rendu visuel : ce qui se voit reste à l'agent principal, via
  la page **servie** (jamais `file://`).


## Session du 24/08 après-midi — livré et vérifié

- **D51** : `check-probes.ps1 -Only` (boucle de dev ciblée) ; passe par défaut ~2 s au lieu
  de 19 s (sondes coûteuses inchangées vérifiées sur leur dernière sortie réelle) ; `-All`
  avant livraison.
- **D52** : journal `var/cache/probe-runs.jsonl` — chaque exécution réelle d'une sonde,
  avec durée et origine (`Write-ProbeRun`/`Get-ProbeRuns`). Nourri par `Get-State` ET par
  le contrôleur.
- **D53** : historique validé — conceptions cible et migration dans `docs/conception/`
  (réalignées sur D52 par le sous-agent). **Q1** (seuils de dérive) et **Q2** (restitution
  des événements) attendent l'arbitrage — visibles dans l'Atelier, page Propositions.
- **D54** : notifications du tray sur bascule de module — guetteur dans `apps/tray/tray.ps1`
  (lecture du cache d'état, jamais /state), réglages `config/notifications.local.json` via
  `GET/POST /notifications`, popin ⚙ dans l'en-tête. **Non éprouvé en réel : la bulle
  elle-même** (aucun module n'a basculé depuis le déploiement). Deux pièges corrigés :
  `modules` est un dictionnaire (pas PSObject.Properties), et Pode livre le corps JSON en
  dictionnaire aussi.
- **D55** : Atelier réorganisé — un sujet = une page (`tray-marque`, `tray-menu`, `splash`,
  `propositions`), accueil en sommaire En cours / Archivé, lien « Ouvrir Vigie » sur toutes
  les pages via `vigie.php` (port LU dans la config, jamais recopié).
- Wi-Fi scindé en « Lien Wi-Fi » + « Stabilité » (sous-agent, vérifié en réel ; le chemin
  « coupures détectées » n'a pas pu être observé).
- « Redémarrage en attente » déplacé : carte **Windows** (avec action) ; la carte mises à
  jour propose aussi le redémarrage quand la dernière installation le requiert (le bouton
  ne s'y voit qu'après une installation lancée depuis Vigie).
- **D56** : menu **Paramètres** unique (⚙) — onglets Notifications / Modules / Apparence /
  À propos ; thème rapide au footer près du logo GitHub, GitHub retiré de l'en-tête ;
  le ⋮ d'une carte ouvre l'onglet Modules sur son module. Tout nouveau réglage y va.
- Front : footer **fixe**, `toast()` réparé (visait un élément disparu), favicon versionnée
  par le build (cache navigateur), bouton **Atelier** dans l'en-tête **uniquement si le
  serveur local répond** (détection côté serveur, `Get-AtelierUrl` dans /health), bouton de
  thème en icône.


### Fin de journée du 24/08 — suite et fin de session

- **D56** livré puis REFONDU : menu Paramètres = tiroir **large (720 px)** à navigation
  latérale (icônes : ⚑ notifications, 🧩 modules, ☀ apparence, i-cerclé à propos) ; le
  bouton rapide de thème vit au **footer**, GitHub retiré de l'en-tête (footer + À propos).
  Apparence en **cartes-radio** de thèmes (extensibles). Onglet Modules : sous-sections
  **Notifications** (un switch par notification — aujourd'hui une par carte, mais le modèle
  est « n notifications par module », demain déclarées) et **Paramètres**.
- **D57** livré : `Config` (défauts, versionnés dans `module.psd1`) + `Parameters`
  (déclaration) + surcharges dans `config/parameters.local.json` via
  `GET/POST /parameters(/unit)` ; `Get-ModuleSetting` = seul point de lecture. Premier cas
  réel éprouvé de bout en bout : seuil d'alerte du disque (60 → 150 → warn → défaut → ok).
  Un changement invalide les sondes du module ; le panneau se réaffiche aussitôt, les
  cartes se recalculent derrière. **Candidats suivants** : TTL par sonde, paquets ignorés
  (winget/choco), cible de latence, rétention d'historique.
- **Design système** : `docs/DESIGN.md` (DA en 5 principes + tableau des composants) +
  page Atelier `design-systeme.html` — **palette lue en direct** dans le front par
  `tokens.php` (même principe que palette.php), composants reproduits en miroir.
  DISCIPLINE : toute évolution visuelle met la page à jour dans la même livraison.
- **Flux paquets cohérent** : pendant = « 1 sur 3 en cours… (depuis N min) » + liste ;
  après = « Dernière mise à jour : … réussie / N ÉCHEC(S) » conservé dans la carte
  (`sel` posé par Start-PkgJob, `last` écrit par le worker). GameInput : l'échec venait de
  l'installateur MSI (1603) — cause probable : redémarrage Windows en attente.
- **Auto-guérison du serveur** : panne réelle vécue — Pode tenait le port mais répondait
  408 à tout (NullReferenceException du listener). Le tray détecte désormais « port ouvert
  + /health muet ×3 » et tue/relance le serveur seul.
- **Icônes** : règle consignée (police + habillage CSS, SVG réservé à la marque).
  **CHOIX EN ATTENTE** : fonte d'icônes — voie 1 recommandée (Bootstrap Icons vendorisée,
  MIT, un woff2 dans le dépôt) ou voie 2 (fonte maison, fonttools à installer).
- **Q1/Q2 arbitrés** (voir D57) ; page Propositions de l'Atelier à jour.
- **Incident consigné** : un script d'édition planté a laissé `index.html` à 0 octet,
  commité et poussé — d'où la discipline « écriture atomique » (plus haut) et l'interdit
  de chaîner git derrière un script par un simple retour à la ligne.

- **Autostart en panne au logon du 24/08 au soir** : la tâche « Vigie » échoue en
  0xC0070154 — pwsh vient du Store (MSIX) et son paquet n'est pas prêt à la seconde du
  logon. Correctif dans `install-autostart.ps1` (délai PT45S + 3 reprises/1 min), mais la
  tâche DÉJÀ INSTALLÉE n'a pas pu être modifiée sans élévation : **relancer une fois
  `scripts/install-autostart.ps1` (UAC) pour l'appliquer**. En attendant, relance manuelle
  propre : `Start-ScheduledTask -TaskName Vigie` (élevé sans UAC). L'Atelier se lance par
  `apps/atelier/atelier.ps1` (jamais élevé).

### File de travail (dans l'ordre)

1. **Fonte d'icônes** — dès l'arbitrage (voie 1 prête à faire).
2. **Historique** — implémentation par étapes par un sous-agent (conceptions validées,
   `docs/conception/`), étape 1 = s'appuyer sur `probe-runs.jsonl` (D52).
3. **Étendre les paramètres** (D57) aux candidats listés ci-dessus.
4. **Notifications déclarées** : passer de « une par carte » à `notifications[]` par module.
5. Fond ancien : éprouver verrou/VBS depuis serveur élevé après un vrai redémarrage ;
   commentaires en anglais (D41) ; workflow GitHub à coller ; bulle de notification du
   tray jamais observée en réel.

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
