# Vigie

[English](README.md) · **Français**

**Un tableau de bord local pour un PC Windows.** Vigie surveille Windows Update, le
disque, la mémoire, le réseau, WSL, la sécurité et vos gestionnaires de paquets, et
présente le tout sous forme de cartes dans une fenêtre de navigateur. Sa fonction
phare : elle **permet de verrouiller Windows Update** — verrou que vous activez ou
relâchez quand vous voulez — pour que Windows ne puisse pas redémarrer la machine tout
seul, tout en vous laissant installer les mises à jour quand *vous* l'avez décidé.

> **Rien ne sort de votre machine.** Vigie ne transmet aucune donnée sur Internet : elle
> lit l'état de votre PC, l'affiche localement, et c'est tout. Aucun compte, aucune
> télémétrie, aucun serveur distant. Le seul accès réseau qu'elle fait est celui que vous
> déclenchez vous-même : mesurer le débit, relever l'adresse IP publique, ou demander à
> un gestionnaire de paquets s'il a des mises à jour.

Dépôt : <https://github.com/Cartman34/vigie-windows>

> **Version 0.1 — pas encore publiée.** Aucune version n'est publiée, il n'y a pas
> d'installeur et aucune promesse de stabilité. Le code tourne sur la machine de
> l'auteur ; attendez-vous à des aspérités, et lisez les points ci-dessous avant de
> l'installer sur la vôtre.

---

## Démarrer

