# Changelog

## [non publie]
### Ajoute
- Scaffold initial du projet (arborescence, conventions, doc 4 volets).
- Contrat REST v1 (`api/openapi.yaml`).
- Maquette front generique (thèmes + modules + actions), branchee sur un mock.
### A faire
- (Vide : les trois points de ce bloc ont ete livres.)
  - Backend Pode implementant le contrat -> livre le 2026-08-19.
  - Modele de sondes/actions auto-decouvert par theme -> livre le 2026-08-19.
  - Icone barre systeme + lancement a l'ouverture de session -> livre le 2026-08-20 (b).
    NB : la fenetre dediee utilise le mode `--app` d'Edge/Chrome, PAS WebView2 comme
    initialement prevu.

## 2026-08-19 — Backend + front branches
### Ajoute
- Backend Pode : `backend/start.ps1`, `backend/server.ps1`, `backend/lib/common.ps1`.
- Endpoints : `/health`, `/state`, `/modules/{id}`, `/actions` (jeton Bearer).
- Sondes Windows Update : `wu-lock`, `wu-history` (lecture directe).
- Actions : `update-mode-on`, `update-mode-off`, `run-audit`, `open-folder`.
- Front v2 : consomme le contrat (API en direct + repli mock).
- Documentation : `doc/en/developing/conventions.md`, `doc/en/developing/technologies.md`, mise a jour des
  4 volets ; fichier de suivi `SUIVI.md` ; fichier d'init renomme
  `PRISE-EN-MAIN.md` (nom non-standard).

## 2026-08-19 (b) — Scripts install/lancement
### Ajoute
- `backend/install.ps1` (idempotent) : NuGet, PSGallery, Pode, jeton — sans invite.
- `backend/run.ps1` : lancement + ouverture navigateur ; options -Admin, -NoBrowser.

## 2026-08-19 (c) — Idempotence
### Modifie
- `start.ps1`/`run.ps1` : garde "deja en cours" (via `Test-ServerUp`), plus de
  double demarrage.
- `doc/en/developing/conventions.md` : regle "tous les scripts idempotents".

## 2026-08-19 (d) — Organisation des ports
### Modifie
- Port par defaut 8787 -> 47600 ; documente comme configurable.
### Ajoute
- `LocalWork/PORTS.md` : registre des ports (plage 47600-47699).
- `doc/en/developing/conventions.md` : convention d'allocation des ports.

## 2026-08-19 (e) — Fix encodage PowerShell 5.1
### Corrige
- `.ps1`/`.psd1` reconvertis en ASCII pur (les accents/tiret cadratin cassaient
  l'analyse en Windows PowerShell 5.1). Regle documentee dans conventions.md.

## 2026-08-19 (f) - Cible PowerShell 7 + UTF-8
### Modifie
- `install/start/run.ps1` : bascule auto en pwsh (PS7), UTF-8 natif ; install.ps1
  installe PS7 via winget si absent. Lanceurs conserves en ASCII pour la bascule.
- `doc/en/developing/conventions.md` : PS7 + UTF-8 remplace la contrainte ASCII generale.

## 2026-08-19 (g) - Journalisation fichier
### Ajoute
- `lib/common.ps1` : `Get-LogDir`, `Write-Log`.
- `install.ps1`/`start.ps1` : transcript + journalisation dans backend/logs/.
- `server.ps1` : logs Pode (erreurs + requetes) sur fichier.

## 2026-08-19 (h) - Front operationnel + UI
### Corrige
- Balise <script> non fermee dans index.html (JS non execute).
### Ajoute
- UI-STATUS : accent de couleur + icone de statut par carte.
- UI-ACTION-TRACK : panneau de suivi des actions (etat + message + heure).

## 2026-08-19 (i) - Statut par parametre
### Ajoute
- Contrat : champ `status` par `Field` (ok/warn/error/neutral).
- Sondes wu-lock / wu-history : statut renseigne par ligne.
- Front : pastille de couleur + valeur teintee par parametre.

## 2026-08-19 (j) - Widgets Disque/WSL/Securite + acces permanent + aide
### Ajoute
- Sondes system/disk, wsl/wsl, security/vbs + actions associees.
- Field.help (contrat) + infobulles front.
- install-autostart.ps1 / uninstall-autostart.ps1 (tache au logon + raccourci).

## 2026-08-19 (k) - UX statuts/actions
### Corrige
- Icone d'aide (glyphe non supporte) -> "i" dessine en CSS.
- Bug 500 : catch de Get-State utilisait $_ (l'erreur) au lieu du nom de fichier.
- New-ModuleObject accepte 'neutral' (statut module info).
### Ajoute
- Depliage du detail par parametre (clic sur "i"), colore selon le statut.
- Field.status 'neutral' rendu (anneau creux + badge Info).
- Action.help : tooltip par action + explication reprise dans la confirmation.

## 2026-08-19 (l) - Widgets complets + vue dense
### Ajoute
- Sondes : system/os (edition+activation), system/perf (RAM/CPU/uptime),
  security/defender (temps reel + definitions + derniere analyse),
  security/firewall (profils), network/net (connexion/IP/VPN),
  windows-update/pending (MAJ detectees, recherche LOCALE sans installer).
- Theme 'Reseau'.
### Modifie
- Front : vue compacte (beaucoup d'infos d'un coup) ; delai /state 30 s ;
  rafraichissement auto 60 s.

## 2026-08-19 (n) - Securite + remediation + UI tuiles
### Securite (revue : doc/en/developing/security-review.md)
- CRITIQUE : POST /actions permettait une traversee de chemin via `type`
  (execution de script arbitraire sur serveur eleve). Corrige : liste blanche +
  confinement du chemin (route + Invoke-ActionById).
- Anti-CSRF : controle d'origine locale sur les requetes modifiantes.
### Ajoute
- Remediation : Field.fixAction (action programmable) / Field.guide (instructions
  manuelles) ; bouton "Resoudre" ; popin d'instructions.
- Action.kind (immediate/confirm/manual) + icones ; confirmation explicative.
### Modifie
- Vue en tuiles ; valeur coloree selon le statut ; details deplies conserves
  entre les refresh ; icone "i" fiable.

## 2026-08-19 (o) - UI lisible + elevation
### Corrige
- Retour aux LIGNES lisibles (label a gauche, valeur coloree a droite) au lieu
  des tuiles ; contenu en pleine largeur.
### Modifie
- start.ps1 / run.ps1 : auto-elevation (demande UAC si besoin) pour que le
  serveur tourne avec les droits. Protections maintenues (voir security-review.md).

## 2026-08-19 (p) - antivirus reel, reseau, pare-feu, version, UX refresh
### Corrige
- Antivirus : lecture via SecurityCenter2 -> affiche l'antivirus REEL (Avast...),
  plus seulement Defender.
- Pare-feu : comparaison d'etat robuste (etait "Non" a tort).
- Reseau : connectivite detectee sur tout profil (IPv4/IPv6).
- Texte ACL clarifie (serveur eleve par defaut).
### Ajoute
- Reseau : action "Mesurer debit/latence" (ping + ~10 Mo), resultat memorise
  (.state/netmeasure.json) et affiche.
- Version applicative (Get-AppVersion) exposee (/health, /state, injectee dans
  la page) : la page se RECHARGE seule si la version serveur change.
- Indicateur "Actualisation en cours" (spinner + bouton desactive) a chaque refresh.

## 2026-08-19 (q) - masonry, valeur en face, accents, cache
### Modifie
- Cartes en MASONRY (colonnes qui se remplissent) au lieu de bandes par theme ;
  le theme devient une etiquette sur la carte.
- Champs : valeur en face du label (passe dessous si longue, alignee a droite).
- ACCENTS ajoutes partout (labels/aides des sondes, themes) - possible en PS7/UTF-8.
### Ajoute
- Cache par sonde avec TTL (perf 8s ... os 3600s) : rafraichissements legers,
  plus de recalcul complet a chaque fois. Invalidation auto si le code des
  sondes change (empreinte _codeStamp).

## 2026-08-20 (a) — Verrou ACL, réseau, cache ciblé, modales in-app
### Corrige
- Verrou ACL : `takeown`/`icacls` fonctionnaient bien (code 0, DENY posé) — le
  défaut venait de la DÉTECTION (Windows FR affiche « Système »). Détection
  refaite via `icacls` (chaîne `(DENY)`, non localisée) : le verrou marche.
- Réseau : détection via .NET (`System.Net.NetworkInformation`) au lieu de
  `Get-Net*` (CIM), qui renvoyait du vide.
### Ajoute
- Invalidation ciblée du cache après une action (`result.invalidate`).
- Front : modales in-app (fin des popups navigateur), boutons « occupés »,
  icône de rafraîchissement par carte, toasts de suivi détachés.
### Modifie
- Statut de carte = santé fonctionnelle : un avertissement de ligne sans impact
  (ex. verrou ACL) ne fait plus passer la carte en orange.
- Boutons « Résoudre » typés, libellés cliquables, thème clair plus coloré.

## 2026-08-20 (b) — App barre système, cache par sonde, débit montant
### Ajoute
- App barre système `backend/tray.ps1` : serveur lancé en fond (cache chaud) +
  icône permanente de statut + menu (Ouvrir / Redémarrer / Journaux / Quitter).
  L'autostart au logon (tâche planifiée, RunLevel Highest, via
  `install-autostart.cmd`) pointe désormais dessus.
- Icône du tray dessinée en GDI+ (`$setIcon`) : jauge en anneau, sens inverse
  (conforme = jauge pleine), aiguille large à la couleur du statut avec liseré
  en teinte foncée (facteur 0,72) et point blanc central.
- Débit **montant** (upload ~5 Mo) en plus du débit descendant.
- Filtre rapide par groupe (chips) en haut de page.
### Modifie
- Cache : invalidation **par sonde** (mtime) au lieu de globale — éditer une
  sonde ne recalcule que celle-ci. TTL allongés (wsl 600 s, verrou 600 s,
  MAJ en attente 900 s) ; délai front de `/state` porté à 90 s (1er calcul à
  froid).
- `netmeasure.json` : écriture par **fusion** (`Update-StateJson`) — la mesure
  de débit n'efface plus l'IP publique.
- Gestionnaires de paquets : la valeur affiche la version seule, le détail passe
  dans le Guide.
- Bouton « Ouvrir Windows Update » déplacé sur la carte « Mises à jour en
  attente » ; icône « Résoudre » à la couleur du texte ; message d'erreur
  accentué (UTF-8).

## 2026-08-21 (a) — Fin des 408 sur /state, icône = statut de l'app, fenêtre dédiée
### Corrige
- **408 sur `/state` (effet troupeau)** : `Get-State` passe en SINGLE-FLIGHT —
  un seul recalcul à la fois (verrou nommé `Local\HcpStateRecompute`, renommé
  `Local\VigieStateRecompute` le 22/08 ; gestion du mutex abandonné), les autres
  requêtes servent le cache immédiatement. Écriture du cache INCRÉMENTALE et
  ATOMIQUE (chaque sonde terminée est conservée), sondes lentes calculées en
  dernier.
- Ligne « État » du menu du tray invisible (item désactivé, texte gris sombre
  sur menu sombre) : passée en `ToolStripLabel` à couleur lisible.
### Modifie
- **Icône du tray = statut de l'APP** (et non des composants), lu via `/health` :
  vert = en marche, orange = démarrage, rouge = erreur ou arrêt. Trois états
  seulement, pas d'« inconnu ». La charge `/state` est retirée du tray.
- Chargement non bloquant côté front : les cartes restent affichées pendant
  l'actualisation ; repère « Chargement… » seulement au 1er affichage.
### Ajoute
- **Fenêtre dédiée** : « Afficher l'application » ouvre le navigateur en mode
  `--app` (fenêtre sans onglets) ; entrée « Ouvrir dans le navigateur » ajoutée.
  Menu : Afficher / Ouvrir navigateur / État / Relancer / Redémarrer serveur /
  Journaux / Quitter.

## 2026-08-21 (b) — MAJ des paquets, notifications, titre générique
### Ajoute
- Action `pkg-check-updates` (à la demande) : MAJ disponibles par gestionnaire
  (winget, pip, npm, choco, scoop, gem), affichées « (N MAJ) » avec la liste
  dans le détail ; carte orange s'il existe des MAJ ; bouton « Vérifier les
  mises à jour ».
- Notifications refaites : toasts empilés à disparition automatique (succès
  4,5 s, erreur 9 s), bouton cloche et tiroir latéral droit (historique
  supprimable, « Tout effacer ») ; supprimer une notification retire aussi son
  toast.
### Corrige
- Double-clic sur l'icône du tray : une variable d'environnement nulle cassait
  `Join-Path`, donc l'ouverture en `--app` ; `openApp` rendu robuste.
- Débordement des textes longs (chemins) : `overflow-wrap: anywhere`.
- Icône « i » des champs recentrée (SVG au lieu du glyphe italique).
### Modifie
- **Généricité** : le titre affiche le nom de machine calculé
  (`$env:COMPUTERNAME`, via `/state.host`) au lieu d'un nom codé en dur.
- Icône du tray : queue d'aiguille et graduations supprimées (bruit à 16 px, lu
  à tort comme un « bug d'aiguille ») ; l'aiguille part du centre.
- Chargement initial épuré.

## 2026-08-22 (a) — Actions non bloquantes, MAJ des paquets, résolutions, topbar
### Ajoute
- Socle générique `Start-DetachedAction` (worker `pwsh` détaché, fenêtre cachée)
  : une action lente répond « en cours » et travaille en tâche de fond sans
  bloquer le reste. L'action renvoie `result.async` + `module` ; le front met la
  carte en « occupé » et l'interroge jusqu'à la fin.
- Paquets : **une carte par gestionnaire**, avec vérification ET mise à jour en
  tâche de fond ; chaque carte s'actualise seule (polling par carte). Worker
  unique `backend/workers/pkg-job.worker.ps1` (check/upgrade), lancé par
  `Start-PkgJob`.
- WSL : trio d'actions Démarrer / Redémarrer / Arrêter (seuls les boutons
  pertinents sont affichés) — actions `wsl-start` / `wsl-restart` avec
  invalidation de la sonde.
