# État d'implémentation

Légende : **Fait** / **Partiel** / **À faire**. Les ID renvoient à `../targeting/features.md`.
Mise à jour : 2026-08-27.

## Socle

| ID | État | Où | Écarts vs cible |
|----|------|-----|-----------------|
| CORE-CONTRACT | Fait | `apps/backend-pode/api/openapi.yaml` | — |
| CORE-BACKEND | Fait | `apps/backend-pode/server.ps1`, `lib/common.ps1` | Exécution élevée requise pour les actions réelles |
| CORE-FRONTEND | Fait | `apps/frontend-web/index.html`, page unique servie par le serveur | — |
| CORE-PROBES | Fait | 16 sondes auto-découvertes, 41 actions, contrôlées par `scripts/check-probes.ps1` | — |
| CORE-TRAY | Fait | `apps/tray/tray.ps1` — auto-réparant, relance le serveur avec l'application | — |
| CORE-AUTOSTART | Fait | `scripts/install-autostart.ps1` ; tâches `Vigie` / `Vigie - <compte>`, réparation par `repair-tasks` | — |
| CORE-SECURITY | Fait | Écoute 127.0.0.1, jeton porteur injecté dans la page | À auditer avant toute exposition |
| CORE-VERSION | Fait | `Get-GitVersion` / `Get-GitCommit`, empreinte BUILD dans l'archive | — |
| CORE-UPDATE | Fait | Action `vigie-update`, `scripts/vigie-update.ps1` | — |
| CORE-UPDATE-TRUST | À faire | — | Rien ne vérifie aujourd'hui que l'archive téléchargée est bien celle publiée : ni empreinte, ni signature. On s'en remet à HTTPS et à GitHub. |
| CORE-DEPLOY | Fait | Carte Déploiement, `deploy-shared`, `pwsh-install-machine`, `setup.cmd` | Éprouvé sur cette machine seulement |
| CORE-ACCOUNTS | Fait | Carte Comptes, `accounts-details`, `diag-account-logs` | Éprouvé sur le compte Famille |
| CORE-OPERATIONS | Fait | Marqueurs d'occupation, verrou de ressources, `/operations` interrogé par toutes les pages | — |
| CORE-EXPORT | Fait | `apps/frontend-web/rapport.html`, route `/rapport` | Jamais vérifié à l'impression réelle |

## Modules

| ID | État | Où | Écarts vs cible |
|----|------|-----|-----------------|
| WU-LOCK | Fait | `probes/windows-update/lock.probe.ps1` | 12 tâches TrustedInstaller restent prêtes, inoffensives sous `NoAutoUpdate=1` |
| WU-UPDATEMODE | Fait | `update-mode-on` / `update-mode-off` | — |
| WU-PENDING | Fait | `pending.probe.ps1`, `wu-scan`, `wu-list-pending`, `wu-install` | — |
| WU-AUDIT | Fait | `run-audit` | Rapport écrit sur disque, pas remonté dans l'interface |
| SYS-DISK | Fait | `disk.probe.ps1`, `disk-cleanup`, `disk-analyze`, `disk-tree` | — |
| SYS-OS | Fait | `os.probe.ps1` | — |
| SYS-PERF | Fait | `perf.probe.ps1`, `perf-counters-rebuild` | — |
| SYS-POWER | Fait | `power.probe.ps1` | Jamais observé en situation réelle de sous-alimentation |
| NET-STATE | Fait | `net.probe.ps1`, `net-publicip`, `net-speedtest`, `net-dns-flush` | — |
| SEC-VBS | Fait | `vbs.probe.ps1`, `toggle-vbs`, `toggle-hvci` | — |
| SEC-DEFENDER | Fait | `defender.probe.ps1` | — |
| SEC-FIREWALL | Fait | `firewall.probe.ps1` | — |
| WSL-STATE | Fait | `wsl.probe.ps1`, `wsl-start`, `wsl-restart`, `wsl-shutdown` | — |
| TOOLS-PACKAGES | Fait | `packages.probe.ps1`, `pkg-check-updates`, `pkg-list-updates`, `pkg-upgrade` | — |
| GAMING | Fait | `gaming.probe.ps1` | — |

Module `debug` (carte Vigie : version, serveur, journaux, données locales) en plus de la cible : inactif par défaut.

## Interface

| ID | État | Où | Écarts vs cible |
|----|------|-----|-----------------|
| UI-STATUS | Fait | Accent de couleur et icône par carte | — |
| UI-ACTION-TRACK | Fait | Suivi d'action, ligne rouge en cas d'échec, notification | — |
| UI-NOTIF | Fait | Tiroir de notifications, notification verrouillée pendant une opération | — |
| UI-COMPONENTS | Fait | Objet `UI`, un seul cadre arrondi | — |
| UI-LAYOUT | Fait | Colonnes réelles, regroupement par module | — |
| UI-REORG | Fait | Mode réorganisation, dépôt dans une colonne vide | — |
| UI-SETTINGS | Fait | Panneau latéral unique, défauts issus de la configuration | — |

## Ce qui reste ouvert

- Historique des mesures (D53) : décidé, non conçu.
- Actions longues asynchrones au sens du contrat (202 + jobId) : le suivi passe aujourd'hui par les marqueurs
  d'occupation et `/operations`, pas par le contrat.
- Audit Windows Update non remonté dans l'interface.

