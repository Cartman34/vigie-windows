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
- Documentation : `docs/conventions.md`, `docs/technologies.md`, mise a jour des
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
- `docs/conventions.md` : regle "tous les scripts idempotents".

## 2026-08-19 (d) — Organisation des ports
### Modifie
- Port par defaut 8787 -> 47600 ; documente comme configurable.
### Ajoute
- `LocalWork/PORTS.md` : registre des ports (plage 47600-47699).
- `docs/conventions.md` : convention d'allocation des ports.

## 2026-08-19 (e) — Fix encodage PowerShell 5.1
### Corrige
- `.ps1`/`.psd1` reconvertis en ASCII pur (les accents/tiret cadratin cassaient
  l'analyse en Windows PowerShell 5.1). Regle documentee dans conventions.md.

## 2026-08-19 (f) - Cible PowerShell 7 + UTF-8
### Modifie
- `install/start/run.ps1` : bascule auto en pwsh (PS7), UTF-8 natif ; install.ps1
  installe PS7 via winget si absent. Lanceurs conserves en ASCII pour la bascule.
- `docs/conventions.md` : PS7 + UTF-8 remplace la contrainte ASCII generale.

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
### Securite (revue : docs/operating/SECURITY.md)
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
  serveur tourne avec les droits. Protections maintenues (voir SECURITY.md).

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
  Archive `docs/maquettes-validees/` volontairement non retouchée.
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
  `docs/fr` et `docs/en` (configuration, windows-update, dépannage, sondes-et-actions).
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
- Documentation alignée : `docs/fr` et `docs/en` (configuration, fonctionnalités,
  dépannage), `docs/REPRISE.md`, note de mise à jour sous **D18**.
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
