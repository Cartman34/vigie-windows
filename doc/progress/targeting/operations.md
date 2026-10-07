# Les opérations — un inventaire, un protocole

Besoin : `features.md`, entrée `CORE-OPERATIONS`. Arbitrages : **D82** (aucune tâche de fond n'échoue en silence),
**D94** (une opération en cours ne s'efface pas), **D95** (ce qui tourne se voit depuis toutes les pages), **D102**
(une opération en cours fige l'écran qui la montre). Constat qui a fait écrire ce plan : [2026-09-12-operations-outside-the-protocol.md](../../../notes/evidence/2026-09-12-operations-outside-the-protocol.md).

État réel, opération par opération : [../implemented/operations.md](../implemented/operations.md).

## Ce qu'est une opération

Tout ce que Vigie **exécute**, qu'on le lui demande ou qu'elle le fasse d'elle-même :

| Famille | Qui la déclenche |
|---|---|
| **action** | un bouton, un dialogue, l'app cliente ou un script, par `POST /actions` |
| **écriture par l'API** | une route qui modifie un réglage, un compte ou un accès |
| **tâche de veille** | l'app serveur elle-même, sur son minuteur : sentinelles, résidents, recalculs dus, disque, WSL, ports |
| **tâche cliente** | l'app serveur, qui confie à l'app cliente ce qui a besoin d'une session |
| **installation** | une personne ou le bouton de mise à jour ; séquence dans [install-update.md](install-update.md) et [uninstall.md](uninstall.md) |

Une opération est **synchrone** quand son résultat est dans la réponse. Elle est **asynchrone** quand le travail
continue après la réponse. Ce n'est pas une affaire de temps : une opération synchrone peut attendre une mesure de
plusieurs secondes, une asynchrone peut finir en une.

## L'inventaire

1. **Toute opération figure dans l'inventaire**, `implemented/operations.md`, avec le fichier où elle vit, ce qui la
   déclenche, son mode au sens ci-dessus et la manière dont elle se lance.
2. **L'inventaire se tient mécaniquement.** Un vérificateur refuse l'écart dans les deux sens : une action ou un
   lancement présent dans le code et absent de l'inventaire, une ligne d'inventaire qui ne désigne plus rien.
3. **On cherche une opération dans l'inventaire**, pas dans le code. Le code confirme ; il ne sert pas à découvrir.

## Le protocole des opérations asynchrones

Un seul, pour toutes. Il n'en existe pas de variante « légère ».

1. **Une seule fonction de lancement**, pour un worker PowerShell comme pour un programme externe. Une action ne crée
   jamais de processus détaché elle-même.
2. **La marque d'occupation existe avant la réponse de l'action**, et porte le numéro du processus qui fait le travail.
   La page qui reçoit la réponse voit donc l'opération en cours, jamais une opération déjà finie.
3. **Toute fin écrit un résultat** : réussite, échec, exception, arguments invalides, échec au chargement de la
   bibliothèque. Aucune sortie du worker ne se fait sans lui.
4. **Un processus disparu sans résultat est un échec**, affiché comme tel : « arrêtée sans rendre de résultat ». Sa
   marque ne s'efface jamais en silence.
5. **L'état d'une opération se lit à un seul endroit** : marques et résultats, servis par `/operations`. Aucun fichier
   d'état propre à une opération ne dit « en cours », et aucune opération n'a sa propre règle d'abandon.
6. **Le verrou de ressources vaut pour toutes**, puisqu'il lit ces mêmes marques.
7. **« Lancée » n'est pas une réussite.** La réponse d'une opération asynchrone s'affiche comme un départ. La réussite
   vient du résultat, et de lui seul.
8. **Le détail du travail reste libre.** Une opération peut publier sa progression, ses titres, ses échecs par élément.
   Elle le fait en plus du protocole, jamais à sa place.

## À l'écran, toutes pareilles

Toute opération se présente de la même manière, synchrone ou asynchrone : **lancée, en cours, terminée**, en réussite
ou en échec. Ce qui diffère derrière, un résultat dans la réponse ou un travail qui continue, ne se voit pas à l'écran.

## Les opérations synchrones

- **Un échec rend `ok = false`**, jamais une réussite polie, et l'audit le trace comme un échec.
- **Une opération synchrone ne lance rien qui lui survive.** Si le travail continue après la réponse, l'opération est
  asynchrone, et le protocole s'applique.

## Ce qui est tenu depuis le 07/10

Les **tâches de veille** et les **tâches clientes** figurent dans l'inventaire, ne taisent aucune erreur, et
rejoignent les marques et les résultats de `/operations` — **fait le 07/10**. Ce fut longtemps un **écart au
besoin**, présenté à tort comme une question ouverte.

Cette page a longtemps écrit l'inverse : « n'est pas tranché… aucune demande ne le couvre encore ». C'était faux.
`features.md` → `CORE-OPERATIONS` dit **toute** opération de Vigie, synchrone ou asynchrone, et qu'une opération
asynchrone **se voit tant qu'elle dure, depuis toutes les pages ouvertes**. La tâche de veille figure dans cette même
page comme une famille d'opération à part entière. La demande était là depuis le début ; c'est la conception qui a
inventé une réserve.

**Ce que ça coûtait** : ce que Vigie décide elle-même — recalculer une carte, lire ce que WSL occupe, relever les
ports — n'apparaissait nulle part. Si l'un de ces travaux se bloquait, rien ne le montrait, et la carte concernée
vieillissait en silence. Constaté le 06/10 : il a fallu fouiller les journaux du compte de service, illisibles
depuis une session ordinaire, pour savoir pourquoi une carte restait grise.

Sujet **S14**.

## La conception retenue

Écrite le 07/10, avant le code, à la demande du propriétaire : *« Ta conception doit être solide… prévois tous les
cas… pense code maintenable, architecture hexagonale, SOLID, DRY. La sécurité, les performances et l'optimisation
sont importantes aussi. »*

### Le principe : une tâche de veille EST une opération, pas une nouveauté

Il existe déjà un mécanisme complet pour « ce qui tourne » : une **marque** posée avant, un **résultat** écrit
après, `/operations` qui sert les deux, et une page qui les affiche. Une tâche de veille n'a besoin d'**aucun** de ces
éléments en double. Elle entre dans le mécanisme existant par un espace de noms réservé : `pass:<nom>`.

Rien de neuf n'est donc créé : pas de fichier, pas de route, pas de lecteur, pas de code d'interface.

### Une seule porte : `Invoke-WatchTask`

```
Invoke-WatchTask -Name 'sentinels' -Label 'Relevé des sentinelles' -MaxSeconds 30 -Body { ... }
```

Le corps de la tâche **ne sait rien** de la marque : il mesure, il calcule, il rend. C'est l'enveloppe qui pose,
efface et juge. Ajouter une tâche de veille demain, c'est l'entourer de cette fonction — et rien d'autre. Une seule
responsabilité, un seul endroit à corriger, et le jour où la détection change, elle change une fois.

### Ce qui s'écrit, et ce que ça coûte

| Quand | Ce qui est écrit |
|---|---|
| au départ du tour de veille | **une** marque, ~150 octets, réécrite sur place |
| à chaque tâche qui dépasse **1 s** | le nom de la tâche dans cette même marque |
| à la fin du tour | la marque est effacée |
| quand une tâche dépasse son plafond | **un** résultat, une seule fois par occurrence |

Soit **deux écritures par tour de trente secondes** en régime normal — 5 760 par jour, d'un fichier de 150 octets.
Une tâche rapide n'écrit rien de plus. C'est le prix minimal pour qu'un blocage soit visible : sans marque, il n'y a
rien à regarder.

### Le blocage est constaté par le LECTEUR, pas par l'écrivain

C'est le point qui fait tenir le reste. Si une tâche de veille se bloque, la minuterie est bloquée avec elle : **rien dans ce
processus ne peut plus rien signaler**. La détection ne peut donc pas y vivre.

`Get-RunningOperations` tourne dans la requête HTTP, qui est un autre fil d'exécution. Elle lit la marque, compare
son heure de départ au plafond déclaré, et conclut. Une tâche bloquée se voit même quand tout le reste est figé.

### Les marques orphelines s'effacent seules

La marque porte le numéro de processus du serveur. `Get-ModuleBusyMark` efface déjà, à la lecture, une marque dont
le processus a disparu. Un serveur qui redémarre après un arrêt brutal a un numéro neuf : l'ancienne marque s'en va
au premier regard. Aucun nettoyage à écrire, aucun orphelin possible.

### Une tâche de veille ne bloque aucun bouton

Elle ne mobilise rien : sa liste de ressources est vide. **Mais la page doit cesser de croire qu'une liste vide veut
dire « on ne sait pas »** — elle appliquait alors le repli « on bloque tout ». Ce repli datait d'un temps où les
marques ne déclaraient pas leurs ressources ; elles le font depuis le 06/10. Il est retiré : **une opération qui ne
déclare rien ne retient rien**.

Sans cette correction, chaque tour de veille gèlerait l'interface pendant qu'il dure.

### Les plafonds, déclarés par passe

Chacun vient de ce que la passe fait, pas d'un chiffre rond : la mesure des paquets attend une tâche cliente avec un
délai de 60 s, elle ne peut pas tenir en 10.

| Tâche de veille | Plafond | Pourquoi |
|---|---|---|
| résidents | 10 s | lit des processus, ne calcule rien |
| app clientes | 10 s | lit des tâches planifiées |
| sentinelles | 30 s | peut forcer le calcul d'une carte (30 s d'attente) |
| ordonnanceur | 10 s | ne fait que lancer des workers |
| disque | 5 s | lit l'espace libre et un historique |
| WSL | 25 s | tâche cliente, délai de 20 s |
| paquets | 65 s | tâche cliente, délai de 60 s |
| ports | 5 s | une lecture de 15 ms, plus un journal au plus toutes les 5 min |

### Sécurité

La marque est écrite par l'app serveur dans son propre `var/run`, et lue par `/operations`, déjà authentifiée. Le
nom d'une passe est une **constante déclarée dans le code**, jamais une entrée : aucun chemin ne se compose à partir
de ce que quelqu'un envoie. Ce qui est exposé en plus : un nom de tâche et une heure de départ.

### Ce qui s'affiche

**Tant que tout va bien, rien.** Le cycle revient toutes les trente secondes : afficher chaque tâche ferait
apparaître quelque chose en permanence dans « ce qui tourne », pour une information que personne ne regarde. La
marque existe — c'est elle qui permet de voir un blocage — mais `/operations` ne la publie qu'au-delà du plafond.

**Une tâche qui dépasse son plafond apparaît**, avec son nom et depuis combien de temps, exactement comme une
opération lancée par un bouton.

**Et elle remonte à l'utilisateur.** Règle de base du produit, rappelée par le propriétaire le 07/10 : *« Toutes les
erreurs remontent à l'utilisateur, une règle de base, elle doit être appliquée partout. »* Une tâche bloquée veut
dire qu'une partie de Vigie ne fonctionne plus et que les cartes qu'elle alimente vieillissent en silence : elle
produit donc **une bulle, une seule par blocage**, soumise comme les autres aux réglages de notification et au répit
de dix minutes (D54, S10). Ce n'est pas envahissant : c'est une fois, et seulement quand quelque chose est cassé.

**Le détail vit sur la carte Débogage** : la liste des tâches de veille, leur dernier passage, leur durée. Visible
quand on cherche, invisible le reste du temps.

## L'exception arbitrée

**La relance du serveur reste hors du protocole**, sans marque ni résultat : arbitré par l'utilisateur le 13/09. Son
travail arrête le processus même qui répond aux pages.
