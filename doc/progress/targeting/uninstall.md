# Désinstallation — ce qui doit disparaître, et comment

Vigie doit savoir s'en aller. ID concerné : **CORE-UNINSTALL**. L'installation, elle, vit dans
[`install-update.md`](install-update.md).

**Le point d'entrée est `uninstall.cmd`**, livré à côté de `setup.cmd`. Un script, pas un bouton : il doit fonctionner
quand l'app serveur est morte, quand l'installation est à moitié défaite, ou quand plus rien ne répond — c'est-à-dire
précisément les jours où on désinstalle.

---

## Ce qui est dit AVANT l'élévation

La désinstallation exige les droits administrateur. La fenêtre qui précède la demande d'élévation — la même mécanique
que l'installation — annonce **ce qui va être supprimé**, et laisse **confirmer ou quitter**. Elle nomme en particulier
la chose que personne n'attend :

> **Les données de Vigie de TOUS les comptes de cette machine seront supprimées** — réglages, historiques, journaux.

Cela suppose de les **inventorier** : non pas les comptes actifs, ni même les comptes qui existent encore, mais **tous
ceux qui ont eu des données un jour**. Le disque fait foi — un dossier `Sowapps\Vigie` subsiste dans un profil dont le
compte a été supprimé, et il doit partir aussi.

---

## Ce qui doit disparaître

