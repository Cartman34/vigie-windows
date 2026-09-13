# Quatre opérations longues hors du protocole commun — 12/09/2026

## Ce qui a été observé

Le 12/09, l'utilisateur choisit quelques mises à jour Windows dans le dialogue de la carte Windows Update et lance
l'installation. La page annonce aussitôt une réussite, ce qui est impossible pour une installation. La carte reste
ensuite, capture à l'appui, sur ces deux lignes :

| Ligne | Valeur affichée |
|---|---|
| À installer | 48 |
| Installation | Démarrage… |

Le nombre à installer n'a pas bougé : rien ne s'est installé. La ligne « Démarrage… » ne change plus.

## Ce qui a été lu dans le code

**La réussite immédiate.** `wu-install.action.ps1` lance son worker par `Start-DetachedAction` et répond
`ok = true, async = true` dès que le processus est créé. La réponse de `POST /actions` porte la liste des opérations en
cours, construite par `Get-RunningOperations` à partir des seules marques d'occupation. L'installation n'en pose
aucune. La page, dans `syncOperations`, voit donc l'opération absente de la liste, la tient pour finie, ne trouve aucun
résultat et affiche « : terminée. ».

**L'état sans issue.** L'action écrit `installing = true, phase = 'demarrage'` dans `var/cache/wu-install.json` avant
de lancer le worker. Seul le worker efface cet état. Il ne porte ni numéro de processus ni expiration, et la sonde
`pending.probe.ps1` l'affiche tel quel.

**La mort sans trace.** `Start-DetachedAction` ne redirige ni la sortie ni les erreurs, et l'action jette le numéro de
processus rendu. Le worker a deux sorties silencieuses avant son bloc `try`, sans racine ou sans identifiants.

## L'inventaire des lancements longs

| Opération | Lancement | Marque d'occupation | Résultat commun | Garde de vie |
|---|---|---|---|---|
| `vigie-update` | `Start-WatchedAction` | oui | oui | numéro de processus |
| `pwsh-install-machine` | `Start-WatchedAction` | oui | oui | numéro de processus |
| `wu-install` | `Start-DetachedAction` | non | non | aucune |
| `wu-scan` | `Start-DetachedAction` | non | non | aucune |
| `disk-analyze` | `Start-DetachedAction` | non | non | 60 minutes, dans l'action |
| `pkg-check-updates`, `pkg-upgrade` | `Start-PkgJob` puis `Start-DetachedAction` | non | non | 45 minutes, dans la sonde |

Conséquences communes aux quatre dernières lignes :

- le verrou de ressources, `Test-ActionResourcesFree`, ne lit que les marques : il ne protège aucune d'elles ;
- la page peut annoncer « terminée » dès la réponse de l'action ;
- chaque opération a son fichier d'état et sa règle d'abandon.

## Les failles du protocole commun lui-même

- `Get-ModuleBusyMark` efface **en silence** la marque d'un processus mort. Sans résultat écrit, la page affiche
  « terminée ».
- `watched-action.worker.ps1` sort sans marque ni résultat quand ses arguments sont invalides. Un échec au chargement de
  `lib/common.ps1` ne laisse rien non plus.
- La marque est posée par le veilleur une fois démarré, alors que l'action a peut-être déjà répondu.

## Pourquoi l'écart a duré

- **D82** (26/08) exige qu'aucune tâche de fond n'échoue en silence. Elle a été appliquée aux deux actions du jour, et
  **le plan cible n'a pas été mis à jour** : `CORE-OPERATIONS` ne dit ni « toute opération », ni « aucune fin
  silencieuse ».
- `implemented/status.md` marque `CORE-OPERATIONS`, `WU-PENDING`, `SYS-DISK` et `TOOLS-PACKAGES` « Fait », sans écart.
- `briefing.md`, `architecture.md` et `probes-and-actions.md` enseignent `Start-DetachedAction` comme modèle d'action
  longue, et citent `wu-install` en exemple.
- Aucun inventaire des opérations n'existait : chaque recherche partait du code, à tâtons.
- Aucun vérificateur ne contrôle la manière dont une opération est lancée.

Trouvé en passant : le code du verrou de ressources cite **D93** comme sa décision. D93 porte sur la langue de la
documentation. Aucune décision ne consigne le verrou par ressource.

## Ce qui n'a PAS été vérifié

- **Pourquoi le worker du 12/09 n'a pas avancé.** Son état et son journal sont dans le profil du compte de service,
  sous `systemprofile/AppData/Local/Sowapps/Vigie/var/`, illisibles sans élévation. Ils n'ont pas été lus.
- **La course sur les opérations conformes.** Que la marque du veilleur arrive après la réponse est déduit du code,
  jamais observé.
- **La durée réelle des opérations courtes.** L'inventaire dit si une action répond avec son résultat ou continue après
  sa réponse. Il ne dit rien de sa durée, qui n'a pas été mesurée.
