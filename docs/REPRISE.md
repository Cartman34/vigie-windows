# Vigie — reprise du projet (à lire en premier)

> **Rôle de ce document (consigne utilisateur)** : servir à reprendre le travail en cas de
> perte de session — **uniquement ce qui est utile à l'instant**. Pas de journal : le
> passé vit dans `git log` et `CHANGELOG.md`, les règles dans `DECISIONS-VALIDEES.md`.

Point de reprise. Après ce fichier : `docs/DECISIONS-VALIDEES.md`, `SUIVI.md`, `PRISE-EN-MAIN.md`.

## Le projet
**Vigie** : tableau de bord **local** pour un PC Windows. Dépôt : `vigie-windows`.
> ⚠️ « HYPERION » n'est **pas** un nom de code du projet : c'est le **nom de la machine** de
> l'utilisateur. Toute occurrence dans le code, les identifiants ou la doc est un **défaut de
> généricité** (valeur machine codée en dur) à éliminer, pas un héritage à conserver.
- Backend **PowerShell + Pode** (`backend/`), écoute **127.0.0.1:47600**, jeton Bearer + anti-CSRF + liste blanche d'actions.
- Frontend **HTML/JS pur** (`apps/frontend-web/index.html`), sert la maquette `apps/frontend-web/mock/state.json` si le back est absent.
- **App tray WinForms** (`apps/tray/tray.ps1`) : lance le serveur en fond, icône = statut de l'app (jauge), menu, fenêtre dédiée (Edge/Chrome `--app`).
- Fonction phare : **verrouiller Windows Update** (ACL deny SYSTEM sur les dossiers de tâches) pour bloquer les redémarrages forcés, sans masquer les vraies MAJ.

> **Ne pas confondre avec l'Atelier.** « Vigie » = l'application (PowerShell + Pode, port
> 47600, élevée). « **Atelier** » = l'outil de développement (PHP, port 47610, jamais
> élevé, `apps/atelier/`). Voir **D28**, **D29** et `apps/atelier/README.md`.

## Règles de conception (permanentes)
- **On parle français, le code est en anglais.**
- Pas de duplication (helpers partagés dans `apps/backend-pode/lib/common.ps1`).
- **Toujours** traiter erreurs + sortie + code retour (`Invoke-Native`).
- Scripts **idempotents**. **PS7 + UTF-8 avec accents** (les lanceurs restent ASCII).
- **Numéroter les sujets (S1, S2…) dans les comptes rendus** : l'utilisateur répond par
  numéro. **Un statut d'alerte se vérifie avant de s'afficher** : un compromis volontaire
  (HVCI coupé…) se décrit en neutre, il ne s'alerte pas — vérifier l'état réel et les
  contraintes de LA machine avant d'affirmer.
- **Vérifier les prérequis en amont.** **Valider avant de dire « prêt »** (ne jamais inventer une validation).
- **Tests courants = tests de CONTRAT** (**D63**) : parseur + `check-probes.ps1` (sondes
  en lecture seule, invariants). Exécuter une action/un worker pour de vrai ou piloter
  l'app de bout en bout = test d'intégration : ça se **demande**, à chaque fois.
- **Rien qui consomme la machine sans autorisation** (**D62**) : charge GPU/CPU, test
  lourd, benchmark — on demande à CHAQUE fois. Une permission passée ne vaut pas pour la
  suite. Les branches rares se valident par simulation (`VIGIE_FAKE_<QUOI>`).

### Disciplines de validation — dans cet ordre, avant toute livraison

| Ce qu'on touche | Ce qu'on lance | Ce que ça attrape |
|---|---|---|
| un **module** (creation/evolution) | suivre **`docs/MODULES.md`** — LA reference, a citer dans tout brief de SA qui touche aux sondes | l'oubli d'une regle D48/D49/D57 |
| n'importe quel `.ps1` | `[Parser]::ParseFile` sur chaque fichier | la syntaxe, **rien de plus** |
| une **sonde** | `pwsh -File .\scripts\check-probes.ps1 -Only <sonde|module>` (dev, ciblé — D51) puis `-All` avant livraison | l'exécution réelle + les invariants **D49**/**D50** |
| `apps/frontend-web/index.html` | recharger la page **servie** (`http://127.0.0.1:47600`) et lire la console | erreurs de syntaxe et d'exécution JS |
| un contrat (`openapi.yaml`) | relecture — aucun parseur YAML sur la machine | rien d'automatique, à dire tel quel |

**Le parseur ne suffit pas** (**D50bis**) : un paramètre passé deux fois le franchit sans un
mot et fait disparaître une carte à l'exécution. C'est arrivé, livré et annoncé comme fait.

