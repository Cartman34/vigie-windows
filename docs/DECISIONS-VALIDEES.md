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

- Générée à l'identique de **D01** par `backend/assets/tray/generer-icones.py` (PIL)
  → `ok.ico` / `warn.ico` / `error.ico` (multi-résolutions 16→256).
- Chargées par `tray.ps1` (fonction `setIcon`), avec repli sur le dessin GDI+ si un fichier manque.

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
| Titre `api/openapi.yaml` « HYPERION Control Panel API » | « Vigie API » |
| `backend/demarrer-hyperion.vbs` | `backend/demarrer-vigie.vbs` |

**Exception** : `docs/maquettes-validees/` n'est pas retouché — c'est l'archive des supports
de décision, on n'y réécrit pas l'histoire.

## D06 — Validation du JS du front : navigateur, pas Node

**Node n'est pas installé** sur la machine et **n'est pas ajouté** : le projet n'a aucune
dépendance JS (pas de `package.json`, pas de build, un seul fichier HTML servi tel quel) ;
installer un runtime permanent pour une seule vérification syntaxique n'est pas justifié.

Validation retenue : charger `frontend/index.html` en `file://` dans un navigateur et lire
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
- Outil : `backend/uninstall-legacy.ps1` (voir **D11**) retire la tâche et le raccourci hérités
  et met l'ancien dossier de côté. `backend/install-autostart.ps1` enregistre la tâche courante.
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

Arbitrage retenu : `backend/uninstall-autostart.ps1` ne connaît **que** les noms courants,
et un script **dédié et jetable**, `backend/uninstall-legacy.ps1`, porte seul les anciens noms.
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

`backend/config.psd1` est **versionné et générique** : il porte LA définition de chaque
valeur et ne contient plus rien de propre à une machine. `ToolsPath` y vaut `''`.

`backend/config.local.psd1` est **ignoré par git**, optionnel, et surcharge les seules
valeurs qui ne peuvent pas être génériques (chemins d'une machine donnée).
`backend/config.local.sample.psd1` est le modèle versionné qui documente ce qu'on peut
y surcharger. `Get-Config` fusionne les deux, et **échoue avec un message explicite**
si le fichier local est illisible.

Toute valeur dérivée est calculée à UN endroit (**D15**), dans `lib/common.ps1` :
`Get-AppUrl`, `Get-ApiUrl`, `Get-ToolsPath`, `Get-AdminRoot`, et la réponse commune
`New-ToolsMissingResult`. Plus aucune URL ni port en dur ailleurs dans le code.

L'outillage externe est **optionnel** : `ToolsPath` vide ou introuvable → les six actions
qui en dépendent rendent un message clair au lieu d'échouer obscurément. Un clone neuf
fonctionne donc sans configuration, avec ces actions désactivées.

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
Il tient donc en **une seule ligne**, en tête de `backend/probes/wsl/wsl.probe.ps1`, sous un
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

`api/openapi.yaml` déclarait `enum: [ok, warn, error]` pour le statut d'un module, alors que
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

Toute la géométrie de **D01** est conservée : seules les fractions changent. La valeur est
écrite à **deux** endroits qui doivent rester identiques, faute de quoi le `.ico` et le repli
GDI+ divergeraient : `backend/assets/tray/generer-icones.py` et `backend/tray.ps1`.
Les `.ico` ont été **régénérés** (Pillow installé dans le scratchpad, pas dans le Python
de la machine).

Le générateur est renommé `generer-icones_B.py` → **`generer-icones.py`** : la lettre
d'option ne survit pas à la validation (**D04**).

## D24 — Un atelier de validation visuelle, **servi** et outillé

`docs/atelier-validation.html` — page de validation visuelle, **servie par un petit serveur
local** (`docs/atelier.ps1`, serveur intégré de PHP), pas ouverte en double-clic.

**Pourquoi un serveur** : ouverte en `file://`, la page ne peut pas faire son travail. Les
chemins relatifs vers les `.ico` cassent dès qu'on déplace le fichier (images cassées), et le
navigateur refuse d'afficher `frontend/index.html` dans un cadre (rectangle noir). Les deux
défauts ont été constatés en livrant la première version : **c'était une livraison
inutilisable**. Servie en `http`, la page fonctionne entièrement.

Elle reste ouvrable en `file://` mais **le dit** alors, au lieu d'afficher des cassures
silencieuses.

**Contenu** : la marque du tray avec un curseur de fraction (16 → 128 px, dont une bande
imitant la barre des tâches) ; les `.ico` **réellement livrés** à côté de la simulation ;
le **menu du tray** réglable, qui écrit les valeurs exactes à recopier dans
`VigieMenuPalette` ; l'écran de chargement en direct.

**Exigences tenues** (demande explicite de l'utilisateur) :

| Exigence | Réponse |
|---|---|
| Configuration à un seul endroit | `BindAddress` et `AtelierPort` dans `config.psd1`, lus via `Get-Config`. L'URL en dérive, aucune recopie (**D15**). |
| Outils de gestion | `-Status`, `-Stop`, `-Background`, `-NoBrowser`. Idempotent. Codes de retour distincts. |
| Documentation | `docs/atelier.md` : démarrage, commandes, configuration, périmètre, tableau de dépannage. |
| Aide intégrée | Aide basée sur les commentaires : `Get-Help .\docstelier.ps1 -Full`. |

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
| Lancement | tâche planifiée `Vigie` à l'ouverture de session | à la main, `docstelier.cmd` |
| Code | `backend/`, `frontend/` | `docs/atelier*` |
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

Documenté dans `README.md`, `docs/REPRISE.md` et `docs/atelier.md`.

**Règle de travail associée** : en cas de doute sur l'appartenance d'un composant à l'une ou
l'autre brique, **demander à l'utilisateur avec une suggestion** plutôt que de trancher seul.
