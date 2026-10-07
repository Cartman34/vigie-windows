# Le filet de la chaîne de mise à jour, et la purge des données — éprouvés

Trois cases de `implemented/components.md` portaient **non éprouvé** ou **non exécuté** depuis le 14/09. Elles sont
mesurées le 07/10, sans toucher à l'installation réelle ni aux données du poste.

## La restauration de la version précédente

C'est le filet de la chaîne de mise à jour : si un déploiement rate, c'est lui qui ramène l'installation d'avant.
La ligne disait « sert à la restauration ; une restauration, réussie ou non, la laisse en place », et rien ne
l'avait jamais exercé.

Éprouvé sur dossiers jetables, avec une sauvegarde d'un côté et une installation « cassée » de l'autre :

| Ce qui est éprouvé | Résultat |
|---|---|
| Le contenu de la sauvegarde | reposé à l'identique |
| Un fichier que seule la version ratée portait | retiré |
| `var/` du poste — les données, pas le code | **intact** |
| La sauvegarde elle-même après la restauration | toujours là |
| Une restauration dont la sauvegarde n'existe pas | **refusée avant** toute suppression |
| L'installation après ce refus | entière |

Le dernier point est le plus important et c'est celui qu'on n'aurait pas deviné : `Restore-Install` **vide** la
destination avant de recopier. Si le refus arrivait après ce vidage, une restauration impossible laisserait une
installation vide et rien pour la remplir. Le contrôle passe bien **en premier**.

## La purge des données du service

`service-data-reset` existe depuis le 14/09 et n'avait **jamais été exécuté**. Lancé sur le dos de développement,
jamais sur l'installation partagée :

| Partie demandée | Résultat |
|---|---|
| `cache` | 18 éléments supprimés, `ok` |
| `history` | 12 éléments supprimés, `ok` |
| une partie inconnue | **refusée** : « cache » ou « history » attendu |

Et la condition que la conception pose : **`var/run` est resté intact**, ses trois marques en place. Une opération
en cours reste donc visible pendant une purge — ce qui est la raison d'être de cette exception.

Les données de développement ont été remises après la mesure, et une sonde relue ensuite rend ses invariants.

**Ce que ça ne dit pas** : la purge n'a pas tourné sur l'installation partagée, sous le compte du service. Le
mécanisme est le même — c'est le même fichier, appelé avec le même paramètre — mais les droits ne le sont pas.
