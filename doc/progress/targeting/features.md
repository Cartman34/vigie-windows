# Fonctionnalités cibles (spécifications)

Format : `ID` — Titre, puis le besoin et ses critères. On n'écrit **pas** ici l'état d'avancement : il vit dans
`../implemented/status.md`, qui référence ces mêmes ID.

## Socle (CORE)

- **CORE-CONTRACT** — Contrat REST source de vérité. API versionnée et standard (verbes et codes HTTP, JSON), décrite en
  OpenAPI. Le front ne dépend que du contrat ; le back reste interchangeable.
- **CORE-BACKEND** — Back implémentant le contrat et capable de piloter Windows. Sert l'état et les actions.
- **CORE-FRONTEND** — Dashboard web statique et générique, rendu à partir du seul JSON d'état. Clair et sombre.
- **CORE-PROBES** — Modèle générique de sondes et d'actions, auto-découvert, regroupé par module. Ajouter une sonde =
  déposer un fichier, sans toucher ni au contrat ni au front.
- **CORE-TRAY** — Icône de barre système reflétant l'état global, menu d'accès rapide. Elle ne ferme **jamais** l'app
  serveur : une relance se **demande** au serveur, qui se relance lui-même avec ses propres droits — sans UAC, depuis
  n'importe quel compte. Si le serveur ne répond plus, alors seulement elle propose de le relancer, en demandant
  l'élévation.
- **CORE-AUTOSTART** — Deux démarrages, par tâches planifiées idempotentes et sans UAC à chaque action. L'**app
  serveur** démarre avec l'ordinateur, sous un compte dédié, **avant** et **sans** qu'aucune session soit ouverte.
  L'**app cliente** démarre à l'ouverture de session de chaque compte autorisé. Les tâches se réparent seules quand
  elles sont cassées, et lancent toujours l'installation partagée — jamais un dépôt de travail, qu'un autre compte ne
  pourrait pas lire.
- **CORE-SECURITY** — Écoute sur 127.0.0.1 uniquement, jeton porteur local. **Aucune donnée n'est envoyée sur Internet.**
- **CORE-VERSION** — Un seul numéro de version, dérivé des étiquettes git, visible dans l'application avec son commit.
- **CORE-UPDATE** — Vigie se met à jour elle-même, sans réinstallation manuelle. Séquence détaillée : [install-update.md](install-update.md). **La source est déclarée**, pas
  devinée : une branche du dépôt de l'ordinateur en développement, une version publiée en production. La carte se
  compare à cette même source — elle répond donc à « ce bouton changerait-il quelque chose ? » — et l'écart se lit dans
  le numéro de version (`v0.1.27+3`). À la fin d'une mise à jour, **les deux applications** repartent sur le nouveau
  code : les app clientes sur ordre, l'app serveur en se relançant elle-même.
- **CORE-WATCH** — Vigie surveille **en permanence**, y compris quand aucune session n'est ouverte : l'app serveur
  tourne déjà sous son compte de service, c'est de là qu'on observe. Une sonde à la fois, la plus urgente d'abord,
  l'urgence étant **déclarée par le module** et non devinée. Sans cela, une notification ne peut pas exister — rien
  n'est mesuré tant que personne ne regarde. Détail : [surveillance.md](surveillance.md).
- **CORE-RESIDENT** — Certaines choses doivent **rester en vie** aux côtés de l'app serveur : un abonnement, un
  écouteur, un consommateur. Un module en déclare une, le serveur l'arme à son démarrage, l'arrête avec lui, la réarme
  si elle meurt, et son état se voit. Ce qu'elle fait ne regarde qu'elle. Détail : [residents.md](residents.md).
- **CORE-DEPLOY** — Installation partagée pour tous les comptes de la machine, jamais par compte. Les dépendances
  (PowerShell 7) en font partie. Un installateur aboutit, ou dit pourquoi il a échoué.
- **CORE-UPDATE-TRUST** — La chaîne de mise à jour ne doit pas pouvoir être détournée. Ce qui s'installe doit être
  **vérifiable** — empreinte publiée, et à terme signature — et pas seulement « téléchargé en HTTPS depuis la bonne
  URL ». Une intrusion dans le dépôt, un jeton de publication volé ou une release remplacée ne doivent pas suffire à
  faire installer du code sur les machines : c'est par là que des projets bien plus gros se sont fait avoir. Vont avec :
  protection de la branche et des tags, second facteur sur le compte qui publie, et de quoi **revenir en arrière** quand
  une version se révèle mauvaise.
