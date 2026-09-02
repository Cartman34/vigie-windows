# Les résidents — ce qui vit avec l'app serveur

Besoin : `features.md`, entrée `CORE-RESIDENT`. Voisin : [surveillance.md](surveillance.md), qui décrit les
sentinelles — un usage possible d'un résident, pas sa raison d'être.

## Le manque

Tout ce que Vigie fait aujourd'hui se déclenche : une requête, un minuteur, un bouton. Rien ne peut simplement
**rester en vie** aux côtés de l'app serveur — écouter, consommer, tenir un état. Le premier besoin qui l'exige est
l'abonnement aux démarrages de processus, mais il ne sera pas le dernier, et la mécanique ne doit rien supposer de ce
qu'on en fera.

## Ce qu'est un résident

Un composant **déclaré**, que l'app serveur arme à son démarrage et qui vit aussi longtemps qu'elle. Ce qu'il fait ne
regarde que lui : un abonnement, un écouteur, un consommateur de file, un préchauffage. Le mécanisme ne le sait pas et
n'a pas à le savoir.

## Son contrat

| | |
|---|---|
| **Déclaré** | comme le sont les sondes et les sentinelles, dans le `module.psd1` de son module |
| **Armé au démarrage** | par l'app serveur, seul processus permanent |
| **Arrêté avec elle** | aucun résident ne lui survit : un orphelin ne se voit pas et ne se tue pas |
| **Réarmé s'il meurt** | la boucle de veille qui existe déjà le vérifie à chaque passage |
| **Resynchronisé en s'armant** | s'il a un état à reconstruire, il le reconstruit alors — une **faculté**, pas une obligation |
| **Observable** | armé, mort, en erreur, depuis quand : une surveillance dont on ne sait pas si elle fonctionne ne vaut rien |

## Ce qu'il ne fait pas

- **Il ne parle à personne directement.** S'il produit un résultat, il l'écrit ; qui le lit — une sentinelle, une
  carte, personne — ne le concerne pas.
- **Il n'ouvre pas un second chemin.** Ce qu'il publie rejoint les mécanismes existants : c'est toujours la même
  comparaison qui journalise, historise et fait recalculer une carte.
- **Il ne se persiste pas hors du serveur.** Windows sait enregistrer des abonnements permanents, qui survivent au
  redémarrage et tournent hors de l'application : ils s'installent dans le dépôt du système, se désinstallent mal, et
  personne ne les voit. Le prix ne vaut pas le gain — un résident meurt avec l'app serveur, et se réarme avec elle.

## Ce que ça change pour ce qui existe

Rien. Les sentinelles continuent de relever à leur cadence ; une seule chose s'ajoute : une sentinelle peut désormais
**lire un état qu'un résident tient à jour** au lieu d'aller le chercher elle-même. Elle ne sait pas qui l'a écrit,
et reste le filet si le résident est mort.
