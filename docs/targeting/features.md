# Fonctionnalites cibles (specifications)

Format : `ID` — Titre. Besoin / criteres. NE PAS documenter ici l'etat
d'avancement (voir `../implemented/status.md`).

## Socle (CORE)

- **CORE-CONTRACT** — Contrat REST source de verite.
  API versionnee, standard (verbes/codes HTTP, JSON), decrite en OpenAPI.
  Le front ne depend que du contrat ; le back est interchangeable.
- **CORE-BACKEND** — Back implementant le contrat, capable de piloter Windows.
  Sert `/state`, `/actions`. Techno libre (Pode par defaut).
- **CORE-FRONTEND** — Dashboard web statique, generique.
  Rendu par thème/module a partir du seul JSON `/state`. Clair/sombre.
- **CORE-PROBES** — Modele generique de sondes et actions, auto-decouvert,
  regroupe par thème. Ajouter une sonde = deposer un dossier, sans toucher
  contrat ni front.
- **CORE-TRAY** — Icone barre systeme refletant l'etat global (vert/ambre/rouge),
  menu d'acces rapide.
- **CORE-WINDOW** — Fenetre applicative (WebView2) affichant le dashboard.
- **CORE-AUTOSTART** — Lancement a l'ouverture de session, privileges eleves,
  via tache planifiee idempotente (pas de UAC a chaque action).
- **CORE-SECURITY** — Ecoute 127.0.0.1 uniquement + jeton Bearer local.

## Windows Update (WU)

- **WU-LOCK** — Surveiller et garantir le verrouillage des MAJ automatiques.
  Etat : NoAutoUpdate, verrou ACL des dossiers de taches, taches desactivees vs
  actives, WaaSMedic neutralise, redemarrage en attente. Aucun redemarrage/
  installation sans consentement.
- **WU-UPDATEMODE** — Basculer entre « verrouille » et « mode mise a jour ».
  Deverrouille pour installer a la demande, puis re-verrouille. L'utilisateur
  choisit toujours le moment du redemarrage.
- **WU-AUDIT** — Produire un audit complet de la machinerie Windows Update
  (strategies, taches, services, reboot en attente).

## Systeme (SYS)

- **SYS-DISK** — Surveiller l'espace du disque C: avec seuil d'alerte (60 Go).
  Action de nettoyage.

## WSL

- **WSL-STATE** — Surveiller l'etat WSL2 (RAM/swap configures, sante du boot de
  la distro). Actions : diagnostic de boot, arret de WSL.

## Securite (SEC)

- **SEC-VBS** — Surveiller VBS et l'integrite memoire (HVCI) ; basculer chacun
  (impact sur les perfs de virtualisation).

## Interface (UI)
- **UI-STATUS** - Lisibilite des statuts : accent de couleur par carte + icone
  (vert/coche = conforme, ambre = a surveiller, rouge = probleme).
- **UI-ACTION-TRACK** - Suivi des actions : chaque action lancee affiche son etat
  (en cours -> reussi/echec) avec message et horodatage. Cible ulterieure :
  actions longues asynchrones (202 + jobId, polling de GET /actions/{jobId}).