- **CORE-ACCOUNTS** — Plusieurs comptes Windows utilisent Vigie : chacun ses réglages, aucun pouvoir supplémentaire ;
  diagnostiquer un autre compte passe par Vigie, jamais par un contournement. Un compte **standard** doit pouvoir
  lancer les opérations qu'on lui ouvre, même lorsqu'elles exigent techniquement l'élévation — sans jamais voir
  d'identifiants d'administrateur. Conception : **[Un serveur élevé par machine](multi-account-server.md)**.
- **CORE-OPERATIONS** — Une opération longue se voit tant qu'elle dure, verrouille les ressources qu'elle occupe, et
  reste visible depuis toutes les pages ouvertes.
- **CORE-EXPORT** — Deux exports imprimables et sobres : les caractéristiques matérielles, et l'état courant.

## Windows Update (WU)

- **WU-LOCK** — Surveiller et garantir le verrouillage des mises à jour automatiques : `NoAutoUpdate`, verrou ACL des
  dossiers de tâches, tâches désactivées, WaaSMedic neutralisé, redémarrage en attente. Aucune installation ni
  redémarrage sans consentement.
- **WU-UPDATEMODE** — Basculer entre « verrouillé » et « mode mise à jour » : déverrouiller pour installer à la demande,
  puis re-verrouiller. L'utilisateur choisit toujours le moment du redémarrage.
- **WU-PENDING** — Lister les mises à jour en attente, les rechercher et les installer au choix.
- **WU-AUDIT** — Produire un audit complet de la machinerie Windows Update : stratégies, tâches, services, redémarrage
  en attente.

## Système (SYS)

- **SYS-DISK** — Surveiller l'espace du disque système avec seuil d'alerte. Nettoyage et analyse de l'occupation en
  actions, l'arborescence se demandant un niveau à la fois.
- **SYS-OS** — Identité de la machine : version de Windows, édition, build, durée depuis le démarrage.
- **SYS-PERF** — Charge courante : processeur, mémoire, avec de vrais noms de processus.
- **SYS-POWER** — Alimentation : batterie, secteur, et alerte quand un portable est sur secteur mais **sous-alimenté**.

## Réseau (NET)

- **NET-STATE** — Connexion, nom du réseau, qualité et stabilité du lien Wi-Fi, adresses IP, VPN. L'IP publique et le
  test de débit sont des actions explicites, jamais automatiques.

## Sécurité (SEC)

- **SEC-VBS** — Surveiller VBS et l'intégrité mémoire (HVCI), basculer chacun — l'impact sur la virtualisation est
  annoncé.
- **SEC-DEFENDER** — État de Microsoft Defender : protection en temps réel, signatures, dernière analyse.
- **SEC-FIREWALL** — État du pare-feu par profil.

## WSL

- **WSL-STATE** — État de WSL2 : mémoire et swap configurés, santé du démarrage de la distribution. Actions : démarrer,
  redémarrer, arrêter.

## Outils (TOOLS)

- **TOOLS-PACKAGES** — Paquets installés via le gestionnaire de paquets, mises à jour disponibles, mise à jour à la
  demande. Une mise à jour déjà faite ne se propose pas.

## Gaming (GAMING)

- **GAMING** — Ce qui compte pour jouer, **pendant** qu'on joue : pourquoi ça rame, ce qui va gêner la partie, et ce
  qui mérite une alerte sans qu'on regarde la carte. Le détail — ce qu'elle doit dire, ce qu'elle ne doit pas faire,
  et comment la partie doit être détectée — vit dans [gaming.md](gaming.md).

## Interface (UI)

- **UI-STATUS** — Lisibilité des statuts : accent de couleur par carte et icône. Aucun état ne masque une carte, et une
  carte déjà affichée ne disparaît jamais.
- **UI-ACTION-TRACK** — Suivi des actions : état, message et horodatage. Une résolution est toujours un bouton.
- **UI-NOTIF** — Une notification est un événement nommé, pas une carte. Celle d'une opération en cours est verrouillée :
  impossible à effacer tant que l'opération dure.
- **UI-COMPONENTS** — Composants réutilisables plutôt que des copies : un seul cadre arrondi, DRY et SOLID.
- **UI-LAYOUT** — Colonnes stables, cartes d'un même module placées à la suite ou à proximité.
- **UI-REORG** — Un mode réorganisation explicite où l'utilisateur ordonne ses cartes, y compris vers une colonne vide.
- **UI-SETTINGS** — Un menu Paramètres unique ; le défaut vient de la configuration.

## Abandonné

- **CORE-WINDOW** — Fenêtre applicative WebView2 affichant le dashboard. Abandonné : la page est servie par le serveur
  et s'ouvre dans le navigateur (D47), le tray assure l'accès rapide. Conservé ici pour que l'ID ne soit pas réattribué.
