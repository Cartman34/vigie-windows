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
- **CORE-TRAY** — Icône de barre système reflétant l'état global, menu d'accès rapide, capable de relancer l'application
  ET son serveur.
- **CORE-AUTOSTART** — Lancement à l'ouverture de session avec privilèges élevés, par tâche planifiée idempotente, sans
  UAC à chaque action. La tâche se répare seule quand elle est cassée.
- **CORE-SECURITY** — Écoute sur 127.0.0.1 uniquement, jeton porteur local. **Aucune donnée n'est envoyée sur Internet.**
- **CORE-VERSION** — Un seul numéro de version, dérivé des étiquettes git, visible dans l'application avec son commit.
- **CORE-UPDATE** — Vigie se met à jour elle-même depuis le dépôt, sans réinstallation manuelle.
- **CORE-DEPLOY** — Installation partagée pour tous les comptes de la machine, jamais par compte. Les dépendances
  (PowerShell 7) en font partie. Un installateur aboutit, ou dit pourquoi il a échoué.
- **CORE-ACCOUNTS** — Plusieurs comptes Windows utilisent Vigie : chacun ses réglages, aucun pouvoir supplémentaire ;
  diagnostiquer un autre compte passe par Vigie, jamais par un contournement.
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

- **GAMING** — Ce qui compte pour jouer : GPU et sa mémoire réellement utilisée par application, mode jeu, pilotes.

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
