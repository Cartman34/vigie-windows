# `progress/` — la conception

**En français**, comme `../agent-working/` : c'est la langue du projet, et ces documents ne
s'adressent pas au public. Ils vivent donc en dehors des dossiers de langue.

Ce dossier porte un **état consistant** — ce que le produit doit être, ce qu'il est. Il se
modifie souvent et décrit malgré tout une chose durable. Ce qui est *vraiment temporel*,
comme le registre des sujets ouverts, vit dans `../../notes/`.

| | Ce qu'il répond |
|---|---|
| [decisions.md](decisions.md) | Pourquoi ainsi et pas autrement. Un arbitrage par entrée, numéroté, **avec sa preuve**. |
| [targeting/](targeting/README.md) | Ce que le produit doit faire. |
| [implemented/](implemented/README.md) | Ce qui est réellement en place. |

`targeting/` et `implemented/` décrivent la même fonctionnalité des deux côtés. C'est la
**seule duplication assumée** du dépôt : perdre l'écart entre ce qu'on veut et ce qu'on a
coûte plus cher que de le répéter.