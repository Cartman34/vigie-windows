# État d'implémentation

Légende : **Fait** / **Partiel** / **À faire**. Les ID renvoient à `../targeting/features.md`.
Mise à jour : 2026-09-02.

## Socle

| ID | État | Où | Écarts vs cible |
|----|------|-----|-----------------|
| CORE-CONTRACT | Fait | `apps/backend-pode/api/openapi.yaml` | — |
| CORE-BACKEND | Fait | `apps/backend-pode/server.ps1`, `lib/common.ps1` | Exécution élevée requise pour les actions réelles |
| CORE-FRONTEND | Fait | `apps/frontend-web/index.html`, page unique servie par le serveur | — |
| CORE-PROBES | Fait | 17 sondes auto-découvertes, 45 actions, contrôlées par `scripts/check-probes.ps1` | — |
| CORE-TRAY | Fait | `apps/tray/tray.ps1` — auto-réparant ; ne ferme jamais l'app serveur, lui **demande** de se relancer (action `server-restart`) | — |
| CORE-AUTOSTART | Fait | app serveur : tâche `Vigie - Serveur` sous `VigieService`, au **démarrage de l'ordinateur**, sans session ouverte (`scripts/lib/install-service.ps1`). App cliente : `scripts/install-autostart.ps1`, tâches `Vigie` / `Vigie - <compte>`, réparation par `repair-tasks` | — |
| CORE-SECURITY | Fait | [identity.md](identity.md) | À auditer avant toute exposition |
| CORE-VERSION | Fait | `Get-GitVersion` / `Get-GitCommit`, empreinte BUILD dans l'archive | — |
| CORE-UPDATE | Fait | [update-chain.md](update-chain.md) | Éprouvé le 01/09 par le bouton de la carte, de bout en bout, plusieurs fois. Le compte de service lit le dépôt (`safe.directory` sur le dossier **et** son `.git`) et fabrique depuis le clone |
| CORE-UPDATE-TRUST | À faire | — | Rien ne vérifie aujourd'hui que l'archive téléchargée est bien celle publiée : ni empreinte, ni signature. On s'en remet à HTTPS et à GitHub. |
| CORE-DEPLOY | Fait | Carte Déploiement, `pwsh-install-machine`, `setup.cmd` | Éprouvé sur cette machine seulement |
| CORE-ACCOUNTS | Partiel | Carte Comptes, `accounts-details`, `diag-account-logs` | Un compte **standard** ne peut pas démarrer Vigie : le serveur exige l'élévation et lui réclamerait un mot de passe administrateur. Conception validée, non codée : `targeting/multi-account-server.md`. |
| CORE-RESIDENT | Fait | `Get-ResidentDeclarations`, `Start-Resident`, `Invoke-ResidentPass`, `Get-ResidentHealth` dans `common.ps1` ; armés par la boucle d'une minute de l'app serveur | Un seul résident déclaré (`gaming/game`). Éprouvé hors élévation : armement, balayage initial, battement, arrêt, et l'état « abonnement refusé » remonté au lieu d'être tu |
| CORE-WATCH | Fait | Minuteur d'une minute dans l'app serveur, sentinelles déclarées par module ([surveillance.md](../targeting/surveillance.md)) ; historique par sentinelle (`watch.<clé>`, nature `event`) | **Éprouvée en production le 01/09 à 19 h 54** : la sentinelle `gaming/game-battery` a écrit son premier relevé et fait recalculer la carte Jeux, sans session ouverte. Trois sentinelles posées (`network/internet`, `gaming/game-battery`, `system/power`) — les autres modules n'en déclarent pas encore |
| CORE-OPERATIONS | Fait | Marqueurs d'occupation, verrou de ressources, `/operations` interrogé par toutes les pages | — |
| CORE-LAUNCH | Fait | `Start-ChildProcess` / `ConvertTo-ProcessArgument` dans `common.ps1` (**D116**) ; douze lancements y sont revenus, quatorze citations à la main ont disparu, deux lignes de commande écrites en un seul morceau aussi, `check-probes` refuse les trois formes à la main | Éprouvé sur douze valeurs limites — espaces, antislash final, guillemets, chaîne vide — en comparant ce que l’enfant reçoit à ce qu’on lui passe |
| UI-HISTORY | Fait | Le champ porte l’identifiant de sa mesure (`Add-MeasureLinks`, catalogue) ; l’interface trace la forme des 24 h à côté de la valeur, série lue sur `/history` | Quatre séries reliées : espace disque, latence réseau, GPU du jeu, applis gourmandes. Les quatre sentinelles montrent leur frise des changements à côté du champ qu’elles surveillent |
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
| GAMING | Partiel | `gaming.probe.ps1` (lecture seule de la partie), résident `game.resident.ps1`, quatre méthodes d'identification dans `probes/gaming/identify/`, sentinelles `game` et `game-battery` ; cible : [gaming.md](../targeting/gaming.md) | La détection lisait les bibliothèques Steam et la Game Bar dans `HKCU`, donc dans la ruche du compte de service : corrigé le 01/09 (D113), la détection ne mesure plus : elle part du **démarrage des processus** et applique quatre méthodes indépendantes, la première qui répond suffit. Éprouvé le 02/09 : Odyssey reconnu par la Game Bar, Chrome écarté, `explorer` écarté sur son emplacement, verdicts mémorisés. **Non éprouvé** : l'abonnement lui-même, qui exige l'élévation — il sera armé par l'app serveur au prochain déploiement. La carte porte un **mode** (`mode: game` au contrat) et l'interface lui donne un liseré, un fond et une mention « en jeu » |

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
| UI-ACTIONS | Partiel | Boutons permanents par carte (**D114**) : Antivirus, Pare-feu, Ressources, Jeux, Réseau, Stockage mènent aux réglages Windows de leur sujet | Quatre cartes n'ont encore aucune destination permanente : Déploiement, Débogage, Windows Update, WSL |

## Ce qui reste ouvert

- Historique des mesures (D53) : **fait**. Un fichier par mesure et par jour (`var/history/<mesure>/<AAAA-MM-JJ>.jsonl`), purge par suppression de fichiers, et seuls les **retournements** sont conservés — un point compris entre ses deux voisins s'efface à l'écriture. Les sentinelles y écrivent leurs changements d'état. Reste : aucune interface ne montre ces séries.
- Actions longues asynchrones au sens du contrat (202 + jobId) : le suivi passe aujourd'hui par les marqueurs
  d'occupation et `/operations`, pas par le contrat.
- Audit Windows Update non remonté dans l'interface.

