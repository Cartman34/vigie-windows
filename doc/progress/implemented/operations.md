# CORE-OPERATIONS — l'inventaire des opérations, tel qu'il est

Cible : [../targeting/operations.md](../targeting/operations.md). Arbitrages : **D82**, **D95**. Sujet ouvert :
**S14**.

Relevé du 13/09/2026, fait dans le code. Ce que l'inventaire doit porter et comment il sert : `../targeting/operations.md`,
section « L'inventaire ».

**Tenu par `scripts/dev/check-operations.ps1`**, qui dit lui-même ce qu'il compare et ce qu'il ne voit pas.

## Les fonctions de lancement

Toutes dans `apps/backend-pode/lib/common.ps1`.

| Fonction | Ce qu'elle lance | Protocole |
|---|---|---|
| `Start-WatchedAction` | le veilleur `workers/watched-action.worker.ps1`, qui lance un programme externe et attend sa fin | **le protocole commun** : marque d'occupation, résultat, verrou |
| `Start-DetachedAction` | un worker PowerShell détaché, sans attente ni compte rendu | **hors protocole** |
| `Start-PkgJob` | `workers/pkg-job.worker.ps1`, par `Start-DetachedAction` | **hors protocole** |
| `Start-ServerRelauncher` | un relanceur détaché qui arrête le serveur et le redémarre par sa tâche | **hors protocole** |
| `Start-ChildProcess` | un processus avec ses arguments cités par l'outil (**D116**) | sans objet : lancement court |
| `Invoke-Native` | un exécutable attendu, sortie et code relevés | sans objet : lancement court |

## Les actions

Déclenchées par `POST /actions`, exécutées par `Invoke-ActionById`, qui applique les droits et le verrou de ressources
puis trace l'audit. Fichiers : `apps/backend-pode/actions/<action>.action.ps1`. Les ressources réservées sont déclarées
dans `lib/common.ps1`, table `RessourcesParAction`.

Colonnes : **S'exécute** dit où tourne le code, `serveur` ou `session` du demandeur (`# @execution`). **Durée** suit la
définition de `../targeting/operations.md`, section « Ce qu'est une opération ».

