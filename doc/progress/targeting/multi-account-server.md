# Un serveur élevé par machine — conception

> **État : à valider.** Rien n'est codé. Ce document décrit la cible, ses conséquences et ce
> qui reste à trancher. Il complète `features.md` (CORE-ACCOUNTS, CORE-SECURITY) et sera
> suivi d'une décision numérotée une fois validé.

---

## Le problème, tel qu'il a été constaté

Le 28/08/2026, Vigie ne démarrait pas sur le compte « Famille ». Deux causes se
superposaient ; la première est corrigée, la seconde est structurelle.

1. **Corrigé (D101).** Le tray calculait son journal à côté du programme. Sur un compte
   standard, Windows refuse cette écriture : le script mourait avant sa première ligne de
   journal, sans laisser de trace.
2. **Structurel.** `apps/backend-pode/start.ps1` exige l'élévation et se relance en
   `RunAs` s'il ne l'a pas. Sur un compte **standard**, cela déclenche une invite qui
   réclame le mot de passe d'un administrateur — que ce compte n'a pas, par définition.
   L'icône apparaîtrait, le serveur ne démarrerait jamais.

S'y ajoute un troisième obstacle, latent : **un seul port**. Deux sessions ouvertes
simultanément (bascule rapide d'utilisateur) et le second serveur ne peut pas s'attacher à
`127.0.0.1:47600`. Rien ne traite ce cas aujourd'hui.

## Ce que Windows autorise, et ce qu'il interdit

Deux faits cadrent toute solution :

- **Un compte standard ne peut pas s'élever.** Aucune ruse ne contourne ça : il faut les
  identifiants d'un administrateur, ou rien.
- **Une tâche planifiée est un courtier d'élévation légitime.** Elle s'exécute avec les
  droits fixés à son enregistrement — par un administrateur — et un compte sans privilège
  peut être autorisé à la déclencher **sans jamais voir d'identifiants**. C'est le
  mécanisme sanctionné par Windows, et Vigie s'en sert déjà pour démarrer.

## La cible

**Un seul serveur, élevé, pour la machine entière.** Il démarre avec la machine, pas avec
une session. Chaque compte s'y connecte depuis son propre tray, avec son propre jeton ; le
serveur sait **qui** demande et applique les droits de ce compte.

```
                 ┌──────────────────────────────────────────┐
   session       │  Serveur Vigie — UNE instance, élevée     │
   fhaza  ──────▶│  tâche machine, démarre au boot           │
   (tray)        │  127.0.0.1:47600                          │
                 │                                           │
   session       │  identifie le compte par SON jeton        │
   Famille ─────▶│  applique les droits de CE compte         │
   (tray)        │  journalise qui a demandé quoi            │
                 └──────────────────────────────────────────┘
```

Ce que ça règle, d'un coup : le compte standard obtient les opérations qu'on décide de lui
ouvrir, exécutées par le serveur **en son nom** ; et le conflit de port disparaît au lieu
d'être contourné.

## Les pièces à construire

### 1. Le démarrage

- **Une tâche machine** (`Vigie`, principal `SYSTEM` ou un administrateur), déclencheur
  « au démarrage de l'ordinateur », qui lance le serveur. Une seule, pour tous.
- **Une tâche par compte**, conservée, mais réduite à son vrai rôle : lancer **le tray** de
  ce compte, sans élévation. Le tray ne démarre plus le serveur ; il s'y connecte.
- Le tray doit savoir attendre : au logon, le serveur tourne déjà, ou il démarre — l'état
  « en attente du serveur » existe déjà (icône orange).

### 2. L'identité et les jetons

- **Un jeton par compte**, écrit par le serveur (qui est élevé, donc en a le droit) dans
  `%LOCALAPPDATA%\Sowapps\Vigie\var\secrets\` du compte, avec une **ACL qui n'autorise que
  ce compte**. Écrit au moment où le compte est activé, et recréé s'il manque.
- Le serveur tient la correspondance jeton → compte. Une requête sans jeton connu est
  refusée, sans autre explication.
- **À vérifier au moment de coder** : recouper le jeton avec le propriétaire réel du
  processus appelant (via le PID de la connexion TCP locale). Si c'est fiable, un jeton
  volé ne suffit plus. Sinon, on s'en tient au jeton et on le dit.

### 3. Les droits, par action

L'en-tête `# @droits:` existe déjà. Il gagne un troisième niveau :

| Niveau | Qui peut lancer | Exécuté comment |
|---|---|---|
| `lecture` | tout compte activé | sans privilège particulier |
| `standard` | tout compte activé | **par le serveur élevé, au nom du demandeur** |
| `admin` | comptes administrateurs uniquement | par le serveur élevé |

Le niveau `standard` est le cœur du besoin : une opération qui exige l'élévation *technique*
mais qu'on juge sans danger pour la machine. **Refus par défaut** : une action sans niveau
déclaré est `admin`.

> **À trancher — ce n'est pas à moi de le décider.** Quelles actions passent en `standard` ?
> Redémarrer WSL ? Vider le cache DNS ? Mesurer le débit ? Chacune se justifie une par une.
> Le verrou Windows Update, la mise à jour de l'installation et la gestion des comptes
> restent `admin` sans discussion.

### 4. Les données, par compte

Aujourd'hui, un processus = un `var/`. Demain, un serveur sert plusieurs comptes : il faut
séparer ce qui appartient à la machine de ce qui appartient à quelqu'un.

| Donnée | Où | Pourquoi |
|---|---|---|
| État des sondes, cache | machine | c'est la même machine pour tout le monde |
| Réglages, modules actifs, notifications | **par compte** | chacun ses choix (D65) |
| Jeton | **par compte** | c'est son identité |
| Journaux | machine, avec le compte demandeur en clair | un incident se relit d'un seul endroit |

### 5. La migration

Une installation existante a une tâche `Vigie` par compte qui lance le tray **et** le
serveur. Le passage doit être idempotent et réversible : poser la tâche machine, réécrire
les tâches de compte pour qu'elles ne lancent plus que le tray, et ne rien supprimer tant
que la nouvelle chaîne n'a pas démarré une fois.

## Le risque, nommé

**Un service élevé qu'un compte standard peut solliciter est un chemin d'élévation de
privilèges.** C'est le prix de cette architecture, et il ne se paie qu'à trois conditions,
non négociables :

1. **Refus par défaut.** Une action non déclarée est `admin`. Un jeton inconnu est rejeté.
2. **La liste blanche est dans le code**, pas dans une configuration modifiable par un
   compte standard. Sinon la barrière se déplace là où elle ne tient plus.
3. **Journal nominatif.** Chaque action privilégiée écrit qui l'a demandée, quoi, et le
   résultat. Sans ça, on ne saura jamais si la barrière a cédé.

À quoi s'ajoute ce qui est déjà vrai : écoute strictement locale, et **aucune donnée
envoyée sur Internet**.

## Ce que ça ne fait pas

- Ça ne donne **aucun pouvoir supplémentaire** à un compte standard hors de la liste
  blanche : refusé reste refusé, avec la raison affichée (D65, D66).
- Ça ne fusionne pas les réglages : deux comptes gardent deux configurations.
- Ça ne change rien pour une machine à un seul compte, sinon que le serveur démarre au boot
  plutôt qu'au logon.

## Ordre de travail proposé

1. La tâche machine et le démarrage du serveur au boot ; le tray s'y connecte au lieu de le
   lancer. *Rien ne change encore pour les droits.*
2. Les jetons par compte et l'identification du demandeur.
3. Le niveau `standard` dans `# @droits:`, refus par défaut, journal nominatif.
4. La séparation des données par compte.
5. La migration des installations existantes.

Chaque étape se livre seule et laisse Vigie fonctionnelle. Aucune ne se commence avant que
la précédente ait tourné sur cette machine, comptes `fhaza` **et** `Famille`.
