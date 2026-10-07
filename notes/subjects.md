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
| **D'abord** | ~~S04~~ · ~~S06~~ (clos le 30/09) · ~~S05~~ (clos le 07/10) · **S07** |
| Ensuite | ~~S02~~ (clos le 06/10) |
| En dernier | **S01** |

**S14** est né le 12/09, d'un défaut signalé par l'utilisateur ; il attend son rang.
**S15** est né le 13/09, d'un déploiement bloqué ; il attend son rang.
**S03** et **S09** ne se classent pas : ce sont des **preuves**, et elles demandent son geste à lui, pas mon travail.
**S08** descend avec S07, par le même cliquet.
**S17** et **S18** sont nés le 06/10 et clos le jour même : l'un d'un mot que j'avais inventé, l'autre d'une action
supprimée qui restait installée. Aucun n'a eu besoin d'un rang.

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

## Revue du 05/10/2026 — ce que la vérification dans le code a changé

Chaque sujet ouvert relu **dans le code**, pas dans la revue précédente. Quatre ont rétréci, un est périmé, deux sont
inchangés.

- **S05 est périmé tel qu'il est écrit.** Il mesure le code contre un contrat « 202 + jobId » qui **n'existe plus
  nulle part** : ni dans le besoin (`features.md` → `CORE-OPERATIONS`), ni dans la conception
  (`targeting/operations.md`), qui définit le protocole comme les **marques d'occupation servies par `/operations`** —
  exactement ce que fait le code. Le contrat cité a été remplacé les 12 et 13/09 par D82, D94, D95 et D102. Ce qui
  reste de vrai dans S05 — toutes les opérations ne suivent pas ce protocole — est **déjà S14**. À requalifier ou à
  clore ; ce n'est pas à moi d'en décider, c'est toi qui l'as classé premier.
- **S02 a avancé le 06/10, et ne garde qu'un manque : la recherche de mises à jour.** L'action `pkg-inventory`
  (`@execution: session`) et `Update-PkgInventory` font remonter la **présence et la version** de chaque gestionnaire
  depuis la session du compte. Constaté : winget, absent du panneau, y est — version 1.29.380, lu dans la session de
  Famille, et la carte le dit. Relevé : `evidence/2026-10-06-winget-invisible-to-the-service-account.md`.
- **Ce qui était écrit le 05/10, et qui tient toujours : S02 ne portait plus que les gestionnaires de paquets.** Les lectures `HKCU` du module Jeux et de la
  carte WSL sont faites : `Get-UserRegistryRoots` lit la ruche de **chaque** compte connecté (D113), et
  `30-gamebar.ps1` comme `wsl.probe.ps1` passent par là. Restent `winget`, `pip`, `npm` et `scoop`, qui répondent
  encore pour le compte de service (`packages.probe.ps1`, `Invoke-Native` direct).
- **S09 a perdu une de ses quatre preuves, et c'est la bonne.** Une notification née de la **boucle de l'app
  cliente** a eu lieu : `[2026-10-05 15:02:53] notification : network.ports-low ok->warn`, puis
  `notification montree par 20-winrt-com` (`client_20261004.log`). La ligne est écrite dans la boucle elle-même
  (`client.ps1`), pas par un script d'essai. Restent trois preuves : second ordinateur, décharge batterie en partie,
  export imprimé.
- **S15 a rétréci.** Plus aucune pièce n'est marquée « aucune réponse » dans `implemented/components.md`. Restent
  **deux réponses jamais vérifiées** — l'état cassé de `var/history` et celui des bascules VBS/HVCI — et une purge
  jamais exécutée (`service-data-reset` avec `part = history`).
- **S14 est inchangé, et vérifié.** `check-operations.ps1` déclare toujours deux lancements détachés hors protocole
  (`Get-State`, `Invoke-RefreshPass`), et `vigie-update` reste la **seule** opération éprouvée en production — deux
  fois aujourd'hui, code 0 en 124 s. Windows Update, le disque et les paquets n'ont toujours pas tourné sous
  protocole.
- **S07, S08, S01, S03 sont inchangés.** Les cliquets sont à **450** identifiants, **5 607** commentaires, **3** noms
  de fichiers, **2** fichiers Python — mesurés aujourd'hui. S01 est reporté par ta décision du 05/09, S03 attend ton
  geste.

## Revue du 07/10/2026 — après une journée de travail

- **S02 est clos.** Son dernier manque — les gestionnaires de paquets — est traité : présence, version, recherche de
  mises à jour et installation passent par la session du compte. Trouvé en chemin, et mesuré : **l'app serveur ne
  peut pas exécuter winget**, un paquet MSIX refusant de se lancer pour un compte où il n'est pas enregistré.
