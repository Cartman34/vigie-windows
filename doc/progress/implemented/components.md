# CORE-LIFECYCLE — l'inventaire des pièces, tel qu'il est

Cible : [../targeting/components.md](../targeting/components.md), qui définit les situations. Sujet ouvert : **S15**.

Relevé du 13/09/2026, fait dans le code et la documentation. Où vit chaque pièce : `../targeting/uninstall.md`, section
« Ce qui doit disparaître ». Une case dit ce qui existe ; **aucune réponse** marque un écart à la cible, **non vérifié**
une réponse que le code laisse supposer sans qu'elle ait été constatée.

**Tenu par : aucun vérificateur.** C'est un écart, porté par **S15**.

## Le compte de service et ses droits

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| compte `VigieService` | installation | repris, mot de passe renouvelé | réinstallation | sans objet | **aucune réponse** par le serveur | retiré |
| ligne qui masque le compte | installation | idempotente | réinstallation | sans objet | **aucune réponse** | retirée |
| droit « ouvrir une session en tant que tâche » | installation, par `secedit` | idempotent | réinstallation | sans objet | **aucune réponse** | **aucune réponse** : jamais retiré |
| profil du compte de service | premier démarrage de la tâche | sans objet | **aucune réponse** | voir les données | lecture des journaux par `diag-account-logs` | retiré |

## Les tâches planifiées

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| tâche `Vigie - Serveur` | installation | réenregistrée | **non vérifié** : `Repair-VigieTasks` la prend par son préfixe | sans objet | **non vérifié** : `repair-tasks` | retirée |
| tâches `Vigie - <compte>` | activation d'un compte | réenregistrées, ancien nom renommé | réécrites par `Repair-VigieTasks` | sans objet | `repair-tasks` | retirées |

## L'installation et la déclaration de l'ordinateur

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| installation partagée | installation | copie vérifiée, restauration si invalide | restauration de la version précédente | sans objet | `vigie-update` | retirée en dernier |
| `machine.psd1` | installation et déploiement | réécrite à chaque déploiement | **aucune réponse** : `SourcePath` peut désigner un dossier disparu | sans objet | **aucune réponse** | retirée |
| sauvegarde de l'installation précédente | déploiement | supprimée après une copie valide | sert à la restauration | une seule | **aucune réponse** | retirée |
| verrou d'installation | installation | sans objet | verrou orphelin ignoré | sans objet | sans objet | retiré |
| déclaration du dossier d'installation | installation | vérifiée, jamais crue | ignorée si périmée | sans objet | **aucune réponse** | retirée |
| identité des notifications | installation | réécrite à chaque passe du minuteur | réécrite | sans objet | sans objet | retirée |
| source du journal d'événements `Vigie` | premier usage | sans objet | **aucune réponse** | journal de Windows | **aucune réponse** | **aucune réponse** : jamais retirée |

## Git : le clone, les déclarations, les étiquettes

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| clone du service | première synchronisation | récupération forcée ; recloné à côté de l'ancien si git refuse alors que la source répond. **Éprouvé en production le 13/09 à 11 h 57** : les étiquettes déplacées ont été absorbées sans reclonage | illisible : recloné ; source muette : clone intact, texte de git affiché | sans objet | `service-clone-repair`, `service-clone-reset` | retiré avec le profil |
| déclarations `safe.directory` | installation et déploiement | **aucune réponse** : une par source, jamais retirée quand la source change | sans objet | **aucune réponse** : s'accumulent | **aucune réponse** | retirées |
| étiquettes de version | déploiement en `dev`, posées et poussées dans le dépôt de la personne | déplacées par une réécriture d'historique, elles bloquent le clone | sans objet | une par déploiement | **aucune réponse** | conservées : le dépôt appartient à la personne |

## Les données sous `var/`

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| `var/cache` | exécution | supprimé à la mise à jour, jamais migré | recalculé | borné par les sondes | **aucune réponse** | retiré |
| `var/history` | sentinelles | sans objet | **non vérifié** | purge à 90 jours | **aucune réponse** | retiré |
| `var/log`, dont les copies de diagnostic et les sauvegardes `.reg` | exécution | sans objet | sans objet | **aucune réponse** : aucune purge trouvée | lecture par `diag-account-logs` | retiré |
| `var/secrets` | installation | sans objet | ACL revérifiée à chaque lecture | sans objet | **aucune réponse** | retiré |
| `var/run` : marques et état des résidents | exécution | sans objet | marque d'un processus disparu : échec affiché | sans objet | sans objet | retiré |

## Les réglages de Windows que Vigie pose

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| verrou de Windows Update | `update-mode-off` | sans objet | carte du verrou | sans objet | `update-mode-on`, `update-mode-off`, `run-audit` | levé en premier |
| bascules VBS et HVCI | `toggle-vbs`, `toggle-hvci`, après sauvegarde `.reg` | sans objet | **non vérifié** | sauvegardes `.reg` sans purge | `toggle-vbs`, `toggle-hvci` | conservées, selon `uninstall.md` |
| prérequis : PowerShell 7, Pode, NuGet | installation, s'ils manquent | sans objet | installation | sans objet | `pwsh-install-machine` | conservés, selon `uninstall.md` |
