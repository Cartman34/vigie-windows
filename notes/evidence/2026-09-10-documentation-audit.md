# 2026-09-10 — Ce que l'audit de la documentation a trouvé

**Preuve de D119.** L'utilisateur a énoncé cinq exigences sur la documentation. Avant de les
appliquer, voici ce que le dépôt donnait réellement — et c'est la première décision de ce
dépôt à déposer sa mesure, ce qui est aussi le sujet de la décision.

## Les décisions et leurs preuves

| | |
|---|---|
| Entrées dans `decisions.md` | 125 |
| Portant un renvoi vers une mesure | **1** |
| N'en portant aucune | **124** |

Une seule décision sur cent vingt-cinq pouvait se vérifier. Les autres ont pourtant été
prises sur des relevés réels — les mesures existaient, elles n'ont simplement jamais été
déposées. Le plafond de `check-decisions.ps1` est donc posé à 124.

## Les index de dossier

Sept dossiers de documentation sur quatorze n'avaient **aucun `README.md`** :

```
doc/agent-working    doc/en/operating    doc/en/using
doc/fr/operating     doc/fr/using        doc/progress        notes/evidence
```

Un dossier sans index se parcourt en devinant. C'est aussi ce qui pousse à multiplier les
renvois de fichier à fichier : faute d'index, chaque document se met à citer ses voisins.

## Le dossier de langue qui n'en était pas un

`doc/en/agent-working/` contenait deux documents **écrits en français** — `briefing.md` et
`disciplines.md`. Le dossier `en/` promettait de l'anglais et livrait autre chose.

La règle du dépôt dit que ce qui ne se traduit pas vit **en dehors** des dossiers de langue,
et `doc/progress/` la respectait déjà. `agent-working/` la contredisait depuis l'origine,
sans que rien ne le signale : aucun contrôle ne compare la langue d'un fichier à celle de
son dossier.

## Les noms de fichiers

Trois preuves déposées le jour même portaient un nom **français** :

```
2026-09-01-carte-deploiement-defaut-non-identifie.md
2026-09-10-fournisseurs-windows-update-16-orthographes.md
2026-09-10-notifications-quelle-api-est-atteignable.md
```

La discipline disait « un nom de fichier est du code : il s'écrit en anglais », puis
ajoutait « les *documents* restent en français ». Cette seconde phrase parlait du **contenu**
et se lisait comme parlant du nom. Je l'ai lue dans le mauvais sens le matin même en créant
ces trois fichiers.

## Ce qui n'a pas été vérifié

- **Aucun contrôle ne mesure la langue d'un document.** `check-doc.ps1` compare la charpente
  des paires `fr`/`en`, pas leur langue. Un document français reposé un jour dans `en/`
  passerait aussi inaperçu qu'il l'a fait pendant des mois.
- **Aucun contrôle ne mesure les renvois de fichier à fichier.** L'exigence de doser les
  références reste une consigne, sans mesure — donc, par la loi du dépôt, elle ne tient que
  par attention.
- Le plafond de 124 n'a pas été réparti : on ne sait pas combien de ces décisions ont une
  mesure encore retrouvable dans l'historique, et combien sont définitivement sans preuve.
