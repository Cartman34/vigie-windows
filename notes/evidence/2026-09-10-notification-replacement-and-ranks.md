# 2026-09-10 — Les notifications s'empilaient, et les deux rangs affichent

Deux mesures du même après-midi, sur la porte de notification installée (v1.0.10). La
première ferme une question ouverte, la seconde ouvre un défaut.

## Les quatre rangs, vus à l'écran

Le rang 20 — l'API ouverte par COM dans le processus — n'avait **jamais rien affiché** :
il était éprouvé jusqu'à l'objet prêt, en s'arrêtant avant `Show()`. Quatre notifications
ont été envoyées par la porte installée, deux par le rang 20 et deux par le rang 40, à
texte identique à l'étiquette de test près.

| Rang | État | Affichée |
|---|---|---|
| `20-winrt-com` | `warn` | oui |
| `20-winrt-com` | `ok` | oui |
| `40-winrt-host` | `warn` | oui |
| `40-winrt-host` | `ok` | oui |

**Constat de l'utilisateur, captures à l'appui : les quatre sont identiques**, icône verte
et orange de Vigie comprises. Le rang 20 affiche donc réellement, et rend la même chose que
le rang 40 — ce qui est exactement ce qu'on attend de deux outils derrière une même porte.

## Le défaut que ces quatre notifications ont révélé

**Constat de l'utilisateur : « une notif suivante ne semble pas remplacer la précédente ».**
Les quatre se sont empilées dans le centre de notifications au lieu de se succéder. Sur un
même sujet, cela laissait côte à côte « à surveiller » et « rétabli » — deux lignes qui se
contredisent.

**Cause.** Windows ne remplace une notification par une autre que si les deux portent la
**même étiquette** (`Tag`). Les miennes n'en portaient aucune : rien dans le document XML,
rien sur l'objet.

**Ce qui a été vérifié avant d'écrire quoi que ce soit**, sans rien afficher :

| | |
|---|---|
| `IToastNotification2` demandée sur la notification construite | obtenue, HRESULT 0 |
| `put_Tag` appelée avec « gaming.hogs » | HRESULT 0 |

L'identifiant d'interface `9dfb9fd1-143a-490e-90bf-b9fba7132de7` venait de ma mémoire : il a
donc été **éprouvé en le demandant**. Un identifiant faux répond `E_NOINTERFACE` au lieu de
faire semblant, ce qui rend cette vérification concluante dans les deux sens.

**Ce qui a été retenu comme étiquette** : la référence du champ, `gaming.hogs`, portée
depuis l'app cliente jusqu'aux outils. Un rétablissement remplace ainsi sa propre alerte.
Plusieurs bascules simultanées n'ont pas de champ unique et partagent `vigie.modules`.

## Ce qui n'a PAS été vérifié

- **Le remplacement lui-même n'a pas été vu à l'écran.** L'étiquette est posée et les
  interfaces répondent, mais personne n'a encore regardé une alerte se faire remplacer par
  son rétablissement. C'est le seul essai qui compte vraiment, et il reste à faire.
- **Le cas inverse non plus** : deux sujets différents doivent rester côte à côte. Une
  étiquette trop large ferait disparaître des notifications qu'on veut garder, et rien ne
  l'a encore montré.
- **Aucune de ces quatre notifications n'est venue de la boucle de l'app cliente.** Elles
  ont été envoyées par un script appelant les outils installés. S13 reste donc ouvert.
- La limite de 64 caractères de l'étiquette vient de la documentation de Windows, pas d'une
  mesure : on coupe à 64 sans avoir constaté ce qui se passe au-delà.
