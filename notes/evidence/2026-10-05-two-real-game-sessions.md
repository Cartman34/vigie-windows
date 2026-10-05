# Deux vraies parties, du 04 et du 05/10/2026 — ce qui a marché et ce qui n'a pas marché

Analyse demandée par le propriétaire après deux sessions d'**Assassin's Creed Odyssey** sur son compte. Tout ce qui
suit est lu dans les relevés de Vigie et dans le journal de l'app cliente de `fhaza`, pas reconstitué.

| | Début | Fin | Écoulé | Mesuré | Passages |
|---|---|---|---|---|---|
| Partie 1 | 04/10 16:32:27 | 04/10 18:28:20 | 1 h 55 | **1 h 54** | — |
| Partie 2 | 05/10 13:13:09 | 05/10 15:19:35 | 2 h 06 | **1 h 41** | **138** |

## Ce qui marche, et qui ne marchait pas

**L'échantillonnage par le serveur tient (D124).** 138 passages sur la partie 2, soit un toutes les 44 secondes. À
comparer au 28/09, avant ce changement : **4 passages pour deux heures de jeu**. La mesure existe vraiment maintenant.

**Une notification a été vue à l'écran.** `[2026-10-05 15:02:53] notification : network.ports-low ok->warn`, puis
`notification montree par 20-winrt-com`. C'est la première preuve qu'une notification de Vigie atteint l'écran —
c'était écrit depuis septembre et jamais constaté.

**Le récapitulatif s'ouvre tout seul.** `[2026-10-05 06:45:21] openApp demande (sur recap)` puis
`openApp OK (fenetre dediee)`. Le mécanisme fonctionne.

**Et la machine n'était pas saturée.** Sur la partie 2 : processeur **12,5 %** en moyenne (pointe 18,4 %), carte
graphique **54,1 %** (pointe 78,5 %), 3,8 Go de mémoire pour le jeu. **Aucun bouchon** relevé, sur aucune des deux
parties. Si ça a ramé, ce n'est pas la saturation de la machine.

## Ce qui ne va pas

### 1. Le récapitulatif s'ouvre douze heures trop tard

La partie 1 s'est terminée le **04/10 à 18:28**. Le récapitulatif ne s'est ouvert que le lendemain **à 06:45**.

**Cause, trouvée dans le code et non supposée.** L'app cliente ouvre le récapitulatif quand la ligne « Dernière
partie » **change**. Or cette ligne dit « terminée à 18:28 » le jour même et « terminée le 04/10 à 18:28 » ensuite :
au premier calcul passé minuit, la ligne change sans que rien ne se soit passé. Les lignes de 06:43 le montrent —
l'adresse réseau change, la carte est recalculée, et deux minutes plus tard le récapitulatif s'ouvre.

Ce n'était donc pas « à la reprise » : c'était **au passage de minuit**, au premier recalcul.

**Correctif.** Un champ peut désormais porter une `identity` — l'identité du fait énoncé, jamais affichée — et
« Dernière partie » porte la fin de la partie. L'app cliente compare l'identité, plus le libellé. Tout champ dont
la valeur porte une date ou une durée relative doit porter une identité : son libellé dérive avec le temps.

### 2. L'app cliente a encore disparu, pendant la partie

Le journal de l'app cliente s'arrête net à **15:02:54**, en pleine partie. Le fichier suivant commence à **17:20:07**.
Entre les deux, plus rien : ni ligne d'arrêt, ni erreur, ni reprise.

La partie s'est terminée à 15:19, **sans app cliente** : donc pas de récapitulatif automatique, pas de notification de
fin, pas d'icône. C'est la deuxième fois — la première était le 28/09 au soir, et avait déjà coûté une soirée de
mesures.

Ce qui change depuis : la veille permanente ramène une app cliente absente (depuis le 29/09), et elle l'a ramenée.
Mais la disparition elle-même n'est toujours pas expliquée.

### 3. Vingt-cinq minutes manquent à la partie 2

2 h 06 écoulées, **1 h 41 comptées**. La partie 1, elle, ne perd que 108 secondes — le temps avant le premier
passage, ce qui est normal.

Le temps est accumulé d'un passage à l'autre, **plafonné à cinq minutes par écart** pour qu'un ordinateur mis en
veille ne compte pas comme du jeu. Une interruption de vingt-cinq minutes ne compterait donc que pour cinq. C'est
l'explication la plus probable, et elle n'est pas vérifiable après coup : rien ne garde les passages un par un.

### 4. Les ports réseau se remplissaient pendant la partie

La notification de 15:02 est `network.ports-low` : la réserve de ports temporaires de Windows s'approchait de sa
limite **pendant le jeu**. C'est le sujet de la fuite de WSL
([relevé du 30/09](2026-09-30-ephemeral-port-exhaustion.md)), et c'est la première fois qu'on la voit gêner pendant
une partie.

## Ce qu'il faut en tirer

- ~~Ouvrir le récapitulatif à la fin de la partie~~ — **fait** : il ne s'ouvrait pas à la reprise, il s'ouvrait au
  passage de minuit, parce qu'on comparait un libellé au lieu d'un fait.
- **Expliquer la disparition de l'app cliente** : deux fois en une semaine, toujours sans trace.
- **Garder les passages d'une partie**, au moins leur horodatage, pour que « vingt-cinq minutes manquent » soit une
  question à laquelle on puisse répondre.
