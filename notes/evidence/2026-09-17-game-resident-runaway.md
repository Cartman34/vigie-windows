# Le résident des jeux qui se multiplie — 17/09/2026

## Ce qui a été observé

L'utilisateur signale des ralentissements vers 11 h, des défauts d'affichage dans Tabby, et une seule alerte de Vigie :
« serveur injoignable ».

| Source | Constat |
|---|---|
| journal Système, 10:46:20 | `Tcpip` 4266 : plus aucun port UDP éphémère libre |
| journal Système, 10:49:04 | `Win32k` 704 : échec d'allocation de mémoire du Bureau pour `conhost.exe` |
| journal Système, 10:57:23 | `Tcpip` 4231 : plus aucun port TCP éphémère libre |
| mémoire, vers 11 h 30 | 61,4 Go engagés sur 64,1 Go ; 2 Go de mémoire vive libre sur 31,7 |
| processus, vers 11 h 30 | 116 `pwsh` et 118 `conhost` dans la session 0 ; 115 `pwsh` enfants de l'app serveur (PID 2696, lancée le 16/09 à 17 h 54), **19,2 Go** de mémoire privée |
| app cliente, 10:39 à 11:04 | cinq fois « serveur coincé (port ouvert, health muet) » |
| app serveur | un recalcul de fond de la sonde des jeux en 1 430 s, de la sonde des paquets en 141 s |

Les réarmements du résident « Détection des jeux », comptés dans `state_20260917.log`, et les `pwsh` de la session 0
lancés la même heure :

| Heure | 6 h | 7 h | 8 h | 9 h | 10 h | 11 h |
|---|---|---|---|---|---|---|
| réarmements | 3 | 5 | 16 | 46 | 59 | 33 |
| `pwsh` lancés, encore vivants | 2 | 5 | 12 | 46 | 50 | — |

La veille, de 15 h à 23 h, un réarmement toutes les deux heures environ.

## Après la relance de l'app serveur, 11 h 37

L'ancienne app serveur est arrêtée, la nouvelle écoute. **111 copies restent vivantes**, rattachées au PID disparu ; la
nouvelle app serveur en a relancé 2 en quatre minutes. Mémoire libre : 0,2 Go.

## Ce que cela montre

- L'app serveur réarme le résident quand son battement a plus de 180 s, en tuant le processus inscrit dans son état.
  Chaque copie réécrit **son propre** numéro dans ce même état toutes les 5 s : une seule copie est tuée, les autres
  survivent.
- Chaque copie s'abonne aux démarrages de processus de tout l'ordinateur : chaque nouvelle copie réveille toutes les
  autres, qui ralentissent, battent en retard, et font réarmer une copie de plus.
- Le balayage initial de tous les processus ne bat pas : sur une machine lente, il dépasse 180 s à lui seul.
- Une copie ne vérifie la vie de l'app serveur qu'en tête de sa boucle : bloquée plus haut, elle ne s'arrête pas.

## La correction, en deux temps

Le 17/09, l'app serveur a d'abord été corrigée pour arrêter toute copie avant d'en armer une : un correctif de
symptôme, et un arrêt de processus sans confirmation, ce que l'utilisateur a interdit le 18/09. La cause est le
réarmement lui-même : **un processus lent était traité comme mort**. Depuis le 18/09, un résident n'est réarmé que si
son processus a disparu ; lent ou doublé, il est signalé avec ses raisons, et Vigie n'arrête plus aucun processus.

## Ce qui n'a PAS été vérifié

- La part des ports épuisés tenue par les copies, et celle de l'hôte réseau de WSL, qui en tenait 10 426 le 14/09.
- Le lien entre la mémoire du Bureau épuisée et les défauts d'affichage de Tabby.
- Ce qui a lancé le premier réarmement de la matinée.
