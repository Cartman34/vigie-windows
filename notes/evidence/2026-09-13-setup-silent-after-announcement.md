# Une installation validée qui ne laisse aucune trace — 13/09/2026, 11 h 11

## Ce qui a été observé

| Heure | Ce qui s'est passé |
|---|---|
| 11:11:08 | l'agent lance `setup.cmd` du dépôt principal par `Start-Process`, sans élévation |
| 11:13 | l'utilisateur écrit « j'ai validé l'install » après la fenêtre d'annonce, puis qu'aucune fenêtre n'est restée ouverte |
| 11:45 | l'utilisateur relance `setup.cmd` lui-même ; l'installation réussit |

## Ce qui a été cherché

| Où | Trouvé pour 11:11 à 11:45 |
|---|---|
| journaux du dépôt principal, `apps/backend-pode/var/log/` | rien : le premier journal du jour commence à 11:45:28 |
| journaux du compte de service, copiés par `diag-account-logs` | rien : `install_20260913_080028`, puis `115712` et `134336` |
| dossier temporaire de fhaza, `C:\ProgramData\Sowapps` | aucun fichier de Vigie écrit dans l'intervalle |

`install.ps1` n'a donc jamais ouvert son journal : la passe élevée n'a pas commencé, ou s'est arrêtée avant.

## Ce que cela montre

Dans le `setup.cmd` de ce moment, la branche non élevée lance `Start-Process -Verb RunAs`, puis `exit /b` **sans lire
son résultat**. Une élévation refusée, ou impossible, ferme la console sans un mot et sans journal.

Le test d'un `Start-Process -Verb RunAs` qui échoue, dans un fichier de commandes reprenant les mêmes lignes : le code
rendu est 1, et la nouvelle branche `:elevko` est prise.

## Ce qui n'a PAS été vérifié

- **La cause de 11:11 reste non expliquée.** Rien ne dit si la demande d'élévation a été refusée, n'a pas été affichée,
  ou si la passe élevée est morte avant son journal.
- **Aucune reproduction** : relancer `setup.cmd` met une fenêtre et une demande d'élévation à l'écran de l'utilisateur.
- Le test a porté sur un chemin absent, pas sur un refus réel de la demande d'élévation.
