# Installation et mise à jour — la séquence cible

**Une seule séquence**, quel que soit le point d'entrée : `setup.cmd` lancé par une personne, ou le bouton « Mettre à
jour » de la carte Déploiement. Ce document décrit ce que le produit **doit** faire ; l'état réel vit dans
`../implemented/update-chain.md`.

ID concernés : `CORE-DEPLOY`, `CORE-UPDATE`, `CORE-AUTOSTART`. Arbitrages : **D112** (le service a son clone), **D110**
(la référence de comparaison), **D99** (d'où vient le code), **D77** (« déjà à jour » n'est pas un échec).

---

## La séquence

| # | Étape | 1ʳᵉ install<br>(archive) | 1ʳᵉ install<br>(dépôt) | MAJ par<br>`setup.cmd` | MAJ par<br>le bouton |
|---|---|:---:|:---:|:---:|:---:|
| 1a | **Élévation demandée à l'utilisateur**<br>*Demandée avant de lancer l'installation* | ✓ | ✓ | ✓ | — |
| 1b | **Élévation héritée de l'app serveur**<br>*Elle tourne déjà élevée, sous son compte de service* | — | — | — | ✓ |
| 2 | **Verrou d'installation**<br>*Une seule installation à la fois ; si une autre tourne : refus, et arrêt du déploiement* | ✓ | ✓ | ✓ | ✓ |
| 3 | **Prérequis** | ✓ | ✓ | ✓ | ✓ |
| 4 | **Une opération est en cours ?**<br>*Si oui : échec, et arrêt du déploiement* | — | — | ✓ | ✓ |
| 5 | **Déclaration de l'ordinateur**<br>*Stage, source, dépôt de confiance* | ✓ | ✓ | ✓ | ✓ |
| 6a | **Synchronisation du clone du service**<br>*Si installation depuis un dépôt* | — | ✓ | ✓ | ✓ |
| 6b | **Lecture de la dernière release publiée**<br>*Si installation depuis une archive de release* | — | — | ✓ | ✓ |
| 7 | **Déjà à jour ?**<br>*Si oui : succès, et arrêt du déploiement. Forçable* | — | ✓ | ✓ | ✓ |
| 8 | **Marquage de version**<br>*Seulement si stage `dev` et commits d'avance ; un échec est signalé, le déploiement continue* | — | ✓ | ✓ | ✓ |
| 9a | **Fabrication de l'archive**<br>*Depuis le clone du service* | — | ✓ | ✓ | ✓ |
| 9b | **Téléchargement de l'archive**<br>*Si installation depuis une archive de release* | — | — | ✓ | ✓ |
| 10 | **Extraction de l'archive** | — | ✓ | ✓ | ✓ |
| 11 | **Le déploiement est-il possible ?**<br>*Contrôles rapides sur l'installation partagée ; si non : échec, et arrêt du déploiement* | ✓ | ✓ | ✓ | ✓ |
| 12 | **Arrêt des tâches d'app cliente**<br>*Tous les comptes activés ; arrêt propre, puis forcé ; un échec est signalé, le déploiement continue* | — | — | ✓ | ✓ |
| 13 | **Arrêt de la tâche serveur**<br>*Arrêt propre, puis forcé ; si le forcé échoue aussi : échec, et arrêt du déploiement* | — | — | ✓ | ✓ |
| 14 | **Arrêt des app clientes lancées hors tâche**<br>*Arrêt forcé ; un échec est signalé, le déploiement continue* | — | — | ✓ | ✓ |
| 15 | **Sauvegarde de l'installation en place** | — | — | ✓ | ✓ |
| 16 | **Copie vers l'installation partagée**<br>*Depuis l'archive extraite, par nous ou par l'utilisateur* | ✓ | ✓ | ✓ | ✓ |
| 17 | **Vérification de la copie**<br>*Version attendue et fichiers clés* | ✓ | ✓ | ✓ | ✓ |
| 18a | **Suppression de la sauvegarde**<br>*Si la copie est valide* | — | — | ✓ | ✓ |
| 18b | **Restauration de la version précédente**<br>*Si la copie n'est pas valide : échec, et arrêt du déploiement après restauration* | — | — | ✓ | ✓ |
| 19 | **Enregistrement de la tâche serveur**<br>*Création ou réparation ; un échec est signalé, le déploiement continue* | ✓ | ✓ | ✓ | ✓ |
| 20 | **Démarrage de la tâche serveur** | ✓ | ✓ | ✓ | ✓ |
| 21 | **Enregistrement des tâches d'app cliente**<br>*Création ou réparation pour les comptes avec Vigie activée ; un échec est signalé, le déploiement continue* | ✓ | ✓ | ✓ | ✓ |
| 22a | **Démarrage de la tâche d'app cliente du compte courant** | ✓ | ✓ | — | — |
| 22b | **Démarrage des tâches d'app cliente arrêtées** | — | — | ✓ | ✓ |
| 23 | **Verdict** | ✓ | ✓ | ✓ | ✓ |
| 24 | **Fenêtre de fin**<br>*Toujours affichée, succès comme échec* | ✓ | ✓ | ✓ | — |
| 25 | **Libération du verrou d'installation**<br>*Quel que soit le résultat, y compris après un arrêt du déploiement* | ✓ | ✓ | ✓ | ✓ |