### Modifie
- Boutons de résolution : ils prennent le **libellé de l'action** (fin du
  « Résoudre » générique) et n'apparaissent que si une action existe. Icône
  « boîte-flèche » = ouvre un logiciel externe ; icône « fenêtre » = ouvre une
  popin.
- Résolutions câblées : Latence → mesure (`net-speedtest`) ; Windows Update
  « Détectées » → Ouvrir Windows Update (note raccourcie).
- WSL : champ Statut « Actif / Inactif » coloré, au lieu de « Oui / Non ».
- Topbar : statut intégré (texte + couleur) ; l'ancienne barre de mode devient
  un simple liseré coloré (3 px) reflétant l'état de connexion à l'API
  (vert = direct, orange = maquette, rouge = erreur).
- `Update-StateJson` sérialisé par mutex inter-processus ; `Remove-ProbeCache`
  factorisé.
### Corrige
- Halo des cartes « en cours » : ne déborde plus du rayon d'arrondi.

## 2026-08-22 (b) — Renommage Vigie, écran de chargement, lien GitHub
### Modifie
- **Interface « Vigie »** à la place de « Control Panel » (titre d'onglet,
  sous-titre, `document.title`, tray) — **D03**. Le titre principal reste le
  **nom de la machine**, dynamique.
- **Nom de machine éliminé du projet** (**D05**) : ce n'était pas cosmétique
  mais un défaut de généricité. Tâche planifiée `Vigie`, raccourci `Vigie.url`,
  mutex `VigieTray` / `Local\VigieState_*` / `Local\VigieStateRecompute`, types
  .NET `VigieNative` / `VigieDarkColors`, variables d'environnement
  `VIGIE_BACKEND` / `VIGIE_TOKEN` / `VIGIE_PORT` (ex-`HCP_*`), titre
  `api/openapi.yaml` « Vigie API », lanceur `backend/demarrer-vigie.vbs`.
  Archive `doc/maquettes-validees/` volontairement non retouchée.
- **DRY** : l'URL du dépôt devient une constante unique par langage — `REPO_URL`
  (front) et `$RepoUrl` (tray) ; le libellé affiché est dérivé de l'URL. Nombres
  magiques du front hissés en constantes (`REFRESH_MS`, `VERSION_POLL_MS`,
  `SPLASH_*`) ; nom de machine factorisé dans `setMachineName()` ; ouverture
  d'URL factorisée côté tray (`$openUrl`, avec gestion d'erreur et
  journalisation).
