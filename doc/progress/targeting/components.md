# Les pièces de Vigie — chacune répond à chaque situation de sa vie

Besoin : `features.md`, entrée `CORE-LIFECYCLE`. Arbitrages : **D65** (chacun ses réglages, aucun pouvoir en plus),
**D106** (une action privilégiée laisse une trace), **D112** (le service a son clone). État réel :
[../implemented/components.md](../implemented/components.md).

## Ce qu'est une pièce

Tout ce que Vigie crée ou modifie hors de son propre code : un compte, une tâche planifiée, un dossier ou un fichier de
données, une clé de registre, une déclaration git, un droit Windows, une étiquette de version, un clone, un réglage de
Windows qu'elle pose.

## Les situations auxquelles toute pièce répond

| Situation | Ce qui est exigé |
|---|---|
| **Création** | Elle se crée d'elle-même, à l'installation ou au premier usage, et la créer deux fois ne change rien. |
| **Mise à jour de Vigie** | La nouvelle version la reprend, la convertit ou la recrée. Jamais un échec. |
| **Ce dont elle dépend change** | Source, chemin, compte, historique réécrit : elle se remet d'aplomb d'elle-même. |
| **État cassé ou incohérent** | Il est détecté, puis réparé ou recréé d'office. Sinon il se voit sur une carte, avec son geste de réparation. |
| **Croissance** | Elle est bornée : purge, rotation ou limite déclarée. |
| **Maintenance** | Un administrateur, et l'agent sur le poste de développement, peuvent la lire, la réparer ou la réinitialiser. |
| **Suppression par quelqu'un** | Vigie la recrée, ou dit qu'elle manque, sans se bloquer. |
| **Désinstallation** | Elle est retirée, ou conservée avec sa raison, selon [uninstall.md](uninstall.md). |

## Jamais bloquée

Aucune situation ne laisse une pièce dans un état dont Vigie ne sort pas d'elle-même ou par une action. Une pièce que
Vigie possède seule, comme son clone, son cache ou ses marques, est remise de force dans l'état voulu plutôt que de
refuser.

## Sécurisée

La maintenance passe par les actions du serveur. Chacune déclare ses droits, laisse une trace d'audit et ne recopie
aucun secret. L'agent sur le poste de développement emprunte ces mêmes actions : il n'a aucun chemin à lui.

## Les durées de conservation

| Donnée | Durée |
|---|---|
| journaux, copies de diagnostic et sauvegardes `.reg`, sous `var/log` | **30 jours**, arbitré par l'utilisateur le 13/09 |
| historique des mesures, sous `var/history` | celle de `config.psd1`, section `History` |

## L'inventaire

Toute pièce figure dans `implemented/components.md`, avec sa réponse à chaque situation. Une pièce nouvelle y entre dans
le même commit que le code qui la crée.
