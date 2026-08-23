# Migration vers `apps/` + `scripts/` — reprise

> **État : EN COURS, non fusionnée.** Tout vit sur la branche
> `claude/vigie-project-resume-d27ddf`. `main` est **intact et fonctionnel**.
>
> ⛔ **Ne pas fusionner dans `main` avant d'avoir fini** — la tâche planifiée `Vigie`
> pointe sur `…\backend\tray.ps1`, chemin qui n'existe plus dans la nouvelle structure.
> Fusionner en l'état casserait l'application à la prochaine ouverture de session.

Interrompue volontairement (pause demandée), à un point cohérent : rien n'est à moitié
déplacé, il reste des références textuelles à corriger et la validation à faire.

---

## Pourquoi cette migration

Décision de l'utilisateur : l'Atelier n'est pas un « outil » rangé dans `docs/`, c'est
**une app du projet**, même si elle ne sert qu'au développement. Structure retenue :

```
api/                    contrat REST (emplacement À TRANCHER, voir « Question ouverte »)
apps/
  backend/              serveur Pode, sondes, actions, workers, lib, config
  frontend/             interface web
  tray/                 app barre système : tray.ps1 + assets/ (icônes + générateur)
  atelier/              app de développement : serveur php, page, SA config
scripts/                install, désinstall, run, migration
docs/                   documentation transverse
logs/                   journaux communs à toutes les apps
```

Le tray devient une app à part entière (**Q1B** validé) : interface WinForms, icônes et
cycle de vie propres. Il **pilote** le backend sans en faire partie.

---

## FAIT

### Déplacements (`git mv`, historique préservé)
- `backend/` → `apps/backend/`, `frontend/` → `apps/frontend/`
- `backend/tray.ps1` → `apps/tray/tray.ps1`
- `backend/assets/tray/` → `apps/tray/assets/` (les 3 `.ico` + `generer-icones.py`)
- `docs/atelier.ps1|.cmd|.md`, `docs/atelier-validation.html` → `apps/atelier/`
  (la page devient `index.html`, la doc devient `README.md`)
- 9 scripts de gestion `backend/*` → `scripts/` :
  `install.ps1`, `install-autostart.ps1|.cmd|.vbs`, `uninstall-autostart.ps1`,
  `uninstall-legacy.ps1`, `run.ps1|.cmd`, `demarrer-vigie.vbs`

### Code adapté
- **`apps/backend/lib/common.ps1`** : ajout de `Get-RepoRoot`, `Get-AppsRoot`,
  `Get-AppPath` — les chemins inter-apps sont calculés **là et nulle part ailleurs**
  (D15). `Get-LogDir` pointe désormais sur `<racine>/logs`.
- **`apps/tray/tray.ps1`** : `$backend` résolu comme app **sœur** ; `$trayRoot` passé au
  runspace ; icônes lues dans `assets/` ; journal dans `<racine>/logs`.
- **`scripts/*.ps1`** (5 fichiers) : `$backend` résolu vers `apps/backend` ;
  `install-autostart.ps1` pointe la tâche sur `apps/tray/tray.ps1`.
- **`apps/atelier/atelier.ps1`** : réécrit, **autonome** — plus aucune dépendance à
  `common.ps1` (test de port inclus), lit **sa** config.
- **`apps/atelier/config.psd1`** : créé (`BindAddress`, `Port`, `StartPage`).
- **`apps/backend/config.psd1`** : `AtelierPort` **retiré** — le port de l'Atelier
  appartient à l'Atelier. D15 reste respecté : une valeur, une définition ; chaque app
  est maîtresse des siennes.
- **`apps/atelier/index.html`** : chemins d'icônes → `../tray/assets/`.
- **`.gitignore`** : `apps/backend/.secrets|.state|config.local.psd1`, et `logs/`.

### Vérifié
- `apps/backend/server.ps1` et `Get-AppVersion` trouvent toujours le front sans
  modification : ils calculent « dossier parent + `frontend` », et `backend`/`frontend`
  sont restés **voisins** sous `apps/`.
