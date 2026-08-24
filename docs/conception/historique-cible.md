# Historique des mesures — conception cible

> Document de conception (proposition P2 validée). **Aucun code n'accompagne ce document** :
> il décrit la cible ; le chemin pour y aller, étape par étape, est dans
> [`historique-migration.md`](historique-migration.md).

## 1. Le principe, en une phrase

Vigie calcule déjà des valeurs à chaque passage de sonde ; l'historique se contente de les
**noter au passage** dans des fichiers d'archive, puis de s'en servir pour montrer des
tendances et signaler des dérives — **sans jamais exécuter une sonde de plus, ni plus
souvent**.

### Règles fondatrices

1. **On échantillonne ce qui est déjà calculé.** Le point d'accroche unique est le recalcul
   d'une sonde dans `Get-State` (`common.ps1`) : c'est le seul endroit où une valeur fraîche
   apparaît, c'est le seul endroit où on la note. Aucune cadence propre à l'historique,
   aucun réveil supplémentaire de la machine.
2. **L'historique n'est pas du cache.** `var/cache/` peut être vidé sans dommage (tout se
   recalcule) ; un historique perdu ne se recalcule pas. Il vit donc dans un dossier
   distinct : `apps/backend-pode/var/history/` (nouvelle valeur `history` de
   `Get-VarPath -Kind`, conformément à D33).
3. **Dates en UTC, toujours.** Toute date écrite l'est en
   `ToUniversalTime().ToString('o')` ; toute date relue passe par `ConvertTo-UtcDate`.
   Le mélange UTC/local a déjà rendu le cache d'état inopérant (D44) — on ne rejoue pas ça.
4. **Écriture concurrente maîtrisée.** Fichiers **append-only** (une ligne JSON par
   échantillon), chaque fichier protégé par un mutex nommé dérivé de son nom
   (même convention que `Update-StateJson` : `Local\VigieHistory_<leaf>`). La réécriture
   complète n'arrive qu'à la purge, en écriture atomique (`.tmp` + `Move-Item`).
5. **Une valeur, une définition** (D15) : le catalogue des mesures, les rétentions et les
   seuils de dérive sont définis chacun à un seul endroit (voir §5).
6. **Pas de dépendance externe** (D06) : PowerShell pour écrire et servir, JS pur pour
   dessiner les sparklines (un `<svg>` de quelques lignes, pas de bibliothèque).

## 2. Ce qu'on échantillonne

Deux natures de séries, parce que deux natures de faits :

| Nature | Ce que c'est | Quand on écrit | Exemple |
|---|---|---|---|
| **`gauge`** | une valeur numérique qui varie | à chaque recalcul de la sonde, bornée par un intervalle minimal | espace disque libre |
| **`event`** | un changement d'état | **uniquement quand la valeur change** | WSL passe d'Actif à Inactif |

Un `event` ne coûte presque rien en stockage (quelques lignes par mois) et dit l'essentiel :
*quand* c'est arrivé. Une `gauge` échantillonnée à chaque TTL de sonde serait obèse pour
rien (perf toutes les 8 s = 10 000 points/jour) : chaque mesure porte donc un **intervalle
minimal d'échantillonnage** — si le dernier point est plus récent, on ne note rien.

### Catalogue initial des mesures

Identifiants en anglais (D41), de la forme `<module>.<measure>` :