### Ajoute
- **Écran de chargement** (**D08**) : `#splash` plein écran présent dans le HTML
  statique (donc visible avant même l'exécution du JS), « Vigie » en gros
  (clamp 54–88 px), sous-titre = nom de la machine dès qu'il est connu, marque
  **D01** redessinée en SVG à la géométrie exacte du générateur `.ico` (anneau
  0,45 ; piste 0,35 à 11 % ; 7 graduations ; aiguille à talon −0,06 avec liseré
  assombri 0,72 ; moyeu et point blanc), aiguille animée de 0 à la fraction
  « démarrage » 0,50. Il s'efface au **premier** chargement, réussi ou en erreur
  (sinon l'erreur resterait cachée), avec une durée minimale de 550 ms
  (anti-clignotement) et un garde-fou à 90 s ; `prefers-reduced-motion` respecté.
- **Lien GitHub** (**D09**) accessible à quatre endroits : splash, icône
  discrète dans la topbar, pied de page, et « À propos de Vigie » dans le menu
  du tray. Ouverture en `_blank` + `rel="noopener"`, jamais dans la fenêtre
  `--app` qui n'a pas de barre d'adresse. Les liens du front sont câblés par
  `wireRepoLinks()` via l'attribut `data-repo-link`.
### Verifie
- Parser PowerShell OK sur `tray.ps1`, `common.ps1`, `server.ps1`, `start.ps1`,
  `run.ps1`, `install-autostart.ps1`, `uninstall-autostart.ps1`.
- Front chargé en `file://` : script exécuté intégralement (aucune erreur de
  syntaxe), 3 liens câblés, 7 graduations, aucun débordement horizontal.
  Node n'est pas installé et ne l'est pas devenu (**D06**).
### A faire
- **D07** : la tâche planifiée pointe encore sur l'ancien espace de travail
  `LocalWork/hyperion-control-panel` ; le repointage sur le dépôt exige une
  session élevée (RunLevel Highest).

## 2026-08-24 — Paquets : mise à jour au choix, interface du gestionnaire
### Ajoute
- **Choisir les paquets à mettre à jour**, gestionnaire par gestionnaire, sur le
  modèle exact de Windows Update (**D45**) : nouvelle action
  `pkg-list-updates` (`kind: dialog`, `severity: fix`) qui renvoie
  `result.choose`, `result.action` et `result.updates[]`. Le bouton
  « Mettre à jour » de la carte ouvre désormais cette fenêtre au lieu de
  demander un simple oui/non — mettre à jour « tout » sans voir quoi n'est pas
  un choix.
- **Identifiant ciblable par paquet** dans `Get-PkgUpdates` (`pkgs[]` :
  `id`, `titre`, `detail`) — colonne Id pour winget, nom pour Chocolatey et pip.
  Les chaînes d'affichage (`items`) sont inchangées. Le catalogue porte un
  champ `upgOne` (args de mise à jour d'UN paquet, `{pkg}` substitué) : c'est
  lui, et lui seul, qui décide si le choix est possible (**D15**).
- **pip devient « à jour »-able** : il n'avait pas de commande « tout mettre à
  jour », il a maintenant `install -U <nom>` par paquet.
- **Bouton vers l'interface graphique du gestionnaire**, jumeau de « Ouvrir
  Windows Update » : action `pkg-open-gui` (`kind: manual`, `severity: info`).
  Le bouton n'apparaît QUE si la cible est réellement installée
  (`Get-PkgGui` : protocole enregistré dans `HKEY_CLASSES_ROOT` pour le
  Microsoft Store, exécutable présent pour Chocolatey GUI). Un bouton mort est
  pire que pas de bouton. Sur cette machine : Store présent, Chocolatey GUI
  absent, pip sans interface.
- **Liste verrouillée** quand le gestionnaire ne sait pas cibler un paquet
  (scoop, npm, gem) : la liste s'affiche quand même, cases cochées et **non
  décochables**, et la fenêtre dit pourquoi. Contrat : `result.selection`,
  `result.intro`, `result.vide`, `result.confirmLabel`.
### Modifie
- `Invoke-PkgUpgrade` accepte `-Pkgs` : une commande par paquet retenu, résultat
  agrégé (code de retour, redémarrage 3010/1641, liste des échecs). Sans liste,
  comportement historique inchangé (tout le gestionnaire, une commande).
  `Start-PkgJob` et `pkg-job.worker.ps1` transportent la sélection.
- `api/openapi.yaml` : `result.selection`, `result.confirmLabel`, `result.intro`,
  `result.vide` et `result.updates[]` sont décrits.
### Corrige
- **winget : identifiant faux sur les noms longs.** Le découpage se faisait sur
  « deux espaces ou plus » ; winget dimensionne chaque colonne sur son plus long
  élément, si bien qu'un nom long ne laisse qu'UN espace avant l'Id. Constaté en
  réel : `12.0.40664.0` était pris pour l'identifiant du Redistribuable Visual
  C++ 2013 — la mise à jour aurait visé un paquet inexistant. Le découpage se
  fait désormais aux **positions de colonnes lues dans l'en-tête**.
- **Variable `$pid`** (automatique, en lecture seule) utilisée pour l'identifiant
  de paquet : l'affectation levait une exception avalée par un `catch` vide et la
  liste revenait **vide** en annonçant zéro mise à jour. Renommée `$ident`.
  Même famille de défaut que **D43** : un échec silencieux passe pour un succès.
- Cases **verrouillées** rendues avec `disabled` : le navigateur les grise et on
  ne voyait plus qu'elles étaient cochées — exactement ce qu'il fallait montrer.
  Elles restent actives, l'interaction est coupée par le CSS.
### Verifie
- Parser PowerShell OK sur `common.ps1`, `packages.probe.ps1`,
  `pkg-job.worker.ps1` et les actions `pkg-list-updates`, `pkg-upgrade`,
  `pkg-open-gui`, `pkg-check-updates`.
- `Get-PkgUpdates -Id winget` exécuté en réel : 3 paquets, identifiants exacts
  (`Microsoft.GameInput`, `Microsoft.Teams.Free`, `Microsoft.VCRedist.2013.x86`).
- `pkg-list-updates` exécutée en réel sur `winget` (choix libre), `gem`
  (verrouillé) et `yarn` (refus explicite) ; sonde `packages.probe.ps1` exécutée :
  bouton `dialog` et bouton Store présents, `pkg-open-gui` absent pour Chocolatey.
- Front servi en **http** (**D47**, jamais `file://`) : script exécuté
  intégralement, aucune erreur console, fenêtre de choix testée dans les deux
  modes (libre : rien de coché au départ, bouton désactivé tant que rien n'est
  retenu, compteur juste ; verrouillé : tout coché, indécochable, barre
  « Tout cocher » masquée, libellé du bouton corrigé après chargement).
- `api/openapi.yaml` relu par un analyseur YAML.

## 2026-08-24 (b) — Le verrouillage Windows Update devient natif
### Ajoute
- **Verrouiller, déverrouiller et auditer Windows Update sans aucun script hors dépôt.**
  Une installation faite depuis GitHub disposait de la LECTURE mais pas de
  l'ÉCRITURE : les trois boutons rendaient « outillage externe non configuré » et ne
  faisaient rien. La fonction phare du produit ne pouvait pas rester sous-traitée.
- `Get-UpdateTaskCatalog` (`lib/common.ps1`) : **LE** catalogue du sujet — dossiers de
  tâches, chemins du planificateur, tâches désactivables, services, SID visés et clés de
  stratégie. Ces listes étaient recopiées dans la sonde **et** dans un script extérieur.
- `Get-UpdateLockState` : lecture complète et unique (stratégie, verrou ACL, tâches,
  élévation), reprise telle quelle par la sonde, les actions et l'audit.
- `Invoke-UpdateAudit` : audit **lecture seule** de la machinerie Windows Update
  (édition, stratégies, redémarrage en attente, tâches, services dont WaaSMedic,
  derniers correctifs). Rapport texte **et** JSON écrits dans `var/log/`, conformément à
  la convention du projet — l'ancien script écrivait à la racine d'un autre dépôt.
### Modifie
- `Set-UpdateLock` reste l'**unique porte d'entrée en écriture** (**D15**) mais applique
  désormais le verrou elle-même : stratégie `NoAutoUpdate`, réouverture des dossiers,
  bascule des tâches gérées, puis `takeown` + `icacls` (grant administrateurs, **deny**
  SYSTEM par SID). Chaque geste est **idempotent** : rejouable sans effet ni alarme.
  Un `ToolsPath` contenant `update-mode.ps1` reste **préféré** — jamais requis.
- **Élévation vérifiée AVANT d'agir** : sans droits administrateur, `icacls` et `takeown`
  échouent en silence et Vigie annoncerait un verrou qu'elle n'a pas posé. Les deux
  actions et `Set-UpdateLock` refusent d'emblée, sans rien toucher, avec une phrase qui
  le dit.
- `update-mode-on` / `update-mode-off` : court-circuit **idempotent** (l'état demandé est
  déjà celui de la machine → succès tranquille), puis compte rendu de ce qui a été
  **observé** après coup (**D43**), distinguant verrou complet, MAJ automatiques coupées
  sans verrou ACL, et échec.
- `lock.probe.ps1` consomme `Get-UpdateLockState` au lieu de refaire sa propre lecture.
- `Test-IsElevated` délègue à `Test-Elevated` : le même test existait en double.
- `run-audit` rapporte un résumé (verrou, tâches désactivées/actives) et le chemin du
  rapport, au lieu de « Audit lancé » sans savoir si quoi que ce soit avait été écrit.
- `ToolsPath` documenté comme **facultatif** : `config.psd1`, `config.local.sample.psd1`,
  `doc/fr` et `doc/en` (configuration, windows-update, dépannage, sondes-et-actions).
  Restent tributaires de l'outillage : `toggle-vbs`, `toggle-hvci`, `open-folder`.
### Corrige
- **Clé de stratégie absente** : l'écriture de `NoAutoUpdate` échouait silencieusement
  quand `...\WindowsUpdate\AU` n'existait pas — le cas d'une machine neuve, donc
  exactement celui qu'on prétendait servir. La clé est créée avant écriture.
- **Audit : « the array index evaluated to null »** sur une clé de registre qui existe
  mais se lit `$null` (aucune valeur, ou lecture refusée sans élévation) :
  `$null.PSObject.Properties.Name` rend un élément `$null` qui passait le filtre et
  servait ensuite d'index. Constaté à l'exécution, pas déduit.
- `Get-ScheduledTask` passe en `-ErrorAction Ignore` : un dossier dont l'accès est refusé
  — précisément l'effet du verrou — empilait une erreur dans `$Error` à chaque lecture.
### Verifie
- Parser PowerShell OK sur **tous** les `.ps1` / `.psd1` du dépôt.
- `Get-UpdateLockState` confrontée à un relevé manuel de la machine : même
  `NoAutoUpdate`, même présence du `(DENY)`, mêmes tâches désactivées.
- Audit exécuté en réel : rapport complet écrit (texte + JSON), 0 erreur non terminante.
- Refus d'élévation éprouvé **en conditions réelles** (session agent non élevée) :
  `Set-UpdateLock` et les deux actions refusent, et l'état de la machine est **identique
  avant et après** (`NoAutoUpdate=1`, verrou ACL posé, 6 tâches désactivées).
- Mécanique ACL et **idempotence** éprouvées sur un dossier jetable : pose jouée deux
  fois (mêmes codes de retour, verrou détecté à chaque fois), levée jouée deux fois
  (codes 0, verrou absent à chaque fois).
- Sonde `lock.probe.ps1` exécutée : mêmes champs, mêmes actions qu'avant la bascule.
### A faire
- Le verrou n'a **pas** pu être posé ni levé pour de vrai : la session de l'agent n'est
  pas élevée et la machine de l'utilisateur ne devait pas changer d'état. À éprouver
  depuis un serveur Vigie lancé en administrateur.
- `toggle-vbs`, `toggle-hvci` et `open-folder` appellent **toujours** des scripts hors
  dépôt : le produit ne tient pas encore entièrement debout seul.
  → **Traité le 2026-08-24 (c)**, ci-dessous.

## 2026-08-24 (c) — VBS / intégrité mémoire natives ; plus aucune dépendance externe
### Ajoute
- **Basculer VBS et l'intégrité mémoire sans aucun script hors dépôt.** Les deux derniers
  boutons qui déléguaient (`toggle-vbs.ps1`, `toggle-memory-integrity.ps1`) écrivent
  désormais eux-mêmes dans `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard`.
  **Plus aucune fonction de Vigie ne dépend de `ToolsPath`.**
- `Get-DeviceGuardCatalog` : LE catalogue du sujet (clés, noms de valeurs, libellés).
- `Get-DeviceGuardState` : lecture unique, partagée par la sonde et les bascules. Elle
  distingue quatre choses qu'on ne peut pas confondre — `configured` (ce que demande le
  registre), `running` (ce que Windows exécute), `requested` (ce que Vigie a demandé et
  qui attend un redémarrage) et `effective` (ce que la carte affiche).
- `Set-DeviceGuardFeature` : **unique porte d'entrée en écriture** (**D15**). Sauvegarde
  `.reg` de la clé dans `var/log` avant d'écrire, refuse sans élévation, écrit, puis
  **relit le registre**.
- `Invoke-DeviceGuardToggle` : décision + compte rendu, partagé — les deux actions ne
  diffèrent que par le nom de la fonction visée et tiennent en une ligne chacune.
- `Test-RestartCountdown` : « un redémarrage différé court-il encore ? ». Ce calcul vivait
  dans `lock.probe.ps1` et allait être recopié dans `vbs.probe.ps1` (**D15**).
- **Carte de la virtualisation : ligne « En attente de redémarrage »** quand une bascule
  est écrite mais pas appliquée, et bouton **Redémarrer Windows** — l'action
  `system-restart` existante (double confirmation, différée 60 s, annulable), pas une
  copie. Un redémarrage déjà programmé fait apparaître *Annuler le redémarrage* à la place.
### Modifie
- **Une bascule ne prend effet qu'au REDÉMARRAGE** : le succès se juge donc sur la valeur
  **écrite dans le registre**, jamais sur l'état actif — qui ne bougera pas avant le
  redémarrage et ferait un faux échec garanti à chaque clic. Le message le dit :
  « sera désactivée au prochain redémarrage », pas « désactivée ».
- **La bascule s'appuie sur ce que la carte affiche** (`effective`), pas sur ce qui tourne.
  Recliquer avant d'avoir redémarré **annule la demande** au lieu de réécrire la même
  valeur — une bascule qui ne bascule pas serait un piège.
- **Désactiver VBS coupe aussi l'intégrité mémoire**, qui ne peut pas fonctionner sans
  elle : la laisser demandée produit une configuration incohérente que Windows résout
  parfois en rallumant VBS. Le message l'annonce. L'inverse n'est **pas** fait : activer
  VBS n'active pas l'intégrité mémoire dans le dos de l'utilisateur.
- **`open-folder` n'est plus un bouton mort** : `history.probe.ps1` ne propose l'action que
  si le dossier d'administration est configuré **et** existe. Le libellé d'aide affiche le
  chemin réel. Dépendre d'un chemin configuré est légitime pour « ouvrir un dossier » ;
  proposer un bouton qui ne peut rien faire ne l'est pas.
- `lock.probe.ps1` consomme `Test-RestartCountdown` au lieu de sa copie locale.
- `New-ToolsMissingResult` : message en français **accentué** (il ne concerne plus qu'une
  seule action), et il tutoyait l'utilisateur.
- Documentation alignée : `doc/fr` et `doc/en` (configuration, fonctionnalités,
  dépannage), `doc/en/agent-working/briefing.md`, note de mise à jour sous **D18**.
### Verifie
- Parser PowerShell OK sur **tous** les `.ps1` / `.psd1` du dépôt ; les **12 sondes**
  s'exécutent sans erreur.
- `Get-DeviceGuardState` confrontée à un relevé manuel du registre et de
  `Win32_DeviceGuard` : mêmes valeurs (`configured=0`, `running=True`, `vbsStatus=2`).
- Refus d'élévation éprouvé **en conditions réelles** (session non élevée) sur les deux
  actions **et** sur `Set-DeviceGuardFeature` : registre **inchangé**, aucun marqueur écrit.
- Rendu de l'attente de redémarrage éprouvé en amorçant le marqueur de Vigie (fichier
  d'état, aucun réglage Windows touché) : la ligne apparaît, `system-restart` apparaît avec
  sa double confirmation, et un nouveau clic viserait bien l'annulation de la demande.
- Cas du redémarrage déjà programmé : *Annuler le redémarrage* remplace *Redémarrer* ;
  compte à rebours expiré correctement ignoré.
- **L'écart préexistant de cette machine** (registre VBS=0 mais VBS en cours, valeur
  imposée) ne déclenche **pas** le bouton de redémarrage — c'était le piège à éviter.
- `open-folder` : bouton absent sans chemin configuré, présent et pointant le bon dossier
  avec un `ToolsPath` valide (éprouvé via un `config.local.psd1` temporaire, puis retiré).
### Corrige (hors sujet, constaté au passage)
- **La carte Réseau avait disparu du tableau de bord.** `net.probe.ps1` levait
  *« parameter 'FixAction' is specified more than once »* et ne rendait donc aucun module.
  Le champ *Latence* portait **deux** `-FixAction` : la forme conditionnelle ajoutée lors
  de la refonte (identique à celles de *Débit descendant* et *Débit montant*) et, en fin de
  ligne, l'ancienne inconditionnelle restée là. Le reliquat est retiré ; les trois champs
  ont désormais la même forme. Défaut **préexistant sur `main`**, pas introduit par cette
  fusion (vérifié : le fichier était identique à `origin/main` avant correction).
### A faire
- Aucune bascule réelle n'a été appliquée : la session de l'agent n'est pas élevée et la
  machine de l'utilisateur ne devait pas changer d'état. À éprouver depuis un serveur Vigie
  lancé en administrateur — écriture effective des deux clés, sauvegarde `.reg`, puis
  comportement après un vrai redémarrage.

## 2026-09-11 — **v1.1.0**, première publication depuis la v1.0.0

*Ce journal n'avait plus été tenu depuis le 24/08 : les entrées ci-dessus s'arrêtent avant
la v1.0.0 elle-même. Cette section couvre donc les 44 commits qui séparent les deux
versions, du point de vue de qui utilise Vigie.*

### Notifications de bureau
- Elles portent **le nom et l'icône de Vigie**. Elles s'annonçaient « PowerShell ».
- Le **titre nomme ce qui a changé** et le corps donne la mesure — « 2 détectée(s) » plutôt
  qu'un « Un module a changé d'état » identique pour tous les sujets.
- Un **rétablissement remplace son alerte** au lieu de s'ajouter à côté.
- Un même champ **ne sonne pas deux fois en dix minutes** : dix bascules en quarante minutes
  décrivaient une seule situation.
- **Rien ne sonne quand personne ne regarde l'écran** : revenir d'une autre session ne
  déverse plus une pile de bulles.
- Derrière, plusieurs outils d'affichage rangés par préférence, le dernier toujours
  disponible : une notification n'est jamais perdue faute d'outil.

### Mises à jour Windows
- La liste des mises à jour en attente est **groupée par constructeur**, en repliant les
  orthographes d'un même fabricant — Intel s'écrivait de trois façons.
- Chaque ligne de pilote porte le **nom du modèle** plutôt que le titre de Windows, qui
  porte parfois la version à sa place.
- Deux **versions du même pilote** : seule la plus récente est proposée, et l'ancienne
  revient si la récente échoue à s'installer.
- Le compteur de la carte et la fenêtre d'installation **disent le même nombre**, et
  l'écart avec ce que Windows détecte est expliqué.
- Vigie ne se substitue jamais à Windows Update : la sélection va à son installateur.

### Jeux
- Ce qui **appartient au jeu ou à sa plateforme** n'est plus signalé comme une application
  gourmande étrangère.
- Les applications gourmandes sont **nommées**, plus seulement comptées.

### Installation et désinstallation
- **On choisit où Vigie s'installe.**
- La **désinstallation** est écrite : ce qu'elle retire, dans quel ordre, ce qu'elle laisse.
  Interrompue, elle se reprend en la relançant. Elle n'emporte jamais de quoi réinstaller.
- **Une tâche de démarrage par compte**, sous un seul schéma de nom, réparée toute seule.

### Retiré
- L'affichage d'un **historique dans les cartes**, que personne n'avait demandé.

### A faire
- Les essais d'**installation et de désinstallation réelles** se font à partir de cette
  publication : rien n'a encore été installé depuis une archive publiée.

## 2026-09-13 — **v1.1.1**, les opérations asynchrones suivent un seul protocole

*Étiquette posée par le déploiement, non publiée sur GitHub.*

### Corrigé
- **Une installation Windows Update s'annonçait terminée dès son départ**, puis figeait sa carte sur « Démarrage… »
  (12/09). Quatre opérations lançaient leur worker hors du protocole de D82. `Start-Operation` est désormais le seul
  lancement : la marque d'occupation existe avant la réponse de l'action, tout arrêt écrit un résultat, et un processus
  disparu sans résultat s'affiche en échec. Windows Update, l'analyse du disque et les paquets passent par lui.
- Le correcteur d'accents ne touche plus un segment de chemin, et réécrit `lang/fr.json` en LF.

### Ajouté
- **L'inventaire de toutes les opérations**, `doc/progress/implemented/operations.md`, tenu par
  `scripts/dev/check-operations.ps1` dans les deux sens.
- Dans la documentation : les critères d'une décision, la règle « une règle à un seul endroit », l'ordre de travail
  (preuve, plan cible, développement, plan cible), et la discipline « une opération importante attend un oui ».

## 2026-09-13 — **v1.1.2**, le clone du service ne se bloque jamais

*Étiquette posée par le déploiement, non publiée sur GitHub.*

### Corrigé
- **Le déploiement s'arrêtait** en annonçant un dépôt injoignable : le clone du service refusait les étiquettes
  déplacées par la réécriture d'historique du 11/09. `Update-ServiceClone` récupère avec `--force`, puis reclone à
  côté de l'ancien si git refuse encore alors que la source répond ; une source muette laisse le clone intact et
  affiche le texte de git. **Éprouvé en production le 13/09 à 11 h 57.**
- Le correcteur de libellés garde l'ordre du fichier.

### Ajouté
- Deux actions d'administration, par le serveur : `service-clone-repair` et `service-clone-reset`.
- **L'inventaire des pièces**, `doc/progress/implemented/components.md` : chaque pièce que Vigie pose répond à chaque
  situation de sa vie (création, mise à jour, état cassé, croissance, maintenance, désinstallation).

## 2026-09-13 — **v1.1.3**, la fenêtre d'annonce a une cible

*Étiquette posée par le déploiement, non publiée sur GitHub.*

### Corrigé
- Un exemple de la documentation se lisait comme un lien, et la fabrication de l'archive le signalait.

### Modifié
- Cible de la fenêtre affichée avant l'élévation : un seul écran, un mode détecté (installation ou mise à jour), des
  gestes tirés du plan réel.

## 2026-09-13 — **v1.1.4**, la fenêtre d'annonce montre le plan, et les pièces sans réponse en ont une

*Étiquette posée par le déploiement le 13/09 à 13 h 45, non publiée sur GitHub.*

### Modifié
- **La fenêtre d'annonce** est calculée par `scripts/lib/install-plan.ps1`, sous Windows PowerShell 5.1 : version en
  place et version qui arrive, compte de service, tâches, prérequis manquants. Une installation choisit d'abord son
  dossier ; une mise à jour n'en propose pas. **Pas encore affichée pour de vrai.**
- **114 textes reformulés** : ni « tu » ni « vous » quand une tournure neutre existe.
- Toute opération se présente de la même manière à l'écran : lancée, en cours, terminée.

### Corrigé
- `setup.cmd` garde sa console ouverte quand l'installation échoue avant sa fenêtre de fin, et le dossier choisi
  traverse la bascule vers PowerShell 7.
- `Repair-VigieTasks` ne prend plus la tâche `Vigie - Serveur` pour celle d'un compte « Serveur ».

### Ajouté
- **Les journaux sont purgés après 30 jours**, au démarrage des deux apps puis chaque jour.
- `service-account-repair` : nouveau mot de passe du compte de service, droit d'ouverture de session, tâche serveur
  réenregistrée. **Jamais exécuté.**
- La désinstallation retire aussi le droit « ouvrir une session en tant que tâche » et la source d'événements `Vigie` ;
  un déploiement retire la confiance git de la source qu'il quitte. **Non éprouvé.**
- La carte Déploiement signale une source déclarée disparue.
- `scripts/dev/check-components.ps1` refuse une écriture sur l'ordinateur que l'inventaire des pièces ne nomme pas.

## 2026-09-13 — après la v1.1.4, non publié

### Modifié
- Les opérations se nomment **synchrones** (résultat dans la réponse) et **asynchrones** (le travail continue après),
  plus « courtes » et « longues ».

### Corrigé
- **La carte Déploiement disait « Jamais démarrée » d'une app cliente en marche.** Une mise à jour redémarrait une
  tâche qui tournait déjà ; Windows refusait, et ce refus était lu comme un échec. Une tâche en cours au processus
  vivant n'est plus redémarrée ni signalée, et un dernier démarrage en échec ne se dit plus « Jamais démarrée ».
  **Constaté sur la carte après la mise à jour de 22 h 39.** Le redémarrage refusé, lui, a encore eu lieu : la tâche
  venait d'être réenregistrée et ne se lisait plus « en cours ». C'est désormais le processus vivant qui décide ;
  **ce second correctif n'est pas encore déployé.**
- **Une installation Windows Update rendait « Inconnu »** pour une mise à jour que Windows savait en échec, et
  **taisait une mise à jour demandée** qu'elle ne retrouvait plus (12/09 : quatre demandées, trois dans le compte
  rendu). Le verdict manquant est relu dans l'historique de Windows Update, chaque code a un nom, et une mise à jour
  introuvable compte comme un échec. **Non éprouvé sur une vraie installation.**
