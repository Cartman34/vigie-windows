# Vigie — à lire avant d'agir

Ce fichier est court exprès : il reste sous les yeux de l'agent en permanence, y compris
quand tout le reste du contexte a été compressé. Il ne contient donc **aucune règle** —
il dit **où sont les règles, qu'il faut les lire, et qu'il faut les appliquer**.

## La consigne, en une phrase

**Lire la documentation du dépôt, et l'appliquer.** Elle n'est pas une référence qu'on
consulte en cas de doute : c'est la manière de travailler sur ce projet, et elle prévaut
sur toute habitude, tout souvenir et tout résumé. Une règle qu'on n'a pas lue s'applique
quand même ; c'est pour cela qu'on la lit.

## Reprise après compression — obligatoire, avant toute conclusion

Une compression laisse un **résumé**, pas les règles ni les documents. Ce qui y est écrit
est un souvenir, pas une source : ne rien en conclure sans revérifier. Premier geste au
retour, avant la moindre réponse de fond :

```
pwsh -File scripts/dev/reprise.ps1
```

Il rappelle les disciplines, les documents de vérité et l'état du dépôt. Tant qu'il n'a
pas été lancé, on ne conclut rien, on ne supprime rien, on ne livre rien.

## Où vit la vérité

Chacun de ces documents dit, en tête, ce qu'il oblige à lire ensuite. On suit la chaîne
jusqu'au bout.

| | |
|---|---|
| `doc/en/agent-working/briefing.md` | **à lire en premier** : le projet et ses règles de conception permanentes. |
| `doc/en/agent-working/disciplines.md` | **à lire en entier, et à tenir** : comment travailler ici. |
| `doc/progress/decisions.md` | les arbitrages, qui **s'imposent**. `scripts/dev/decisions.ps1 -About "…"` **avant** de concevoir. |
| `doc/progress/targeting/` | ce que le produit doit faire. Le premier fichier qu'on modifie quand il demande quelque chose. |
| `doc/progress/implemented/` | ce qui est en place. |