**LES ANTISLASHS DE MES SCRIPTS D'ÉDITION SONT MANGÉS** — piège coûteux, rencontré cinq
fois le 26/08. `\\` arrive souvent **simple** dans le fichier écrit, et `\t`, `\25`, `\b`
deviennent des **caractères de contrôle** (tabulation, 0x15, retour arrière). Symptômes
vécus : une regex `(^|\\)` inopérante qui a fait échouer **en silence** tout l'inventaire
des comptes ; un chevron CSS affiché « B8 » ; un chemin `apps\tray\tray.ps1` transformé en
tabulations, donc introuvable. **Remède** : ne pas écrire d'antislash littéral quand on
peut l'éviter — `Join-Path` imbriqués, `Split([char]92)`, chevron dessiné en CSS — et
relire le fichier écrit (`cat -A`) au moindre doute.

**Toute écriture scriptée d'un fichier source est ATOMIQUE** : écrire dans `fichier.tmp`,
vérifier la taille, puis `os.replace`. Un script Python qui plante en plein `write()` sur
le fichier ouvert en 'w' laisse un fichier TRONQUÉ — c'est arrivé le 24/08 (index.html à
0 octet, commité et poussé sur main par la chaîne shell qui suivait). Et ne jamais chaîner
`git commit` derrière un script par un simple retour à la ligne : `&&` uniquement.

