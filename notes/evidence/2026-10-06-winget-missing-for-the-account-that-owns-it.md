# winget absent pour le compte qui le possède — enquête en cours

Suite de [winget était invisible pour Vigie](2026-10-06-winget-invisible-to-the-service-account.md), sujet **S02**,
règle **D128**. **Ce relevé n'est pas conclu** : il consigne ce qui est mesuré, pour que l'enquête ne reparte pas de
zéro.

## Le symptôme

Après le correctif du 06/10, la carte winget **n'apparaît plus du tout** pour le compte `fhaza`. Les cartes
`pkg-choco` et `pkg-pip` sont là, portée `machine` : correctes, elles viennent d'installations pour tout l'ordinateur.

C'est le repli retiré qui rend le trou visible : avant, il était masqué par le winget d'un autre compte.

## Ce qui est mesuré, et qui écarte les explications faciles

| Ce qu'on a vérifié | Résultat |
|---|---|
| L'ordonnanceur calcule-t-il la carte par compte ? | **Oui** : `tools/packages@fhaza` calculé en 7 386 ms, journal `state` du serveur |
| Mon app cliente a-t-elle été interrogée ? | **Oui**, deux fois : `ordre de bureau : pkg-inventory` à 07:17:43 et 08:18:23 |
| L'action rend-elle le bon résultat ? | **Oui** : `ok=True`, 3 gestionnaires, winget 1.29.380 |
| L'inventaire du serveur contient-il mon compte ? | **Oui** : `cache/pkg-inventory.json` porte `fhaza` **et** `Famille`, chacun avec winget |
| La lecture de ce fichier rend-elle mes lignes ? | **Oui** : testée sur le fichier réel, 3 lignes pour `fhaza` |
| `Get-State -Account` renseigne-t-il la porte `Get-StateAccount` ? | **Oui** : vérifié dans un processus neuf |
| Le cache porte-t-il bien une entrée par compte ? | **Oui** : `packages.probe.ps1@fhaza`, `@Famille`, `@VigieService` |
| Cette entrée contient-elle winget ? | **Non** : `pkg-choco, pkg-pip` seulement, écrite à 06:28:07 UTC |

L'inventaire de `fhaza` a été écrit à **06:18:26 UTC**, dix minutes **avant** le calcul de 06:28:07. La donnée était
donc là, lisible, et la sonde ne l'a pas utilisée. Chaque maillon marche isolément ; la chaîne, non.

## Ce qui a été mis en place pour répondre, au lieu de déduire

1. **`diag-account-logs` ramène l'état, pas seulement les journaux.** Elle copiait `log/` et résumait `cache/` sans
   son contenu. Un journal dit ce qui **s'est passé** ; l'état dit ce qui **est** — et c'est l'état qui dit ce qu'un
   calcul a **lu**. Une demi-heure a été perdue à deviner un fichier qui était à une copie de distance. `cache/` et
   `run/` sont désormais rapatriés, `secrets/` jamais, et un fichier de plus de 16 Mo est nommé au lieu d'être copié.
2. **La carte dit pour quel compte elle a été calculée**, et combien de gestionnaires ont été lus dans sa session.
   Une carte à laquelle on ne peut pas poser de question ne peut pas être crue.

## Ce qui reste à trancher

Pourquoi `$requester` ou `$inventory` est vide **dans la sonde**, alors que la porte et le fichier répondent tous
deux correctement hors de ce contexte. La ligne ajoutée sur la carte doit le dire au prochain calcul.
