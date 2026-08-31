# CORE-UPDATE — la chaîne de mise à jour, telle qu'elle est

Arbitrages : **D112** (le service a son clone), **D110** (la référence de comparaison), **D99** (d'où vient le code).
Besoin : `../targeting/features.md`, entrée `CORE-UPDATE`.

## Qui fait quoi

| | |
|---|---|
| **App cliente** (compte de la personne) | pose le tag de version dans son dépôt et le pousse — action `tag-version`, `@execution: session` |
| **App serveur** (compte de service) | synchronise **son** clone, fabrique l'archive, déploie, relance les deux applications |

Le service ne lit ni n'écrit jamais dans le dépôt d'une personne, à une exception près : il **clone** depuis lui quand
c'est l'adresse déclarée — d'où la déclaration `safe.directory`, posée par l'installation et par le déploiement.

## Les réglages

| clé | rôle |
|---|---|
| `Environment` | `dev` ou `prod`. **Déclaré**, jamais déduit. Conditionne la pose du tag, rien d'autre. |
| `UpdateSource` | `auto` · `clone` · `release`. `auto` prend le clone si une source est connue, sinon la version publiée. |
| `UpdateRemote` | l'adresse d'où le clone se synchronise. Vide = le dépôt public. |
| `SourcePath` | *(machine.psd1)* d'où vient ce déploiement — un fait, noté par l'installation et le déploiement. |

## Le déroulé

1. **Tag** — si `Environment = dev` et qu'il y a des commits d'avance. Depuis l'interface, c'est l'app cliente du
   compte qui a cliqué ; depuis un terminal, celui qui tape la commande **est** le propriétaire, il le pose lui-même.
   Un échec n'arrête rien : une mise à jour ne rate pas pour un tag.
2. **Synchronisation** — `Sync-ServiceClone` : clone à la première fois, `fetch` ensuite. Répit de 5 minutes, forcé par
   « Actualiser ».
3. **Fabrication** — `vigie-fetch` produit l'archive depuis le clone, sur le tag visé ; depuis une source locale et
   sans référence imposée, il suit la branche.
4. **Déploiement** — `install.ps1`, qui arrête, sauvegarde, copie en préservant les réglages de la machine, vérifie, et redémarre.
5. **Relance** — ordre `restart` aux app clientes des comptes qui en ont une ; l'app serveur se relance elle-même via
   sa tâche planifiée, après la fin des opérations en cours.

## Ce que la carte affiche

Elle compare l'installation partagée **à ce que le bouton irait chercher** : le clone quand la voie est `clone`, la
dernière version publiée sinon. Quand elle ne peut pas lire la source, elle affiche le message de git plutôt qu'un
verdict inventé.

## Où en est la séquence cible

La cible est décrite dans [`../targeting/install-update.md`](../targeting/install-update.md). Posé le 30/08 :

| | |
|---|---|
| Verrou d'installation | `Lock-Install` / `Unlock-Install`, avec verrou orphelin ignoré — éprouvé |
| Refus si une opération tourne | l'installation lit les marques d'occupation et nomme ce qui tourne |
| Récupération avant l'arrêt | `vigie-update.ps1` marque, fabrique, extrait, et rend le dossier — il ne fait plus que cela |
| Contrôles avant l'arrêt | `Test-DeploymentPossible` — écriture réelle et espace disque — éprouvé |
| Arrêts | tâches d'app cliente, balayage des app clientes hors tâche, tâche serveur |
| Sauvegarde, vérification, restauration | `Backup-Install`, `Test-InstallCopy`, `Restore-Install` — éprouvés sur un arbre jetable |
| Copie | `Copy-InstallFrom`, réglages de la machine préservés — éprouvé |
| Réparation des tâches | toutes les tâches d'app cliente, pas seulement celle du compte courant |
| Le bouton appelle l'installation | plus de second geste ; `-Requester`, `-Force`, `-NoWindow` |

**Éprouvé le 31/08** : la séquence complète, lancée par `setup.cmd` en administrateur (journal
`var/log/install_20260831_065430.log`). Vue dans l'ordre : récupération **avant** tout arrêt, fabrication de
`v0.1.33`, contrôles, arrêt des app clientes et de l'app serveur, sauvegarde de `v0.1.32`, pose, vérification,
suppression de la sauvegarde, tâches, démarrages, verdict. Le second `setup.cmd` lancé en parallèle a été **refusé**
par le verrou, en nommant qui le tenait.

**Le bouton de la carte, éprouvé le 31/08 — et il a échoué**, code de sortie 5 : le refus « une opération tourne ».
L'app serveur pose la marque d'occupation avant de lancer l'installation, qui trouvait donc la sienne et s'interdisait
elle-même. Corrigé : l'action lui dit quelle marque est la sienne (`-FromAction`), et elle seule est retirée du
contrôle. **À re-éprouver après déploiement.**

Trois défauts que ce journal a montrés, et qui sont corrigés :

| Ce qui se lisait | Cause | Correction |
|---|---|---|
| deux erreurs PowerShell rouges dans un déploiement réussi | `Get-NetTCPConnection` lève quand le port est libre, ce qui est la réponse attendue après l'arrêt | `Get-PortListener`, qui rend `$null` |
| « Écarté volontairement : [int]46 fichier(s) » | le transtypage hors des parenthèses devenait un argument de `Get-Label` | `([int]$nb)` |
| « une installation en cours depuis 04:54 » à 06:54 | le verrou stocke l'heure en UTC ; elle était affichée telle quelle | conversion en heure locale à l'affichage |

## Écarts connus

- Le `fetch` depuis un dépôt local **exige** `safe.directory` : mesuré le 30/08, git refuse même la lecture d'un dépôt
  appartenant à un autre compte.
- La chaîne complète depuis le bouton de l'interface n'a pas encore été éprouvée de bout en bout.
- Le verrou n'est lu qu'**après** l'élévation : deux `setup.cmd` lancés coup sur coup ouvrent deux fenêtres et deux
  demandes de droits avant que le second ne soit refusé. Le fichier du verrou est pourtant lisible sans droits.
- La sauvegarde vit désormais dans `%ProgramData%\Sowapps\Vigieackup` (`Get-InstallBackupRoot`) : hors de toute
  installation, donc lisible par le `setup.cmd` du dossier installé même si le dépôt source a disparu. L'ancien
  emplacement, sous `var/`, est supprimé par l'installation.
