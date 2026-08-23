# Migration vers `apps/` + `scripts/` — état

> **La migration est FUSIONNÉE dans `main` et terminée côté dépôt.**
> Il reste **une seule étape**, sur la machine : réenregistrer la tâche planifiée.
>
> Supprimer ce fichier une fois cette étape faite et vérifiée.

---

## Il reste UNE étape

La tâche planifiée `Vigie` pointe encore sur `…\backend\tray.ps1`, **chemin qui n'existe
plus**. Tant qu'elle n'est pas réenregistrée, l'application **ne démarre plus** à
l'ouverture de session.

Dans un terminal, **sans élévation** — le script s'en charge, après une fenêtre qui
explique ce qu'il va modifier (D22) :

```
pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

La tâche pointera alors sur `apps\tray\tray.ps1`, et l'application sera relancée.

**Vérifier ensuite** :

```
Get-ScheduledTask -TaskName Vigie | ForEach-Object { $_.Actions.Arguments }
Invoke-WebRequest http://127.0.0.1:47600/api/v1/health -UseBasicParsing
```

L'icône doit réapparaître dans la barre système et `/health` répondre `200`.

---

## Ce qui a été fait

### Structure

```
api/                 contrat REST partagé (emplacement encore ouvert, voir plus bas)
apps/
  backend/           serveur Pode, sondes, actions, workers, lib, config
  frontend/          interface web
  tray/              app barre système : tray.ps1 + assets/ (icônes + générateur)
  atelier/           app de développement : serveur php, page, sa config
scripts/             install, désinstall, run, migration
docs/                documentation transverse
logs/                journaux communs à toutes les apps
```

Déplacements en `git mv` : **l'historique des fichiers est préservé**.

### Code

- `apps/backend-pode/lib/common.ps1` : `Get-RepoRoot`, `Get-AppsRoot`, `Get-AppPath`.
  Les chemins inter-apps sont calculés **là et nulle part ailleurs** (D15).
  `Get-LogDir` pointe sur `<racine>/logs`.
- `apps/tray/tray.ps1` : résout `apps/backend-pode` comme app **sœur**, lit ses icônes dans
  `assets/`, journalise dans `<racine>/logs`.
- `scripts/*.ps1` : résolvent `apps/backend-pode` ; `install-autostart.ps1` vise
  `apps/tray/tray.ps1`.
- `apps/atelier/atelier.ps1` : **autonome**, plus aucune dépendance à `common.ps1`.
- `apps/atelier/config.psd1` créé ; `AtelierPort` retiré de la config du backend.
- `.gitignore` mis à jour.

### Fichiers ignorés par git — déjà déplacés

`config.local.psd1`, `.secrets/`, `.state/` → `apps/backend-pode/` ; `logs/` → racine.
L'ancien dossier `backend/` a entièrement disparu.

### Validé

- Parser PowerShell : 43 fichiers, 0 erreur. Lanceurs toujours ASCII pur.
- Les deux `config.psd1` se chargent ; repères d'arborescence vérifiés, cibles existantes.
- Atelier servi depuis la nouvelle structure : 6 ressources en HTTP 200, anciens chemins
  en 404, page à 18 icônes sur 18, aucune cellule morte, aucun débordement.

---

## Tranché depuis

**Le contrat appartient au backend** : `apps/backend-pode/api/openapi.yaml` (**D30**).
**Les apps portent leur techno** : `backend-pode`, `frontend-web` — elles sont des
implémentations remplaçables du contrat. `tray` et `atelier` n'ont pas de suffixe :
ils n'implémentent aucun contrat.

---

## À juger à l'œil, sans lien avec la migration

- **Menu du tray** : coins arrondis désormais par découpe de région (**D26**), jamais vus
  à l'écran.
- **Écran de chargement** : jamais vu non plus. Visible dans l'Atelier
  (`apps\atelier\atelier.cmd`).
