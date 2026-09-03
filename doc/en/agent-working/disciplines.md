# DISCIPLINES DE PROCESS — à tenir en continu

> Règles que Claude doit respecter systématiquement sur ce projet.
> Toute nouvelle discipline demandée par l'utilisateur est ajoutée ici.
>
> **Ce document se LIT en entier et s'APPLIQUE.** Ce n'est pas une référence à consulter
> quand on hésite : chaque section vient d'un manquement réel, et la relire après coup ne
> répare rien. Une discipline qu'on n'a pas lue s'applique quand même.
>
> Il oblige à son tour : les **arbitrages** vivent dans `../../progress/decisions.md` et
> s'imposent (voir « Chercher avant de concevoir ») ; la **conception** vit dans
> `../../progress/targeting/` — ce que le produit doit faire — et
> `../../progress/implemented/` — ce qui est en place.

## Langue & encodage
- Échanges **en français** ; code **entièrement en anglais**.
- **Un nom de fichier est du code : il s'écrit en anglais.** Scripts, bibliothèques, actions, sondes. Les *documents*
  restent en français, c'est la langue du projet. `check-naming.ps1` tient un cliquet séparé sur les noms de fichiers
  — j'ai créé `reprise.ps1` le 31/08, dans le quart d'heure où j'écrivais la discipline qui l'interdit : la règle était
  écrite et relue, elle n'était vérifiée nulle part.
- **Messages de commit en anglais** : c'est du technique, au même titre que le code. Ils étaient écrits en français
  jusqu'au 30/08.
- **Accents obligatoires** dans les libellés visibles. **UTF-8 partout**, cible **PowerShell 7**.
- Exception : les **lanceurs** (`run/start/install/*.cmd`) restent en **ASCII** (compat PS 5.1 avant bascule pwsh).

## NODO — l'arrêt immédiat, et il n'a qu'un seul interrupteur

**Dès que le propriétaire écrit `NODO`, plus rien ne change tant qu'il ne le lève pas : aucune modification, aucune
compilation, aucun commit, aucune publication, aucun artefact. Lire pour répondre est permis ; tout le reste attend,
aussi petit et aussi évident que cela paraisse.**

C'est la règle du dessus : elle prime sur toutes les autres, y compris sur « une erreur trouvée se corrige » et sur
« un correctif, un commit ». Une correction évidente, une coquille, un fichier temporaire, un `git add` : tout attend.

**Ce qui reste permis :** lire le dépôt, lancer un vérificateur en lecture seule, relire un journal — bref, ce qu'il
faut pour **répondre**. Rien qui écrive.

**Qui la lève :** lui, et lui seul. Ni le temps, ni la fin d'une tâche, ni le fait que le sujet ait changé, ni ma
conviction que ce que je m'apprête à faire est sans risque. En cas de doute sur l'intention — a-t-il écrit le mot pour
l'appliquer, ou pour en parler ? — on considère qu'il l'applique, et on demande.

## Jamais de commande ponctuelle — toujours l'installation

**Une correction se pose par un script idempotent, jamais par une commande à taper une fois.** Le 30/08 j'ai proposé un
`git config --system --add safe.directory …` « pour débloquer tout de suite » : refusé, et à raison. Une commande
ponctuelle ne laisse aucune trace, n'existe que sur cette machine, et disparaît au prochain poste.

**Comment l'appliquer :** si un réglage manque, il manque **dans l'installation** — on le pose là, et on relance
`setup.cmd`, qui est idempotent par construction. Ce qui vaut d'être fait à la main vaut d'être fait par le script.

## Avant d'agir
- **Vérifier les prérequis** de l'environnement en amont (pwsh, Pode, droits, chemins).
- **Idempotence** : tout script doit pouvoir être relancé sans effet de bord.

## Qualité de code
- **Zéro duplication** : une fonctionnalité = un seul code partagé (helpers dans `lib/common.ps1` :
  `Test-Elevated`, `Invoke-Native`, `Test-UpdateTasksAclLock`, `Update-StateJson` ; rendu de carte `cardHtml`).
- **Traiter tout appel externe** (commande / service / script) : erreurs **ET** sorties **ET** codes de retour
  (passer par `Invoke-Native` ; une action doit vérifier son **résultat réel**, jamais renvoyer un faux succès).

