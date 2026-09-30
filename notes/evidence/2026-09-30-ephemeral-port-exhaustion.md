# « Ports réseau épuisés » : ce que dit vraiment l'événement — 30/09/2026

Étude demandée par le propriétaire. Tout ce qui suit est mesuré sur ce poste, le 30/09, sur le journal Système complet
et sur l'état réel des ports. Rien n'est déduit d'un souvenir.

L'événement vient de `Tcpip` **4231** (espace TCP) et **4266** (espace UDP), nommés « Ports réseau épuisés » par
`probes/system/events.probe.ps1`.

## 1. Ce n'est pas Vigie

| Mesure | Valeur |
|---|---|
| Premier événement du journal Système | 24/07/2026 18:09 |
| **Premier 4231/4266** | **25/07/2026 07:47** — le lendemain |
| Première version de Vigie (`CHANGELOG.md`) | 19/08/2026 |
| Total sur tout le journal | **75** (29 en TCP, 46 en UDP) |

Le phénomène est aussi vieux que le journal, et le précède d'un mois. Le journal ne remonte pas plus loin : on ne peut
donc pas dire depuis quand, seulement que ce n'est pas né avec Vigie.

## 2. Le nombre d'événements n'est PAS le nombre d'échecs

Windows étouffe les répétitions, et c'est mesurable :

| Mesure | TCP (4231) | UDP (4266) |
|---|---|---|
| Événements | 29 | 46 |
| **Écart minimum entre deux identiques** | **753 min (12 h 33)** | **405 min (6 h 45)** |

Deux événements du même type ne sont jamais proches, alors que huit sessions de démarrage en portent deux à quatre. Un
événement veut donc dire « au moins un échec depuis le dernier signalé » — pas « un échec ». La carte qui affiche
« Ports réseau épuisés (1 fois, la dernière hier 13:40) » énonce ce que Windows a **gardé**, pas ce qui s'est passé.

## 3. Le reste du temps, la réserve est vide

Relevé le 30/09 à 10 h 30, hors incident :

| | Occupés | Limite | Part |
|---|---|---|---|
| TCP | 127 | 16 384 | 1 % |
| UDP | 47 | 16 384 | 0 % |

Les plus gros porteurs tiennent 16 à 31 ports (`seaf-daemon`, TIME_WAIT, `chrome`, `dllhost`). **La cause classique
est écartée** : les plages réservées, celles que Hyper-V et WSL taillent d'ordinaire dans l'espace éphémère et qui
font échouer l'allocation alors que le compteur paraît bas, ne pèsent ici que **61 ports en TCP et 60 en UDP**.

L'épuisement est donc une **pointe**, courte, qui ne laisse aucune trace derrière elle.

## 4. Quand

Réparti sur la journée de travail, avec un sommet à 9–10 h (20 des 71 événements des soixante derniers jours), et
**sans lien avec le démarrage** : 2 événements sur 71 tombent dans les dix minutes qui suivent un démarrage de Windows,
sur 66 démarrages.

## 5. Ce que Vigie fait de ça aujourd'hui, et ce qui manque

La carte Réseau sait lire l'occupation **maintenant** (`Get-EphemeralPortUsage`), et la carte Journal Windows signale
l'événement **après coup**. Entre les deux, rien :

1. **Le geste proposé est inapplicable.** « Fermer ou redémarrer l'application qui en tient le plus » s'adresse à
   quelqu'un qui regarde pendant la pointe. Quand il lit la carte, la réserve est à 1 % et le tableau nomme des
   processus qui n'y sont pour rien.
2. **Rien n'historise l'occupation des ports.** Les autres mesures ont leur historique (**D53**) ; celle-ci non. La
   pointe n'est donc observable par personne, ni sur le moment ni après.
3. **Le décompte affiché induit en erreur**, par ce que montre le point 2 ci-dessus : « 1 fois » est un plancher, et
   la carte le présente comme un total.

## Ce qui reste à trancher

- **Historiser l'occupation des ports** comme les autres mesures, pour que la carte puisse dire ce qu'elle valait
  quand Windows s'est plaint, au lieu de ce qu'elle vaut quand on la lit.
- **Redire la ligne** : nommer ce que Windows a gardé, et ne proposer le geste que si l'occupation est haute
  **au moment où l'on regarde**.
- **Densifier la mesure après un tel événement**, le temps de prendre la pointe suivante sur le fait.
