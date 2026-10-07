# Le verrou de l'historique ne couvrait qu'une session

Demandé par le propriétaire le 06/10, après avoir constaté qu'un historique abîmé ne dit rien : *« Il faut surtout
éviter les historiques cassés, si tu vois des raisons, mets des fixes, s'il faut mettre des locks dessus, fais-le. »*

## Ce qui a été trouvé

Le verrou existait déjà, et la purge le prenait correctement — ce point-là était sain. Mais il s'appelait
**`Local\VigieHistory_…`**.

Un verrou `Local` n'existe **qu'à l'intérieur d'une session Windows**. L'app serveur écrit depuis la session du
compte de service ; une app cliente, depuis celle de son compte. Chacune prenait alors un verrou **différent portant
le même nom** : elles ne se voyaient pas.

## Ce que ça risquait vraiment, et ce que ça ne risquait pas

**Je n'ai pas réussi à fabriquer une ligne déchirée avec l'ancien code**, et c'est une information en soi : deux
processus, deux verrous distincts, huit cents lignes de quatre cents caractères — **zéro ligne illisible**. La raison
est que `File.AppendAllText` ouvre déjà le fichier sans partage en écriture : une seconde écriture simultanée **lève**
au lieu d'écrire par-dessus. Le risque de l'ancien code était donc la **perte** d'une ligne, pas sa corruption.

**Ce qui reste dangereux et que je n'ai pas pu reproduire** : la purge **réécrit** le fichier entier et le remplace.
Si elle le fait depuis la session du service pendant qu'une app cliente ajoute depuis la sienne, les deux ne
s'attendent pas. C'est le seul chemin qui mélange réellement un contenu — et c'est précisément celui que le verrou de
machine ferme.

Et une coupure de courant en pleine écriture laissera toujours une ligne tronquée : c'est pour ça que la lecture doit
savoir l'écarter **et le dire**.

## Ce qui est en place

| | |
|---|---|
| **Verrou de machine** | `Global\VigieHistory_…`, avec un droit d'accès posé à la création — sans lui, une app cliente non élevée ne pourrait pas l'ouvrir et écrirait **sans aucun verrou**, ce qui serait pire. |
| **Une seule porte** | `Get-HistoryMutex` : plus aucun verrou construit à la main, les trois prises passent par elle. |
| **Écriture entière ou rien** | ouverture en ajout, écriture **exclusive**, un seul appel, cinq tentatives espacées. Une ligne perdue se compte ; une ligne à moitié écrite n'existe pas. |
| **Un fichier abîmé le dit** | la lecture rend `unreadable`, le nombre de lignes écartées. |

## Éprouvé

```
deux processus, deux verrous distincts, 1 000 lignes   -> 1 000 lisibles, 0 illisible
un fichier avec 1 ligne valide et 2 lignes de bruit    -> points : 1 | illisibles : 2
```

Le second remplace un silence : avant, ce fichier rendait **zéro point et rien d'autre**, soit exactement ce que rend
une mesure jamais relevée.
