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

## Installation

> Vigie touche à Windows Update et tourne en administrateur : les trois points de
> [À lire avant d'installer](#à-lire-avant-dinstaller) valent la minute qu'ils prennent.

**Trois gestes, pas de ligne de commande.**

1. Téléchargez `vigie-<version>.zip` depuis la [page des Releases](https://github.com/Cartman34/vigie-windows/releases).
2. Décompressez-la **à un endroit durable** — ni `Téléchargements`, ni un dossier temporaire : Vigie se lancera depuis
   ce chemin à chaque ouverture de session.
3. Ouvrez le dossier obtenu et double-cliquez **`setup.cmd`**. Windows demande votre accord pour l'élévation :
   acceptez.

Vigie s'installe, s'ajoute au démarrage de votre session et s'ouvre. Il n'y a rien d'autre à faire, et rien à
réinstaller ensuite : `setup.cmd` se charge lui-même de ce qui manque sur la machine. Si vous fermez Vigie un jour,
`scripts\run.cmd` la relance.

*Si la page des Releases est vide, aucune version n'a encore été publiée : voir la voie git ci-dessous.*

**Les autres voies** — clone git, ligne de commande, rôle de chaque script, désinstallation — sont dans
[Installation](doc/fr/operating/install.md). Ce que vous avez sous les yeux au premier lancement :
[Premiers pas](doc/fr/using/getting-started.md).

## À lire avant d'installer

Vigie n'est pas un moniteur passif. Trois choses à savoir :

1. **Elle peut verrouiller Windows Update.** C'est une fonction qui s'active et se
   relâche depuis l'application, pas un état imposé. Verrou posé, les mises à jour automatiques sont
   coupées (`NoAutoUpdate`) et un verrou ACL empêche Windows de réactiver ses tâches de
   mise à jour. Aucune mise à jour ne s'installe seule, et **aucun redémarrage n'est
   jamais forcé** — mais rien ne s'installe seul non plus. Garder la machine à jour
   devient un geste *volontaire*, depuis le « Mode MAJ » de Vigie ou depuis les
   Paramètres Windows. Voir [Windows Update](doc/fr/using/windows-update.md).
2. **Elle tourne en administrateur.** Lire et appliquer ce verrou suppose d'écrire dans
   `HKLM`, de modifier des tâches planifiées et de poser des ACL. La tâche planifiée qui
   lance Vigie est enregistrée avec les privilèges les plus élevés, et un lancement
   manuel déclenche une invite UAC. Chaque élévation est expliquée dans une fenêtre
   *avant* que l'invite UAC n'apparaisse.
3. **Elle n'écoute que sur 127.0.0.1** — jamais sur une interface réseau. L'API exige un
   jeton Bearer, contrôle l'origine des requêtes et n'exécute que des actions d'une liste
   blanche figée. Il subsiste un risque résiduel connu (le jeton est injecté dans la page
   servie), décrit honnêtement dans [Sécurité](doc/fr/operating/security.md).

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

Le détail carte par carte : [Ce que surveille Vigie](doc/fr/using/features.md).

## Documentation

| | |
|---|---|
| [Sommaire de la documentation](doc/fr/README.md) | tout, sur une page |
| [Installation](doc/fr/operating/install.md) | archive ou clone git, démarrage automatique, désinstallation |
| [Premiers pas](doc/fr/using/getting-started.md) | premier lancement, icône, lecture d'une carte |
| [Ce que surveille Vigie](doc/fr/using/features.md) | chaque carte et chaque action |
| [Windows Update](doc/fr/using/windows-update.md) | le verrou, le mode MAJ, installer les mises à jour |
| [Sécurité](doc/fr/operating/security.md) | élévation, écoute locale, jeton, risque résiduel |
| [Configuration](doc/fr/operating/configuration.md) | port, outillage externe, surcharges locales |
| [Dépannage](doc/fr/using/troubleshooting.md) | journaux, commandes du tray, pannes courantes |
| **[Développement](doc/en/developing/README.md)** | architecture, sondes et actions, contribution |

## Prérequis

- **Windows 10 ou 11.**
- **Un compte administrateur** : Vigie modifie des réglages de Windows Update et enregistre une tâche de démarrage.
- **Un navigateur.** Edge ou Chrome pour la fenêtre dédiée, sans barre d'adresse ; n'importe lequel pour la page
  ordinaire.

Le reste est de la plomberie que `setup.cmd` pose lui-même — vous n'avez ni à l'installer, ni à savoir ce que c'est.
Le détail est dans [Installation](doc/fr/operating/install.md) pour qui veut le lire.

## Licence

Le dépôt ne contient pas encore de fichier de licence.