- **`setup.cmd` se fermait sans rien dire quand l'élévation n'avait pas lieu.** Il le dit maintenant et attend. La
  cause de l'installation silencieuse du 13/09 à 11 h 11 reste **non expliquée**.
- Une installation élevée retire la confiance git d'un dossier qui n'existe plus, la paire seulement.
- Une copie valide de l'installation retire aussi les sauvegardes laissées par des copies en échec, qui s'accumulaient.
- Une installation depuis un dépôt ne garde que la confiance git de la source déclarée.
- Un secret de compte dont les droits accordent un accès à un tiers est révoqué, réémis et l'incident journalisé. Le
  jeton de l'API locale suit la même règle ; ses droits seulement hérités se referment sans le changer.
- La carte Déploiement signale un profil du compte de service temporaire ou corrompu.
- Action d'administration `service-data-reset` : vide le cache ou l'historique du service. **Non exécutée.**
- **Savoir qui écoute sur un port prenait 26 secondes**, parce que l'appel WMI énumérait les 10 775 connexions de
  l'ordinateur, dont 10 426 tenues par l'hôte réseau de WSL : la mise à jour du 14/09 a duré 225 s au lieu de 98.
  L'appel natif qui ne demande que les ports en écoute répond en quelques millisecondes, et le service d'un processus
  se retrouve de la même façon ; `check-probes` refuse les appels lents.
