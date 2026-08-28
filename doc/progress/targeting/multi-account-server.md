# Un serveur élevé par machine — conception

> **État : à valider. Rien n'est codé.**
>
> **Cette version corrige la précédente.** La première mouture recommandait « un seul serveur élevé qui fait tout ».
> En cherchant les contraintes de Windows plutôt qu'en les supposant, il apparaît qu'un serveur unique en session 0
> **casserait** la carte WSL, les cartes de gestionnaires de paquets, une partie de la carte Gaming et les neuf actions
> qui ouvrent une fenêtre. La porte d'entrée unique est conservée — c'est ce qui règle le port — mais le travail
> *propre à un utilisateur* est délégué au tray de ce compte.

---

## Le problème, tel qu'il a été constaté

Le 28/08/2026, Vigie ne démarrait pas sur le compte « Famille ». Deux causes ; la première est corrigée, la seconde est
structurelle.

1. **Corrigé (D101).** Le tray calculait son journal à côté du programme. Sur un compte standard, Windows refuse cette
   écriture : le script mourait avant sa première ligne de journal, sans laisser de trace.
2. **Structurel.** `apps/backend-pode/start.ps1` exige l'élévation et se relance en `RunAs` s'il ne l'a pas. Sur un
   compte **standard**, cela réclame le mot de passe d'un administrateur — que ce compte n'a pas, par définition.

S'y ajoute un obstacle latent : **un seul port**. Deux sessions ouvertes en même temps, et le second serveur ne peut pas
s'attacher à `127.0.0.1:47600`.

Le besoin, posé par l'utilisateur : *« il y a des opérations qu'un utilisateur standard devrait pouvoir faire qui
nécessitent une élévation »*.

---

## Les contraintes de Windows, vérifiées

Ce sont elles qui dictent l'architecture. Chacune a été confirmée dans le code de ce dépôt ou tient d'une règle
Windows non contournable.

### C1. Un compte standard ne peut pas s'élever

Aucune ruse ne contourne ça : il faut les identifiants d'un administrateur, ou rien.

### C2. Une tâche planifiée est le courtier d'élévation légitime

Elle s'exécute avec les droits fixés **à son enregistrement**, par un administrateur, et un compte sans privilège peut
être autorisé à la déclencher sans jamais voir d'identifiants. Le droit de déclenchement se donne par le **descripteur
de sécurité de la tâche** (SDDL), posé à l'installation.

### C3. La session 0 n'a pas de bureau — et c'est là que vit un service

Un serveur lancé au démarrage par une tâche `SYSTEM` tourne en **session 0**, isolée. Conséquence directe et non
négociable : **tout ce qui doit s'afficher pour l'utilisateur est invisible depuis là**. Sont concernées, dans le code
actuel :

- les **neuf actions `open-*`** (dossier, journaux, Gestionnaire des tâches, Gestionnaire de périphériques, Paramètres
  Windows, Windows Update, options d'alimentation, paramètres utilisateurs, dossier d'analyse) ;
- les fenêtres d'explication avant élévation (`show-confirm.ps1`) ;
- les notifications du tray.

### C4. Beaucoup de mesures sont PAR UTILISATEUR, pas par machine

C'est la découverte qui corrige la conception. Relevé dans le dépôt :

| Sujet | Fichiers concernés | Pourquoi c'est par utilisateur |
|---|---|---|
| **WSL** | 6 | WSL s'exécute dans la session de l'utilisateur. `wsl --shutdown` lancé par `SYSTEM` ne verrait pas la distribution de Famille. |
| **winget** | 5 | Les paquets installés en portée utilisateur diffèrent d'un compte à l'autre. |
| **pip, npm, scoop** | 4 | Idem : installations dans le profil. |
| **Gaming** | 3 lectures `HKCU` | Réglages graphiques du compte, VRAM par processus de SA session. |
| **WSL (config)** | 1 lecture `HKCU` | Idem. |

`HKCU` depuis la session 0 ne désigne **pas** la ruche de l'utilisateur : elle désigne celle de `SYSTEM`. Lire celle
d'un autre compte demande de charger sa ruche (`reg load`), ce qui est lourd, verrouillant, et impossible si le compte
est déconnecté.

### C5. Les variables d'environnement du serveur ne sont plus celles de personne