| Action | Proposée par | Droits | S'exécute | Durée | Lancement | Protocole |
|---|---|---|---|---|---|---|
| `accounts-details` | `comptes.probe.ps1`, `scripts/dev/ask-vigie.ps1` | admin | serveur | courte | lecture directe | sans objet |
| `accounts-refresh` | `comptes.probe.ps1` | tous | serveur | courte | lecture directe | sans objet |
| `diag-account-logs` | `scripts/vigie-diag-compte.ps1` | admin | serveur | courte | copie de journaux | sans objet |
| `disk-analyze` | `disk.probe.ps1` | tous | serveur | longue | `Start-DetachedAction`, `workers/disk-scan.worker.ps1` | **hors protocole** |
| `disk-analyze-stop` | `disk.probe.ps1` | tous | serveur | courte | drapeau relu par le worker | sans objet |
| `disk-cleanup` | `disk.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `disk-tree` | `disk.probe.ps1`, `index.html` | tous | serveur | courte | lecture de cache | sans objet |
| `net-dns-flush` | `net.probe.ps1` | admin | serveur | courte | `Invoke-Native` | sans objet |
| `net-publicip` | `net.probe.ps1` | tous | serveur | courte | appel HTTP | sans objet |
| `net-speedtest` | `net.probe.ps1` | tous | serveur | courte | appels HTTP, la réponse attend la mesure | sans objet |
| `open-device-manager` | `gaming.probe.ps1` | tous | session | courte | `Start-ChildProcess` | sans objet |
| `open-folder` | `history.probe.ps1` | tous | session | courte | `Start-ChildProcess` | sans objet |
| `open-gaming-settings` | `gaming.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `open-logs` | `vigie.probe.ps1` | tous | session | courte | `Start-ChildProcess` | sans objet |
| `open-network-settings` | `net.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `open-power-options` | `gaming.probe.ps1`, `power.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `open-scan-folder` | `index.html` | tous | session | courte | `Start-ChildProcess` | sans objet |
| `open-security-settings` | `defender.probe.ps1`, `firewall.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `open-storage-settings` | `disk.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `open-task-manager` | `gaming.probe.ps1`, `perf.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `open-users-settings` | `comptes.probe.ps1` | tous | serveur | courte | aucun : l'interface ouvre elle-même le panneau | sans objet |
| `open-windows-update` | `pending.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `perf-counters-rebuild` | `gaming.probe.ps1` | admin | serveur | courte | `Invoke-Native` | sans objet |
| `pkg-check-updates` | `packages.probe.ps1` | tous | serveur | longue | `Start-PkgJob`, `workers/pkg-job.worker.ps1` | **hors protocole** |
| `pkg-list-updates` | `packages.probe.ps1` | tous | serveur | courte | lecture de cache | sans objet |
| `pkg-open-gui` | `packages.probe.ps1` | tous | session | courte | `Start-Process` | sans objet |
| `pkg-upgrade` | dialogue ouvert par `pkg-list-updates` | admin | serveur | longue | `Start-PkgJob`, `workers/pkg-job.worker.ps1` | **hors protocole** |
| `pwsh-install-machine` | `deployment.probe.ps1` | admin | serveur | longue | `Start-WatchedAction` | commun, avec ses failles |
| `repair-tasks` | `deployment.probe.ps1` | admin | serveur | courte | `Repair-VigieTasks` | sans objet |
| `run-audit` | `lock.probe.ps1` | tous | serveur | courte | `Invoke-UpdateAudit` | sans objet |
| `server-restart` | `vigie.probe.ps1`, `apps/tray/tray.ps1`, `scripts/tray.ps1` | tous | serveur | longue | `Start-ServerRelauncher` | **hors protocole**, cas non arbitré : le serveur qui répond est celui qui s'arrête |
| `system-restart` | `os.probe.ps1`, `vbs.probe.ps1`, `pending.probe.ps1` | tous | serveur | courte | `Invoke-Native` sur `shutdown.exe`, redémarrage différé et annulable | sans objet |
| `system-restart-cancel` | `os.probe.ps1`, `vbs.probe.ps1`, `pending.probe.ps1` | tous | serveur | courte | `Invoke-Native` sur `shutdown.exe` | sans objet |
| `tag-version` | ordre de bureau envoyé par `scripts/install.ps1` | admin | session | courte | `Invoke-Git` | sans objet |
| `toggle-hvci` | `vbs.probe.ps1` | admin | serveur | courte | `Invoke-DeviceGuardToggle` | sans objet |
| `toggle-vbs` | `vbs.probe.ps1` | admin | serveur | courte | `Invoke-DeviceGuardToggle` | sans objet |
| `update-mode-off` | `lock.probe.ps1` | admin | serveur | courte | `Set-UpdateLock`, puis relecture | sans objet |
| `update-mode-on` | `lock.probe.ps1` | admin | serveur | courte | `Set-UpdateLock`, puis relecture | sans objet |
| `vigie-update` | `deployment.probe.ps1`, `scripts/dev/ask-vigie.ps1` | admin | serveur | longue | `Start-WatchedAction` | commun, avec ses failles |
| `wsl-restart` | `wsl.probe.ps1` | tous | serveur | courte | `Start-Job` borné par un délai | sans objet |
| `wsl-shutdown` | `wsl.probe.ps1` | tous | serveur | courte | `Start-Job` borné par un délai | sans objet |
| `wsl-start` | `wsl.probe.ps1` | tous | serveur | courte | `Start-Job` borné par un délai | sans objet |
| `wu-install` | dialogue ouvert par `wu-list-pending` | admin | serveur | longue | `Start-DetachedAction`, `workers/wu-install.worker.ps1` | **hors protocole** |
| `wu-list-pending` | `pending.probe.ps1` | tous | serveur | courte | `Get-PendingUpdateList` | sans objet |
| `wu-scan` | `pending.probe.ps1` | admin | serveur | longue | `Start-DetachedAction`, `workers/wu-scan.worker.ps1` | **hors protocole** |

**Durée** : l'inventaire ne dit pas combien de temps prend une opération courte. Aucune n'a été mesurée.

## Les écritures par l'API

Routes de `apps/backend-pode/server.ps1` qui modifient quelque chose. Toutes courtes.