- **La carte Ressources dit pourquoi elle alerte** : les applications qui occupent le plus la mémoire ou le processeur,
  regroupées par nom, et la mémoire engagée face à sa limite, celle qui déclenche les alertes de saturation de Windows.
  Ses mesures sont lues directement auprès de Windows : 0,45 s au lieu de 2,9 s.
- **Le résident des jeux ne peut plus se multiplier** : le 17/09, 115 copies occupaient 19 Go et ont épuisé la mémoire
  et les ports réseau de l'ordinateur. Un résident n'est plus relancé que si son processus a disparu, jamais parce
  qu'il bat en retard ; un résident lent ou doublé est signalé sur la carte Vigie avec ses raisons, et Vigie n'arrête
  plus aucun processus d'elle-même.
- **La carte Windows Update suit une installation en cours**, dans un bloc qui n'existe que pendant l'installation :
  en tête la mise à jour en cours, ce qu'elle fait, son avancement et ses octets, et en clair si elle ne progresse plus
  depuis deux minutes ou échoue ; dessous chaque mise à jour avec son état, les réussies repliées derrière un bouton ;
  en bas l'avancement total.
- **Une carte « Journal Windows » dit les erreurs que Windows consigne** : sur les dernières 24 heures, ports réseau
  épuisés, mémoire du Bureau épuisée, mémoire virtuelle épuisée, écran bleu, erreur matérielle, erreur de disque, arrêt
  inattendu, pilote graphique en erreur et service arrêté brutalement sont nommés avec leur sens et leur geste, et une
  notification les annonce ; les autres erreurs sont listées par source. Le 17/09, ports et mémoire du Bureau épuisés
  étaient consignés sans qu'aucune carte ne le dise.
- **La carte Réseau compte les ports réseau temporaires** face à la limite de Windows, en TCP et en UDP, avec les
  processus qui en tiennent le plus ; une notification prévient à 80 %. À la limite, plus aucune application ne peut
  ouvrir de connexion : c'est arrivé 85 fois du 06/07 au 17/09.
- **Vigie se surveille elle-même** : une carte « Processus de Vigie », dans le module Débogage, compte l'app serveur et
  tout ce qu'elle a lancé, avec le rôle et la mémoire de chacun, et signale un résident qui tourne hors de l'app
  serveur ; au-delà de seuils réglables, elle alerte et une notification le dit. Le bouton de relance du serveur porte
  désormais son nom, « Redémarrer le serveur », au lieu de « Résoudre ».
- **L'app cliente dit pourquoi le serveur ne répond pas** : ses bulles « Serveur bloqué » et « Serveur arrêté » ajoutent
  ce qu'elle mesure seule, mémoire engagée proche de sa limite, ports réseau presque épuisés, manque de ports ou de
  mémoire consigné par Windows dans la demi-heure, Vigie emballée.
- **La carte WSL montre la mémoire de sa machine virtuelle** et la borne réglée dans `.wslconfig` ; au-delà d'un seuil
  réglable, elle dit comment la borner soi-même : le fichier, la ligne `memory=` à écrire, et l'arrêt de WSL qui
  l'applique.
- **La carte Jeu se calcule en 1,8 s au lieu de 8,7 s** : ses compteurs GPU sont lus directement auprès de Windows
  (`Get-Counter` prenait 6 s pour les seuls moteurs), et les lectures d'E/S par processus, du parent d'un processus et
  de l'heure de démarrage passent par des appels directs, mesurés à l'identique
  (`notes/evidence/2026-09-18-system-calls-measured.md`). `check-probes` refuse désormais `Get-Counter`.
- **Une carte garde son résultat aussi longtemps qu'elle coûte cher** : chaque requête de l'interface confie une carte
  périmée à une tâche de fond, et des caches de 5 s rendaient tout périmé en permanence. Le 28/09, la carte des paquets
  a été recalculée 305 fois pour 1 128 s de calcul, le réseau 171 fois pour 713 s. Paquets : 5 s → 5 min ; réseau et
  alimentation : 15 s → 1 min ; stockage : 5 s → 1 min, sauf pendant une analyse d'espace, où il reste à 5 s pour
  montrer sa progression. Les actions invalident leurs cartes, le bouton « Actualiser » force, et les sentinelles
  recalculent la leur dès que leur valeur bouge : rien n'attend.
- **La carte Stockage prévient avant que le disque soit plein** : « 43 Go de moins depuis le 21/09 — plein dans
  6 jours à ce rythme », dit seulement quand la baisse est franche, et jamais présenté comme une prophétie.
- **Un bouton envoie une vraie notification d'essai** (module Débogage) et dit quel outil l'a affichée. Les alertes
  ajoutées en septembre — mémoire engagée, ports réseau, erreurs système, emballement de Vigie — n'avaient jamais été
  vues à l'écran : un mécanisme que personne n'a vu fonctionner est une promesse, pas une fonction.
- **Deux valeurs de la carte Stockage débordaient sur deux lignes** : « 42 Go de moins depuis le 21/09 — plein dans
  5 jours à ce rythme » et « Sous-système Linux WSL (Ubuntu 24.04 LTS) : 150,7 Go ». La règle du projet veut une
  valeur qui répond, courte : « Plein dans 5 jours » et « WSL 150,7 Go ». La phrase entière et le nom complet vivent
  désormais dans le détail et le tableau.
- **Le panneau ne s'ouvrait plus** : un renommage avait laissé « async async function » dans la page, et une seule
  faute de syntaxe tue tout son script — Vigie restait sur son écran de chargement. Corrigé, et surtout : un
  vérificateur, `check-front`, analyse désormais le script de la page à chaque passe (`node` de WSL quand Windows n'en
  a pas), parce qu'aucun des onze autres ne lisait le JavaScript.
- **Une mise à jour ne laisse plus un compte sans app cliente** : Windows garde l'état « en cours » d'une tâche dont
  le processus est mort, et refuse alors de la démarrer (0x800710E0). Le 28/09, le compte qui avait demandé la mise à
  jour s'est retrouvé sans icône. La tâche fantôme est désormais terminée avant d'être relancée.
- **Une notification cliquée ouvre enfin Vigie** : ni la bulle du démarrage, ni les notifications Windows n'avaient
  de gestionnaire de clic — cliquer ne pouvait que les faire disparaître. La bulle ouvre le panneau, et les
  notifications portent une cible que Windows sait atteindre, le protocole `vigie://`, déclaré par l'app cliente pour
  son compte.
- **Le récapitulatif s'ouvre tout seul à la fin d'une partie** (réglage actif par défaut, module Jeux). La fenêtre se
  ferme d'elle-même quand une nouvelle partie commence, ou après dix minutes sans avoir été une seule fois au premier
  plan — regardée, elle reste. Réglage éteint, une notification « Partie terminée / Voir le récap » propose de
  l'ouvrir, et elle obéit aux réglages de notification comme les autres.
- **Le récapitulatif d'une partie s'ouvre dans une fenêtre**, jamais sur la carte : les bouchons d'abord, puis le jeu,
  puis ce que chaque application a pris. La même fenêtre par toutes les portes — le bouton de la carte, la liste des
  parties précédentes, et bientôt la fin d'une partie. La carte ne garde qu'une ligne : « ACOdyssey, 1 h 35, terminée
  à 11:50 — Processeur saturé 14 min ».
- **La carte Stockage nomme les disques virtuels** : « Sous-système Linux WSL (Ubuntu 24.04 LTS) : 150,7 Go » au lieu
  de « 150,7 Go pour 1 disque(s) », et le tableau dit à quel compte appartient chacun.
- **Une partie garde ses bouchons, pas seulement ses gourmands** : un relevé compte comme bouchon quand la machine est
  au plafond **et** qu'une application étrangère au jeu prend une part à elle seule — 85 % de processeur avec un gêneur
  à 10 %, 95 % de carte graphique avec un gêneur à 5 %, ou 90 % de mémoire engagée, où la machine bride seule. Un jeu
  seul à 96 % n'est pas gêné, et dix poussières à 1 % ne font pas un bouchon. Il faut deux relevés consécutifs, soit
  une minute, pour qu'un pic isolé ne devienne pas un verdict.
- **Le bilan de la dernière partie** : la carte Jeu relève, toutes les trente secondes, ce que chaque application
  prend pendant une partie, et en garde le résumé. Elle lit ensuite, par exemple : « ACOdyssey, 1 h 35 — surtout
  Assassin's Creed Odyssey, 41,8 % de processeur en moyenne », avec le détail par application : présence, moyennes et
  pointe. Le relevé est une addition, jamais un journal qui grossit.
- **L'alerte des applications gourmandes ne se déclenchait pour rien** : son seuil était de 1 % de processeur, tous
  cœurs confondus — un sixième d'un cœur sur cet ordinateur —, mesuré sur neuf dixièmes de seconde. Le Gestionnaire de
  fenêtres le franchissait en dessinant le jeu, et l'alerte est sortie quatorze fois le 16/09 pour rien. Le seuil passe
  à 8 %, l'application doit avoir tenu trois minutes dans la partie, et les composants de Windows restent au tableau
  sans jamais déclencher l'alerte : ils travaillent pour le jeu.
- **Chaque carte tenue en retrait le dit elle-même**, dans son en-tête (« en retrait · 20 min »), et seulement celles
  qui le sont vraiment — pas la carte Jeu, qui, elle, garde sa cadence. Sans cette mention, une mesure vieille de vingt
  minutes se lisait comme une mesure de l'instant. Le contrat porte la cadence de la carte (`Module.pace`).
- **Les cadences en jeu sont bornées pour ne pas remplacer un excès par un autre** : Jeu 30 s, Ressources 20 s,
  Processus de Vigie 2 min, Vigie 5 min ; hors partie, Jeu passe de 10 à 30 s et Ressources de 8 à 15 s. Processeur,
  mémoire vive et mémoire engagée sont notés toutes les 5 minutes au repos, toutes les minutes pendant une partie.
- **La carte Jeu coûte 2,4 s au lieu de 5,5 s** : le fichier des verdicts « est-ce un jeu ? » était relu et réanalysé
  pour chaque processus, 45 ms à chaque fois ; il est lu une fois par passe, et le verdict revient en 3,4 ms.
- **La carte Stockage dit où va la place, sans analyse manuelle** : l'évolution de l'espace libre sur sept jours, avec
  la variation de chaque jour, et les disques virtuels (WSL, Docker, Hyper-V, VirtualBox) qui grossissent et ne rendent
  jamais rien — 150,7 Go pour le disque de WSL le 28/09, quand le disque n'avait plus que 28 Go libres. Leur recherche
  est bornée aux emplacements connus et gardée une demi-heure : 0,08 s par recalcul au lieu de 3,1 s.
- L'historique des sentinelles s'affiche en heure locale, et non plus en UTC : deux heures d'écart qui ont d'abord fait
  croire qu'aucune mesure n'avait été prise pendant une partie.
