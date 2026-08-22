# Backend

Implementation du contrat `api/openapi.yaml`. Techno actuelle : **Pode**
(framework web en PowerShell) — choisie parce qu'elle sert le front ET pilote
Windows en natif (registre, taches, ACL, services) sans couche intermediaire.
Interchangeable : tout back respectant le contrat convient.

## Modele de sondes et d'actions (plugin)

Le back est un **socle generique**. Il ne code pas les modules en dur : il
**decouvre** des sondes.

### Sonde (probe) — lecture d'etat
- Emplacement : `backend/probes/<theme>/<nom>.probe.ps1`
- Contrat : le script ecrit sur la sortie standard **un objet JSON conforme au
  schema `Module`** de l'OpenAPI (id, theme, label, status, fields[], actions[]).
- Le back agrege toutes les sondes d'un theme dans `GET /state`.
- Doit etre **rapide et sans effet de bord** (lecture seule). Appels lents
  (ex. `wsl`) bornes par un delai.

### Action — effet de bord
- Emplacement : `backend/actions/<id>.action.ps1`
- Declaree par une sonde dans `actions[]` (id + label).
- Invoquee par `POST /actions {type:<id>, module, params}`.
- Retourne un objet `Job` (jobId, status, message, result). Action longue =
  repondre 202 puis suivre via `GET /actions/{jobId}`.
- Reutilise l'outillage existant quand il existe (voir ci-dessous).

## Reutilisation de l'existant

Le verrouillage Windows Update est deja implemente dans
`LocalAgentAdmin/tools/` (`lockdown-updates.ps1`, `update-mode.ps1`,
`audit-update-tasks.ps1`). Les sondes/actions `windows-update` **appellent ces
scripts** plutot que de reimplementer la logique. A terme, envisager de
centraliser ces scripts dans ce projet.

## Securite (obligatoire)

- Ecoute **127.0.0.1 uniquement**.
- **Jeton Bearer** genere au premier lancement, stocke en local, exige sur tous
  les endpoints sauf `/health`.
- Le back tourne eleve (via la tache planifiee de demarrage) : ne jamais exposer
  hors de la machine.

## Conventions de code (heritees de LocalAgentAdmin/AGENTS.md)

- Code et noms en anglais ; commentaires en francais.
- Verifier les prerequis en amont (droits, presence des commandes/modules).
- Scripts de tache planifiee **idempotents** (`Register-ScheduledTask -Force`).

## Precision sonde vs action (mise a jour)
- Les **sondes** font une **lecture directe** de l'etat (registre, taches...),
  rapide et sans effet de bord — elles n'appellent PAS les scripts lourds.
- Les **actions** (ex. `run-audit`, `update-mode-on/off`) appellent l'outillage
  `LocalAgentAdmin/tools/`.
