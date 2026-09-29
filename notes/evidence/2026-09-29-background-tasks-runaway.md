# Quand Vigie s'est emballée sur sa propre machine — 29/09/2026

Relevé pour **D126** (un plafond dur sur ce que Vigie lance). Tout ce qui suit a été mesuré sur ce poste, pendant
l'incident et juste après.

## Ce qui s'est passé

En livrant l'ordonnanceur (D124/D125), j'ai rendu le verrou de recalcul **par sonde**. Le garde-fou qui empêchait une
tâche de fond d'en lancer une autre, lui, testait le verrou **global** — lequel n'existait plus jamais. Chaque tâche de
fond en lançait donc une nouvelle, qui en lançait une autre.

| Moment | Ce qui était mesuré |
|---|---|
| 11:01 | déploiement de la version fautive |
| 11:08 | 79 processus `pwsh`, tous élevés, du compte `VigieService` |
| 11:14 | 112 processus |
| 11:16 | **161 processus**, 55 % de processeur, **0,3 Go de RAM libre** |
| 11:16 | l'app serveur ne répond plus : 400, puis 408 sur son API |
| 11:20 | l'app serveur n'arrive plus à écouter son port après un redémarrage |
| 11:36 | arrêt des `pwsh` de `VigieService`, en six passes, sous élévation |
| 11:38 | 26 processus, puis 1 |
| 11:48 | correctif installé (v1.1.6+59) |
| 11:51 | **6 processus**, carte « Processus de Vigie » au vert |

**Arrêter la tâche du serveur n'a pas suffi** : la chaîne se nourrissait d'elle-même, chaque tâche de fond en lançant
une autre sans passer par le serveur. Le nombre continuait de monter, serveur arrêté.

## Ce qui a été posé

1. **Une tâche de fond ne lance jamais une tâche de fond** : `Start-DetachedAction` marque ses enfants
   (`VIGIE_NO_BACKGROUND`), et `Get-State` ne délègue pas quand cette marque est là.
2. **Un plafond dur, qui REFUSE** : `Refresh.MaxChildren` (8 par défaut). Chaque processus lancé est inscrit dans
   `var/run/children.json`, les morts sont oubliés à chaque passage, et au-delà du plafond le lancement est refusé,
   journalisé en erreur. Refuser de démarrer suffit : rien n'est arrêté par ce mécanisme.
3. Le garde-fou de délégation teste désormais le verrou **de la sonde concernée**, le seul qui dise quelque chose.

Éprouvé le 29/09 : avec neuf enfants déclarés vivants, `Start-DetachedAction` refuse et écrit
« lancement REFUSE : 9 taches de fond vivantes, plafond 8 ».

## Ce qui n'est PAS vérifié ici

- Le plafond n'a pas été éprouvé **en situation réelle** d'emballement : il a été éprouvé en lui présentant une liste
  d'enfants fabriquée.
- La valeur 8 est un choix, pas une mesure : elle vaut le double de ce que Vigie lance en marche normale (2 à 4).
