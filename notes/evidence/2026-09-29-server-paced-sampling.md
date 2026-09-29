# Ce qu'une partie de deux heures a laissé quand personne ne regardait — 29/09/2026

Relevé pour **D124** (le serveur relève, le client vient chercher). Tout ce qui suit est lu sur ce poste, par l'app
serveur elle-même (`scripts/dev/ask-vigie.ps1`), le 29/09 au matin, à propos de la soirée du 28/09.

## Le fait

L'app cliente du compte Famille a disparu vers **20:22** (heure locale) pendant une partie d'Assassin's Creed Odyssey.
L'app serveur, elle, n'a jamais cessé de tourner : ni redémarrage, ni veille avant 21:41.

## Ce que l'app serveur a gardé de la partie

| Ce qu'on lit | Valeur | Lu où |
|---|---|---|
| Jeu reconnu, session ouverte | `ACOdyssey`, **19:50:57** | action `game-sessions` |
| Passages enregistrés | **4** | action `game-recap`, champ `passes` |
| Couverture cumulée | **430 s** pour une partie de plus de 2 h | `seconds` |
| Dernier passage | **20:22** | dernier point de `game.gpu` |
| Fermeture de la session | **05:40 le lendemain**, au retour de l'app cliente | `endedAt` |
| Bouchons détectés | **aucun** (la règle demande deux passages consécutifs) | `jams` |
| Historique `perf.cpu` | dernier point **20:22**, puis rien jusqu'à **05:40** | route `history/perf.cpu?window=24h` |
| Historique `game.gpu` | dernier point **20:22**, à 78,9 % | route `history/game.gpu?window=24h` |

Les moyennes du jeu rendues par le récapitulatif — 13,8 % de processeur, 27,1 % de graphique, pointe à 78,9 % — reposent
donc sur quatre échantillons pris dans la première demi-heure. Elles n'expliquent rien de la lenteur ressentie ensuite.

## Pourquoi

Un relevé du catalogue n'est écrit qu'**après le recalcul réussi d'une sonde** (`Write-MeasureSamples`, appelé depuis
l'assemblage de l'état), et le passage de jeu n'est ajouté que par la sonde Jeu elle-même (`Add-GameTallyPass`). Or la
boucle de veille du serveur (`vigie-watch`, 60 s) exécute les résidents et les relevés déclarés, et ne fait recalculer
une carte **que si la valeur d'un relevé change**. « Un jeu tourne » ne change pas pendant la partie : aucun recalcul,
donc aucun échantillon.

Ce qui cadençait réellement les échantillons, c'était donc **l'app cliente** : elle lit l'état chaque minute, et chaque
lecture confie la sonde la plus périmée à une tâche de fond. Les cadences posées le 28/09 (`$script:GameModeUseful` :
Jeu 30 s, Ressources 20 s) ne sont que des **plafonds de fraîcheur** — personne ne les joue.

## Ce que coûte un passage, mesuré le 29/09

| Sonde | Durée d'un passage | À 30 s | À 60 s | À 120 s |
|---|---|---|---|---|
| `gaming.probe.ps1` | **3 262 ms** | 10,9 % d'un cœur | 5,4 % | 2,7 % |
| `perf.probe.ps1` | **1 385 ms** | 4,6 % d'un cœur | 2,3 % | 1,2 % |

Mesuré par `scripts/check-probes.ps1 -Only <sonde>`, machine au repos. À comparer à la plainte du 28/09 : Vigie avait
consommé **34 % d'un cœur** pendant une partie, avec 383 recalculs en 77 minutes.

## Ce qui n'est PAS vérifié ici

- La cause de la disparition de l'app cliente : le journal `Microsoft-Windows-TaskScheduler/Operational` est désactivé
  sur ce poste, aucun rapport d'erreur ni vidage mémoire n'existe pour elle.
- Le coût d'un **passage léger** (totaux processeur, graphique, mémoire, sans détail par processus) : il n'a pas été
  isolé. L'échantillon graphique impose une attente de 900 ms, donc il ne sera pas inférieur à environ une seconde.