**Ce qui décide d'une ligne, ce sont des faits**, jamais le point d'entrée : une installation est-elle déjà en place,
un dépôt existe-t-il, le stage vaut-il `dev`, quelle source est déclarée, une session est-elle ouverte.

---

## Les règles qui traversent la séquence

**Les lettres marquent des alternatives, jamais des séquences.** `6a` **ou** `6b`, `9a` **ou** `9b`, `18a` **ou**
`18b`, `22a` **ou** `22b`.

**Trois natures d'arrêt anticipé**, et le verdict doit dire laquelle : un **refus** (2, une autre installation tourne),
un **échec** (4, 11, 13, 18b), un **succès** (7, déjà à jour).

**Un échec non bloquant est signalé et n'interrompt rien** : le marquage (8), l'arrêt d'une app cliente (12, 14),
l'enregistrement d'une tâche (19, 21). Dans ce dernier cas le code est bien déployé — c'est son démarrage automatique
qui manquera — et cela ne justifie donc aucune restauration.

**On n'attend jamais qu'une application démarre ; on attend toujours qu'elle soit arrêtée.** Un arrêt se constate — le
port se libère, le processus disparaît —, un démarrage se suppose.

**Tout démarre et s'arrête par la tâche planifiée**, pour les deux applications. C'est elle qui sait sous quelle
identité lancer, et c'est le seul moyen pour l'app cliente d'un autre compte.

---

## Ce qu'il faut savoir à côté

### Le verrou d'installation

Il porte **qui le tient** — numéro de processus et heure de pose — et un verrou dont le processus n'existe plus est
**ignoré**. Sans cela, une installation interrompue brutalement condamnerait le poste jusqu'à une suppression manuelle,
ce qu'on s'interdit : ce qui manque manque dans l'installation, jamais dans une commande à taper.

