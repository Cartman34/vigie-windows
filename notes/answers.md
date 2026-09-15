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
| 13/09 | Les passes internes (minuteur, résidents, recalcul des sondes) rejoignent-elles `/operations` ? | Question mal posée, passée. Ne pas la reposer sans l'expliquer mieux. | `notes/subjects.md`, **S14** |
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
| 14/09 | Chaque question porte-t-elle son contexte ? | Oui, toujours : une petite phrase qui dit de quoi on parle. | `doc/en/agent-working/disciplines.md`, section « Asking a question » |