- **Vigie se met en retrait pendant une partie** : mesuré le 28/09 sur une session de 77 minutes, elle recalculait
  ses cartes 383 fois, 1 582 secondes de calcul, soit 34 % d'un cœur en continu — dont 400 s pour la seule carte des
  paquets. Pendant une partie, les cartes de la partie gardent leur cadence, les autres passent à un quart d'heure au
  moins et les lourdes à une heure ; le bouton « Actualiser » passe toujours avant ce retrait.
- **Ce que faisait l'ordinateur pendant une partie est enregistré** : processeur, mémoire vive et mémoire engagée
  suivent désormais la carte Ressources, et chaque point porte le nom du jeu en cours. Le compte des applications
  gourmandes était faux depuis le 06/09 — l'extracteur cherchait un nombre là où la carte donne des noms, et
  l'historique affichait zéro pendant toute une partie ; il compte juste et garde les noms.
- **Le repli s'anime, et devient un composant standard** : trois classes — `acc`, `acc-h`, `acc-b` — suffisent pour un
  accordéon animé, sans une ligne de code, et l'atelier du design le montre. Le CSS seul ne tenait pas : sous
  Chrome 152, `::details-content` avec `interpolate-size` laissait le contenu affiché une fois replié (mesuré le
  20/09). Le réglage « animations réduites » de Windows rend le pli instantané.
- **Dans la liste des mises à jour, le nom d'un groupe coche le groupe** au lieu de le replier. Tout le reste de la
  ligne — la flèche, l'espace après le nom, le compte — replie et déplie. L'en-tête se comporte enfin comme les lignes
  en dessous, où cliquer le texte coche la case. Le nom ne prend aucune apparence de bouton au survol.
- **La carte Windows Update rapporte ses problèmes** au lieu d'afficher un seul nombre : une mise à jour réinstallée en
  boucle (14 fois en sept jours pour un paquet du Store), une installation en échec ou annulée avec son code, les mises
  à jour que Windows ne servait plus au moment d'installer — 14 sur 15 le 18/09, et la carte disait « réussie » —, un
  cache local qui contredit la dernière analyse en ligne, et les erreurs que Windows consigne lui-même. Le nombre
  affiché est désormais consigné à chaque changement : celui de 46 à 48 mises à jour vu quelques jours avant le 20/09
  n'avait laissé aucune trace vérifiable.
- **Un résident doublé le dit avant de partir** : quand son état désigne un autre processus, il consigne les deux
  numéros dans le journal du serveur et dans son état, et la carte Vigie l'affiche pendant 24 heures. Il partait en
  silence. L'heure du dernier événement d'un résident est donnée en heure locale, et non plus en UTC.
- **La détection des jeux ne se tait plus pendant une rafale de processus** : le résident ne battait qu'après avoir jugé
  tous les démarrages en file, et réécrivait son état à chacun. Le 18/09 il n'a plus battu de 16:28 à 17:46, vingt
  minutes après un redémarrage de Windows : aucune partie ne pouvait être détectée, et Vigie semblait absente. Il bat
  désormais pendant la file, écrit son état une fois par lot, ne suit plus les arrêts de processus, qui ne servaient à
  rien, et consigne toute file longue.
- **Une mise à jour demande aux app clientes de partir d'elles-mêmes** avant d'arrêter leurs tâches : elles le
  consignent dans leur journal, et seules celles qui ne répondent pas sont arrêtées de force. Le 18/09, celles de
  Famille ont disparu sept fois sans une ligne pour dire pourquoi.
- Le journal d'une mise à jour lancée par l'app serveur n'annonce plus « de v1.1.6+23 vers v1.1.6+23 » : la version
  visée n'est connue qu'une fois fabriquée depuis le dépôt, et elle est dite après la copie.
- La colonne « RAM » de la carte Jeu compte la mémoire vive propre à chaque application : elle additionnait les pages
  partagées une fois par processus, 7,9 Go pour Chrome quand il en tenait 2,2.
- **Un résident n'est plus pris pour un autre processus** : son état ne garde qu'un numéro de processus, que Windows
  réattribue, et qui survit à un redémarrage. Un programme quelconque héritant de ce numéro passait pour le résident,
  qui n'était alors plus jamais relancé. Le processus doit désormais être un PowerShell démarré après l'armement.
- La carte WSL distingue WSL absent, machine virtuelle arrêtée et mémoire illisible ; la carte Journal Windows ne
  signale en erreur une erreur matérielle que si Windows l'a consignée comme erreur, pas une erreur corrigée.
- **Les cartes disent ce qui est réellement en mémoire vive** : Ressources, WSL et Processus de Vigie montraient sous le
  mot « mémoire » la mémoire engagée (`PrivateMemorySize64`), 14,4 Go pour WSL quand 12,4 Go étaient en mémoire vive.
  Elles montrent désormais, côte à côte, la mémoire vive occupée (l'ensemble de travail privé du Gestionnaire des
  tâches) et la mémoire engagée ; chaque alerte trie et nomme selon ce qui la déclenche.
- **La carte Ressources sépare la mémoire vive du fichier d'échange** : la mémoire vive utilisée face à celle installée,
  le fichier d'échange utilisé face à sa taille, et la mémoire engagée dit de quoi sa limite est faite. Un ordinateur de
  32 Go lisait « 49 Go » sans savoir quelle part était sur le disque. La carte WSL cite aussi `autoMemoryReclaim`.
- **La notification de saturation mémoire nomme ses raisons** : une notification `commit-high` suit la mémoire engagée,
  celle qui déclenche les alertes de Windows, et la bulle de `ram-high` comme la sienne nomme les trois applications qui
  occupent le plus la mémoire. Un champ en alerte porte désormais sa raison (`reason`), que l'app cliente reprend.
- Une version de développement s'écrit d'une seule façon, `v1.1.6+1` : l'installation l'écrivait `v1.1.6-dev1`, et
  l'état du déploiement annonçait un dépôt en avance sur une installation au même commit.
- **Un déploiement ne pose plus d'étiquette de version** (D123) : il affiche le dernier numéro suivi de ses commits,
  par exemple `v1.1.5+3`. Une étiquette se pose pour une version stable validée, à sa publication.
- **Le récapitulatif de fin de partie ne pouvait pas s'ouvrir.** Son bloc avait été écrit dans la branche du PREMIER
  passage de la boucle de l'app cliente : là, sa condition — un récapitulatif déjà vu, différent de celui du moment —
  ne peut jamais être vraie, et l'on ne repasse jamais par cette branche. Livré le 28/09, relu deux fois, il n'a pas pu
  tourner une seule fois, et la fermeture automatique non plus. Les deux vivent désormais dans la boucle.
- **Les noms écrits en français pendant le lot du 28/09 sont en anglais** (D41) : trente et un identifiants, de
  `$state.RecapVu` à `$nomsDuJeu`, dans l'app cliente, les sondes Jeu et Stockage, la bibliothèque commune et les
  outils de débogage. Relevé par le propriétaire, pas par un vérificateur.

### Ajouté
- `scripts/dev/check-all.ps1` lance tous les vérificateurs du dépôt en une commande.
- `scripts/dev/check-language.ps1` vérifie que chaque document est écrit dans la langue de son dossier.
- Les sept documents de `doc/en/developing/` encore écrits en français sont traduits en anglais : conventions, débogage,
  design, glossaire, modules, revue de sécurité, technologies.