Sous `SYSTEM`, `$env:USERNAME` vaut `SYSTEM`, `$env:LOCALAPPDATA` pointe dans `C:\Windows\System32\config\systemprofile`.
Le code actuel s'appuie dessus à quatre endroits dans `common.ps1`. Chacun devient faux et doit désigner **le compte
demandeur**, pas le processus.

### C6. `Test-IsElevated` change de sens

Aujourd'hui la question « suis-je élevé ? » sert à décider si une action est permise. Dans un serveur toujours élevé,
elle répond **toujours oui** — et le contrôle des droits disparaît sans bruit. Elle doit être remplacée partout par
« **le demandeur** a-t-il ce droit ? ». C'est le point le plus dangereux de la migration : une régression y serait
silencieuse et donnerait des droits d'administrateur à tout le monde.

### C7. Les jetons : aucun emplacement n'est sûr par héritage

**Un jeton que tout le monde peut lire ne sert à rien.** Les deux emplacements envisagés ont été mesurés sur cette
machine, et **aucun des deux** n'est acceptable tel quel :

| Emplacement | Droits hérités constatés | Verdict |
|---|---|---|
| `C:\ProgramData` | `BUILTIN\Utilisateurs` : **lecture ET écriture** | inutilisable : n'importe quel compte lirait tous les jetons |
| `%LOCALAPPDATA%` du compte | le compte, `SYSTEM`, `Administrateurs` — **et** `Hyperion\CodexSandboxUsers` en lecture | insuffisant : un outil tiers y avait ajouté un groupe |

Le second cas est le plus instructif : ce profil est censé être privé, et il ne l'était déjà plus. **On ne se fie donc
à aucun héritage.**

**Ce qui est retenu :**

1. **Le jeton vit dans le profil du compte**, sous `%LOCALAPPDATA%\Sowapps\Vigie\var\secrets\`. Cela suppose que le
   profil existe : Vigie **impose** donc qu'un compte ait ouvert une session au moins une fois avant d'être activé, et
   le refuse en le disant sinon. La carte Comptes sait déjà distinguer un profil jamais chargé.
2. **L'héritage est coupé** sur le dossier `secrets`, et une ACL explicite est posée : le compte (lecture/écriture),
   `SYSTEM`, `Administrateurs`. **Personne d'autre** — aucun groupe, aucune exception.
3. **L'ACL est vérifiée à chaque lecture**, pas seulement à l'écriture. Si elle accorde quoi que ce soit à un tiers, le
   jeton est tenu pour **compromis** : révoqué, réémis, et l'incident journalisé. Un secret dont on ne vérifie les
   droits qu'une fois est un secret dont on ignore l'état.
4. **Le serveur ne garde qu'une empreinte**, jamais le jeton en clair, dans un fichier lisible du seul `SYSTEM`. Lire
   la table du serveur ne donne alors rien d'exploitable.
5. **Un administrateur peut lire n'importe quel jeton.** C'est irréductible sous Windows, et sans conséquence : il peut
   déjà tout faire. Ce qui compte, c'est qu'un compte **standard** ne puisse lire que le sien.

### C7bis. Écrire dans le profil d'un autre compte

Possible pour `SYSTEM`, avec deux précautions : le chemin se résout par le **SID**
(`HKLM\...\ProfileList\<SID>\ProfileImagePath`) et non par le nom du compte ; et les fichiers créés appartiennent à
`SYSTEM` — il faut donc poser le propriétaire et l'ACL explicitement, sans quoi le compte ne pourrait pas lire son
propre jeton.

### C8. Le tray ne pourra plus relancer le serveur

Il n'est pas élevé et n'a aucun droit sur une tâche `SYSTEM`. Deux issues : lui donner le droit d'exécution sur cette
tâche via son SDDL (C2), ou passer par une action `admin` du serveur. La première est plus simple et se pose une fois,
à l'installation.

### C9. Divers, à ne pas oublier

- **Pas de règle de pare-feu** : l'écoute reste sur `127.0.0.1`.
- **Réservation d'URL** : inutile pour `SYSTEM`, qui a le droit d'écouter.
- **Culture** : `SYSTEM` peut avoir une culture différente de l'utilisateur. Tout formatage de date ou de nombre destiné
  à l'affichage doit être explicite (il l'est déjà : `'dd/MM/yyyy HH:mm'`).
- **Bascule rapide d'utilisateur** : plusieurs trays connectés en même temps, c'est le cas nominal. Aucun code du
  serveur ne peut plus supposer « l'utilisateur ».

---

## L'architecture corrigée

**Une porte d'entrée, deux exécutants.**

```
   session fhaza                 ┌─────────────────────────────────┐
   ┌───────────────┐             │  SERVEUR — tâche machine        │
   │     tray      │◀───ordres───│  SYSTEM, session 0, élevé       │
   │  (sa session) │────────────▶│  127.0.0.1:47600                │
   └───────────────┘   résultats │                                 │
                                 │  • sert l'interface             │
   session Famille               │  • identifie le demandeur       │
   ┌───────────────┐             │  • travail MACHINE et PRIVILÉGIÉ│
   │     tray      │◀───ordres───│  • délègue le travail PAR       │
   │  (sa session) │────────────▶│    UTILISATEUR à son tray       │
   └───────────────┘   résultats └─────────────────────────────────┘
