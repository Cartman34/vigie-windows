# Identité et droits — qui parle à Vigie, et ce qu'elle lui montre

Arbitrages : **D109** (qui exécute n'est pas qui demande), **D65** (multi-utilisateurs).
Besoin : `../targeting/features.md`, entrées `CORE-SECURITY` et le socle multi-comptes.

## Les trois notions

| | |
|---|---|
| `Get-ProcessAccount` | qui **exécute** ce processus. Vrai pour l'app cliente — elle *est* la personne — et pour un script lancé à la main. |
| `Get-RequesterAccount` | qui **demande**, lu dans le cookie de session. `$null` si personne ne s'est identifié. |
| `Get-ActionRequester` | qui demande, **avec un repli** sur le compte du processus : sert à signer le journal d'audit, jamais à décider de ce qu'on montre. |

`check-probes` refuse `$env:USERNAME` en clair : le choix entre les trois doit être conscient.

## La chaîne d'identification

1. L'app cliente lit le **secret** de son compte, dans son profil, protégé par une ACL explicite.
2. Elle l'échange contre une **adresse d'ouverture** à usage unique (30 s) — `Get-OpenUrl`, le seul chemin pour en
   demander une, et seulement **pour soi** : le secret ne se lit que depuis la session de son compte.
3. Le panneau ouvert par cette adresse reçoit un **cookie de session** (`HttpOnly`, `SameSite=Strict`, durée un an),
   puis le serveur **redirige vers l'adresse principale** — l'adresse d'ouverture ne reste ni dans la barre d'adresse,
   ni dans un signet, et ce qu'on met en favori est la bonne adresse.

**Ce qui circule est jetable, ce qui reste ne l'est pas.** L'adresse ne vaut qu'une fois et 30 secondes ; la session
qu'elle ouvre **ne périme pas**. Elle expirait au bout de 24 heures : passé ce délai la fenêtre restait ouverte mais
n'appartenait plus à personne, sans que rien ne l'annonce. Une session se termine autrement — son fichier est
supprimé, ou le compte cesse d'être activé.

### Regarder Vigie dans un vrai navigateur

```powershell
pwsh -File scripts/dev/sign-in-url.ps1          # rend l'adresse, à coller
pwsh -File scripts/dev/sign-in-url.ps1 -Open    # ouvre directement
```

**Stage `dev` uniquement**, et depuis le **dépôt** : c'est un outil de développement, il ne part pas dans l'archive
livrée. En stage `prod`, il refuse — Vigie s'y ouvre par son icône, qui identifie déjà le compte. Ce refus dit une
intention ; ce qui protège réellement la session reste le secret du compte.

Une fois, et le navigateur reste identifié : outils de développement, console et réseau, avec « vous » à la bonne
ligne et des actions qui savent qui les demande.

Une page ouverte sans preuve d'ouverture — un signet, un rechargement — n'a donc pas de cookie : personne n'est
« vous », et c'est dit ainsi plutôt que d'attribuer la session au compte de service.

> **Le mot « ticket » est interne, et il n'a jamais été validé.** Il ne s'affiche nulle part dans l'application ; il ne
> vit que dans le code (`/session/ticket`, `New-OpenTicket`, `Use-OpenTicket`) et dans cette page. À renommer le jour
> où l'étape reçoit un nom du projet.

### Ouvrir l'URL à la main : ça marche, et personne n'est « vous »

L'installation **ne pose plus de raccourci sur le bureau**, et retire celui qu'elle avait posé. Il pointait droit sur
`http://127.0.0.1:47600/`, donc sur un panneau sans preuve d'ouverture : pas de cookie, personne n'est « vous »
(constaté le 31/08), et surtout **aucune action ne sait qui la demande**. Une porte dégradée qu'on installait
soi-même sur le bureau de chacun.

Vigie s'ouvre par son **icône dans la barre système**, qui emprunte la chaîne complète.

**Ouvrir l'URL directement reste possible et doit le rester** : c'est ainsi qu'on regarde et qu'on débogue dans un
vrai navigateur. La page se sert, le jeton d'API l'authentifie, tout fonctionne — mais le serveur ne sait pas qui la
regarde, donc « vous » n'apparaît sur personne. C'est un geste de développeur, assumé comme tel.

**Question ouverte, non tranchée :** faut-il que le serveur reconnaisse une connexion **locale** en remontant du port
source au processus, puis au compte qui l'exécute ? Ce serait une seconde voie d'identification à côté de la preuve
d'ouverture, et donc un arbitrage à consigner.

## Les droits : on juge LE DEMANDEUR

**D65 : par défaut, Vigie ne permet rien de plus que ce que Windows permet déjà à ce compte.** Une action déclare
`# @droits: admin` ou `# @droits: tous` en tête de son fichier ; `config/actions.policy.json` (couche machine) peut
ouvrir ou fermer une action nommément — c'est là que l'utilisateur change d'avis sur une action précise. Sans
déclaration : `admin`. Le silence n'ouvre rien.

`Test-ActionAllowed` juge alors **qui demande**, avec trois refus qui ne disent pas la même chose :

| | |
|---|---|
| on ne sait pas qui demande | fenêtre ouverte sans identification — le panneau renvoie vers l'icône de Vigie |
| on sait, et ce compte n'est pas administrateur | « Windows la refuserait de la même façon » |
| le demandeur a le droit, mais le serveur n'est pas élevé | il ne **peut** pas, ce n'est pas un refus de droit |

Hors contexte web — rafraîchissement de fond, script lancé à la main — le demandeur est **celui qui exécute**.

*Cette fonction a longtemps posé la mauvaise question : elle demandait si le **serveur** était élevé, or il tourne sous
un compte de service administrateur, donc toujours. Une action `admin` passait pour n'importe qui, y compris pour un
navigateur ouvert sur l'adresse sans identification — pendant que l'écran des utilisateurs affichait que Vigie refuse
les actions administrateur à un compte standard. Corrigé le 31/08.*

La **garde réelle** est dans `Invoke-ActionById`, le seul point par où passe une action : une requête peut arriver sans
passer par l'interface. L'affichage des boutons, lui, est calculé au rendu des cartes et peut être servi depuis le
cache commun ; un bouton peut donc apparaître actif et se faire refuser au clic, avec sa raison. Une action ne
disparaît jamais (D59) : elle se voit et s'explique.

## Une fenêtre qui ne dit pas qui elle est

Ouvrir l'adresse à la main — navigation privée, signet, autre navigateur — n'associe la fenêtre à aucun compte. Vigie
servait pourtant le panneau **entier**, jeton d'API compris : n'importe quel programme du poste pouvait lire l'état de
la machine et agir. *Constaté le 31/08 en navigation privée : tout était visible.*

Le comportement est **réglable par un administrateur**, dans Paramètres > Utilisateurs, et vaut pour tout l'ordinateur
(`AnonymousAccess`, dans `machine.psd1`) :

| | |
|---|---|
| `error` — **le défaut** | `apps/frontend-web/no-session.html`, servie en 403 : ni état, ni jeton, ni liste de cartes. Elle ne dit pas non plus ce qui manque exactement — « ouvrez Vigie depuis son icône » suffit à qui a le droit d'être là. |
| `cards` | le panneau, avec les droits d'un compte standard : les actions qui touchent la machine restent refusées. |

L'écriture du réglage est vérifiée **côté serveur** — compte administrateur ET serveur élevé — parce qu'un menu grisé
n'est qu'un affichage.

## Les cercles de comptes

| | | |
|---|---|---|
| 1 | tous les comptes de l'ordinateur | `Get-ComputerAccounts` |
| 2 | les comptes de personne | `Get-UserAccounts` |
| 3 | ceux qui ont Vigie activée | `Get-EnabledAccounts` |
| 4 | ceux qui tournent | tâche + app cliente vivante — pas de fonction, personne n'en a besoin |

`check-coherence` refuse qu'un de ces cercles soit refiltré à la main : le filtre était recopié à sept endroits, et
l'appel qui l'avait oublié déposait un ordre de relance chez le compte de service.

## Le cache

Le rendu des sondes est mis en cache dans un fichier **commun**. Une sonde dont la carte dépend de qui regarde se
déclare `PerAccount = $true` dans son `module.psd1` et obtient une clé par compte (`comptes.probe.ps1@fhaza`). Le relevé
lui-même reste neutre : ce qu'on écrit sur le disque doit rester vrai pour n'importe qui.

L'invalidation demandée par une action retire aussi les entrées par compte.

**Un affichage ne recalcule RIEN.** Ni le chargement de la page, ni le sondage automatique : ils servent le cache tel
quel et repartent. Une carte qu'on ne connaît pas encore ne s'affiche pas — elle apparaîtra quand quelqu'un l'aura
demandée. Un recalcul se **demande** : le bouton ↻ en haut de la page pour tout, le bouton d'une carte pour elle seule.

*Il y avait un rafraîchissement de fond, lancé dès qu'une sonde était périmée. Il recalculait, les délais des autres
expiraient pendant ce temps, la requête suivante en relançait un : des passes qui s'enchaînaient sans interruption, une
machine occupée en permanence et un `/state` à 27 secondes (mesuré le 31/08). Supprimé.*