- **S14 a avancé sans être clos.** `disk-analyze` (613 s) et `pkg-check-updates` sont éprouvées sous protocole, et
  `/operations` donne enfin le **numéro de processus** que la marque portait. Reste **une seule chose** : l'installation Windows Update, geste du propriétaire ; et un **défaut**, non une question ouverte : ce que Vigie fait d'elle-même
  sur minuterie n'apparaît nulle part, alors que `CORE-OPERATIONS` demande que **toute** opération asynchrone se
  voie tant qu'elle dure. La conception écrivait « n'est pas tranché, aucune demande ne le couvre » ; c'était faux,
  et c'est corrigé le 07/10.
- **S15 a avancé sans être clos.** L'état cassé de `var/history` est vérifié **et corrigé** : le verrou passe de la
  session à la machine (`Global\`), l'écriture devient entière ou rien, et la lecture **compte les lignes
  écartées**. Restent la purge jamais exécutée et les bascules VBS/HVCI, hors de ma portée.
- **S05 est clos**, périmé : il mesurait le code contre un contrat qui n'existe plus nulle part. Ce n'était pas un
  arbitrage — une règle écrite y répondait, et il suffisait de la lire.
- **S07, S08, S01, S03, S09 sont inchangés.** Les cliquets sont à **450** identifiants, **5 603** commentaires
  (en baisse de 4 aujourd'hui), **3** noms de fichiers, **2** fichiers Python, et **zéro** pour les deux mots bannis.

## Ouverts

| N° | Sujet | Où c'est décrit | Pourquoi c'est ouvert |
|----|-------|-----------------|-----------------------|
| **S01** | Confiance de la chaîne de mise à jour | `targeting/features.md` → `CORE-UPDATE-TRUST` | Rien ne vérifie que ce qui s'installe est bien ce qui a été publié. **Décidé le 05/09 : dans la cible, pas maintenant** — mais la chaîne d'aujourd'hui ne doit rien faire qui empêche une version future de vérifier. |
| **S03** | La désinstallation n'a jamais été éprouvée en vrai | `targeting/uninstall.md` | Elle est écrite et relue, jamais exécutée : **c'est un geste de l'utilisateur, jamais le mien**. Tant qu'elle n'a pas eu lieu, on sait qu'elle est cohérente, pas qu'elle marche. |
| **S07** | Le français dans le code | `dev/check-naming.ps1` | Trois cliquets qui ne peuvent que descendre : identifiants français, noms de fichiers français, lignes de commentaire françaises (**D115**). Ils baissent quand on passe à côté, jamais en campagne dédiée. **Avancé le 07/10** : trois fichiers vidés — `vigie-fetch.ps1`, `check-probes.ps1`, `disk-scan.worker.ps1` — soit **450 → 404** identifiants, 10 % du total. Chacun **exécuté avant et après sur la même entrée**, sortie comparée à l'identique : c'est la seule preuve qui tient, un renommage qui parse pouvant très bien ne plus marcher ([relevé](evidence/2026-10-07-a-rename-that-parsed-and-no-longer-worked.md)). **Puis `common.ps1` le même jour**, la tranche la plus critique : c'est la bibliothèque que toutes les sondes et toutes les actions lisent, et celle dont je recopie le style, donc celle qui **reproduisait** la dette. **127 → 19**, soit 108 noms et 358 occurrences ; compte du dépôt **404 → 296**. Prouvé sur `check-probes -All`, sur la structure des 19 sondes et sur `Get-State` — identique au canon dans les trois cas. Deux gardes mécaniques y ont été bâties : une qui refuse de fusionner deux noms employés dans la même portée (55 proposées, 2 refusées), une qui empêche l'outil d'écrire un remplacement vide — il avait vidé les 10 000 lignes de leurs noms, rattrapé par le reparsage. Restent 296, dont **55 dans `index.html`** ; dans `common.ps1`, 4 paramètres et 4 clés de contrat lues par le front, qui changent un protocole : décision séparée. |
| **S08** | Deux fichiers Python subsistent | **D41** | PHP est l'outil par défaut ; Python n'est toléré qu'argumenté et délimité. Cliquet posé à 2 dans `check-naming`. |
| **S09** | Preuves qui n'ont jamais eu lieu | — | L'installation sur un **second ordinateur** depuis la v1.0.0, l'alerte de **décharge batterie** pendant une partie, et l'export **imprimé pour de vrai**. et une notification née de la **boucle de l'app cliente** plutôt que d'un script. Quatre choses écrites que rien n'a encore confrontées au réel. |
| **S12** | Le numéro de version ne peut pas se publier sans session | **D123** | **Clos le 14/09** : un déploiement ne pose plus de numéro, il n'a donc plus rien à publier. Mesuré le 08/09 : le déploiement de 09 h 55 n'avait posé aucun numéro, personne n'étant connecté. |
| **S14** | Les opérations ne suivent pas toutes le même protocole | `targeting/operations.md` · `implemented/operations.md` · **D82** | Constaté le 12/09 : une installation Windows Update annoncée terminée dès son départ, puis une carte figée sur « Démarrage… ». Le 13/09, les quatre opérations passent par `Start-Operation`, éprouvé en production sur `vigie-update` seulement. La relance du serveur reste hors protocole, arbitré le 13/09. Reste à éprouver Windows Update, le disque et les paquets, et le défaut des **tâches de veille**, invisibles dans `/operations`, **corrigé le 07/10** : chacune est entourée par `Invoke-WatchTask`, porte son plafond, et un dépassement est publié, rapporté en résultat et remonté en bulle. Preuve : `notes/evidence/2026-09-12-operations-outside-the-protocol.md`. **Avancé le 06/10** : `disk-analyze` (613 s, 374 316 dossiers) et `pkg-check-updates` (Chocolatey et pip) éprouvées sous protocole, marque et résultat constatés. Trouvé au passage : `/operations` ne recopie pas le **numéro de processus** que la marque porte, alors que le protocole en fait la seule porte de lecture ([relevé](evidence/2026-10-06-three-operations-run-under-the-protocol.md)). |
| **S15** | Des pièces de Vigie sans réponse à certaines situations de leur vie | `targeting/components.md` · `implemented/components.md` · **D112** | Constaté le 13/09 : le déploiement s'est arrêté parce que le clone du service refusait les étiquettes déplacées par la réécriture d'historique du 11/09. Le même jour, le clone est corrigé et éprouvé ; journaux, droit de session, source du journal d'événements, confiance git, source disparue et compte de service reçoivent leur réponse, **non éprouvée en réel**. Restent les manques que `implemented/components.md` marque « aucune réponse ». Preuve : `notes/evidence/2026-09-13-service-clone-blocked-by-rewritten-tags.md`. **Avancé le 06/10** : l'état cassé de `var/history` est **vérifié** — rien ne casse, une ligne illisible est écartée, mais un fichier entièrement corrompu rend zéro point **sans un mot**, indiscernable d'une mesure jamais relevée ([relevé](evidence/2026-10-06-what-vigie-answers-when-its-history-is-broken.md)). Restent la purge jamais exécutée et les bascules VBS/HVCI, hors de ma portée. |

## Clos

| N° | Sujet | Clos le | Comment |
|----|-------|---------|---------|
| **S02** | Les mesures par utilisateur, invisibles depuis la session 0 | 06/10/2026 | Tout ce qui appartient à un compte se lit dans sa session. WSL et les lectures de registre l'étaient déjà ; les **gestionnaires de paquets** ont suivi le 06/10 — présence et version (`pkg-inventory`), recherche de mises à jour et **installation** (`pkg-updates`, en tâche cliente). L'app serveur **ne peut pas exécuter winget** : paquet MSIX, « Accès refusé », quel que soit son privilège. Constaté sur la machine : carte winget 1.29.380, portée `user`, chemin du compte qui regarde, 17 mises à jour listées, et une mise à jour d'un seul paquet qui ne touche que lui. Arbitré par **D128**. |
| **S17** | Un terme de conception inventé, jamais validé, posé dans le code | 06/10/2026 | « tâche serveur » et « tâche cliente » entrent au glossaire — une tâche porte le nom de l'application qui l'exécute, comme « app serveur » et « app cliente ». Le terme inventé disparaît du code, des journaux et de la conception ; `Invoke-DesktopAction` devient `Invoke-ClientTask`, les fichiers d'échange suivent. Cinquième cliquet à zéro dans `check-naming`. Éprouvé : une tâche cliente a traversé le canal renommé. Arbitré par **D129**. |
| **S18** | Une pièce retirée de la source survit dans l'installation | 06/10/2026 | `Copy-InstallFrom` ne supprimait qu'à deux niveaux : une action supprimée de la source restait **installée et appelable**, avec ses droits. La suppression couvre désormais toute l'arborescence, `var/` excepté, par `Remove-InstallSurplus`. Éprouvé sur dossiers jetables (action retirée à trois niveaux supprimée, action gardée intacte, `var/` intact), puis **constaté en vrai** : l'action de mesure temporaire a disparu de l'installation au déploiement suivant. |
| **S05** | Les actions asynchrones ne suivent pas le contrat | 07/10/2026 | **Périmé.** Il mesurait le code contre un contrat « 202 + jobId » qui n'existe **nulle part** : ni dans le besoin (`features.md` → `CORE-OPERATIONS`), ni dans la conception (`targeting/operations.md`), qui définit le protocole par les **marques servies par `/operations`** — exactement ce que fait le code. Le contrat cité avait été remplacé les 12 et 13/09 par D82, D94, D95 et D102, sans que ce sujet soit relu. Ce qui restait de vrai — toutes les opérations ne sont pas éprouvées — est **S14**. |
| **S06** | Le mot banni dans les identifiants | 30/09/2026 | Renommé en une fois, et non par zones : `apps/client/`, `client.ps1`, `scripts/client.ps1`, `Get-ClientHeartbeat`, `client.alive`, `CORE-CLIENT`, les clés de libellés, les commentaires, la documentation. Le risque des chemins déjà posés était éteint depuis le 29/09 (`New-VigieClientAction`). `check-naming` tient un plafond de **zéro**. Trouvé au passage : `update-mode-on.action.ps1` n'analysait plus depuis `d1f7a64`, d'où le nouveau `check-powershell`. |
| **S16** | Un module éteint n'est plus jamais recalculé, et sa carte sert ce qu'elle avait | 30/09/2026 | Quatre défauts distincts, tous mesurés sur la machine avant et après. Un module allumé par un compte était **éteint pour l'ordonnanceur**, qui calcule sans demandeur. À retard égal, le tri en prenait trois au hasard : **deux calculs n'avaient jamais tourné** depuis le premier jour. Un **lancement refusé** ne laissait aucune trace et se répétait indéfiniment. Et une **mesure par compte** était calculée dans une entrée que personne ne lit — la carte WSL était recalculée toutes les cinq minutes et affichait 31 h. Chaque carte porte désormais sa date, son dernier départ, son dernier passage et ses échecs, lisibles depuis son menu, avec la teinte sur le bouton quand elle sort de son intervalle. |
| **S04** | L'audit Windows Update ne remonte pas dans l'interface | 30/09/2026 | Le rapport revient par le canal ordinaire d'une action (`result.detail`) et la page l'ouvre dans une fenêtre large, préformatée : colonnes tenues, lignes longues repliées. Générique, donc `accounts-details` et `repair-tasks` se lisent droit du même coup. Le fichier reste sous `var/log/`, nommé sous le rapport. Ses lignes sont devenues de l'interface, donc elles portent leurs accents. |
| **S10** | Un état qui oscille notifie à chaque oscillation | 30/09/2026 | Le répit de dix minutes par notification est **éprouvé en usage réel** : sur le compte Famille le 28/09, `gaming.hogs` a produit **six bascules, deux bulles, quatre retenues** (`client_20260928.log`). C'est la partie réelle qu'attendait ce sujet. |
| **S11** | Les bulles s'annonçaient « PowerShell » | 07/09/2026 | Une identité déclarée pour la machine (`AppUserModelId\Sowapps.Vigie` : nom affiché et icône livrée) et portée par le processus avant que son icône n'existe — `a376f76`, maintenue à chaque passage par l'app serveur `21e63d1`. **Vu à l'écran** : la bulle porte « Vigie » et l'icône verte. |
| **S13** | La grosse icône des bulles était celle de Windows | 11/09/2026 | Une bulle `NotifyIcon` ne choisit son glyphe que parmi `Info`/`Warning`/`Error`. Réglé par une **porte** (`targeting/notifications.md`) : plusieurs outils rangés par préférence, le premier qui sait afficher gagne, et le dernier rang reste toujours disponible. **Vu à l'écran le 10/09**, captures de l'utilisateur : quatre notifications portant les icônes de Vigie, verte et orange, rendues à l'identique par les deux premiers rangs. Je l'ai gardé ouvert un jour de trop contre une condition que j'avais ajoutée moi-même — que la notification vienne de la boucle de l'app cliente — qui ne dit rien sur l'icône et appartient à **S09**. Le rang 60 (Windows App SDK) n'est toujours pas écrit, et n'a pas à l'être : les rangs 20 et 40 affichent. |

## Réanalyse de S14, le 07/10

**`Start-DetachedAction` n'a pas à rejoindre le protocole**, et c'est la réponse après l'avoir relu dans le code.
Ses deux appelants recalculent une sonde : l'ordonnanceur (`Invoke-RefreshPass`) et le rattrapage en cours de
requête (`Get-State`). Les faire passer par `Start-Operation` poserait une marque d'occupation à **chaque recalcul
de carte**, donc en permanence — exactement le bruit supprimé le 07/10 pour les tâches de veille.

**Et leur échec n'est pas muet** : un calcul de l'ordonnanceur qui échoue est compté (`fails`, `lastError`) et
remonte sur la fraîcheur de la carte depuis **S16**, lisible depuis son menu. Le rattrapage porte sur les mêmes
sondes : son échec est donc vu par le même compteur.

L'exemption est déclarée dans `check-operations.ps1`, pas subie.

**Il ne reste donc à S14 qu'une preuve, et elle demande un geste du propriétaire** : éprouver l'installation
Windows Update sous protocole. Je n'installe pas de mise à jour.
