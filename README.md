# Vigie

> **Local-only control panel for a single Windows PC.** Locks the Windows Update task
> folders (ACL deny for SYSTEM) to stop forced reboots, and surfaces system, security,
> network, WSL and package-manager health as live cards. PowerShell/Pode backend +
> tray app, bound to 127.0.0.1 with a bearer token and a strict action whitelist.

**Vigie** est un tableau de bord **local** pour *surveiller et piloter* un PC Windows :
verrouillage de Windows Update (sans redémarrage forcé), disque, WSL, sécurité de la
virtualisation, réseau, gestionnaires de paquets… Interface web locale + application
dans la barre système, lancée avec la session.

> Le projet s'appelle **Vigie** (dépôt `vigie-windows`). « HYPERION » est le **nom de la machine**
> de l'utilisateur, jamais un nom de code du projet : toute occurrence restante est un défaut de
> généricité (valeur machine codée en dur) à corriger.

Dépôt : https://github.com/Cartman34/vigie-windows

## Principes directeurs
1. **Contract-first** — le contrat REST (`api/openapi.yaml`) est la source de vérité.
   Le front ne connaît que ce contrat ; le back n'en est qu'une implémentation
   (Pode/PowerShell aujourd'hui, remplaçable sans toucher au front).
2. **Générique et extensible** — socle à base de **sondes** (lecture d'état) et
   d'**actions**, regroupées par **thème**. Ajouter une sonde = déposer un fichier dans
   `backend/probes/<theme>/`, sans modifier ni le contrat, ni le front.
3. **Front statique** — HTML/CSS/JS pur, aucun rendu serveur, uniquement `fetch()`.
4. **Non bloquant** — toute opération longue (MAJ paquets, mesure réseau, WSL…) tourne
   en **tâche de fond** ; l'UI reste réactive et chaque carte s'actualise seule.
5. **Sécurité** — API strictement locale (127.0.0.1) + jeton Bearer + anti-CSRF +
   liste blanche d'actions. Jamais une porte dérobée.

## Arborescence
    api/            Contrat REST (openapi.yaml) — SOURCE DE VERITE
    frontend/       Front statique (dashboard). mock/ = jeu de donnees sans back
    backend/        Implementation Pode : lib/, probes/<theme>/, actions/, workers/, assets/
    docs/           Documentation + docs/DECISIONS-VALIDEES.md (a ne jamais perdre)

## Sécurité / ce qui n'est jamais versionné
`backend/.secrets/` (jeton API), `backend/.state/` (cache/état), `backend/logs/` — voir `.gitignore`.

## Démarrage rapide
- **Front seul (maquette)** : ouvrir `frontend/index.html` (utilise `frontend/mock/state.json`).
- **Complet** : lancer le serveur (voir `PRISE-EN-MAIN.md`) — l'app se sert sur `http://127.0.0.1:47600`.

## Reprise / contexte
- **Contexte pour Claude Code** : `CLAUDE.md`
- État courant & prochaines actions : `SUIVI.md`, `PRISE-EN-MAIN.md`
- **Décisions validées** : `docs/DECISIONS-VALIDEES.md`
