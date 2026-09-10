# 2026-09-10 — La langue d'`agent-working/`, et ce que D93 disait vraiment

**Preuve de D120.** Trois échanges du même après-midi ont déplacé ce dossier deux fois avant
de le poser. Ce qui suit dit pourquoi, et ce que la mesure a donné.

## Ce que le dépôt donnait

| | |
|---|---|
| Emplacement, avant le 10/09 | `doc/en/agent-working/` |
| Langue du contenu | **français** |
| Lignes concernées | 845 (`briefing.md` 295, `disciplines.md` 539, `README.md` 11) |
| Poids | 59 325 octets |

Un dossier `en/` qui contenait du français, depuis des mois, sans que rien ne le signale.

## Les deux déplacements, et pourquoi le premier était faux

**Premier déplacement, vers `doc/`.** J'ai lu dans le `README.md` de `doc/` : « The development
documentation exists in English only, and therefore **lives outside the language folders** ».
J'en ai fait une règle d'emplacement.

**C'était faux, et le dépôt le montrait** : `en/developing/` est bien à l'intérieur d'`en/`.
La phrase parlait de l'absence de jumeau, pas de l'emplacement. Coût de l'erreur : trois
fichiers déplacés, quatorze renvois réécrits, et un `check-doc` au vert sur un dépôt cohérent
au mauvais endroit.

**Deuxième déplacement, vers `doc/fr/`**, après le constat de l'utilisateur : « tu as mis
agent working sous `doc/` au lieu de `fr/` ou `en/` ». Arbitrage : un document porte toujours
un dossier de langue, et ce qui varie est l'existence du jumeau, pas l'emplacement.

## Ce qui a tranché la langue elle-même

**D93 fait du français la langue maîtresse, et dit pourquoi** : « la validation se fait en
français — faire mener l'anglais reviendrait à valider une traduction, et on n'approuve pas un
texte dont l'original est ailleurs ».

Cette raison est **conditionnelle** : elle tient tant que l'utilisateur valide le texte. Il a
répondu sans ambiguïté :

> « Je ne valide pas directement ce qu'il y a dans agent-working et je ne veux pas valider
> tout contenu de doc. »

La condition tombe pour ce dossier. Trois raisons le font alors basculer :

- son lecteur est un **agent**, pas l'utilisateur ;
- le **code est déjà en anglais** (D41, D115), et ces documents ne parlent que de code ;
- un agent d'un autre client le lit sans détour — préoccupation exprimée par l'utilisateur le
  matin même, à propos du partage du schéma documentaire.

**D93 n'est pas annulée** : elle garde son numéro et gagne un paragraphe qui dit sur quoi elle
porte — ce que l'utilisateur valide, c'est-à-dire la documentation d'usage.

## Ce que la traduction a corrigé au passage

Quatre défauts, trouvés en relisant ligne à ligne pour traduire :

- la section Langue disait encore « les *documents* restent en français », contredit par D119
  le matin même ;
- la section « Où va ce qui est daté » portait l'ancien classement — `doc/` intemporel,
  `notes/` « daté mais utile » — que l'arbitrage du 10/09 avait remplacé ;
- la liste des vérificateurs en nommait sept sur huit, `check-decisions` et `check-author`
  manquaient ;
- deux titres de section étaient collés au paragraphe précédent, sans ligne vide.

Et dans le briefing : la procédure de redéploiement décrivait un `git merge --no-ff` que les
disciplines interdisent, un chemin `local/doc/` qui n'existe pas — c'est `local/docs/` —, un
dossier `doc/maquettes-validees/` absent du dépôt, et « D01→D72 » quand il y en a 122.

## Ce qui n'a PAS été vérifié

- **La traduction n'a été relue par personne.** L'utilisateur a dit qu'il ne validait pas ce
  contenu ; les nuances de 845 lignes reposent donc sur ma seule relecture.
- **Aucun contrôle ne mesure la langue d'un document.** Le défaut d'origine — du français sous
  `en/` — passerait exactement pareil demain. C'est écrit dans l'audit du même jour et rien
  n'a été fait depuis.
- Les documents traduits citent des incidents datés d'août et septembre ; **aucun n'a été
  revérifié** à cette occasion. Ils sont traduits, pas réaudités.
