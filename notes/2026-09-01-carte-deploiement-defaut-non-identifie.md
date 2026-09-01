# 2026-09-01 — Carte Déploiement : un défaut non identifié, à surveiller

**Constat (utilisateur, 01/09).** Après l'installation de la v0.1.48, la carte Déploiement
affichait « Démarrage automatique : 1 tâche(s) hors service — Famille : la tâche est
désactivée dans Windows », alors que la tâche `Vigie - Famille` était `Ready`.

**Ce qui a été mesuré, au moment du constat :**

| | |
|---|---|
| `GET /api/v1/modules/deployment` (cache) | `Démarrage automatique : Opérationnel`, statut `ok` |
| `GET /api/v1/modules/deployment?fresh=1` | identique — `Opérationnel`, statut `ok` |
| Action `accounts-details` | « tâche « Vigie - Famille » : Ready, niveau Limited » |

Le serveur était donc juste des deux côtés. L'affichage fautif venait du DOM de l'onglet
ouvert, resté sur un rendu antérieur ; un rafraîchissement demandé à la main l'a corrigé.

**Pourquoi cette note existe quand même :** l'utilisateur maintient qu'il y a un défaut,
non identifié à ce stade. Ce qui n'a PAS été vérifié :

- pourquoi l'onglet n'a pas repris la valeur au sondage automatique suivant (60 s) ;
- si le rendu affiché correspondait à un `pending` servi puis rempli, ou à un rendu figé ;
- si l'invalidation faite par l'installation a bien atteint le var du compte de service
  cette fois-là (elle vise deux racines, et un échec y est silencieux).

**À faire au prochain constat :** relever l'heure exacte, comparer `generatedAt` de la
réponse `/state` reçue par l'onglet avec l'heure affichée, et regarder `timings` — les
trois disent si la page a reçu quelque chose et quand.
