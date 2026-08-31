# Installation

[Sommaire](../README.md) · [English](../../en/operating/install.md)

Deux voies. L'**archive** est celle qu'on recommande : ni git, ni outillage de
développement. Le **clone git** s'adresse à qui compte lire ou modifier le code.

> Vigie est en version **0.1**. L'archive est fabriquée par `scripts/build-release.ps1`,
> puis attachée à une Release GitHub par un mainteneur. Si la page des Releases est encore
> vide, aucune version n'a été publiée et c'est la voie git qui fonctionne.

---

## Prérequis

| | |
|---|---|
| Windows | 10 ou 11 |
| PowerShell | **7** (`pwsh`). `scripts\install.ps1` l'installe via winget s'il manque, puis demande de le relancer. |
| Module Pode | installé par `scripts\install.ps1` (portée `AllUsers` si élevé, sinon `CurrentUser`) |
| Droits | administrateur, pour les actions Windows Update et la tâche de démarrage |
| Navigateur | Edge ou Chrome pour la fenêtre applicative dédiée ; n'importe lequel pour la page simple |

Ni Node, ni npm, ni étape de construction : le front est un unique fichier HTML statique.

---

## Voie 1 — l'archive publiée (recommandée)

1. Rendez-vous sur la [dernière version publiée](https://github.com/Cartman34/vigie-windows/releases/latest) — ce lien pointe toujours sur la plus récente,
   sans avoir à connaître son numéro — et téléchargez `vigie-<version>.zip`. La
   [liste complète](https://github.com/Cartman34/vigie-windows/releases) reste accessible si vous cherchez une version antérieure.
2. Décompressez-la où vous voulez. Elle se déplie en un unique dossier `vigie-<version>/`, qui n'est qu'un
   intermédiaire : `setup.cmd` **copie Vigie dans `C:\Program Files\Sowapps\Vigie`** et c'est cette copie qui
   sera lancée ensuite. Le dossier décompressé peut être supprimé après l'installation.
3. Windows marque les fichiers téléchargés comme bloqués. Soit vous débloquez le dossier
   une fois :
   ```powershell
   Get-ChildItem -Recurse | Unblock-File
   ```
   soit vous utilisez les lanceurs `.cmd` ci-dessous, qui contournent volontairement la
   stratégie d'exécution.

Puis suivez [Premier lancement](#premier-lancement).

### Ce que contient l'archive — et ce qu'elle ne contient pas

L'archive est le **produit**, pas le dépôt. Elle porte le serveur, le front, l'app de la
barre système, les scripts d'installation, cette documentation, la licence et le fichier
de version — une petite centaine de fichiers.

Volontairement laissés de côté :

| Absent | Pourquoi |
|---|---|
| `apps/atelier/` | outil de développement (PHP, port 47610) qu'un utilisateur ne lance jamais |
| `scripts/build-release.ps1`, `scripts/install-hooks.ps1`, `scripts/hooks/` | outillage de mainteneur ; ils exigent un dépôt git, ce que l'archive n'est pas |
| `scripts/uninstall-legacy.ps1` | nettoyage daté et jetable des postes antérieurs au renommage — sans objet sur une installation neuve |
| Les documents de travail internes (décisions, backlog, journal, conventions) | la mémoire du dépôt, pas de la documentation d'usage. Les pages qui y renvoient pointent vers GitHub |
| `apps/*/var/`, `config.local.psd1`, les journaux, le jeton d'API | données d'exécution et secrets. Ils ne sont jamais versionnés, donc ils ne peuvent pas atteindre l'archive |

Si l'un d'eux vous manque, passez par la voie git.

## Voie 2 — clone git

```powershell
git clone https://github.com/Cartman34/vigie-windows.git
cd vigie-windows
```

Même arborescence, mêmes scripts. À choisir pour suivre `main`, lire le code ou
contribuer — voir [Développement](../../en/developing/README.md).

### Ce que l'installation déclare quand elle part d'un dépôt

Lancée depuis un clone git, `setup.cmd` note deux choses **pour tout l'ordinateur**, dans
`%ProgramData%\Sowapps\Vigie\machine.psd1` :

| | |
|---|---|
| `SourcePath` | d'où vient ce déploiement — un **fait**, pas une intention |
| `safe.directory` (config git machine) | ce dossier est de confiance pour git |

**Pourquoi la seconde.** L'app serveur tourne sous un compte de service, et git refuse
d'ouvrir un dépôt appartenant à quelqu'un d'autre (« detected dubious ownership »). Sans
cette déclaration, le service ne peut même pas **cloner** votre dépôt : le bouton « Mettre
à jour » de l'interface échouerait, sans que rien n'explique pourquoi.

Elle demande l'élévation. Sans elle, l'installation continue et **le dit** — la mise à jour
depuis l'interface restera en échec tant que ce ne sera pas fait :

```powershell
git config --system --add safe.directory C:/chemin/vers/votre/depot
```

**L'environnement, lui, ne se déduit jamais.** Trouver un dépôt ne fait pas d'un poste une
machine de développement : `Environment` (`dev` ou `prod`) se déclare dans
`apps\backend-pode\config\config.local.psd1`, et il ne dit pas d'où vient le code —
c'est `UpdateSource` / `UpdateRemote` qui le disent. Les deux sont indépendants : un
environnement de développement peut se synchroniser depuis un dépôt distant, une
production depuis un clone local.

---

## Premier lancement

Tout vit dans `scripts\`. Chaque script est **idempotent** : le relancer ne casse rien.

### 1. Les prérequis, une fois

**Le plus simple : double-cliquez `setup.cmd`.** Il demande lui-même
l'élévation (fenêtre Windows à accepter), fait la première passe avec Windows PowerShell —
`pwsh` n'existe pas encore au moment d'installer — puis la seconde avec PowerShell 7 une
fois celui-ci posé.

En ligne de commande, dans un terminal **administrateur** :

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

`install.ps1` bascule tout seul en PowerShell 7 si vous l'avez lancé depuis 5.1, installe
le provider NuGet, approuve le dépôt PSGallery, installe **Pode**, génère le jeton d'API
local et vérifie la présence du runtime WebView2. Il écrit un transcript dans
`var\log\install_*.log`.

**Il commence par se copier dans `C:\Program Files\Sowapps\Vigie`**, puis reprend depuis cette copie : c'est elle
que la tâche de démarrage lancera. Deux exceptions, où Vigie reste où elle est — un **clone git** (poste de
développement, Vigie tourne depuis les sources) et une installation **déjà** faite à cet emplacement. Les réglages de
la machine déjà présents à destination (`config/*.local.*`, `actions.policy.json`) sont conservés : mettre à jour ne
remet pas les choix à zéro.

**Vos données ne vivent jamais à côté du programme.** Jeton, journaux, caches et réglages d'un compte vont dans
`%LOCALAPPDATA%\Sowapps\Vigie`. Le serveur tourne élevé, il *pourrait* écrire dans Program Files — et c'est
justement le piège : tous les comptes partageraient alors le même jeton et les mêmes réglages, alors que chacun doit
avoir les siens.

**L'élévation n'est pas facultative quand PowerShell 7 manque** : l'installation se fait
en portée **machine** (`--scope machine`), sans quoi winget pose le paquet dans le profil
du compte courant et les autres comptes ne peuvent pas démarrer Vigie. Sans droits
administrateur, `install.ps1` s'arrête et affiche la commande à lancer plutôt que de
retirer une version qui fonctionnait avant d'échouer. Lancé élevé, il installe aussi Pode
pour **tous les utilisateurs**, ce dont la tâche planifiée élevée a besoin.

### 2. Lancer Vigie

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

ou double-cliquez sur `scripts\run.cmd`.

`run.ps1` se relance sous PowerShell 7 et **s'élève via UAC** : le serveur doit tourner en
administrateur pour lire et appliquer le verrou Windows Update. Il installe Pode
automatiquement s'il manque encore, refuse de démarrer un second serveur si un autre écoute
déjà (il ouvre simplement le navigateur), et n'ouvre le navigateur qu'une fois le port
réellement à l'écoute. `-NoBrowser` évite d'ouvrir un onglet.

Le tableau de bord est sur <http://127.0.0.1:47600/>. L'API REST est sous `/api/v1`.

### 3. Le rendre permanent (facultatif, mais c'est l'usage prévu)

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

ou double-cliquez sur `scripts\install-autostart.cmd`.

Avant toute invite UAC, une fenêtre énumère exactement ce qui va être modifié et vous
laisse refuser **sans qu'aucune invite système n'apparaisse**. Ce qu'elle fait :

- enregistre une tâche planifiée nommée **`Vigie`**, déclenchée à l'ouverture de session,
  qui lance `apps\tray\tray.ps1` en fenêtre cachée avec les **privilèges les plus élevés** ;
- crée un raccourci bureau `Vigie.url` vers le tableau de bord ;
- démarre la tâche tout de suite, l'icône apparaît donc immédiatement.

Codes de retour : `0` installé, `1` prérequis manquant, `3` refusé.

`scripts\start-vigie.vbs` relance ensuite cette tâche silencieusement, et
`scripts\install-autostart.vbs` est la variante silencieuse de l'installeur.

---

## Désinstaller

### Retirer le démarrage automatique

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\uninstall-autostart.ps1
```

Retire la tâche planifiée `Vigie` et le raccourci bureau. **Aucun fichier de l'application
n'est supprimé** ; réinstallable à tout moment avec `install-autostart.ps1`. Le code de
retour `3` signifie que vous avez refusé à la fenêtre d'explication.

### Retirer Vigie entièrement

Après l'étape précédente, supprimez deux dossiers :

- le programme, `C:\Program Files\Sowapps\Vigie` (ou celui d'où vous la lanciez, si vous
  travaillez depuis un clone git) ;
- vos données, `%LOCALAPPDATA%\Sowapps\Vigie` — réglages, journaux et caches. **Chaque compte a les
  siennes** : un compte qui a utilisé Vigie garde les siennes tant que vous ne les effacez pas depuis ce compte.

Rien d'autre de Vigie ne vit en dehors — sauf ce que vous lui avez demandé de changer sur le système :

> **Important :** désinstaller Vigie ne **déverrouille pas** Windows Update. Si vous
> l'aviez verrouillé, déverrouillez-le *avant* de retirer Vigie, sinon la machine reste
> avec ses mises à jour automatiques coupées. Voir
> [Windows Update](../using/windows-update.md#déverrouiller-pour-de-bon).

### Vestiges d'une installation antérieure au renommage

Les postes installés avant que le projet ne s'appelle Vigie portent une tâche planifiée et
un raccourci orphelins. Un script daté et jetable les retire — **il est livré avec le
dépôt uniquement, pas avec l'archive**, puisqu'il ne peut pas concerner une installation
neuve :

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\uninstall-legacy.ps1 -WhatIf
pwsh -ExecutionPolicy Bypass -File .\scripts\uninstall-legacy.ps1 -LegacyWorkspace 'C:\chemin\vers\ancien-dossier'
```

`-WhatIf` montre ce qui serait fait et ne modifie rien. L'ancien espace de travail est
**renommé** avec un suffixe `.old`, jamais supprimé : l'effacer reste votre geste
volontaire. Codes de retour : `0` terminé, `2` au moins une étape en échec, `3` refusé.

---

## Ensuite

- [Premiers pas](../using/getting-started.md) — l'icône, le tableau de bord, votre première action
- [Configuration](configuration.md) — port, outillage externe, surcharges locales
- [Dépannage](../using/troubleshooting.md) — quand une de ces étapes ne se passe pas comme écrit
