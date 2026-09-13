# Une mise à jour Windows « Inconnu », et une autre disparue — installation du 12/09/2026

## Ce qui a été observé

Installation demandée depuis la carte Windows Update le 12/09 à 18 h 26. Journal `wuinstall_20260912.log` du compte de
service, copié le 13/09 par l'action `diag-account-logs` :

| Heure | Ligne |
|---|---|
| 18:26:21 | demande : 4 mise(s) à jour |
| 18:28:52 | téléchargement : code 2 |
| 18:31:42 | Visual C++ 2008 SP1 (KB2538243) -> Installée |
| 18:31:42 | Outil de suppression de logiciels malveillants v5.145 (KB890830) -> Annulée (0x8024000B) |
| 18:31:42 | PowerShell v7.6.6 (x64) -> Inconnu |
| 18:31:42 | installation : code 3 redémarrage=False |
| 18:31:52 | verrou reposé : True |

## Ce que Windows en dit

L'historique de Windows Update (`IUpdateSearcher.QueryHistory`), lu le 13/09 :

| Date | Mise à jour | ResultCode | HResult |
|---|---|---|---|
| 12/09 18:31 | PowerShell v7.6.6 (x64) | 4, échec | `0x80242008`, opération annulée |

PowerShell installé le 13/09 : **7.6.5**. L'app cliente de fhaza a démarré le 13/09 sous « PS 7.6.5 ».

## Ce que cela montre

- **L'hypothèse notée le 13/09 ne tient pas** : la mise à jour de PowerShell n'a pas interrompu le worker. Son journal
  continue dix secondes après, jusqu'au verrou reposé.
- **Le worker ne nomme pas tous les verdicts.** Il traduit les codes 2 à 5 ; un résultat illisible (`-1`), non commencé
  (`0`) ou en cours (`1`) devient « Inconnu », sans code. Windows, lui, connaissait le verdict : échec, `0x80242008`.
- **Une mise à jour demandée a disparu sans trace.** Quatre demandées, trois retenues : le worker ignore un identifiant
  que la recherche ne retrouve plus, et ne le dit nulle part.

## Ce qui n'a PAS été vérifié

- **Quel code** le worker a reçu pour PowerShell : `-1`, `0` ou `1`. Le journal ne l'écrivait pas.
- **Pourquoi** Windows a annulé la mise à jour de PowerShell. Une piste, non éprouvée : ses fichiers étaient en usage,
  le worker lui-même tournant sous `pwsh`.
- **Quelle** était la quatrième mise à jour : le journal ne portait que les titres retrouvés.
- Aucune installation n'a été relancée pour reproduire : l'agent n'installe pas de mise à jour Windows.
