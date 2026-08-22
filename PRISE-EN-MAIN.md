# PRISE-EN-MAIN — HYPERION Control Panel

> Fichier d'initialisation du projet, a **nom volontairement non-standard** pour
> ne pas etre charge automatiquement par les agents. Tout agent qui reprend le
> projet DOIT lire ce fichier en entier, puis suivre les liens ci-dessous.

## But
Panneau de controle **local** (web + moteur natif Windows) pour surveiller et
piloter l'etat de la machine `HYPERION` (Windows Update, disque, WSL, securite),
lance avec la session, avec icone barre systeme. Voir `README.md`.

## A lire, dans l'ordre
1. `README.md` — vue d'ensemble + arborescence.
2. `docs/conventions.md` — **toutes** les conventions.
3. `docs/technologies.md` — **toutes** les technos et leurs raisons.
4. `api/openapi.yaml` — **le contrat REST (source de verite)**.
5. `docs/targeting/features.md` — ce que le produit DOIT faire (IDs).
6. `docs/implemented/status.md` — ce qui est REELLEMENT fait.
7. `SUIVI.md` — **fichier de suivi** : etat courant + prochaine action + journal.

## Architecture (resume)
- Contract-first : front <-> back uniquement via `api/openapi.yaml`.
- Front statique (HTML/JS). Back = Pode (PowerShell), interchangeable.
- Generique a plugins : etat = modules par theme ; ajouter une **sonde**
  (`backend/probes/<theme>/*.probe.ps1`) ou une **action**
  (`backend/actions/<id>.action.ps1`) sans toucher contrat ni front.
- Securite : API 127.0.0.1 + jeton Bearer.

## Lancer / tester maintenant
    # Prerequis (une fois) :
    Install-Module Pode -Scope CurrentUser
    # Demarrer :
    powershell -ExecutionPolicy Bypass -File backend\start.ps1
    # Puis ouvrir http://127.0.0.1:47600/  (UI) — l'API est sous /api/v1
Sans lancer le back, ouvrir `frontend/index.html` affiche le mode maquette.

## Lien avec LocalAgentAdmin
La logique Windows Update (verrouillage, mode MAJ, audit) vit dans
`../../LocalAgentAdmin/tools/` ; les actions du panneau **l'appellent**.
Historique/lecons : `LocalAgentAdmin/AGENTS.md`.

## Regle de fin de session (obligatoire)
Avant de t'arreter, mets a jour : `SUIVI.md` (journal + prochaine action),
`docs/implemented/status.md` (matrice), `CHANGELOG.md`, et toute doc de
convention/techno/fonctionnalite impactee. **Tout doit rester documente.**

## Installation & lancement (scripts dedies)
    powershell -ExecutionPolicy Bypass -File backend\install.ps1   # prerequis (une fois)
    powershell -ExecutionPolicy Bypass -File backend\run.ps1        # lance + ouvre l'UI
    powershell -ExecutionPolicy Bypass -File backend\run.ps1 -Admin # eleve (actions actives)
