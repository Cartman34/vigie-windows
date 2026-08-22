# Guide d'exploitation (admin systeme)

> Public : celui qui installe, met a jour et depanne le panneau sur la machine.

## Prerequis

- Windows 10/11 Pro, PowerShell 5.1+ (ou 7).
- Module **Pode** : `Install-Module Pode -Scope CurrentUser` (sans admin).
- Runtime **WebView2** (present par defaut sur Win10/11 recents ; sinon
  installer « Evergreen WebView2 Runtime »).

## Installation (cible)

1. Deposer le projet sur la machine.
2. Generer le jeton d'API local (au 1er lancement du back).
3. Enregistrer la **tache planifiee** « a l'ouverture de session », privileges
   eleves, qui lance le back Pode (cache) + l'UI (tray/fenetre). Script
   d'enregistrement **idempotent**.

> Procedure detaillee a completer quand `CORE-AUTOSTART` sera implemente
> (voir `implemented/status.md`).

## Exploitation

- **Port / URL** : `http://127.0.0.1:47600/api/v1` (ecoute locale uniquement).
- **Jeton** : stocke localement ; requis sur tous les endpoints sauf `/health`.
- **Logs** : (a definir) — repertoire de logs du back.

## Depannage

- Le panneau ne s'ouvre pas : verifier la tache planifiee et le runtime WebView2.
- L'API ne repond pas : tester `GET /health` ; verifier que le back Pode tourne.
- Windows Update s'est reactive : relancer le verrouillage
  (`LocalAgentAdmin/tools/lockdown-updates.ps1`), cf. `WU-LOCK`.

## Securite

Le back tourne **eleve** : ne jamais l'exposer hors de `127.0.0.1`. Le jeton
Bearer empeche tout autre processus local non autorise d'appeler les actions.

## Scripts d'installation et de lancement (recommande)
- **`backend\install.ps1`** — idempotent : installe le provider NuGet, approuve
  PSGallery, installe Pode, genere le jeton. Aucune invite. Pas besoin d'admin.
- **`backend\run.ps1`** — lance le back + ouvre l'UI. Options :
  `-Admin` (relance eleve : actions Windows Update actives), `-NoBrowser`.
Ces scripts remplacent les commandes manuelles ci-dessus.

## Logs
Emplacement : `backend/logs/`.
- `install_*.log`, `start_*.log` : transcript + evenements.
- `pode-error_*.log`, `pode-request_*.log` : runtime du serveur.
En cas de souci, fournir/relire ces fichiers (ils sont recuperables via le pont).
