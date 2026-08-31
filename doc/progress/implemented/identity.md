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
2. Elle l'échange contre un **ticket** à usage unique (30 s), qu'elle met dans l'URL du panneau.
3. La page consomme le ticket et reçoit un **cookie de session** (`HttpOnly`, `SameSite=Strict`).

Une page ouverte sans preuve d'ouverture — un signet, un rechargement — n'a donc pas de cookie : personne n'est
« vous », et c'est dit ainsi plutôt que d'attribuer la session au compte de service.

> **Le mot « ticket » est interne, et il n'a jamais été validé.** Il ne s'affiche nulle part dans l'application ; il ne
> vit que dans le code (`/session/ticket`, `New-OpenTicket`, `Use-OpenTicket`) et dans cette page. À renommer le jour
> où l'étape reçoit un nom du projet.

### Écart connu — le raccourci du bureau ouvre une page sans identité

L'installation pose `Vigie.url` sur le bureau, qui pointe directement sur `http://127.0.0.1:47600/`, **sans** preuve
d'ouverture. Ouvert par là, le panneau n'a pas de cookie : la carte des utilisateurs n'affiche « vous » sur personne
(constaté le 31/08), et surtout **aucune action ne sait qui la demande** — le tag de version se poserait sans
demandeur, et les cartes par compte n'ont personne à qui se rapporter.

L'app cliente, elle, emprunte la chaîne complète : `tray.ps1` demande la preuve d'ouverture puis ouvre `/?t=…`.

Approches envisagées, **aucune tranchée** : le raccourci passe par la même chaîne que l'app cliente ; ou le serveur,
qui est élevé, remonte du port source d'une connexion locale au processus puis au compte ; ou l'installation cesse de
poser un raccourci qui mène à une page dégradée.

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
