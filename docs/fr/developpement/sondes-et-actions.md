# Sondes et actions

[Développement](README.md) · [Sommaire](../README.md) · [English](../../en/development/probes-and-actions.md)

Le back est un **socle générique**. Il ne code aucune carte en dur : il découvre les sondes
sur le disque. Ajouter une carte, ou un bouton, c'est déposer un fichier. Le contrat ne
change pas, le front ne change pas.

---

## Sonde — lire un état

**Emplacement :** `apps/backend-pode/probes/<theme>/<nom>.probe.ps1`

**Contrat :** le script écrit sur la sortie standard un objet conforme au schéma `Module`
du contrat OpenAPI — ou un tableau, quand une sonde produit légitimement plusieurs cartes
(c'est ainsi qu'il y a une carte par gestionnaire de paquets).

**Règles :**

- **Rapide et sans effet de bord.** Une sonde lit ; elle ne modifie rien. Les appels lents
  (WSL, par exemple) doivent être bornés par un délai.
- **Ne jamais appeler les scripts lourds.** Une sonde lit directement le registre, les
  tâches, les ACL. Tout ce qui est long relève d'une action et d'un worker, la sonde se
  contentant de lire le fichier de résultat écrit par le worker.
- Donnez-lui un TTL dans la table de `lib/common.ps1` si les 30 s par défaut ne conviennent
  pas.

```powershell
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

New-ModuleObject -Id 'ma-carte' -Theme 'system' -Label 'Ma carte' -Status 'ok' -Fields @(
    New-Field -Key 'valeur' -Label 'Quelque chose' -Value 42 -Kind 'number' -Unit 'Go' -Status 'ok' `
        -Help "Ce que c'est, en langage clair." `
        -Guide "Ce qu'il faut faire quand ça ne va pas."
) -Actions @(
    New-Action -Id 'mon-action' -Label 'Faire la chose' -Kind 'confirm' -Severity 'fix' -Confirm
)
```

### `New-Field`

| Paramètre | Remarques |
|---|---|
| `Key`, `Label`, `Value` | obligatoires |
| `Kind` | `bool` · `number` · `text` · `date` |
| `Unit` | affichée après la valeur |
| `Status` | `ok` · `warn` · `error` · `neutral` |
| `Help` | ce que ce champ *est* — langage clair, pas de jargon |
| `Guide` | quoi faire quand ça ne va pas : ce que c'est, le risque à ne rien faire, les options |
| `FixAction` | l'id de l'action qui résout ce champ |
| `Table` | détail structuré : `@{ columns = @(...); rows = @(@(...), ...) }`. Des dizaines de lignes tassées dans une chaîne restent illisibles où qu'on les affiche ; un tableau se parcourt du regard |

### `New-Action`

