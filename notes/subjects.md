# Sujets ouverts — `SXX`

Un sujet ouvert porte un **numéro court**, `S01`, `S02`… C'est un moyen de le désigner en une conversation, sans
réciter un identifiant de fonctionnalité ni redire de quoi il s'agit. **Il n'y a rien à faire ici** : ce fichier ne
décide de rien, il ne fait que **nommer** ce qui est décrit ailleurs et pointer vers l'endroit qui fait foi.

**Un numéro ne se réutilise jamais.** Un sujet réglé garde le sien, marqué clos avec sa date : une phrase écrite il y a
trois mois doit encore désigner la même chose aujourd'hui. Réattribuer `S03` rendrait faux tout ce qui a été dit avant.

**Un sujet n'est pas une tâche.** C'est une chose qui reste ouverte et sur laquelle on revient — un manque assumé, une
preuve qui n'a pas eu lieu, une dette. Ce qui se règle dans la journée n'a pas besoin d'un numéro.

## L'ordre, tel qu'il a été donné

Arbitré par l'utilisateur le 06/09, et c'est **cet ordre-là** que je suis quand il n'est pas là :

| Rang | Sujets |
|------|--------|
| **D'abord** | **S04** · **S05** · **S06** · **S07** |
| Ensuite | **S02** |
| En dernier | **S01** |

**S10** est né le 07/09, d'une gêne signalée par l'utilisateur ; il attend son rang.
**S03** et **S09** ne se classent pas : ce sont des **preuves**, et elles demandent son geste à lui, pas mon travail.
**S08** descend avec S07, par le même cliquet.

## Ouverts

| N° | Sujet | Où c'est décrit | Pourquoi c'est ouvert |
|----|-------|-----------------|-----------------------|
| **S01** | Confiance de la chaîne de mise à jour | `targeting/features.md` → `CORE-UPDATE-TRUST` | Rien ne vérifie que ce qui s'installe est bien ce qui a été publié. **Décidé le 05/09 : dans la cible, pas maintenant** — mais la chaîne d'aujourd'hui ne doit rien faire qui empêche une version future de vérifier. |
| **S02** | Les mesures par utilisateur, invisibles depuis la session 0 | `targeting/multi-account-server.md` → C4 | WSL et les gestionnaires de paquets répondent pour le compte de service, pas pour le compte qui regarde. |
| **S03** | La désinstallation n'a jamais été éprouvée en vrai | `targeting/uninstall.md` | Elle est écrite et relue, jamais exécutée : **c'est un geste de l'utilisateur, jamais le mien**. Tant qu'elle n'a pas eu lieu, on sait qu'elle est cohérente, pas qu'elle marche. |
| **S04** | L'audit Windows Update ne remonte pas dans l'interface | `implemented/status.md` → `WU-AUDIT` | Le rapport s'écrit sur disque et personne ne le voit depuis Vigie. |
| **S05** | Les actions longues ne suivent pas le contrat | `implemented/status.md` | Le suivi passe par les marqueurs d'occupation et `/operations`, pas par le `202 + jobId` que décrit le contrat. |
| **S06** | « tray » dans les identifiants | **D108** | Le vocabulaire affiché est réglé ; les dossiers, fichiers et clés gardent leur ancien nom. Par étapes, en touchant chaque zone quand on y travaille déjà. |
| **S07** | Le français dans le code | `dev/check-naming.ps1` | Trois cliquets qui ne peuvent que descendre : identifiants français, noms de fichiers français, lignes de commentaire françaises (**D115**). Ils baissent quand on passe à côté, jamais en campagne dédiée. |
| **S08** | Deux fichiers Python subsistent | **D41** | PHP est l'outil par défaut ; Python n'est toléré qu'argumenté et délimité. Cliquet posé à 2 dans `check-naming`. |
| **S09** | Preuves qui n'ont jamais eu lieu | — | L'installation sur un **second ordinateur** depuis la v1.0.0, l'alerte de **décharge batterie** pendant une partie, et l'export **imprimé pour de vrai**. Trois choses écrites que rien n'a encore confrontées au réel. |
| **S10** | Un état qui oscille notifie à chaque oscillation | `apps/tray/tray.ps1` | Mesuré le 06/09 : `gaming.hogs` a basculé `ok`↔`warn` **dix fois en quarante minutes**, soit dix bulles pour une seule situation. **Tranché par l'utilisateur le 07/09** : un même champ ne notifie pas deux fois avant **dix minutes** — le répit est par notification, un autre sujet qui se dégrade pendant ce temps sort quand même. Rejoué sur la séquence réelle du 06/09 : douze bascules, cinq bulles. Ouvert jusqu'à une partie réelle. |
| **S12** | Le numéro de version ne peut pas se publier sans session | `scripts/install.ps1` → étape du tag | Mesuré le 08/09 : le déploiement de 09 h 55 n'a posé aucun numéro, personne n'étant connecté. Le repli fait poser le tag par l'app serveur, mais **le compte de service n'a pas les identifiants git et ne peut pas les demander** : la session 0 n'a pas de bureau où afficher une invite. Publication à différer jusqu'à la première app cliente. |
| **S13** | La grosse icône des bulles est celle de Windows, pas celle de Vigie | `targeting/notifications.md` | Une bulle `NotifyIcon` ne choisit son glyphe que parmi `Info`/`Warning`/`Error`. **Traité le 10/09** : une porte, plusieurs outils rangés par préférence, et le dernier rang toujours disponible. Reste ouvert jusqu'à ce qu'une vraie notification soit vue à l'écran depuis l'app cliente, et le rang 60 (Windows App SDK) n'est pas écrit. |

## Clos

| N° | Sujet | Clos le | Comment |
|----|-------|---------|---------|
| **S11** | Les bulles s'annonçaient « PowerShell » | 07/09/2026 | Une identité déclarée pour la machine (`AppUserModelId\Sowapps.Vigie` : nom affiché et icône livrée) et portée par le processus avant que son icône n'existe — `27a2155`, maintenue à chaque passage par l'app serveur `9376ad6`. **Vu à l'écran** : la bulle porte « Vigie » et l'icône verte. |