- `notes/answers.md` garde chaque réponse de l'utilisateur, et `scripts/dev/answers.ps1` la cherche avant toute question.
- **Le panneau ne découvre plus un calcul une minute plus tard** : `/health`, qu'il interroge déjà toutes les 15 s, porte l'empreinte du cache d'état ; quand elle change, le panneau relit le cache. Aucune route nouvelle, aucun recalcul provoqué par une lecture.
- **Et elle dit le prix du geste qui les rendrait** : tant qu'une distribution tourne — elles sont toutes nommées, plusieurs peuvent tourner —, la carte avertit que rendre la place exige de l'arrêter, sessions, serveurs et conteneurs en cours compris. Le disque virtuel de ce poste n'est pas en mode fragmenté : aucun geste ne rend ces 107 Go sans cet arrêt, et c'est dit plutôt que suggéré à la légère.
- **Une carte d'un groupe décoché ne revient plus à l'écran** : rafraîchie seule, elle était remplacée par un nœud neuf qui n'avait pas le masquage du filtre — et depuis que le serveur calcule en fond, les cartes se rafraîchissent tout le temps. Constaté le 30/09 sur le groupe Comptes.
- **La carte Jeu nomme ce qui gêne, pendant la partie** : un champ « Ce qui gêne la partie » dit la machine au plafond et qui y prend sa part — `Processeur saturé · Steam 12,9 %` — au lieu d'attendre le récapitulatif. L'alerte des applis gourmandes répondait à une autre question : elle regarde toute la partie et exige trois minutes de présence ; un bouchon, c'est maintenant.
- **Et Vigie prévient quand un bouchon dure** : au-delà de `JamNotifyMinutes` (5 min, réglable), le champ passe à l'orange et la notification `game-jam` part — soumise aux réglages de notification, comme les autres.
- **Steam n'est plus pris pour un jeu** : ses propres composants — `steamwebhelper` et les autres — sont lancés par `steam.exe`, donc la filiation ne prouvait rien. Ce qui les sépare d'un jeu, c'est où ils vivent : un jeu installé par une boutique est dans une bibliothèque (`steamapps\common\…`), ses composants sont dans le dossier de la boutique. Conséquence directe, signalée le 29/09 : la partie ne se terminait jamais — Odyssey fermé, Steam prenait la suite — donc **le récapitulatif ne s'ouvrait pas tout seul**.
- **La pointe processeur d'un jeu ne dépasse plus 100 %** : la fenêtre de mesure démarrait après le premier instantané, si bien que le temps processeur était compté sur le parcours des six cents processus en plus de l'attente, mais divisé par la seule attente. Une pointe de **121,7 %** a été relevée sur une vraie partie ; 100 % veut dire « tous les cœurs », et c'est désormais le plafond.
- **Le récapitulatif de partie s'affiche dans une popin large** (880 px) : six colonnes dans 520 px repliaient chaque ligne en deux.
- **Tous les calculs passent en tâche de fond** (**D124**) : chacune des 19 sondes déclare son calcul et son intervalle à l'ordonnanceur, et **aucune requête ne calcule plus rien** — le panneau sert le cache, le bouton « Rafraîchir » marque la carte due et l'ordonnanceur la prend dans les trente secondes. Une sentinelle qui change demande elle aussi, au lieu de bloquer la boucle de veille pendant treize secondes. Coût mesuré du régime permanent, hors partie : **7,9 % d'un cœur**, contre les 34 % constatés le 28/09 quand c'était l'affichage qui menait les calculs.
- **La liste des paquets ne se fait qu'une fois par jour, et au calme** : `OnlyWhen = 'calm'`, un mode déclaré par le module Système qui lit 250 ms de charge processeur et refuse pendant une partie. Elle coûte 3,7 s à chaque passage — winget, choco et pip interrogés l'un après l'autre.
- **Les journaux de Vigie sont bornés par la taille**, et plus seulement par l'âge : trente jours pesaient **166 Mo** chez le compte de service — 703 fichiers, plusieurs de 4 Mo par jour — sur une machine descendue à 31 Go libres. Un âge ne borne rien : une journée chargée écrit dix fois ce qu'écrit une journée calme. Au-delà de `LogMaxMb` (60 Mo par compte), les plus anciens partent, sauf ce qui a été écrit dans la dernière heure — le journal qu'on lit quand quelque chose vient d'échouer n'est jamais celui qu'on sacrifie.
- **Les copies de diagnostic ne s'accumulent plus** : chaque rapatriement des journaux d'un compte pesait 163 Mo, et vingt d'entre elles occupaient **1,1 Go** dans un profil — sur la machine dont Vigie surveille justement le disque. Les trois dernières d'un compte sont gardées, les autres supprimées au passage suivant.
- La ligne de lancement d'une app cliente était écrite **en trois endroits** — l'installateur, la réparation de l'ancienne tâche, l'activation d'un compte : en corriger un laissait les deux autres. Elle vit maintenant dans `New-VigieTrayAction`, et une tâche encore lancée à l'ancienne est un **défaut structurel** que la réparation réécrit d'elle-même, au démarrage du serveur.
- **Plus de terminal vide à l'ouverture de session, ni de fenêtre qui vole le focus pendant un déploiement** : « -WindowStyle Hidden » cache une fenêtre que Windows a DÉJÀ créée — invisible sur un compte administrateur, bien visible sur un compte standard, où un terminal PowerShell vide restait à l'écran à chaque ouverture de session (constaté sur Famille). L'app cliente démarre maintenant par une console sans fenêtre (`conhost --headless`), et la ligne de lancement est réécrite pour **tous** les comptes à chaque installation, pas seulement pour celui qui l'a demandée.
- **La carte Stockage dit ce que WSL ne rend pas** : « WSL 150,7 Go · 107 Go non rendus ». L'app serveur n'a pas de distribution — elle tourne sous un compte de service —, alors elle demande une fois par heure à une app cliente de lire `df` dans les distributions **déjà en marche** ; aucune n'est démarrée pour la mesure, et la carte lit le cache sans jamais attendre.
- Le cliquet des commentaires ne compte plus les **en-têtes de déclaration** (`@droits`, `@execution`, `@libelle`) : ils sont lus par le code, leurs mots-clés sont français par construction, et ajouter une action suffisait à faire échouer le vérificateur. Plafond descendu de 5 698 à 5 607.
- **Vigie regarde le disque d'elle-même quand il se vide** : une chute de 10 Go en 24 heures (réglable, 0 éteint) déclenche l'analyse d'espace, au plus une fois par fenêtre et jamais quand un mode est actif — une partie, par exemple. Le 28/09 le disque était passé de 112 à 28 Go libres sans que rien ne le dise, et la cause a été trouvée à la main, des jours plus tard.
- **Les deux sondes Windows Update lentes sont mesurées et traitées** : la carte du verrou tombe de **8 417 ms à 1 077 ms** — l'énumération des tâches passait par une applet qui parcourt tout l'arbre à chaque appel (6 682 ms pour quatre dossiers), là où l'interface du Planificateur liste les mêmes six tâches en 43 ms. La carte des mises à jour en attente, elle, coûte 10 s **que Windows nous prend** (sa recherche hors ligne, au même prix deux fois de suite) : elle n'est donc plus jamais calculée pendant qu'on attend, mais par l'ordonnanceur, toutes les six heures. Relevé : `notes/evidence/2026-09-29-slow-update-probes.md`.
- **Vigie n'arrête plus que ses propres processus** : l'arrêt de l'app serveur visait « celui qui tient le port 47600 » sans rien vérifier — un autre programme ayant pris ce port aurait été tué par une mise à jour. Il faut maintenant un PowerShell **et** une ligne de commande citant un de nos scripts sous notre installation ; une ligne illisible ne prouve rien et n'autorise rien.
- **Vigie ne peut plus s'emballer** (**D126**) : une tâche de fond ne lance jamais une tâche de fond, et un plafond dur (`Refresh.MaxChildren`, 8 par défaut) **refuse** tout lancement au-delà, en le journalisant. Posé après un incident sur la machine du propriétaire, le 29/09 : un garde-fou rendu aveugle par le passage à un verrou par sonde a laissé les tâches de fond se lancer les unes les autres — 161 processus élevés, 0,3 Go de mémoire libre, et une app serveur incapable d'écouter son port.
- **Un ordonnanceur dans la veille permanente** (**D125**) : la boucle passe toutes les 30 s et lance les **calculs** que les modules déclarent — pas des cartes : un calcul alimente plusieurs cartes, une carte peut en avoir plusieurs. Tout se décide en **temps écoulé**, jamais en nombre de passages ; les lancements sont asynchrones et parallèles jusqu'à `RefreshMaxParallel` (3 par défaut, `0` = sans limite) ; un calcul déjà en cours n'est jamais relancé ; un calcul **en échec** est repoussé avec un délai qui double, pour cesser d'être le plus vieux et de bloquer les autres ; un calcul **trop long** est journalisé, historisé et montré sur la carte « Processus de Vigie », sans jamais être arrêté. Les **modes** sont déclarés par les modules — « en jeu » n'est plus un cas codé en dur — et un intervalle se déclare par mode.
- **C'est le serveur qui relève, plus le client** (**D124**) : la veille permanente joue désormais des cadences pendant une partie — cartes Jeu et Ressources recalculées toutes les 60 s — au lieu de n'agir que sur le changement d'une sentinelle. « Un jeu tourne » ne change pas pendant la partie : rien n'était donc recalculé, et l'échantillonnage reposait en fait sur l'app cliente. Mesuré sur la soirée du 28/09 : une partie de plus de deux heures n'a laissé que **4 passages et 430 s**, tous pris tant que l'app cliente vivait, et la session s'est fermée neuf heures trop tard. Coût de la cadence, mesuré et écrit à côté d'elle : 5,4 % d'un cœur pour la carte Jeu, 2,3 % pour Ressources, et **zéro hors partie**.
- **Une app cliente absente est ramenée par la veille permanente** : constatée muette deux passages de suite (une minute d'écart) avec le processus qui a écrit son dernier battement réellement disparu, sa tâche est redémarrée, au plus deux fois, chaque tentative journalisée. **Aucun processus n'est arrêté** : si le processus du dernier battement existe encore, l'app cliente est « vivante mais muette » et Vigie ne touche à rien. Ce garde-fou vient d'une mesure du 29/09 : `Test-VigieTaskProcessAlive` compare des LIGNES DE COMMANDE, que Windows cache pour un processus élevé vu d'une session qui ne l'est pas — il a répondu « aucun processus » d'une app cliente qui tournait, et la relance a terminé sa tâche, donc le processus vivant. Un test qui peut se tromper ne décide jamais seul d'un geste.
- **Le détail d'un compte disait « tâche illisible »** au lieu de son état, de son niveau, de sa commande et de son code : Windows rend un HRESULT non signé sur 32 bits, `0x800710E0` vaut 2 147 946 720, et le convertir en `Int32` levait — au moment précis où l'on cherchait pourquoi une tâche avait échoué. Le même piège était déjà corrigé dans la lecture des maux d'une tâche, et pas ici. Constaté sur le compte Famille, dont le dernier code EST `0x800710E0` : un démarrage refusé.
- **Vigie surveille ses propres app clientes** : le battement de cœur de chaque app cliente dont la session est ouverte est lu à chaque calcul de la carte « Processus de Vigie » (90 ms) ; une qui cesse de battre est signalée avec sa durée de silence, et la disparition est consignée une seule fois dans `var/history/tray-vanished.jsonl` avec le jeu en cours. Le 28/09 l'app cliente d'un compte est partie en pleine partie sans une ligne — ni sortie propre, ni rapport d'erreur, ni vidage mémoire — et Vigie n'a plus rien mesuré jusqu'au lendemain sans le dire.
- Le cliquet des noms (`check-naming.ps1`) lit enfin les **paramètres**, les **propriétés affectées** et quarante mots
  de plus : les 277 identifiants français comptés étaient en réalité 481, sans qu'un seul nom ait été ajouté. Après le
  renommage du lot, le plafond est de 450, et il ne remonte pas.
- **L'audit Windows Update s'affiche enfin** (**S04**) : il produisait depuis le premier jour un rapport complet — verrouillage, stratégies, redémarrage en attente, tâches planifiées, services — qui partait dans un fichier sous `var/log/` que rien n'ouvrait ; l'audit servait de trace pour un agent, pas d'information pour l'utilisateur. Le rapport revient maintenant par le canal ordinaire d'une action (`result.detail`) et la page l'ouvre dans une fenêtre large, préformatée : les colonnes tiennent, les lignes longues se replient. Le fichier reste, nommé sous le rapport, pour être gardé ou envoyé. Le chemin est générique, donc « Détail des comptes » et « Réparer les tâches » se lisent droit du même coup — leur indentation était repliée par la fenêtre depuis toujours. Et parce que ces lignes sont devenues de l'interface, elles portent leurs accents.
- **Les deux applications portent enfin le même nom partout** (**D108**, sujet S06) : « app serveur » et « app cliente » étaient écrits dans l'interface depuis le 29/08, et le code gardait l'ancien mot dans ses dossiers, ses fichiers, ses clés et ses commentaires — 37 fichiers. On devait le reprendre « par zones, en y passant pour autre chose » : treize mois plus tard, rien n'avait bougé. Tout est renommé d'un coup : `apps/client/`, `client.ps1`, `scripts/client.ps1`, `Get-ClientHeartbeat`, `client.alive`, `client-vanished.jsonl`, `CORE-CLIENT`, les clés de libellés, la documentation. Ce qui rendait l'opération risquée — les chemins écrits dans les tâches planifiées déjà posées — avait disparu le 29/09 : une seule fonction écrit cette ligne, et l'installation la réécrit pour tous les comptes à chaque passage. Un quatrième cliquet dans `check-naming` tient le mot à **zéro** : il ne peut pas revenir un fichier à la fois.
- **Un vérificateur lit enfin le PowerShell** (`check-powershell`) : il donne les 159 scripts du dépôt à l'analyseur, sans en exécuter aucun. Il a été écrit parce qu'il a trouvé, dès sa première passe, que `update-mode-on.action.ps1` n'analysait plus depuis le commit `d1f7a64` — une apostrophe française au milieu d'une chaîne à guillemets simples la ferme, et le reste de la ligne devient du code. L'action « Mode MAJ (déverrouiller) » ne pouvait donc plus tourner, et **rien ne le disait** : un fichier n'est analysé que le jour où on en a besoin.
- **La fenêtre de confirmation retrouve l'icône de Vigie** : elle la cherchait dans un dossier qui n'a jamais existé, le test échouait en silence, et la fenêtre gardait l'icône de l'interpréteur.
- **Ce que la source n'a plus, l'installation ne le garde plus** : la copie d'installation ajoutait et écrasait, sans jamais supprimer — un fichier retiré en amont restait sur le disque pour toujours. Constaté le 30/09, dans l'heure qui a suivi le renommage : l'ancien dossier de l'app cliente a survécu dans l'installation, la tâche planifiée du compte nommait encore l'ancien script — il existait, donc rien ne se déclarait cassé — et **deux app clientes tournaient sur le même compte**, chacune avec son icône et son battement de cœur. L'installation supprime désormais, à la racine et dans `apps/`, ce que la source n'a pas ; `var/` est la seule chose gardée, c'est la donnée et non le code.
- **Et une tâche qui lance une autre application que celle installée est un défaut structurel** : jusqu'ici il suffisait que le fichier existe. La réparation des tâches la réécrit maintenant d'elle-même, au démarrage de l'app serveur.
- **Vigie note qui tient les ports réseau, mais seulement quand ça se gâte** : Windows se plaint de ne plus avoir de port temporaire libre **75 fois depuis le 25/07** sur cette machine, et deux plaintes identiques ne sont jamais à moins de six heures — il étouffe les répétitions, donc le compte affiché est un plancher, pas un total. Quand on lit la carte, la réserve est revenue à 1 % et le tableau nomme des processus qui n'y sont pour rien. La veille permanente relève désormais l'occupation à chaque passage (15 ms) et **n'écrit que si elle dépasse un seuil réglable, ou dans le quart d'heure qui suit une plainte** : tant que tout va bien, pas une ligne.
- **Et la jauge des ports ne voyait pas les ports vraiment pris** : elle lit les tables de **connexions**, où une prise de port sans connexion ne figure pas. Mesuré le 30/09 : **128 comptés contre 381 réellement tenus**, dont 335 dans cet état — dont **244 pour le seul hôte réseau de WSL**, qui ne les rend jamais. La lecture complète coûte 1,5 s, cinquante fois la jauge : elle est donc prise **seulement au moment d'écrire**, et c'est elle qui nomme le porteur avec ses états.
- **Un fait du journal n'est plus pris pour un état de la machine** (**D127**, demandé) : la carte « Journal Windows » restait rouge une journée entière pour une allocation de port qui avait échoué **une fois**, des heures plus tôt, sur une machine dont la réserve était revenue à 1 % — et comme cet événement revient environ une fois par jour depuis le 25/07, la carte était rouge presque tous les jours. Chaque ligne porte désormais son état, et c'est **la mesure du moment** qui tranche : « en cours » quand elle le confirme — la ligne pèse alors quel que soit son âge —, « ce n'est plus le cas » quand elle le dément — la ligne reste citée et ne pèse plus —, « on ne sait pas si c'est encore le cas » quand rien ne peut le vérifier, et « arrivé » pour un fait passé par nature. Et l'âge déclasse : au-delà d'une heure (réglable), une erreur reste dans le tableau, retrouvable, sans mettre la carte en défaut — **un écran bleu compris**. Le geste proposé ne l'est plus quand il n'y a plus rien à faire.
- **Déclasser n'est pas faire disparaître, et ce qui revient le dit** (**D127**, précisé le jour même) : une erreur déclassée par son âge reste dans le tableau, avec son état, et la carte annonce le compte de ce qui **pèse** — le reste se lit juste en dessous. Chaque ligne porte désormais sa **récurrence** : « 3 fois en 7 jours, la dernière il y a 26 h », parce qu'une répétition n'est pas un accident et que la cacher reviendrait à la présenter comme tel. Le verdict est rendu en un seul endroit (`Get-JournalFactVerdict`), partagé par la carte « Journal Windows » et par les problèmes de « Mise à jour du système » — dont les erreurs consignées par Windows suivent maintenant la même règle : trois échecs d'installation de paquets du Store en sept jours, le dernier il y a plus d'un jour, sont cités sans mettre la carte en défaut.
- **Les tableaux de détail ne sont plus illisibles** : ouverts dans une fenêtre de 520 px, quatre colonnes se disputaient la largeur — la dernière, qui porte les messages longs, était forcée sur une seule ligne et partait derrière une barre de défilement horizontale, pendant que la première se cassait **lettre par lettre** (« Microso ft-Windo ws-Distribu tedCO M », vu à l'écran). La fenêtre s'ouvre désormais large, comme le récapitulatif ; la dernière colonne se replie au lieu de pousser le tableau de côté ; la première a un plancher, et un mot ne se coupe plus que s'il ne tient vraiment pas.
- **La carte nomme ce qui bloque une mise à jour, au lieu de donner un code** : « installation en échec, 0x80073D02 » ne dit rien à personne. Windows, lui, sait : son journal de déploiement **nomme l'application à fermer**. La carte le reprend — « Windows nomme ce qu'il faut fermer : Microsoft.YourPhone, OpenAI.Codex » — et explique la suite : un paquet en cours d'utilisation ne peut pas être remplacé, la mise à jour s'applique à la fermeture de session ou au redémarrage.
- **Et le nettoyage qui tourne en rond est dit** : le service de déploiement n'arrivait pas à supprimer des fichiers d'un paquet désinstallé sous « C:\Program Files\WindowsApps\Deleted » et réessayait **377 fois en sept jours, une tentative toutes les neuf minutes**, redémarrages compris. Personne ne le voyait : c'était dans un journal que personne n'ouvre. La cadence est mesurée sur les dernières 24 heures, pas sur la semaine — la moyenne sur sept jours est diluée par les heures machine éteinte et annonçait une tentative toutes les 24 minutes là où il y en a une toutes les six.
- **Vigie nomme qui tient un fichier**, par le Gestionnaire de redémarrage de Windows — celui-là même dont se servent les installateurs pour dire quoi fermer (`scripts/lib/file-locks.ps1`). Lecture seule : on demande QUI tient, jamais de redémarrer quoi que ce soit. Éprouvé sur un fichier ouvert en exclusif : « tenu par PowerShell 7 (PID 46108) ».
- **Et la carte va regarder dans le dossier des paquets supprimés**, que l'app serveur peut lire et pas une session ordinaire : elle nomme les fichiers qui restent et les processus qui les tiennent. Piège évité au passage, et c'est exactement celui que `Test-PathSafe` documente depuis le 29/08 : `Test-Path` **lève** sur ce dossier pour une session non élevée, et sous la préférence par défaut il répond « faux » — la carte aurait alors annoncé « le dossier est vide » là où elle n'avait pas le droit de regarder. Un refus se dit comme un refus.
- **Une carte dit enfin de quand elle date** (**S16**) : une valeur vieille de vingt-deux heures s'affichait exactement comme une valeur de la seconde. Chaque carte porte maintenant trois moments — quand la page a lu le cache, quand la sonde a produit la mesure, quand l'ordonnanceur est passé — plus l'intervalle prévu et, s'il y en a, les échecs enchaînés du calcul. Le détail s'ouvre depuis le menu de la carte.
- **Et quand elle est en retard, ça se voit sans rien ajouter** : le bouton de rafraîchissement de la carte prend la teinte d'alerte. Pas de mention, pas d'élément de plus — l'icône qu'on allait cliquer de toute façon. En retard veut dire le double de l'intervalle et au moins deux minutes, ou un calcul qui enchaîne les échecs : celui-là ne reviendra pas tout seul.
- **La relecture automatique ne ternit plus l'interface** : elle passait par le même chemin qu'un recalcul complet, et toutes les cartes se grisaient à chaque passage — plusieurs fois par minute. Seul un vrai recalcul les met en sursis désormais ; le liseré de l'en-tête continue de dire, discrètement, que quelque chose se passe.
- **Deux calculs n'avaient jamais tourné depuis que l'ordonnanceur existe**, et rien ne le disait. Un calcul qui n'a jamais démarré n'a pas de dernier départ, donc son retard est infini — et sur un état neuf c'est vrai de **tous** à la fois. Le tri ne départage pas des valeurs égales : trois étaient pris sur quinze, au hasard, et c'étaient toujours les mêmes. Les deux cartes du module Débogage affichaient ainsi une mesure vieille de 29 heures et de 10 jours comme si elle était fraîche. Le tri est maintenant départagé par la clé du calcul : stable, et dès le premier passage chacun a une vraie date.
- **Et un lancement refusé compte désormais comme un échec** : c'était un `continue` nu — aucune entrée, aucun échec, aucune trace. La carte gelait pour toujours pendant que l'état restait muet, et comme un calcul jamais démarré repasse en tête à chaque fois, le refus se répétait indéfiniment. Il prend maintenant le délai qui double, comme les autres : il cesse d'être le plus vieux, il cesse de tenir la première place, et la carte le dit.
- **Un module allumé par un compte est calculé, quel que soit le compte qui regarde** — et c'est la vraie raison pour laquelle les deux calculs du module Débogage n'avaient jamais tourné. Ce module naît éteint ; l'utilisateur l'avait allumé, et ce choix vit dans **son** profil. L'ordonnanceur, lui, calcule sans demandeur : il lisait la configuration du compte de service, n'y trouvait rien, retombait sur la valeur par défaut et écartait le module. Il était donc **allumé pour l'utilisateur et éteint pour l'ordonnanceur**, avec deux cartes affichées comme les autres et jamais calculées une seule fois. Les choix de tous les comptes sont désormais réunis, et un seul « oui » suffit : 39 ms, gardés trente secondes.
- **La carte Comptes échouait huit fois de suite alors que son calcul marchait** : une sonde dont le rendu dépend de qui regarde a **une entrée de cache par compte** (**D109**). La preuve qu'un calcul a produit quelque chose — « l'empreinte du cache a bougé » — lisait la **première** entrée rencontrée dans le fichier, donc souvent celle d'un autre compte, qui n'avait aucune raison de bouger. L'ordonnanceur comptait un échec, repoussait, recommençait. C'est la **plus récente** des entrées qui fait foi désormais, quel que soit le compte à qui elle appartient.
- **Une mesure qui dépend de qui regarde est désormais calculée pour chaque compte connecté** (**D109**). Le cache de ces sondes a une entrée par compte ; l'ordonnanceur, qui calcule sans demandeur, écrivait dans la sienne — une entrée que personne ne lit jamais. Mesuré le 30/09 : la carte WSL était recalculée toutes les cinq minutes toute la journée, et ce qui s'affichait datait de **31 heures**. Et comme une requête ne calcule plus rien (**D124**), rien ne l'aurait jamais rattrapé. L'ordonnanceur lance maintenant un calcul par session ouverte — leur ruche de registre est montée, donc ce sont eux qui peuvent regarder — et la preuve du résultat porte sur l'entrée de ce compte-là. Personne de connecté, rien à calculer, et personne pour le lire non plus.
- **Les cartes des gestionnaires de paquets portent enfin leur intervalle** : le calcul déclarait une seule carte, « pkg-none », celle qui ne s'affiche justement **que s'il n'y a aucun gestionnaire**. Les cartes réellement vues — winget, choco, pip — n'avaient donc ni intervalle ni fraîcheur : elles ne pouvaient pas dire leur âge, ni signaler un retard. Les douze cartes que cette sonde peut produire sont maintenant déclarées.
