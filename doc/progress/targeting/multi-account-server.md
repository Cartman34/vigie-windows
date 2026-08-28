# Un serveur élevé par machine — conception

> **État : à valider. Rien n'est codé.**
>
> **Cette version corrige la précédente.** La première mouture recommandait « un seul serveur élevé qui fait tout ».
> En cherchant les contraintes de Windows plutôt qu'en les supposant, il apparaît qu'un serveur unique en session 0
> **casserait** la carte WSL, les cartes de gestionnaires de paquets, une partie de la carte Gaming et les neuf actions
> qui ouvrent une fenêtre. La porte d'entrée unique est conservée — c'est ce qui règle le port — mais le travail
> *propre à un utilisateur* est délégué à son propre agent.

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

### C7. Écrire dans le profil d'un autre compte

Possible pour `SYSTEM`, mais : le chemin se résout par le SID
(`HKLM\...\ProfileList\<SID>\ProfileImagePath`), les fichiers créés appartiennent à `SYSTEM` et doivent recevoir une ACL
explicite, et **le profil peut ne pas exister** tant que le compte ne s'est jamais connecté.

**Conséquence pour les jetons** : on ne les met pas dans les profils. Ils vont dans
`C:\ProgramData\Sowapps\Vigie\tokens\<SID>.token`, un fichier par compte, avec une ACL qui n'autorise **que** ce SID.
`ProgramData` existe toujours, ne dépend d'aucune session, et supprime le problème de l'œuf et de la poule : le tray
n'a pas besoin d'un jeton pour obtenir son jeton.

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
   │ tray + agent  │◀───ordres───│  SYSTEM, session 0, élevé       │
   │  (sa session) │────────────▶│  127.0.0.1:47600                │
   └───────────────┘   résultats │                                 │
                                 │  • sert l'interface             │
   session Famille               │  • identifie le demandeur       │
   ┌───────────────┐             │  • travail MACHINE et PRIVILÉGIÉ│
   │ tray + agent  │◀───ordres───│  • délègue le travail PAR       │
   │  (sa session) │────────────▶│    UTILISATEUR à son agent      │
   └───────────────┘   résultats └─────────────────────────────────┘
```

**Le serveur** fait ce qui relève de la machine et ce qui exige l'élévation : verrou Windows Update, VBS, tâches
planifiées, disque, déploiement, mise à jour. Il est la seule porte HTTP — donc un seul port, pour tout le monde.

**L'agent** est le tray, qui gagne un rôle : exécuter, **dans la session de son compte et avec ses droits**, ce qui n'a
de sens que là — WSL, gestionnaires de paquets, lectures `HKCU`, et les neuf actions qui ouvrent une fenêtre. Il ne
gagne aucun privilège : il fait ce que l'utilisateur pourrait faire lui-même.

**Le canal existe déjà.** Le tray lit des ordres déposés dans un dossier (`var/run`), mécanisme éprouvé pour
`restart`/`stop` et prévu pour être étendu — *« accepte de nouveaux ordres sans toucher au mécanisme »*. Il déménage
dans `C:\ProgramData\Sowapps\Vigie\run\<SID>\`, lisible par le serveur et par le seul compte concerné.

### Ce qu'une action doit désormais déclarer

L'en-tête `# @droits:` gagne un niveau, et un second axe apparaît — **où** l'action s'exécute.

| `# @droits:` | Qui peut lancer | Exécuté par |
|---|---|---|
| `lecture` | tout compte activé | le serveur |
| `standard` | tout compte activé | **le serveur, au nom du demandeur** |
| `admin` | comptes administrateurs | le serveur |

| `# @session:` | Où | Exemples |
|---|---|---|
| *(absent)* | serveur, session 0 | verrou Windows Update, nettoyage disque |
| `utilisateur` | **agent du demandeur** | `wsl-*`, `pkg-*`, `open-*` |

**Refus par défaut** dans les deux axes : sans `@droits`, c'est `admin` ; une action `@session: utilisateur` sans agent
connecté est refusée avec une raison claire, pas mise en attente indéfiniment.

---

## Ce que ça coûte, honnêtement

**Un service élevé sollicitable par un compte standard est un chemin d'élévation de privilèges.** Trois conditions non
négociables :

1. **Refus par défaut** — action non déclarée = `admin` ; jeton inconnu = rejet sans explication.
2. **La liste blanche vit dans le code**, jamais dans une configuration qu'un compte standard pourrait modifier.
3. **Journal nominatif** : qui a demandé quoi, et ce qui s'est passé.

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

1. **Les jetons dans `ProgramData`**, un par compte, avec leur ACL. Le tray lit le sien. *Le serveur ne bouge pas
   encore* : c'est la brique d'identité, testable seule.
2. **Le serveur devient une tâche machine** démarrée au boot ; le tray s'y connecte au lieu de le lancer, et reçoit le
   droit de la redémarrer (SDDL). *Les droits ne changent pas encore.*
3. **L'agent** : le tray sait exécuter un ordre d'action dans sa session et rendre son résultat. On y bascule d'abord
   les neuf `open-*`, les plus simples et les plus visibles.
4. **Le reste du travail par utilisateur** : WSL, gestionnaires de paquets, lectures `HKCU`.
5. **Les droits** : `@droits: standard`, remplacement de `Test-IsElevated` par « le demandeur a-t-il ce droit », refus
   par défaut, journal nominatif. **Relecture dédiée.**
6. **Les données par compte** : réglages, modules actifs, notifications.
7. **La migration** des installations existantes, idempotente et réversible.

---

## Ce qui reste à trancher — et qui ne m'appartient pas

- **Quelles actions passent en `standard`** ? Redémarrer WSL, vider le cache DNS, mesurer le débit se discutent une par
  une. Le verrou Windows Update, la mise à jour de l'installation et la gestion des comptes restent `admin`.
- **Que fait Vigie quand un compte standard demande une action `@session: utilisateur` alors qu'aucun agent n'est
  connecté** — refuser en le disant, ou proposer de réessayer ?
- **Le serveur tourne-t-il sous `SYSTEM` ou sous un compte administrateur dédié** ? `SYSTEM` est plus simple (aucun mot
  de passe à gérer) mais donne les pleins pouvoirs ; un compte dédié se restreint, au prix d'un secret à faire vivre.
