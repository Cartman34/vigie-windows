# Les notifications de bureau — une porte, plusieurs outils

Besoin : `features.md`, entrée `CORE-NOTIFY`. Voisin : [surveillance.md](surveillance.md), qui décrit **ce qui**
déclenche une notification — cette page ne parle que de la **montrer**. Ce qui a été essayé et ce que chaque essai a
répondu : [`notes/proofs/2026-09-10-notification-api-reachability.md`](../../../notes/proofs/2026-09-10-notification-api-reachability.md).

## Le manque

L'app cliente appelait `ShowBalloonTip` directement, à cinq endroits. Cet appel décide de tout : la grosse icône ne
peut être qu'un des trois glyphes de Windows, le texte tient sur deux lignes, aucun bouton n'est possible. Changer
d'outil demandait donc de récrire les cinq appelants, et chaque outil candidat a ses conditions — la vraie API de
notification n'est pas atteignable depuis PowerShell 7, celle que Microsoft recommande vit dans un SDK qu'il faut
installer.

Le défaut n'est pas le choix de l'outil. C'est qu'il n'y avait **pas de place** où le changer.

## La porte

L'app cliente décrit un **événement**, jamais un affichage :

| | |
|---|---|
| **Sujet** | ce qui a changé, nommé — « Applications gourmandes pendant une partie » |
| **État** | rétabli, à surveiller, en erreur |
| **Mesure** | ce qu'on a relevé, quand il y a quelque chose à relever — « Chrome et 2 autres » |
| **Urgence** | de quoi choisir une icône et une durée, pas de quoi choisir un outil |

Elle ne nomme ni glyphe, ni fichier d'icône, ni API. **Ce vocabulaire est le contrat** : un outil qui ne sait pas
rendre l'un de ces quatre éléments le laisse tomber, il ne renégocie pas.

## Les outils

Un fichier par outil, dans `apps/tray/notify/`, **rangés par préférence** — le nom porte son rang, comme les méthodes
d'identification des jeux (`probes/gaming/identify/`). Chacun répond à une seule question : *ici, maintenant, sais-tu
montrer ceci ?* Le premier qui montre gagne, on s'arrête là.

| Rang | Outil | Ce qu'il donne | Ce qu'il exige |
|------|-------|----------------|----------------|
| **20** | `Windows.UI.Notifications`, activée par COM | l'icône de Vigie en 256 pixels, texte long, boutons | rien — l'API est dans Windows. **Porte ouverte le 10/09** : fabrique, notificateur et document obtenus depuis PowerShell 7, en parcourant les tables de méthodes à la main. Jamais encore affichée depuis l'app cliente |
| **40** | la même API, par un `powershell.exe` | la même chose | un processus fils par notification ; **vu à l'écran le 10/09**, c'est ce rang qui a montré les icônes colorées |
| **60** | `AppNotificationManager` du Windows App SDK | la même chose, avec l'API que Microsoft recommande | le runtime du SDK, à vérifier **à l'installation** et à faire installer si besoin — jamais à découvrir au moment d'afficher |
| **90** | `ShowBalloonTip` | deux lignes et un glyphe système | rien, et c'est sa raison d'être |

**Le dernier rang est toujours disponible.** C'est la règle qui rend le reste sans risque : on peut ajouter un outil,
en retirer un, se tromper sur un, sans jamais perdre une notification.

## Ce que la porte ne fait pas

- **Elle ne décide pas s'il faut notifier.** Le répit de dix minutes par notification, le plancher d'une bulle par
  minute, le silence quand personne ne regarde l'écran : tout cela reste en amont, et ne se répète pas par outil.
- **Elle ne connaît pas les modules.** Un sujet est une chaîne de caractères ; elle n'a jamais à savoir d'où il vient.
- **Elle ne choisit pas d'outil une fois pour toutes au démarrage.** Une machine change — un runtime s'installe, une
  session se verrouille. Le rang retenu se garde pour ne pas payer l'essai à chaque passage, et se réexamine.

## Les icônes

Les `.ico` livrés contiennent six tailles jusqu'à 256, mais le rendu des notifications y pioche une petite image et
l'agrandit : le contour sort en escalier, constaté à l'écran le 10/09. Les outils modernes veulent un **PNG**. Celui de
256 est déjà dans chaque `.ico`, rangé tel quel : on le recopie octet pour octet, sans réencoder et sans toucher au
script qui les fabrique.

## Une dépendance, si elle est assumée

Dépendre de quelque chose de Windows n'est pas un problème en soi — c'en est un quand on le découvre en marchant.
Un outil qui exige un composant le déclare, l'installation le vérifie et l'installe, et l'absence du composant fait
simplement descendre d'un rang. Sur Windows 11, en n'étant pas exigeant sur la version, le runtime du SDK est
probablement déjà là : dix-neuf paquets présents sur la machine du 10/09, amenés par d'autres logiciels. Probablement
n'est pas partout, d'où le rang.
