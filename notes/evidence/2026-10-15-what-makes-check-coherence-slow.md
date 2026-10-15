# Ce qui rendait `check-coherence` long — et les deux optimisations qui ne paient pas

**15/10/2026.** `check-coherence` — avant sa scission, qui a eu lieu le même jour — prenait 7,5 s, la moitié du
coût d'une passe complète des seize vérificateurs (29 s). Demandé par le propriétaire : « tu vois que c'est anormalement long, tu dois établir un diag et soit
corriger soit le stocker pour le retrouver ensuite avec justification de pourquoi ce n'est pas corrigé. » Voici le
diagnostic, les deux corrections tentées, et pourquoi aucune n'est gardée.

## Le relevé, phase par phase

Mesuré sur une copie instrumentée du vérificateur, chronomètre entre chaque phase, dépôt entier :

| Phase | Ce qu'elle vérifie | Coût |
|---|---|---|
| 1 | une fonction n'est définie qu'une fois | 147 ms |
| 2 | une décision citée existe | 913 ms |
| 3 | les cercles de comptes ne sont pas refiltrés à la main | 601 ms |
| 4 | une variable ne porte pas le nom d'un paramètre | 998 ms |
| 5 | ce qu'une action rend à une personne ne vit pas chez le service | 66 ms |
| 6 | **un nom splaté que personne n'assigne** | **3 715 ms** |
| 7 | une concaténation dans une liste à virgules | 841 ms |

La sixième porte la moitié du temps. Elle est la seule à **analyser** chaque `.ps1` du dépôt — 153 fichiers, dont
`common.ps1` et ses 615 Ko — là où les phases 2, 3 et 4 se contentent de lire le texte.

## Première tentative : ne pas analyser les fichiers sans splat

L'idée : un test de texte avant l'analyse, pour ne parser que les fichiers qui contiennent un splat.

**Elle ne sélectionne rien.** 153 fichiers sur 153 portent un `@mot` hors de leurs commentaires — `@author` est
dans l'en-tête de chacun, et le motif raffiné (hors lignes de commentaire) ne change pas le compte. Mesuré avant
d'écrire une ligne de code : le filtre aurait coûté une lecture de plus par fichier pour n'en écarter aucun.

## Seconde tentative : partager l'arbre entre les phases 6 et 7

Les deux parcourent les mêmes fichiers et les analysaient chacune de son côté. Un cache `chemin -> arbre`,
quinze lignes, les deux phases y puisent.

**Aucun gain mesurable** : 7,5 s avant, 7,5 s après, sur deux passes chacune. Le second passage ne payait pas ce
que son chronomètre laissait croire — ses 841 ms ne sont pas une analyse mais le parcours et les recherches
qu'elle fait dans l'arbre. Le changement a donc été **retiré** : une complication qui ne gagne rien est une dette.

## Ce qui reste, et pourquoi on le garde tel quel

Les 7,5 s sont le prix d'**une** analyse de chaque `.ps1` du dépôt, et cette analyse est ce que la sixième phase
demande : on ne peut pas savoir qu'un `@nom` n'est jamais assigné sans lire la structure du fichier. Les deux
leviers visibles ont été mesurés et ne donnent rien.

Ce qui ferait réellement baisser ce coût est d'un autre ordre, et n'est pas fait aujourd'hui :

- **n'analyser que les fichiers modifiés** quand la passe est une validation de changement — c'est la question de
  conception ouverte le 15/10 sur `check-naming`, et elle vaut pour celui-ci. Elle demande que le vérificateur
  sache travailler sur une liste, pas seulement sur le dépôt ;
- **découper `common.ps1`** (11 791 lignes, 615 Ko) : un fichier qui pèse à lui seul une part notable de chaque
  analyse du dépôt. C'est un sujet à lui tout seul.

En attendant, le coût est connu, chiffré, et il se paie une fois par passe complète — que la sélection par
changement rend désormais rare.

## Ce qui a été fait ensuite, le même jour

Le propriétaire a tranché : **un vérificateur ne porte pas deux périmètres**. Les trois contrôles locaux sont
partis dans `check-file-coherence.ps1`, qui lit les fichiers qu'on lui donne ; `check-repo-coherence.ps1` garde
les quatre qui demandent le dépôt entier.

Ce que ça donne, mesuré : `check-repo-coherence` **2,1 s** (contre 7,5 s), `check-file-coherence` **0,5 s** sur
les fichiers touchés, la passe ordinaire **19 s** contre 29 s. Les 3,7 s de l'analyse ne se paient plus que sur
`-All`, où elles sont à leur place.

Ce qui reste vrai de ce relevé : les deux optimisations tentées ne paient toujours pas, et les deux vrais leviers
— ne lire que les fichiers modifiés, découper `common.ps1` — sont les mêmes.