> Vigie touche à Windows Update et tourne en administrateur : les trois points de
> [À lire avant d'installer](#à-lire-avant-dinstaller) valent la minute qu'ils prennent.

La voie recommandée est l'**archive publiée dans les Releases GitHub** — ni git, ni clone.

**Un seul fichier, à la racine : `setup.cmd`. Double-cliquez-le.** Il fait tout — les prérequis,
PowerShell 7 **pour la machine**, le module Pode, le démarrage à chaque ouverture de
session, et le lancement de Vigie.

| | Fichier | Ce qu'il fait |
|---|---|---|
| 1 | **`setup.cmd`** | **L'installation complète.** Demande les droits administrateur (fenêtre Windows à accepter) : PowerShell 7 est installé **pour toute la machine**, pas pour votre seul compte. À faire **une fois**. |
| 2 | **`scripts\run.cmd`** | Relance Vigie si vous l'avez fermée. Le navigateur s'ouvre sur <http://127.0.0.1:47600/> dès que le serveur écoute vraiment. |

Avant le premier double-clic : téléchargez `vigie-<version>.zip` depuis la
[page des Releases](https://github.com/Cartman34/vigie-windows/releases) et décompressez-la
**à un endroit durable** — ni `Téléchargements`, ni un dossier temporaire : la tâche
planifiée pointera sur ce chemin. L'archive se déplie en un unique dossier
`vigie-<version>/`. *Si cette page est vide, aucune version n'a encore été taguée :
passez par git, ci-dessous.*

> **Pourquoi l'installation demande l'élévation.** Vigie démarre par une tâche planifiée,
> une par compte, et cette tâche lance `pwsh`. Un PowerShell 7 installé pour un seul
> compte (paquet du Store) vit dans son profil : les autres comptes ne pourraient pas
> démarrer Vigie. `setup.cmd` l'installe donc **pour la machine**
> (`C:\Program Files\PowerShell\7`).

En ligne de commande, si vous préférez — l'installation exige un terminal
**administrateur**, et Windows PowerShell suffit puisque `pwsh` n'est pas encore là :

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\run.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

La voie git, le rôle de chaque script et la désinstallation :
[Installation](docs/fr/installation.md). Premier lancement et lecture du tableau de
bord : [Prise en main](docs/fr/prise-en-main.md).

## À lire avant d'installer

Vigie n'est pas un moniteur passif. Trois choses à savoir :

1. **Elle peut verrouiller Windows Update.** C'est une fonction qui s'active et se
   relâche depuis l'application, pas un état imposé. Verrou posé, les mises à jour automatiques sont
   coupées (`NoAutoUpdate`) et un verrou ACL empêche Windows de réactiver ses tâches de
   mise à jour. Aucune mise à jour ne s'installe seule, et **aucun redémarrage n'est
   jamais forcé** — mais rien ne s'installe seul non plus. Garder la machine à jour
   devient un geste *volontaire*, depuis le « Mode MAJ » de Vigie ou depuis les
   Paramètres Windows. Voir [Windows Update](docs/fr/windows-update.md).
2. **Elle tourne en administrateur.** Lire et appliquer ce verrou suppose d'écrire dans
   `HKLM`, de modifier des tâches planifiées et de poser des ACL. La tâche planifiée qui
   lance Vigie est enregistrée avec les privilèges les plus élevés, et un lancement
   manuel déclenche une invite UAC. Chaque élévation est expliquée dans une fenêtre
   *avant* que l'invite UAC n'apparaisse.
3. **Elle n'écoute que sur 127.0.0.1** — jamais sur une interface réseau. L'API exige un
   jeton Bearer, contrôle l'origine des requêtes et n'exécute que des actions d'une liste
   blanche figée. Il subsiste un risque résiduel connu (le jeton est injecté dans la page
   servie), décrit honnêtement dans [Sécurité](docs/fr/securite.md).

---

## Ce qu'elle fait vraiment

| Thème | Cartes |
|---|---|
| **Windows Update** | verrouillage (MAJ automatiques, verrou ACL, tâches désactivées vs actives, redémarrage en attente), mises à jour détectées (analyse en ligne, installation au choix), historique (dernier redémarrage, WaaSMedic) |
| **Système** | édition / activation / version de Windows, espace libre de C: face à un seuil, RAM / CPU / uptime |
| **Réseau** | connexion, type de connexion, Wi-Fi, IP locale, IP publique, IPv6, MAC, VPN, mesure de latence et de débit à la demande |
| **Sécurité** | antivirus (nom, actif, à jour), profils du pare-feu, VBS et intégrité mémoire (HVCI) |
| **WSL** | installé, distribution par défaut, actif / inactif, démarrer / redémarrer / arrêter |
| **Gestionnaires de paquets** | une carte par gestionnaire trouvé dans le `PATH` (winget, Chocolatey, Scoop, npm, pnpm, Yarn, pip, pipx, Cargo, RubyGems, .NET SDK) — version, mises à jour disponibles, mise à jour en tâche de fond |

Le détail carte par carte : [Ce que surveille Vigie](docs/fr/fonctionnalites.md).

## Documentation

| | |
|---|---|
| [Sommaire de la documentation](docs/fr/README.md) | tout, sur une page |
| [Installation](docs/fr/installation.md) | archive ou clone git, démarrage automatique, désinstallation |
| [Prise en main](docs/fr/prise-en-main.md) | premier lancement, icône, lecture d'une carte |
| [Ce que surveille Vigie](docs/fr/fonctionnalites.md) | chaque carte et chaque action |
| [Windows Update](docs/fr/windows-update.md) | le verrou, le mode MAJ, installer les mises à jour |
| [Sécurité](docs/fr/securite.md) | élévation, écoute locale, jeton, risque résiduel |
| [Configuration](docs/fr/configuration.md) | port, outillage externe, surcharges locales |
| [Dépannage](docs/fr/depannage.md) | journaux, commandes du tray, pannes courantes |
| **[Développement](docs/fr/developpement/README.md)** | architecture, sondes et actions, contribution |

## Prérequis

- Windows 10 ou 11.
- **PowerShell 7** (`pwsh`), **pour la machine** (`C:\Program Files\PowerShell\7`) —
  installé par `scripts\install.ps1` s'il est absent. C'est lui que lancent les tâches de
  démarrage : une installation limitée à un compte empêcherait les autres de démarrer
  Vigie.
- Le module PowerShell **Pode** — installé par le même script.
- Les droits administrateur, pour les actions Windows Update et la tâche de démarrage.
- Un navigateur Chromium (Edge ou Chrome) pour la fenêtre applicative dédiée ; n'importe
  quel navigateur suffit pour la page simple.

Ni Node, ni étape de construction, ni gestionnaire de paquets : le front est un unique
fichier HTML statique.

## Licence

Le dépôt ne contient pas encore de fichier de licence.
