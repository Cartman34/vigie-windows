# Vigie — reprise du projet (à lire en premier)

Point de reprise. Après ce fichier : `docs/DECISIONS-VALIDEES.md`, `SUIVI.md`, `PRISE-EN-MAIN.md`.

## Le projet
**Vigie** (nom de code interne « HYPERION ») : tableau de bord **local** pour un PC Windows.
- Backend **PowerShell + Pode** (`backend/`), écoute **127.0.0.1:47600**, jeton Bearer + anti-CSRF + liste blanche d'actions.
- Frontend **HTML/JS pur** (`frontend/index.html`), sert la maquette `frontend/mock/state.json` si le back est absent.
- **App tray WinForms** (`backend/tray.ps1`) : lance le serveur en fond, icône = statut de l'app (jauge), menu, fenêtre dédiée (Edge/Chrome `--app`).
- Fonction phare : **verrouiller Windows Update** (ACL deny SYSTEM sur les dossiers de tâches) pour bloquer les redémarrages forcés, sans masquer les vraies MAJ.

## Règles de conception (permanentes)
- **On parle français, le code est en anglais.**
- Pas de duplication (helpers partagés dans `backend/lib/common.ps1`).
- **Toujours** traiter erreurs + sortie + code retour (`Invoke-Native`).
- Scripts **idempotents**. **PS7 + UTF-8 avec accents** (les lanceurs restent ASCII).
- **Vérifier les prérequis en amont.** **Valider avant de dire « prêt »** (ne jamais inventer une validation).
- **Toute décision validée est consignée dans `docs/DECISIONS-VALIDEES.md`** + son support copié dans `docs/maquettes-validees/`.

## Architecture (contract-first)
- `api/openapi.yaml` = source de vérité du contrat REST.
- Sonde = `backend/probes/<theme>/*.probe.ps1`, renvoie 1 module OU un tableau de modules.
- Action = `backend/actions/<id>.action.ps1`, renvoie `@{ message; result }`. `result.invalidate=@('x.probe.ps1')` force le recalcul.
- Agrégation + cache (mtime+TTL, single-flight, serve-stale) : `Get-State` dans `common.ps1`.
- **Tâches de fond** : `Start-DetachedAction` (worker pwsh caché) ; ex. paquets via `Start-PkgJob` + `backend/workers/pkg-job.worker.ps1`. Une action longue répond `result.async=$true` + `module`; le front met la carte en « busy » et l'interroge jusqu'à fin.

## État — FAIT (déployé sur la machine, validé hors-ligne)
- Socle asynchrone non bloquant (`Start-DetachedAction`, `Remove-ProbeCache`, `Update-StateJson` avec mutex inter-processus).
- Paquets : **une carte par gestionnaire**, **vérification ET mise à jour** en tâche de fond (winget/choco/scoop/npm/gem), polling par carte, halo « en cours ».
- Boutons de résolution : prennent le **libellé de l'action** (plus de « Résoudre » générique), n'apparaissent que si une action existe. **Icônes** : boîte-flèche = logiciel externe ; fenêtre = popin.
- Résolutions câblées : Latence → `net-speedtest` ; Windows Update « Détectées » → `open-windows-update` (note raccourcie).
- WSL : champ **Statut Actif/Inactif** coloré + **trio Démarrer/Redémarrer/Arrêter** (boutons pertinents). Actions `wsl-start`/`wsl-restart` + invalidation sonde.
- Topbar : **liseré coloré = état de connexion à l'API** (vert live / orange maquette / rouge erreur) ; santé globale dans la topbar.
- **Icône tray** : `.ico` multi-résolutions nets, design **option B validée** (anneau + graduations + aiguille à talon + point blanc), générés par `backend/assets/tray/generer-icones_B.py`, chargés par `tray.ps1` (`setIcon`) avec repli GDI+.
- **Rebrand interface** : « Control Panel » → **« Vigie »** (titre onglet, sous-titre, `document.title`, tray). Le titre principal reste le **nom de la machine** (dynamique).