**Un fichier rendu (`.html`) ne s'édite JAMAIS avec les outils Edit/Write** (**D47**) :
l'aperçu du panneau ouvre alors le fichier en `file://` et vole le focus de l'utilisateur.
Passer par un script de remplacement exact — et relancer ensuite le garde-fou de chaînes JS
(chaîne monoquote non terminée, expression régulière coupée par un retour à la ligne : deux
couches d'écriture ont déjà mangé des échappements).

**Redéployer** = commit sur la branche, `git merge --no-ff` dans `main` depuis le dépôt
principal, `git push` des deux, puis :
`Stop-Process` sur l'écouteur du port 47600, puis `pwsh -File scripts/tray.ps1 -Restart`.
**Relancer le tray ne relance PAS le serveur** : l'ancien devient orphelin et `$startServer`
sort aussitôt puisque le port répond — on sert alors indéfiniment du code périmé.
- **Toucher une sonde ⇒ lancer `scripts/check-probes.ps1`** : le parseur ne voit pas qu'un paramètre est passé deux fois, l'exécution si (**D50bis**).
- **Toute décision validée est consignée dans `docs/DECISIONS-VALIDEES.md`** + son support copié dans `docs/maquettes-validees/`.

## Architecture (contract-first)
- `apps/backend-pode/api/openapi.yaml` = source de vérité du contrat REST.
- Sonde = `apps/backend-pode/probes/<theme>/*.probe.ps1`, renvoie 1 module OU un tableau de modules.
- Action = `apps/backend-pode/actions/<id>.action.ps1`, renvoie `@{ message; result }`. `result.invalidate=@('x.probe.ps1')` force le recalcul.
- Agrégation + cache (mtime+TTL, single-flight, serve-stale) : `Get-State` dans `common.ps1`.
- **Tâches de fond** : `Start-DetachedAction` (worker pwsh caché) ; ex. paquets via `Start-PkgJob` + `apps/backend-pode/workers/pkg-job.worker.ps1`. Une action longue répond `result.async=$true` + `module`; le front met la carte en « busy » et l'interroge jusqu'à fin.

## État actuel du produit (résumé — le détail est dans le code et les docs)

Vigie tourne en production : tray élevé (tâche planifiée qu'il répare lui-même) + serveur
Pode 47600 + front une page + Atelier PHP 47610 (à lancer à la main :
`pwsh -File apps/atelier/atelier.ps1`).

**Éditeur : Sowapps ; auteur : Florent HAZARD** (D72). Installation partagée :
`C:\Program Files\Sowapps\Vigie` ; données par compte :
`%LOCALAPPDATA%\Sowapps\Vigie`.

Modules : Windows Update (verrouillage natif, MAJ au choix, date de dernière analyse),
Système (**Stockage** : seuil D57, analyse de la consommation en tâche de fond D60/D61,
arborescence demandée **niveau par niveau**), **Comptes** (D67), Sécurité, Réseau, WSL,
Outils & paquets, Jeux (détection par faits : Game Bar, bibliothèque Steam, moteur, plein
écran — D64).

Paramètres (D56) : notifications, modules **en accordéon** (D71), utilisateurs, apparence,
à propos. **21 notifications nommées** déclarées par les modules (D68), filtrées par les
droits avec remontée des cas critiques (D70). Icônes : fonte maison (D58), cloche d'après
Font Awesome, puzzle, utilisateurs — planche dans l'Atelier (`design-systeme.html`).

Docs de référence : `MODULES.md` (créer/maintenir un module), `DESIGN.md` (design
système), `DECISIONS-VALIDEES.md` (toutes les règles, D01→D72).

### File de travail (dans l'ordre)

1. **Session `Famille` — à constater** (en attente de l'utilisateur). Tout est en place et
   vérifié : version déployée dans `C:\Program Files\Sowapps\Vigie` (133 fichiers, aucun
   secret, `BUILTIN\Utilisateurs` en lecture/exécution), tâche **`Vigie - Famille`** créée
   pour `HYPERION\Famille` en niveau *Limited*, pointant sur l'installation partagée. À
   constater en ouvrant sa session : démarrage **non élevé**, actions administrateur
   **refusées et expliquées** (D65), réglages et historique **séparés**
   (`%LOCALAPPDATA%\Sowapps\Vigie`).
2. **Jeux — détection VÉRIFIÉE en vraie partie le 26/08** : Autonauts reconnu (Game Bar +
   bibliothèque Steam + `UnityPlayer.dll`), CPU 4,7 % · GPU 22,3 % · VRAM 0,98 Go. **Seul
   reste un défaut de LATENCE** : la carte a affiché « aucun » pendant que le
   rafraîchissement de fond tournait (~40 s pour l'ensemble des sondes) alors que la sonde
   et l'API disaient déjà « Autonauts ». À traiter : rafraîchir la carte Jeux plus vite
   (TTL 10 s déjà, c'est le cycle du front et du recalcul global qui traîne).
3. **Icônes — à éprouver sur la page Design système** (demande utilisateur) : cloche
   (proportions Font Awesome), puzzle (tenon haut, encoche droite), utilisateurs, point du
   « i ». Planche : `http://127.0.0.1:47610/apps/atelier/design-systeme.html` (Atelier à
   lancer à la main : `pwsh -File apps/atelier/atelier.ps1`). Reste aussi l'ancien sujet du
   **centrage vu sur SON écran** (frames de sa vidéo au scratchpad, à mesurer, pas à l'œil).
4. **Edge — feu vert donné, diagnostic en cours** : le binaire est SAIN (151.0.4129.107,
   lancement headless code 0, aucune erreur au journal Application). Un lancement fenêtré
   avec un **profil neuf** sort aussi en code 0 sans fenêtre : la piste « profil corrompu »
   est donc écartée, le profil (500 Mo, `Default` présent, aucun verrou résiduel) n'est pas
   en cause. Piste suivante : lancement bloqué par une stratégie ou un composant système
   (`MicrosoftEdgeUpdate`, GameAssist MSIX présent) — reprendre par `msedge --version`,
   `--enable-logging --v=1`, et l'Observateur d'événements côté Edge.
5. **S5 — invalidation immédiate de la sonde réseau** sur événement Windows de changement
   d'adresse : **feu vert donné**, à faire.
6. **Tray — feu vert pour analyse** : il ne prend plus l'ordre `-Restart` en 15 s (constaté
   à chaque déploiement les 25 et 26/08) ; c'est son auto-guérison qui relance le serveur,
   donc le déploiement aboutit quand même. À analyser : `apps/tray/var/run` (ordres),
   `apps/tray/var/log`, et la boucle qui consomme les ordres dans `apps/tray/tray.ps1`.
7. Fond ancien : éprouver verrou/VBS élevé après redémarrage ; commentaires en anglais
   (D41) ; workflow GitHub ; bulle de notification du tray à observer en réel.

## État de la machine de l'utilisateur — à savoir avant de conclure quoi que ce soit

- **Windows Update est VERROUILLÉ** (`NoAutoUpdate=1`, verrou ACL posé) : c'est voulu, c'est
  la fonction phare. Les actions de Vigie lèvent le verrou le temps d'agir puis le reposent.
- **Un redémarrage est en attente** depuis l'installation de mises à jour.
- **Écart permanent registre/actif sur VBS** : le registre dit 0, VBS tourne pourtant. Ne
  jamais en déduire une bascule en attente — la proposition de redémarrage ne doit
  apparaître qu'après une bascule faite **depuis Vigie**.
- **Edge est installé mais ne démarre pas** (sort en moins d'une seconde, sans fenêtre).
  Chrome est le navigateur par défaut et fonctionne.
- **Le DNS passe par Acrylic** (proxy DNS local, service `AcrylicDNSProxySvc`,
  127.0.0.1 sur le Wi-Fi) : une panne d'Acrylic ressemble à « plus d'internet » —
  le champ DNS de la carte Réseau (S11) fait la différence.
- **`netsh wlan` échoue** (erreur 5) : ni force de signal, ni SSID par ce chemin.
- **git n'est que dans le PATH utilisateur**, pas machine : un processus élevé ne le trouve
  pas sans chemin résolu.
- **Node n'est pas installé** et ne le sera pas (**D06**) ; **aucun parseur YAML** non plus.


## Travailler avec des sous-agents (autorisé par l'utilisateur)

**Cadre posé par l'utilisateur** : jusqu'à **3 sous-agents**, chacun dans **son propre
worktree**, chacun **fusionne lui-même** dans `main`. Ils sont **persistants** : on leur
renvoie un sujet plutôt que d'en relancer un neuf, ils gardent leur contexte. « Ne les gave
pas » — un sujet à la fois, cadré ; le rôle de l'agent principal est l'**orchestration**.

### Répartition qui a fonctionné

Découper par **fichiers disjoints**, pas par thème : deux agents dans `common.ps1` en même
temps, c'est un conflit garanti. Répartition tenue :
sondes d'un côté · gestionnaires de paquets et backend de l'autre · documentation seule
(elle ne touche aucun `.ps1`). L'agent principal garde le front (`index.html`) et le socle.

### Ce qu'un brief doit contenir, sans exception

1. **Où lire** — `docs/REPRISE.md` puis les décisions précises (`D15`, `D43`, `D47`…), pas
   « lis la doc ».
2. **Le sujet, un seul**, avec le modèle existant à copier quand il y en a un (« étudie
   `wu-list-pending.action.ps1` avant d'écrire »).
3. **Les règles non négociables** : français accentué pour l'utilisateur, commentaires sans
   accents, identifiants en anglais, points de suspension réservés à une action en cours,
   validation par le Parser **et** `check-probes.ps1`, jamais de ligne `Co-Authored-By`.
4. **Les pièges connus**, nommés — sinon ils les retrouvent à leurs frais : `--disable-interactivity`
   pour winget, `netsh wlan` qui échoue ici, l'aperçu `file://` qui vole le focus.
5. **Ce qu'il ne doit PAS toucher** : les fichiers d'un autre agent, et le **redémarrage du
   serveur** (port 47600) que l'agent principal se réserve.
6. **La prudence machine** : « ne laisse pas la machine dans un état différent de celui où
   tu l'as trouvée » — indispensable dès qu'on touche au verrou Windows Update ou à VBS.
7. **Le format de réponse attendu** : deux ou trois phrases — ce qui a changé, ce qui a été
   vérifié **en conditions réelles**, ce qui reste incertain.

### Ce qu'ils ont apporté que je n'aurais pas trouvé seul

Ils **exécutent** au lieu de relire, et remontent ce que le brief avait de faux. Exemples
réels : `$pid` est en lecture seule et l'exception était avalée par un `catch` vide ; le
découpage des colonnes winget donnait une version comme identifiant de paquet ; une clé de
registre absente faisait échouer le verrou **en silence** sur une machine neuve ; et surtout
la correction de mon propre brief — `Get-AdminRoot` existe à côté de `Get-ToolsPath`, mon
`grep` ne voyait que le second.

**Leçon** : un agent qui conteste le brief a souvent raison. Vérifier soi-même avant de
trancher, puis lui redonner le sujet corrigé.

### Limites constatées

- L'isolation du worktree peut **refuser** les commandes git visant le dépôt partagé ; ils
  contournent alors par `git push origin HEAD:main` depuis leur worktree. Conséquence :
  **le `main` local se retrouve en retard**, faire `git pull` avant toute fusion.
- Ils ne peuvent pas juger un rendu visuel : ce qui se voit reste à l'agent principal, via
  la page **servie** (jamais `file://`).


## Décisions validées
Voir `docs/DECISIONS-VALIDEES.md` : icône tray = option B (graduations + talon confirmés) ; nom = dépôt « Vigie Windows » (slug `vigie-windows`), interface « Vigie » à la place de « Control Panel ».

## Dépôt GitHub (état à jour)

**La publication est faite.** Le dépôt `Cartman34/vigie-windows` est peuplé ; l'import initial est
le commit **`e45a062`** (« Vigie — import initial »), branche **`main`**.

**Source de vérité aujourd'hui** : `C:\EspaceRestreint\Workspaces\Git\vigie-windows`.
C'est le dépôt git, et c'est **là** qu'on travaille (Claude Code s'ouvre dans ce dossier).

**Ancien espace de travail** : `C:\EspaceRestreint\Workspaces\AiTeam\LocalWork\hyperion-control-panel`
— **en cours de retrait**, il n'est plus la source. Ne plus y éditer, ne plus y recopier.
Conformément à **D07** il est **renommé** (suffixe `.old`) et non supprimé ; la suppression
n'aura lieu qu'après confirmation explicite que tout fonctionne depuis le dépôt.

### Config git / accès (toujours valable)
- `credential.helper=manager` ; `user.name` / `user.email` déjà réglés.
- Remote en **HTTPS** : `https://github.com/Cartman34/vigie-windows.git`.
- Authentification : token *fine-grained* (All repos + **Contents R/W**), mémorisé par le Credential
  Manager au 1er push. Username = `Cartman34`, Password = le **token** (pas le mot de passe GitHub).
- Alternative zéro-token : remote SSH `git@github.com:Cartman34/vigie-windows.git` avec la clé locale.
- `.gitignore` exclut déjà le jeton API (`apps/backend-pode/var/secrets/`), l'état (`apps/backend-pode/var/cache/`) et les logs.
  Avant tout commit, `git status` ne doit montrer NI `var/secrets/`, NI `var/cache/`, NI `apps/*/var/log/`, NI `*.bak-*`.

### Droits de l'agent (**D40**)
`.claude/settings.json` est **versionné** et accorde les outils au niveau de l'outil
(`"Bash"`, `"PowerShell"`, sans parenthèses) : plus aucune demande de permission, y compris
sur les commandes composées. Ne **pas** revenir à des règles par motif (`Bash(git *)`) : elles
ne couvrent que les commandes analysables statiquement, ce qui était la cause du problème.
Un hook `PreToolUse` jugeant le texte a été essayé puis **retiré** (faux positifs inévitables,
+1 s par commande) — l'historique complet est dans **D40**, ne pas le refaire.

## Contraintes environnement (importantes)

> Cette section decrit la machine de travail REELLE. Elle remplace l'ancienne, qui
> decrivait une VM Linux ephemere (Cowork/`device_bash`) et n'a plus cours : le projet
> est desormais edite directement sur la machine, dans le depot git.

### Outils presents
- **PowerShell 7** (`pwsh`) : present. C'est l'outil de validation du code PowerShell.
- **Python 3.11** : present (sert a `apps/tray/assets/generate-icons.py`).
- **Chocolatey**, **git**, **php**, **composer**, **symfony-cli** : presents.
- **git** fonctionne normalement : depot, branches et worktrees operationnels. **HTTPS** vers
  GitHub, jeton memorise par le Credential Manager.

### Outils ABSENTS (et volontairement non installes)
- **Node / npm** : absent de la machine (verifie : PATH, nvm, fnm, volta, scoop, paquets
  Chocolatey, et recherche de `node.exe` sous Program Files / LOCALAPPDATA / APPDATA /
  ProgramData). Le projet n'a **aucune** dependance JS : pas de `package.json`, pas d'etape
  de build, un seul fichier HTML servi tel quel. On n'installe donc pas Node (voir **D06**).

### Comment valider (ne JAMAIS inventer une validation)
- **PowerShell** : `[System.Management.Automation.Language.Parser]::ParseFile(...)` sur chaque
  `.ps1` / `.psd1` modifie, et on rapporte la sortie reelle.
- **JavaScript du front** : charger `apps/frontend-web/index.html` en `file://` dans un navigateur et
  lire la console (**D06**). Une erreur de syntaxe empeche l'execution de tout le bloc
  `<script>` : verifier qu'une constante definie en fin de script existe bien suffit a prouver
  que le fichier parse. Ce test couvre en plus les erreurs d'execution et le repli sur
  `mock/state.json`.
- **Lanceurs** (`.cmd`, `.vbs`) : doivent rester **ASCII pur** (verification octet par octet).
  Le reste du code est en **UTF-8 avec accents**.

### Privileges
- La session de l'agent n'est **pas elevee**. Toute operation sur la tache planifiee
  (enregistree en `RunLevel Highest`) exige un PowerShell administrateur lance par
  l'utilisateur : `install-autostart.ps1`, `uninstall-autostart.ps1`, `uninstall-legacy.ps1`.

### A ne jamais committer
- `apps/backend-pode/var/secrets/` (jeton API), `apps/backend-pode/var/cache/`, `apps/*/var/log/`, `*.bak-*`.
  Le `.gitignore` les couvre deja ; verifier malgre tout `git status` avant chaque commit.