| # | Quoi | Où | Pourquoi ça ne peut pas rester |
|---|---|---|---|
| 1 | **Le verrou sur Windows Update** | ACL des dossiers de tâches WU (refus pour SYSTEM) | **Le point dangereux.** Partir en le laissant rend la machine durablement bloquée, sans plus rien pour l'expliquer ni le lever. Il se retire AVANT tout le reste : tant que Vigie est là, elle peut encore le faire proprement. |
| 2 | **La tâche serveur** `Vigie - Serveur` | Planificateur de tâches | Elle relancerait l'app serveur au prochain démarrage, sur un dossier disparu. |
| 3 | **Les tâches d'app cliente** `Vigie` et `Vigie - <compte>` | Planificateur de tâches | Idem, à chaque ouverture de session. |
| 4 | **Le compte local `VigieService`** | Comptes locaux Windows | Un compte de service sans service est une porte de plus, et son mot de passe reste dans le coffre de Windows. |
| 5 | **La ligne qui masque ce compte** | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList` | Posée par l'installation pour que le compte n'apparaisse pas à l'écran d'accueil. Elle survivrait au compte lui-même. |
| 6 | **Le profil du compte de service** | `C:\Users\VigieService` | Supprimer un compte local ne supprime pas son profil : le cache et les secrets y restent. |
| 6bis | **Le clone du dépôt que Vigie tient pour ses mises à jour** | `…\VigieService\AppData\Local\Sowapps\Vigie\var\update\depot` — ou sous le dossier d'installation quand `var/` y vit | C'est **notre** copie de travail, pas une source : elle est refaite au premier déploiement venu. Elle part avec le profil, et le balayage des données par profil la reprend si ce profil a résisté. |
| 7 | **Les déclarations `safe.directory`** | Configuration git **de la machine** | Posées pour que le compte de service puisse lire le dépôt. Elles désignent ensuite des chemins qui n'ont plus de raison d'être. |
| 7bis | **La déclaration du dossier d'installation** | `HKLM\SOFTWARE\Sowapps\Vigie` | Écrite par l'installation pour qu'un dossier choisi hors `Program Files` reste trouvable ; lue en premier, elle enverrait sinon tout le monde vers un dossier supprimé. |
| 8 | **Le dossier d'installation partagé** | Le chemin choisi à l'installation | Avec sa configuration de machine. Il se retire en dernier : il contient ce qui exécute la désinstallation. **Ailleurs que dans `Program Files`, on ne retire que ce qui est à nous** (voir ci-dessous). |
| 9 | **Les données de chaque compte** | `%LOCALAPPDATA%\Sowapps\Vigie` dans **tous** les profils | Annoncées avant l'élévation (ci-dessus). |
| 10 | **Les données de l'ordinateur** | `%ProgramData%\Sowapps\Vigie` | La déclaration de l'ordinateur (stage, source, dépôt de confiance) **et la sauvegarde de l'installation précédente — une copie complète de Vigie**. Ce dossier ne dépend d'aucune installation : c'est précisément pourquoi il leur survit. Retiré en dernier, après le dossier d'installation, qui lit la déclaration pour savoir quelle source épargner. |

**Ce qui ne se supprime PAS : les prérequis.** PowerShell 7 et le module Pode ont pu être posés par l'installation,
mais on ignore qui d'autre s'en sert sur cette machine. On ne retire jamais un outil général.

---

## Où vivent les données de Vigie

Tout ce que les cartes produisent vit sous un **`var/`**, et il y en a un **par compte** : celui de l'app serveur est
dans le profil du compte de service, celui de chaque personne dans le sien (**D65**). Rien de tout cela n'est rangé à
côté du programme.

| Nature | Où | Exemples |
|---|---|---|
| `cache` | `…\Sowapps\Vigie\var\cache` | l'état des cartes (`state-cache.json`), la mémoire de veille (`watch.json`), les verdicts d'identification des jeux, le cercle des comptes |
| `history` | `…\var\history\<mesure>\<AAAA-MM-JJ>.jsonl` | les séries : espace disque, latence, GPU du jeu, et les changements d'état des sentinelles |
| `run` | `…\var\run` | ce qui décrit l'instant : **la partie en cours** (`game-session.json`), l'état des résidents, les marques « une opération tourne » |
| `log` | `…\var\log` | les journaux du serveur, de l'app cliente, des installations |
| `secrets` | `…\var\secrets` | le jeton de l'API locale, le secret de compte — ACL posée et revérifiée à chaque lecture |
| clone de MAJ | `…\var\update\depot` | la copie du dépôt que Vigie tient pour se mettre à jour |

**Donc « le mode en jeu » n'est pas ailleurs** : c'est `var/run/game-session.json` dans le profil du compte de
service, et il part avec lui.

## Ce qui a pu être généré part aussi

Une désinstallation qui ne retire que ce que l'installation a **copié** laisse derrière elle tout ce que l'exécution a
**produit** — et c'est souvent le plus encombrant. Ce qui est généré se range en trois endroits, tous listés plus haut :

- **sous le dossier d'installation** : `var/` (cache, journaux, secrets, historiques), `dist/`, `logs/` ;
- **dans chaque profil** : les données par compte, dont le clone du dépôt tenu pour les mises à jour ;
- **à l'échelle de l'ordinateur** : la déclaration et la sauvegarde de l'installation précédente.

**La règle qui vaut pour la suite** : tout emplacement qu'un code de Vigie **écrit** doit apparaître dans le tableau
ci-dessus. Un nouvel emplacement d'écriture est une ligne de plus ici, le jour où on l'ajoute — pas le jour où
quelqu'un s'aperçoit qu'il reste.

Ce qui reste hors de portée : les fichiers temporaires (`%TEMP%\vigie-*`), que Windows nettoie, et dont chaque
producteur efface le sien.

## Installée ailleurs : on ne retire que son propre dossier

Dans `Program Files`, le dossier a été créé pour Vigie : il est à elle seule, et il part **entier**.

**Un dossier choisi, non.** `D:\Outils\Vigie` peut être le nôtre, mais `D:\Outils` peut aussi être passé tel quel en
paramètre à `setup.cmd` et contenir dix autres outils. Supprimer ce dossier entier emporterait le travail de
quelqu'un — exactement ce que la désinstallation ne doit jamais faire.

**Donc, hors `Program Files`, on retire nos éléments et eux seuls** : `apps`, `config`, `doc`, `lang`, `notes`,
`scripts`, `var`, `dist`, `logs`, `setup.cmd`, `uninstall.cmd`, `CHANGELOG.md`, `CLAUDE.md`, `LICENSE`, `README.md`,
`README.fr.md` — le sommet de l'archive publiée, plus ce que l'exécution produit. Le dossier lui-même n'est retiré
que s'il **finit vide** ; sinon on le dit, avec ce qui l'occupe. Ce n'est pas un échec : c'est à quelqu'un.

**La liste vit dans la bibliothèque** (`Get-InstallOwnEntries`), pas dans ce document ni dans deux scripts : ce que
l'installation pose et ce que la désinstallation retire se lisent au même endroit, sinon ils divergeront.

## Ce qui est conservé

| Quoi | Pourquoi |
|---|---|
| **PowerShell 7** et le module **Pode** | Posés par l'installation s'ils manquaient, mais ce sont des outils généraux : on ignore qui d'autre s'en sert sur cet ordinateur. |
| **Le dépôt git** d'où Vigie a été installée | Une installation est une copie ; un dépôt est du travail. La présence de `.git` suffit à l'épargner. |
| **L'archive extraite** qui a servi à installer | Déclarée par l'installation (`InstallSource`). Désinstaller ne doit pas emporter de quoi réinstaller. |
| **Les réglages Windows que Vigie n'a pas posés** | Elle ne défait que ce qu'elle a fait. Le verrou de Windows Update est à elle : il se lève. Le reste ne lui appartient pas. |
| **Le dossier `Sowapps` d'un profil**, s'il contient autre chose | Un autre produit du même éditeur peut y vivre. Il ne part que vide. |
| **Les journaux d'installation déjà écrits ailleurs** | Rien n'est cherché hors des emplacements listés plus haut : on ne fouille pas la machine. |

## Ce qui ne se supprime jamais, même quand ça y ressemble

**Un dépôt git n\u0027est pas une installation.** La recherche du dossier partagé se rabat sur « le dossier courant si tous
les comptes peuvent le lire » — et tout dossier créé à la racine de `C:` hérite de ce droit. Sur un poste où Vigie
tourne depuis un clone, cette question rendrait donc un dépôt, que la désinstallation effacerait. La présence de `.git`
tranche, avant toute suppression : une installation est une **copie**, un dépôt est du **travail**.

**Ce qui a servi à installer ne se supprime pas non plus.** Le dépôt ou l'archive extraite que la personne a gardés sur son disque lui appartiennent : désinstaller Vigie ne doit pas emporter de quoi la réinstaller. L'installation déclare donc son origine — un dépôt l'était déjà, une archive ne l'était nulle part — et la désinstallation épargne ce dossier, en le disant.

**Et rien ne se supprime sous un programme qui tourne** : l\u0027app serveur, ses résidents et les app clientes tiennent des
fichiers du dossier visé, et une app cliente lancée à la main survit à la tâche qui l\u0027aurait emportée. On arrête
d\u0027abord — avec les mêmes appels que l\u0027installation, qui fait déjà cela avant de remplacer des fichiers.

## Reprendre après un échec, et ne rien bloquer ensuite

**Une désinstallation interrompue se relance, tout simplement.** Un fichier verrouillé, une fenêtre fermée, un
redémarrage : on relance `uninstall.cmd` et elle reprend. Cela tient à une seule règle de conception — **chaque étape
regarde ce qui EST, jamais ce qu'une exécution précédente a cru faire**. Rien n'est mémorisé entre deux passages, donc
rien ne peut mentir.

**Ce qui la rendait irréprenable, et qui est corrigé :** la déclaration du dossier d'installation partait *avant* le
dossier qu'elle désigne. Entre les deux, une interruption laissait une installation à moitié effacée que plus rien ne
savait nommer — son fichier repère ayant déjà disparu, la recherche ordinaire répondait « rien d'installé ». La
déclaration part donc **après**, et sert de second recours pour retrouver un dossier dont le repère n'est plus là.

**Et rien de ce qui reste ne gêne une réinstallation** :

- un **compte de service** laissé en place est repris par l'installation, qui lui repose son mot de passe ;
- une **déclaration** qui pointe vers un dossier supprimé répond « rien d'installé » — le repère est vérifié, jamais
  cru sur parole ;
- des **tâches** restées là sont réenregistrées, pas dupliquées : elles portent un nom, pas un numéro ;
- les **déclarations git** et la **ligne de registre** sont posées de façon idempotente.

## Les règles

- **On dit ce qu'on fait, et ce qu'on n'a pas pu faire.** Une désinstallation qui échoue à mi-chemin est le pire des
  états : elle nomme chaque élément resté en place, et comment le retirer à la main.
- **Un élément déjà absent n'est pas une erreur.** Désinstaller deux fois de suite doit aboutir, comme installer deux
  fois de suite (idempotence).
- **L'ordre compte** : le verrou de Windows Update d'abord, le dossier d'installation en dernier.
