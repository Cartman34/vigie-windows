# 25/10/2026 — Où va la mémoire de cet ordinateur, et ce que Vigie y prend

Relevé demandé par l'utilisateur : « Trouve où va toute la RAM occupée, ce n'est pas normal », puis « 571 Mo pour
Vigie, c'est beaucoup trop ». Deux questions, deux mesures, et elles ne se mélangent pas.

Machine : 32 492 Mo de RAM, démarrée le **20/10 à 05:47** — cinq jours sans redémarrage. **565 processus.**

## 1. L'ordinateur : 31 130 Mo occupés, et 53 493 Mo ENGAGÉS

La saturation n'est pas la RAM, c'est **l'engagement** : 53 493 Mo pour une limite de 56 099 Mo (RAM + fichier
d'échange). Il reste **2,6 Go** avant que Windows refuse une allocation.

Attribution par **octets privés** — la mesure qui ne compte pas deux fois les pages partagées :

| Processus | Nb | Octets privés |
|---|---|---|
| `vmmemWSL` | 1 | 7 137 Mo |
| `chrome` | 35 | 6 321 Mo |
| `phpstorm64` | 1 | 5 246 Mo |
| `dllhost` | 3 | 3 426 Mo |
| `ChatGPT` | 12 | 2 549 Mo |
| `Tabby` | 5 | 2 297 Mo |
| `claude` | 12 | 1 999 Mo |
| `explorer` | 3 | 1 901 Mo |
| `platform_runtime_RGB_service` | 2 | 1 547 Mo |
| `dwm` | 2 | 1 430 Mo |
| `msedgewebview2` | 20 | 1 085 Mo |
| `AvastUI` | 10 | 849 Mo |
| `svchost` | 105 | 787 Mo |
| `pwsh` | 5 | 714 Mo |

Noyau : **pool paginé 1 188 Mo**, **pool non paginé 1 126 Mo**, cache système 648 Mo.

**Ce qui est conforme à ce qui a été réglé** : `vmmemWSL` à 7,1 Go pour un plafond de 8 Go déclaré dans
`~/.wslconfig` (`memory=8GB`, `swap=4GB`, `autoMemoryReclaim=gradual`).

**Ce qui ne ressemble à rien de normal** — ce ne sont pas des applications ouvertes, ce sont des processus système
ou constructeur qui ont grossi pendant cinq jours :

- **`dllhost` : 3 426 Mo engagés pour 262 Mo réellement en RAM** (hôte COM, `{17696EAC-9568-4CF5-BB8C-82515AAD6C09}`,
  né le 20/10 à 15:49). Engagé et jamais touché : c'est ce genre d'écart qui remplit le fichier d'échange.
- **`explorer` 1 901 Mo** et **`dwm` 1 430 Mo** : un explorateur et un compositeur de bureau se tiennent
  d'ordinaire à 200-400 Mo.
- **`platform_runtime_RGB_service` 1 547 Mo** pour trois processus d'éclairage RGB.

**Les outils, pour mémoire** : `phpstorm64` seul à 5,2 Go, 35 processus Chrome à 6,3 Go, et les trois applications
d'IA de bureau (`claude`, `ChatGPT`, `msedgewebview2`) à **5,6 Go** à elles trois.

**Vigie n'y est pour rien** : 571 Mo sur 31 130, soit **1,8 %**.

## 2. Vigie : 571 Mo, et de quoi ils sont faits

| Processus | Mémoire | Depuis | Ce que c'est |
|---|---|---|---|
| `pwsh` 35264 | 310 Mo | 24/10 06:55 | l'app serveur (2 072 descripteurs, 38 fils) |
| `pwsh` 48436 | 112 Mo | 24/10 06:55 | l'app cliente du compte `fhaza` |
| `pwsh` 38328 | 106 Mo | 24/10 06:55 | l'app cliente du compte `Famille` |
| `pwsh` 64320 | 54 Mo | 24/10 06:56 | le résident du module Jeux |

**D'où vient le coût, mesuré en repartant de zéro** :

| Étape | Mémoire |
|---|---|
| `pwsh` nu, sans rien | **89 Mo** |
| après avoir chargé `lib/common.ps1` | **181 Mo** |
| après avoir chargé le module Pode | **221 Mo** |
| l'app serveur après 24 h de service | **310 Mo** |

Ce que ça dit, et c'est l'inverse de ce qu'on suppose :

1. **62 % de l'empreinte de Vigie est le moteur PowerShell lui-même** : 89 Mo × 4 processus = 356 Mo avant que la
   moindre ligne de Vigie soit lue.
2. **La bibliothèque coûte 92 Mo à charger** — elle double un `pwsh` nu. Cinquante-six morceaux, douze mille
   lignes, analysés et gardés en mémoire dans chacun des quatre processus.
3. **Pode coûte 40 Mo.**
4. **La croissance en 24 h de service est de 89 Mo** : il n'y a pas de fuite qui s'emballe, il y a un **plancher**
   de 221 Mo par processus serveur.

**Le levier n'est donc pas « trouver la fuite », c'est le nombre de processus PowerShell vivants** et ce que
chacun charge.

## 3. Ce que ce relevé a trouvé en passant

**Vigie n'enregistre pas sa propre mémoire en série.** Le module `debug` déclare la notification `vigie-memory` et
un seuil, mais aucune mesure : la carte alerte sur l'instant, et personne ne peut dire après coup si les 310 Mo
sont un plancher ou une pente. L'application qui surveille la mémoire des autres ne surveille pas la sienne.
