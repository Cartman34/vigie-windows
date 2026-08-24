# Décisions validées — à ne JAMAIS perdre

> Règle : toute décision validée par l'utilisateur est consignée ici **et** son
> support (maquette HTML, paramètres exacts) est copié dans `docs/maquettes-validees/`.
> Ces fichiers vivent dans le dépôt, sur la machine — jamais uniquement dans une
> discussion ou un environnement éphémère.
>
> **Numérotation** : les décisions sont numérotées `Dnn`, définitivement. Un numéro
> n'est jamais réattribué, même si la décision est plus tard remplacée (on ajoute
> alors une nouvelle décision qui indique celle qu'elle remplace).
> Cette numérotation est **indépendante** de celle des questions (`Qn`, réutilisable
> une fois les questions répondues).

---

## Sommaire

Uniquement des renvois : les titres vivent plus bas, une seule fois.
Ajouter une décision = ajouter son numéro à une ligne.

- **Identité et nommage** — D03 · D04 · D05 · D28 · D30 · D41
- **Structure du dépôt** — D29 · D32 · D33 · D35
- **Configuration** — D15 · D18
- **Interface** — D01 · D02 · D08 · D09 · D19 · D20 · D23 · D25 · D26 · D27 · D37 · D38 · D42 · D45 · D46 · D48
- **Sécurité et installation** — D07 · D11 · D22 · D34
- **Outillage** — D06 · D21 · D24 · D40 · D44 · D47
- **Méthode de travail** — D10 · D12 · D13 · D14 · D16 · D17 · D31 · D36 · D39 · D43

---

## D01 — Icône du tray : « v1 — jauge à graduations »

**Nom de référence : `icône tray v1 — jauge à graduations`.**
Provenance historique : proposée comme « option B — Teinte 0,72 » dans la maquette
`docs/maquettes-validees/icone-tray_needle-liseres2.html`. Ce libellé d'option n'a plus
cours (voir **D04**) ; il n'est conservé ici que pour retrouver la maquette d'origine.

