# Les réponses de l'utilisateur — ce qui a déjà été demandé

**Une question posée une fois ne se repose pas.** Chaque réponse de l'utilisateur à une question `Qn` s'écrit ici, le
jour même, avec la question en une phrase. Avant de poser une question, on cherche ici :

```powershell
pwsh -File scripts/dev/answers.ps1 -About "mots de la question"
```

Le script cherche aussi dans `doc/progress/decisions.md`, `doc/progress/targeting/` et `notes/subjects.md`. Une réponse
qui change le produit est reportée dans le plan cible ; celle qui passe les critères d'une décision, dans
`decisions.md`. La colonne « Reportée dans » dit où. Une réponse ne se redemande que sur un fait nouveau, nommé dans la
question.

| Date | Question, en une phrase | Réponse | Reportée dans |
|---|---|---|---|
| 13/09 | Faut-il autoriser, pour un lot, fusion dans `main`, poussée et mise à jour par le serveur sans redemander ? | Oui, tout est autorisé, mais la mise à jour par le serveur une seule fois par lot, ou le moins possible. | `local/` (suivi de séance) |
| 13/09 | La règle « ni tu ni vous » s'applique-t-elle à tous les textes affichés d'un coup ? | Oui, tous en une passe. | `doc/en/developing/conventions.md`, section « The wording of labels » |
| 13/09 | Combien de temps garder les journaux, copies de diagnostic et sauvegardes `.reg` ? | 30 jours ; c'était déjà défini, et l'ancienne valeur vaut si on la retrouve. | `doc/progress/targeting/components.md`, section « Les durées de conservation » |
| 13/09 | Que fait la mise à jour quand la source déclarée a disparu ? | Elle prend la dernière version publiée, et la carte le signale. | `doc/progress/implemented/components.md`, ligne `machine.psd1` |
| 13/09 | Le serveur peut-il réparer le compte de service par une action réservée aux administrateurs ? | Oui. | action `service-account-repair` |
| 13/09 | Les tâches de veille (minuteur, résidents, recalculs dus) rejoignent-elles `/operations` ? | Question mal posée, passée. Ne pas la reposer sans l'expliquer mieux. **Tranché le 07/10 : ce n'était pas une question.** `CORE-OPERATIONS` l'exigeait déjà — c'est un défaut, pas un arbitrage. | `targeting/operations.md`, « Ce qui n'est pas tenu » |
| 13/09 | La relance du serveur suit-elle le protocole des opérations asynchrones ? | Non, elle reste à part. | `doc/progress/targeting/operations.md`, section « L'exception arbitrée » |
| 13/09 | L'agent peut-il installer lui-même des mises à jour Windows pour éprouver Vigie ? | Non, jamais ici. | — |
| 13/09 | Faut-il revoir le remplacement des notifications ? | Non : elles fonctionnent, aucune modification majeure prévue. | — |
| 13/09 | Les opérations se nomment-elles courtes et longues, ou synchrones et asynchrones ? | Synchrones et asynchrones. | `doc/en/developing/glossary.md`, section « What runs » |
| 13/09 | Un sujet en échec bloque-t-il le lot ? | Non : il est mis de côté, on continue, on y revient. | `local/` (suivi de séance) |
| 14/09 | Faut-il relire les décisions existantes avec les critères de ce qui mérite une décision ? | Non, pas pour le moment ; c'était déjà dit. | — |
| 14/09 | Quand publier une nouvelle version sur GitHub ? | Quand une version stable est validée, avec tous les changements en cours. | — |
| 14/09 | Faut-il traiter les pièces de l'inventaire encore « aucune réponse » ? | Oui, c'était déjà défini : toutes. | `doc/progress/targeting/components.md` |
| 14/09 | Les documents encore en français sous `doc/en/developing/` se traduisent-ils ? | Oui, tous d'un coup, pour la prochaine version. | `doc/en/developing/conventions.md`, section « A document's language follows its folder » |
| 14/09 | Faut-il une action pour vider le cache du compte de service ? | Question technique, déjà définie : ne pas la poser. | `doc/progress/targeting/components.md`, situation « Maintenance » |
| 14/09 | L'historique des mesures a-t-il besoin d'une remise à zéro ? | Déjà existant et défini : un trou se complète seul, sans demander. | `doc/progress/targeting/components.md` |
| 14/09 | Faut-il renouveler les secrets du compte de service ? | La stratégie est définie : l'appliquer. | `doc/progress/targeting/multi-account-server.md`, section C7 |
| 14/09 | Faut-il limiter les étiquettes de version, 92 à ce jour ? | On devrait en avoir 10 à 20 : au-delà, le protocole de marquage n'a pas été respecté. | **D96** et la mise à jour unique par lot ; `doc/progress/implemented/components.md` |
| 14/09 | Que faire d'un profil du compte de service abîmé ? | Toute erreur se gère et se remonte : c'est déjà défini. | `doc/progress/targeting/components.md`, situation « État cassé » |
| 14/09 | Une installation retire-t-elle les déclarations `safe.directory` de Vigie qui ne visent pas la source actuelle ? | Oui. | `doc/progress/targeting/install-update.md`, étape 5 |
| 14/09 | Quand une étiquette de version doit-elle être posée ? | L'agent a déployé bien plus souvent que demandé. Puis : seulement pour une version stable validée, celle qu'on publie ; un déploiement `dev` affiche le dernier numéro et ses commits (`v1.1.5+3`). | **D123** ; `doc/progress/targeting/install-update.md`, étape 8 |
| 14/09 | Faut-il remplacer l'appel qui prenait 26 s pour savoir qui écoute sur un port ? | Oui, et toujours utiliser la solution optimisée qui donne les informations nécessaires. | `doc/en/agent-working/disciplines.md`, section « Wrapping system calls » ; `scripts/lib/tcp-ports.ps1` |
| 18/09 | Où Vigie montre-t-elle ses propres processus ? | Dans le module Débogage, dont le réglage décide de la visibilité ; rien n'empêche une carte à part dans ce module. | `doc/progress/targeting/residents.md` |
| 18/09 | Faut-il détecter l'épuisement des ports réseau ? | Il faut détecter toutes les erreurs possibles, surtout au niveau système. | `doc/progress/targeting/features.md`, CORE-ERRORS, SYS-EVENTS, NET-STATE |
| 18/09 | La notification de saturation mémoire se complète-t-elle ? | Oui : mémoire engagée comme déclencheur, et ses raisons dans son texte. | `doc/progress/implemented/status.md`, SYS-PERF |
| 18/09 | L'app cliente et la carte WSL donnent-elles leurs raisons ? | Oui, toutes les deux. | — |
| 18/09 | Toute erreur remonte-t-elle à l'utilisateur ? | Oui, par le bon canal, avec ses raisons : c'était déjà demandé. | `doc/en/developing/modules.md`, section « What a card must say » |
| 18/09 | Comment limiter la mémoire de WSL ? | D'abord en proposant d'éditer `.wslconfig` soi-même. | — |
| 18/09 | Une optimisation technique se demande-t-elle ? | Non : c'est technique ; elle se mesure, performance et compatibilité, avant d'être livrée. | `doc/en/agent-working/disciplines.md`, section « Asking a question » |
| 18/09 | La documentation de l'implémenté se met-elle à jour à la fin ? | Non : au fur et à mesure, et l'état cible dès qu'une décision est prise. | `doc/en/agent-working/disciplines.md`, section « The order of work » |
| 18/09 | L'agent peut-il arrêter un processus ? | Jamais sans une confirmation très explicite, claire et sans ambiguïté. | `doc/en/agent-working/disciplines.md`, section « An important operation waits for an explicit YES » |
| 15/09 | Quelle longueur pour répondre à une question ? | Une phrase, pas un exposé ; c'était déjà dit. | `doc/en/agent-working/disciplines.md`, section « Answering » |
| 14/09 | Chaque question porte-t-elle son contexte ? | Oui, toujours : une petite phrase qui dit de quoi on parle. | `doc/en/agent-working/disciplines.md`, section « Asking a question » |
| 18/09 | La carte Ressources montre-t-elle la mémoire vive et le fichier d'échange ? | Oui, séparément : 32 Go de mémoire vive, et « 49 Go » mêlait le fichier d'échange. | `doc/progress/implemented/status.md`, SYS-PERF |
| 18/09 | Que doivent dire les chiffres de mémoire ? | Ce qui est réellement en mémoire vive ; la mémoire engagée ne se présente jamais comme de la mémoire vive. | `apps/backend-pode/probes/system/perf.probe.ps1`, `scripts/lib/system-metrics.ps1` (`Get-ProcessMemoryUse`) |
| 19/09 | Que fait un résident qui trouve un autre PID dans son état ? | Il rapporte le problème avec les deux PID et s'arrête ; un signal au serveur peut aider. | `doc/progress/targeting/residents.md`, « Un seul auteur par champ d'état » |
| 20/09 | La carte Windows Update doit-elle rapporter ses problèmes ? | Oui, tous, d'une manière ou d'une autre. | `doc/progress/implemented/status.md`, WU-PENDING |
| 20/09 | Que fait un clic sur l'en-tête d'un groupe de mises à jour ? | Le libellé coche ou décoche ; tout le reste de la ligne replie ou déplie. | `apps/frontend-web/index.html`, `onGroupHeadClick` |
| 20/09 | Le repli d'un groupe doit-il s'animer ? | Oui, et l'accordéon doit être un composant standard, réutilisable tel quel. | `doc/en/developing/design.md`, ligne « Accordion » ; `apps/atelier/design-systeme.html` |
| 28/09 | Que doit faire Vigie pendant une partie, et que doit dire la carte Stockage ? | Un mode jeu qui allège et espace les autres cartes en rechargeant plus souvent ce qui sert en jeu ; et corriger les quatre points relevés. | `apps/backend-pode/lib/common.ps1` (mode jeu), `disk.probe.ps1` |
| 28/09 | Où s'affiche le mode jeu, et à quelle fréquence enregistrer ? | Sur chaque autre carte réellement en retrait, pas sur la carte Jeu ; et pas de données chaque seconde : ne pas faire ramer l'ordinateur. | `Module.pace` dans le contrat ; `$script:GameModeUseful` |
| 28/09 | Comment voir dans WSL, et que faire de l'alerte des applis gourmandes ? | L'app cliente relève (le serveur n'a pas de distribution) ; le problème est le déclenchement, pas la notification : il était injustifié, et une session doit garder qui a pris quoi, pour un récapitulatif après coup. | `gaming.probe.ps1`, `Add-GameTallyPass` |
| 28/09 | Qu'est-ce qu'un bouchon pendant une partie, et où se lit le récapitulatif ? | Machine au plafond avec un gêneur qui prend une part à lui seul (85 %/10 %, deux relevés) ; le récapitulatif est toujours une popin, jamais sur la carte, et s'ouvre même après une partie courte. | `Add-GameTallyPass`, `$script:GameJam*` |
| 28/09 | Comment ouvrir et fermer le récapitulatif, et que doit dire la notification ? | Ouverture automatique par défaut, fermeture à la partie suivante ou après dix minutes sans être regardée ; notification sans détail (« Voir le récap ») et soumise aux réglages de notification. | `apps/client/client.ps1`, `OpenRecapAtEnd` |
| 29/09 | Faut-il corriger un défaut de mon propre code, et jusqu'où ? | Oui, sans demander, mais avec un suivi tenu de ce qui est prévu, en cours et terminé. | `local/suivi.md` ; `CHANGELOG.md` |
| 29/09 | Comment savoir qui termine une app cliente disparue sans trace ? | C'est technique : à l'agent de choisir ; le propriétaire n'a pas de solution à proposer. | `doc/progress/targeting/features.md`, CORE-SELFWATCH ; `Update-ClientWatch` |
| 29/09 | Un nom d'état comme `RecapVu` est-il acceptable ? | Non : les noms techniques s'écrivent en anglais, et l'agent se permettait trop de dérives. | **D41** ; `scripts/dev/check-naming.ps1` (cliquet élargi) |
| 06/10 | Comment Vigie doit-elle traiter les mises à jour winget, l'app serveur ne pouvant pas exécuter winget ? | Question refusée : elle était déjà répondue. Les mises à jour partent dans la session du compte, et **l'élévation UAC est autorisée pour elles** — la redemander est inutile. | `apps/backend-pode/workers/pkg-job.worker.ps1` ; `doc/progress/targeting/multi-account-server.md`, C4 |
| 06/10 | Sur quel paquet éprouver le bouton de mise à jour winget ? | `7zip.7zip` (26.02 → 26.03) : petit, autonome, sans conséquence s'il échoue. | `apps/backend-pode/actions/pkg-updates.action.ps1` ; relevé de l'épreuve |
| 07/10 | Un travail que Vigie lance elle-même sur minuterie et qui se bloque mérite-t-il une bulle ? | **Oui.** « Toutes les erreurs remontent à l'utilisateur, une règle de base, elle doit être appliquée partout. Après, y'a des moyens UX de ne pas que ce soit trop envahissant. » | `targeting/operations.md` ; `targeting/notifications.md` |
| 07/10 | Comment nomme-t-on le travail que Vigie lance elle-même toutes les trente secondes ? | **« tâche de veille »** — « veille » est déjà le mot du produit, « tâche » rejoint tâche serveur et tâche cliente. | `doc/en/developing/glossary.md` ; `targeting/operations.md` |

## 07/10/2026 — « Je ne veux plus que tu t'arrêtes »

**Ce qu'il a demandé**, quatre fois : partir sur la liste entière des sujets, sans arrêt, sans question, sans
excuse, après une confirmation de la liste. Ses mots : *« Je ne veux plus que tu t'arrêtes, seulement quand TOUS
les sujets sont TOUS terminés »*, *« JE VEUX UNE CONFIRMATION : De la liste exhaustive de tous les sujets »*, et
*« Tu dois confirmer quand tu pars »*.

**Ce que ça vaut désormais** : une confirmation d'une ligne **devant les appels d'outils**, le travail derrière, et
le message final qui **s'ouvre en la redisant**. Raison, apprise de lui le 08/10 : dans le **client desktop**, la
ligne écrite avant les outils **disparaît** quand le message final est posté — elle reste sur la ligne de commande,
mais c'est le client desktop qu'il utilise. Une confirmation donnée seulement avant le travail est donc une
confirmation dont il se retrouve privé, ce qui explique qu'il l'ait réclamée quatre fois. La règle est en place dans `doc/en/agent-working/disciplines.md`, section « "Go, and
do not stop" », et son analyse dans
[`notes/evidence/2026-10-07-four-times-told-to-start.md`](evidence/2026-10-07-four-times-told-to-start.md).

**Et une seconde**, du même jour : *« Un sujet un numéro, tu dois t'y tenir »*. Une liste improvisée (1, 2, 3, 4)
n'est pas une numérotation ; un chantier sans numéro en reçoit un dans `notes/subjects.md` avant d'être mentionné.

## 08/10/2026 — Python est permis, à condition de dire pourquoi

**Ses mots** : « tu as le droit d'avoir des fichiers python mais la raison de pourquoi c'est un python doit être
en entête, et il doit respecter les mêmes entêtes que pour php, adaptés pour le langage. Du coup, tu ne dois pas
le lister comme fichier à convertir en php. »

**Ce que ça change** : le compte des fichiers `.py` cesse d'être un cliquet qui descend vers zéro. `check-naming`
lit désormais chaque `.py` et exige dans son en-tête la section **« WHY THIS FILE IS IN PYTHON »**, en plus de la
ligne d'auteur. Un fichier Python argumenté n'est plus de la dette ; un fichier Python muet est refusé.

**Et les en-têtes PHP eux-mêmes n'étaient pas tenus** : `check-author` ne connaissait pas l'extension `.php`, et
quatre fichiers sur cinq n'avaient aucun auteur. Il la connaît, et pose la ligne **après `<?php`** — posée avant,
elle sortirait telle quelle dans la réponse HTTP.

## 08/10/2026 — chaque fichier porte son intention et son usage

**Ses mots** : « Chaque fichier doit avoir son intention (son utilité, pourquoi) et son usage, comment bien s'en
servir. Ça vaut pour la doc et le code. » Puis, sur l'étendue : « ça ne veut pas dire que tu dois l'appliquer
partout maintenant, c'est juste que t'aligner avec ça sur le terme, ça serait bien, mais plus à la modif quand tu
touches au fichier. »

**Les termes retenus** : **Intent** et **Usage**. Ses exemples d'autres applications Sowapps écrivent parfois
`Utility` à la place d'`Intent`, et les attributs PHP `#[Design(... intent: ...)]` n'ont souvent pas d'`Usage` —
il l'a signalé lui-même comme un manque.

**Ce qui ne doit pas bouger** : l'intention et l'usage sont assez généraux pour ne jamais être réécrits quand le
contenu change. S'il faut les retoucher à chaque modification, c'est qu'ils décrivaient le contenu.

**Où c'est écrit** : `doc/en/developing/conventions.md`, section « Every file says its INTENT and its USAGE ».