## Sécurité (ne jamais devenir une back door)
- Écoute **127.0.0.1 uniquement**, **jeton Bearer**, **anti-CSRF** (Origin/Referer), **whitelist d'actions**
  + confinement de chemin (`Resolve-Path`). Vérifier les failles à **chaque** ajout d'action.
- Le script lancé par l'utilisateur **demande l'UAC** si besoin ; le serveur tourne **élevé** mais protégé.

## Poser une question — FORMAT OBLIGATOIRE

Ce n'est pas une préférence de style : une question posée hors de ce format est à reposer.

**Numérotation.** Toute question, tout problème, toute décision à prendre porte un numéro préfixé `Q` — Q1, Q2… — pour
qu'une réponse s'y accroche sans ambiguïté (« Q1A »). Les numéros **restent stables** tant qu'une question de la série
est ouverte ; quand toutes sont répondues, la série repart à Q1.

**Questions autonomes.** Chaque question est énoncée **en entier**, avec ses options, **à chaque fois qu'elle est
posée** — jamais réduite à un thème ou à une étiquette. Une question qu'il faut aller rechercher plus haut est une
question mal posée.

**Options.** Une question fermée reçoit des options lettrées — A, B, C… — **la recommandée en premier**. Une question
ouverte reste libre. Chaque option annonce son **avantage principal** en quelques mots (plus rapide à construire, plus
sûr, plus maintenable…), pour que l'arbitrage soit explicite plutôt que deviné.

**Le format ci-dessus est LE format — partout.** En conversation comme dans un document de conception, un compte rendu
ou un fichier de suivi : numéro `Qn`, énoncé complet, options lettrées.

**Les outils interactifs sont à ÉVITER, et ils ne priment jamais sur les formats définis.** J'avais écrit ici que les
questions « passent par l'outil de question interactif » : une confusion entre le canal et le format, qui m'a fait
présenter un moyen comme une règle. Une question se pose en texte, au format ci-dessus ; sans numéro ni options, elle
reste hors format quel que soit le moyen employé.

## Répondre — court, complet, et à la question posée

**Une question appelle une RÉPONSE, pas une action.** Aucune modification de code, de documentation ou de
configuration ne s'engage sur la foi d'une question : seule est permise l'analyse — lecture, mesure — strictement
nécessaire pour répondre. Il pose souvent des questions pour éprouver un raisonnement *avant* de décider ; agir à ce
moment-là court-circuite sa décision. Répondre d'abord, complètement. Si l'action est évidente, la proposer en une
phrase à la fin plutôt que de l'exécuter.

**On annonce AVANT, on conclut APRES.** Une phrase avant de commencer — ce que je vais faire — puis le silence
pendant, puis le résultat. Vingt-quatre minutes sans nouvelle, c'est le laisser deviner si je travaille, si j'ai
compris, ou si je me suis perdu.

**UN OUTIL PLUTÔT QU'UNE RÈGLE À RETENIR — et il devient alors OBLIGATOIRE.** Quand un appel bas niveau se trompe de
la même façon à chaque fois, on ne retient pas la parade : on l'enferme dans une fonction, elle devient le seul chemin,
et un vérificateur refuse l'appel brut. L'erreur est alors corrigée **une fois pour toutes**, y compris pour le code
qui n'est pas encore écrit. `Start-ChildProcess` (**D116**) est le premier de la famille — voir « Envelopper les appels
système », dont c'est la forme aboutie.

*Le 02/09, le résident des jeux mourait à chaque armement sur « `C:\Program` n'est pas un script » : `Start-Process`
joint ses arguments avec des espaces et n'en cite aucun. J'ai corrigé en entourant le chemin à la main — et c'était
faux aussi : `"C:\dossier\"` échappe son propre guillemet fermant et avale l'argument suivant (mesuré le 03/09).*

**UNE VALEUR PEUT TOUT CONTENIR — et la liste des pires cas n'existe pas.** Espaces, antislashs, antislash **final**,
guillemets, apostrophes, accents, `&`, `|`, `;`, `%`, tabulation, chaîne vide : on ne conçoit pas pour la valeur
d'aujourd'hui, on conçoit pour celle qui cassera. Un échappement s'**éprouve** en comparant ce que le destinataire
reçoit vraiment à ce qu'on a voulu lui passer, jamais en relisant la ligne.