Caractéristiques (en fractions de la taille `s`) :
- anneau : rayon `0.45`, trait `0.024`, couleur du statut à opacité `0.35` ;
- piste (fond d'arc) : couleur `#30363d`, largeur `sw = 0.11`, extrémités rondes, de `135°` sur `270°` ;
- arc de valeur : couleur du statut, largeur `0.11`, de `135°` sur `frac*270°` ;
- **graduations** : **7** traits radiaux de `r*0.98` à `r*0.80`, `#8b949e` opacité `0.35`, largeur `0.02`,
  aux angles `135° + (i/6)×270°` pour `i = 0..6` — donc **7 traits**, bornes comprises.
  *(Corrigé le 2026-08-22 : cette ligne annonçait « 6 traits », en reprenant la borne `/6` de la
  boucle au lieu du nombre de traits. Vérifié dans la maquette validée (`for(let i=0;i<=6;i++)`)
  ET dans le générateur déployé (`range(0,7)`) : les deux en tracent bien 7. Le code était juste,
  c'est la décision qui était mal transcrite.)* ;
- aiguille : du **talon** `pt(-0.06, ang)` à la pointe `pt(r*0.92, ang)` ;
  - liseré : teinte foncée `darken(couleur, 0.72)` opacité `0.95`, largeur `0.098` ;
  - aiguille : couleur du statut, largeur `0.082` ;
- moyeu : couleur du statut, rayon `0.095` ; point central blanc `#f0f6fc` rayon `0.042` ;
- fractions du niveau : conforme `0.88`, à surveiller/démarrage `0.50`, erreur `0.14` ;
- couleurs : ok `#3fb950`, warn `#d29922`, err `#f85149`.

**Statut reflété** : celui de l'APP (via `/health`) — 3 états seulement : marche (vert) /
démarrage (orange) / erreur ou arrêt (rouge). Jamais l'état des composants.

**CONFIRMÉ par l'utilisateur** : on garde graduations + talon d'aiguille, fidèle à la maquette.

> Historique à ne pas perdre : le 21/08, graduations et talon avaient été **supprimés** (jugés
> « bruit à 16 px ») — `SUIVI.md` en garde la trace. Cette suppression a été **annulée** : la
> présente décision, plus récente, fait foi, et le code déployé la respecte.

## D02 — Reproduction de l'icône en `.ico` (déployée)

- Générée à l'identique de **D01** par `apps/tray/assets/generate-icons.py` (PIL)
  → `ok.ico` / `warn.ico` / `error.ico` (multi-résolutions 16→256).
- Chargées par `tray.ps1` (fonction `setIcon`). *Mis à jour :* le repli GDI+ décrit ici a été
  **supprimé** (**D38**) ; en cas d'échec de lecture, un simple disque de la couleur du statut
  est dessiné et l'échec est journalisé.

## D03 — Nom du projet

- **Dépôt GitHub** : « Vigie Windows » (slug `vigie-windows`), https://github.com/Cartman34/vigie-windows
- **Interface** : nom court **« Vigie »**, affiché **à la place de « Control Panel »** (discret,
  pas en gros dans la barre). Le titre principal de la barre reste le **nom de la machine** (dynamique).

---

## D04 — Nommage des options validées : « vX — nom descriptif »

Une option retenue **perd son numéro d'option** (A/B/C…), qui n'a de sens que pendant
l'arbitrage. Elle est renommée « **vX — nom descriptif** » : la version tranche l'antériorité,
le nom dit de quoi il s'agit. Exemple : « icône tray v1 — jauge à graduations » (**D01**).
Le libellé d'origine peut rester mentionné comme simple provenance vers la maquette.

## D05 — « HYPERION » est le nom de la machine, pas celui du projet

Le projet s'appelle **Vigie**, le dépôt **vigie-windows**. « HYPERION » est le nom de la
machine de l'utilisateur : sa présence dans le code est un **nom de machine codé en dur**,
donc un défaut de généricité — pas un point cosmétique optionnel. Il est éliminé du projet
(code, identifiants techniques, documentation).

Renommages retenus :

| Avant | Après |
|---|---|
| Tâche planifiée `HyperionControlPanel` | `Vigie` |
| Raccourci bureau `HYPERION Control Panel.url` | `Vigie.url` |
| Mutex tray `HyperionControlPanelTray` | `VigieTray` |
| Mutex `Local\HcpState_<sonde>` | `Local\VigieState_<sonde>` |
| Mutex `Local\HcpStateRecompute` | `Local\VigieStateRecompute` |
| Types .NET `HcpNative`, `HcpDarkColors` | `VigieNative`, `VigieDarkColors` |
| Variables d'environnement `HCP_BACKEND`, `HCP_TOKEN`, `HCP_PORT` | `VIGIE_BACKEND`, `VIGIE_TOKEN`, `VIGIE_PORT` |
| Titre `apps/backend-pode/api/openapi.yaml` « HYPERION Control Panel API » | « Vigie API » |
| `backend/demarrer-hyperion.vbs` | `scripts/start-vigie.vbs` |

**Exception** : `docs/maquettes-validees/` n'est pas retouché — c'est l'archive des supports
de décision, on n'y réécrit pas l'histoire.

## D06 — Validation du JS du front : navigateur, pas Node

**Node n'est pas installé** sur la machine et **n'est pas ajouté** : le projet n'a aucune
dépendance JS (pas de `package.json`, pas de build, un seul fichier HTML servi tel quel) ;
installer un runtime permanent pour une seule vérification syntaxique n'est pas justifié.

Validation retenue : charger `apps/frontend-web/index.html` en `file://` dans un navigateur et lire
la console. Cela couvre **plus** que `node --check` : erreurs de syntaxe, erreurs d'exécution,
rendu réel, et le repli sur la maquette `mock/state.json` qui est précisément le mode `file://`.
`node --check` sera réintroduit si le front acquiert un jour une vraie chaîne de build.

Le PowerShell reste validé par le Parser : `[System.Management.Automation.Language.Parser]::ParseFile(...)`.

## D07 — L'installation bascule sur le dépôt

L'app installée (tâche planifiée) pointait encore sur l'ancien espace de travail
`C:\EspaceRestreint\Workspaces\AiTeam\LocalWork\hyperion-control-panel`, alors que les
sources vivent désormais dans `C:\EspaceRestreint\Workspaces\Git\vigie-windows`.
Vérifié : les deux copies étaient **identiques** (74 fichiers, aucun écart d'empreinte).

**État : NON FAIT au 2026-08-22** — exige un PowerShell administrateur, impossible depuis la
session de l'agent. Ce qui suit décrit la **cible**, pas l'existant.

- La tâche planifiée doit être repointée sur le **dépôt principal**
  (`C:\EspaceRestreint\Workspaces\Git\vigie-windows\backend\tray.ps1`) — **jamais** sur un
  worktree, qui est temporaire.
- L'ancien espace de travail est **renommé** (suffixe `.old`) et non supprimé ; sa suppression
  n'aura lieu qu'après confirmation explicite que tout fonctionne.
- Outil : `scripts/uninstall-legacy.ps1` (voir **D11**) retire la tâche et le raccourci hérités
  et met l'ancien dossier de côté. `scripts/install-autostart.ps1` enregistre la tâche courante.
  Les deux exigent un PowerShell **administrateur**.

## D08 — Écran de chargement (splash)

Un écran de chargement soigné affiche **« Vigie » en gros** au démarrage, **à chaque ouverture
de la fenêtre**, et s'efface dès le premier chargement réussi. Comportement régulier et
prévisible, plutôt qu'un affichage conditionnel au démarrage à froid du serveur.

## D09 — Lien GitHub retrouvable dans l'app

https://github.com/Cartman34/vigie-windows est accessible depuis **quatre** endroits :
le **splash**, une icône discrète dans la **topbar**, un **pied de page**, et l'entrée
**« À propos »** du menu du tray.

Les liens externes s'ouvrent dans une autre page ou un vrai navigateur (`target="_blank"`
+ `rel="noopener"`), jamais dans la fenêtre `--app` qui n'a pas de barre d'adresse.

## D10 — Branche de travail

Le travail se fait sur une branche dédiée (`claude/vigie-project-resume-*`), relue puis
fusionnée dans `main` par l'utilisateur. **La branche n'est pas supprimée à la fusion.**

## D11 — Un script de désinstallation dédié pour les vestiges

Les installations antérieures au renommage laissent une tâche planifiée et un raccourci
**orphelins**. Les nettoyer suppose de connaître les anciens noms — ce que **D05** demande
justement d'éliminer du projet.

Arbitrage retenu : `scripts/uninstall-autostart.ps1` ne connaît **que** les noms courants,
et un script **dédié et jetable**, `scripts/uninstall-legacy.ps1`, porte seul les anciens noms.
Il est daté (vestiges antérieurs au 2026-08-22), idempotent, exige une session élevée
(il ne s'auto-élève pas, pour que son compte rendu reste lisible), supporte `-WhatIf`, et
**ne supprime jamais de dossier** : l'ancien espace de travail est seulement mis de côté
(suffixe `.old`). Le chemin de cet espace est un **paramètre sans valeur par défaut** —
un chemin de machine n'a rien à faire dans le code.

Une fois tous les postes migrés, ce fichier peut être supprimé : les anciens noms
disparaissent alors avec lui.

## D12 — `docs/REPRISE.md` décrit l'environnement réel

La section « Contraintes environnement » décrivait une VM Linux éphémère (Cowork/`device_bash`,
« pas de pwsh », « git ne peut pas s'initialiser »). Elle est réécrite pour la machine réelle :
outils présents, outils volontairement absents (Node, cf. **D06**), méthode de validation de
chaque langage, privilèges (session non élevée), et ce qu'on ne committe jamais.

## D13 — `CHANGELOG.md` est tenu à jour

Le CHANGELOG s'était arrêté au 2026-08-19 alors que `SUIVI.md` journalisait les sessions
suivantes. Il est complété. Les deux fichiers ont des rôles distincts et sont conservés :
`SUIVI.md` = journal de travail détaillé (état courant, TODO, décisions techniques) ;
`CHANGELOG.md` = ce qui change **pour l'utilisateur de l'app**, par date.

## D14 — Rythme de commit et push (REMPLACE la version initiale)

Un commit unique par lot de travail terminé, sur la branche dédiée (**D10**),
**puis push immédiat sans demander**.

Ne **jamais** poser la question « est-ce que je pousse ? » : c'est une branche dédiée,
relue avant fusion (**D10**), donc pousser est sans risque et le demander est une
interruption inutile. La règle initiale « pas de push sans accord explicite » est
**annulée** par l'utilisateur.

## D15 — Une valeur unique n'est définie qu'à UN SEUL endroit

Règle générale, pas un cas particulier : toute valeur unique du produit (port,
adresse d'écoute, URL, chemin, nom, délai…) a **une seule** définition, dont tout
le reste dérive. Aucune recopie, aucun « en dur » qui doublonne une source existante.

Cas déclencheur : `install-autostart.ps1` écrivait `http://127.0.0.1:47600/` en dur
dans le raccourci bureau alors que `config.psd1` porte déjà `BindAddress` et `Port`
et que `Get-Config` existe — changer le port produisait un raccourci mort.

Corollaire déjà appliqué : l'URL du dépôt est une constante unique par langage
(`REPO_URL` / `$RepoUrl`, **D09**).

## D16 — Traiter tout le backlog, dans l'ordre reçu

Les sujets du backlog se traitent **tous**, **dans l'ordre**, l'un après l'autre.
Ne pas demander à l'utilisateur lequel prendre ensuite : l'ordre est déjà donné.
Un sujet réellement bloqué (droits, décision manquante) est signalé et **sauté**,
le suivant est traité — on ne s'arrête pas au blocage.

## D17 — Ne se charger que d'informations utiles

Ne pas aller lire d'anciennes entrées, d'anciens fichiers ou d'anciennes sections
quand ce n'est pas nécessaire à la tâche en cours. Le contexte est une ressource :
le remplir d'informations inutiles dégrade le travail. Corollaire : ne pas soulever
de questions cosmétiques sur du contenu ancien qu'on n'avait aucune raison d'ouvrir.

## D18 — Configuration : un socle versionné générique + une surcharge locale

`apps/backend-pode/config/config.psd1` est **versionné et générique** : il porte LA définition de chaque
valeur et ne contient plus rien de propre à une machine. `ToolsPath` y vaut `''`.

`apps/backend-pode/config/config.local.psd1` est **ignoré par git**, optionnel, et surcharge les seules
valeurs qui ne peuvent pas être génériques (chemins d'une machine donnée).
`apps/backend-pode/config/config.local.sample.psd1` est le modèle versionné qui documente ce qu'on peut
y surcharger. `Get-Config` fusionne les deux, et **échoue avec un message explicite**
si le fichier local est illisible.

Toute valeur dérivée est calculée à UN endroit (**D15**), dans `lib/common.ps1` :
`Get-AppUrl`, `Get-ApiUrl`, `Get-ToolsPath`, `Get-AdminRoot`, et la réponse commune
`New-ToolsMissingResult`. Plus aucune URL ni port en dur ailleurs dans le code.

L'outillage externe est **optionnel** : `ToolsPath` vide ou introuvable → les actions qui
en dépendent rendent un message clair au lieu d'échouer obscurément. Un clone neuf
fonctionne donc sans configuration, avec ces actions désactivées.

> *Mis à jour :* « avec ces actions désactivées » n'était pas tenable pour la fonction
> **phare** du produit. Le verrouillage de Windows Update (`update-mode-on`,
> `update-mode-off`) et son audit (`run-audit`) sont désormais **natifs**, dans
> `lib/common.ps1` (`Set-UpdateLock`, `Invoke-UpdateAudit`, `Get-UpdateLockState`,
> `Get-UpdateTaskCatalog`) : une installation faite depuis GitHub dispose de la fonction
> entière. `ToolsPath` reste *préféré* s'il porte `update-mode.ps1`, jamais requis.
> Restent tributaires de l'outillage : `toggle-vbs`, `toggle-hvci` et `open-folder`.

**Exception assumée** : dans `server.ps1`, la liste blanche anti-CSRF garde `127.0.0.1` et
`localhost` en littéral. Ce n'est **pas** une copie de `BindAddress` mais la liste des
origines de **bouclage**, volontairement fixe : même si `BindAddress` changeait, seule une
origine locale doit être acceptée. Le port, lui, dérive bien de la config.

## D19 — Menu du tray : style Windows 11

Le menu contextuel de la barre système suit la référence « menu sombre arrondi type Win11 » :

- **Coins arrondis natifs** via DWM (`DwmSetWindowAttribute`, `DWMWA_WINDOW_CORNER_PREFERENCE`
  = `DWMWCP_ROUND`), et non par découpe de région : on conserve l'anticrénelage et l'ombre
  système. Couleur de bordure posée par `DWMWA_BORDER_COLOR`. Appliqué à chaque ouverture
  (idempotent, le menu peut recréer son handle).
- **Survol encarté et arrondi** (rayon 5 px, marge latérale 5 px) au lieu d'une bande pleine
  largeur — c'est la différence la plus visible avec le rendu WinForms par défaut.
- **Items de 32 px** (mesuré), séparateurs fins et encartés alignés sur les mêmes marges.
- Palette définie **une seule fois** dans `VigieMenuPalette` (**D15**) : la table de couleurs
  et le renderer y puisent tous les deux.
- Couleur et hauteur des items sont posées par **une seule boucle** sur `$menu.Items`, plus
  item par item.

Tout échec (compilation, DWM) retombe silencieusement sur le rendu par défaut : le menu reste
utilisable. Sur une version antérieure à Windows 11, l'appel DWM échoue sans dommage.

**Piège à retenir** : `System.Drawing` est scindé en plusieurs assemblages — `Color` vient de
`System.Drawing.Primitives`, `Graphics` et `GraphicsPath` de `System.Drawing.Common`. Un
`Add-Type` qui ne référence que le premier échoue sur `Drawing2D`.

## D20 — WSL inactif est signalé : champ ET carte en rouge

« WSL inactif » est un **état à signaler**, pas un état normal : le champ « Statut » **et**
la carte passent en rouge. La carte reçoit un lisere gauche rouge de 4 px et le badge
« Problème » ; le bouton « Démarrer » reste proposé.

Cela corrige au passage une **contradiction** : le champ était déjà rouge alors que la carte
restait neutre. Désormais les deux dérivent de la **même** variable, ils ne peuvent plus
diverger. WSL **non installé** reste neutre : on ne reproche pas à une machine de ne pas
l'avoir installé.

**Exigence explicite de l'utilisateur : ce choix doit rester trivial à rebasculer.**
Il tient donc en **une seule ligne**, en tête de `apps/backend-pode/probes/wsl/wsl.probe.ps1`, sous un
bandeau de commentaire qui énumère les valeurs possibles :

```powershell
$inactiveSeverity = 'error'   # 'error' rouge | 'warn' orange | 'neutral' gris
```

Aucune autre ligne n'est à toucher, et **rien** n'est à changer côté front : les trois valeurs
sont déjà rendues. Vérifié en exécutant la sonde réelle sur les **6** combinaisons
(3 sévérités × actif/inactif) : carte et champ concordent à chaque fois.

Ce réglage vit dans la sonde et non dans `config.psd1` : c'est une décision **produit**,
pas une valeur propre à une machine (**D18**).

## D21 — Le contrat accepte `neutral` comme statut de module

`apps/backend-pode/api/openapi.yaml` déclarait `enum: [ok, warn, error]` pour le statut d'un module, alors que
`New-ModuleObject` accepte `neutral` et que les sondes en émettent (ex. WSL non installé).
Le contrat était faux : `neutral` y est ajouté et documenté. L'implémentation était juste.

## D22 — Jamais d'invite UAC « nue » : expliquer avant de demander

Quand un script de Vigie a besoin des droits administrateur, il affiche **d'abord** une
fenêtre qui dit ce qui va être modifié et pourquoi, **puis seulement** déclenche l'invite UAC.
Même principe qu'Android, qui explique une permission avant de la demander.

- L'utilisateur peut refuser **sans qu'aucune invite système n'apparaisse**.
- La fenêtre énumère les changements concrets (tâche, raccourci, dossier) et précise
  explicitement ce qui n'est **pas** touché.
- Échap et la croix **refusent** (`CancelButton`), jamais l'inverse.
- Sans interface graphique (session sans bureau, exécution automatisée), on explique en
  console et on **refuse par défaut** ; `-Yes` permet un lancement délibérément automatisé.

Implémentation partagée dans `lib/common.ps1` — chaque script avait auparavant **sa propre
copie** du bloc d'élévation :

| Fonction | Rôle |
|---|---|
| `Test-IsElevated` | le test d'élévation, rédigé une seule fois |
| `Show-ElevationRationale` | la fenêtre explicative, renvoie le consentement |
| `Invoke-ElevatedSelf` | relance le script en élevé **en conservant ses paramètres** et restitue sa sortie |
| `ConvertTo-PSLiteral` | échappement des apostrophes pour la ligne de commande élevée |
| `Set-WindowChrome` | barre de titre sombre / coins arrondis / couleur de bordure (DWM) |

Utilisé par `install-autostart.ps1`, `uninstall-autostart.ps1` et `uninstall-legacy.ps1`.
Code de retour **3** = refusé par l'utilisateur (distinct d'un échec).

**Point technique** : un processus lancé avec `-Verb RunAs` ne peut pas voir sa sortie
redirigée. `Invoke-ElevatedSelf` passe donc par `-Command` + un fichier journal, relu et
réaffiché par le processus appelant : le compte rendu n'est jamais perdu.

**Corollaire (D15)** : la signature P/Invoke `DwmSetWindowAttribute` n'est plus déclarée
qu'à un seul endroit (`Set-WindowChrome`). `tray.ps1` la déclarait de son côté pour les
coins arrondis de son menu (**D19**) ; il utilise désormais le helper partagé.

## D23 — Icône tray « v2 — jauge pleine à l'état conforme » (REMPLACE D01 sur ce point)

À l'état **conforme**, la jauge est **pleine** : fraction `1.00` au lieu de `0.88`.
Une jauge arrêtée avant la fin se lit comme « presque bon », ce qui n'est pas le message
voulu quand tout va bien.

- conforme : **1.00** (l'aiguille rejoint la fin de l'arc, en bas à droite) ;
- démarrage : `0.50` — inchangé ; erreur : `0.14` — inchangé.

Toute la géométrie de **D01** est conservée : seules les fractions changent.
Les `.ico` ont été **régénérés** (Pillow installé dans le scratchpad, pas dans le Python
de la machine).

> *Mis à jour :* cette décision exigeait de reporter la fraction à **deux** endroits
> (`generate-icons.py` et le repli GDI+ de `tray.ps1`). Le repli a depuis été **supprimé**
> (**D38**) : il n'existe plus qu'un seul endroit. La fraction d'erreur, elle, est passée
> à `0.17` (**D42**).

Le générateur est renommé `generer-icones_B.py` → **`generate-icons.py`** : la lettre
d'option ne survit pas à la validation (**D04**).

## D24 — Un atelier de validation visuelle, **servi** et outillé

`apps/atelier/index.html` — page de validation visuelle, **servie par un petit serveur
local** (`apps/atelier/atelier.ps1`, serveur intégré de PHP), pas ouverte en double-clic.

**Pourquoi un serveur** : ouverte en `file://`, la page ne peut pas faire son travail. Les
chemins relatifs vers les `.ico` cassent dès qu'on déplace le fichier (images cassées), et le
navigateur refuse d'afficher `apps/frontend-web/index.html` dans un cadre (rectangle noir). Les deux
défauts ont été constatés en livrant la première version : **c'était une livraison
inutilisable**. Servie en `http`, la page fonctionne entièrement.

Elle reste ouvrable en `file://` mais **le dit** alors, au lieu d'afficher des cassures
silencieuses.

**Contenu** : la marque du tray avec un curseur de fraction (16 → 128 px, dont une bande
imitant la barre des tâches) ; les `.ico` **réellement livrés** à côté de la simulation ;
le **menu du tray** réglable, qui écrit les valeurs exactes à recopier dans
`VigieMenuPalette` ; l'écran de chargement en direct.

### L'Atelier lit les valeurs livrées, il ne les recopie pas

Les couleurs du menu étaient **recopiées à la main** dans la page. Elles ont divergé : fond
bleuté `#2b3038` dans l'Atelier contre gris neutre `#2c2c2c` dans le tray. L'Atelier
affichait donc autre chose que ce qui est livré — et ne servait plus à valider quoi que ce
soit, ce que cette décision interdit précisément.

`apps/atelier/palette.php` lit désormais les constantes **dans `apps/tray/tray.ps1`** et la
page en part au chargement. Le bloc de code sous l'aperçu indique s'il est *identique au
livré* ou combien de valeurs ont été modifiées. Une recopie finit toujours par diverger ; la
seule correction qui tienne est de supprimer la recopie.

Corollaire **D15** : la couleur du libellé actif, écrite en dur à deux endroits de
`tray.ps1`, a été remontée dans `VigieMenuPalette.Text`. Ce qui n'a pas de définition unique
ne peut pas être lu à la source.

En cas d'échec de lecture (page ouverte en `file://`, constante disparue), la page **avertit
en jaune** au lieu de replier silencieusement sur ses valeurs écrites en dur : une valeur
fausse mais plausible se ferait valider sans qu'on voie le problème.

**Exigences tenues** (demande explicite de l'utilisateur) :

| Exigence | Réponse |
|---|---|
| Configuration à un seul endroit | `BindAddress`, `Port` et `StartPage` dans `apps/atelier/config/config.psd1` — la config de **cette** app. L'URL en dérive, aucune recopie (**D15**). |
| Outils de gestion | `-Status`, `-Stop`, `-Background`, `-NoBrowser`. Idempotent. Codes de retour distincts. |
| Documentation | `apps/atelier/README.md` : démarrage, commandes, configuration, périmètre, tableau de dépannage. |
| Aide intégrée | Aide basée sur les commentaires : `Get-Help ./apps/atelier/atelier.ps1 -Full`. |

**Périmètre** : écoute strictement locale, **aucun droit administrateur**, port distinct de
celui du serveur applicatif — les deux cohabitent. Il ne sert aucune API, n'exécute aucune
sonde, n'a accès à aucun secret.

**Règle** : la géométrie de la page est une **reproduction** du code. Toute modification doit
être faite en miroir dans le code ET ici, sinon l'atelier devient trompeur — c'est
précisément ce qu'il sert à éviter.

## D25 — Un redémarrage demandé n'est pas une panne

Le tray affichait **rouge** dès que le serveur devenait injoignable, y compris pendant un
redémarrage que l'utilisateur venait lui-même de demander. L'orange « démarrage » ne
s'appliquait qu'au tout premier lancement : une fois `EverUp` vrai, il ne revenait jamais.

Désormais l'état porte un drapeau `Starting`, remis à vrai par **tout** démarrage voulu, avec
une fenêtre de tolérance de 25 secondes :

- démarrage en cours, dans la fenêtre → **orange** « Démarrage… » ;
- démarrage en cours, fenêtre dépassée → **rouge** « Échec de démarrage » ;
- pas de démarrage en cours et injoignable → **rouge** « Arrêtée / injoignable ».

« Redémarrer le serveur » passe l'icône en orange **immédiatement**, sans attendre le sondage
suivant (8 s) qui affichait un rouge injustifié. Conforme à **D01** : trois états, et le rouge
reste réservé à un vrai problème.

## D26 — Coins du menu : découpe de région, pas DWM

**D19** arrondissait les coins du menu par DWM. Constaté à l'écran : ça ne fonctionne pas.
DWM n'arrondit pas les fenêtres **sans cadre standard**, ce qu'est un menu contextuel — le
menu restait à coins carrés alors que l'appel renvoyait pourtant `HRESULT 0`.

`Set-RoundedRegion` (dans `lib/common.ps1`) découpe le contrôle en rectangle arrondi : ça
s'applique **toujours**. L'appel DWM est conservé avant, sans dommage s'il est ignoré.
Contrepartie assumée : bords sans anticrénelage et ombre coupée au tracé.

Rayon dans `VigieMenuPalette.MenuRadius` (8 px), distinct de `CornerRadius` qui est celui du
**rectangle de survol** (5 px) — les deux étaient confondus dans le commentaire d'origine.

**Leçon** : un `HRESULT 0` prouve que l'appel a été **accepté**, pas qu'il a **produit** un
effet. Ce n'était donc pas une validation suffisante.

## D27 — Jauge pleine : surface unie, sans graduations

À l'état **conforme**, l'arc plein recouvre les graduations : la jauge est une **surface
unie**. C'est **volontaire et validé**. Les graduations réapparaissent dès que la jauge
n'est plus pleine, c'est-à-dire dès qu'il y a quelque chose à regarder.

Conséquence de **D23** (fraction portée à `1.00`) : l'arc de valeur est dessiné **après**
les graduations, donc il les masque. À `0.88` il en restait une visible ; à `1.00`, aucune.

L'ordre de dessin reste donc : anneau → piste → **graduations** → arc de valeur → aiguille
→ moyeu → point blanc. **Ne pas le réordonner** pour « récupérer » les graduations : elles
sont sous l'arc par construction, et c'est le rendu retenu.

Ceci **précise D01** sans l'annuler : les graduations restent au dessin (7 traits, mêmes
paramètres), simplement invisibles quand la jauge est pleine.

## D28 — Deux briques, deux noms : **Vigie** et **Atelier**

L'application et l'outil de développement ne doivent **jamais** être confondus, ni dans le
code, ni dans la documentation, ni dans les conversations.

|  | **Vigie** | **Atelier** |
|---|---|---|
| Nature | l'**application** livrée | **outil de développement** interne |
| Serveur | **PowerShell + Pode** | **PHP** (`php -S`) |
| Port | **47600** | **47610** |
| Élévation | **oui** (`RunLevel Highest`) | **non**, jamais |
| Lancement | tâche planifiée `Vigie` à l'ouverture de session | à la main, `apps/atelier/atelier.cmd` |
| Code | `apps/backend-pode/`, `apps/frontend-web/`, `apps/tray/` | `apps/atelier/` |
| Sondes, actions, secrets | oui | **aucun accès** |
| Doit tourner pour l'utilisateur final | oui | non |

**PHP est cantonné à l'outillage** et n'entre pas dans l'application. Trois raisons
mesurées, pas des préférences :

1. **Élévation** — le verrouillage Windows Update pose des ACL (`icacls`/`takeown`),
   désactive des tâches et écrit dans `HKLM`. Ce qui sert l'API doit être élevé ; un
   serveur HTTP en administrateur est une surface d'attaque bien plus large.
2. **Concurrence** — `php -S` traite **une requête à la fois** (mesuré : 2 s seule,
   4,0 s à deux). L'interface rafraîchit carte par carte et interroge en boucle.
3. **Coût des processus** — un `pwsh` froid coûte **~350 ms**. À 12 sondes, un appel par
   sonde ferait **~4,2 s** de pur démarrage par rafraîchissement complet ; aujourd'hui
   `/health` répond en **65 ms** dans un runtime déjà chaud.

Documenté dans `README.md`, `docs/REPRISE.md` et `apps/atelier/README.md`.

**Règle de travail associée** : en cas de doute sur l'appartenance d'un composant à l'une ou
l'autre brique, **demander à l'utilisateur avec une suggestion** plutôt que de trancher seul.

## D29 — Le dépôt contient plusieurs apps : `apps/` + `scripts/`

L'Atelier n'est pas un « outil » rangé dans `docs/` : c'est **une app du projet**, même si
elle ne sert qu'au développement. Le tray non plus n'est pas un morceau du backend : il a
son interface, ses icônes et son cycle de vie propres.

```
api/                 contrat REST partagé
apps/
  backend/           serveur Pode, sondes, actions, workers, lib, config
  frontend/          interface web
  tray/              app barre système : tray.ps1 + assets/ (icônes + générateur)
  atelier/           app de développement : serveur php, page, sa config
scripts/             install, désinstall, run, migration
docs/                documentation transverse
logs/                journaux communs à toutes les apps
```

**Un dossier par app, un dossier par rôle.** `scripts/` sort les scripts de gestion du code
applicatif : installer, désinstaller, lancer et migrer ne sont pas des fonctions du backend.

### Règles qui en découlent

- **Chaque app est maîtresse de sa config.** L'Atelier a `apps/atelier/config/config.psd1` ; le
  backend garde `apps/backend-pode/config/config.psd1`. Cela **précise D15** : « une valeur, une
  définition » ne veut pas dire « un fichier pour toutes les valeurs ». `AtelierPort` a
  quitté la config du backend.
- **L'Atelier ne dépend pas de la bibliothèque du backend.** Il ne dot-source plus
  `common.ps1` : une app de développement qui s'appuie sur l'app livrée, c'est la frontière
  de **D28** percée dès le premier jour.
- **Le tray pilote le backend sans en faire partie.** Il résout `apps/backend-pode` comme une app
  **sœur** et ne garde que deux liens vers elle : la bibliothèque partagée et le démarrage
  du serveur.
- **Les chemins inter-apps sont calculés à un seul endroit** : `Get-RepoRoot`,
  `Get-AppsRoot`, `Get-AppPath` dans `apps/backend-pode/lib/common.ps1`. Aucun script ne
  recompose un chemin inter-apps à la main.
- **Les journaux sont communs**, à la racine : le serveur et le tray sont deux apps, mais on
  ne fait pas chercher l'utilisateur à deux endroits.

### Ce qui n'a pas bougé, et pourquoi

`backend` et `frontend` sont restés **voisins** sous `apps/`. Les quatre endroits qui
calculaient « dossier parent + `frontend` » (dont `server.ps1` et `Get-AppVersion`)
fonctionnent donc **sans une ligne de modification**. Les lanceurs `.cmd`/`.vbs` utilisent
`%~dp0` : ils trouvent leurs voisins dans `scripts/`.

### Question tranchée depuis

L'emplacement du contrat et le nommage des apps sont réglés par **D30**.

### Migration réalisée

Déplacements en `git mv` (historique préservé). Points à ne pas oublier lors d'un
déplacement analogue : les fichiers **ignorés par git** (`var/secrets/`, `var/cache/`,
`config.local.psd1`, `apps/*/var/log/`) ne suivent pas et se déplacent à la main, et la **tâche
planifiée** porte un chemin absolu — elle doit être réenregistrée, sans quoi l'app ne
démarre plus à l'ouverture de session.

## D30 — Les apps portent leur techno ; le contrat appartient au backend

### Nommage

| Dossier | Techno | Pourquoi ce suffixe |
|---|---|---|
| `apps/backend-pode` | PowerShell + **Pode** | implémentation **remplaçable** du contrat |
| `apps/frontend-web` | HTML/CSS/JS, sans framework ni build | idem, côté client |
| `apps/tray` | WinForms | **pas de suffixe** |
| `apps/atelier` | PHP | **pas de suffixe** |

Le suffixe rend visible le principe directeur n°1 : le back et le front ne sont que des
**implémentations** du contrat. Un dossier `frontend` ne dit rien ; `frontend-web` annonce
qu'un autre pourrait exister à côté.

**Le tray et l'Atelier n'en portent pas**, et c'est délibéré : le suffixe signifie
« implémentation interchangeable d'un contrat ». Ces deux-là n'implémentent aucun contrat
et n'auront pas d'alternative ; un `tray-winforms` promettrait un échange qui n'arrivera pas.

### Les noms ne vivent qu'à un seul endroit

`Get-AppPath -Role 'backend'|'frontend'|'tray'|'atelier'` traduit un **rôle** en **dossier**.
Le code demande un rôle et ne connaît jamais le nom du dossier : renommer une implémentation
ne touche qu'une ligne de `common.ps1`.

**Exception inévitable : le bootstrap.** Un script qui doit *charger* `common.ps1` ne peut
pas encore appeler `Get-AppPath` — il faut savoir où est la bibliothèque avant de s'en
servir. Le nom `backend-pode` figure donc en clair dans `tray.ps1` et `scripts/*.ps1`,
chaque fois signalé par un commentaire `BOOTSTRAP`.

### Le contrat

`api/openapi.yaml` → **`apps/backend-pode/api/openapi.yaml`**. Le contrat est fourni par le
backend, qui l'implémente et le publie.

**Réserve consignée** : avec plusieurs backends, chacun décrirait le sien, et deux
descriptions finissent toujours par diverger. Si un second backend apparaît, il faudra soit
désigner un contrat de référence, soit vérifier automatiquement que les implémentations
restent conformes. Ce n'est pas un problème aujourd'hui : il n'y a qu'un backend.

## D31 — La documentation est maintenue **en toute circonstance**

Une doc qui ment est pire qu'une doc absente : on la croit.

**Règle** : aucun état intermédiaire ne doit laisser un document affirmer le contraire de
la réalité. Si un changement rend une phrase fausse, elle est corrigée **dans le même
commit**, pas « plus tard ».

**Ce qui a déclenché cette règle** (manquements réels, à ne pas reproduire) :

- `docs/MIGRATION-APPS.md` a porté un avertissement « ⛔ ne pas fusionner » **après** que la
  fusion ait eu lieu. Lu tel quel, il aurait fait renoncer à une action déjà faite.
- **D29** et la note de migration ont gardé une section « question laissée ouverte » sur
  l'emplacement du contrat alors que **D30** l'avait tranchée.
- La section « Configuration » de l'Atelier décrivait encore une clé `AtelierPort` déplacée
  depuis.

**En pratique** :

1. Un renommage ou un déplacement se propage **dans le même commit** : code, doc, décisions.
2. Les fichiers **sans extension** (`.gitignore`, `.cmd`…) sont vérifiés à part : un
   remplacement filtré par extension les rate. C'est exactement ce qui a laissé passer
   `config.local.psd1` dans git.
3. Une décision remplacée n'est pas réécrite : la nouvelle indique celle qu'elle remplace,
   et l'ancienne renvoie vers la nouvelle. L'historique reste lisible, sans contradiction.
4. Un document de transition (note de reprise) décrit l'état **courant**, jamais l'état
   souhaité au moment où il a été écrit.
5. `CHANGELOG.md` fait exception aux propagations de chemins : ses entrées datées
   décrivent une réalité vraie à l'époque. On y ajoute, on n'y réécrit pas.

## D32 — Pas de dossier `_to_delete/` dans le projet

**Aucun dossier `_to_delete/` ne doit exister dans le projet versionné.** Ce qui est mort se
supprime ; git conserve l'historique, c'est son rôle. Une « corbeille » dans le dépôt est
du bruit qui survit toujours plus longtemps que prévu.

À l'application de cette décision : vérifié qu'il n'était **ni suivi, ni présent sur le
disque, ni dans aucun commit de l'historique**.

La règle `_to_delete/` a été **retirée de `.gitignore`**, et c'est délibéré : l'ignorer
revenait à tolérer la pratique en silence. Sans cette règle, un tel dossier apparaît dans
`git status` et se fait remarquer.

*(Origine : l'environnement d'édition d'origine ne pouvait pas supprimer de fichiers et les
déplaçait dans cette corbeille. Cette contrainte n'existe plus.)*

## D33 — `var/` par app, `config/` par app, `config/` commun à la racine

Convention **Symfony**, appliquée telle quelle.

### `var/` — tout ce que l'app génère ou gère en local

```
apps/<app>/var/
  cache/     état calculé : state-cache.json, netmeasure.json, pkgupdates.json
  log/       journaux de l'app
  secrets/   secrets GÉNÉRÉS à l'exécution : api.token
```

Pas seulement le cache : **tout** fichier temporaire, téléversé, ou local géré par l'app.
Remplace `.state/`, `.secrets/` et le `logs/` commun à la racine.

**Chaque app a son `var/`**, y compris le tray, qui écrit désormais dans
`apps/tray/var/log/`. L'entrée « Ouvrir les journaux » du menu continue d'ouvrir ceux du
**serveur** : c'est ce qu'on veut voir pour diagnostiquer.

Le jeton d'API est dans `var/secrets/` et non dans `config/` : il est **généré par l'app**,
pas rédigé par un humain. C'est une donnée d'exécution.

### `config/` — ce qui est rédigé

```
config/common.psd1                     valeurs partagées par plusieurs apps
apps/<app>/config/config.psd1          config propre à l'app (versionnée)
apps/<app>/config/config.local.psd1    surcharge machine (ignorée par git)
apps/<app>/config/config.local.sample.psd1   le modèle (versionné)
```

**Fusion en trois couches**, de la plus générale à la plus spécifique : commune → app →
locale. La plus spécifique gagne.

`BindAddress` était **recopiée** dans les deux apps : elle vit maintenant dans
`config/common.psd1`, avec la plage de ports du projet. Chaque app y choisit **son** port,
dans sa propre config — Vigie 47600, Atelier 47610.

L'Atelier lit la config commune sans que cela contredise **D29** : lire un fichier de
config partagé n'est pas dépendre d'une **app**. Il ne charge toujours pas `common.ps1`.

### Dette remboursée au passage

Le chemin `.state\` était **recomposé à la main dans 8 fichiers** (actions, sondes,
workers, `common.ps1`). Tous passent désormais par
`Get-VarPath -Kind cache|log|secrets [-File <nom>]`, qui crée le dossier au besoin.
Le chemin n'est écrit qu'**une fois**, conformément à **D15**.

### `.gitignore`

`apps/*/var/` couvre d'un coup cache, journaux, état et secrets générés ; plus besoin
d'énumérer. `apps/*/config/config.local.psd1` reste ignoré, son `.sample` versionné.

## D34 — L'Atelier filtre ce qu'il sert

**Défaut trouvé en testant** : l'Atelier sert la **racine du dépôt** — il lui faut des
fichiers de plusieurs apps (icônes du tray, frontend, contrat). Sans filtre, il exposait
donc aussi `apps/backend-pode/var/secrets/api.token`, **le jeton de l'API de Vigie**,
téléchargeable en HTTP.

`apps/atelier/router.php` refuse désormais, quel que soit le chemin :

| Refusé | Pourquoi |
|---|---|
| `var/` | données d'exécution : cache, journaux, **secrets générés** |
| `config/` | configurations, dont les surcharges machine |
| tout élément commençant par `.` | `.git`, `.gitignore`… |
| `.psd1`, `.log`, `.token` | par extension, où qu'ils soient |

**Liste de REFUS, pas d'autorisation** : une liste d'autorisation casserait dès qu'on
ajoute une ressource à la page, et la tentation serait de l'élargir jusqu'à ne plus rien
filtrer.

Les antislashs sont normalisés avant le test : sous Windows, un chemin écrit avec des
antislashs atteindrait le même fichier en contournant un motif qui ne testerait que les
slashs.

**`atelier.ps1` REFUSE de démarrer si `router.php` est absent.** Un filtre de sécurité
qu'on peut désactiver en supprimant un fichier n'en est pas un.

**Vérifié réellement** : jeton, cache, configs et `.gitignore` en **403** ; les 5
ressources légitimes en **200** ; et trois contournements (traversée `../`, encodage
`%2F`, double slash) tous en **403**.

**Portée du défaut** : l'Atelier écoute uniquement en local et ne tourne qu'à la demande,
donc l'exposition restait limitée aux processus de la machine — qui peuvent de toute façon
lire le fichier sur disque. Ce n'en était pas moins une fuite gratuite, et corrigée.

## D35 — Les réglages d'IDE ne sont pas versionnés

`.idea/`, `.vscode/` et `*.code-workspace` sont ignorés **en entier**.

PhpStorm dépose lui-même un `.idea/.gitignore` qui exclut le volatil et le sensible
(`workspace.xml`, `dataSources*` — là où atterriraient des identifiants de base de
données). Git ne voyait donc que `vcs.xml` et ce `.gitignore`, tous deux inoffensifs :
vérifié, aucun mot de passe, jeton ni chemin machine.

On ignore malgré tout le dossier entier : l'IDE ne sert pas à éditer ce projet, et des
réglages d'éditeur versionnés finissent toujours par diverger d'un poste à l'autre.

Si un jour la config IDE doit être partagée, le sous-ensemble à versionner serait
`vcs.xml`, `modules.xml`, `*.iml` et `misc.xml` — **jamais** `workspace.xml` ni
`dataSources*`.

*(Note : `.claude/worktrees/` est exclu par `.git/info/exclude`, un mécanisme local au
dépôt et non versionné. C'est voulu : c'est de l'outillage propre à cette machine.)*

## D36 — Le contenu de fichier s'écrit avec l'outil d'édition, pas à travers un shell

**Défaut réel** : D34 et D35 ont été écrites en faisant passer du texte français dans une
here-string PowerShell. PowerShell y traite l'accent grave comme caractère d'échappement :
`` `a `` et `` `v `` ont été **avalés**, `` `r `` est devenu un retour chariot. Résultat :
« `apps/...` » affichait « pps/... », « `var/` » affichait « ar/ », et toutes les
apostrophes étaient doublées. Le texte était faux **et** illisible — dans le fichier censé
faire autorité sur les décisions du projet.

**Règle** : tout contenu de fichier — documentation, code, markdown accentué — s'écrit avec
l'**outil d'édition** (écriture / remplacement exact), qui transmet le contenu tel quel.
Aucune couche shell entre le texte et le fichier.

Un shell ajoute au moins une passe d'interprétation : guillemets, accent grave, `$`, `%`,
antislash. Chaque couche est une occasion de corrompre silencieusement. Ici il y en avait
deux (PowerShell, puis Python), et c'est exactement ce qui est arrivé.

**Ce à quoi servent les shells** : exécuter, mesurer, valider, inspecter. Pas à produire du
contenu.

Reste acceptable pour du texte **strictement ASCII et sans métacaractère** : un `sed`
ponctuel, un ajout de ligne. Au moindre accent ou backtick, on passe par l'outil d'édition.

**Vérification après écriture de doc** : chercher `''` (apostrophes doublées) et les
backticks manquants autour des chemins. Voir **D31** — une doc fausse est pire qu'une doc
absente, et celle-ci l'était.

## D37 — Chaque taille d'icône est dessinée à sa résolution

**Défaut** : le générateur dessinait **une seule fois à 256 px** et laissait Pillow réduire
vers chaque taille. À 16 px, l'anneau fin et l'arc épais fusionnaient en une pastille
illisible. Un détail conçu pour 256 px ne survit pas à une réduction en 16 — c'est déjà ce
qui avait fait supprimer les graduations le 21/08, en traitant le symptôme.

Désormais chaque taille est **dessinée à sa propre résolution** (supersampling ×8 puis
réduction), et le `.ico` embarque ces dessins-là via `append_images`, pas des réductions.

### Niveaux de détail

| Élément | Dessiné à partir de | Pourquoi |
|---|---|---|
| Anneau extérieur | 48 px | trait très fin, devient un halo flou en dessous |
| Graduations | 64 px | déjà sous l'arc plein (**D27**), pur parasite en petit |
| Liseré de l'aiguille | 32 px | ferait moins d'un pixel en dessous |

Les traits s'épaississent à mesure que l'icône rétrécit : `arc` de 0,110 à 0,150, `needle`
de 0,082 à 0,115. On retire chaque élément **avant** qu'il ne devienne du bruit, plutôt que
de le laisser se transformer en tache.

### Piège Pillow, corrigé

`ImageDraw.arc(..., width=w)` épaissit le trait **vers l'intérieur** du rectangle
englobant : un rectangle de rayon `r` donne un trait sur `[r-w, r]`, d'axe `r-w/2`. SVG,
lui, centre le trait **sur** le tracé, soit `[r-w/2, r+w/2]`.

Conséquences observées : l'arc du `.ico` était décalé vers l'intérieur d'une demi-épaisseur
— donc plus petit que la simulation à géométrie pourtant identique — et les disques simulant
les extrémités arrondies, centrés sur `r`, dépassaient en formant des bosses visibles.

**Correction** : le rectangle est élargi à `r + w/2`. Le trait retombe centré sur `r`, et le
`.ico` coïncide enfin avec la simulation de l'Atelier.

### Miroir obligatoire

Les seuils et épaisseurs existent **à deux endroits** : `apps/tray/assets/generate-icons.py`
et la simulation de `apps/atelier/index.html`. Ils doivent changer ensemble — sinon
l'Atelier montre autre chose que ce que Windows affiche, et il ne sert plus à rien (**D24**).

## D38 — Le mode dégradé de l'icône est un disque, pas une imitation

`setIcon` charge le `.ico` livré. En cas d'échec, l'ancien repli **redessinait la jauge en
GDI+** : un second dessin de la même marque, qui avait fini par **diverger** — aiguille
partant du centre au lieu du talon, aucune graduation, épaisseurs et couleur de piste
différentes. C'était le design d'avant que **D01** ne rétablisse graduations et talon.

Pire : l'échec de lecture était avalé par un `catch` vide. Le tray pouvait donc afficher une
**autre marque** sans que personne ne le remarque.

Le repli est désormais un **simple disque de la couleur du statut**. Il ne cherche pas à
ressembler à la marque : il signale que les assets manquent, tout en conservant
l'information utile (la couleur). Personne ne le prendra pour l'icône réelle.

Tout échec — fichier absent ou illisible — est **journalisé**. Une icône qui change sans
raison est indiagnosticable si la cause n'est pas tracée.

Corollaire **D15** : il n'existe plus qu'**une seule** représentation de la marque, le
`.ico` généré. Deux dessins de la même chose finissent toujours par diverger ; celui-ci
avait déjà divergé.

## D39 — Les détails techniques se tranchent, ils ne se demandent pas

**Le silence de l'utilisateur vaut accord.** Sur un détail technique, s'il ne dit rien,
c'est qu'il n'a rien à dire : on décide et on avance. S'il a une décision technique à
préciser, il en fait part de lui-même.

Ne demander d'arbitrage que lorsque le choix est **produit** — comportement visible, parti
pris d'interface, priorité — et qu'aucune règle déjà consignée ne permet de le déduire.
Un choix d'implémentation, un nom interne, une structure de code se tranchent.

En cas de doute, la bonne posture est : **décider, annoncer la décision et sa raison, et
indiquer qu'elle est réversible**. Pas attendre.

### Quand on pose une question, elle doit être identifiable

Format obligatoire, sinon elle n'est pas vue :

- numérotée `Q1`, `Q2`… — numéros uniques tant que les questions sont ouvertes,
  réutilisables une fois répondues ;
- réponses fermées en **A**, **B**, **C**, une ligne chacune, la recommandation en premier ;
- dans un **bloc identifiable**, jamais diluée dans un paragraphe de fin de message.

**Manquement à ne pas reproduire** : le sort du repli GDI+ de l'icône a été « posé » deux
fois sous forme de suggestions en prose, en clôture de longs messages. L'utilisateur n'a vu
**aucune question** — et il avait raison, ce n'en étaient pas. C'était de surcroît un détail
technique, qui relevait de la décision et non de l'arbitrage.

### Un rapport, c'est une phrase par sujet

**Règle** : un compte rendu se lit d'un coup d'œil. Une ligne par sujet traité, verdict en
premier. Pas de récit de l'enquête, pas de justification de la méthode, pas de rappel de ce
qui a déjà été dit.

Le détail — cause, mesure, raisonnement — va dans le **dépôt** : décision, commentaire de
code, ou entrée de `docs/REPRISE.md`. C'est là qu'il survit et qu'on le retrouve ; dans un
message, il se lit une fois puis se perd.

Une phrase de plus n'est justifiée que si elle change une décision de l'utilisateur : un
défaut encore ouvert, une vérification qui n'a pas pu être faite, une action attendue de lui.

## D40 — Les droits de l'agent sont un fichier du dépôt, pas un réglage de session

Les demandes de permission incessantes venaient de règles **par motif de commande**
(`Bash(git *)`) : elles ne couvrent que les commandes **analysables statiquement**. Dès
qu'une commande contient une boucle, une substitution `$(...)` ou un test `[ ]`, l'analyse
échoue et la permission est redemandée — alors que la même commande écrite simplement
passerait. Allonger la liste de motifs ne corrige rien : le défaut est dans le grain de la
règle, pas dans la liste.

La règle retenue est **au niveau de l'outil** — `"Bash"`, `"PowerShell"`, sans parenthèses —
dans [`.claude/settings.json`](../.claude/settings.json), **versionné**. Elle couvre toutes
les commandes, analysables ou non. Rien à maintenir.

### Tentative abandonnée : un hook qui juge le texte de la commande

Une première version branchait un script PowerShell sur l'évènement `PreToolUse` : il
autorisait par défaut et redemandait sur une liste de motifs destructeurs (`rm -rf`,
`push --force`, `format`, `shutdown`…). **Retirée après deux faux positifs immédiats** :

- `Get-ScheduledTask … | Format-List` bloqué sur le motif `format` ;
- `grep -n "format|diskpart"` bloqué en **cherchant** le motif dans le script lui-même.

La cause n'est pas une frontière de mot mal écrite. Un hook ne voit que le **texte** d'une
commande, jamais son effet : toute liste de mots-clés bloque aussi les commandes qui se
contentent de **mentionner** le mot. Corriger un motif déplace le problème au suivant, et
chaque faux positif est exactement la nuisance qu'on voulait supprimer.

S'ajoutait un coût permanent : un démarrage de `pwsh` (~1 s) **avant chaque commande**.

Ce dépôt est local, mono-utilisateur et entièrement poussé sur GitHub : le filet de sécurité
réel est l'**historique git**, pas une liste de mots.

Corollaire pratique : une modification de `.claude/settings.json` ne prend effet qu'au
**redémarrage de la session** — l'agent ne relit pas un réglage apparu en cours de route.

Ce qui reste hors du dépôt est local par nature : `.claude/settings.local.json` (réglages de
poste) et `.claude/worktrees/` (arbres de travail), tous deux ignorés.

## D41 — Le code est en anglais ; le français est la langue de l'écrit

**Deux registres, une frontière nette :**

| En anglais | En français |
|---|---|
| noms de fichiers de code, identifiants, fonctions, paramètres | documentation (`docs/`, `README.md`, `CHANGELOG.md`, `SUIVI.md`) |
| valeurs techniques, clés de configuration | échanges avec l'utilisateur |
| | libellés affichés à l'utilisateur (interface, messages) |

**Langages** : PowerShell pour les outils **Windows** — c'est sa raison d'être ici. Pour tout
le reste, **PHP** (l'Atelier l'utilise déjà). Pas de troisième langage sans argument.

Renommages appliqués :

| Avant | Après |
|---|---|
| `scripts/installer-hooks.ps1` | `scripts/install-hooks.ps1` |
| `scripts/demarrer-vigie.vbs` | `scripts/start-vigie.vbs` |
| `apps/tray/assets/generer-icones.py` | `apps/tray/assets/generate-icons.py` |

**Exceptions** : `vigie` et `atelier` sont des **noms propres** — un nom de produit ne se
traduit pas. `docs/maquettes-validees/` reste intact (**D05** : on ne réécrit pas l'archive
des supports de décision), de même que les entrées historiques de `CHANGELOG.md` et
`SUIVI.md`, qui consignent des faits datés.

**Reste à faire** : les commentaires internes des scripts sont encore en français. Ils
portent le raisonnement derrière chaque choix — les traduire est une passe à part entière,
à mener fichier par fichier, pas un `sed`.

## D42 — Fraction de la jauge à l'état erreur : `0.17` (remplace **D23** sur ce point)

- conforme : `1.00` — inchangé (**D23**) ; démarrage : `0.50` — inchangé ;
- **erreur : `0.17`** (au lieu de `0.14`).

La fraction n'est écrite qu'à **un seul** endroit,
[`apps/tray/assets/generate-icons.py`](../apps/tray/assets/generate-icons.py) — le repli GDI+
qui la dupliquait a été supprimé (**D38**). Les `.ico` ont été régénérés : `ok.ico` et
`warn.ico` sont ressortis **identiques à l'octet près**, ce qui confirme au passage que le
générateur est déterministe et que seul l'état erreur a bougé.

## D43 — On constate le résultat, on ne fait pas confiance au code de retour

**L'application ne s'ouvrait pas depuis le tray** — signalé **quatre fois** avant d'être
diagnostiqué. Pendant tout ce temps le journal affichait `openApp ok (fenetre dediee)`.

Deux défauts distincts, tous deux masqués par un succès apparent :

1. `Add-PodeRoute -Path '/'` chargeait `common.ps1` **après** avoir appelé `Get-AppPath`.
   Une route Pode s'exécute dans son **propre espace d'exécution** : rien de ce qui est
   chargé au démarrage du serveur n'y existe. La route levait donc
   *« Get-AppPath is not recognized »* et rendait **500** — le serveur répondait, mais la
   page n'existait pas. Toutes les autres routes chargeaient bien `common.ps1` en première
   ligne ; celle-là était la seule exception.
2. Le tray prenait le **premier** navigateur trouvé sur disque, Edge avant Chrome. Sur cette
   machine Edge est installé mais **ne démarre pas** : le processus sort en moins d'une
   seconde, sans fenêtre et sans erreur. `Start-Process` rendait la main sans exception, et
   le code écrivait « ok » sur cette seule base. « Ouvrir dans le navigateur » marchait,
   lui, parce qu'il passe par le navigateur **par défaut** — Chrome.

**Règle qui en découle** : un lancement, une écriture, un rendu ne sont pas « réussis »
parce que l'appel n'a pas levé d'exception. Le code doit **observer l'effet** avant de le
déclarer, et le journal doit rapporter ce qui a été observé, pas ce qui a été tenté.

Appliqué ici : le tray essaie d'abord le navigateur **par défaut** (celui dont on sait qu'il
fonctionne), vérifie **1,5 s plus tard** que le processus tient — ou que le navigateur a
gagné des processus, cas de la délégation à une instance déjà lancée — et passe au candidat
suivant sinon. En dernier recours il ouvre un onglet normal : mieux vaut une fenêtre
imparfaite que rien.

C'est le même défaut que le repli GDI+ de **D38** (échec avalé par un `catch` vide) et que
la vérification PowerShell qui ne validait aucun fichier tout en affichant « OK ».

**Reste ouvert** : `$stopServer` ne tue que le serveur lancé par l'instance **courante** du
tray. Après un redémarrage du tray, l'ancien serveur devient orphelin et `$startServer` sort
immédiatement puisque le port répond — le tray sert alors indéfiniment du code périmé. C'est
ce qui a fait croire, ce jour-là, que le correctif du 500 n'avait rien changé.

## D44 — Le cache d'état comparait des heures de fuseaux différents

Les dates du cache sont écrites en **UTC** (`ToUniversalTime().ToString('o')`) mais étaient
comparées à `Get-Date`, qui rend l'heure **locale**. Sur un poste à UTC+2, toute entrée
paraissait donc vieille de deux heures : **aucune n'a jamais été jugée fraîche**.

Conséquence mesurée : chaque appel à `/state` recalculait les **douze** sondes — environ
21 s, dont 10 s pour la seule sonde `lock`. Le cache, son TTL par sonde, son invalidation
par empreinte de code et son verrou anti-troupeau étaient tous corrects — et tous inutiles.
Après correction : **0,3 s** au lieu de 21 s.

La normalisation est faite en un seul endroit, `ConvertTo-UtcDate` : `ConvertFrom-Json`
rend tantôt une chaîne, tantôt un `[datetime]`, avec un `Kind` qui peut valoir `Utc`,
`Local` ou `Unspecified`. Comparer sans normaliser est un piège qui se represente à chaque
nouvelle lecture de date.

**Règle** : une date qui traverse un fichier se compare en UTC des deux côtés. Le seul
moyen de le vérifier est de **mesurer** l'âge obtenu, pas de relire le code — les deux
lignes fautives étaient chacune correcte prise isolément.

### Rafraîchir n'est pas recharger

Deux besoins distincts, désormais distingués dans le contrat :

- **chargement de la page** — `GET /state` : peut servir le cache, doit s'afficher vite ;
- **bouton « Rafraîchir »** — `GET /state?fresh=1` : **recalcule** les sondes (≈ 24 s,
  bouton désactivé et animé pendant l'opération).

Le bouton appelait la même route que le chargement : il rendait la main aussitôt en
réaffichant les mêmes valeurs, donc il ne rafraîchissait rien. `Get-State` acceptait déjà
`-Force` ; la route ne le passait simplement jamais.

## D45 — Installer les mises à jour Windows depuis Vigie, au choix

L'application ne savait qu'**ouvrir** Windows Update. Elle peut désormais **installer**, mais
jamais en bloc : l'utilisateur coche ce qu'il veut dans une fenêtre de choix.

Le parcours en deux temps, volontaire :

1. `wu-list-pending` — lecture seule, recherche **locale** (`Online = $false`, comme la
   sonde) : renvoie titre, KB, taille et un identifiant stable par mise à jour ;
2. `wu-install` — reçoit les identifiants **retenus** et lance un worker détaché.

Une liste vide est **refusée** plutôt qu'interprétée comme « tout ». Le verrou du Mode MAJ
est détecté **avant** de lancer quoi que ce soit : le dire coûte une seconde, le découvrir
après dix minutes d'installation ratée coûte la confiance.

**Détaché, donc increvable** : une installation dure des minutes. Portée par la requête
HTTP, une fermeture d'onglet l'interromprait en plein téléchargement. Ici le navigateur peut
disparaître, l'installation continue, et la carte reprend son état à la reconnexion.

Le résultat rapporté est celui **constaté** — code de retour de `Install()`, réussite
partielle (code 3) distinguée de la réussite, redémarrage requis signalé (**D43**).

### Quatrième type d'action : `dialog`

Trois types ne suffisaient plus, et deux se ressemblaient trop à l'écran :

| Type | Icône | Sens |
|---|---|---|
| `immediate` | triangle « lecture » gris | part tout de suite |
| `confirm` | **triangle d'avertissement orange** | demande un oui/non |
| `dialog` | liste cochée bleue | ouvre une fenêtre de **choix** dans l'application |
| `manual` | flèche sortante bleue | ouvre un **logiciel externe** |

L'icône de `confirm` était un rectangle de fenêtre depuis l'import initial : il se lisait
comme une case vide, pas comme une mise en garde.

**Manquement à ne pas reproduire** : cette fonction a été demandée **cinq fois** avant
d'être faite. Une demande répétée qui reste sans réponse n'est pas une demande de moindre
priorité — c'est la plus urgente.

## D46 — Les deux liserés ne disent pas la même chose

Ils ont été confondus, puis intervertis. Ils sont distincts et le restent :

| Élément | Emplacement | Ce qu'il porte |
|---|---|---|
| `.modebar` | bande horizontale **sous l'en-tête** | statut de l'**application** (en ligne / maquette / erreur) |
| `.card` | liseré **à gauche** de chaque carte | statut de **ce module** |

Le liseré de carte reste **à gauche** — il avait été déplacé en haut par erreur, sur une
confusion avec la barre de l'application.

**L'état « en cours » vit dans le même liseré**, en clignotant vers la couleur d'accent.
Il était auparavant rendu par un **halo** autour de la carte : deux signaux séparés pour une
même chose, et un halo se lit comme une alerte. Une carte a un seul endroit où dire son
état. *(Validé à l'œil par l'utilisateur.)*

## D47 — Ne jamais ouvrir le front en `file://`

Éditer `apps/frontend-web/index.html` avec l'outil d'édition de l'agent déclenche l'aperçu
automatique du panneau navigateur : il charge le fichier en `file://`, **vole le focus** et
affiche une copie qui n'est pas celle que sert le back — sans jeton d'API, donc sans données.

Deux règles en découlent :

1. **Toute vérification passe par un serveur** : `http://127.0.0.1:47600` pour l'application,
   `http://127.0.0.1:47610` pour l'Atelier. Jamais un chemin de fichier.
2. **Les fichiers du front se modifient par script** (remplacement exact en Python), pas avec
   l'outil d'édition — c'est ce qui déclenche l'aperçu. Vérifié : une modification par
   script ne l'a jamais déclenché.

Pistes essayées pour désactiver l'aperçu, **sans succès à ce jour** :

- fermer le panneau navigateur : l'aperçu le **rouvre** ;
- `disableAllHooks: true` dans `.claude/settings.json` : sans effet dans la session en
  cours. Le réglage est conservé — il n'y a aucun autre hook dans ce projet — et reste à
  vérifier après un redémarrage de session ;
- aucun fichier de hook n'existe sur disque : l'aperçu est intégré au panneau, pas
  configurable par le dépôt.

Contrepartie assumée : une couche de script a déjà cassé des chaînes JavaScript
(apostrophes, `\n`). Elle impose donc son garde-fou — recherche des chaînes monoquotes
non terminées — **et** un rechargement de la page servie avant d'annoncer quoi que ce soit.
`docs/DECISIONS-VALIDEES.md` garde la règle inverse (**D36**) : lui s'écrit avec l'outil
d'édition, car une couche shell l'avait corrompu.

## D48 — Gestion des modules : un panneau latéral, deux portes d'entrée

**Forme retenue** : un **panneau latéral large** (~520 px), même mécanique que le tiroir des
notifications. Il présente la **liste des modules** ; en choisir un ouvre sa **configuration
dans le même panneau** (liste → détail). Écartés : la vue plein écran (routage à inventer
pour un besoin de réglage) et la modale par carte (trop étroite pour de la configuration).

**Deux portes d'entrée, et il en faut bien deux :**

1. **Un menu de gestion dédié**, indépendant des cartes. Indispensable : un module désactivé
   n'a **pas de carte**, donc aucune carte ne peut y mener. Sans cette entrée, un module
   désactivé serait irrécupérable depuis l'interface.
2. **Un menu par carte** (bouton ⋮ / ☰) qui ouvre directement la configuration **de ce
   module**. Raccourci, jamais l'unique chemin.

### Ce qui reste à étudier avant d'écrire une ligne

Le découpage est le vrai sujet. Le contrat ne connaît que deux niveaux — `theme` (le groupe
affiché) et `module` (une carte) — alors qu'un module au sens de l'utilisateur produit
**plusieurs cartes** : « Windows Update » en donne trois (historique, verrouillage, mises à
jour en attente). Il recouvre à peu près un thème, mais pas exactement. Le niveau qui
manque est l'**unité fonctionnelle** : ce qu'on active, désactive et configure, distinct de
la carte qui l'affiche.

Questions ouvertes, à trancher avant l'implémentation :

- troisième niveau dans le contrat (`unit` / `feature`) possédant ses cartes, ou `theme`
  enrichi devenant cette unité ?
- une sonde = une carte aujourd'hui ; si l'unité regroupe des sondes, qui porte
  l'activation : le fichier de sonde, ou une déclaration séparée ?
- où vit la configuration d'un module : le `config.psd1` du backend, ou un fichier par
  module sous `apps/backend-pode/config/modules/` ?
- un module désactivé disparaît-il de `/state`, ou y figure-t-il avec un drapeau ? Le
  premier est plus simple ; le second permet de le réactiver depuis le panneau sans
  connaître la liste des modules possibles.
