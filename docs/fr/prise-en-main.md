# Premiers pas

[Sommaire](README.md) · [English](../en/getting-started.md)

Vous avez suivi [l'installation](installation.md). Voici ce que vous avez sous les yeux.

---

## L'icône de la barre système

Une fois la tâche de démarrage enregistrée, Vigie se lance avec votre session sous forme
d'une **icône dans la zone de notification**, près de l'horloge. L'icône est une jauge, et
**sa couleur est la santé de l'application elle-même**, pas celle de votre machine :

| Couleur | Signification |
|---|---|
| Vert | le serveur tourne et répond |
| Orange | le serveur démarre |
| Rouge | le serveur est arrêté ou en erreur |

Le tray interroge `/health` toutes les 8 secondes : la couleur n'a jamais plus de quelques
secondes de retard.

**Double-clic** sur l'icône : le tableau de bord s'ouvre dans une fenêtre dédiée.
**Clic droit** : le menu.

| Entrée | Effet |
|---|---|
| **Afficher l'application** | ouvre le tableau de bord dans une fenêtre dédiée (Edge ou Chrome en mode `--app` : ni barre d'adresse, ni onglets) |
| Ouvrir dans le navigateur | ouvre le tableau de bord dans un onglet ordinaire |
| *État : …* | non cliquable — l'état courant, en toutes lettres |
| Relancer l'application | redémarre l'app de la barre système elle-même |
| Redémarrer le serveur | arrête puis relance le serveur Pode |
| Ouvrir les journaux | ouvre le dossier de journaux du serveur dans l'explorateur |
| À propos de Vigie | ouvre le dépôt GitHub |
| Quitter | ferme Vigie (le serveur s'arrête avec) |

La fenêtre dédiée exige un navigateur Chromium. À défaut, utilisez « Ouvrir dans le
navigateur ».

## Le tableau de bord

La page est sur <http://127.0.0.1:47600/>. Un écran de chargement s'affiche le temps du
premier calcul d'état, puis les cartes apparaissent.

- Le **titre principal est le nom de votre machine**, lu à l'exécution.
- Le **liseré coloré sous l'en-tête** est la connexion à l'API : vert = données en direct,
  orange = maquette (le serveur est injoignable et la page est repliée sur un jeu de
  données d'exemple), rouge = erreur.
- L'état se rafraîchit **automatiquement toutes les 60 secondes**, et la page se recharge
  d'elle-même quand une nouvelle version de l'application est servie.

### Lire une carte

Chaque carte est un **module** surveillé, regroupé par thème. Sur son bord gauche, un
**liseré coloré porte le statut de CE module** — à ne pas confondre avec le liseré sous
l'en-tête, qui parle de la connexion à l'API.

| Statut | Signification |
|---|---|
| Vert | conforme, rien à faire |
| Orange | à surveiller |
| Rouge | un problème |
| Neutre | informatif, ou non mesurable pour l'instant |

À l'intérieur, chaque ligne est un **champ** : un libellé, une valeur, et son propre
statut. Déplier un champ donne une explication en langage clair de ce que c'est — et,
quand quelque chose ne va pas, ce que vous risquez à ne rien faire et ce que vous pouvez
faire.

Un **liseré gauche qui clignote** signale une tâche de fond en cours sur cette carte (mise
à jour de paquets, analyse en ligne des MAJ, mesure réseau). La page interroge cette carte
toute seule ; vous pouvez fermer le navigateur, la tâche continue.

### Les boutons

Les boutons portent **le libellé de l'action**, jamais un « Résoudre » générique. Ils
n'apparaissent que si une action existe vraiment. L'icône dit ce qui va se passer :

| Icône | Signification |
|---|---|
| Triangle | s'exécute immédiatement |
| Triangle d'avertissement orange | demande d'abord confirmation |
| Liste cochée | ouvre une fenêtre où vous choisissez ce qui sera appliqué |
| Flèche sortante | passe la main à un logiciel externe (Paramètres Windows, nettoyage de disque, explorateur) |

---

## Votre première chose utile

Ouvrez le thème **Windows Update** et regardez la carte *Verrouillage des mises à jour*.
Elle dit si les mises à jour automatiques sont coupées, si le verrou ACL est appliqué,
combien de tâches de mise à jour sont désactivées face à celles encore actives, et si un
redémarrage est en attente.

De là, un unique bouton bascule entre **« Mode MAJ (déverrouiller) »** et **« Verrouiller
maintenant »**. Les deux demandent confirmation. Lisez
[Windows Update](windows-update.md) avant d'utiliser l'un ou l'autre : c'est la carte qui
change le comportement de votre machine.

## Ensuite

- [Ce que surveille Vigie](fonctionnalites.md) — chaque carte, chaque champ, chaque action
- [Windows Update](windows-update.md) — le verrou, en détail
- [Dépannage](depannage.md) — l'icône est rouge, la page affiche la maquette, …