Il vit hors de l'installation partagée, avec la déclaration de l'ordinateur (`%ProgramData%\Sowapps\Vigie\`), pour
survivre à une copie et rester lisible par les deux points d'entrée.

### Les prérequis modifient la machine, et on le dit

L'étape 3 installe ce qui manque — PowerShell 7, Pode, WebView2 — **avant** les contrôles qui peuvent arrêter le
déploiement. C'est assumé : ces dépendances servent de toute façon. La fenêtre d'annonce dit donc **ce qui sera
installé**, et que **Vigie ne le désinstallera jamais**, à aucun moment.

### La sauvegarde

Elle vit **hors de toute installation**, à l'échelle de la machine : `%ProgramData%\Sowapps\Vigieackup`, là où
vit déjà la déclaration de l'ordinateur. Elle porte la **version** qu'elle contient, pour qu'on sache ce qu'on
restaure, et elle est **supprimée dès que la copie est vérifiée** : elle n'existe que le temps du risque.

*Elle a d'abord vécu sous `var/` de l'app serveur, c'est-à-dire **dans le dossier qu'elle sert à restaurer** — le filet
accroché au trapèze. Trois façons d'y perdre : une copie qui écrase le dossier emporte la sauvegarde avec, une
désinstallation aussi, et le `setup.cmd` livré **dans** le dossier installé ne peut pas restaurer ce que ce dossier
contenait — or c'est le cas qui compte, puisque le dépôt source peut avoir disparu.*

Conséquence sur les contrôles : la destination et la sauvegarde peuvent être sur **deux disques différents**. La place
se vérifie donc des deux côtés, chacun pour ce qu'il recevra, et non deux fois du même côté.

### Ce que « déjà à jour » signifie

L'installation partagée porte exactement le commit de la source. En stage `dev`, sans commit d'avance, il n'y a rien à
marquer ni à déployer : on s'arrête et on le dit. Le forçage refait la séquence entière — il ne saute que ce test.

### La vérification de l'archive

Elle appartient à la récupération (9a, 9b), qui ouvre l'archive et contrôle son contenu avant de s'en servir : un
téléchargement coupé laisse un fichier d'allure normale mais illisible. Ce n'est pas une étape à part.

### Migration des données, le jour où un format changera

Sa place est **entre 17 et 19** : le nouveau code est en place et **rien ne tourne**. Elle s'exécute **par compte** —
chaque profil a ses réglages, son historique, ses notifications — et l'installation, élevée, peut les atteindre tous.
Elle exige un **numéro de format** rangé à côté des données, sinon on ne saura pas ce qui a déjà été migré, et elle est
couverte par la sauvegarde : une migration ratée doit pouvoir revenir en arrière comme une copie ratée.

### Le cache ne se migre pas, il se supprime

Un cache perdu se recalcule : c'est sa définition. Aujourd'hui il n'y a rien à faire — il est indexé sur l'empreinte du
fichier de sonde, que la mise à jour change, donc ses entrées se périment seules. Le jour où sa **structure** changera,
sa suppression ira au même endroit que la migration, entre 17 et 19, et pour tous les comptes.

### Une tâche d'app cliente exige une session ouverte

Elle est **interactive** : Windows refuse de la démarrer pour un compte qui n'a aucune session. « Ouverte » ne veut pas
dire « active » — un compte laissé par « Changer d'utilisateur » garde une session **déconnectée**, et sa tâche y
démarre très bien. Vérifié le 30/08 : deux sessions coexistaient, l'une active, l'autre déconnectée.

Un compte sans session n'est donc pas une erreur : son app cliente repartira à sa prochaine ouverture, avec le nouveau
code. La tâche serveur, elle, ouvre une session par mot de passe : elle démarre sans personne de connecté.

### L'installation ne se compte pas elle-même parmi les opérations en cours

Le refus « une opération tourne » protège ce qu'on ne doit pas interrompre — une analyse de disque, une installation de
mises à jour Windows. Mais depuis le bouton, l'app serveur pose la marque « une opération tourne » **avant** de lancer
l'installation, pour que la carte le montre et que rien d'autre ne démarre : l'installation trouvait donc **la sienne**
et s'interdisait elle-même.

*Constaté le 31/08 : « Mise à jour de Vigie — ÉCHEC le 31/08/2026 09:27 — code de sortie 5 », le code du refus.*

L'action lui dit donc quelle marque est la sienne (`-FromAction`), et cette seule opération est retirée de la liste.
Le contrôle reste entier pour toutes les autres.

### Depuis le bouton, l'installation tourne détachée de l'app serveur

L'étape 13 arrête l'app serveur — or c'est elle qui a lancé l'installation. Si le processus d'installation était son
enfant direct, il mourrait avec elle et tout ce qui suit n'aurait jamais lieu. Il est donc **détaché**, comme le
relanceur : l'app serveur le lance et le laisse vivre.

### Un tag sans déploiement derrière n'est pas grave

Le marquage (8) précède la fabrication (9a) parce que l'archive doit porter le numéro. Si la suite échoue, le dépôt
garde un tag qui ne correspond à rien de déployé : c'est acceptable, on ne le retire pas.

### Quand la restauration elle-même échoue

Il n'y a pas de reprise automatique : l'installation partagée est dans un état intermédiaire, et la fenêtre de fin le
**dit** — avec le chemin de la sauvegarde, s'il en reste une, et celui du journal. C'est le seul cas où Vigie demande
une intervention.

### Correspondances techniques

| Dans le plan | Dans le code |
|---|---|
| stage | `Stage` (ancien nom `Environment` encore lu) |
| source déclarée | `UpdateSource`, `UpdateRemote`, `UpdateRef` |
| forçable | commutateur `-Force` |
| déclaration de l'ordinateur | `%ProgramData%\Sowapps\Vigie\machine.psd1` |
| installation partagée | `C:\Program Files\Sowapps\Vigie` |
| clone du service | données du compte de service, dossier `update\depot` |
| sauvegarde | `%ProgramData%\Sowapps\Vigieackup\installation-<version>` (`Get-InstallBackupRoot`) |
| verrou d'installation | `%ProgramData%\Sowapps\Vigie\` (`Get-InstallLockPath`) |
| dossier de la machine | `Get-ComputerDataRoot` — une seule définition pour les trois lignes ci-dessus |