**ET L'ÉCHAPPEMENT DÉPEND DU MONDE.** Citer à la main est juste pour `Start-Process` et **faux** pour l'opérateur
d'appel `&` comme pour `ArgumentList` de .NET, qui citent eux-mêmes : la valeur y arrive avec de vrais guillemets
dedans. Trois sites du dépôt étaient dans ce cas, sans que rien ne le dise. Le monde décide de l'échappement, pas
l'habitude — et c'est l'outil qui connaît le monde, pas moi.

**MON PROPRE OUTILLAGE D'ÉCRITURE MANGE LES ÉCHAPPEMENTS.** Le 03/09, un `\\` écrit dans un script est arrivé `\` dans
le fichier, et l'expression régulière refusait de compiler. Ce qui porte des antislashs ou des guillemets s'écrit par
un chemin qui ne les réinterprète pas, et **on relit la ligne écrite** — ce que j'ai voulu écrire ne prouve rien sur
ce qui est dans le fichier.

**Les caractères spéciaux se traitent par le contrôle, pas par l'attention.** Antislashs mangés, guillemets imbriqués,
espaces dans un chemin, échappements avalés par un script d'écriture : ces fautes reviennent parce qu'elles ne se
voient pas à la relecture. Chacune se règle par un vérificateur qui refuse, jamais par une promesse de vigilance — et
le vérificateur s'éprouve en posant volontairement le piège.

**Une commande longue part en TACHE DE FOND.** Sinon je ne réponds plus : il parle, et je suis muet jusqu'à ce que
la commande finisse. Une installation, une passe complète de sondes, un déploiement : en fond, puis je rends compte.
Rester bloqué sur une commande n'apporte rien à personne — surtout pas à lui.