- Les lanceurs `.cmd`/`.vbs` utilisent `%~dp0` : ils trouvent leurs voisins dans
  `scripts/`, rien à changer.

---

## RESTE À FAIRE, dans l'ordre

1. **Références textuelles périmées** (aucun impact fonctionnel, mais la doc ment) :
   - `apps/atelier/README.md` — URL `docs/atelier-validation.html` → `apps/atelier/index.html` ;
     section Configuration → `apps/atelier/config.psd1` au lieu de `backend/config.psd1` ;
     liens `../backend/tray.ps1` → `../tray/tray.ps1`.
   - `apps/atelier/index.html` — quelques mentions textuelles de `backend/assets/tray/`.
   - `apps/frontend/index.html` — commentaire ligne ~270.
   - `docs/DECISIONS-VALIDEES.md` — D02, D19, D23, D24, D28 citent les anciens chemins.
   - `docs/REPRISE.md`, `README.md`, `PRISE-EN-MAIN.md`, `SUIVI.md`, `docs/conventions.md`,
     `docs/technologies.md`, `apps/backend/README.md`.
2. **Consigner la décision** dans `docs/DECISIONS-VALIDEES.md` (D29) : structure `apps/` +
   `scripts/`, tray promu app, config par app, journaux communs.
3. **Validation complète** :
   - Parser PowerShell sur tous les `.ps1`/`.psd1`.
   - `Import-PowerShellDataFile` sur les deux `config.psd1`.
   - Lanceurs `.cmd`/`.vbs` toujours **ASCII pur**.
   - Démarrer l'Atelier (`apps/atelier/atelier.ps1 -Background -NoBrowser`) et vérifier
     en HTTP 200 : `/apps/atelier/index.html`, `/apps/tray/assets/ok.ico`,
     `/apps/frontend/index.html`.
   - Dans la page servie : 18 icônes chargées, aucune cellule morte.
4. **Fusion dans `main`.**
5. **Fichiers ignorés à déplacer À LA MAIN dans le dépôt principal** (git ne les suit pas) :
   ```
   backend\config.local.psd1  ->  apps\backend\config.local.psd1
   backend\.secrets\          ->  apps\backend\.secrets\
   backend\.state\            ->  apps\backend\.state\
   backend\logs\              ->  logs\
   ```
   Sans `.secrets`, un nouveau jeton est généré : sans gravité (le serveur l'injecte dans
   la page), mais les onglets ouverts devront être rechargés.
6. **Réenregistrer la tâche planifiée** — la seule étape qui demande l'élévation :
   ```
   pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
   ```
   Elle pointera sur `apps\tray\tray.ps1`. La fenêtre de consentement (D22) s'affiche
   d'abord. Vérifier ensuite : icône présente, `/api/v1/health` en 200.
7. **Supprimer ce fichier** une fois la migration terminée.

---

## Question ouverte

**Où ranger `api/openapi.yaml` ?** Non tranché, laissé **à la racine** en attendant.

- *Pour la racine* : le principe directeur n°1 dit que le front ne connaît que le
  contrat et que le back n'en est qu'une implémentation remplaçable. À la racine, le
  fichier se lit comme la **norme** à laquelle les backends se conforment.
- *Pour `apps/backend/api/`* (position de l'utilisateur) : le fichier décrit ce qu'un
  backend implémente. Le placer ailleurs n'empêche techniquement rien — l'argument de
  « dépendance » avancé au départ était **exagéré** et a été retiré.

C'est un choix de signal, pas de contrainte. Un `git mv` et trois liens suffisent à
basculer.

---

## Sujets en attente, sans lien avec la migration

- **Menu du tray** : style validé tel quel par l'utilisateur ; les coins arrondis passent
  désormais par une découpe de région (**D26**) et n'ont **pas encore été vus à l'écran**.
- **Écran de chargement** : jamais vu à l'écran non plus. À juger via l'Atelier.
