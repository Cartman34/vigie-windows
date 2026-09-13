# Le clone du service bloqué par des étiquettes déplacées — 13/09/2026

## Ce qui a été observé

La mise à jour de Vigie demandée le 13/09 à 8 h 00 a échoué au bout de 87 secondes. L'installation partagée est restée en
v1.0.15. Le journal du compte de service, récupéré par l'action `diag-account-logs`, s'arrête à la synchronisation :

| Ligne du journal | Contenu |
|---|---|
| Voie retenue | clone |
| Étape | Mise a jour du clone... |
| Erreur affichée | La recuperation a echoue : depot injoignable, ou reseau absent. |
| Code | 2 |

Avant l'échec, la mise à jour a posé l'étiquette `v1.1.1` sur `0ef705a` et l'a poussée sur GitHub.

| Mise à jour | Résultat |
|---|---|
| 11/09, 7 h 17 | réussie |
| 11/09, 10 h 37 | réussie |
| 11/09, vers 11 h 57 | réécriture de l'historique pour retirer les lignes de co-auteur : 32 étiquettes déplacées |
| 13/09, 8 h 00 | échec |

## La reproduction

Un clone fait depuis la sauvegarde d'avant la réécriture, `local/backup/avant-nettoyage-coauthor.bundle`, puis la même
commande que le service, `git fetch --quiet --tags --prune origin`, vers la source déclarée :

```text
 ! [rejected] v1.1.0     -> v1.1.0  (would clobber existing tag)
 * [new tag] v1.1.1     -> v1.1.1
fetch exit=1
```

Chaque étiquette déplacée est refusée, et git rend le code 1.

## Ce que cela montre

- `scripts/vigie-fetch.ps1` et `Sync-ServiceClone` récupèrent les étiquettes sans forcer : une seule étiquette déplacée
  bloque le clone pour toujours.
- L'erreur affichée invente une cause, « dépôt injoignable, ou réseau absent », au lieu du texte de git.
- Aucune action du serveur ne permet de réparer ou de réinitialiser le clone.
- Le clone a été créé le 30/08 (**D112**) sans réponse à cette situation.

## Autres pièces sans réponse, relevées dans le code le même jour

| Pièce | Situation sans réponse |
|---|---|
| source du journal d'événements `Vigie` | créée, jamais retirée par la désinstallation |
| droit « ouvrir une session en tant que tâche » du compte de service | accordé par `secedit`, jamais retiré |
| `var/log` | aucune purge trouvée ; les copies de diagnostic et les sauvegardes `.reg` s'y ajoutent |
| déclarations `safe.directory` | ajoutées à chaque source nouvelle, jamais retirées quand la source change |
| `SourcePath` de `machine.psd1` | peut désigner un dossier de travail qui disparaîtra, comme un worktree |

## Ce qui n'a PAS été vérifié

- **Le clone du service lui-même** n'a pas été lu : le profil du compte de service ne se lit pas sans élévation. La
  cause est établie par reproduction sur une copie.
- **La réparation des tâches** : que `Repair-VigieTasks` traite correctement la tâche `Vigie - Serveur`, dont le nom
  commence par le même préfixe que les tâches d'app cliente.
- **La taille réelle des journaux** du compte de service et des comptes de personnes.
