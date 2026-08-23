# Etat d'implementation

Legende : DONE (fait) / PARTIAL (partiel) / TODO (a faire).
Reference les IDs de `../targeting/features.md`. Maj : 2026-08-19.

| ID              | Etat    | Ou / Comment | Ecarts vs cible |
|-----------------|---------|--------------|-----------------|
| CORE-CONTRACT   | DONE    | `api/openapi.yaml` v1.0.0 | — |
| CORE-BACKEND    | DONE*   | `apps/backend/start.ps1` + `apps/backend/server.ps1` (Pode) ; routes `/health`, `/state`, `/modules/{id}`, `/actions` ; `apps/backend/lib/common.ps1` | *Necessite `Install-Module Pode` ; actions reelles necessitent une execution ELEVEE |
| CORE-FRONTEND   | DONE    | `apps/frontend/index.html` v2 : consomme le contrat, mode API en direct + repli `apps/frontend/mock/state.json` / mock inline | Themes system/wsl/security pas encore alimentes |
| CORE-PROBES     | DONE    | Modele auto-decouvert (`apps/backend/lib/common.ps1` -> `Get-State`) ; sondes `apps/backend/probes/windows-update/lock.probe.ps1`, `history.probe.ps1` | Sondes des autres themes a ecrire |
| CORE-SECURITY   | DONE    | Ecoute 127.0.0.1 ; jeton Bearer (`apps/backend/.secrets/api.token`) ; injecte dans la page servie | Middleware simple ; a auditer avant exposition eventuelle |
| CORE-TRAY       | TODO    | — | Icone barre systeme a faire |
| CORE-WINDOW     | TODO    | — | Fenetre WebView2 a faire |
| CORE-AUTOSTART  | PARTIAL | — | Tache planifiee d'ouverture de session (elevee) a faire |
| WU-LOCK         | DONE    | Sonde `wu-lock` (etat) + scripts `LocalAgentAdmin/tools/lockdown-updates*.ps1` | 12 taches TrustedInstaller restent Ready (inoffensives sous NoAutoUpdate=1) |
| WU-UPDATEMODE   | DONE    | Actions `update-mode-on/off` -> `LocalAgentAdmin/tools/update-mode.ps1` | — |
| WU-AUDIT        | DONE    | Action `run-audit` -> `LocalAgentAdmin/tools/audit-update-tasks.ps1` | Rapport ecrit cote LocalAgentAdmin (pas encore remonte dans l'UI) |
| SYS-DISK        | DONE    | Script `LocalAgentAdmin/tools/disk-guard.ps1` | Sonde `system` + action nettoyage a ecrire |
| WSL-STATE       | DONE    | Scripts WSL dans `LocalAgentAdmin/` | Sonde `wsl` + actions a ecrire |
| SEC-VBS         | DONE    | `LocalAgentAdmin/toggle-vbs.ps1`, `toggle-memory-integrity.ps1` | Sonde `security` + actions a ecrire |

| UI-STATUS       | DONE    | `apps/frontend/index.html` : accent couleur carte + icone de statut | - |
| UI-ACTION-TRACK | PARTIAL | `apps/frontend/index.html` : panneau de suivi (en cours/reussi/echec + message) | Actions encore SYNCHRONES cote back ; async (jobId/polling) a faire |

## Prochaines etapes
Voir `../../SUIVI.md` (prochaine action immediate).

## Maj 2026-08-19 (j)
- Sondes ajoutees : `system/disk.probe.ps1`, `wsl/wsl.probe.ps1`,
  `security/vbs.probe.ps1` (+ actions disk-cleanup, wsl-shutdown, toggle-vbs,
  toggle-hvci). Le dashboard affiche desormais 4 themes.
- Aide par parametre : `Field.help` (contrat) + infobulle front.
- CORE-AUTOSTART : `install-autostart.ps1` (tache au logon + raccourci bureau) et
  `uninstall-autostart.ps1`. RESTE : icone barre systeme (CORE-TRAY) et fenetre
  WebView2 (CORE-WINDOW).
