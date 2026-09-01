# Development

[Documentation index](../README.md) · [Français](../../fr/README.md)

This section is for people who read or change the code. If you only want to *use* Vigie,
everything you need is in the [user documentation](../README.md#for-users).

---

## Repository layout

```
README.md / README.fr.md   Entry points (EN / FR)
VERSION                    The product version number, and nowhere else
config/common.psd1         Settings shared by every local server of the repository
apps/
  backend-pode/            The application server (PowerShell + Pode)
    api/openapi.yaml         THE REST CONTRACT — source of truth
    lib/common.ps1           Shared helpers: state, cache, config, elevation, jobs
    probes/<theme>/*.probe.ps1     Read state, one card each
    actions/<id>.action.ps1        Side effects, one button each
    workers/*.worker.ps1           Long jobs, detached
    config/                        config.psd1 + config.local.sample.psd1
  frontend-web/index.html  The whole front end: one static HTML file
    mock/state.json          Sample state, used when the API is unreachable
  tray/tray.ps1            The system-tray app (WinForms) + assets/
  atelier/                 Internal visual-validation tool (PHP) — not part of the product
scripts/                   install, run, autostart, uninstall, tray control, git hooks
  build-release.ps1          Builds the distribution archive
doc/                      This documentation + the project's internal working documents
dist/                      Build output (git-ignored)
```

## Development dependencies

Anything the work needs is a **dependency**, and a dependency is declared and installed by a script — never by hand on
one machine, which teaches the next machine nothing. `scripts/dev/install-dev.ps1` holds the list, each entry with the
reason it is there.

```powershell
pwsh -File .\scripts\dev\install-dev.ps1 -Lister   # what is here, what is missing — changes nothing
pwsh -File .\scripts\dev\install-dev.ps1           # install what is missing (administrator terminal)
```

| Tool | What it is for here |
|---|---|
| **Git** | `build-release.ps1` lists files with `git ls-files`, which is what keeps ignored files out of the archive; also backs the update's `clone` route |
| **GitHub CLI** (`gh`) | publishing a release and attaching the archive to it |
| **PHP** | serving the Atelier (`apps/atelier`), the visual-validation tool — deliberately confined to tooling, never part of the app |

Installs go **machine-wide**, never into one account's profile (**D79**). The script stops short of `gh auth login`:
opening a GitHub session uses your own credentials, and that is your gesture, not a script's.

These are development dependencies only. None of them is needed to *use* Vigie, and none of them ships in the
distribution archive. What the application itself needs is handled by `scripts/install.ps1`.

## Running from source

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\install.ps1   # prerequisites, once
pwsh -ExecutionPolicy Bypass -File .\scripts\run.ps1       # start (elevates via UAC)
```

The front end alone, without the server, falls back to `apps/frontend-web/mock/state.json`
— but **serve it over HTTP**, never open it as `file://`: relative asset paths break and
the browser refuses to frame the page.

## Two things never to confuse

| | **Vigie** | **Atelier** |
|---|---|---|
| Nature | the **product** | an internal **development tool** |
| Purpose | watch and steer the PC | judge by eye what no parser can validate |
| Server | PowerShell + Pode | PHP (`php -S`) |
| Port | **47600** | **47610** |
| Elevated | **yes** (`RunLevel Highest`) | **never** |
| Started by | the `Vigie` scheduled task, at logon | by hand |
| Access to probes, actions, secrets | yes | **none** |

**Why PowerShell stays the application's server, and not PHP:**

1. **Elevation.** The Windows Update lock applies ACLs, disables scheduled tasks and
   writes to `HKLM`. Whatever serves the API has to be elevated — and an HTTP server
   running as administrator is a far wider attack surface than a dedicated PowerShell
   process.
2. **Concurrency.** `php -S` handles **one request at a time** (measured: 2 s alone,
   4.0 s with two). The UI refreshes card by card and polls; one slow probe would block
   everything else.
3. **Process cost.** A cold `pwsh` costs **~350 ms** before doing any work. With 12
   probes, one process per probe would mean **~4.2 s** of pure startup on every full
   refresh. Everything lives in an already-warm runtime instead: `/health` answers in
   **65 ms**.

PHP is deliberately confined to tooling. See [`apps/atelier/README.md`](https://github.com/Cartman34/vigie-windows/blob/main/apps/atelier/README.md).

## Conventions

- **The code is in English; French is the language of prose.** Identifiers, file names
  and symbols in English; the project's internal documents and decision records in French.
- **No duplication.** A value is defined in one place and derived everywhere else. A
  subject is documented in one place and linked from everywhere else.
- **Always handle errors, output and exit code** — through the shared `Invoke-Native`.
- **Idempotent scripts.** Running one twice must be harmless.
- **PowerShell 7 and UTF-8 with accents**, except the launchers (`.cmd`, `.vbs`), which
  stay **pure ASCII**.
- **Check prerequisites up front**, and **verify before saying "done"** — never report a
  validation you did not run.
- **Check the result, do not trust the return code.** After a change, re-read the system
  and report what you actually obtained.

Full detail: [`doc/en/developing/conventions.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/conventions.md) and
[`doc/en/developing/technologies.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/technologies.md) (French).

## How to validate a change

| What | How |
|---|---|
| PowerShell | `[System.Management.Automation.Language.Parser]::ParseFile(...)` on every modified `.ps1` / `.psd1`, and report the real output |
| Front-end JavaScript | load the page **over HTTP** in a browser and read the console. A syntax error kills the whole `<script>` block, so checking that a constant defined at the end exists proves the file parses |
| Launchers | `.cmd` and `.vbs` must stay byte-for-byte ASCII |
| Anything visual | the Atelier — see [`apps/atelier/README.md`](https://github.com/Cartman34/vigie-windows/blob/main/apps/atelier/README.md) |

## Publishing a release

```powershell
pwsh -File .\scripts\build-release.ps1 -ListOnly   # see exactly what would ship
pwsh -File .\scripts\build-release.ps1             # produce dist/vigie-<version>.zip
```

The version number comes from the **last git tag**, and from nowhere else (**D96**). Releasing therefore reads:

```powershell
git tag -a v0.1.9 -m "..."   # tags are posted at release time, never on every commit
git push origin v0.1.9
pwsh -File .\scripts\build-release.ps1
gh release create v0.1.9 --title "Vigie v0.1.9" --notes "..." dist/vigie-0.1.9.zip
```

Add `--prerelease` for a version that is published but not yet recommended — GitHub then keeps it out of
`releases/latest`, which is exactly what Vigie's own update route reads. The
[workflow below](#automating-it-the-release-workflow) does all of this on its own once it is installed.

**How the archive stays clean.** The file list comes from `git ls-files`, never from
walking the disk. Anything `.gitignore` ignores — the API token, `var/`, logs,
`config.local.psd1`, `*.bak-*` — is therefore never even a candidate; you cannot forget to
exclude what was never offered. On top of that, a deny-list drops files that *are*
versioned but do not belong in a user's hands (the Atelier, maintainer scripts, the
internal working documents); each rule carries its reason in the script. Finally a guard
rail scans the list, and then the produced archive, and aborts with exit code `2` rather
than shipping a doubt.

Consequence to keep in mind: excluding a file breaks every documentation link that pointed
at it. Such links are written as absolute GitHub URLs, and the build warns about any that
still resolve nowhere inside the archive.

Exit codes: `0` built, `1` prerequisite missing, `2` forbidden file detected (nothing
written), `3` build failure.

### Automating it: the release workflow

The repository carries no `.github/workflows/` directory. GitHub refuses a push that adds
or changes a workflow file unless the credential doing the pushing holds the **workflow**
scope, and the token this project pushes with does not. The workflow therefore lives here,
in full, rather than half-committed somewhere it cannot be updated.

Two ways to install it, both one-off:

- **Through the GitHub web interface** — *Actions* → *New workflow* → *set up a workflow
  yourself*, name the file `release.yml`, paste the block below, commit. The web interface
  is not subject to the token's scope.
- **Or grant the scope** — give the token **Workflows: read and write** (fine-grained
  token: *Repository permissions* → *Workflows*), then commit the file to
  `.github/workflows/release.yml` and push normally.

It uses only `actions/checkout` (maintained by GitHub) and `gh`, which is preinstalled on
`windows-latest`. Note that it has never been executed — it is written, not proven.

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

What it guarantees: a tag that disagrees with `VERSION` stops the run before anything is
built; the archive is checked to exist before the Release is created; and while the
version is `0.x`, the Release is marked pre-release.

## Never commit

`apps/backend-pode/var/secrets/` (the API token), `apps/backend-pode/var/cache/`,
`apps/*/var/log/`, `*.bak-*`. `.gitignore` covers them; check `git status` anyway.

## Going deeper

- [Glossary](glossary.md) — the project's words, one notion per word (in French, like the rest of the internal docs)
- [Architecture](architecture.md) — contract-first, the four apps, the request path
- [Probes and actions](probes-and-actions.md) — add a card or a button
- [Debugging](debugging.md) — one procedure, the same every time (`scripts/dev/debug.ps1`)
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml) — the contract itself

## The project's internal documents (French)

Working memory, not user documentation — read them before proposing a change that
reverses a settled decision.

- [`doc/progress/decisions.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/decisions.md) — every settled decision, numbered `D01`…, with the reasoning and the discarded alternatives
- [`doc/en/agent-working/briefing.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/agent-working/briefing.md) — where the project stands, and the backlog
- [`CHANGELOG.md`](../../../CHANGELOG.md)
- [`doc/progress/targeting/features.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/targeting/features.md) — target features by ID · [`doc/progress/implemented/status.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/implemented/status.md) — what is really implemented, by the same IDs
- [`doc/en/developing/security-review.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/security-review.md) — the internal security review