| Identifiant | Nature | Source (déjà calculée) | Intervalle mini | Pourquoi |
|---|---|---|---|---|
| `disk.free` | gauge | sonde `disk` (Go libres sur C:) | 30 min | tendance de remplissage, projection de saturation |
| `disk.used` | gauge | sonde `disk` (%) | 30 min | même sujet, lecture en pourcentage |
| `net.latency` | gauge | sonde `net` / `netmeasure.json` (ms) | à chaque **nouvelle mesure** (`measAt` change) | dérive de la qualité de ligne |
| `net.down` / `net.up` | gauge | `netmeasure.json` (Mbps) | idem | dérive du débit |
| `wsl.running` | event | sonde `wsl` (Actif/Inactif) | sur changement | compter les redémarrages/arrêts de WSL |
| `update.lock` | event | sonde `lock` (verrou posé/levé : `autoUpdatesEnabled` + `aclLock`) | sur changement | tracer chaque levée du verrou — c'est la fonction phare |
| `update.rebootPending` | event | sonde `lock` | sur changement | savoir depuis quand un redémarrage attend |
| `pkg.pending` | gauge | sonde `packages` (nb de MAJ en attente, par gestionnaire) | 6 h | voir l'entretien s'accumuler |
| `perf.cpu` / `perf.ram` | gauge | sonde `perf` | 10 min | contexte de charge (rétention courte) |
| `probe.duration` | gauge | le journal des passages (§3) | intrinsèque | dérive du coût des sondes (`lock` ≈ 11 s aujourd'hui) |

Le catalogue vit **dans le code**, à un seul endroit (`$script:MeasureCatalog` dans
`common.ps1`, à côté de `$script:ProbeTtls`) : pour chaque mesure — sonde source, extracteur
(comment lire la valeur dans le module rendu), nature, intervalle minimal par défaut. La
**rétention**, elle, est de la configuration (§5) : c'est un choix d'utilisateur, pas une
définition de mesure.

**Règle d'extension** : ajouter une mesure = ajouter une entrée au catalogue. Aucune sonde
n'écrit elle-même dans l'historique — sinon chaque sonde réinvente l'échantillonnage, et
l'une finira par oublier le mutex ou l'UTC.

## 3. Le journal des passages de sondes

Fichier `apps/backend-pode/var/history/probe-runs.jsonl` — une ligne par recalcul de sonde :

```json
{"at":"2026-08-24T10:12:03.412Z","probe":"lock.probe.ps1","ms":11240,"status":"ok"}
{"at":"2026-08-24T10:12:04.001Z","probe":"net.probe.ps1","ms":540,"status":"error","error":"..."}
```

- écrit par un helper unique `Write-ProbeRun`, appelé au **seul** endroit qui recalcule
  (la boucle de `Get-State`), là où la durée est déjà mesurée pour `Write-Log` ;
- `status` = `ok` ou `error` (l'erreur d'exécution de la sonde, pas le statut de la carte) ;
- lu par `Get-ProbeRuns` (filtre par sonde, par fenêtre de temps).

C'est le **premier échantillonnage de l'historique** : il rend diagnosticables les sondes
lentes ou instables (aujourd'hui il faut fouiller un log texte), et la série
`probe.duration` en dérive sans rien recalculer.

> Note d'exactitude : ce journal **n'existe pas encore** — seul un log texte
> (`Write-Log 'state'`) trace les durées. Sa création est l'étape 1 de la migration.

## 4. Format de stockage

**Un fichier JSONL par mesure** : `apps/backend-pode/var/history/<measureId>.jsonl`
(ex. `disk.free.jsonl`), plus `probe-runs.jsonl` (§3).

```json
{"at":"2026-08-24T10:12:03Z","v":212.4}                  // gauge
{"at":"2026-08-24T09:41:00Z","from":"Actif","to":"Inactif"}   // event
```

### Pourquoi ce découpage et pas un fichier unique

- **Append-only par nature** : ajouter une ligne ne relit rien, ne réécrit rien — la
  fenêtre de course se réduit à l'append, sous mutex court. Un JSON unique imposerait
  lecture-fusion-réécriture à chaque échantillon (le coût et les courses de
  `state-cache.json`, pour un fichier qui ne fait que grossir).
- **Rétention par mesure** triviale : purger `net.latency` à 30 jours ne touche pas
  `disk.free` gardé un an.
- **Lecture partielle** : servir la tendance d'une mesure ne charge que son fichier.
- Un fichier par mesure reste **peu de fichiers** (une douzaine), lisibles à l'œil nu —
  c'est aussi un outil de diagnostic.

### Index d'échantillonnage

Un petit fichier `history-index.json` (écrit via `Update-StateJson`, donc fusion sous
mutex) porte, par mesure : date du dernier point (`lastAt`), dernière valeur notée
(`lastValue`, pour détecter les changements des `event` sans relire le JSONL), date de la
dernière purge. Il évite de relire la fin de chaque fichier à chaque passage. S'il est
perdu, on repart de zéro sans dommage : au pire un point en double.

### Bornage et purge

- **Rétention en jours**, configurable au global et par mesure (§5). La purge réécrit le
  fichier en ne gardant que les lignes dans la fenêtre (atomique, sous le mutex du fichier).
- **Déclenchement** : au démarrage du serveur, puis au plus une fois par 24 h, adossé à un
  recalcul déjà en cours (jamais de réveil dédié). Date de dernière purge dans l'index.
- **Garde-fou de taille** en plus de l'âge : au-delà d'un plafond par fichier
  (`MaxLinesPerMeasure`, défaut 50 000 lignes), la purge garde les plus récentes même si la
  rétention en autoriserait davantage. Un intervalle minimal mal réglé ne doit pas pouvoir
  remplir le disque — ce serait piquant pour un module qui surveille l'espace disque.
- Une ligne illisible (écriture interrompue) est **ignorée et comptée**, jamais bloquante ;
  la purge en profite pour l'éliminer.

## 5. Configuration

Dans `apps/backend-pode/config/config.psd1` (versionné, générique — D18/D33), surcharge
possible dans `config.local.psd1`. **Exigence explicite de l'utilisateur : la rétention se
règle au global ET par mesure.**

```powershell
History = @{
    # Interrupteur general. Desactive = plus aucune ecriture (les fichiers restent).
    Enabled          = $true
    # Retention PAR DEFAUT, en jours. S'applique a toute mesure sans reglage propre.
    RetentionDays    = 90
    # Garde-fou de taille par fichier de mesure (lignes), en plus de l'age.
    MaxLinesPerMeasure = 50000
    # Reglages PAR MESURE : la cle est l'identifiant du catalogue. Toute cle absente
    # herite du global. IntervalMinutes surcharge l'intervalle minimal du catalogue.
    Measures = @{
        'disk.free'   = @{ RetentionDays = 365 }
        'net.latency' = @{ RetentionDays = 30 }
        'perf.cpu'    = @{ RetentionDays = 7; IntervalMinutes = 10 }
        'update.lock' = @{ RetentionDays = 365 }
    }
}
```

Résolution en un seul endroit (`Get-HistoryConfig` dans `common.ps1`) : catalogue → global →
mesure, la plus spécifique gagne — même logique de couches que la config (D33). `RetentionDays = 0`
sur une mesure = ne pas l'échantillonner (le fichier existant n'est pas supprimé : détruire
une archive reste un geste manuel et volontaire).

## 6. Restitution dans l'interface

### Sparkline dans la carte

- Le contrat gagne une propriété **optionnelle** sur un champ : `measureId` (posée par
  `New-Field -MeasureId`). Un champ qui la porte est historisé ; le front affiche alors une
  **sparkline** discrète sous la valeur (SVG inline, ~90 × 24 px, la couleur du statut du
  champ), avec au survol la valeur min/max/dernière de la fenêtre.
- Un clic sur la sparkline déplie une vue plus grande **dans la carte** (même mécanique que
  les tableaux dépliables existants) avec choix de fenêtre : 24 h / 7 j / 30 j / tout.
- Les `event` ne donnent pas une courbe mais une **ligne de faits** : « 3 redémarrages WSL
  sur 7 jours, dernier le 22/08 à 14 h 02 ». C'est un texte, pas un graphique — un
  escalier de deux états n'apprend rien de plus.

### Endpoint

`GET /api/v1/history/{measureId}?window=7d` (contrat ajouté à `openapi.yaml`) :

```json
{ "measureId": "disk.free", "kind": "gauge", "unit": "Go", "window": "7d",
  "points": [ { "at": "…", "v": 212.4 }, … ],
  "summary": { "count": 336, "min": 208.1, "max": 215.0, "first": 214.8, "last": 212.4 } }
```

- **Décimation côté serveur** : au plus ~200 points rendus, par godets (moyenne + min/max
  par godet) — le front ne reçoit jamais 50 000 lignes ;
- le front ne lit **jamais** les fichiers JSONL : le contrat reste la seule frontière.

### Ce que le front ne fait pas

Pas de page « graphiques » dédiée dans la cible initiale : l'historique sert les cartes
existantes (tendance là où vit la valeur), conformément à l'esprit du tableau de bord. Une
vue dédiée pourra venir ensuite si l'usage la réclame — décision produit à part.

## 7. Quand une dérive devient un avertissement

Règle D49 : un `warn` **doit** proposer une solution (`FixAction`) ou un guide. Une dérive
sans issue proposée resterait du bruit.

**Où** : dans la **sonde** concernée, à son recalcul — c'est elle qui possède le statut de
ses champs, et elle tourne déjà. Elle appelle un helper de lecture
(`Get-MeasureTrend -MeasureId … -Window …` : pente, min/max, comparaison à une base) qui ne
lit que la fin du fichier. Coût : quelques millisecondes, aucun processus de plus.

Dérives câblées dans la cible, chacune avec son issue :

| Dérive | Détection | Ce que dit le warning (D49 : constat, enjeu, issues) |
|---|---|---|
| **Disque se remplit** | pente de `disk.free` sur 30 j croise le seuil (60 Go) dans moins de N jours | « Au rythme des 30 derniers jours (−1,2 Go/j), le seuil sera atteint vers le 12/10. » `FixAction: disk-cleanup` + guide de libération |
| **WSL instable** | plus de N passages Actif→Inactif non demandés sur 7 j | « WSL s'est arrêté 5 fois cette semaine. » Guide : journaux WSL, `wsl --shutdown` propre, mise à jour du noyau |
| **Latence dégradée** | médiane 7 j > 2× la médiane 30 j | « La latence a doublé par rapport au mois écoulé. » `FixAction: net-speedtest` (remesurer) + guide box/câble |
| **Verrou levé longtemps** | `update.lock` ouvert depuis plus de N h | « Le verrou Windows Update est levé depuis 26 h — les redémarrages forcés sont possibles. » `FixAction: update-mode-on` |
| **Sonde qui s'alourdit** | `probe.duration` médiane 7 j > 2× la base | signalé **dans les logs et le journal** d'abord ; en carte seulement si un module « santé de Vigie » voit le jour (hors périmètre initial) |

Les **seuils** de ces règles vivent avec la règle, en tête de la sonde concernée (même
esprit que `$inactiveSeverity` de D20 : un choix produit rebasculable en une ligne), pas
dans `config.psd1` — ce ne sont pas des valeurs propres à une machine.

**Garde-fous** : jamais de dérive calculée sur moins de points qu'il n'en faut (pas de
projection sur 3 échantillons) ; l'absence d'historique n'est **pas** un warning (contrairement
à une valeur absente, D49-1 : ici l'information n'est pas manquante, elle est jeune) ; une
dérive revenue à la normale éteint le warning au recalcul suivant, sans mémoire rancunière.

## 8. Ce que cette conception s'interdit

- Exécuter des sondes plus souvent, planifier des réveils, ou allonger le recalcul
  perceptiblement (l'échantillonnage est un append + un index, quelques ms).
- Une base de données, un format binaire, une dépendance externe (D06).
- Écrire l'historique depuis les sondes elles-mêmes, ou le lire depuis le front autrement
  que par le contrat.
- Mêler historique et cache : `Remove-ProbeCache` et un vidage de `var/cache/` ne doivent
  jamais toucher `var/history/`.
