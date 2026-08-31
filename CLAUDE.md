# Vigie — à lire avant d'agir

Ce fichier est court exprès : il reste sous les yeux de l'agent en permanence, y compris
quand tout le reste du contexte a été compressé. Il ne contient donc **aucune règle** —
seulement le chemin vers celles qui existent.

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

| | |
|---|---|
| `doc/en/agent-working/briefing.md` | le projet, ses règles de conception permanentes. |
| `doc/en/agent-working/disciplines.md` | comment travailler. 159 lignes : se lit en entier. |
| `doc/progress/decisions.md` | les arbitrages. `scripts/dev/decisions.ps1 -About "…"` **avant** de concevoir. |
| `doc/progress/targeting/` | ce que le produit doit faire. Le premier fichier qu'on modifie. |
| `doc/progress/implemented/` | ce qui est en place. |
