# Les méthodes d'identification d'un jeu

Auteur : Florent HAZARD <f.hazard@sowapps.com>

Un fichier par méthode, **indépendante des autres**. Chacune reçoit un processus et répond
« c'est un jeu, parce que… » ou se tait. **Une seule qui parle suffit** : aucune n'est
complète, c'est leur réunion qui l'est.

Le nom du fichier porte son **rang**, qui est son **coût** : les méthodes s'exécutent de la
moins chère à la plus chère, et on s'arrête à la première qui répond.

    20-launcher.ps1   le parent est une boutique de jeux — l'information est déjà là
    30-gamebar.ps1    Windows l'a enregistré comme jeu — une lecture de registre
    40-platform.ps1   il est installé dans une bibliothèque de jeux — des chemins en mémoire
    50-markers.ps1    des marqueurs de jeu entourent l'exécutable — des accès disque

Contrat d'une méthode : `param($Process)` où `$Process` porte `Id`, `Name`, `Path`,
`ParentId`, `ParentPath`, `SessionId`, `Sid`. Elle rend **une phrase** qui dit pourquoi,
ou rien. Elle ne juge jamais sur le **nom** du fichier (D64), et n'écrit rien.

En ajouter une : déposer un fichier ici. Rien d'autre.

Cible : `doc/progress/targeting/gaming.md`, dans le dépôt (ce document ne part pas dans l'archive).
