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

**Non traité à ce stade.** La cible dit qu'on les marque sans les masquer ; ce n'est pas
codé. Si la question revient, c'est ici que se trouvent les cas réels pour l'éprouver.

## Ce qui n'a pas été vérifié

- Le comportement sur une machine où `DriverProvider` serait vide — zéro cas ici, donc le
  repli « Pilotes sans constructeur déclaré » n'a jamais été emprunté pour de vrai.
- Le poids total annoncé par groupe (2,5 Go dont 801 Mo pour NVIDIA) n'a pas été comparé à
  ce que Windows télécharge réellement : `MaxDownloadSize` vaut 0 sur une mise à jour déjà
  téléchargée.