| Paramètre | Remarques |
|---|---|
| `Id`, `Label` | obligatoires. Le libellé dit **ce que l'action fait** — jamais un « Résoudre » générique |
| `Kind` | choisit l'**icône**, c'est-à-dire *comment ça se passe* : `immediate` · `confirm` (oui/non) · `dialog` (fenêtre de choix dans l'application) · `manual` (passe la main à un logiciel externe) |
| `Severity` | choisit la **couleur**, c'est-à-dire *ce que ça vaut* : `neutral` (gris) · `info` (bleu, consultation ou ouverture) · `fix` (vert, corrige quelque chose) |
| `Confirm` | exige une confirmation avant exécution |
| `BusyLabel` | affiché pendant l'exécution. Il doit dire ce qui se passe — « Mise à jour… », pas « En cours… ». Les points de suspension sont réservés à une action en cours ; un libellé au repos n'en porte jamais |

`kind` et `severity` étaient autrefois confondus : la couleur suivait la forme, ce qui
n'apprenait rien au lecteur. Gardez-les distincts.

### `New-ModuleObject`

`Id`, `Theme`, `Label`, `Status` obligatoires ; `Fields`, `Actions` optionnels. `-Busy`
marque la carte comme travaillant, et `-BusyAction` nomme l'action réellement en cours —
sans lui, l'interface anime tous les boutons de la carte et on ne sait plus lequel
travaille.

---

## Action — faire quelque chose

**Emplacement :** `apps/backend-pode/actions/<id>.action.ps1`, avec `<id>` conforme à
`^[a-z0-9-]{1,40}$`. Déclarée par une sonde dans ses `actions[]`, invoquée par
`POST /actions {type, module, params}`.

**Renvoie** `@{ message; result }`. Clés utiles dans `result` :

| Clé | Effet |
|---|---|
| `ok` | succès ou échec, tel qu'il a été réellement constaté |
| `invalidate` | `@('lock.probe.ps1')` — force le recalcul de ces sondes maintenant |
| `async` | `$true` quand le travail se poursuit dans un worker |
| `module` | la carte que le front doit interroger tant que `async` |

```powershell
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
# ...
@{ message = 'Fait.'; result = @{ ok = $true; invalidate = @('ma.probe.ps1') } }
```

### Règles

1. **Ne jamais interpoler l'entrée client dans une commande.** Les `params` n'atteignent
   jamais un shell. Chaque action est un script fixe sur le disque ; le chemin résolu est
   confiné à `actions/`.
2. **Traiter la sortie ET le code retour** — via `Invoke-Native`, partagé.
3. **Vérifier le résultat, ne pas croire le code de retour.** Après un changement, relire le
   système et rapporter ce qu'on a réellement obtenu. `update-mode-off` est le modèle : il
   agit via `Set-UpdateLock`, journalise le code de retour de chaque `icacls` / `takeown`,
   puis **relit** l'état complet avec `Get-UpdateLockState` et distingue succès complet,
   succès partiel (MAJ auto coupées mais verrou ACL absent) et échec.
4. **Ne pas recopier une invocation.** Si deux actions ont besoin de la même opération, elle
   va dans un helper partagé de `lib/common.ps1` — `Set-UpdateLock` existe précisément
   parce que le verrou allait être invoqué depuis un troisième endroit.
5. **Une capacité du produit s'implémente dans le produit.** Le verrouillage de Windows
   Update et son audit ont d'abord été délégués à des scripts hors dépôt : sur une machine
   qui installe Vigie depuis GitHub, les boutons ne faisaient rien. Ils vivent désormais
   dans `lib/common.ps1` (`Set-UpdateLock`, `Invoke-UpdateAudit`, `Get-UpdateLockState`,
   `Get-UpdateTaskCatalog`). Un outillage externe peut rester *préféré* quand il existe,
   jamais *requis*.
6. **Vérifier l'élévation avant d'agir, pas après.** `icacls` et `takeown` échouent en
   silence sans droits administrateur : on refuserait de bonne foi un état faux. Les deux
   actions de verrou testent `Test-Elevated` d'abord et ne touchent à rien sinon.
7. **La faire relire dans [Sécurité](../securite.md)** si elle touche à la sécurité du
   système.

### Actions longues

Tout ce qui se compte en minutes part dans un worker :

```powershell
$null = Start-DetachedAction -Script (Join-Path $backend 'workers/mon.worker.ps1') `
                             -ArgsMap @{ foo = 'bar' } -Backend $backend
@{ message = 'Lancé en tâche de fond.'
   result  = @{ ok = $true; async = $true; module = 'ma-carte'
                invalidate = @('ma.probe.ps1') } }
```

Le worker écrit sa progression dans `var/cache/<nom>.json` via `Update-StateJson` (protégé
par mutex), et la sonde ne fait que lire ce fichier. Prévoyez une **péremption** : une
tâche peut mourir sans rien écrire, et sans limite d'âge son drapeau « en cours » ne
retombe jamais — les cartes de paquets abandonnent au bout de 45 minutes pour exactement
cette raison.

---

## Exemples existants à lire

| Fichier | Pourquoi |
|---|---|
| `probes/windows-update/lock.probe.ps1` | champs riches, actions conditionnelles, traitement honnête du cas « non élevé » |
| `probes/tools/packages.probe.ps1` | une sonde, plusieurs cartes, état « en cours », péremption des tâches |
| `actions/update-mode-off.action.ps1` | vérifier le résultat réel plutôt que le code de retour |
| `actions/wu-install.action.ps1` | sélection explicite, worker détaché, verrou levé puis reposé |
| `actions/net-speedtest.action.ps1` | fusionner un résultat dans un fichier de cache partagé |

## Ensuite

- [Architecture](architecture.md) — où tout cela s'inscrit
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml) — le contrat
- [Sécurité](../securite.md) — les règles qu'une action doit respecter
