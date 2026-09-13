# « Jamais démarrée » sur une app cliente qui tourne — 13/09/2026

## Ce qui a été observé

Après les mises à jour de Vigie demandées au serveur à 11 h 58 et 13 h 45, la carte Déploiement affiche « Démarrage
automatique : Jamais démarrée — fhaza », en neutre. L'app cliente de fhaza tourne pourtant, icône visible.

| Lecture, 13/09 vers 22 h | Valeur |
|---|---|
| tâche `Vigie - fhaza`, état | `Running` |
| dernier lancement | 13/09/2026 13:45:00 |
| dernier résultat | `0x800710E0` : « L'opérateur ou l'administrateur a refusé la requête » |
| réglage des instances | `IgnoreNew` |
| processus `pwsh` de la session de fhaza | démarré à 13:44:34, toujours vivant |
| `tray.ps1` installé, date d'écriture | 13:43:40 |

## La chronologie, relue dans les journaux

Journaux du compte de service copiés par l'action `diag-account-logs` (`install_20260913_134336.log`,
`comptes_20260913.log`), journal de l'app cliente de fhaza (`tray_20260913.log`) :

| Heure | Ce qui s'est passé |
|---|---|
| 13:44:34 | « Démarrage automatique : code 0 » ; l'app cliente de fhaza écrit « demarrage (PS 7.6.5, STA) » |
| 13:44:43 | l'app cliente est en marche (« Application.Run ») |
| 13:44:44 et 13:44:55 | les tâches `Vigie - Famille` et `Vigie - fhaza` sont réenregistrées : la mise à jour tourne sous `VigieService`, fhaza est donc un « autre compte » |
| vers 13:45:00 | `Start-TrayTasks` démarre les tâches des comptes arrêtés, dont celle de fhaza, déjà en cours |
| 13:45:00 | « Mise à jour de Vigie : code 0 en 85 s » |

## Ce que cela montre

- Un démarrage demandé à une tâche `IgnoreNew` qui tourne déjà est refusé, et son refus devient le dernier résultat de
  la tâche, daté du refus.
- `Get-VigieTaskHistoryAilment` lit ce code comme un échec postérieur au code installé, et la sonde Déploiement le range
  parmi les tâches « à confirmer ». Elle affiche alors « Jamais démarrée », texte qui ne vaut que pour une tâche jamais
  lancée : un échec et une absence de lancement portaient le même libellé.
- `Start-TrayTasks` démarre sans regarder si la tâche tourne.

## Après le déploiement de la v1.1.5, 13/09 à 22 h 39

| Lecture | Valeur |
|---|---|
| carte Déploiement | « Démarrage automatique : Opérationnel » : **la lecture de l'historique est corrigée** |
| app cliente de fhaza | démarrée à 22:38:53, toujours vivante |
| tâche `Vigie - fhaza` réenregistrée | 22:39:15 (`comptes_20260913.log`) |
| dernier lancement, dernier résultat | 22:39:20, `0x800710E0` : **le redémarrage refusé a eu lieu quand même** |
| journal de la mise à jour | « App clientes relancées : Famille, fhaza » |

`Start-TrayTasks` ne sautait une tâche que si elle se lisait `Running`. Réenregistrée cinq secondes plus tôt, elle ne se
lisait plus ainsi, alors que son instance tournait. Depuis, c'est le processus vivant qui décide, quel que soit l'état.
**Ce second correctif n'est pas déployé** : il attend la prochaine mise à jour.

## Ce qui n'a PAS été vérifié

- **Le refus n'a pas été reproduit.** Redémarrer la tâche de fhaza aurait pu mettre une seconde app cliente à l'écran.
- **Aucun événement du Planificateur de tâches** ne confirme l'heure du refus : son journal `Operational` est désactivé
  sur cet ordinateur (`enabled: false`).
- La tâche de Famille n'a pas pu être relue : une session non élevée ne voit pas les tâches d'un autre compte.
