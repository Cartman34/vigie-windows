# CORE-LIFECYCLE — l'inventaire des pièces, tel qu'il est

Cible : [../targeting/components.md](../targeting/components.md), qui définit les situations. Sujet ouvert : **S15**.

Relevé du 13/09/2026, fait dans le code et la documentation. Où vit chaque pièce : `../targeting/uninstall.md`, section
« Ce qui doit disparaître ». Une case dit ce qui existe ; **aucune réponse** marque un écart à la cible, **non vérifié**
une réponse que le code laisse supposer sans qu'elle ait été constatée.

**Tenu par `scripts/dev/check-components.ps1`** pour les écritures sur la machine, qui dit lui-même ce qu'il ne voit pas.

## Le compte de service et ses droits

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| compte `VigieService` | installation | repris, mot de passe renouvelé | réinstallation, ou `service-account-repair` | sans objet | `service-account-repair` : mot de passe, droit, ligne qui le masque, tâche serveur ; **non éprouvé** | retiré |
| ligne qui masque le compte | installation | idempotente | réinstallation, ou `service-account-repair` | sans objet | `service-account-repair` ; **non éprouvé** | retirée |
| droit « ouvrir une session en tant que tâche » | installation, par `Set-BatchLogonRight` | idempotent | réinstallation, ou `service-account-repair` | sans objet | `service-account-repair` ; **non éprouvé** | retiré avant le compte, depuis le 13/09 ; **non éprouvé** |
| profil du compte de service | premier démarrage de la tâche | sans objet | **aucune réponse** | voir les données | lecture des journaux par `diag-account-logs` | retiré |

## Les tâches planifiées

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| tâche `Vigie - Serveur` | installation | réenregistrée | écartée de `Repair-VigieTasks`, qui la prenait pour la tâche d'un compte « Serveur » | sans objet | `service-account-repair` la réenregistre et la réactive ; **non éprouvé** | retirée |
| tâches `Vigie - <compte>` | activation d'un compte | réenregistrées, ancien nom renommé | réécrites par `Repair-VigieTasks` | sans objet | `repair-tasks` | retirées |

## L'installation et la déclaration de l'ordinateur

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| installation partagée | installation | copie vérifiée, restauration si invalide | restauration de la version précédente | sans objet | `vigie-update` | retirée en dernier |
| `machine.psd1` | installation et déploiement | réécrite à chaque déploiement | `SourcePath` disparu : la mise à jour prend la dernière version publiée, et la carte Déploiement le signale | sans objet | **aucune réponse** | retirée |
| sauvegarde de l'installation précédente | déploiement | supprimée après une copie valide | sert à la restauration | une seule | **aucune réponse** | retirée |
| verrou d'installation | installation | sans objet | verrou orphelin ignoré | sans objet | sans objet | retiré |
| déclaration du dossier d'installation | installation | vérifiée, jamais crue | ignorée si périmée | sans objet | **aucune réponse** | retirée |
| identité des notifications | installation | réécrite à chaque passe du minuteur | réécrite | sans objet | sans objet | retirée |
| source du journal d'événements `Vigie` | premier usage | sans objet | **aucune réponse** | journal de Windows | **aucune réponse** | retirée, depuis le 13/09 ; **non éprouvé** |

## Git : le clone, les déclarations, les étiquettes

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| clone du service | première synchronisation | récupération forcée ; recloné à côté de l'ancien si git refuse alors que la source répond. **Éprouvé en production le 13/09 à 11 h 57** : les étiquettes déplacées ont été absorbées sans reclonage | illisible : recloné ; source muette : clone intact, texte de git affiché | sans objet | `service-clone-repair`, `service-clone-reset` | retiré avec le profil |
| déclarations `safe.directory` | installation et déploiement | la source précédente perd les siennes au déploiement suivant, depuis le 13/09 | sans objet | celles des sources quittées avant le 13/09 restent | **aucune réponse** | retirées |
| étiquettes de version | déploiement en `dev`, posées et poussées dans le dépôt de la personne | déplacées par une réécriture d'historique, elles bloquent le clone | sans objet | une par déploiement | **aucune réponse** | conservées : le dépôt appartient à la personne |

## Les données sous `var/`

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| `var/cache` | exécution | supprimé à la mise à jour, jamais migré | recalculé | borné par les sondes | **aucune réponse** | retiré |
| `var/history` | sentinelles | sans objet | **non vérifié** | purge à 90 jours | **aucune réponse** | retiré |
| `var/log`, dont les copies de diagnostic et les sauvegardes `.reg` | exécution | sans objet | sans objet | purge à 30 jours, au démarrage de l'app serveur et de l'app cliente, puis chaque jour avec l'historique | lecture par `diag-account-logs` | retiré |
| `var/secrets` | installation | sans objet | ACL revérifiée à chaque lecture | sans objet | **aucune réponse** | retiré |
| `var/run` : marques et état des résidents | exécution | sans objet | marque d'un processus disparu : échec affiché | sans objet | sans objet | retiré |

## Les réglages de Windows que Vigie pose

| Pièce | Création | Mise à jour, dépendance qui change | État cassé | Croissance | Maintenance | Désinstallation |
|---|---|---|---|---|---|---|
| verrou de Windows Update | `update-mode-off` | sans objet | carte du verrou | sans objet | `update-mode-on`, `update-mode-off`, `run-audit` | levé en premier |
| bascules VBS et HVCI | `toggle-vbs`, `toggle-hvci`, après sauvegarde `.reg` | sans objet | **non vérifié** | sauvegardes `.reg` sans purge | `toggle-vbs`, `toggle-hvci` | conservées, selon `uninstall.md` |
| prérequis : PowerShell 7, Pode, NuGet | installation, s'ils manquent | sans objet | installation | sans objet | `pwsh-install-machine` | conservés, selon `uninstall.md` |

## Où chaque pièce s'écrit

Chaque fonction de `apps/backend-pode/lib/common.ps1`, ou chaque fichier ailleurs, qui écrit sur la machine.

| Qui écrit | Pièce |
|---|---|
| `Invoke-UpdateLockNative` | verrou de Windows Update |
| `Register-VigieEventSource` | source du journal d'événements `Vigie` |
| `Remove-GitSafeDirectory` | déclarations `safe.directory` |
| `Rename-VigieLegacyTask` | tâches `Vigie - <compte>` |
| `Repair-VigieTasks` | tâches `Vigie - <compte>` |
| `Set-BatchLogonRight` | droit « ouvrir une session en tant que tâche » |
| `Set-DeviceGuardFeature` | bascules VBS et HVCI |
| `Set-GitSafeDirectory` | déclarations `safe.directory` |
| `Set-InstallPathDeclaration` | déclaration du dossier d'installation |
| `Set-VigieAccountEnabled` | tâches `Vigie - <compte>` |
| `Set-VigieToastIdentity` | identité des notifications |
| `apps/tray/tray.ps1` | tâches `Vigie - <compte>`, quand l'app cliente répare la sienne |
| `scripts/install-autostart.ps1` | tâches `Vigie - <compte>` |
| `scripts/lib/install-service.ps1` | compte `VigieService`, ligne qui masque le compte, tâche `Vigie - Serveur` |
| `scripts/uninstall-autostart.ps1` | tâches `Vigie - <compte>` |
| `scripts/uninstall-legacy.ps1` | vestiges d'avant le nom Vigie |
| `scripts/uninstall.ps1` | toutes les pièces, à la désinstallation |