# Surveillance permanente — ce que Vigie mesure quand personne ne regarde

Arbitrages : **D54** (une notification est un événement nommé), **D48** (un module se déclare).
Besoin : `features.md`, entrée `CORE-WATCH`. État actuel : `../implemented/identity.md`.

## Le manque

Aujourd'hui, **un recalcul n'a lieu que si quelqu'un demande quelque chose**. Le rafraîchissement de fond est déclenché
par une requête ; l'app cliente en émet une par minute, ce qui l'entretient tant qu'une session est ouverte. Fermez
toutes les sessions, et plus rien n'est mesuré : aucune notification ne peut partir, et la première page ouverte le
lendemain sert des mesures de la veille.

C'est contradictoire avec ce que Vigie promet — surveiller — et avec les notifications, qui n'ont de sens que si
quelqu'un observe en continu.

## Ce qu'on veut

**L'app serveur surveille en permanence.** Elle tourne déjà sous son compte de service, sans session, au démarrage de
l'ordinateur : c'est le seul endroit d'où l'on peut observer quand personne n'est là.

| | |
|---|---|
| une boucle **dans l'app serveur** | pas un processus de plus, pas une tâche planifiée de plus |
| elle recalcule **une sonde à la fois** | jamais toutes ensemble — la règle ne change pas |
| elle choisit **la plus urgente** | urgence déclarée par le module, plus le retard accumulé |
| elle **ne bloque personne** | les requêtes continuent d'être servies pendant |
| elle **se tait** pendant une installation | le verrou d'installation la met en pause |

## L'urgence se déclare, elle ne se devine pas

Chaque module déclare dans son `module.psd1` à quelle cadence ses sondes méritent d'être revues **quand personne ne
regarde**. Trois niveaux, pas plus : au-delà, on invente des réglages que personne n'ajuste.

| niveau | cadence visée | pour quoi |
|---|---|---|
| `haute` | ~1 minute | ce qui coupe : connexion, service, verrou Windows Update |
| `normale` | ~15 minutes | ce qui dérive : espace disque, mises à jour en attente, sécurité |
| `basse` | ~12 heures | ce qui ne bouge presque jamais : version de Windows, comptes, matériel |

**Sans déclaration : `normale`.** Le silence ne doit ni réveiller la machine toutes les minutes, ni laisser une carte
dormir un jour entier.

**`aucune`** existe aussi, pour une sonde qui n'a de sens que sur demande — une mesure de débit consomme la ligne, elle
ne se lance pas toute seule.

## Comment la boucle choisit

À chaque tour — une fois par minute —, elle prend **la sonde la plus en retard par rapport à sa propre cadence**, et
elle en prend **une seule**. C'est le même classement que pour le rafraîchissement déclenché par une requête : la
règle est écrite une fois et sert aux deux.

Une sonde `aucune` n'entre jamais dans le classement.

## Ce que ça change pour les notifications

Elles deviennent **vraies**. Une coupure de connexion, un service arrêté, un verrou qui saute : constatés dans la
minute, même écran verrouillé. C'est ce que D54 décrit depuis le début et que le déclenchement par requête ne pouvait
pas tenir.

## Ce que ça ne doit pas devenir

- **Une machine qui chauffe.** Une sonde par minute, jamais deux à la fois : c'est le plafond, et il ne se règle pas.
- **Un second chemin.** La boucle appelle le même `Get-State -Only` que tout le reste ; elle ne recalcule rien elle-même.
- **Un bruit de fond.** Une notification reste un événement nommé, déclaré par le module, et ne se répète pas (D54).