## État — À FAIRE (backlog)
1. **Écran de chargement soigné** au démarrage avec « Vigie » en **gros** (splash qui s'efface après chargement).
2. **Lien GitHub retrouvable** dans l'app (https://github.com/Cartman34/vigie-windows) — à placer (splash / pied de page / à-propos).
3. **Rendre `backend/config.psd1` générique** : `ToolsPath` est un chemin absolu machine-spécifique → calculer/relativiser + `config.sample.psd1`.
4. **Style du menu contextuel du tray** (référence : menu sombre arrondi type Win11) — pas encore satisfaisant.
5. **Rename interne complet** HYPERION → Vigie (commentaires, noms de mutex `HyperionControlPanelTray`, `Local\Hcp*`) — optionnel, l'interface est déjà faite.
6. **Couleur WSL « Inactif »** : aujourd'hui rouge **au niveau du champ** seulement (la carte reste neutre pour ne pas alarmer). À confirmer si on veut la carte entière en rouge.
7. **Publier sur GitHub** (voir plus bas).

## Décisions validées
Voir `docs/DECISIONS-VALIDEES.md` : icône tray = option B (graduations + talon confirmés) ; nom = dépôt « Vigie Windows » (slug `vigie-windows`), interface « Vigie » à la place de « Control Panel ».

## Publier sur GitHub (dépôt Cartman34/vigie-windows)
> IMPORTANT : ce dossier (`LocalWork/hyperion-control-panel`) est l'**espace de travail**, PAS le dépôt.
> Créer le dépôt local **ailleurs** (emplacement des projets de l'utilisateur) et y **copier le contenu**,
> en excluant `_to_delete/`, `*.bak-*`, `backend/.secrets/`, `backend/.state/`, `backend/logs/`.
> Le dépôt distant vide existe déjà. Demander à l'utilisateur le chemin cible avant de copier.
Depuis Claude Code / un terminal **sur la machine**. Config déjà OK : `credential.helper=manager`,
user.name/email réglés. Remote en **HTTPS** (token *fine-grained* All repos + Contents R/W,
mémorisé une fois par le Credential Manager au 1er push) :
Chemins (machine « hyperion ») :
- Espace de travail : `C:\EspaceRestreint\Workspaces\AiTeam\LocalWork\hyperion-control-panel`
- Dépôts git : `C:\EspaceRestreint\Workspaces\Git` → dépôt `...\Git\vigie-windows`

Flux **clone-first** (le dossier de travail n'est PAS le dépôt) :
```
# 1) cloner le depot vide
cd /c/EspaceRestreint/Workspaces/Git
git clone https://github.com/Cartman34/vigie-windows.git
cd vigie-windows

# 2) copier le contenu de l'espace de travail (exclut secrets/etat/logs/sauvegardes/corbeille)
SRC="/c/EspaceRestreint/Workspaces/AiTeam/LocalWork/hyperion-control-panel"
tar -C "$SRC" --exclude='./_to_delete' --exclude='./backend/.secrets' \
  --exclude='./backend/.state' --exclude='./backend/logs' --exclude='*.bak-*' \
  -cf - . | tar -xf -

# 3) verifier, committer, pousser
git add .
git status      # NI .secrets/ NI .state/ NI logs/ NI *.bak-*
git commit -m "Vigie — import initial"
git branch -M main
git push -u origin main   # Username: Cartman34 ; Password: le token (memorise ensuite)
```
Puis ouvrir l'agent (Claude Code) DANS `C:\EspaceRestreint\Workspaces\Git\vigie-windows` — plus dans l'espace de travail.
Avant le commit, `git status` ne doit montrer NI `.secrets/`, NI `.state/`, NI `logs/`, NI `*.bak-*`.
Au 1er push : Username `Cartman34`, Password = le token (mémorisé ensuite par le Credential Manager).
Au 1er push : Username = `Cartman34`, Password = le **token** (pas le mot de passe GitHub).
Créer le dépôt **vide** sur GitHub (sans README) avant le push. `.gitignore` exclut déjà
le jeton API, l'état et les logs. (Alternative zéro-token : remote SSH `git@github.com:Cartman34/vigie-windows.git` avec la clé locale.)

## Contraintes environnement (importantes)
- Ce dossier a été édité via **Cowork/`device_bash`** (VM Linux, montage de ton dossier) :
  - **git ne peut pas s'initialiser DANS le dossier** depuis ce montage (suppression interdite) → sur ta vraie machine / Claude Code, `git init` marche normalement.
  - **pas de pwsh** sur cette VM Linux (validation PS faite par reconstruction/parse ailleurs).
  - **SSH bloqué** vers GitHub depuis la VM ; **HTTPS OK**.
- Validation à privilégier : `pwsh` (Parser) pour PowerShell, `node --check` pour le JS de `index.html`.
- Ne jamais committer `backend/.secrets/api.token`.
