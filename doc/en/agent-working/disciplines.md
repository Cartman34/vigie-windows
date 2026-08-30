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

## Poser une question — FORMAT OBLIGATOIRE

Ce n'est pas une préférence de style : une question posée hors de ce format est à reposer.

**Numérotation.** Toute question, tout problème, toute décision à prendre porte un numéro préfixé `Q` — Q1, Q2… — pour
qu'une réponse s'y accroche sans ambiguïté (« Q1A »). Les numéros **restent stables** tant qu'une question de la série
est ouverte ; quand toutes sont répondues, la série repart à Q1.

**Questions autonomes.** Chaque question est énoncée **en entier**, avec ses options, **à chaque fois qu'elle est
posée** — jamais réduite à un thème ou à une étiquette. Une question qu'il faut aller rechercher plus haut est une
question mal posée.

**Options.** Une question fermée reçoit des options lettrées — A, B, C… — **la recommandée en premier**. Une question
ouverte reste libre. Chaque option annonce son **avantage principal** en quelques mots (plus rapide à construire, plus
sûr, plus maintenable…), pour que l'arbitrage soit explicite plutôt que deviné.

**Dans une conversation**, les questions passent par l'outil de question interactif, pas par une liste en texte. Le
format ci-dessus vaut pour les questions **écrites** : documents de conception, comptes rendus, fichiers de suivi.

## Chercher avant de concevoir

**La source de vérité, c'est `doc/progress/decisions.md`** — les arbitrages, rien d'autre. Avant de concevoir quoi que
ce soit : y chercher. Le fichier fait près de trois mille lignes, donc chercher doit coûter dix secondes :

```powershell
pwsh -File scripts/dev/decisions.ps1 -About "mise a jour deploiement"   # les titres
pwsh -File scripts/dev/decisions.ps1 -About "cache" -Full               # + le texte
pwsh -File scripts/dev/decisions.ps1 -Number D99                        # le texte entier
```

**Une incohérence sans décision qui tranche se DEMANDE**, elle ne s'arbitre pas seul : c'est ainsi qu'on empile deux
conceptions contradictoires dont aucune n'est écrite.

**Chaque chose à sa place.** Un arbitrage va dans `decisions.md`. Une discipline de travail va ICI. Une conception —
comment ça marche — va dans `doc/en/developing/`. Le 29/08 j'ai écrit une discipline dans `decisions.md`, alors que ce
fichier-ci existait et le dit dans son en-tête.

*Le 29/08 : trois erreurs le même jour, jamais un oubli de code — trois fois ne pas avoir cherché. Réinventé « d'où
vient le code déployé » quand `UpdateSource` y répondait ; rangé un réglage d'ordinateur dans chaque copie quand D33
décrit les couches de configuration ; redéfini une fonction qui existait déjà, la dernière définition écrasant l'autre
en silence.* `scripts/dev/check-coherence.ps1` attrape désormais ces deux dernières.

## Validation avant de dire « prêt »
- Chaque `.ps1` / `.psd1` : **parser** via `[System.Management.Automation.Language.Parser]::ParseFile`
  (`pwsh` de la machine), et on rapporte la **sortie réelle**.
- Le JS d'`index.html` : **charger la page en `file://` et lire la console** (**D06**).
  Node n'est pas installé et ne doit pas l'être : le projet n'a aucune dépendance JS.
  Une erreur de syntaxe empêche l'exécution de **tout** le bloc `<script>` — vérifier qu'une
  constante définie en fin de script existe suffit à prouver que le fichier parse.
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
- `apps/frontend-web/index.html` → auto-reload via version.

## Documentation (toujours à jour)
- `briefing.md` (reprise à tout moment), `CHANGELOG.md`, `doc/en/developing/conventions.md`, `doc/progress/targeting/features.md`.
