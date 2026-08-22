# SUIVI - HYPERION Control Panel

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
- GENERIQUE : le titre affiche le NOM DE MACHINE calcule ($env:COMPUTERNAME, via /state.host) au lieu de "HYPERION" en dur.

### TODO genericite (a finir)
- [ ] Chemins encore specifiques a cette machine : `config.psd1` ToolsPath absolu (LocalAgentAdmin/tools) -> rendre calcule/relatif.
      Verifier tout chemin/nom code en dur pour un deploiement sur un autre PC.
- [ ] Menu tray : style precis a valider (coins/espacement/survol) — en attente des details utilisateur.
- [ ] Stale-while-revalidate complet (cartes-squelette pour sondes pas encore pretes).


### Session 21/08 (matin)
- **408 sur /state (effet troupeau)** corrige : `Get-State` en SINGLE-FLIGHT (un seul recalcul a la fois, verrou
  `Local\HcpStateRecompute`, gestion du mutex abandonne), les autres requetes servent le cache immediatement,
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
      Autostart au logon (tache 'HyperionControlPanel', Highest) via `install-autostart.cmd`.
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

## 2026-08-22 — Actions non bloquantes, upgrade paquets, résolutions, topbar
- Socle générique `Start-DetachedAction` (worker pwsh détaché, fenêtre cachée) : une action lente répond « en cours » et travaille en tâche de fond sans bloquer le reste.
- Paquets : une carte par gestionnaire ; vérification ET mise à jour (upgrade) en tâche de fond, chaque carte s'actualise seule (état « en cours » + polling par carte). Worker unique `pkg-job.worker.ps1` (check/upgrade), lanceur `Start-PkgJob`.
- Boutons de résolution : prennent le libellé de l'action (plus de « Résoudre » générique) et n'apparaissent que si une action existe. Icône « boîte-flèche » = ouvre un logiciel externe ; icône « fenêtre » = ouvre une popin.
- Résolutions câblées : Latence → mesure (net-speedtest) ; Windows Update « Détectées » → Ouvrir Windows Update (note raccourcie).
- WSL : Statut « Actif/Inactif » coloré (au lieu de Oui/Non) + trio Démarrer/Redémarrer/Arrêter (uniquement les boutons pertinents). Actions `wsl-start`/`wsl-restart` + invalidation de la sonde.
- Topbar : statut intégré (texte + couleur) ; l'ancienne barre de mode devient un simple liseré coloré (3px) qui reflète l'état.
- Divers : `Update-StateJson` sérialisé par mutex inter-processus ; `Remove-ProbeCache` factorisé ; halo de carte « en cours » corrigé (ne déborde plus du radius).
