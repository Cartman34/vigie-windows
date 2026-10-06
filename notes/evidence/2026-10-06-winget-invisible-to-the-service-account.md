# winget était invisible pour Vigie — mesuré, corrigé, constaté

Sujet **S02**, les mesures par utilisateur que la session 0 ne voit pas (`targeting/multi-account-server.md` → C4).
Tout ce qui suit est **lu dans Vigie**, pas reconstitué.

## Le constat, 05/10

L'app serveur ne produisait que **deux** cartes de gestionnaires de paquets :

| Carte | Gestionnaire | Où il est installé |
|---|---|---|
| `pkg-choco` | Chocolatey | `C:\ProgramData\chocolatey\bin\choco.exe` — pour toute la machine |
| `pkg-pip` | pip | `C:\Python311\Scripts\pip.exe` — pour toute la machine |

**winget manquait**, alors que la machine l'a. Son exécutable vit dans un profil :
`…\AppData\Local\Microsoft\WindowsApps\winget.exe`. L'app serveur tourne sous un compte de service, dont le `PATH`
ne nomme jamais ce dossier. Le gestionnaire de paquets **principal de Windows** était donc absent du panneau, sans
que rien ne le signale : la carte n'existait pas, il n'y avait pas d'erreur à lire.

## Le correctif

La porte existait déjà pour WSL (D113) : le serveur confie à l'app cliente du compte ce qui a besoin de sa session.

1. **Action `pkg-inventory`**, `@execution: session` — résout chaque gestionnaire du catalogue et lit sa version,
   dans la session du compte, avec son `PATH`. Lecture seule.
2. **`Update-PkgInventory`**, dans la passe de veille — demande à **un compte par passe**, le plus en retard, au plus
   une fois par heure. Onze lancements de processus dans trois sessions à la même seconde n'auraient rien appris de
   plus.
3. **La sonde lit l'inventaire** en plus de ce qu'elle voit elle-même : un gestionnaire installé pour toute la
   machine reste vrai sans personne de connecté.
4. **La carte dit d'où vient la lecture.** Sans ça elle donnerait à croire que le serveur l'a vu lui-même.

## Le constat après, 06/10

Quatre cartes, et la nouvelle porte sa provenance :

```
pkg-choco · pkg-pip · pkg-winget · (pkg-check-updates)

winget — Version 1.29.380
  Chemin : C:\Users\Famille\AppData\Local\Microsoft\WindowsApps\winget.exe
  Lu dans la session de Famille : ce gestionnaire est installé dans ce profil,
  l'app serveur ne le voit pas.
```

C'est le compte **Famille** qui a répondu, et non `fhaza` : il était le plus en retard des deux sessions ouvertes.

## Et le premier jet montrait le winget d'un autre

Relevé ci-dessus : la carte affichait un chemin sous `C:\Users\Famille\` à une session ouverte sous `fhaza`. La
première version repliait sur **l'union des comptes** quand le demandeur n'avait pas encore été lu.

Le propriétaire l'a vu le jour même, et sa question tranche la conception : **le compte de service n'a pas winget, et
il n'y a rien au niveau de la machine**. Donc rien ici n'appartient à la machine. Une carte winget construite depuis
la lecture d'un autre compte montre son chemin, sa version, et à l'étape suivante **ses mises à jour** — qui ne sont
pas celles du lecteur.

Le repli est retiré : chaque compte voit le sien, ou rien. Et « pas encore lu dans votre session » est **écrit sur la
carte** plutôt que laissé en trou — la passe de veille lit un compte par passe, une session qui vient de s'ouvrir
attend son tour.

**Une mesure par compte empruntée à un autre compte est fausse, même quand elle est exacte.**

## Ce qui reste de S02

La **recherche de mises à jour** (`pkg-check-updates` → `pkg-job.worker.ps1`) tourne toujours sous le compte de
service. Elle verra donc les paquets de ce compte, pas ceux du profil. C'est le prochain pas, et il est plus lourd :
l'opération suit le protocole des opérations, et son travail natif doit passer dans la session sans sortir du
protocole.
