# Une carte occupée ne disait pas par quoi, et ne se déplaçait plus

Constaté par le propriétaire pendant que j'éprouvais le protocole des opérations (**S14**) en lançant une analyse de
disque. Deux comportements que personne n'avait demandés, et un défaut de blocage qui débordait.

## Ce qu'il a vu

**Première capture** — la carte *Chocolatey* : en-tête « Conforme », « Version 2.7.4 », « Mises à jour : Non
vérifiées », et le bouton « Vérifier les mises à jour » **éteint**. Or l'opération en cours était une analyse de
disque, qui ne retient que le disque.

**Deuxième capture** — la carte *Stockage* : grisée, ses trois boutons éteints — « Paramètres de stockage »,
« Nettoyage de disque… », « Arrêter l'analyse » —, un champ « Analyse — dossiers parcourus : 0 », et **rien ne
nommait l'opération en cours** ni depuis quand elle tournait.

Et : *« Je ne peux pas la déplacer. »*

## Trois choses, trois causes

### 1. Le déplacement était bloqué par l'occupation

`.card.card-loading{opacity:.55;pointer-events:none}` — la carte entière était éteinte, donc sa poignée de
déplacement avec elle. Comportement inventé, jamais demandé.

> « Pour le déplacement de carte, aucune opération ne doit bloquer le déplacement, tu as inventé ce comportement non
> demandé et tu dois le corriger. »

### 2. Le mode de ré-agencement n'éteignait que la moitié

Seuls le bouton de rafraîchissement et le menu étaient coupés ; **les boutons d'action restaient cliquables**.

> « Pendant le mode de ré-agencement, aucune action ne doit être possible sur aucune carte, elles peuvent avoir une
> teinte spécifique mais par contre, le déplacement ne peut pas être bloqué. »

### 3. Le gel débordait sur ce que l'opération ne retient pas

La page décidait ce qu'elle bloque à partir des ressources lues **sur la carte** (`busyResources`) — que presque
aucune sonde ne déclare. Les ressources arrivaient donc vides, et le repli écrit le 27/08 — « on ne sait pas ce
qu'elle tient, on bloque tout » — s'appliquait à chaque fois.

La route `/operations`, elle, porte le libellé, l'action, **les ressources** et l'heure de départ. La page ne la
lisait pas pour ça.

## Ce qui est en place

| | |
|---|---|
| Carte occupée | seules ses **actions** s'éteignent. Déplacement, menu et rafraîchissement restent vivants. |
| Ré-agencement | **aucune action** : boutons, résolutions, aides, dépliants, menu, rafraîchissement. Une teinte propre au mode. Déplacement entier. |
| Note sous l'en-tête | le libellé de l'opération et depuis combien de temps — « Analyse de C:\ · depuis 4 min ». |
| Ressources | lues sur `/operations`, la marque du serveur, au lieu d'être devinées sur la carte. |

Arbitrage : **D130**.
