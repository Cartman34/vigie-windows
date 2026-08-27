# Premiers pas

[Sommaire](../README.md) · [English](../../en/using/getting-started.md)

Vous avez suivi [l'installation](../operating/install.md). Voici les cinq minutes qui suivent — le détail de chaque
écran est ailleurs, les liens sont en bas de page.

---

## 1. L'icône près de l'horloge

Vigie se lance avec votre session et s'installe dans la zone de notification, sous forme d'une jauge. **Sa couleur est
la santé de Vigie elle-même, pas celle de votre machine** : verte, le serveur répond ; orange, il démarre ; rouge, il
est à terre.

**Double-cliquez** dessus : le tableau de bord s'ouvre. **Clic droit** : le menu, dont « Redémarrer le serveur » et
« Ouvrir les journaux ».

## 2. Le tableau de bord

La page vit sur <http://127.0.0.1:47600/>. Le titre est le nom de votre machine. Les cartes apparaissent après un
premier calcul d'état, puis se rafraîchissent toutes les 60 secondes.

Chaque carte est un **module** surveillé. Le liseré de son bord gauche porte son statut : vert, rien à faire ; orange,
à surveiller ; rouge, un problème ; gris, informatif. À l'intérieur, chaque ligne se déplie et s'explique en langage
clair : ce que c'est, ce que vous risquez à ne rien faire, ce que vous pouvez faire.

Les boutons portent le nom de ce qu'ils font, jamais un « Résoudre » vague, et n'apparaissent que si l'action existe
vraiment.

## 3. Votre première chose utile

Ouvrez le module **Windows Update**, carte *Verrouillage des mises à jour*. Elle dit si les mises à jour automatiques
sont coupées, si le verrou est appliqué, et si un redémarrage est en attente. Un unique bouton bascule entre
**« Mode MAJ (déverrouiller) »** et **« Verrouiller maintenant »**.

Lisez [Windows Update](windows-update.md) avant d'y toucher : c'est la carte qui change le comportement de votre
machine.

---

## Pour aller plus loin

- [Ce que surveille Vigie](features.md) — le menu du tray, l'anatomie d'une carte, les icônes des boutons, puis chaque
  carte une par une
- [Windows Update](windows-update.md) — le verrou, en détail
- [Dépannage](troubleshooting.md) — l'icône est rouge, la page affiche la maquette, où sont les journaux
