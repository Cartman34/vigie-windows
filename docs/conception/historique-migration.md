# Historique des mesures — plan de migration

> Comment atteindre la cible décrite dans [`historique-cible.md`](historique-cible.md),
> **petit à petit** : chaque étape est livrable seule, utile seule, et ne casse rien de
> l'existant. On peut s'arrêter après n'importe laquelle avec un produit cohérent.

## Constat de départ (vérifié dans le code au 2026-08-24)

- **Aucun journal structuré n'existe.** Ni `Write-ProbeRun`, ni `Get-ProbeRuns`, ni
  `var/cache/probe-runs.jsonl` — nulle part dans le dépôt. La seule trace des passages de
  sondes est le log **texte** (`Write-Log 'state'` : « sonde X recalculée (N ms) »), écrit
  dans la boucle de recalcul de `Get-State` (`common.ps1`). L'étape 1 crée donc le journal ;
  elle ne s'appuie sur rien d'autre que ce point d'accroche existant.
- Les briques réutilisables sont là : `Update-StateJson` (fusion JSON sous mutex),
  `ConvertTo-UtcDate`, `Get-VarPath`, la mesure de durée déjà faite pour le log.

## Règles valables à toutes les étapes

- **Jamais** de sonde exécutée plus souvent : tout se greffe sur le recalcul existant.
- Dates écrites en UTC `'o'`, relues via `ConvertTo-UtcDate` (D44).
- Toucher `common.ps1` ou une sonde ⇒ `[Parser]::ParseFile` sur chaque fichier modifié
  **et** `pwsh -File .\scripts\check-probes.ps1` (D50bis). Toucher `index.html` ⇒
  modification par script, vérification sur la page **servie** (D47).
- Toucher le contrat ⇒ mise à jour d'`openapi.yaml` dans le même commit (D31).
- L'échantillonnage est **best-effort** : une erreur d'écriture d'historique se journalise
  et ne fait jamais échouer un recalcul ni une requête `/state`.

---

## Étape 1 — Le journal des passages de sondes

**Livrable** : `apps/backend-pode/var/history/probe-runs.jsonl`, alimenté à chaque recalcul.

- `Get-VarPath` accepte `-Kind 'history'` (création du dossier comme pour les autres).
- Nouveau helper `Write-ProbeRun` dans `common.ps1` : append d'une ligne
  `{at, probe, ms, status, error?}` sous mutex nommé (`Local\VigieHistory_probe_runs_jsonl`),
  appelé aux deux issues (succès/erreur) de la boucle de recalcul de `Get-State` — là où
  la durée est déjà calculée pour `Write-Log`. Le log texte **reste** : il sert le
  diagnostic au fil de l'eau, le JSONL sert la lecture outillée.
- Helper de lecture `Get-ProbeRuns` (`-Probe`, `-Since`) pour l'exploitation en console.
- Bornage minimal dès cette étape : à l'ouverture, si le fichier dépasse un plafond de
  lignes, on tronque aux plus récentes (pas encore de config : constante en tête de
  fonction, la config arrive à l'étape 2).

**Utile seule** : répondre à « pourquoi le rafraîchissement est lent ? » par des données
(`lock` ≈ 11 s, combien de fois, quand) au lieu de fouiller un log texte. C'est aussi la
matière première de la future série `probe.duration`.

**Ne touche pas** : contrat, front, sondes, config.

**Validation** : parser sur `common.ps1` ; `check-probes.ps1` ; appeler `/state?fresh=1`
sur le serveur local puis constater les lignes ajoutées (D43 : on observe l'effet, on ne
croit pas l'absence d'exception).

## Étape 2 — Le socle des séries de mesures, avec deux mesures pilotes

**Livrable** : l'infrastructure d'échantillonnage + `disk.free` et `net.latency` archivées.

- `$script:MeasureCatalog` dans `common.ps1` : identifiant, sonde source, extracteur,
  nature (`gauge`/`event`), intervalle minimal. Deux entrées seulement — une gauge lente
  (disk) et une gauge liée à une mesure externe (`net.latency`, notée quand `measAt`
  change).
- `Write-MeasureSamples` : appelé juste après un recalcul réussi dans `Get-State`, il
  consulte le catalogue pour la sonde concernée, lit l'index (`history-index.json`, via
  `Update-StateJson`), applique l'intervalle minimal, append dans
  `var/history/<measureId>.jsonl` sous le mutex du fichier.
