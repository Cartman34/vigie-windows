# La carte Jeux — ce qu'elle doit faire

Arbitrages : **D49** (ce qu'une carte doit dire), **D62** (aucune charge fabriquée sans autorisation), **D64** (de
vrais noms de processus), **D66** (une alerte porte son bouton), **D68** (une notification est un événement nommé),
**D75** (la VRAM se lit en `Local Usage`), **D113** (un réglage par utilisateur ne se lit jamais dans `HKCU`).
Besoin : `features.md`, entrée `GAMING`. État réel : `../implemented/status.md`.

## À qui elle sert, et quand

À **celui qui joue**, pendant qu'il joue — pas à l'administrateur après coup. Elle répond à trois questions, dans cet
ordre d'importance :

1. **Pourquoi ça rame ?** Qui prend le processeur, le GPU, la mémoire vidéo, le disque et le réseau **en ce moment**.
2. **Qu'est-ce qui va me gêner ?** Ce qui pompe pendant la partie, la mémoire vidéo qui sature, la carte qui chauffe et
   se bride, la batterie qui se vide.
3. **Est-ce que ça a changé ?** Ce qui mérite une bulle Windows pendant la partie, sans qu'on regarde la carte.

## Le vrai besoin : un MODE « en jeu »

Détecter la partie n'est pas un champ de plus sur une carte : c'est **faire basculer la machine dans un état**, dont
découlent des comportements de surveillance qui n'ont de sens que là. Hors partie, ces mêmes surveillances seraient du
bruit ; en partie, leur absence est une panne.

Ce que le mode « en jeu » déclenche :

| | |
|---|---|
| **La décharge de la batterie** | surveillée par paliers, alerte dès que la charge a fondu — sans partie, une décharge est normale et ne dit rien |
| **Les applications gourmandes** | seuils bas et alerte : une sauvegarde qui démarre pendant une partie se voit, alors qu'elle est banale le reste du temps |
| **La mémoire vidéo et la température** | ce sont les deux causes de saccades ; ailleurs, un GPU chaud qui ne rend rien n'intéresse personne |
| **La carte qui bride ses fréquences** | la vraie cause des chutes d'images par seconde, à dire pendant, pas après |

Et la question symétrique, à trancher : **ce que Vigie doit s'interdire pendant une partie** — lancer une analyse
d'espace disque, installer des mises à jour, sortir une bulle non critique. Une application qui surveille le confort de
jeu ne peut pas être ce qui le gâche.

Le mode a donc trois propriétés : il **commence** à la reconnaissance du jeu, il **dure** tant que ses processus
vivent, et il **appartient à un compte** — c'est ce compte-là qu'on prévient.

## Ce qu'elle doit dire

| | |
|---|---|
| **La carte graphique** | modèle et pilote, et **laquelle rend** — un jeu poussé sur l'intégrée au lieu de la dédiée est une cause de lenteur invisible |
| **La mémoire vidéo** | occupée / totale, en `Local Usage` (**D75**) ; le total réel se lit dans le registre du pilote, `Win32_VideoController.AdapterRAM` ment au-delà de 4 Go |
| **La température** | et surtout le **bridage** : c'est lui qui fait chuter les images par seconde, pas le degré affiché |
| **Le jeu détecté** | son nom lisible, et **pourquoi** il a été reconnu — un « jeu détecté » sans justification n'est pas vérifiable |
| **Ses ressources** | ce que la partie prend à elle seule |
| **Les applications gourmandes** | pendant la partie seulement, avec les services Windows **annotés** comme légitimes plutôt que masqués |
| **L'alimentation** | secteur ou batterie, et la **baisse depuis le début de la partie** |
| **La répartition** | un tableau unique, toutes dimensions par application, plus une ligne « autres » pour que le total reste additionnable |

## Ce qu'elle ne doit pas faire

