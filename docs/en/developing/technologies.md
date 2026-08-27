# Technologies employees

Chaque techno : role, pourquoi, alternatives ecartees, installation.

## PowerShell (5.1+ / 7)
- **Role** : moteur natif — pilote Windows (registre, taches, ACL, services).
- **Pourquoi** : acces natif a l'hote sans couche intermediaire ; tout
  l'outillage existant (`LocalAgentAdmin/`) est deja en PowerShell.
- **Installation** : present nativement sur Windows.

## Pode (module PowerShell)
- **Role** : serveur web — sert le front ET expose l'API REST, en PowerShell.
- **Pourquoi** : un seul langage cote back ; il rend l'API tout en pilotant
  Windows nativement. Evite d'ajouter PHP/Node juste pour deleguer ensuite a
  PowerShell.
- **Alternatives ecartees** : PHP/Node (ajout d'un runtime + pont vers
  PowerShell pour chaque action privilegiee) ; ASP.NET (plus lourd).
- **Installation** : `Install-Module Pode -Scope CurrentUser` (sans admin).
- **Point d'attention** : Pode isole les routes en runspaces. On passe le
  contexte par variables d'environnement (`VIGIE_BACKEND`, `VIGIE_TOKEN`) et on
  re-source `lib/common.ps1` dans chaque route.

## OpenAPI 3 (apps/backend-pode/api/openapi.yaml)
- **Role** : contrat REST, source de verite front/back.
- **Pourquoi** : standard, outillable, permet de changer de back sans toucher
  au front.

## HTML / CSS / JavaScript (vanilla)
- **Role** : front statique (dashboard).
- **Pourquoi** : aucune dependance, aucun build ; ne fait que du `fetch()` vers
  le contrat. Rendu clair/sombre.
- **Alternatives ecartees** : framework SPA (React/Vue) — inutile a cette
  echelle, ajouterait un build.

## WebView2  (a venir — CORE-WINDOW)
- **Role** : fenetre applicative affichant le dashboard comme une vraie app.
- **Pourquoi** : moteur Edge deja present sur Win10/11 ; pas d'Electron.
- **Installation** : « Evergreen WebView2 Runtime » si absent.

## Tache planifiee Windows  (a venir — CORE-AUTOSTART)
- **Role** : lancer le back + l'UI a l'ouverture de session, en eleve.
- **Pourquoi** : demarrage automatique sans invite UAC a chaque action.

## Jeton Bearer + ecoute locale
- **Role** : securite de l'API (back eleve).
- **Pourquoi** : 127.0.0.1 limite l'acces a la machine ; le jeton bloque les
  autres processus locaux non autorises.

## Mecanismes Windows pilotes (rappel, detail dans LocalAgentAdmin)
- Registre Windows Update (`NoAutoUpdate`...), taches planifiees Update,
  ACL/`takeown`/`icacls`, service WaaSMedic. Documentes cote `LocalAgentAdmin`.
