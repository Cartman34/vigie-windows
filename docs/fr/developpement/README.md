# Développement

[Sommaire](../README.md) · [English](../../en/development/README.md)

Cette section s'adresse à qui lit ou modifie le code. Pour simplement *utiliser* Vigie,
tout est dans la [documentation utilisateur](../README.md#pour-lutilisateur).

---

## Arborescence du dépôt

```
README.md / README.fr.md   Points d'entrée (EN / FR)
VERSION                    Le numéro de version du produit, et nulle part ailleurs
config/common.psd1         Réglages partagés par tous les serveurs locaux du dépôt
apps/
  backend-pode/            Le serveur applicatif (PowerShell + Pode)
    api/openapi.yaml         LE CONTRAT REST — source de vérité
    lib/common.ps1           Helpers partagés : état, cache, config, élévation, tâches
    probes/<theme>/*.probe.ps1     Lecture d'état, une carte chacune
    actions/<id>.action.ps1        Effets de bord, un bouton chacun
    workers/*.worker.ps1           Tâches longues, détachées
    config/                        config.psd1 + config.local.sample.psd1
  frontend-web/index.html  Tout le front : un fichier HTML statique
    mock/state.json          État d'exemple, servi quand l'API est injoignable
  tray/tray.ps1            L'app de la barre système (WinForms) + assets/
  atelier/                 Outil interne de validation visuelle (PHP) — hors produit
scripts/                   install, run, démarrage auto, désinstallation, pilote du tray, hooks git
  build-release.ps1          Fabrique l'archive de distribution
docs/                      Cette documentation + les documents de travail internes
dist/                      Sortie de fabrication (ignorée par git)
```

## Lancer depuis les sources

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\install.ps1   # prérequis, une fois
pwsh -ExecutionPolicy Bypass -File .\scripts\run.ps1       # démarre (s'élève via UAC)
```

Le front seul, sans serveur, se replie sur `apps/frontend-web/mock/state.json` — mais
**servez-le en HTTP**, jamais en `file://` : les chemins relatifs des ressources cassent et
le navigateur refuse d'afficher la page dans un cadre.

## Deux choses à ne jamais confondre

| | **Vigie** | **Atelier** |
|---|---|---|
| Nature | le **produit** | un **outil de développement** interne |
| À quoi ça sert | surveiller et piloter le PC | juger à l'œil ce qu'aucun parseur ne valide |
| Serveur | PowerShell + Pode | PHP (`php -S`) |
| Port | **47600** | **47610** |
| Élévation | **oui** (`RunLevel Highest`) | **jamais** |
| Lancé par | la tâche planifiée `Vigie`, à l'ouverture de session | à la main |
| Accès aux sondes, actions, secrets | oui | **aucun** |

**Pourquoi PowerShell reste le serveur de l'application, et pas PHP :**

1. **L'élévation.** Le verrou Windows Update pose des ACL, désactive des tâches planifiées
   et écrit dans `HKLM`. Ce qui sert l'API doit donc être élevé — et un serveur HTTP
   tournant en administrateur est une surface d'attaque bien plus large qu'un processus
   PowerShell dédié.
2. **La concurrence.** `php -S` traite **une requête à la fois** (mesuré : 2 s seule, 4,0 s
   à deux). L'interface rafraîchit carte par carte et interroge en boucle : une sonde lente
   bloquerait tout le reste.
3. **Le coût des processus.** Un `pwsh` froid coûte **~350 ms** avant de travailler. À 12
   sondes, un appel par sonde ferait **~4,2 s** de pur démarrage à chaque rafraîchissement
   complet. Tout vit dans un runtime déjà chaud : `/health` répond en **65 ms**.

PHP est volontairement cantonné à l'outillage. Voir
[`apps/atelier/README.md`](https://github.com/Cartman34/vigie-windows/blob/main/apps/atelier/README.md).

## Conventions

- **On parle français, le code est en anglais.** Identifiants, noms de fichiers et symboles
  en anglais ; les documents internes et les décisions en français.
- **Pas de duplication.** Une valeur n'est définie qu'à un endroit, tout en dérive. Un sujet
  n'est documenté qu'à un endroit, tout y renvoie.
- **Toujours traiter erreurs, sortie et code retour** — via `Invoke-Native`, partagé.
- **Scripts idempotents.** Relancer un script doit être sans conséquence.
- **PowerShell 7 et UTF-8 avec accents**, sauf les lanceurs (`.cmd`, `.vbs`), qui restent
  **ASCII pur**.
- **Vérifier les prérequis en amont**, et **valider avant de dire « prêt »** — ne jamais
  rapporter une validation qu'on n'a pas faite.
- **Constater le résultat, ne pas croire le code de retour.** Après un changement, relire le
  système et rapporter ce qu'on a réellement obtenu.

Le détail : [`docs/conventions.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/conventions.md) et
[`docs/technologies.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/technologies.md).

## Comment valider un changement

| Quoi | Comment |
|---|---|
| PowerShell | `[System.Management.Automation.Language.Parser]::ParseFile(...)` sur chaque `.ps1` / `.psd1` modifié, et on rapporte la sortie réelle |
| JavaScript du front | charger la page **en HTTP** dans un navigateur et lire la console. Une erreur de syntaxe empêche l'exécution de tout le bloc `<script>` : vérifier qu'une constante définie en fin de fichier existe prouve que le fichier parse |
| Lanceurs | `.cmd` et `.vbs` doivent rester ASCII, octet par octet |
| Tout ce qui est visuel | l'Atelier — voir [`apps/atelier/README.md`](https://github.com/Cartman34/vigie-windows/blob/main/apps/atelier/README.md) |

## Publier une version

```powershell
pwsh -File .\scripts\build-release.ps1 -ListOnly   # voir exactement ce qui partirait
pwsh -File .\scripts\build-release.ps1             # produit dist/vigie-<version>.zip
```

Le nom de l'archive vient du fichier `VERSION`, et de nulle part ailleurs. Pour publier :
incrémenter `VERSION`, committer, pousser le tag correspondant (`v0.1` pour `0.1`), lancer
le script, et attacher `dist/vigie-<version>.zip` à la Release GitHub. Le
[workflow ci-dessous](#automatiser--le-workflow-de-publication) fait tout cela seul, une
fois installé.

**Comment l'archive reste propre.** La liste des fichiers vient de `git ls-files`, jamais
d'un parcours du disque. Tout ce que `.gitignore` ignore — le jeton d'API, `var/`, les
journaux, `config.local.psd1`, les `*.bak-*` — n'est donc même pas candidat : on ne peut
pas oublier d'exclure ce qui n'a jamais été proposé. Par-dessus, une liste d'exclusions
retire ce qui **est** versionné mais n'a rien à faire chez un utilisateur (l'Atelier, les
scripts de mainteneur, les documents de travail internes) ; chaque règle porte sa raison
dans le script. Enfin un garde-fou relit la liste, puis l'archive produite, et s'arrête
avec le code `2` plutôt que de livrer un doute.

Conséquence à garder en tête : exclure un fichier casse tous les liens de documentation
qui le visaient. Ces liens sont écrits en URL GitHub absolue, et la fabrication signale
ceux qui ne résolvent plus nulle part dans l'archive.

Codes de retour : `0` fabriquée, `1` prérequis manquant, `2` fichier interdit détecté
(rien n'est écrit), `3` échec de fabrication.

### Automatiser : le workflow de publication

Le dépôt ne porte pas de dossier `.github/workflows/`. GitHub refuse un push qui ajoute ou
modifie un fichier de workflow si l'identifiant qui pousse n'a pas la portée **workflow**,
et le jeton avec lequel ce projet pousse ne l'a pas. Le workflow vit donc ici, en entier,
plutôt qu'à moitié committé à un endroit où il ne pourrait plus être mis à jour.

Deux façons de l'installer, l'une comme l'autre en une fois :

- **Par l'interface web de GitHub** — *Actions* → *New workflow* → *set up a workflow
  yourself*, nommer le fichier `release.yml`, coller le bloc ci-dessous, committer.
  L'interface web n'est pas soumise à la portée du jeton.
- **Ou accorder la permission** — donner au jeton **Workflows: read and write** (jeton
  *fine-grained* : *Repository permissions* → *Workflows*), puis committer le fichier dans
  `.github/workflows/release.yml` et pousser normalement.

Il n'utilise que `actions/checkout` (maintenue par GitHub) et `gh`, préinstallé sur
`windows-latest`. À savoir : il n'a jamais été exécuté — il est écrit, pas éprouvé.

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write        # necessaire pour creer la Release et y attacher l'archive

jobs:
  release:
    runs-on: windows-latest

    steps:
      - name: Recuperer les sources
        uses: actions/checkout@v4
        # Le script lit la liste des fichiers avec « git ls-files » : il lui faut un vrai
        # depot git, c'est exactement ce que fournit ce checkout.

      - name: Verifier que le tag correspond au fichier VERSION
        shell: pwsh
        run: |
          # Le numero de version n'a qu'UNE definition : le fichier VERSION (D15). Le tag
          # doit s'y conformer, sinon la Release s'appellerait autrement que son archive.
          $version = "$(Get-Content -LiteralPath VERSION -Raw)".Trim()
          $tag = "${{ github.ref_name }}"
          $attendu = "v$version"
          if ($tag -ne $attendu) {
            Write-Host "::error::Le tag '$tag' ne correspond pas au fichier VERSION ('$version', soit '$attendu'). Mets à jour VERSION, ou retire et repose le tag."
            exit 1
          }
          Write-Host "Tag '$tag' conforme au fichier VERSION."
          "version=$version" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8

      - name: Fabriquer l'archive
        shell: pwsh
        run: |
          # Le script s'arrete de lui-meme (code 2) si un fichier interdit approche de
          # l'archive : aucun controle n'est repris ici, il vivrait en double.
          ./scripts/build-release.ps1
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

      - name: Publier la Release
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          # On constate le resultat avant de publier, on ne se fie pas au seul code de
          # retour de l'etape precedente (D43).
          $zip = "dist/vigie-$env:version.zip"
          if (-not (Test-Path -LiteralPath $zip)) {
            Write-Host "::error::Archive introuvable : $zip"
            exit 1
          }
          Write-Host ("Archive : {0} ({1:N0} octets)" -f $zip, (Get-Item $zip).Length)

          $arguments = @(
            'release', 'create', "${{ github.ref_name }}", $zip,
            '--title', "Vigie ${{ github.ref_name }}",
            '--generate-notes'
          )
          # Tant que Vigie est en 0.x, rien n'est presente comme une version stable.
          if ($env:version.StartsWith('0.')) { $arguments += '--prerelease' }
          gh @arguments
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

Ce qu'il garantit : un tag en désaccord avec `VERSION` arrête l'exécution avant toute
fabrication ; l'existence de l'archive est constatée avant de créer la Release ; et tant
que la version est en `0.x`, la Release est marquée avant-première.

## À ne jamais committer

`apps/backend-pode/var/secrets/` (le jeton d'API), `apps/backend-pode/var/cache/`,
`apps/*/var/log/`, `*.bak-*`. Le `.gitignore` les couvre ; vérifiez `git status` malgré tout.

## Pour aller plus loin

- [Architecture](architecture.md) — contract-first, les quatre apps, le chemin d'une requête
- [Sondes et actions](sondes-et-actions.md) — ajouter une carte ou un bouton
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml) — le contrat lui-même

## Les documents de travail internes

Mémoire du projet, pas documentation d'usage — à lire avant de proposer un changement qui
reviendrait sur une décision déjà tranchée.

- [`docs/DECISIONS-VALIDEES.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/DECISIONS-VALIDEES.md) — chaque décision tranchée, numérotée `D01`…, avec le raisonnement et les pistes écartées
- [`docs/REPRISE.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/REPRISE.md) — où en est le projet, et le backlog
- [`SUIVI.md`](https://github.com/Cartman34/vigie-windows/blob/main/SUIVI.md), [`CHANGELOG.md`](../../../CHANGELOG.md)
- [`docs/targeting/features.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/targeting/features.md) — les fonctionnalités cibles par ID · [`docs/implemented/status.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/implemented/status.md) — ce qui est réellement fait, avec les mêmes ID
- [`docs/operating/SECURITY.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/operating/SECURITY.md) — la revue de sécurité interne
