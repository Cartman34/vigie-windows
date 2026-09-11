# 2026-09-10 — Windows Update : seize orthographes pour douze constructeurs

**Preuve de D118.** L'utilisateur a signalé une liste de 49 mises à jour à plat et demandé
un regroupement par constructeur. La question qui a suivi — faut-il une table de
correspondance, ou une règle mécanique suffit-elle ? — a été tranchée sur ces mesures.

## Ce qui a été relevé

Recherche locale (`IsInstalled=0 And IsHidden=0`, `Online = $false`), lecture seule :

| | |
|---|---|
| Mises à jour en attente | 49 |
| Pilotes | 48 |
| Autres (correctif de sécurité) | 1 |
| Pilotes sans `DriverProvider` | **0** |

`DriverProvider` est donc renseigné partout, ce qui écarte l'idée de lire le constructeur
dans le titre. Et c'est heureux : les titres de pilotes commencent par le constructeur,
celui du correctif non — « Mise à jour de sécurité pour le package redistribuable Microsoft
Visual C++ 2008 Service Pack 1 (KB2538243) ». Lire le nom dans le texte aurait marché
**quarante-huit fois sur quarante-neuf**, la pire proportion possible.

## Les orthographes brutes, telles quelles

```
INTEL                        13      Realtek                       3
Lenovo                        6      Realtek Semiconductor Corp.   3
Intel Corporation             5      A-Volute                      2
Elevoc Technology Co.,Ltd     3      Microsoft                     2
Intel(R) Corporation          3      ASIX                          1
Nahimic                       3      Microsoft Corporation         1
                                     NVIDIA / SunplusIT / Tobii AB 1 chacun
```

**Seize orthographes pour douze constructeurs.** Intel éclaté en trois piles pour vingt et
une mises à jour, Realtek en deux, Microsoft en deux.

## Ce que chaque étage replie

| Étage | Groupes restants |
|---|---|
| Aucun traitement | 16 |
| Repli mécanique seul (majuscules, ponctuation, suffixes de forme juridique en fin de nom) | 12 |
| Repli mécanique + table écrite | **11** |

Le repli mécanique fait donc **l'essentiel** : quatre groupes sur cinq. La table n'a servi
qu'à un seul rapprochement, `Nahimic` et `A-Volute` vers `SteelSeries` — deux noms
qu'aucun traitement de texte ne rapprochera jamais.

**C'est ce rapport-là qui justifie l'ordre des deux étages** (D118) : si la table avait dû
absorber les quinze cas, elle aurait été une liste à maintenir déguisée en solution.

## Doublons de modèle relevés au passage

Quatre paires, deux versions du même pilote proposées ensemble :

- `Microsoft` — XBOX 360 Controller For Windows (2009-04-08 et 2009-08-13)
- `Intel Corporation` — Intel(R) UHD Graphics
- `Lenovo` — Universal Device Client Device
- `Elevoc` — Elevoc Device Extension

**Traité le soir même**, l'utilisateur ayant vu la paire Elevoc à l'écran et demandé si
c'était bien deux versions de la même chose. Ce que la mise en œuvre a appris :

- **Grouper sur le modèle seul est faux.** `Intel(R) UHD Graphics` apparaît deux fois à la
  **même date**, une fois en classe `Display` et une fois en `Extension` : deux composants
  d'un même appareil, pas deux versions d'un composant. Le premier jet marquait l'un des
  deux comme ancien, ce qui était simplement faux.
- **La règle retenue** : même constructeur, même modèle **et même classe**, et les dates
  doivent réellement différer. Trois paires marquées sur les quatre relevées le matin ; la
  quatrième, celle d'Intel, n'en était pas une.

**Et un faux doublon qui n'en était pas un du tout.** L'utilisateur a aussi signalé trois
lignes `Nahimic - MEDIA - 2.0.5.0`, `1.1.4.0` et `2.0.4.0`, qui se lisent comme une même
chose proposée trois fois. Ce sont **trois appareils distincts** — `Nahimic mirroring
device`, `Nahimic VAD`, `Nahimic Easy Surround device` — dont le titre Windows porte la
**version** là où les autres constructeurs mettent le modèle. La ligne porte désormais le
**modèle** comme titre, et le titre de Windows descend dans le détail, où la version qu'il
contient reste lisible.

**Ce qui n'a PAS été vérifié** : la règle n'a été éprouvée que sur ces 49 mises à jour. Un
constructeur qui laisserait `DriverClass` vide ferait tomber deux composants distincts dans
la même clé, et rien n'a montré ce cas ici.

## Ce qui n'a pas été vérifié