- Section `History` de `config.psd1` : `Enabled`, `RetentionDays` global,
  `MaxLinesPerMeasure`, table `Measures` par mesure (**rétention au global ET par mesure**
  dès cette étape — c'est l'exigence, pas une option à retard). `Get-HistoryConfig` résout
  les couches. `config.local.sample.psd1` documente la surcharge.
- Purge : `Invoke-HistoryPurge`, déclenchée au plus une fois par 24 h depuis
  `Write-MeasureSamples` (date en index), réécriture atomique sous mutex. Couvre aussi
  `probe-runs.jsonl` (qui perd sa constante provisoire de l'étape 1).

**Utile seule** : les archives se constituent silencieusement — chaque jour qui passe rend
les étapes suivantes plus intéressantes ; les fichiers se lisent déjà à l'œil ou en console.

**Ne touche pas** : contrat, front, sondes (l'extracteur lit le module rendu, pas la sonde).

**Validation** : parser + `check-probes.ps1` ; forcer deux recalculs espacés et constater
points, respect de l'intervalle, index à jour ; passer `Enabled = $false` et constater
qu'il ne s'écrit plus rien.

## Étape 3 — L'historique entre au contrat : `GET /history/{measureId}`

**Livrable** : la route `GET /api/v1/history/{measureId}?window=7d` (Bearer, comme le
reste), décrite dans `openapi.yaml`, avec décimation serveur (~200 points max) et bloc
`summary` (min/max/first/last/count).

- Lecture seule ; mesure inconnue → 404 propre ; fichier vide → `points: []` (ce n'est pas
  une erreur, l'historique est jeune).
- Rappel D30 : le contrat vit dans `apps/backend-pode/api/openapi.yaml` ; pas de parseur
  YAML sur la machine, la relecture manuelle est la validation du fichier, dite telle
  quelle.

**Utile seule** : les données deviennent interrogeables (console, `curl`) sans attendre le
front ; le contrat est posé et relisible.

**Validation** : appel réel sur le serveur local, fenêtres 24 h / 7 j / inconnue / mesure
inexistante.

## Étape 4 — La tendance se voit : sparkline sur les cartes

**Livrable** : `New-Field` accepte `-MeasureId` ; les sondes `disk` et `net` le posent sur
« Espace libre » et « Latence » ; le front dessine la sparkline (SVG inline, JS pur) sous
tout champ qui porte `measureId`, avec le dépliage 24 h / 7 j / 30 j.

- `openapi.yaml` documente la propriété optionnelle `measureId` d'un champ.
- Le front est générique dès le premier jour : ajouter une mesure ensuite (étapes 5+) ne
  demandera plus une ligne de JS.
- Sans historique ou avec moins de 2 points : **pas de sparkline du tout** — pas de cadre
  vide, pas de « données insuffisantes ».

**Utile seule** : premier bénéfice visible pour l'utilisateur ; c'est aussi la validation
visuelle du format et de la décimation.

**Validation** : page **servie** (`http://127.0.0.1:47600`), console propre, garde-fou de
chaînes JS après modification par script (D47) ; `check-probes.ps1` pour les deux sondes
touchées.

## Étape 5 — Les événements : WSL, verrou, redémarrage en attente

**Livrable** : nature `event` opérationnelle ; `wsl.running`, `update.lock`,
`update.rebootPending` au catalogue ; restitution en ligne de faits (« 3 redémarrages WSL
sur 7 jours ») dans les cartes concernées.

- Détection de changement via `lastValue` de l'index — pas de relecture du JSONL.
- `GET /history/{id}` rend les events tels quels (pas de décimation : ils sont rares).
- Attention au champ WSL : la valeur affichée est un libellé (« Actif »/« Inactif ») ;
  l'extracteur note une valeur **stable en anglais** (`running`/`stopped`), le libellé
  reste une affaire d'affichage (D41).

**Utile seule** : « depuis quand ce redémarrage attend-il ? », « le verrou a-t-il été levé
cette semaine ? » — des questions qu'on se pose déjà et que rien ne sait dater aujourd'hui.

**Validation** : arrêter/démarrer WSL depuis la carte et constater l'événement écrit puis
restitué ; `check-probes.ps1`.

## Étape 6 — Une dérive devient un avertissement (D49)

**Livrable** : `Get-MeasureTrend` dans `common.ps1` (pente, médianes, comparaison de
fenêtres, refus de conclure sous un nombre minimal de points) ; **une seule** règle câblée
pour commencer : la **projection de saturation disque**, dans la sonde `disk` — champ
`warn` avec le constat chiffré, `FixAction 'disk-cleanup'` et le guide.

- Une règle à la fois, éprouvée avant la suivante : latence (étape 6b), WSL instable (6c),
  verrou levé trop longtemps (6d) suivront le même moule.
- Seuils en tête de sonde, rebasculables en une ligne (modèle D20).

**Utile seule** : l'historique cesse d'être une archive pour devenir de la vigilance — le
cœur de la proposition P2.

**Validation** : `check-probes.ps1` (qui vérifie précisément l'invariant D49 : tout champ
en défaut propose une issue) ; test avec un fichier d'historique forgé dans
`var/history/` pour provoquer la dérive sans attendre 30 jours.

## Étape 7 — Extension tranquille du catalogue

**Livrable** (au fil de l'eau, sans urgence) : `disk.used`, `net.down`/`net.up`,
`pkg.pending`, `perf.cpu`/`perf.ram` (rétention courte), `probe.duration` dérivée du
journal de l'étape 1. Chaque ajout = une entrée de catalogue + éventuellement un
`-MeasureId` sur un champ ; le reste suit tout seul.

C'est aussi ici que l'historique rejoindra la **gestion des modules** (D48) quand elle
existera : la rétention par mesure a vocation à s'exposer dans le panneau de configuration
du module concerné — même valeur, même définition (`config`), juste une porte de plus.

---

## Ordre et dépendances

```
1 (journal) ──► 2 (socle + pilotes) ──► 3 (contrat) ──► 4 (sparkline)
                        │                                    
                        ├──────────► 5 (events) ──► 6 (dérives → warn)
                        └──────────► 7 (extension, au fil de l'eau)
```

Seul enchaînement contraint : 2 avant 3, 3 avant 4, 2 avant 5, 5 avant 6d. Les étapes 5 à
7 peuvent s'intercaler selon l'envie et le temps ; chaque livraison suit le rite habituel
(commit sur branche, fusion, redéploiement complet — y compris `Stop-Process` du port
47600, cf. `docs/REPRISE.md`).

## Risques identifiés et parades

| Risque | Parade |
|---|---|
| Grossissement silencieux d'un fichier | plafond de lignes dès l'étape 1, rétention + purge dès l'étape 2 |
| Deux écrivains simultanés (requête forcée + rafraîchissement de fond) | append sous mutex par fichier ; l'index passe par `Update-StateJson` qui a déjà réglé ce problème |
| Mélange UTC/local (déjà vécu, D44) | écriture `'o'` UTC unique dans les helpers, relecture via `ConvertTo-UtcDate`, et **mesurer** un âge en test plutôt que relire le code |
| Ralentir `/state` | échantillonnage = un append + une lecture d'index ; mesurer la durée avant/après à l'étape 2 et le dire avec les chiffres (D43) |
| Faux warnings de dérive sur historique jeune | `Get-MeasureTrend` refuse de conclure sous un minimum de points ; pas de warning « historique absent » |
| Vidage de cache emportant l'historique | dossier `var/history/` distinct de `var/cache/` dès l'étape 1 |
