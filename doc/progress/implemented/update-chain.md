# CORE-UPDATE — la chaîne de mise à jour, telle qu'elle est

Arbitrages : **D112** (le service a son clone), **D110** (la référence de comparaison), **D99** (d'où vient le code).
Besoin : `../targeting/features.md`, entrée `CORE-UPDATE`.

## Qui fait quoi

| | |
|---|---|
| **App cliente** (compte de la personne) | pose le tag de version dans son dépôt et le pousse — action `tag-version`, `@execution: session` |
| **App serveur** (compte de service) | synchronise **son** clone, fabrique l'archive, déploie, relance les deux applications |

Le service ne lit ni n'écrit jamais dans le dépôt d'une personne, à une exception près : il **clone** depuis lui quand
c'est l'adresse déclarée — d'où la déclaration `safe.directory`, posée par l'installation et par le déploiement.

## Les réglages

| clé | rôle |
|---|---|
| `Environment` | `dev` ou `prod`. **Déclaré**, jamais déduit. Conditionne la pose du tag, rien d'autre. |
| `UpdateSource` | `auto` · `clone` · `release`. `auto` prend le clone si une source est connue, sinon la version publiée. |
| `UpdateRemote` | l'adresse d'où le clone se synchronise. Vide = le dépôt public. |
| `SourcePath` | *(machine.psd1)* d'où vient ce déploiement — un fait, noté par l'installation et le déploiement. |

## Le déroulé

1. **Tag** — si `Environment = dev` et qu'il y a des commits d'avance. Depuis l'interface, c'est l'app cliente du
   compte qui a cliqué ; depuis un terminal, celui qui tape la commande **est** le propriétaire, il le pose lui-même.
   Un échec n'arrête rien : une mise à jour ne rate pas pour un tag.
2. **Synchronisation** — `Sync-ServiceClone` : clone à la première fois, `fetch` ensuite. Répit de 5 minutes, forcé par
   « Actualiser ».
3. **Fabrication** — `vigie-fetch` produit l'archive depuis le clone, sur le tag visé ; depuis une source locale et
   sans référence imposée, il suit la branche.
4. **Déploiement** — `deploy-prod -Zip`, qui ne fabrique ni ne tague : il copie et préserve les réglages de la machine.
5. **Relance** — ordre `restart` aux app clientes des comptes qui en ont une ; l'app serveur se relance elle-même via
   sa tâche planifiée, après la fin des opérations en cours.

## Ce que la carte affiche

Elle compare l'installation partagée **à ce que le bouton irait chercher** : le clone quand la voie est `clone`, la
dernière version publiée sinon. Quand elle ne peut pas lire la source, elle affiche le message de git plutôt qu'un
verdict inventé.

## Écarts connus

- Le `fetch` depuis un dépôt local **exige** `safe.directory` : mesuré le 30/08, git refuse même la lecture d'un dépôt
  appartenant à un autre compte.
- La chaîne complète depuis le bouton de l'interface n'a pas encore été éprouvée de bout en bout.