```

**Le serveur** fait ce qui relève de la machine et ce qui exige l'élévation : verrou Windows Update, VBS, tâches
planifiées, disque, déploiement, mise à jour. Il est la seule porte HTTP — donc un seul port, pour tout le monde.

**Le tray de chaque compte** gagne un rôle : exécuter, **dans la session de son compte et avec ses droits**, ce qui n'a
de sens que là — WSL, gestionnaires de paquets, lectures `HKCU`, et les neuf actions qui ouvrent une fenêtre. Il ne
gagne aucun privilège : il fait ce que l'utilisateur pourrait faire lui-même.

**Le canal existe déjà.** Le tray lit des ordres déposés dans un dossier (`var/run`), mécanisme éprouvé pour
`restart`/`stop` et prévu pour être étendu — *« accepte de nouveaux ordres sans toucher au mécanisme »*. Il déménage
dans le profil du compte, `%LOCALAPPDATA%\Sowapps\Vigie\var\run\`,
**sous la même règle d'ACL que les jetons** (C7).

> **Le canal d'ordres est une surface d'attaque, au même titre que les jetons.** Un dossier d'ordres inscriptible
> par tous permettrait à un compte de faire exécuter quelque chose par le tray d'un **autre** compte, dans SA
> session. Il obéit donc aux mêmes trois règles : héritage coupé, ACL explicite — le compte, `SYSTEM`,
> `Administrateurs`, personne d'autre — et vérification à la lecture. **Un ordre trouvé dans un dossier dont les
> droits sont trop larges n'est pas exécuté : il est détruit et journalisé.**

### Ce qu'une action doit déclarer

**Rien de nouveau du côté des droits : ils sont déjà déclarés.** Chaque action porte son `# @droits:` depuis le début —
**15 `admin`, 26 `tous`** au 28/08/2026. Il n'y a pas de taxonomie à réinventer, seulement une sémantique à faire
tenir.

| `# @droits:` | Qui peut lancer | Ce qui change |
|---|---|---|
| `tous` | tout compte activé | Aujourd'hui l'action s'exécute avec les droits du compte. Demain elle s'exécute **dans le serveur élevé, au nom du demandeur** — c'est exactement ce qui manquait à un compte standard. |
| `admin` | comptes administrateurs uniquement | inchangé |

C'est là que se joue le besoin : `disk-cleanup`, `net-speedtest`, `wsl-shutdown` sont déjà marquées `tous`, mais un
compte standard ne peut pas les mener à bien aujourd'hui faute d'élévation. Le serveur les fera pour lui.

**Le seul axe vraiment nouveau est le lieu d'exécution**, et il découle de la nature de l'action, pas d'un arbitrage :

| `# @session:` | Où | Lesquelles |
|---|---|---|
| *(absent)* | serveur, session 0 | tout ce qui touche la machine : verrou Windows Update, disque, tâches, déploiement |
| `utilisateur` | **tray du demandeur** | les 9 `open-*`, les `wsl-*`, les `pkg-*` — elles n'ont de sens que dans sa session (C3, C4) |

**Refus par défaut sur les deux axes** : sans `@droits`, c'est `admin` ; une action `@session: utilisateur` sans tray
en ligne est refusée avec sa raison, jamais mise en attente indéfiniment.

---

## Ce que ça coûte, honnêtement

**Un service élevé sollicitable par un compte standard est un chemin d'élévation de privilèges.** Trois conditions non
négociables :

1. **Refus par défaut** — action non déclarée = `admin` ; jeton inconnu = rejet sans explication.
2. **La liste blanche vit dans le code**, jamais dans une configuration qu'un compte standard pourrait modifier.
3. **Traçabilité double** : chaque action privilégiée est écrite dans le journal de Vigie **et** dans le journal
   des événements Windows, avec le compte demandeur. « On doit toujours pouvoir retrouver et justifier une action
   de Vigie » — une trace qu'un fichier supprimé fait disparaître n'est pas une trace.
