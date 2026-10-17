# Le panneau tient en un fichier de 3 736 lignes — ce qu'il y a dedans

**17/10/2026.** Mesure prise avant d'arbitrer comment le panneau doit être rendu (**D132**, cible
[`targeting/panel.md`](../../doc/progress/targeting/panel.md), sujet **S25**). Elle répond à une question de
l'utilisateur : « je ne sais même pas pourquoi tu as un index.html alors que tu as un serveur web ».

## Ce que pèse la page

`apps/frontend-web/index.html` : **3 736 lignes, 228 Ko**, un seul fichier qui porte le style, le script et le
balisage du panneau entier.

| Ce qu'il y a dedans | Lignes |
|---|---|
| script d'amorçage, dans l'en-tête | 47 |
| **style** | **784** |
| balisage | 83 |
| **script principal** | **2 810** |
| commentaires (dont 639 comptés comme français) | 741 |

Le balisage ne fait que 83 lignes parce que **le HTML est fabriqué dans le JavaScript** : cartes, champs, fenêtres
et réglages sont assemblés en chaînes de caractères puis injectés.

## Ce que le script contient

Douze sections, déjà nommées par leurs propres bannières — ce sont elles qui servent de lignes de fracture :
constantes, détection du mode, ordre des cartes (D92), mode réorganisation, notifications, opérations partagées
(D95), composant de fenêtre, verrou pendant une opération, réglages, composants d'interface, démarrage.

Et des vues qu'on ne voit pas en lisant le sommaire : **six fenêtres** distinctes (choix des mises à jour,
arborescence du disque, détail d'un champ, détail d'une carte, récapitulatif de partie, parties précédentes) et
**cinq onglets** de réglages (apparence, modules, notifications, utilisateurs, à propos).

## Comment la page est servie aujourd'hui

La route lit le fichier et remplace un marqueur par le jeton de session — deux lignes. Le **moteur de vues de
Pode n'est pas utilisé du tout**, alors qu'il est livré avec : `Set-PodeViewEngine` connaît le type `Pode`
(gabarit dynamique) et `Use-PodePartialView` inclut une vue partielle dans une autre. Vérifié sur le Pode installé
sur cette machine.

## Pourquoi ça compte

Aucune décision ne portait la question : la page existait avant le serveur, qui n'a eu qu'à la servir. Rien n'a
donc jamais été enfreint — et le fichier a grossi à chaque ajout. C'est la même mécanique qui a produit l'autre
monolithe du dépôt, `apps/backend-pode/lib/common.ps1`, **11 791 lignes, 615 Ko** (sujet **S28**).

Le coût ne se lit pas seulement à l'écran : ce fichier pèse sur chaque analyse du dépôt — c'est l'un des deux
leviers nommés dans [le relevé du 15/10](2026-10-15-what-makes-check-coherence-slow.md) sur le coût de la
validation.
