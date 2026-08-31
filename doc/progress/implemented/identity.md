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

Deux conséquences tenues par le code : ces cartes ne sont **jamais** différées vers le rafraîchissement de fond (qui
tourne sans session, donc écrirait sous une clé anonyme), et l'invalidation demandée par une action retire aussi les
entrées par compte.
