# DISCIPLINES DE PROCESS — à tenir en continu

> Règles que Claude doit respecter systématiquement sur ce projet.
> Toute nouvelle discipline demandée par l'utilisateur est ajoutée ici.

## Langue & encodage
- Échanges **en français** ; code **entièrement en anglais**.
- **Messages de commit en anglais** : c'est du technique, au même titre que le code. Ils étaient écrits en français
  jusqu'au 30/08.
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

**Le format ci-dessus est LE format — partout.** En conversation comme dans un document de conception, un compte rendu
ou un fichier de suivi : numéro `Qn`, énoncé complet, options lettrées.

**Les outils interactifs sont à ÉVITER, et ils ne priment jamais sur les formats définis.** J'avais écrit ici que les
questions « passent par l'outil de question interactif » : une confusion entre le canal et le format, qui m'a fait
présenter un moyen comme une règle. Une question se pose en texte, au format ci-dessus ; sans numéro ni options, elle
reste hors format quel que soit le moyen employé.

## Conventions de nommage — pour que l'erreur soit impossible, pas rattrapée

**Une variable ne porte JAMAIS le nom d'un paramètre du script.** PowerShell ignore la casse : `$source` **est**
`$Source`. Écrire `$source = …` dans un script qui déclare `$Source` n'est pas une variable locale, c'est une
affectation au paramètre — et si celui-ci porte un `ValidateSet`, le script meurt sur place avec un message qui parle
d'autre chose. Deux fois le 30/08, dans le même fichier ; la seconde a tué la mise à jour devant l'utilisateur.

**La convention :** une variable locale porte un nom **qualifié** — `$sourceRepo`, `$sourcePath`, `$targetPath` — jamais
le nom nu qui pourrait être un paramètre. `check-coherence` refuse les collisions, en comparaison **sensible à la
casse** (`-cne` ; avec `-ne`, la règle ne se déclenche jamais — je m'y suis fait prendre en l'écrivant).

**Les autres conventions déjà tenues par un outil :** noms de code en anglais (cliquet `check-naming`), texte affiché
dans `lang/fr.json` (`check-labels`), pas de mot banni « machine » ni « tray » dans l'affiché, une fonction définie une
seule fois, un cercle de comptes jamais refiltré à la main.

## Un correctif, un commit

**Un commit = une correction, ou un ajout, et rien d'autre.** Son titre le dit en entier. S'il faut « et » pour le
résumer, c'était deux commits.

**Pourquoi :** le 30/08, neuf commits pour la journée alors qu'il y avait bien plus de correctifs. `6d02bf6` en portait
trois chantiers sans rapport (l'outil de question à Vigie, « qui exécute » ≠ « qui demande », le cache par compte) ;
`cf824b8` en portait deux (la relance qui passait à côté de la tâche, git qui refusait en silence) ; `5524cc3` deux
aussi. Conséquences concrètes : impossible d'annuler un seul de ces changements, impossible de dire lequel a introduit
une régression, et un message de commit qui raconte au lieu d'expliquer.

**Ce qui va ensemble dans un commit :** le code, ses libellés, son vérificateur et la doc que ce changement rend
fausse. Ce sont les faces d'une même correction, pas des sujets différents.

**UN COMMIT EST UNE LIVRAISON, PAS UN POINT DE SAUVEGARDE.** On ne commite pas après le moindre bout de code : on
commite quand la chose est **terminée**, **éprouvée**, et qu'on juge qu'elle doit être livrée. Parser le fichier et voir
les vérificateurs au vert ne prouve que l'absence de faute de frappe.

*Le 30/08 : six correctifs de la chaîne de mise à jour commités sans qu'un seul ait tourné — dont la relance par la
tâche planifiée, écrite précisément parce que la précédente avait laissé Vigie morte.* Le travail reste dans la copie
de travail jusqu'à l'épreuve. Si l'épreuve demande un geste que je ne peux pas faire (élévation, redémarrage, session
d'un autre compte), je le dis et j'attends — et si la session se termine avant, le commit part quand même, en
**annonçant dans son message ce qui n'a pas été éprouvé** (fin de session prioritaire).

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
