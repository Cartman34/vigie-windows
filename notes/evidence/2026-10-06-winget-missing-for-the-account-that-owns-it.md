# winget absent pour le compte qui le possède — enquête en cours

Suite de [winget était invisible pour Vigie](2026-10-06-winget-invisible-to-the-service-account.md), sujet **S02**,
règle **D128**. **Conclu le 06/10 à 09:03.** La cause est trouvée, et le correctif constaté sur la machine.

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

## La cause : une sonde ré-importe la bibliothèque, et remet la porte à zéro

**Chaque sonde commence par `. (Join-Path $backend 'lib/common.ps1')`.** Cette ligne réexécute la bibliothèque dans
le contexte de la sonde : elle y redéfinit `Get-StateAccount` **et** y réinitialise sa variable à `$null`.

La porte était une variable de portée `script`. `Get-State` l'écrivait dans *son* contexte ; la sonde lisait *le
sien*, qui venait d'être remis à zéro une ligne plus tôt. Chaque maillon fonctionnait seul, et c'est pour ça que
chaque test isolé réussissait :

| Test | Résultat | Pourquoi ça ne prouvait rien |
|---|---|---|
| `Get-StateAccount` après `Get-State -Account 'fhaza'` | rend `fhaza` | testé **hors** de la sonde, dans le contexte où la variable était écrite |
| `Get-PkgInventory -Account 'fhaza'` | 3 lignes | testé **hors** de la sonde, sans ré-import |

**Correctif.** Le compte voyagé dans la portée **globale**, posé juste avant chaque sonde et reprise juste après,
dans la fenêtre que le verrou de recalcul protège déjà. Ce n'est pas un raccourci : une variable de portée `script`
ne peut pas, par construction, franchir un ré-import.

## Ce que cette enquête a coûté, et ce qui le rend moins probable

Une demi-heure sans rien dire, à déduire au lieu de mesurer, sur une chaîne dont chaque maillon répondait juste. Deux
choses en sortent, toutes deux permanentes :

- **`diag-account-logs` ramène l'état** (`cache/`, `run/`), pas seulement les journaux. C'est l'état qui dit ce qu'un
  calcul a **lu** ; sans lui le fichier qui portait la réponse était à une copie de distance et illisible.
- **La carte dit pour quel compte elle a été calculée**, et combien de gestionnaires ont été lus dans sa session.

## Constat final, 06/10 à 09:03

Entrée `packages.probe.ps1@fhaza`, recalculée à 07:03:36 UTC — trois cartes, dont `pkg-winget` :

| | |
|---|---|
| portée | **`user`** — donc la carte porte « votre compte » à l'écran |
| valeur | 1.29.380 |
| chemin | `C:\Users\fhaza\AppData\Local\Microsoft\WindowsApps\winget.exe` |
| provenance | « Lu dans la session de fhaza : ce gestionnaire est installé dans ce profil, l'app serveur ne le voit pas. » |
| calcul | « Carte calculée pour le compte fhaza, 3 gestionnaire(s) lu(s) dans sa session. » |

Le chemin est celui du compte qui regarde, plus celui d'un autre.

## Et une troisième porte, qui manquait

**`probe-refresh`** : marquer une sonde à recalculer. Sans elle, une sonde corrigée restait invisible jusqu'à
**vingt-quatre heures** — l'intervalle de la carte des paquets — car l'installation n'invalide pas les rendus. Trois
déploiements de suite ont été lus contre un cache calculé avant le premier : chaque lecture donnait l'impression que
le correctif ne marchait pas, alors qu'il n'avait jamais tourné.

C'est la troisième chose que cette enquête laisse derrière elle, avec l'état dans le diagnostic et la carte qui dit
pour quel compte elle a été calculée. Toutes les trois répondent à la même faute : **j'ai déduit au lieu de mesurer,
parce que mesurer n'était pas outillé.**
