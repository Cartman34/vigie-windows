# SUIVI - Vigie

> Fichier de suivi pour reprendre le projet a tout moment.
> Conventions detaillees : `docs/conventions.md`. Disciplines de process : `docs/DISCIPLINES.md`. Prise en main : `PRISE-EN-MAIN.md`.

## Etat au 20/08/2026

Serveur **operationnel**, lance en admin via `backend/run.cmd` (ou `run.ps1`), PS7 + Pode (portee AllUsers).
Toutes les modifs de sondes / `common.ps1` / actions sont **live** (re-sourcees a chaque requete) ;
`index.html` change => la page se recharge seule (version).

## Architecture

- **backend/** : serveur Pode (`server.ps1`), bibliotheque partagee (`lib/common.ps1`),
  sondes (`probes/<theme>/*.probe.ps1`), actions (`actions/*.action.ps1`), config (`config.psd1`, port 47600).
- **frontend/index.html** : SPA (masonry de cartes, modales in-app `HDS`, rafraichissement par carte).
- **Lanceurs** (ASCII) : `run.cmd` (robuste, contourne ExecutionPolicy/MOTW) -> `run.ps1` -> `start.ps1` ; `install.ps1`.
- Securite : 127.0.0.1 only, jeton Bearer, anti-CSRF, whitelist d'actions + confinement chemin.

## Fonctionnalites par theme

- **Windows Update** : verrouillage (NoAutoUpdate + taches desactivees + verrou ACL SYSTEM),
  MAJ en attente (distingue pilotes/optionnels), historique. Actions : Mode MAJ (verrouiller/deverrouiller),
  Lancer l'audit, Ouvrir Windows Update.
- **Systeme** : OS/edition/activation, perf (RAM/CPU/uptime), disque.
- **Securite** : antivirus (Avast via SecurityCenter2), pare-feu, VBS/HVCI.
- **Reseau** : connexion (test TCP reel), IP LAN, IP publique (a la demande), IPv6, MAC, liste des interfaces,
  VPN, latence + debit descendant/montant (a la demande). Wi-Fi (type / SSID / etat) : **TODO**.
- **WSL** : etat/RAM/distro.
- **Outils & paquets** : gestionnaires de paquets detectes (winget, choco, scoop, npm, pip, cargo, gem, dotnet...).

## Conventions (voir docs/conventions.md)

1. Pas de duplication : logique partagee dans `common.ps1`
   (`Test-Elevated`, `Test-UpdateTasksAclLock`, `Invoke-Native`) ; rendu de carte `cardHtml`.
2. Toujours traiter erreurs / sorties / codes de retour (ex. `Invoke-Native`, actions verifiant le resultat reel).

## Journal des corrections recentes

### Session 21/08 (suite)
- Icone tray : queue d'aiguille + graduations SUPPRIMEES (bruit a 16px = faux "bug d'aiguille"). Aiguille part du centre.
- Double-clic tray corrige (variable d'env nulle cassait Join-Path -> --app KO). openApp robuste.
- Paquets : nouvelle action `pkg-check-updates` (a la demande) -> MAJ disponibles par gestionnaire (winget/pip/npm/choco/scoop/gem),
  affichees "(N MAJ)" + liste dans le detail ; carte orange si des MAJ existent ; bouton "Verifier les mises a jour".
- Front : NOTIFICATIONS refaites -> toasts empiles auto-dismiss (succes 4.5s, erreur 9s), bouton cloche + DRAWER droite
  (historique, supprimable ; supprimer une notif retire aussi son toast ; "Tout effacer").
- Debordement texte long (chemins) corrige (overflow-wrap:anywhere). Chargement initial epure.
- Icone "i" des champs recentree (SVG au lieu du glyphe italique).
- GENERIQUE : le titre affiche le NOM DE MACHINE calcule ($env:COMPUTERNAME, via /state.host) au lieu du nom de machine en dur.

### TODO genericite (a finir)
- [ ] Chemins encore specifiques a cette machine : `config.psd1` ToolsPath absolu (LocalAgentAdmin/tools) -> rendre calcule/relatif.
      Verifier tout chemin/nom code en dur pour un deploiement sur un autre PC.
- [ ] Nom de machine code en dur : "HYPERION" est le NOM DE LA MACHINE de l'utilisateur, pas un nom de projet.
      Ce n'est PAS cosmetique : c'est un defaut de genericite (l'app ne doit rien contenir de specifique a un PC).
      Fait : tache planifiee `Vigie`, raccourci `Vigie.url`, mutex `Local\VigieState_*` / `Local\VigieStateRecompute`,
      titre openapi `Vigie API`, lanceur `backend/demarrer-vigie.vbs`, docs.
      Fait aussi : `backend/tray.ps1` (mutex `VigieTray`, types `VigieNative` / `VigieDarkColors`) et les
      variables d'environnement `VIGIE_BACKEND` / `VIGIE_TOKEN` / `VIGIE_PORT` (ex-`HCP_*`).
      Le nom de machine a TOTALEMENT disparu du projet (verifie par recherche exhaustive).
      Exception : `docs/maquettes-validees/` n'est pas retouche (archive des supports de decision).
- [ ] Menu tray : style precis a valider (coins/espacement/survol) — en attente des details utilisateur.
- [ ] Stale-while-revalidate complet (cartes-squelette pour sondes pas encore pretes).


### Session 21/08 (matin)
- **408 sur /state (effet troupeau)** corrige : `Get-State` en SINGLE-FLIGHT (un seul recalcul a la fois, verrou
  `Local\VigieStateRecompute` (nomme `Local\HcpStateRecompute` a l'epoque), gestion du mutex abandonne),
  les autres requetes servent le cache immediatement,
  ecriture cache INCREMENTALE et ATOMIQUE (chaque sonde finie conservee), sondes lentes calculees en dernier.
- **Icone tray = STATUT DE L'APP** (et non des composants) via `/health` : vert=en marche, orange=demarrage,
  rouge=erreur/arret. Enleve aussi la charge /state du tray.
- **Fenetre dediee** : "Afficher l'application" ouvre le navigateur en mode `--app` (fenetre sans onglets).
  Item "Ouvrir dans le navigateur" ajoute (option D). Menu : Afficher / Ouvrir navigateur / Etat / Relancer /
  Redemarrer serveur / Journaux / Quitter.
- **Chargement non bloquant** (front) : les cartes restent pendant l'actualisation ; repere "Chargement..." seulement
  au 1er affichage ; message "(quelques secondes)" retire.

### TODO chargement (a finir)
- [ ] Stale-while-revalidate complet : le serveur pourrait lister TOUTES les cartes attendues avec un flag "en cours"
      pour afficher des cartes-squelette (valeur en chargement) plutot que des cartes absentes.
- [ ] Option : refresh en fond via timer Pode pour que /state ne recalcule jamais dans la requete (necessite redemarrage serveur).


### Session 20/08 (soir)
- App barre systeme `tray.ps1` (serveur en fond + icone statut) ; autostart pointe dessus.
- Cache : invalidation **par sonde** (mtime) au lieu de globale -> editer une sonde ne recalcule qu'elle.
  TTL allonges (wsl 600, lock 600, pending 900). Delai front /state porte a 90 s (1er calcul a froid).
- `netmeasure.json` : ecriture par **fusion** (`Update-StateJson`) -> la mesure de debit n'efface plus l'IP publique.
- Debit **montant** ajoute (upload ~5 Mo). Gestionnaires de paquets : valeur = version seule, detail dans le Guide.
- Filtre rapide par groupe (chips) en haut ; icone "Resoudre" a la couleur du texte ; message d'erreur accentue (UTF-8).
- Bouton "Ouvrir Windows Update" deplace sur la carte Mises a jour en attente.


- Verrou ACL : `takeown/icacls` fonctionnent (exit 0, DENY pose). Le bug etait la DETECTION
  (Windows FR affiche "Systeme") -> desormais via `icacls` (chaine `(DENY)`, non localisee). Le verrou marche.
- Statut de carte = sante fonctionnelle : un warning de ligne sans impact (ex. verrou ACL) ne fait
  plus passer la carte en orange.
- Reseau : detection via .NET (`System.Net.NetworkInformation`) au lieu de Get-Net* (CIM) qui renvoyait du vide.
- Cache par sonde + invalidation ciblee apres action (`result.invalidate`).
- Front : modales in-app (fin des popups navigateur), boutons "occupes", "Resoudre" types, chip honnete,
  libelles cliquables, ic. de rafraichissement par carte, theme clair plus colore, toasts de suivi detaches.

## Sujets ouverts / TODO

- [x] Icone tray : **3 statuts uniquement** (vert conforme / orange surveiller / rouge action). Pas d'etat "inconnu" :
      tout defaut/erreur/serveur injoignable => **ROUGE** (regle utilisateur : si l'app ne se lance pas bien, c'est rouge).
- [x] "Pas d'etat" dans le menu : la ligne Etat etait un item desactive (texte gris sombre invisible sur menu sombre)
      -> passee en ToolStripLabel a couleur lisible. Poll verifie OK via pode-request.log (GET /state = 200 toutes les 30 s).

- [x] Integration Windows : **app barre systeme** (`tray.ps1`) = serveur en fond (cache) + icone permanente
      qui reflete le STATUT (vert/orange/rouge, poll /state 30 s) + menu (Ouvrir/Redemarrer/Journaux/Quitter).
      Autostart au logon (tache 'Vigie', Highest) via `install-autostart.cmd`.
- [x] Icone tray : jauge (G5) style **B (anneau)**, sens INVERSE (conforme = jauge pleine), aiguille large
      couleur du statut + liseré **teinte foncée** (facteur 0,72) + point blanc central. Dessin GDI+ dans `tray.ps1` (`$setIcon`).
- [ ] Gestionnaires de paquets : afficher s'ils ont des **MAJ disponibles** (winget upgrade / choco outdated /
      npm outdated -g / pip list --outdated ...). A concevoir (perf : appels lents -> a la demande + cache long).
- [ ] Reseau Wi-Fi : ajouter type (Wi-Fi/Ethernet), nom (SSID via `netsh wlan show interfaces`), etat Wi-Fi.
- [ ] "0 taches desactivees" : la carte affiche l'etat reel par tache (deplier) ; verifier si Windows reactive.
- [ ] Perf sondes lentes : envisager stale-while-revalidate (servir le cache et recalculer en fond).
- [ ] MAJ systeme depuis l'app : bouton "Ouvrir Windows Update" livre ; installation silencieuse
      possible mais volontairement NON faite (principe "rien sans consentement").
- [ ] Perf : `lock.probe` lente (~14 s) a cause de Get-ScheduledTask ; a optimiser si genant.

## 2026-08-22 (nuit, fin+) — Consentement explicite avant toute élévation

- **Plus jamais d'invite UAC « nue » (D22)** : une fenêtre explique d'abord ce qui va être
  modifié et pourquoi, puis seulement Windows demande l'autorisation. Refuser n'affiche
  aucune invite système. Échap et la croix refusent.
- **Bloc d'élévation factorisé** : `Test-IsElevated`, `Show-ElevationRationale`,
  `Invoke-ElevatedSelf`, `ConvertTo-PSLiteral`, `Set-WindowChrome` dans `lib/common.ps1`.
  Les trois scripts (`install-autostart`, `uninstall-autostart`, `uninstall-legacy`) avaient
  chacun **sa propre copie** du test d'élévation et de la relance.
- **La sortie de la session élevée n'est plus perdue** : `-Verb RunAs` interdit la
  redirection, donc la session élevée écrit un journal que l'appelant relit et réaffiche.
- **Code de retour 3** = refusé par l'utilisateur, distinct d'un échec.
- **`Set-WindowChrome`** centralise l'appel DWM (barre de titre sombre, coins arrondis,
  couleur de bordure). `tray.ps1` déclarait sa propre signature P/Invoke : supprimée.
  Vérifié : `dwmapi.dll` n'apparaît plus qu'à **un seul endroit** du projet.
- **Textes de l'interface accentués** : les scripts sont lus par `pwsh` (PS7), qui lit
  l'UTF-8 sans BOM. Vérifié par décodage UTF-8 strict et relecture d'un accent précis.
  Les lanceurs `.cmd`/`.vbs` restent ASCII pur.
- **Validé réellement** : Parser sur 41 fichiers ; helpers chargés ; échappement des
  apostrophes testé ; `-AssumeYes` court-circuite bien ; **fenêtre affichée et capturée**
  (596×345, boucle de messages réelle) ; fermeture automatique → **False**, le refus est
  bien le défaut ; les 3 attributs DWM renvoient HRESULT 0.

## 2026-08-22 (nuit, fin) — WSL inactif signalé, contrat corrigé

- **WSL inactif = rouge, champ ET carte (D20)**. Levait une contradiction : le champ était déjà
  `error` alors que la carte restait `neutral`. Les deux dérivent maintenant de la **même**
  variable et ne peuvent plus diverger. WSL non installé reste neutre.
- **Rebascule en une seule ligne**, exigence explicite : `$inactiveSeverity = 'error'` en tête de
  `backend/probes/wsl/wsl.probe.ps1`, sous un bandeau qui énumère `error` / `warn` / `neutral`.
  **Rien à changer côté front** : `.card.st-error` (lisere gauche 4 px) et le badge « Problème »
  existent déjà pour les trois valeurs.
- **Contrat corrigé (D21)** : `api/openapi.yaml` interdisait `neutral` en statut de module alors
  que `New-ModuleObject` l'accepte et que les sondes en émettent. Le contrat était faux.
- **Validé réellement** : sonde exécutée sur les **6** combinaisons (3 sévérités × actif/inactif)
  à partir du contenu réel du fichier — carte et champ concordent partout, boutons pertinents
  (Actif : Redémarrer/Arrêter ; Inactif : Démarrer).

## 2026-08-22 (nuit, suite) — Menu du tray facon Windows 11

- **Coins arrondis NATIFS** via DWM (`DWMWA_WINDOW_CORNER_PREFERENCE` = `DWMWCP_ROUND`,
  `DWMWA_BORDER_COLOR`) plutôt qu'une découpe de région : anticrénelage et ombre système
  préservés. Appliqué à chaque ouverture (idempotent).
- **Survol encarté et arrondi** (rayon 5, marge 5) au lieu d'une bande pleine largeur — c'est
  ce qui distingue le plus un menu Win11 du rendu WinForms par défaut. Séparateurs fins,
  encartés sur les mêmes marges. Fond uni, sans dégradé ni bande de marge d'icône.
- **Items de 32 px** (hauteur mesurée, pas estimée).
- **DRY** : palette dans `VigieMenuPalette`, source unique pour la table de couleurs ET le
  renderer ; couleur + hauteur des items posées par une seule boucle sur `$menu.Items`
  (elles étaient recopiées item par item).
- **Repli** : toute erreur (compilation C#, DWM) retombe sur le rendu par défaut, menu
  utilisable. Sur Windows 10, l'appel DWM échoue sans dommage.
- **Piège rencontré** : `Add-Type` échouait sur `System.Drawing.Drawing2D`. `System.Drawing`
  est scindé : `Color` est dans `System.Drawing.Primitives`, `Graphics`/`GraphicsPath` dans
  `System.Drawing.Common`. Il faut référencer les deux.
- **Validé réellement** : Parser OK ; **C# compilé** (les 4 overrides sont bien présents) ;
  menu construit hors écran — items à **32 px**, séparateur à 6 px ; les deux attributs DWM
  renvoient **HRESULT 0** sur cette machine (Windows 10.0.26200).
- **Non vérifié** : l'aspect visuel. Il faut relancer le tray pour juger à l'œil.

## 2026-08-22 (nuit) — Configuration générique, une valeur = un seul endroit

- **Configuration en deux couches (D18)** : `config.psd1` versionné et **générique** (plus aucun
  chemin de machine) + `config.local.psd1` **ignoré par git** pour les surcharges locales, avec
  `config.local.sample.psd1` comme modèle. `Get-Config` fusionne les deux et échoue avec un
  message explicite si le fichier local est illisible.
- **`ToolsPath` devient optionnel** : vide ou introuvable → `Get-ToolsPath` / `Get-AdminRoot`
  rendent `$null` et les 6 actions concernées (`run-audit`, `update-mode-on/off`, `toggle-vbs`,
  `toggle-hvci`, `open-folder`) renvoient `New-ToolsMissingResult`, un message unique et clair.
  Un clone neuf fonctionne donc sans configuration.
- **Une valeur = un seul endroit (D15)**, dette remboursée :
  - `install-autostart.ps1` écrivait `http://127.0.0.1:47600/` en dur (×2) — un changement de
    port produisait un raccourci mort. Dérive maintenant de `Get-AppUrl`.
  - `Test-ServerUp` avait des valeurs par défaut `'127.0.0.1'` / `47600` qui doublonnaient la
    config alors que **tous** les appelants passent leurs paramètres : défauts supprimés,
    paramètres rendus obligatoires.
  - La construction d'URL était recopiée dans `run.ps1`, `start.ps1` et `tray.ps1` →
    `Get-AppUrl` / `Get-ApiUrl` dans `common.ps1`.
- **Exception documentée** : la liste blanche anti-CSRF de `server.ps1` garde `127.0.0.1` et
  `localhost` en littéral — ce sont les origines de **bouclage**, pas une copie de `BindAddress`
  (le port, lui, dérive bien). Un middleware Pode tourne dans un runspace séparé où `$cfg`
  n'est pas visible : d'où le passage par `$env:VIGIE_*`.
- **Sur cette machine** : `backend/config.local.psd1` a été créé (dans le worktree ET dans le
  dépôt principal) avec l'ancien `ToolsPath`, pour ne pas régresser l'installation existante.
  Fichier ignoré par git (vérifié via `git check-ignore`).
- **Validé** : Parser sur 41 fichiers, 0 erreur ; fusion de config testée (valeurs et dérivées
  correctes) ; cas générique sans config locale testé (`$null` + message d'action) ; cas chemin
  configuré mais inexistant testé ; `Test-ServerUp` refuse bien un appel sans paramètre.

## 2026-08-22 (soir) — Écran de chargement, lien GitHub, élimination du nom de machine

- **Écran de chargement (D08)** : `#splash` plein écran présent dans le HTML *statique* (visible avant
  même l'exécution du JS). « Vigie » en gros (clamp 54–88 px), sous-titre = nom de machine dès qu'il
  est connu, marque **D01** redessinée en SVG à la géométrie exacte du générateur `.ico`
  (anneau 0,45 / piste 0,35 à 11 % / 7 graduations / aiguille à talon −0,06 avec lisere assombri 0,72 /
  moyeu + point blanc), aiguille animée de 0 à la fraction « démarrage » 0,50.
  S'efface au **premier** chargement (réussi *ou* en erreur — sinon l'erreur resterait cachée),
  avec durée mini 550 ms (anti-clignotement) et garde-fou 90 s. `prefers-reduced-motion` respecté.
- **Lien GitHub (D09)** à 4 endroits : splash, icône discrète dans la topbar, pied de page, et
  « À propos de Vigie » dans le menu du tray. Ouverture en `_blank` + `rel="noopener"`.
- **DRY** : l'URL du dépôt est une **constante unique** par langage — `REPO_URL` (front) et `$RepoUrl`
  (tray). Les liens du front sont câblés par `wireRepoLinks()` via `data-repo-link` ; le libellé
  affiché est **dérivé** de l'URL (aucune duplication). Nombres magiques du front hissés en
  constantes (`REFRESH_MS`, `VERSION_POLL_MS`, `SPLASH_*`). Nom de machine factorisé dans
  `setMachineName()` (était dupliqué). Côté tray, `$openUrl` factorise l'ouverture d'URL
  (navigateur + dépôt) avec gestion d'erreur et journalisation.
- **Nom de machine éliminé (D05)** : tâche `Vigie`, raccourci `Vigie.url`, mutex `VigieTray` /
  `Local\VigieState_*` / `Local\VigieStateRecompute`, types `VigieNative` / `VigieDarkColors`,
  variables `VIGIE_BACKEND` / `VIGIE_TOKEN` / `VIGIE_PORT`, titre openapi `Vigie API`, lanceur
  `demarrer-vigie.vbs`. Archive `docs/maquettes-validees/` volontairement intacte.
- **Validations réellement exécutées** : Parser PowerShell OK sur `tray.ps1`, `common.ps1`,
  `server.ps1`, `start.ps1`, `run.ps1`, `install-autostart.ps1`, `uninstall-autostart.ps1` ;
  front chargé en `file://` — script intégralement exécuté (aucune erreur de syntaxe), 3 liens
  câblés, 7 graduations, aucun débordement horizontal. Node n'est **pas** installé et ne l'est
  pas devenu (**D06**).
- **Script de désinstallation des vestiges (D11)** : `backend/uninstall-legacy.ps1` — daté, jetable,
  idempotent, `-WhatIf`, ne supprime jamais de dossier (l'ancien espace de travail est mis de côté en
  `.old`), chemin en paramètre sans valeur par défaut. Il porte SEUL les anciens noms, pour que
  `uninstall-autostart.ps1` ne connaisse que les noms courants.
  Validé : Parser OK, ASCII pur, refus propre en session non élevée (code 1).
  **Chemin élevé non testé** (session non admin) — le lancer d'abord avec `-WhatIf`.
- **`docs/REPRISE.md` § Contraintes environnement (D12)** réécrit : décrivait une VM Linux éphémère,
  décrit maintenant la machine réelle (outils présents, Node absent et non installé, méthode de
  validation par langage, privilèges, exclusions de commit).
- **CHANGELOG complété (D13)** : il s'arrêtait au 19/08, il couvre maintenant les sessions des
  20, 21 et 22/08.
- **Incohérences de documentation corrigées** (relevées en complétant le CHANGELOG) :
  - **D01 disait « 6 graduations », il y en a 7.** La maquette validée (`for(let i=0;i<=6;i++)`)
    et le générateur déployé (`range(0,7)`) en tracent 7. Le code était juste : c'est la décision
    qui avait repris la borne `/6` au lieu du nombre. **D01 corrigé, code inchangé.**
  - **Graduations : suppression du 21/08 annulée.** `SUIVI.md` gardait la trace d'un retrait
    (« bruit à 16 px ») contredit par D01 et par le code déployé. L'historique est désormais
    explicite dans D01 : la décision la plus récente fait foi.
  - **D07 se lisait comme fait** (« la tâche est repointée ») alors qu'il est en attente.
    D07 porte maintenant un « État : NON FAIT » explicite.
  - **`docs/DISCIPLINES.md` imposait encore `node --check`**, en contradiction directe avec D06.
    Corrigé : validation du JS par chargement `file://` + console.
  - **CHANGELOG, bloc `[non publie]`** : ses trois « à faire » sont livrés, et la fenêtre dédiée
    utilise `--app` (Edge/Chrome), **pas** WebView2 comme annoncé. Corrigé.
- **En attente (D07)** : la tâche planifiée pointe encore sur l'ancien espace de travail
  `LocalWork/hyperion-control-panel` — le repointage exige une session **élevée** (RunLevel Highest).

## 2026-08-22 — Actions non bloquantes, upgrade paquets, résolutions, topbar
- Socle générique `Start-DetachedAction` (worker pwsh détaché, fenêtre cachée) : une action lente répond « en cours » et travaille en tâche de fond sans bloquer le reste.
- Paquets : une carte par gestionnaire ; vérification ET mise à jour (upgrade) en tâche de fond, chaque carte s'actualise seule (état « en cours » + polling par carte). Worker unique `pkg-job.worker.ps1` (check/upgrade), lanceur `Start-PkgJob`.
- Boutons de résolution : prennent le libellé de l'action (plus de « Résoudre » générique) et n'apparaissent que si une action existe. Icône « boîte-flèche » = ouvre un logiciel externe ; icône « fenêtre » = ouvre une popin.
- Résolutions câblées : Latence → mesure (net-speedtest) ; Windows Update « Détectées » → Ouvrir Windows Update (note raccourcie).
- WSL : Statut « Actif/Inactif » coloré (au lieu de Oui/Non) + trio Démarrer/Redémarrer/Arrêter (uniquement les boutons pertinents). Actions `wsl-start`/`wsl-restart` + invalidation de la sonde.
- Topbar : statut intégré (texte + couleur) ; l'ancienne barre de mode devient un simple liseré coloré (3px) qui reflète l'état.
- Divers : `Update-StateJson` sérialisé par mutex inter-processus ; `Remove-ProbeCache` factorisé ; halo de carte « en cours » corrigé (ne déborde plus du radius).