| Route | Ce qu'elle modifie |
|---|---|
| `POST /session/ticket` | échange le secret d'un compte contre un ticket de session à usage unique |
| `POST /units/:id` | active ou désactive un module |
| `POST /anonymous-access` | le mode d'affichage sans compte, pour tout l'ordinateur ; administrateur élevé |
| `POST /users/:name` | active ou désactive Vigie pour un compte, par `Set-VigieAccountEnabled`, qui écrit sa tâche de démarrage |
| `POST /parameters/:unit` | les réglages d'une unité |
| `POST /notifications` | ce que chaque module notifie |
| `POST /actions` | toutes les actions ci-dessus |

## Les passes internes de l'app serveur

| Opération | Où | Déclenchement | Erreurs |
|---|---|---|---|
| minuteur `vigie-watch` | `server.ps1` | toutes les 60 s, suspendu pendant une installation | journal `state` |
| passe des résidents | `Invoke-ResidentPass`, `Start-Resident` ; résident `probes/gaming/game.resident.ps1` | chaque passe du minuteur | état du résident, relu par `Get-ResidentHealth` |
| passe des sentinelles | `Invoke-WatchPass` ; sentinelles `gaming/game`, `gaming/game-battery`, `network/internet` à 60 s, `system/power` à 30 s | chaque passe du minuteur | journal `state` |
| identité des notifications | `Set-VigieToastIdentity` | chaque passe du minuteur | ignorées |
| recalcul d'une sonde périmée | `Get-State`, puis `Start-DetachedAction` sur `workers/state-refresh.worker.ps1` ; une seule à la fois, par mutex | un affichage qui trouve une sonde périmée | ignorées au lancement, **hors protocole** |
| réparation des tâches au démarrage | `start.ps1`, `Repair-VigieTasks` | démarrage du serveur | journal |
| ordre de bureau | `Invoke-DesktopAction` | une action `@execution: session`, ou `scripts/install.ps1` pour `tag-version` | compte rendu `.done.json`, écrit même en cas d'échec |

## Les passes de l'app cliente

Toutes dans `apps/tray/tray.ps1`.

| Opération | Déclenchement | Ce qu'elle fait |
|---|---|---|
| sondage de l'état | toutes les 8 s | `/health` puis `/state`, et les notifications de bureau qui en sortent |
| exécution des ordres de bureau | toutes les secondes | lance `actions/<type>.action.ps1` dans la session et écrit le compte rendu |
| guetteur d'adresse réseau | toutes les secondes | périme la sonde réseau quand l'adresse change |
| demande de relance du serveur | menu de l'icône | `POST /actions` avec `server-restart` |

## L'installation et les scripts

La séquence d'installation et de mise à jour est décrite dans [update-chain.md](update-chain.md) et
[../targeting/install-update.md](../targeting/install-update.md), la désinstallation dans
[../targeting/uninstall.md](../targeting/uninstall.md). Ce qui suit dit seulement où chaque opération vit.

| Script | Opération |
|---|---|
| `scripts/install.ps1` | installe ou met à jour ; arrête et relance les apps clientes (`Stop-TrayTasks`, `Start-TrayTasks`), active les comptes, fait poser le tag par un ordre de bureau |
| `scripts/uninstall.ps1` | désinstalle ; arrête les apps clientes |
| `scripts/install-autostart.ps1`, `install-autostart.cmd`, `install-autostart.vbs` | enregistre la tâche de démarrage de l'app cliente |
| `scripts/uninstall-autostart.ps1` | retire cette tâche |
| `scripts/uninstall-legacy.ps1` | retire les vestiges d'avant le nom Vigie |
| `scripts/vigie-comptes.ps1` | active ou désactive Vigie pour un compte |
| `scripts/vigie-diag-compte.ps1` | demande `diag-account-logs` au serveur |
| `scripts/vigie-fetch.ps1` | rapporte une archive vérifiée, sans rien déployer |
| `scripts/build-release.ps1` | fabrique l'archive de distribution |
| `scripts/run.ps1`, `run.cmd` | lance le panneau |
| `scripts/tray.ps1`, `start-vigie.vbs` | démarre, arrête ou relance l'app cliente par sa tâche |
| `scripts/install-hooks.ps1` | installe les hooks git du dépôt |
