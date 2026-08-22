# Documentation — HYPERION Control Panel

La doc est en **quatre volets**, chacun avec un public et un but distincts.
Regle d'or : **pas de doublon**. Chaque information vit dans UN seul volet ; les
autres y font reference (par ID de fonctionnalite).

| Volet          | Public               | Repond a la question            |
|----------------|----------------------|---------------------------------|
| `using/`       | Utilisateur final    | Comment je m'en sers ?          |
| `operating/`   | Admin systeme        | Comment je l'installe/l'exploite ? |
| `targeting/`   | Concepteur / agent   | Que DOIT faire le produit (cible) ? |
| `implemented/` | Concepteur / agent   | Que fait-il REELLEMENT aujourd'hui ? |

## targeting/ vs implemented/ (le point delicat)

- **`targeting/`** detient l'**enonce du besoin** par fonctionnalite, chacune
  identifiee par un **ID** stable (ex. `WU-LOCK`). C'est la cible, ca bouge peu.
- **`implemented/`** ne **reecrit pas** le besoin. Il donne, par **ID**, l'**etat
  reel** : fait / partiel / a faire, OU c'est code (fichiers), COMMENT ca se
  comporte, et les **ecarts** avec la cible.
- Donc : le "quoi/pourquoi" est dans `targeting/` ; le "ou en est-on/comment"
  est dans `implemented/`. On ne duplique jamais l'enonce.

## IDs de fonctionnalites

Definis dans `targeting/features.md`. Toute la doc (using, operating,
implemented) references ces IDs plutot que de repeter les specifications.