4. **Le serveur ne tourne pas en `SYSTEM`** mais sous un compte dédié, aux privilèges bornés.

S'y ajoute le coût de C6 : **un audit ligne à ligne de `Test-IsElevated`**. Une régression y serait invisible et
donnerait les droits d'administrateur à tout le monde. Cette étape ne se livre pas sans relecture dédiée.

---

## Ce que ça ne fait pas

- Aucun pouvoir supplémentaire hors liste blanche : refusé reste refusé, avec la raison affichée (D65, D66).
- Les réglages ne fusionnent pas : deux comptes gardent deux configurations.
- Pour une machine à un seul compte, rien ne change, sinon que le serveur démarre au boot plutôt qu'au logon.

---

## Ordre de travail

Chaque étape se livre seule et laisse Vigie fonctionnelle. Aucune ne commence avant que la précédente ait tourné sur
cette machine, comptes `fhaza` **et** `Famille`.

1. **Les jetons dans le profil de chaque compte**, héritage coupé, ACL explicite, vérifiée à la lecture. Le tray lit
   le sien ; le serveur n'en garde que l'empreinte. *Le serveur ne bouge pas encore* : c'est la brique d'identité,
   testable seule — et la seule dont une erreur ruinerait tout le reste.
2. **Le serveur devient une tâche machine** démarrée au boot ; le tray s'y connecte au lieu de le lancer, et reçoit le
   droit de la redémarrer (SDDL). *Les droits ne changent pas encore.*
3. **Le tray exécutant** : il sait exécuter un ordre d'action dans sa session et rendre son résultat. On y bascule d'abord
   les neuf `open-*`, les plus simples et les plus visibles.
4. **Le reste du travail par utilisateur** : WSL, gestionnaires de paquets, lectures `HKCU`.
5. **La traçabilité** : source `Vigie` dans le journal des événements Windows, posée à l'installation ; chaque
   action privilégiée y écrit avec son demandeur. *Se livre avant les droits : on veut la trace AVANT d'ouvrir des
   opérations à des comptes standard.*
6. **Les droits** : faire respecter le `@droits:` **déjà déclaré** contre le DEMANDEUR et non contre le processus —
   remplacement de `Test-IsElevated` par « le demandeur a-t-il ce droit », refus
   par défaut, journal nominatif. **Relecture dédiée.**
7. **Les données par compte** : réglages, modules actifs, notifications.
8. **La migration** des installations existantes, idempotente et réversible.

---

## Ce que la vérification des droits a appris

Deux enseignements qui dépassent les jetons, et qui valent pour tout ce que Vigie écrira désormais pour le compte de
quelqu'un d'autre.

**Un emplacement n'est pas sûr parce qu'il est « privé ».** `%LOCALAPPDATA%` est censé l'être, et sur cette machine un
outil tiers y avait ajouté un groupe en lecture. Personne ne l'avait remarqué. La seule position tenable est de **poser
l'ACL soi-même, héritage coupé, et de la revérifier à chaque usage**.

**Vérifier à l'écriture ne suffit pas.** Les droits d'un fichier changent après sa création — un outil, une stratégie
de groupe, une main humaine. Un secret dont on ne contrôle les droits qu'une fois est un secret dont on ignore l'état.
D'où la règle : **on vérifie au moment de s'en servir**, et un écart vaut compromission, pas avertissement.

---

## Ce qui a été tranché

### Sous quelle identité tourne le serveur — **un compte administrateur dédié**

Pas `SYSTEM`. C'est la bonne pratique, et elle borne ce qu'un serveur compromis pourrait faire : le compte reçoit ce
dont Vigie a besoin, et rien de plus.

**Le mot de passe n'est pas un secret à faire vivre**, contrairement à ce que je craignais. Il est généré à
l'installation, passé une seule fois à `Register-ScheduledTask`, et **Windows le conserve lui-même** dans son coffre
pour lancer la tâche. Vigie ne le garde nulle part. S'il faut réenregistrer la tâche plus tard, on en génère un
nouveau et on réinitialise le compte — opération d'administrateur, comme le reste.

