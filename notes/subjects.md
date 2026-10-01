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
| **D'abord** | ~~S04~~ · ~~S06~~ (clos le 30/09) · **S05** · **S07** |
| Ensuite | **S02** |
| En dernier | **S01** |

**S14** est né le 12/09, d'un défaut signalé par l'utilisateur ; il attend son rang.
**S15** est né le 13/09, d'un déploiement bloqué ; il attend son rang.
**S03** et **S09** ne se classent pas : ce sont des **preuves**, et elles demandent son geste à lui, pas mon travail.
**S08** descend avec S07, par le même cliquet.

## Revue du 30/09/2026 — ce qui est encore d'actualité

Chaque sujet ouvert a été **revérifié dans le code**, pas dans le souvenir. Ce que cette revue a changé :

- **S02 a avancé sans être clos.** Le mécanisme qui lui manquait existe depuis le 29/09 : l'app serveur demande à une
  app cliente de mesurer dans SA session (`Invoke-DesktopAction`, action `wsl-usage`), et la carte Stockage affiche ce
  que WSL ne rend pas. Reste à faire passer par ce chemin les **gestionnaires de paquets** (winget, pip, npm, scoop) et
  les lectures `HKCU` du module Jeux, qui répondent encore pour le compte de service.
- **S10 est clos** : le répit de dix minutes a été éprouvé sur une vraie partie (six bascules, deux bulles).
- **S14 reste ouvert et s'est élargi** : `Invoke-RefreshPass` a rejoint `Get-State` dans la liste des lancements
  détachés hors protocole (`check-operations.ps1`). C'est assumé et déclaré, pas réglé.
- **S04 était bien d'actualité, et il est clos le jour même** : l'audit s'écrivait sur disque sans remonter
  (`status.md` → WU-AUDIT) ; il s'affiche maintenant dans le panneau.
- **S06 était bien d'actualité, et il est clos le même jour** : 37 fichiers portaient encore le mot banni dans
  leurs identifiants ; il n'est plus écrit nulle part, et un quatrième cliquet le tient à zéro.
- **S05, S07, S08, S01, S03, S09, S15 sont inchangés**, vérifiés un par un le 30/09 : aucun `202 + jobId` n'existe
  (le contrat le dit noir sur blanc), et les trois cliquets sont à 450 identifiants / 5 607 commentaires /
  3 noms de fichiers, plus 2 fichiers Python.

## Ouverts

| N° | Sujet | Où c'est décrit | Pourquoi c'est ouvert |
|----|-------|-----------------|-----------------------|
| **S01** | Confiance de la chaîne de mise à jour | `targeting/features.md` → `CORE-UPDATE-TRUST` | Rien ne vérifie que ce qui s'installe est bien ce qui a été publié. **Décidé le 05/09 : dans la cible, pas maintenant** — mais la chaîne d'aujourd'hui ne doit rien faire qui empêche une version future de vérifier. |
| **S02** | Les mesures par utilisateur, invisibles depuis la session 0 | `targeting/multi-account-server.md` → C4 | WSL et les gestionnaires de paquets répondent pour le compte de service, pas pour le compte qui regarde. |
| **S03** | La désinstallation n'a jamais été éprouvée en vrai | `targeting/uninstall.md` | Elle est écrite et relue, jamais exécutée : **c'est un geste de l'utilisateur, jamais le mien**. Tant qu'elle n'a pas eu lieu, on sait qu'elle est cohérente, pas qu'elle marche. |
| **S05** | Les actions asynchrones ne suivent pas le contrat | `implemented/status.md` | Le suivi passe par les marqueurs d'occupation et `/operations`, pas par le `202 + jobId` que décrit le contrat. |
+
| **S07** | Le français dans le code | `dev/check-naming.ps1` | Trois cliquets qui ne peuvent que descendre : identifiants français, noms de fichiers français, lignes de commentaire françaises (**D115**). Ils baissent quand on passe à côté, jamais en campagne dédiée. |
| **S08** | Deux fichiers Python subsistent | **D41** | PHP est l'outil par défaut ; Python n'est toléré qu'argumenté et délimité. Cliquet posé à 2 dans `check-naming`. |
| **S09** | Preuves qui n'ont jamais eu lieu | — | L'installation sur un **second ordinateur** depuis la v1.0.0, l'alerte de **décharge batterie** pendant une partie, et l'export **imprimé pour de vrai**. et une notification née de la **boucle de l'app cliente** plutôt que d'un script. Quatre choses écrites que rien n'a encore confrontées au réel. |
| **S12** | Le numéro de version ne peut pas se publier sans session | **D123** | **Clos le 14/09** : un déploiement ne pose plus de numéro, il n'a donc plus rien à publier. Mesuré le 08/09 : le déploiement de 09 h 55 n'avait posé aucun numéro, personne n'étant connecté. |
| **S14** | Les opérations ne suivent pas toutes le même protocole | `targeting/operations.md` · `implemented/operations.md` · **D82** | Constaté le 12/09 : une installation Windows Update annoncée terminée dès son départ, puis une carte figée sur « Démarrage… ». Le 13/09, les quatre opérations passent par `Start-Operation`, éprouvé en production sur `vigie-update` seulement. La relance du serveur reste hors protocole, arbitré le 13/09. Reste à éprouver Windows Update, le disque et les paquets, et à trancher si les passes internes rejoignent `/operations`. Preuve : `notes/evidence/2026-09-12-operations-outside-the-protocol.md`. |
| **S15** | Des pièces de Vigie sans réponse à certaines situations de leur vie | `targeting/components.md` · `implemented/components.md` · **D112** | Constaté le 13/09 : le déploiement s'est arrêté parce que le clone du service refusait les étiquettes déplacées par la réécriture d'historique du 11/09. Le même jour, le clone est corrigé et éprouvé ; journaux, droit de session, source du journal d'événements, confiance git, source disparue et compte de service reçoivent leur réponse, **non éprouvée en réel**. Restent les manques que `implemented/components.md` marque « aucune réponse ». Preuve : `notes/evidence/2026-09-13-service-clone-blocked-by-rewritten-tags.md`. |

