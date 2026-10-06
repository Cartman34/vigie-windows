# Un mot que j'ai inventé, écrit partout, jamais validé

Relevé du constat qui a fait écrire **D129** et ouvrir le sujet **S17**. Tout ce qui suit est compté dans le dépôt.

## Le constat

Le propriétaire lit « ordre de bureau » dans une de mes réponses et le reprend :

> « Tu as inventé le terme en ton bureau, et après tu le réutilises, mais tu ne me l'as jamais présenté. Et pour moi,
> il n'est pas dans le glossaire, puisque je ne l'ai jamais validé. Puis, ordre de bureau, ça ne veut rien dire. Moi,
> j'ai défini qu'il y avait des tâches synchrones et asynchrones, qu'il y avait des tâches longues et des tâches
> immédiates. »

**Et j'avais d'abord répondu l'inverse** : « sur le vocabulaire je me suis trompé à l'envers, le terme *est* défini,
il est dans `operations.md` et dans le code ». C'était confondre **écrit par moi** et **validé par lui**. Qu'un mot
soit dans le dépôt ne prouve que son auteur.

## Ce qui est compté

| | |
|---|---|
| Termes au glossaire (`doc/en/developing/glossary.md`) | **32** |
| Le terme en question, au glossaire | **absent** |
| Occurrences françaises dans le produit | **11**, dans 6 fichiers |
| L'identifiant qui portait la notion | `Invoke-DesktopAction`, **12 usages** |
| Fichiers d'échange | `desktop-*.json` |
| Endroits de conception qui l'avaient adopté | `targeting/operations.md`, `implemented/operations.md`, `implemented/status.md` |

Le mot était donc dans le besoin, la conception, le réalisé, le code, les journaux et l'inventaire des opérations —
et nulle part dans le seul endroit qui fait foi.

## Le mot retenu

Le propriétaire tranche : **« tâche serveur »** et **« tâche cliente »**. Une tâche porte le nom de l'application
qui l'exécute, exactement comme **app serveur** et **app cliente**, déjà au glossaire.

Et c'était déjà écrit dans le code sans que je le voie : chaque action déclare `@execution: serveur` ou
`@execution: session`. Le vocabulaire juste existait dans les en-têtes ; j'en avais inventé un second par-dessus.

## Ce qui tient la règle

- Les deux termes entrent au glossaire, qui est **la seule source**.
- `Invoke-DesktopAction` → `Invoke-ClientTask` ; `desktop-*.json` → `client-task-*.json`.
- **Cinquième cliquet** dans `check-naming.ps1`, à **zéro**, sur le terme français et sur l'identifiant. Les endroits
  qui énoncent la règle — ce vérificateur, la décision, le glossaire, les relevés datés — en sont exemptés.
- Pas de lecture des deux noms de fichiers : une installation arrête et relance chaque app cliente, donc une tâche
  écrite dans les secondes qui précèdent serait perdue de toute façon — et son demandeur le sait, puisqu'une tâche
  cliente rend toujours compte, même en échec.

## Ce qui n'a pas été demandé

Un vérificateur qui refuserait **tout** mot de conception absent du glossaire. Arbitré le 06/10 : « Q2 non ».
Le cliquet ne tient que ce terme-là.
