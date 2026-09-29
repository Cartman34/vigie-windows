# Les deux sondes Windows Update lentes, mesurées — 29/09/2026

Mesures faites sur ce poste avec `scripts/check-probes.ps1 -Only <sonde>` et des appels directs.

## Carte « Verrou Windows Update »

| Ce qui est mesuré | Avant | Après |
|---|---|---|
| Sonde complète | **8 417 ms** | **1 077 ms** |
| `Get-UpdateLockState` | 6 631 ms | 94 ms |
| dont `Get-ScheduledTask -TaskPath` × 4 | 6 682 ms | — |
| dont l'interface du Planificateur (`Schedule.Service`) | — | 43 ms |

`Get-ScheduledTask -TaskPath` parcourt tout l'arbre des tâches à chaque appel. L'interface du Planificateur ouvre le
dossier demandé et le liste : **mêmes six tâches, mêmes états, 155 fois plus vite**.

**Le piège, mesuré aussi** : un dossier refusé (`UpdateOrchestrator`, c'est l'effet même du verrou ACL) faisait
retomber le code sur l'applet lente, pour s'entendre répondre la même absence — 3 400 ms par passage, soit tout le
gain. Un dossier illisible n'a rien à dire, et ce silence EST l'information ; seule l'absence du service justifie le
repli.

## Carte « Mises à jour en attente »

| Ce qui est mesuré | Durée |
|---|---|
| Sonde complète | 12 198 ms (15 536 ms avant le correctif du verrou) |
| `Get-PendingUpdateList` | 10 459 ms |
| dont la recherche hors ligne de Windows Update | **9 676 ms** |
| la même recherche, une seconde fois dans la même session | 9 843 ms |
| `Get-WindowsUpdateAilments` | 556 ms |

**Ces dix secondes ne sont pas les nôtres** : c'est la recherche hors ligne de Windows Update, et elle coûte le même
prix deux fois de suite dans le même processus. Rien à optimiser de notre côté sans perdre l'information.

**Ce qui a donc été fait** : la carte n'est plus jamais calculée pendant qu'on attend. Elle est déclarée à
l'ordonnanceur (D124/D125) avec un intervalle de **6 heures** et un `MaxSeconds` de 120 s ; la carte du verrou, revenue
à une seconde, passe toutes les **30 minutes**.

## Ce qui n'est PAS vérifié ici

- Le comportement sur une machine où le service du Planificateur refuse l'interface : le repli existe, il n'a pas été
  éprouvé.
- Le coût de la recherche hors ligne sur une machine ayant beaucoup de mises à jour en attente : ici elle en trouve
  zéro et coûte déjà dix secondes.