- Le comportement sur une machine où `DriverProvider` serait vide — zéro cas ici, donc le
  repli « Pilotes sans constructeur déclaré » n'a jamais été emprunté pour de vrai.
- Le poids total annoncé par groupe (2,5 Go dont 801 Mo pour NVIDIA) n'a pas été comparé à
  ce que Windows télécharge réellement : `MaxDownloadSize` vaut 0 sur une mise à jour déjà
  téléchargée.

## Suite du 11/09 — ce que Windows Update déclare des dépendances

**Question de l'utilisateur** : « y'en a pas qui dépendent d'autres ? qu'il faut installer
avant ou après ? » Relevé sur les mêmes 49, hors ligne, en lecture seule :

| Ce qui est déclaré | Sur les 49 |
|---|---|
| obligatoires (`IsMandatory`) | 0 |
| exigeant un redémarrage (`RebootRequired`) | 0 |
| licence non acceptée (`EulaAccepted` faux) | 0 |
| contenant un paquet fils (`BundledUpdates`) | 1 |
| en remplaçant d'autres (`SupersededUpdateIDs`) | 1 |
| en installation optionnelle (`DeploymentAction` = 4) | 4 |

**L'interface n'expose aucun graphe de prérequis.** Il n'existe pas de champ « installer
celle-ci d'abord » : l'ordre est l'affaire de l'installateur de Windows, à qui l'on remet la
collection choisie. La seule qui en remplace d'autres est le correctif Visual C++ 2008, et
les deux qu'elle remplace ne sont plus dans la liste.

Les quatre en installation optionnelle sont la paire XBOX 360 et deux pilotes Lenovo — rien
qui recoupe les versions périmées, donc ce champ ne sert pas à les repérer.

## L'exclusion, et sa seule exception

**Arbitré par l'utilisateur le 11/09** : « Notre outil ne doit PAS bypasser la gestion de MAJ
à ce niveau, on ne doit pas casser la manière dont ça fonctionne. […] Si tu arrives à
déterminer que c'est deux versions de la même chose, oui, les anciennes sont exclues et on
prend la dernière. Mais on note si elle a un problème d'installation. »

Ce que ça donne sur la liste du jour : **46 lignes au lieu de 49**, trois versions périmées
retirées. L'exception : si la plus récente a **échoué à s'installer**, l'ancienne revient,
parce qu'elle est alors le seul chemin qui reste.

Éprouvé sur données construites, la branche d'échec ne pouvant pas se provoquer sur la
machine de l'utilisateur : l'ancienne disparaît, elle revient quand la récente a échoué, la
récente reste proposée malgré son échec, et un échec sur un **autre** modèle ne ressuscite
rien.

**Ce qui n'a PAS été vérifié** : aucune installation n'a été lancée, donc le relevé des
échecs par identifiant n'a jamais été écrit par le worker en conditions réelles. La lecture
est éprouvée, l'écriture ne l'est pas.
## Suite du 11/09 — le compteur trompeur, et sa cause

**Constat de l'utilisateur, captures à l'appui** : la carte annonçait `49`, la fenêtre de
choix `0 / 48`.

**Cause.** La liste était construite **deux fois**, et chaque copie appliquait sa propre
soustraction :

| | Ce qu'elle comptait | Ce qu'elle retirait |
|---|---|---|
| la sonde (carte) | le résultat de la recherche | les mises à jour déjà installées que Windows repropose |
| l'action (fenêtre) | le résultat de la même recherche | les versions périmées d'un même pilote |

Aucune des deux ne connaissait la règle de l'autre. Les deux nombres ne pouvaient donc pas
coïncider, et aucun n'était faux séparément — c'est exactement le cas que la discipline
« on factorise avant de recopier » décrit.

**Correction.** `Get-PendingUpdateList` fabrique la liste une seule fois, applique les deux
règles, et rend ce que Windows détecte **et** ce que Vigie propose. La sonde et l'action la
lisent. Relevé après correction :

| | |
|---|---|
| Windows détecte | 51 |
| Vigie propose | 48 |
| versions périmées écartées | 3 |
| déjà installées et reproposées | 0 |

Le libellé suit : `À installer` plutôt que `Détectées (non installées)`, un nombre dont on
avait retiré trois lignes ne pouvant pas s'appeler « détectées ». Et le guide dit les deux
nombres, avec la raison de l'écart.

**Ce qui n'a PAS été vérifié** : la branche « déjà installées et reproposées » vaut 0 sur
cette machine aujourd'hui. Elle vient de l'ancienne sonde et n'a pas été rejouée depuis le
regroupement — aucune installation n'ayant été lancée.
