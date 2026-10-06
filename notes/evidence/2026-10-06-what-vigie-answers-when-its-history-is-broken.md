# Ce que Vigie répond quand son historique est cassé

Sujet **S15** : `implemented/components.md` marquait l'état cassé de `var/history` **« non vérifié »**. Il l'est
maintenant. L'essai a été fait sur **une copie de travail** — le fichier du jour d'une mesure, dans mon propre `var`,
qui était vide : aucune donnée réelle n'a été touchée, et le fichier d'essai a été retiré.

## Les trois états, et la réponse de Vigie

| Fichier du jour | Points rendus | Message |
|---|---|---|
| une ligne valide | **1** | — |
| une ligne valide **+ une ligne de bruit** | **1** | — |
| **que du bruit** | **0** | **aucun** |

## Ce que ça dit

**Rien ne casse.** Une ligne illisible est ignorée, les lisibles sont servies, aucune exception ne remonte. C'est le
bon comportement : un octet abîmé ne doit pas faire perdre un historique entier.

**Mais rien ne le dit non plus.** Un fichier entièrement corrompu rend **zéro point, sans un mot** — exactement ce
que rend une mesure qui n'a jamais été relevée. Les deux situations sont indiscernables : « je n'ai rien gardé » et
« ce que j'ai gardé est illisible » s'affichent pareil.

C'est contraire à la cible de `components.md`, qui veut que **toute erreur soit traitée ET remontée**. Ici elle est
traitée, pas remontée.

## Ce qu'il faudrait

Compter les lignes écartées, et le dire quand il y en a : « 142 relevés, 3 lignes illisibles écartées », ou
« fichier présent mais illisible » plutôt qu'un silence. Le coût est d'un compteur ; ce qu'on y gagne, c'est de ne
plus confondre un trou avec une absence.

## Ce qui reste hors de portée

- **La purge `service-data-reset part = history`** : jamais exécutée, et elle **supprime**. C'est un geste du
  propriétaire, pas le mien.
- **Les bascules VBS et HVCI** : je ne touche pas à un réglage de sécurité. Leur état cassé reste non vérifié.