## Clos

| N° | Sujet | Clos le | Comment |
|----|-------|---------|---------|
| **S06** | Le mot banni dans les identifiants | 30/09/2026 | Renommé en une fois, et non par zones : `apps/client/`, `client.ps1`, `scripts/client.ps1`, `Get-ClientHeartbeat`, `client.alive`, `CORE-CLIENT`, les clés de libellés, les commentaires, la documentation. Le risque des chemins déjà posés était éteint depuis le 29/09 (`New-VigieClientAction`). `check-naming` tient un plafond de **zéro**. Trouvé au passage : `update-mode-on.action.ps1` n'analysait plus depuis `d1f7a64`, d'où le nouveau `check-powershell`. |
| **S16** | Un module éteint n'est plus jamais recalculé, et sa carte sert ce qu'elle avait | 30/09/2026 | Quatre défauts distincts, tous mesurés sur la machine avant et après. Un module allumé par un compte était **éteint pour l'ordonnanceur**, qui calcule sans demandeur. À retard égal, le tri en prenait trois au hasard : **deux calculs n'avaient jamais tourné** depuis le premier jour. Un **lancement refusé** ne laissait aucune trace et se répétait indéfiniment. Et une **mesure par compte** était calculée dans une entrée que personne ne lit — la carte WSL était recalculée toutes les cinq minutes et affichait 31 h. Chaque carte porte désormais sa date, son dernier départ, son dernier passage et ses échecs, lisibles depuis son menu, avec la teinte sur le bouton quand elle sort de son intervalle. |
| **S04** | L'audit Windows Update ne remonte pas dans l'interface | 30/09/2026 | Le rapport revient par le canal ordinaire d'une action (`result.detail`) et la page l'ouvre dans une fenêtre large, préformatée : colonnes tenues, lignes longues repliées. Générique, donc `accounts-details` et `repair-tasks` se lisent droit du même coup. Le fichier reste sous `var/log/`, nommé sous le rapport. Ses lignes sont devenues de l'interface, donc elles portent leurs accents. |
| **S10** | Un état qui oscille notifie à chaque oscillation | 30/09/2026 | Le répit de dix minutes par notification est **éprouvé en usage réel** : sur le compte Famille le 28/09, `gaming.hogs` a produit **six bascules, deux bulles, quatre retenues** (`client_20260928.log`). C'est la partie réelle qu'attendait ce sujet. |
| **S11** | Les bulles s'annonçaient « PowerShell » | 07/09/2026 | Une identité déclarée pour la machine (`AppUserModelId\Sowapps.Vigie` : nom affiché et icône livrée) et portée par le processus avant que son icône n'existe — `a376f76`, maintenue à chaque passage par l'app serveur `21e63d1`. **Vu à l'écran** : la bulle porte « Vigie » et l'icône verte. |
| **S13** | La grosse icône des bulles était celle de Windows | 11/09/2026 | Une bulle `NotifyIcon` ne choisit son glyphe que parmi `Info`/`Warning`/`Error`. Réglé par une **porte** (`targeting/notifications.md`) : plusieurs outils rangés par préférence, le premier qui sait afficher gagne, et le dernier rang reste toujours disponible. **Vu à l'écran le 10/09**, captures de l'utilisateur : quatre notifications portant les icônes de Vigie, verte et orange, rendues à l'identique par les deux premiers rangs. Je l'ai gardé ouvert un jour de trop contre une condition que j'avais ajoutée moi-même — que la notification vienne de la boucle de l'app cliente — qui ne dit rien sur l'icône et appartient à **S09**. Le rang 60 (Windows App SDK) n'est toujours pas écrit, et n'a pas à l'être : les rangs 20 et 40 affichent. |
