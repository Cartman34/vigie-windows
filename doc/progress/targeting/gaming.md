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

Le mode a donc deux propriétés : il **commence** à la reconnaissance du jeu, et il **dure** tant que ses processus
vivent. Il **se voit** : tant qu'il est actif, la carte prend un style dédié.

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

**Le déclencheur** : le **démarrage d'un processus**, pas une mesure périodique. L'app serveur en est prévenue par un
**résident** ([residents.md](residents.md)) ; l'événement porte le PID, le parent, la session, le SID de l'utilisateur
et le chemin de l'exécutable. Le résident ne juge pas : il **présente** le processus à l'identification.

**L'identification** : plusieurs **méthodes déclarées, indépendantes**. Chacune reçoit un processus et répond « c'est
un jeu, parce que… » ou se tait ; **une seule qui parle suffit**. Aucune n'est complète — c'est leur réunion qui l'est,
et en ajouter une demain doit coûter un fichier, rien d'autre.

| Méthode | Ce qu'elle attrape |
|---|---|
| **Marqueurs autour de l'exécutable** — moteur, SDK, boutique, middleware | le jeu indépendant, lancé sans plateforme |
| **Windows l'a enregistré comme jeu** (Game Bar) | ce que le système sait déjà, lu dans la ruche du bon utilisateur |
| **Dossier d'installation d'une plateforme** (Steam, Ubisoft, Epic, GOG, EA) | les grosses boutiques — une liste utile, **jamais suffisante** : elle ignore tout ce qui n'y est pas installé |
| **Le parent est un lanceur connu** | un processus lancé par une boutique de jeux |
| **Déjà reconnu** | tout ce qui a été confirmé une fois |

**Le coût, qui décide de l'ordre.** Le travail n'a lieu qu'au démarrage d'un processus, jamais en boucle. Les méthodes
s'exécutent de la moins chère à la plus chère et **on s'arrête à la première qui répond**. Les deux verdicts — jeu et
non-jeu — sont **mémorisés** : un exécutable qui démarre cent fois ne s'examine qu'une. Ce qui vit dans `C:\Windows`
est écarté d'emblée, sur son **emplacement** et jamais sur son nom.

**La mémoire se périme sur les critères.** Elle porte l'empreinte des méthodes et de leurs réglages : un critère qui
change, une méthode qu'on ajoute, et tout se réexamine une fois.

**L'arbre des processus** rattrape les lanceurs intermédiaires : `upc.exe` lance `ACOdyssey.exe`, et le processus qui
rend n'est pas celui qu'on a lancé.

**La partie dure** : elle commence à la reconnaissance et ne finit qu'à la disparition de ses processus. Aucune mesure
instantanée ne doit pouvoir l'interrompre. Le **GPU redevient un indicateur d'activité** affiché — le jeu rend, ou il
est en pause — jamais un critère de reconnaissance.

**Deux contraintes qui nous sont propres**, et qu'aucune documentation extérieure ne portera :

- L'app serveur tourne **sous un compte de service, en session 0**. Les inventaires des boutiques vivent par
  utilisateur : ils se lisent ruche par ruche (`HKEY_USERS\<SID>`) et profil par profil, jamais dans le `HKCU` du
  service (**D113**).
- Les événements portent la session et le SID de l'utilisateur : c'est ce qui permet de rattacher un processus à la
  session qui l'a lancé, depuis un service qui tourne en session 0. Ce que la carte en fait n'est pas défini.

## Ce qui doit alerter, et à qui

Quatre événements nommés (**D68**), tous non critiques, visibles de tous : température GPU élevée, mémoire vidéo
saturée, applications gourmandes pendant une partie, partie sur batterie. Chacun naît de la bascule d'un champ de la
carte, jamais d'un relevé interne. Une alerte qui ne se résout pas ne s'affiche pas (**D66**) : la carte mène aux
réglages de jeu de Windows et au Gestionnaire des tâches, en permanence.

## Ce qui se règle

Cinq seuils, dans les paramètres du module : détection du jeu (% GPU), alerte CPU et alerte GPU des autres
applications, saturation de la mémoire vidéo, température, et décharge en jeu (points de batterie perdus).
