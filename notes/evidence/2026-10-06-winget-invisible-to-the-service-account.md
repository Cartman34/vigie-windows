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
Le mécanisme ne privilégie pas celui qui regarde, il interroge celui qui attend depuis le plus longtemps.

## Ce qui reste de S02

La **recherche de mises à jour** (`pkg-check-updates` → `pkg-job.worker.ps1`) tourne toujours sous le compte de
service. Elle verra donc les paquets de ce compte, pas ceux du profil. C'est le prochain pas, et il est plus lourd :
l'opération suit le protocole des opérations, et son travail natif doit passer dans la session sans sortir du
protocole.
