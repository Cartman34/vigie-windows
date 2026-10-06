# Une action retirée de la source survit dans l'installation

Constaté en nettoyant la mesure temporaire de l'étape 2 de **S02**. Ce n'est pas un détail de ménage : une action
porte des droits et s'appelle par son nom.

## Le constat

`diag-winget-path.action.ps1`, action temporaire de diagnostic, a été **supprimée de la source** et poussée sur
`main`. Un déploiement a suivi, code 0.

| | |
|---|---|
| Source (`apps/backend-pode/actions/`) | `diag-account-logs.action.ps1` seulement |
| Installation (`C:\Program Files\Sowapps\Vigie\apps\backend-pode\actions\`) | `diag-account-logs.action.ps1` **et** `diag-winget-path.action.ps1`, écrite à 10:58 |
| L'action répond-elle encore ? | **Oui** : `status: done`, elle s'exécute |

## La cause, lue dans le code

`Copy-InstallFrom` supprime ce que la source n'a pas — mais seulement à **deux niveaux** :

```powershell
foreach ($scope in @($Destination, (Join-Path $Destination 'apps'))) {
```

Tout ce qui vit plus bas est seulement **écrasé**, jamais supprimé : `apps/backend-pode/actions/`, `probes/`,
`workers/`, `lib/`. Le correctif du 30/09 — qui avait réglé le cas d'un script d'app cliente resté en place — n'a
couvert que ces deux niveaux.

## Pourquoi ça compte

Une **action** est une surface d'appel avec des droits (`@droits: admin`). Retirer une action de la source est le
geste par lequel on la supprime : si elle survit dans l'installation, elle reste appelable, avec ses droits, par
quiconque passe la porte d'entrée. Même chose pour une **sonde** retirée, qui continuerait de produire une carte, et
pour un **worker** retiré, qui resterait lançable.

Ici l'action était en lecture seule, et elle est partie avec le relevé suivant. Le mécanisme, lui, reste à corriger.

## Ce qu'il faut faire

Étendre la suppression à **toute l'arborescence** de l'installation, hors `var/` (données) et hors les fichiers
propres au poste (`*.local.*`, `actions.policy.json`), déjà épargnés par la fonction. La règle devient : ce que la
source n'a pas, l'installation ne l'a pas — à quelque profondeur que ce soit.