- **Ne jamais juger sur le nom d'un exécutable.** Aucune liste noire d'applications à maintenir : on juge sur des faits
  vérifiables (**D64**). Consommer le GPU ne fait pas un jeu — une application Chromium affiche son interface avec le
  GPU et s'est retrouvée annoncée comme « jeu détecté » (signalé le 25/08).
- **Ne jamais faire disparaître le jeu parce qu'il ne rend plus.** Un menu, une pause, un chargement font retomber le
  GPU sous le seuil ; la carte doit dire « en pause », pas « aucun » (signalé pendant une partie d'Autonauts).
- **Ne jamais dire « aucun » sans dire pourquoi.** Trois états distincts, et la carte doit les distinguer : un jeu
  tourne, aucun jeu ne tourne, **la mesure n'a pas abouti**. Le troisième est aujourd'hui affiché comme le deuxième.
- **Ne jamais fabriquer de charge** pour se tester (**D62**) : les branches rares se valident par simulation
  (`VIGIE_FAKE_GAME`, `VIGIE_FAKE_BATTERY`).

## Détecter la partie — la cible

La détection actuelle repose sur une mesure instantanée de l'utilisation GPU, qui sert à la fois de **filtre d'entrée**
et de preuve d'activité. C'est le défaut de fond : la lecture des compteurs coûte deux secondes et demie, revient
parfois vide, et la carte annonce alors « aucun jeu » — constaté le 02/09, Assassin's Creed Odyssey reconnu à un
relevé, ignoré au suivant.

Ce que la détection doit devenir :

1. **Elle part du démarrage du processus**, pas d'une mesure périodique. Le service est prévenu quand un processus
   naît et quand il meurt, avec son PID, son parent, sa **session**, le **SID de l'utilisateur** et le chemin de son
   exécutable.
2. **Elle reconnaît le jeu par son chemin**, rapproché d'un **inventaire réel des jeux installés** — manifestes Steam,
   Ubisoft Connect, Epic, GOG, EA, Battle.net, Xbox. Le nom du fichier n'est jamais une preuve.
3. **Elle suit l'arbre des processus** : un jeu se lance souvent par un lanceur intermédiaire — `upc.exe` pour
   Odyssey, `steam.exe` pour Steam — et le processus qui rend n'est pas celui qu'on a lancé.
4. **La partie a une durée** : elle commence à la reconnaissance et ne finit qu'à la disparition de ses processus.
   Aucune mesure instantanée ne doit pouvoir l'interrompre.
5. **Le GPU redevient ce qu'il est** : un indicateur d'activité affiché — le jeu rend, ou il est en pause — jamais un
   critère de reconnaissance.

**Deux contraintes qui nous sont propres**, et qu'aucune documentation extérieure ne portera :

- L'app serveur tourne **sous un compte de service, en session 0**. Les inventaires des boutiques vivent par
  utilisateur : ils se lisent ruche par ruche (`HKEY_USERS\<SID>`) et profil par profil, jamais dans le `HKCU` du
  service (**D113**).
- La session et le SID portés par l'événement disent **qui joue**. La carte doit alors devenir personnelle
  (`PerAccount`) : chacun voit sa partie, et l'alerte de décharge part chez le joueur.

## Ce qui doit alerter, et à qui

Quatre événements nommés (**D68**), tous non critiques, visibles de tous : température GPU élevée, mémoire vidéo
saturée, applications gourmandes pendant une partie, partie sur batterie. Chacun naît de la bascule d'un champ de la
carte, jamais d'un relevé interne. Une alerte qui ne se résout pas ne s'affiche pas (**D66**) : la carte mène aux
réglages de jeu de Windows et au Gestionnaire des tâches, en permanence.

## Ce qui se règle

Cinq seuils, dans les paramètres du module : détection du jeu (% GPU), alerte CPU et alerte GPU des autres
applications, saturation de la mémoire vidéo, température, et décharge en jeu (points de batterie perdus).
