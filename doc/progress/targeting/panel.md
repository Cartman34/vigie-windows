# Le panneau — ce qu'il doit être

Ce que le panneau **doit** être, à terme. Les identifiants sont stables ; `../implemented/status.md` en suit la
réalisation sans réécrire l'énoncé. La liste des fonctionnalités le référence depuis sa section Interface.

> **Pourquoi cette page existe.** Rien dans la cible ne disait comment le panneau est fabriqué, et une seule page
> a grossi jusqu'à **3 736 lignes** — styles, script et balisage mêlés — sans qu'aucune règle ne soit enfreinte,
> puisqu'il n'y en avait pas. Ce n'est pas la taille qui est le défaut, c'est l'absence d'énoncé.

## Ce qui est rendu

- **UI-RENDER** — Le panneau est **rendu par l'app serveur**, qui a un moteur de vues : une vue porte la coquille
  — en-tête, balisage, jeton de session — et rien d'autre. Aucun fichier n'est **engendré** : ni dans le dépôt, ni
  dans `var/`, ni à l'installation. Ce qui ne s'engendre pas ne peut ni dériver ni manquer.
- **UI-ASSETS** — Les styles et les scripts sont de **vrais fichiers**, `.css` et `.js`, servis comme tels : le
  navigateur les met en cache, les outils les lisent pour ce qu'ils sont, et le serveur n'a rien à recoller à
  chaque requête.
- **UI-NO-BUILD** — Tout cela **sans build ni Node** (**D06**). Ce qui est écrit est ce qui est servi ; aucune
  étape intermédiaire ne doit exister pour qu'une page s'affiche.

## Comment c'est organisé

- **UI-MODULES** — Le script est découpé en **modules**, une seule entrée, **aucune variable globale**. Un module
  exporte, un autre importe ; ce qui n'est pas exporté n'existe pas pour les autres.
- **UI-SUBJECT** — **Un sujet par fichier**, et le nom du fichier dit le sujet. Trois familles, et la frontière
  entre elles est une règle, pas un goût :
  - le **noyau** parle au serveur, tient l'état reçu et les textes — il ne touche pas au DOM ;
  - un **composant** possède son DOM et ses événements, sait se détruire, et ne connaît ni le serveur ni l'état ;
  - une **vue** connaît les deux, assemble des composants, et **n'écrit pas de HTML à la main**.
- **UI-STATE-OWNER** — Une classe là où il y a un état qui dure — une fenêtre, un tiroir, les bulles. Ailleurs, des
  fonctions pures : des données en entrée, un fragment en sortie.

## Ce qu'une page ne doit jamais redevenir

- **UI-SIZE** — Aucun fichier du panneau ne dépasse la taille que le cliquet tient. Le plafond **ne monte jamais** :
  il descend à chaque découpage, comme les autres cliquets du dépôt. C'est le seul mécanisme qui empêche la
  récidive — l'habitude d'ajouter dans le fichier qui existe déjà a produit les deux monolithes du projet, et
  aucune décision ne l'avait permis.
- **UI-HTML-IN-JS** — Le HTML ne se fabrique pas en chaînes de caractères dispersées dans le script. Il est rendu
  par des composants, qui sont le seul endroit où l'on écrit du balisage.

## Ce que ça ne change pas

Pour qui regarde le panneau, **rien** : mêmes cartes, mêmes couleurs, mêmes gestes. Un découpage qui change ce qui
s'affiche n'est pas un découpage, c'est une refonte — et elle se demande.
