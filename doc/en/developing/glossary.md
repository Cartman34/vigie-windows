# Glossaire — les mots du projet

Un mot par notion, et le même partout : code, documentation, interface. Quand un mot manque, on l'ajoute **ici
d'abord**, puis on l'emploie. Un synonyme qui s'installe finit par désigner autre chose.

## Les deux applications

| mot | ce que ça désigne |
|---|---|
| **app serveur** | `apps/backend-pode` : PowerShell + Pode, écoute sur 127.0.0.1:47600, tourne **élevée** sous le compte de service, sans session. Elle mesure, décide des droits, exécute les actions. |
| **app cliente** | `apps/tray` : l'icône dans la zone de notification, une par compte ouvert. Elle lance le serveur si besoin, ouvre le panneau et porte les notifications Windows. |
| **panneau** | `apps/frontend-web` : la page servie par l'app serveur, celle où l'on lit les cartes. |
| **Atelier** | `apps/atelier` : outil de **développement** (PHP, port 47610, jamais élevé). Il ne fait pas partie de ce qu'on livre. |

*« tray » ne s'écrit plus dans un texte affiché : c'est **app cliente**. Le mot survit dans les chemins et identifiants
(`apps/tray/`), qui se renomment zone par zone.*

## Ce que Vigie montre

| mot | ce que ça désigne |
|---|---|
| **carte** | un bloc de l'écran : un titre, des lignes, des boutons. Elle porte un identifiant (`net`, `deployment`). |
| **groupe** | la famille d'une carte, affichée au-dessus de son titre : Comptes, Système, Réseau… |
| **champ** | une ligne d'une carte : un libellé, une valeur, un statut, une aide, parfois un bouton. |
| **statut** | `ok` · `warn` · `error` · `neutral`. Un `warn` ou un `error` **porte toujours** le geste qui le corrige (D66). |
| **action** | ce qu'un bouton déclenche. Elle déclare ses droits (`@droits`) et où elle s'exécute (`@execution`). |

## Ce qui mesure

| mot | ce que ça désigne |
|---|---|
| **module** | un dossier de `probes/` : ses sondes, sa déclaration (`module.psd1`), ses réglages, ses notifications, ses sentinelles. C'est l'unité qu'on active ou désactive. |
| **sonde** | `<nom>.probe.ps1` : elle mesure et **rend une ou plusieurs cartes**. Lecture seule, jamais d'effet de bord. |
| **sentinelle** | `<clé>.watch.ps1` : une lecture **bon marché** rendant **une valeur comparable**. L'app serveur l'exécute en permanence, même sans session ; quand la valeur **change**, elle émet un **événement** qui fait recalculer les cartes déclarées. Elle ne calcule jamais de carte elle-même. |
| **événement** | ce qu'émet une sentinelle quand sa valeur change. Il déclenche un recalcul ciblé — il ne s'affiche pas. |
| **mesure** | une **série nommée** (`disk.free`, `game.gpu`, `watch.internet`) — pas une unité. Elle a son identifiant, son dossier dans `var/history/`, sa cadence minimale, sa tolérance et sa rétention. L'unité (`Go`, `%`, `ms`) n'est qu'un de ses attributs. |
| **tolérance** | de combien une mesure doit tourner pour que ce soit un vrai retournement. En dessous, c'est du bruit, et le point intermédiaire s'efface. |
| **historique d'une sentinelle** | la suite des états d'une sentinelle, une ligne par **changement** (`watch.<clé>`), avec l'état précédent et les cartes recalculées. La mémoire de veille dit où on en est ; l'historique dit depuis quand, et combien de fois. |
| **notification** | la bulle Windows. Elle naît de la **bascule d'un champ** de carte, pas d'un événement de sentinelle (D54). |

## L'identité

| mot | ce que ça désigne |
|---|---|
| **qui exécute** | le compte sous lequel tourne le processus (`Get-ProcessAccount`). Pour l'app serveur : le compte de service. |
| **qui demande** | le compte derrière la requête (`Get-RequesterAccount`), lu dans le cookie de session. `$null` si personne ne s'est identifié. |
| **secret du compte** | le fichier du profil, protégé par une ACL explicite : c'est lui qui prouve une identité. |
| **adresse d'ouverture** | l'URL à **usage unique** (30 s) que l'app cliente présente pour ouvrir une session. Jetable par construction. |
| **session** | le cookie que l'adresse d'ouverture laisse derrière elle. Elle **ne périme pas**. |

## Le déploiement

| mot | ce que ça désigne |
|---|---|
| **stage** | `dev` ou `prod`. **Déclaré** dans `machine.psd1`, jamais déduit. Il conditionne le marquage des versions, rien d'autre. |
| **source** | d'où vient le code déployé — un réglage (`UpdateSource`, `UpdateRemote`), indépendant du stage. |
| **installation partagée** | `C:\Program Files\Sowapps\Vigie` : ce que lancent tous les comptes. |
| **clone du service** | la copie du dépôt que l'app serveur synchronise pour fabriquer une version. Le service n'écrit **jamais** dans le dépôt d'une personne. |
| **verrou d'installation** | le fichier de `%ProgramData%` qui dit qu'une installation écrit en ce moment. Il libère dès la dernière modification, pas au dernier clic. |
