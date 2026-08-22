# DISCIPLINES DE PROCESS — à tenir en continu

> Règles que Claude doit respecter systématiquement sur ce projet.
> Toute nouvelle discipline demandée par l'utilisateur est ajoutée ici.

## Langue & encodage
- Échanges **en français** ; code **entièrement en anglais**.
- **Accents obligatoires** dans les libellés visibles. **UTF-8 partout**, cible **PowerShell 7**.
- Exception : les **lanceurs** (`run/start/install/*.cmd`) restent en **ASCII** (compat PS 5.1 avant bascule pwsh).

## Avant d'agir
- **Vérifier les prérequis** de l'environnement en amont (pwsh, Pode, droits, chemins).
- **Idempotence** : tout script doit pouvoir être relancé sans effet de bord.

## Qualité de code
- **Zéro duplication** : une fonctionnalité = un seul code partagé (helpers dans `lib/common.ps1` :
  `Test-Elevated`, `Invoke-Native`, `Test-UpdateTasksAclLock`, `Update-StateJson` ; rendu de carte `cardHtml`).
- **Traiter tout appel externe** (commande / service / script) : erreurs **ET** sorties **ET** codes de retour
  (passer par `Invoke-Native` ; une action doit vérifier son **résultat réel**, jamais renvoyer un faux succès).

## Sécurité (ne jamais devenir une back door)
- Écoute **127.0.0.1 uniquement**, **jeton Bearer**, **anti-CSRF** (Origin/Referer), **whitelist d'actions**
  + confinement de chemin (`Resolve-Path`). Vérifier les failles à **chaque** ajout d'action.
- Le script lancé par l'utilisateur **demande l'UAC** si besoin ; le serveur tourne **élevé** mais protégé.

## Validation avant de dire « prêt »
- Chaque `.ps1` : **parser** via `[System.Management.Automation.Language.Parser]::ParseFile` (pwsh 7.4 du conteneur).
- Chaque JS d'`index.html` : **`node --check`**.
- Vérifier l'**ASCII** des lanceurs, l'**UTF-8** du reste.

## Cache & perfs
- Cache **par sonde** (mtime du fichier + TTL) ; **jamais** de recalcul global.
- Après une action : **invalidation ciblée** des sondes impactées (`result.invalidate`).
- Sondes lentes (lock, pending, wsl) : TTL longs.

## Front
- **REST standard**, back interchangeable sans impact front. Contenu **adapté à la largeur**.
- Si la **version serveur** change → la page se **recharge** entièrement seule.
- **Composants réutilisables** (design system `HDS` : dialog/confirm/info in-app, boutons).
- **Statut de carte = santé fonctionnelle** : un avertissement de ligne **sans impact** ne fait pas passer la carte en orange.

## Livraison (device)
- Modifs **live** : `common.ps1`, sondes, actions (re-sourcées à chaque requête) → effet immédiat.
- `server.ps1` / `start.ps1` → **redémarrage serveur** requis.
- `frontend/index.html` → auto-reload via version.

## Documentation (toujours à jour)
- `SUIVI.md` (reprise à tout moment), `CHANGELOG.md`, `docs/conventions.md`, `docs/targeting/features.md`.
- Fichier d'initialisation à **nom non standard** : `PRISE-EN-MAIN.md` (pour ne pas être auto-chargé par des agents).