**On ne double JAMAIS un journal existant.** Le programme écrit le sien : y superposer une capture donne deux
versions du même récit, des lignes en double, et un affichage qui perd ses couleurs et prend un tour de retard —
ce qui fait passer un programme qui avance pour un programme figé (constaté le 01/09 sur l'installation). Si ce
journal ne suffit pas, on **améliore celui-là**.

**Déboguer suit une démarche ÉCRITE, pas un souvenir.** Elle vit dans
[`doc/en/developing/debugging.md`](../developing/debugging.md) et s'exécute avec `scripts/dev/debug.ps1`. La veille,
je savais faire ; le lendemain, j'improvisais une ligne de commande bâtarde. Une démarche qui revient est un script.

**Une installation se DEMANDE, jamais elle ne se lance d'elle-même.** Le message qui la propose porte d'abord les
correctifs — cause, correction, une phrase chacun — puis la demande de la lancer. Il valide, ensuite on lance. Déployer
sans avoir dit ce qu'on déploie lui retire le seul moment où il peut dire non.

**Un défaut se rapporte en DEUX PHRASES : la cause, puis la correction.** Pas le récit de l'enquête, pas ce que j'ai
cru, pas ce qui aurait pu arriver. « La fabrication cassait sur un fichier vide — elle l'ignore désormais. » Le reste
vit dans le message de commit, pour qui veut y revenir.

**Trois lignes.** Une explication tient en trois lignes : l'affirmation elle-même d'abord, puis ce qu'elle coûte, puis
ce qu'on a déjà. Cinq paragraphes numérotés pour répondre à « c'est quoi la bonne pratique ? » est un échec, pas de la
rigueur. Développer seulement s'il le demande.

**Court, mais en phrases complètes.** Ce qu'il refuse est le pavé, pas la grammaire : une réponse en fragments
télégraphiques (« oui sans session, oui à la main ») est un échec au même titre qu'un mur de texte — il a repris les
deux. Sautent : les récapitulatifs de ce que le commit dit déjà, les tableaux décoratifs, les reformulations de sa
demande, la liste de tout ce qui a été vérifié quand rien n'a échoué. Restent : ce qui a changé, ce qui a été trouvé
d'inattendu, ce qui reste ouvert, et ce qu'il doit décider.

*Quand il dit « pavé » ou « trop long », c'est que la réponse contenait ce que j'avais envie de dire plutôt que ce
qu'il avait besoin de lire.*

## Ce qui sort du dépôt s'annonce

**Tout ce que je pose hors des fichiers versionnés se dit explicitement, au moment où je le pose.** Un hook git, une
tâche planifiée, un réglage de machine, un fichier dans un profil : ça agit ensuite sans moi, sur ses gestes à lui, et
il doit savoir que ça existe pour pouvoir le retirer.

*Le 31/08, j'ai installé un hook `pre-commit` dans son `.git/hooks` et je l'ai mentionné au passage, noyé dans un
paragraphe. Il a fallu qu'il demande « tu viens de l'ajouter ? » pour que ce soit clair.*

**Comment l'appliquer :** une phrase, en propre, qui dit **quoi**, **où**, et **ce que ça change** — avant le reste du
compte rendu, pas après.

## Une question qui revient est un script

**La deuxième fois que je pose la même question à la machine, j'écris le script qui y répond.** Pas une ligne de
commande de plus, longue et illisible, jamais deux fois la même : un fichier dans `scripts/dev/`, nommé, commenté, que
lui aussi peut lancer.

*Le 01/09 : après chaque installation je redemandais en une ligne bâtarde si le serveur était revenu, quelle version
était posée, ce qui avait échoué. Il a fallu qu'il me le fasse remarquer.* → `scripts/dev/deploy-status.ps1`.

**Et on factorise avant de recopier.** Un geste écrit deux fois est un geste qui va diverger : les deux exemplaires
n'auront bientôt plus le même délai d'attente, le même repli, le même message. La deuxième écriture n'est pas une
copie, c'est une fonction — dans `lib/common.ps1` si le serveur s'en sert, dans `scripts/lib/` si ce sont les scripts.

*Exemples du jour : `Get-OpenUrl` (l'adresse d'ouverture, écrite dans l'app cliente ET dans l'outil de questions, avec
déjà deux délais différents), `Open-VigieSession` (la même chaîne, réclamée par un troisième appelant),
`Get-PortListener` (un appel système qui ment de la même façon partout).*

## Un outil plutôt que ma vigilance

**À la deuxième occurrence d'un même défaut, on écrit le vérificateur — avant de corriger le défaut.** Quand une
consigne déjà donnée est de nouveau enfreinte, il ne veut ni excuses ni promesse d'attention : il veut un outil. Ce que
je vérifie à l'œil, je le rate.

*Trois violations de la consigne d'encodage en une journée — BOM absent, accents retirés, apostrophes retirées « par
prudence » — toutes de la même cause : aucune vérification mécanique.*

**Comment l'appliquer :** le vérificateur vit dans `scripts/dev/check-*.ps1`, rend un code de retour exploitable, et
propose `-Fix` quand la correction est mécanique. En place : `check-encoding`, `check-naming` (cliquet), `check-labels`,
`check-reachable`, `check-doc`, `check-coherence`, `check-probes`.

## Envelopper les appels système

**Un appel externe qui apparaît une deuxième fois s'enveloppe dans une fonction à nous**, qui devient le seul chemin.
Les retours inattendus et les absences se traitent alors une fois, au même endroit.

*Le 28/08, `$acl.Access` a rendu une collection vide côté serveur là où elle rendait trois règles depuis une session
ordinaire. L'appel était écrit à deux endroits ; il ne mentait que dans un, et le contrôle de sécurité a conclu à une
compromission sur une installation saine. Le 31/08, `Get-NetTCPConnection` levait une erreur là où « personne n'écoute »
est la bonne réponse : deux pavés rouges dans un déploiement réussi.*

**Comment l'appliquer :** la fonction porte le commentaire qui dit ce que l'appel brut fait de travers — sans lui,
quelqu'un le réécrira en direct. Exemples : `Get-AclAccessRules`, `Get-PortListener`, `Invoke-Git`.

## Pas de montagnes — faire la chose simple

**Ne pas inventer de cas limites, de conflits ou de garde-fous que personne n'a rencontrés**, et ne pas transformer un
geste évident en procédure.

*Le 29/08 : un « conflit de ports » entre un serveur et son propre remplaçant, une bascule séparée qui laissait
l'installation à moitié faite, un commutateur pour autoriser ce qui allait de soi, un garde-fou interdisant
« admin + session » qui était faux, un plafond de dix minutes sur une attente que le serveur gère seul. Chaque fois :
du code en plus, une décision de plus à prendre pour lui, un comportement moins évident.*

**Comment l'appliquer :** avant d'ajouter une protection, se demander si le cas s'est produit **une seule fois**. Sinon,
ne rien ajouter. Une installation installe, un remplacement remplace, une relance relance. Les précautions qui valent
sont celles qui vérifient le RÉSULTAT (« est-ce que ça écoute vraiment ? »), pas celles qui refusent d'agir.

## Conventions de nommage — pour que l'erreur soit impossible, pas rattrapée

**Une variable ne porte JAMAIS le nom d'un paramètre du script.** PowerShell ignore la casse : `$source` **est**
`$Source`. Écrire `$source = …` dans un script qui déclare `$Source` n'est pas une variable locale, c'est une
affectation au paramètre — et si celui-ci porte un `ValidateSet`, le script meurt sur place avec un message qui parle
d'autre chose. Deux fois le 30/08, dans le même fichier ; la seconde a tué la mise à jour devant l'utilisateur.

**La convention :** une variable locale porte un nom **qualifié** — `$sourceRepo`, `$sourcePath`, `$targetPath` — jamais
le nom nu qui pourrait être un paramètre. `check-coherence` refuse les collisions, en comparaison **sensible à la
casse** (`-cne` ; avec `-ne`, la règle ne se déclenche jamais — je m'y suis fait prendre en l'écrivant).

**Les autres conventions déjà tenues par un outil :** noms de code en anglais (cliquet `check-naming`), texte affiché
dans `lang/fr.json` (`check-labels`), pas de mot banni « machine » ni « tray » dans l'affiché, une fonction définie une
seule fois, un cercle de comptes jamais refiltré à la main.

## Un correctif, un commit

**Un commit = une correction, ou un ajout, et rien d'autre.** Son titre le dit en entier. S'il faut « et » pour le
résumer, c'était deux commits.

**Pourquoi :** le 30/08, neuf commits pour la journée alors qu'il y avait bien plus de correctifs. `6d02bf6` en portait
trois chantiers sans rapport (l'outil de question à Vigie, « qui exécute » ≠ « qui demande », le cache par compte) ;
`cf824b8` en portait deux (la relance qui passait à côté de la tâche, git qui refusait en silence) ; `5524cc3` deux
aussi. Conséquences concrètes : impossible d'annuler un seul de ces changements, impossible de dire lequel a introduit
une régression, et un message de commit qui raconte au lieu d'expliquer.

**Ce qui va ensemble dans un commit :** le code, ses libellés, son vérificateur et la doc que ce changement rend
fausse. Ce sont les faces d'une même correction, pas des sujets différents.

**UNE LIVRAISON VA JUSQU'À `origin/main`.** Un commit qui reste dans un worktree n'est livré à personne : la branche
se fusionne dans `main` en avance rapide, et `main` se **pousse**. Sans le push, le dépôt de référence ignore la
journée entière — le 31/08, `origin/main` avait dix-neuf commits de retard, dont toutes les corrections que
l'utilisateur essayait sur sa machine.

```powershell
git merge --ff-only <branche>   # depuis le dépôt principal
git push origin main
```

**UN COMMIT EST UNE LIVRAISON, PAS UN POINT DE SAUVEGARDE.** On ne commite pas après le moindre bout de code : on
commite quand la chose est **terminée**, **éprouvée**, et qu'on juge qu'elle doit être livrée. Parser le fichier et voir
les vérificateurs au vert ne prouve que l'absence de faute de frappe.

*Le 30/08 : six correctifs de la chaîne de mise à jour commités sans qu'un seul ait tourné — dont la relance par la
tâche planifiée, écrite précisément parce que la précédente avait laissé Vigie morte.* Le travail reste dans la copie
de travail jusqu'à l'épreuve. Si l'épreuve demande un geste que je ne peux pas faire (élévation, redémarrage, session
d'un autre compte), je le dis et j'attends — et si la session se termine avant, le commit part quand même, en
**annonçant dans son message ce qui n'a pas été éprouvé** (fin de session prioritaire).

## Une erreur trouvée se CORRIGE, elle ne se rapporte pas

**Signaler un défaut n'est pas le traiter.** Le 30/08, j'ai constaté le matin que la tâche `Vigie` lançait le dépôt au
lieu de l'installation partagée — et je me suis contenté de faire **afficher** l'écart par la carte. La cause est restée
en place toute la journée, jusqu'à ce qu'il me le fasse remarquer.

**Comment l'appliquer :** quand un constat sort d'une vérification, il va au bout — on corrige la cause, ou on dit
explicitement pourquoi on ne le fait pas maintenant (et ça devient une tâche écrite, pas une phrase dans un message).
Rendre un défaut visible est utile ; ça ne remplace jamais sa correction.

## Revenir d'une compression de contexte

**Un résumé n'est pas une source.** Quand le contexte est compressé, les disciplines, les décisions et les documents de
conception disparaissent : il ne reste qu'un récit de ce qui a été fait. Ce récit vieillit — il affirme des états du
dépôt (« plus utilisé », « déjà corrigé », « éprouvé ») qui étaient vrais au moment où ils ont été écrits, et parfois
ne l'étaient déjà pas.

*Le 31/08, au retour d'une compression : annoncé que `deploy-prod.ps1` n'était plus appelé par personne, et supprimé en
conséquence. Un bouton de l'interface l'appelait toujours. La phrase venait du résumé ; personne n'avait vérifié.*

**Comment l'appliquer :** le point de reprise est `scripts/dev/restore-context.ps1`, et le point d'entrée qui y renvoie est
`briefing.md` — valable pour n'importe quel agent. Un fichier chargé automatiquement par l'agent (`CLAUDE.md` pour
Claude Code) survit à la compression et rend le retour plus sûr, mais il reste **facultatif** : il ne porte aucune
règle, seulement le chemin. Premier geste au retour, avant toute conclusion et avant toute suppression :

```powershell
pwsh -File scripts/dev/restore-context.ps1          # les disciplines, la carte des documents, l'état du dépôt
pwsh -File scripts/dev/restore-context.ps1 -Court   # sans le texte des disciplines
```

**Trois affirmations ne se font jamais de mémoire**, quelle que soit la confiance qu'on a dans le souvenir :

| Ce qu'on veut dire | Ce qui le prouve |
|---|---|
| « plus rien ne l'appelle » | `check-reachable.ps1`, **puis** une recherche sur le nom — un fichier peut être atteint par une action ou par le front. |
| « on avait décidé que » | `decisions.ps1 -About`. Une incohérence sans décision se demande. |
| « c'est éprouvé » | les vérificateurs, relancés **maintenant**. |

## Une conception porte son schéma

**Un mécanisme qui met en jeu plusieurs pièces se dessine.** Qui déclenche, qui lit, qui écrit, dans quel ordre, et où
ça s'arrête : un paragraphe le décrit mal, un schéma le montre. Il se lit en ASCII dans le document — pas d'outil, pas
de rendu à installer, et il reste juste dans un terminal comme dans un navigateur.

*Le 01/09 : j'ai décrit une boucle de surveillance en trois paragraphes, et implémenté autre chose que ce qui avait
été demandé sans que la différence se voie.*

## Une demande se juge contre le MODÈLE, pas contre le code du jour

**Avant d'écrire une ligne pour une nouvelle demande, on répond à une question : le modèle actuel couvre-t-il ce
besoin, ou faut-il le revoir ?** Trois réponses possibles, et une seule est interdite.

| réponse | ce qu'on fait |
|---|---|
| le modèle couvre | on l'emploie tel quel, sans rien ajouter à côté |
| le modèle s'étend honnêtement | on l'étend, et la cible est mise à jour dans le même geste |
| **le modèle est faux** | on le dit, on propose la reprise, et on ne code pas avant d'être d'accord |

**Ce qui est interdit : tordre l'existant pour y faire entrer le nouveau.** C'est le geste qui coûte le plus cher, et
c'est le plus tentant : il donne un résultat tout de suite, il n'oblige à rien reconsidérer, et il laisse une couche
de plus que le suivant devra comprendre. Au bout de dix demandes, les dix sont incompatibles entre elles et avec ce
qui existait.

**Les besoins ne se devinent pas.** Ils sont dans `doc/progress/targeting/` : on les lit AVANT de juger. Et s'ils ne
suffisent pas à trancher, **on demande** — « des besoins qui touchent le modèle sont-ils prévus ? » — plutôt que de
concevoir pour ce qu'on connaît aujourd'hui.

*Le 01/09, deux fois dans la journée. La veille permanente : je l'ai greffée sur le rafraîchissement de fond existant
— « recalculer la carte la plus en retard » — au lieu de me demander si ce modèle répondait au besoin ; il ne
répondait pas, et il a fallu tout reprendre. L'app cliente : elle lisait le fichier de cache du serveur, ce qui était
juste jusqu'au jour où le serveur est passé sous un compte de service ; ce changement de modèle n'a jamais été
propagé, et elle n'a plus émis une notification pendant quatre jours sans que rien ne le signale.*

**Ce qu'il faut se demander à chaque fois :** qu'est-ce que cette demande dit du modèle ? Si elle ne rentre qu'en
forçant, c'est le modèle qu'elle met en cause — pas elle.

## Chercher avant de concevoir

**La source de vérité, c'est `doc/progress/decisions.md`** — les arbitrages, rien d'autre. Avant de concevoir quoi que
ce soit : y chercher. Le fichier fait près de trois mille lignes, donc chercher doit coûter dix secondes :

```powershell
pwsh -File scripts/dev/decisions.ps1 -About "mise a jour deploiement"   # les titres
pwsh -File scripts/dev/decisions.ps1 -About "cache" -Full               # + le texte
pwsh -File scripts/dev/decisions.ps1 -Number D99                        # le texte entier
```

**Une incohérence sans décision qui tranche se DEMANDE**, elle ne s'arbitre pas seul : c'est ainsi qu'on empile deux
conceptions contradictoires dont aucune n'est écrite.

**Chaque chose à sa place.** Un arbitrage va dans `decisions.md`. Une discipline de travail va ICI. Une conception —
comment ça marche — va dans `doc/en/developing/`. Le 29/08 j'ai écrit une discipline dans `decisions.md`, alors que ce
fichier-ci existait et le dit dans son en-tête.

*Le 29/08 : trois erreurs le même jour, jamais un oubli de code — trois fois ne pas avoir cherché. Réinventé « d'où
vient le code déployé » quand `UpdateSource` y répondait ; rangé un réglage d'ordinateur dans chaque copie quand D33
décrit les couches de configuration ; redéfini une fonction qui existait déjà, la dernière définition écrasant l'autre
en silence.* `scripts/dev/check-coherence.ps1` attrape désormais ces deux dernières.

## Validation avant de dire « prêt »
- Chaque `.ps1` / `.psd1` : **parser** via `[System.Management.Automation.Language.Parser]::ParseFile`
  (`pwsh` de la machine), et on rapporte la **sortie réelle**.
- Le JS d'`index.html` : **charger la page en `file://` et lire la console** (**D06**).
  Node n'est pas installé et ne doit pas l'être : le projet n'a aucune dépendance JS.
  Une erreur de syntaxe empêche l'exécution de **tout** le bloc `<script>` — vérifier qu'une
  constante définie en fin de script existe suffit à prouver que le fichier parse.
- Vérifier l'**ASCII** des lanceurs, l'**UTF-8** du reste.

## Cache & perfs
- Cache **par sonde** (mtime du fichier + TTL) ; **jamais** de recalcul global.
- Après une action : **invalidation ciblée** des sondes impactées (`result.invalidate`).
- Sondes lentes (lock, pending, wsl) : TTL longs.

## Front
- **REST standard**, back interchangeable sans impact front. Contenu **adapté à la largeur**.
- Si la **version serveur** change → la page se **recharge** entièrement seule.
- **Composants réutilisables** (design system `HDS` : dialog/confirm/info in-app, boutons).
- **Statut de carte = santé fonctionnelle** : un avertissement de ligne **sans impact** ne fait pas passer la carte en orange.

## Livraison (device)
- Modifs **live** : `common.ps1`, sondes, actions (re-sourcées à chaque requête) → effet immédiat.
- `server.ps1` / `start.ps1` → **redémarrage serveur** requis.
- `apps/frontend-web/index.html` → auto-reload via version.

## Où va ce qui est daté — `local/`, `notes/`, `doc/`

**La documentation ne contient rien de temporel.** Un constat daté qui s'y glisse vieillit sur place et finit par
mentir : `decisions.md` porte les arbitrages, `targeting/` ce que le produit doit faire, `implemented/` ce qui est en
place, `agent-working/` la manière de travailler. Aucun de ces fichiers ne raconte une journée.

| | | |
|---|---|---|
| `local/` | **ignoré par git** | jetable : scripts temporaires, extractions, fichiers de travail, suivi personnel |
| `notes/` | versionné | daté mais utile : extraits de preuves, mesures, morceaux d'échange gardés en référence |
| `doc/` | versionné | intemporel |

Un fichier de `notes/` porte sa date dans son nom (`2026-08-31-etat-lent.md`) : on sait sans l'ouvrir s'il sert encore.

## Documentation (toujours à jour)
- `briefing.md` (reprise à tout moment), `CHANGELOG.md`, `doc/en/developing/conventions.md`, `doc/progress/targeting/features.md`.
