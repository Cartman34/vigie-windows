# La forme du code — ce qu'un fichier doit rester

Ce que tout fichier du dépôt **doit** rester, quelle que soit sa nature. Les identifiants sont stables ;
`../implemented/status.md` en suit la réalisation sans réécrire l'énoncé.

> **Pourquoi cette page existe.** Deux monolithes ont grossi sans qu'aucune règle ne soit enfreinte, parce qu'il
> n'y en avait pas : `index.html` à 3 736 lignes et `common.ps1` à 11 910. À chaque fois, la cause est la même —
> ajouter dans le fichier qui existe déjà est toujours le geste le plus court. Ce n'est pas la taille qui est le
> défaut, c'est l'absence d'énoncé.

## La taille

- **SIZE-CODE** — Un fichier de code **avertit au-delà de 800 lignes**, et un changement qui **crée** un fichier
  au-delà de **1 000 lignes**, ou qui l'y fait passer, est **refusé**. Un fichier déjà au-delà de 1 000 n'est pas
  refusé pour un changement ordinaire : on ne bloque pas une correction derrière une dette qu'elle n'a pas créée.
- **SIZE-DOC** — Un fichier de documentation **se découpe à envisager au-delà de 400 lignes**, et le découpage est
  **obligatoire au-delà de 600**. Un document qu'on parcourt au lieu de le lire ne porte plus rien.
- **SIZE-LINE** — **200 caractères** au plus, pour toute ligne de tout fichier. Une ligne se coupe parce qu'elle
  change d'idée, pas parce qu'un compteur a sonné. **Exception** : une ligne de tableau markdown ne se coupe pas —
  la couper casse le tableau.

## Le découpage

- **SPLIT-SUBJECT** — Un fichier qui agrège ne se découpe **pas par taille** : il se découpe **par sujet**, et
  chaque sujet quitte les autres. Un sujet lui-même lourd se redécoupe en sous-sujets, jusqu'à des briques
  réutilisables.
- **SPLIT-VERTICAL** — Le découpage se fait **en couches**, jamais par fonctionnalité d'un même sujet portant la
  même responsabilité. Écrire une série et la relire sont la même responsabilité : les séparer, c'est couper en
  deux ce qui tient ensemble. En revanche un **mécanisme** et les **cas** posés dessus sont deux couches, et une
  couche basse est réutilisable seule.
- **SPLIT-ALWAYS-POSSIBLE** — Il y a presque toujours une sous-couche à extraire : « il n'y en a pas » n'est une
  réponse que pour un fichier de fonctions de trois lignes. La question se pose à chaque fichier qui dépasse, et
  elle se répond en nommant la couche, pas en invoquant la taille.
- **SPLIT-NO-DUPLICATION** — Une couche extraite **retire** la duplication qu'elle révèle : deux implémentations du
  même mécanisme deviennent une, et c'est la bonne qui reste. Le découpage de `common.ps1` a montré le verrou
  nommé écrit deux fois — une version qui pose ses droits, une qui les oublie.

## Ce que ça n'autorise pas

Un fichier ne se **coupe pas pour satisfaire un nombre**. Si aucune couche ne s'y trouve, le plafond devient la
question à instruire, pas le fichier à trancher — et le relevé dit alors pourquoi il reste gros.
