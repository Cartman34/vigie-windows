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
| **passe interne** | l'app serveur elle-même : minuteur, résidents, recalcul d'une sonde, relance |
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

## Ce qui n'est pas tenu

Les **passes internes** et les **tâches clientes** figurent dans l'inventaire et ne taisent aucune erreur. Mais elles
ne rejoignent **pas** les marques ni les résultats de `/operations` — et c'est un **écart au besoin**, pas une
question ouverte.

Cette page a longtemps écrit l'inverse : « n'est pas tranché… aucune demande ne le couvre encore ». C'était faux.
`features.md` → `CORE-OPERATIONS` dit **toute** opération de Vigie, synchrone ou asynchrone, et qu'une opération
asynchrone **se voit tant qu'elle dure, depuis toutes les pages ouvertes**. La passe interne figure dans cette même
page comme une famille d'opération à part entière. La demande était là depuis le début ; c'est la conception qui a
inventé une réserve.

**Ce que ça coûte aujourd'hui** : ce que Vigie décide elle-même — recalculer une carte, lire ce que WSL occupe,
relever les ports — n'apparaît nulle part. Si l'un de ces travaux se bloque, rien ne le montre, et la carte
concernée vieillit en silence. Constaté le 06/10 : il a fallu fouiller les journaux du compte de service, illisibles
depuis une session ordinaire, pour savoir pourquoi une carte restait grise.

Sujet **S14**.

## L'exception arbitrée

**La relance du serveur reste hors du protocole**, sans marque ni résultat : arbitré par l'utilisateur le 13/09. Son
travail arrête le processus même qui répond aux pages.