Le compte est **masqué de l'écran de connexion** (`Winlogon\SpecialAccounts\UserList` à `0` — la clé que Vigie lit déjà
pour reconnaître un compte technique) et **l'ouverture de session interactive lui est refusée** : il n'existe que pour
faire tourner le service.

### Toute action privilégiée est traçable — **deux fois**

> « On doit toujours pouvoir retrouver et justifier une action de Vigie. »

Chaque action `admin` écrit **deux traces**, et l'action n'est pas considérée comme faite tant que la première n'est
pas écrite :

1. **Le journal de Vigie** — le détail : qui a demandé, quoi, avec quels paramètres, ce que le système a répondu.
2. **Le journal des événements Windows**, source `Vigie` — la trace opposable, hors de portée d'une simple suppression
   de fichier, et lisible par l'Observateur d'événements comme n'importe quel autre logiciel de la machine.

Vérifié sur cette machine : `Write-EventLog` et `New-EventLog` sont disponibles en **PowerShell 7.6.5**, et l'API .NET
`System.Diagnostics.EventLog` aussi. L'enregistrement de la source exige l'élévation — le serveur l'a, et la source se
pose à l'installation, une fois.

Ce que chaque entrée doit porter, sans exception : **le compte demandeur**, l'action, l'horodatage, le résultat. Une
action privilégiée qu'on ne peut pas rattacher à un demandeur est un trou dans la chaîne, pas un détail de journal.

### Quand une action de session est demandée sans tray en ligne — **on refuse et on le dit**

Il n'y a pas d'« agent » séparé : c'est **le tray du compte**, et son absence est déjà une information que Vigie
affiche. L'action est donc refusée sur-le-champ, avec sa raison — « cette action a besoin de votre session : ouvrez
Vigie sur ce compte ». Rien ne reste en suspens, rien ne s'exécutera plus tard à un moment inattendu.
---
---

## Réponses aux questions ouvertes

### Q1 — Le compte se reconnaît par un ticket, échangé contre un cookie de session

Trois objets distincts, qu'il ne faut pas confondre :

| | Ce que c'est | Où il vit | Durée |
|---|---|---|---|
| **Jeton** | le secret durable du compte | son profil, ACL explicite (C7) | jusqu'à révocation |
| **Ticket** | preuve à usage unique, pour amorcer la page | passé en URL par le tray | quelques secondes, une seule fois |
| **Cookie de session** | ce qui identifie la page ensuite | le navigateur, en mémoire | meurt à la fermeture du navigateur |

Le tray lit **son** jeton — qu'il est seul à pouvoir lire —, demande un ticket au serveur, et ouvre
`http://127.0.0.1:47600/?t=…`. Le serveur consomme le ticket et pose un cookie `HttpOnly`, `SameSite=Strict`, **sans
date d'expiration** — donc de session.

**La page ne détient alors aucun secret en JavaScript.** C'est un gain par rapport à l'existant, où le jeton est injecté
dans le HTML (`window.API_TOKEN`) et reste lisible par tout script de la page.

**Ce qui survit côté navigateur** : rien de sensible, ni aujourd'hui ni demain. Le `localStorage` ne porte que des
préférences d'affichage (groupes masqués, ordre des cartes). `HttpOnly` met le cookie hors de portée du JavaScript, et
l'absence d'expiration le fait mourir avec le navigateur.

### Q2 — L'environnement est un réglage explicite, et Vigie le montre

Deux environnements coexistent sur une même machine : le **dépôt** (développement) et l'**installation partagée**
(production locale). Le choix ne se devine pas : il se déclare.

- Réglage `Environnement` : `prod` **par défaut**, `dev` sur décision. Il vit dans `config.local.psd1` — c'est un choix
  de machine, comme `UpdateSource`.
- **Vigie affiche l'environnement dans lequel elle tourne.** Ne pas savoir lequel des deux répond est la porte ouverte à
  une heure perdue sur un correctif déployé au mauvais endroit.

**Le piège à traiter, signalé par l'utilisateur** : une tâche qui pointe vers un environnement pendant que le serveur
tourne dans l'autre. Le cas est réel — sur cette machine, la tâche de `fhaza` lance le dépôt pendant que celle de
`Famille` lance l'installation partagée.

C'est un **défaut de structure** au sens de D105, donc détecté et nommé comme les autres : *« la tâche de <compte>
lance l'environnement de production alors que Vigie tourne depuis le dépôt »*. Réparable d'un bouton, puisqu'il suffit
de réécrire la tâche vers le bon chemin.
