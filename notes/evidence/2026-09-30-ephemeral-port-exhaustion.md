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

## 6. Qui tient les ports — relevé du 30/09 à 10 h 50

| Processus | Ports éphémères TCP | Détail |
|---|---|---|
| **`dllhost.exe` PID 14656** | **250** | **244 « Bound » sur 0.0.0.0**, 5 établis, 1 écoute — plus **19 en UDP** |
| (sans propriétaire) | 134 | connexions en fermeture, TIME_WAIT |
| `seaf-daemon` | 44 | 22 établis, 16 liés, 5 en cours de connexion |
| `chrome` | 26 | 13 établis, 13 liés |
| `codex`, `ChatGPT`, `claude` | 20, 19, 16 | |

Total des ports éphémères TCP de la machine : **588**. Ce seul `dllhost` en tient **43 %**.

### Ce que ce `dllhost` héberge

`C:\WINDOWS\system32\DllHost.exe /Processid:{17696EAC-9568-4CF5-BB8C-82515AAD6C09}`, sous le compte `fhaza`. Cet
AppID est celui de **`WslDeviceHost_Net`**, `C:\Program Files\WSL\wsldevicehost.dll` — **l'hôte réseau de WSL**.

### Et il ne les rend jamais

Le processus a démarré le 29/09 à 21 h 32. Les 244 ports liés ont des dates de création qui **couvrent ses treize
heures de vie**, du 29/09 21 h 54 au 30/09 10 h 21 : le plus vieux est encore lié. Ce n'est pas une occupation, c'est
une **accumulation**.

Elle se fait **par paquets de exactement 8**, parfois à chaque minute :

| Heure | Ports liés |
|---|---|
| 29/09 21 h | 24 |
| 29/09 22 h | 9 |
| 30/09 06 h | 21 |
| 30/09 07 h | 17 |
| 30/09 08 h | 9 |
| **30/09 09 h** | **152** |
| 30/09 10 h | 12 |

Et 9–10 h est précisément l'heure de pointe des 71 événements des soixante derniers jours (20 d'entre eux).

### Ce n'est pas Vigie qui la déclenche

Mesuré à trois reprises, compteur avant et après : `wsl --list --running` → **0 port**, deux fois de suite ; la sonde
`probes/wsl/wsl.probe.ps1` en entier → **0 port** ; quatre connexions depuis Windows vers un service à l'écoute dans
la distribution → **0 port**. WSL est en mode NAT par défaut (`.wslconfig` ne déclare pas `networkingMode`), et la
distribution n'a que cinq écoutes.

Ce qui provoque les paquets de huit n'est donc **pas identifié** : il faudra prendre une rafale sur le fait.

## 7. Et la jauge de Vigie ne voyait pas ces ports-là

Mesuré le 30/09, au même instant : `Get-EphemeralPortUsage` comptait **128** ports pendant que la machine en
tenait **381 distincts**, dont **335 « Bound »**. La lecture rapide passe par `GetExtendedTcpTable`, qui liste les
**connexions** ; une prise de port sans connexion — `bind()` appelé, ni écoute ni connexion — n'y figure pas.

C'est exactement la forme de la fuite : les 244 ports de l'hôte réseau de WSL étaient **invisibles à la jauge**.
La carte annonçait 1 % en ignorant le tiers de ce que la machine tenait vraiment.

`Get-NetTCPConnection` les voit, et coûte **1,5 s** — cinquante fois la lecture rapide. D'où le partage retenu :
la jauge bon marché à chaque passage, la lecture complète **seulement quand on a décidé d'écrire**.

## Ce qui est en place depuis le 30/09

`Invoke-PortWatch`, dans la boucle de veille :

- **lit** à chaque passage — 15 ms, la plage étant gardée une heure (`Get-EphemeralPortRanges`, partagé avec la carte) ;
- **n'écrit rien** tant que l'occupation reste sous `PortWatchPercent` (50 % par défaut) et que Windows ne s'est pas plaint ;
- **écrit** au seuil, ou pendant les `PortWatchAfterMinutes` (15) qui suivent un 4231/4266, un point dans
  `var/history/net.ports/` : l'occupation, les cinq plus gros porteurs de la jauge, et **la lecture complète** avec
  les états — c'est elle qui nomme `dllhost` et ses 249 ports liés ;
- le journal d'événements est relu **au plus toutes les cinq minutes**, la réponse étant gardée : il coûte plus cher
  que ce qu'il garde.

Coût : **15 ms** par passage ordinaire, **2,1 s** pour un passage qui écrit — au plus une trentaine par jour, et
seulement les jours où il se passe quelque chose.

## Ce qui reste à trancher

- **Historiser l'occupation des ports** comme les autres mesures, pour que la carte puisse dire ce qu'elle valait
  quand Windows s'est plaint, au lieu de ce qu'elle vaut quand on la lit.
- **Redire la ligne** : nommer ce que Windows a gardé, et ne proposer le geste que si l'occupation est haute
  **au moment où l'on regarde**.
- **Densifier la mesure après un tel événement**, le temps de prendre la pointe suivante sur le fait.
