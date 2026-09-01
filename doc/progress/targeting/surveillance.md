# Surveillance permanente — des relevés, des événements, puis des cartes

Arbitrages : **D54** (une notification est un événement nommé), **D48** (un module se déclare), **D57** (les réglages
d'un module vivent dans son `module.psd1`).
Besoin : `features.md`, entrée `CORE-WATCH`. État : `../implemented/identity.md`.

## Le manque

Un recalcul n'a lieu que si quelqu'un demande quelque chose. Fermez toutes les sessions : plus rien n'est mesuré, donc
aucune notification ne peut partir, et la première page ouverte le lendemain sert les mesures de la veille.

## Ce qu'on veut, et ce qu'on ne veut pas

**On ne veut PAS recalculer des cartes en boucle.** Une carte coûte cher — la carte Déploiement met treize secondes —
et la plupart de ce qu'elle contient ne bouge pas dans la minute.

**On veut RELEVER en permanence quelques faits précis, bon marché**, déclarés par chaque module : « Internet
répond-il ? », « le verrou des tâches tient-il ? », « le service tourne-t-il ? ». Quand un relevé **change**, il émet un
**événement**, et c'est cet événement qui fait recalculer **les cartes que le module a désignées**.

Un relevé qui ne change pas ne coûte rien de plus qu'une lecture.

## Le schéma

```
                        app serveur (compte de service, tourne depuis le démarrage)
                        ┌──────────────────────────────────────────────────────────┐
   toutes les minutes → │  BOUCLE DE VEILLE                                        │
                        │    pour chaque relevé DÛ (cadence dépassée) :            │
                        │      ┌────────────────────────────────────────────┐      │
                        │      │  <clé>.watch.ps1   → une valeur comparable │      │
                        │      └────────────────────────────────────────────┘      │
                        │                    │                                     │
                        │        valeur identique ?  ──── oui ──→ rien             │
                        │                    │                                     │
                        │                   non                                    │
                        │                    ↓                                     │
                        │            ÉVÉNEMENT « <clé> a changé »                  │
                        │                    ↓                                     │
                        │      Get-State -Only <sonde des cartes déclarées>        │
                        │            (le chemin existant, pas un autre)            │
                        └──────────────────────────────────────────────────────────┘
                                             ↓
                                    cache d'état mis à jour
                                             ↓
                        ┌────────────────────┴─────────────────────┐
                        ↓                                          ↓
                 app cliente                                   panneau
          (lit l'état chaque minute)                  (sondage régulier /state)
                        ↓                                          ↓
          bascule d'un champ → notification            la carte affiche la nouvelle valeur
                    (D54, inchangé)
```

Ce que le schéma dit, et qu'il faut retenir : **la boucle ne calcule pas de carte**. Elle relève, elle compare, et
c'est le *changement* qui déclenche un recalcul — par le chemin que tout le monde emprunte déjà.

## Comment un module déclare un relevé

Dans son dossier, un fichier `<clé>.watch.ps1` : il fait UNE lecture bon marché et rend UNE valeur comparable — un
booléen, un nombre, une chaîne courte. Rien d'autre : pas de carte, pas de champ, pas de mise en forme.

Dans son `module.psd1`, la clé `Sentinels` dit la cadence et ce que l'événement doit faire recalculer :

    Sentinels = @(
        @{ Key = 'internet'; Label = 'Connexion Internet'; Seconds = 60; Cards = @('net') }
    )

| | |
|---|---|
| `Key` | le nom du relevé — c'est aussi le nom du fichier `<clé>.watch.ps1` |
| `Label` | ce qu'on lit dans le journal quand l'événement part |
| `Seconds` | à quelle cadence relever. Ce qui coupe : 60. Ce qui dérive : 900. |
| `Cards` | les cartes à recalculer quand la valeur change — celles du module, personne d'autre |

## Ce que fait la boucle

Une fois par minute, dans l'app serveur — elle tourne déjà sous son compte de service, sans session :

1. elle prend les relevés **dus** (dernier relevé plus vieux que leur cadence) ;
2. elle exécute chacun — c'est bon marché, c'est la condition pour que ce soit permanent ;
3. **si la valeur a changé**, elle journalise l'événement et fait recalculer les cartes déclarées, **par le chemin
   existant** : `Get-State -Only <sonde>`, celui qu'utilisent déjà le bouton d'une carte et le rafraîchissement de fond ;
4. sinon, elle ne fait rien de plus.

Elle se tait pendant une **installation** (le verrou d'installation le dit) : les fichiers changent sous ses pieds.

## L'historique d'une sentinelle

La mémoire de veille ne garde qu'**un** état par sentinelle : elle répond à « où en est-on ? », jamais à « depuis
quand ? » ni « combien de fois cette nuit ? ». Chaque changement fait donc **une ligne d'historique**, à côté des séries
des sondes et par le même mécanisme — l'historique prévoyait déjà cette nature-là, l'`event` : une valeur qui ne
s'écrit **que quand elle change**.

Une ligne porte l'état atteint, celui d'où l'on vient, et **les cartes que le changement a fait recalculer** : c'est ce
qui distingue une valeur d'une **alerte**. Le tout premier relevé est noté aussi, sinon la série commence dans le vide.

    watch.internet   « oui » → « non » à 03 h 12, carte « net » recalculée
                     « non » → « oui » à 03 h 14, carte « net » recalculée

Une sentinelle peut aussi **compter par paliers** plutôt que basculer : `game-battery` rend `non`, puis `baisse-10`,
puis `baisse-15`… Chaque palier franchi est un changement, donc un événement, donc une alerte. Sans paliers, une
batterie qui se vide pendant une partie n'aurait prévenu qu'**une fois**, au premier point de bascule.

Rien de neuf en dessous : même dossier de données, même purge, même route de lecture que les autres mesures. Une
sentinelle porte l'identifiant de mesure `watch.<clé>`.

## Ce que l'historique pèse, et pourquoi il ne dérive pas

Un fichier **par mesure et par jour** : `var/history/<mesure>/<AAAA-MM-JJ>.jsonl`. Ce découpage n'est pas un rangement,
c'est ce qui rend la **purge gratuite** — supprimer des fichiers dont le nom porte la date, sans rien relire. Avant, la
purge lisait tout, analysait chaque ligne et réécrivait le fichier entier, sous verrou.

Quatre règles, de la plus efficace à la dernière :

1. **On ne garde que les retournements.** Quand un point arrive, le **précédent** devient jugeable : s'il se situe entre
   l'avant-dernier et celui qu'on écrit, il est sur la ligne qui les joint — il se déduit, on l'efface. Ne restent que
   les **extrêmes des fluctuations**, qui portent toute la forme de la courbe et ses records.

   La décision se prend **en regardant en arrière**, à l'écriture : aucun retard, aucune seconde passe, et la journée en
   cours reste juste à la seconde près. Effacer ne coûte rien — on tronque le fichier à l'offset de sa dernière ligne.

   Deux gardes : la **tolérance** déclarée par la mesure (5 points de GPU, 1 Go d'espace, 5 ms de latence) — un demi-tour
   plus petit qu'elle n'en est pas un, un GPU qui oscille entre 22 et 25 % ne raconte rien ; et le **battement de cœur**,
   qui interdit d'effacer si cela creusait un trou de plus de quinze minutes, sinon « stable » ne se distinguerait plus
   de « plus rien ne mesure ».

   Éprouvé : une série de 14 points (10, 12, 15, 20, 25, 30, 28, 22, 24, 23, 25, 40, 39, 5) se réduit à **5** —
   10, 28, 25, 39, 5.
2. **On ne réécrit jamais la même valeur**, et **une cadence minimale** par mesure borne le débit par construction.
3. **Les événements ne se compactent pas** : une sentinelle n'écrit que des changements d'état, et « entre deux » n'a
   aucun sens pour un état.
4. **Un plafond de taille**, en dernier filet : au-delà de 5 Mo pour une journée, la mesure se **bride** à une ligne par
   minute — elle ne se tait pas, se taire à midi rendrait aveugle sur l'incident de l'après-midi — et le journal le dit.
   Avec les règles précédentes, ce filet ne devrait jamais servir : s'il se déclenche, c'est un **défaut**.

## Ce que ça n'est pas

- **Pas un second chemin de recalcul.** Le recalcul passe par `Get-State -Only`, comme le reste.
- **Pas un doublon des notifications (D54).** L'événement fait recalculer ; la notification, elle, naît de la bascule
  d'un champ de carte, et ce mécanisme ne change pas. La boucle rend simplement les bascules **possibles** quand
  personne ne regarde.
- **Pas un réglage de plus.** La cadence et les cartes sont déclarées avec le module, à côté de ce qu'elles décrivent.
