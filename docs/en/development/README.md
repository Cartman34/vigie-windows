# Development

[Documentation index](../README.md) · [Français](../../fr/developpement/README.md)

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
docs/                      This documentation + the project's internal working documents
```

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

PHP is deliberately confined to tooling. See [`apps/atelier/README.md`](../../../apps/atelier/README.md).

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

Full detail: [`docs/conventions.md`](../../conventions.md) and
[`docs/technologies.md`](../../technologies.md) (French).

## How to validate a change

| What | How |
|---|---|
| PowerShell | `[System.Management.Automation.Language.Parser]::ParseFile(...)` on every modified `.ps1` / `.psd1`, and report the real output |
| Front-end JavaScript | load the page **over HTTP** in a browser and read the console. A syntax error kills the whole `<script>` block, so checking that a constant defined at the end exists proves the file parses |
| Launchers | `.cmd` and `.vbs` must stay byte-for-byte ASCII |
| Anything visual | the Atelier — see [`apps/atelier/README.md`](../../../apps/atelier/README.md) |

## Never commit

`apps/backend-pode/var/secrets/` (the API token), `apps/backend-pode/var/cache/`,
`apps/*/var/log/`, `*.bak-*`. `.gitignore` covers them; check `git status` anyway.

## Going deeper

- [Architecture](architecture.md) — contract-first, the four apps, the request path
- [Probes and actions](probes-and-actions.md) — add a card or a button
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml) — the contract itself

## The project's internal documents (French)

Working memory, not user documentation — read them before proposing a change that
reverses a settled decision.

- [`docs/DECISIONS-VALIDEES.md`](../../DECISIONS-VALIDEES.md) — every settled decision, numbered `D01`…, with the reasoning and the discarded alternatives
- [`docs/REPRISE.md`](../../REPRISE.md) — where the project stands, and the backlog
- [`SUIVI.md`](../../../SUIVI.md), [`CHANGELOG.md`](../../../CHANGELOG.md)
- [`docs/targeting/features.md`](../../targeting/features.md) — target features by ID · [`docs/implemented/status.md`](../../implemented/status.md) — what is really implemented, by the same IDs
- [`docs/operating/SECURITY.md`](../../operating/SECURITY.md) — the internal security review
