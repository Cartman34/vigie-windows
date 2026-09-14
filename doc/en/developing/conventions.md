# Project conventions

The single reference for conventions. Every new convention is written HERE.

**The project's words live in [glossary.md](glossary.md)**: one notion, one word, the same everywhere. A missing word is
added there BEFORE it is used -- a synonym that settles in ends up meaning something else.

## Language

Two languages, a clear border. It runs between what the MACHINE reads and what a HUMAN reads.

### In English, without exception
- **Names**: functions, variables, parameters, properties, hashtable keys, classes.
- **File and folder names**, including for French content.
- **Contract identifiers**: ids of modules, actions, fields, resources.
- **Configuration keys** (`UpdateSource`, `ToolsPath`...).

### In English too: comments
They live INSIDE the code, they are part of it, and they are read with it. This page long said the opposite -- it had
been written against the intended rule (**D115**). Code already written carries French comments: they are converted as
files are touched, without a big clean-up, and a ratchet forbids adding any.

### In French, just as deliberately
- **Displayed labels**: card titles, values, buttons, error messages, help. With their accents (see below) -- they are
  what the user sees.
- **Log messages**: they are read during troubleshooting, by the same reader.
- **The documentation** of `doc/fr/` and `progress/`, the notes of `notes/`, `CHANGELOG.md` and `README.fr.md`.

### A document's language follows its folder
`doc/en/` and `README.md` are written in English; what is named just above, in French. `scripts/dev/check-language.ps1`
checks it. Documents still in French under `doc/en/` would be listed there: the list only goes down as they are
translated, and none is added.

### The wording of labels
A label addresses nobody when a neutral wording exists: « Windows demandera ensuite l'autorisation administrateur »
rather than « Si vous continuez, Windows vous demandera l'autorisation ». When avoiding it becomes awkward, use
« vous »; never « tu ». No capitals for insistence: « VOTRE » reads as a shout.

### The only exception allowed
A **domain term** with no established English equivalent. This project is technical: there are almost none, and the
exception must be justified each time, not assumed. "Sonde", "carte", "verrou", "liseré" all have a common English word.

### How we get there -- without a big clean-up
The rule was broken little by little: **310 French identifiers** on 28/08/2026. We do not rename everything at once --
it would drown `git blame` in noise and break code that works. We apply a **ratchet**:

```powershell
pwsh -File .\scripts\dev\check-naming.ps1            # the count must never go up
pwsh -File .\scripts\dev\check-naming.ps1 -Detail    # where they are
```

- **All NEW code follows the rule.** No discussion: that is what the ratchet checks.
- When a file is opened for another reason, what is touched is renamed, and the **ceiling is lowered** by as much in
  the script. It never goes back up.

**And if new code CALLS a French function that already exists?** The ratchet will not see it -- it counts declarations,
not calls. The rule is therefore explicit:

| Situation | What we do |
|---|---|
| All the calls are in files already being changed | **Rename.** It is the gradual catch-up, and it costs nothing more than the review done anyway. |
| The calls spread well beyond the current change | **Call it as is**, and SAY so in the report. Blowing up a diff for a rename turns a readable fix into an impossible review. |

What is never acceptable: **declaring** a new French name. A call is fixed later without breaking anything; a
declaration creates the debt.
- **French is the MASTER language of the user documentation.** A page of `fr/` is written or fixed FIRST; its `en/`
  counterpart is updated right after, never the other way round. When they diverge, `fr/` prevails. The same for the
  two root READMEs: `README.fr.md` leads, `README.md` follows.
- Documents that exist only in English (`en/developing/`, `agent-working/`) or only in French (`progress/`) fall outside
  this rule: without a twin, no master.

## Tree and naming
- Sources: see `../README.md`.
- Probe: `apps/backend-pode/probes/<theme>/<name>.probe.ps1`.
- Action: `apps/backend-pode/actions/<id>.action.ps1` (the `<id>` = the contract's `type` value).
- Timestamped reports: `<name>_YYYYMMDD_HHMMSS.txt` (+ `.json`).

## Contract first
- `apps/backend-pode/api/openapi.yaml` is the **source of truth**. Every API change is decided there BEFORE the code.
  The front end depends only on the contract; the back end is interchangeable.

## Probe / action model
- **Probe**: READ ONLY, fast, no side effect. Outputs ONE `Module` object (OpenAPI schema). Use the factories
  `New-ModuleObject` / `New-Field` / `New-Action` of `apps/backend-pode/lib/common.ps1`. Slow calls bounded by a timeout.
- **Action**: side effect. Signature `param([string]$Module,[hashtable]$Params)`. Returns `@{ message=...; result=... }`.
  Reuses existing tooling (`LocalAgentAdmin/tools/`) rather than reimplementing.
- Allowed statuses: `ok` | `warn` | `error`.
- Field types (`kind`): `bool` | `number` | `text` | `date` (+ optional `unit`).

## Security
- API listening on **127.0.0.1 only**. Never exposed (the back end runs elevated).
- **Bearer token** generated once (`apps/backend-pode/var/secrets/api.token`), required on every endpoint except
  `/health`. Injected into the served page (same origin).

## Technical
- Pode isolates routes in runspaces: context travels through **environment variables** (`VIGIE_BACKEND`,
  `VIGIE_TOKEN`); each route re-sources `lib/common.ps1`. (See `technologies.md`.)
- Scheduled task scripts: **idempotent** (`Register-ScheduledTask -Force`).
- Always **check prerequisites up front** (rights, modules, runtime).

## Line length
- **200 characters**, code and documentation. A line breaks because it changes idea, not because an arbitrary counter
  rang: breaking at 80 or 100 chops Windows paths, tables and strings, and makes diffs unreadable.
- **Exception**: a markdown table line is not broken -- breaking it breaks the table. It runs over, so be it.
- **Fixed as we go**: files already touched for another reason are brought back to 200. No global reformatting pass,
  which would drown the history in noise.

## Three verified traps, and their remedy

Each cost half a day. They do not show on review: they show in production, late.

- **A cache NEVER carries a state that must be read now.** The account list is expensive to build: it is cached. The
  state of their startup task is cheap to read, and it changes: it is read again at every call. A cache that lies never
  lies about what has consequences.
- **Writing a missing property THROWS.** An object returned by `ConvertFrom-Json` has a frozen shape; adding a field
  fails, and the stale value stays. When that JSON comes from a cache written by an earlier version, every added field
  breaks silently. Remedy: `Set-ObjectProperty` (`lib/common.ps1`), which creates the property when it is missing.
- **We observe AFTER, not right away.** Windows returns a task's old state for a short moment after it is rewritten. An
  immediate check therefore declared a successful repair a failure. Let a breath pass before believing what is read.

## Documentation (absolute rule)
- **Everything is documented**: every convention (here), every technology (`technologies.md`), every feature and its
  use (`targeting/` + `implemented/` + `using/`).
- Documentation in 4 parts, **zero duplicates**, references by **ID** (see `README.md`).
- Every decision written in `progress/decisions.md` carries, under its title, **where it comes from**: *Demandée par
  l'utilisateur* (an explicit request or arbitration -- not reopened without him) or *Prise par l'agent* (a technical
  choice made alone -- one remark is enough to question it). They do not weigh the same: confusing them amounts to
  claiming an agreement that was never given.
- *Untraced origin*: sixteen old entries whose text does not say where they come from. They may be used -- but **when
  relying on one, if the doubt matters, confirmation is asked again** rather than an agreement assumed. Once confirmed,
  the entry is requalified on the spot: the question is not asked twice.
- The **resumption point** is `../agent-working/briefing.md`: kept up to date every session, there is only one.

## Device bridge
- Files handled through the bridge (mounted folder). **Deletion forbidden**: move (`mv`) instead of deleting.

## Idempotence (absolute rule)
**All** scripts are idempotent: replayable without side effect or error. In practice:
- Check the state BEFORE acting; redo nothing needlessly.
- Install only if absent (`install.ps1`).
- Do not restart a service already started (`start.ps1`/`run.ps1` test the port through `Test-ServerUp`).
- Scheduled tasks: `Register-ScheduledTask -Force`.
- Configuration changes: set the target value (no blind toggle).

## Ports (organisation)
- Reserved local range: **47600-47699**. Central register: `LocalWork/PORTS.md`.
- Each project: **one fixed port**, configurable (here `apps/backend-pode/config/config.psd1`), written in the register;
  check the register before allocating.
- This project's default: **47600**.

## Script encoding (PowerShell 5.1 compatibility)
Windows PowerShell 5.1 reads `.ps1`/`.psd1` as ANSI (Windows-1252), not UTF-8: any non-ASCII character (accents, em
dash, curly quotes) breaks string parsing. Rule: **PowerShell scripts in pure ASCII** (French comments without accents,
plain `-`, straight quotes). Check: `grep -rlP '[^\x00-\x7F]' --include='*.ps1' --include='*.psd1'` must be empty.

## PowerShell 7 + UTF-8 (update, replaces the ASCII constraint)
- **Target: PowerShell 7 (pwsh)**; the launchers `install/start/run.ps1` **switch back to pwsh automatically** when
  called from 5.1. `install.ps1` installs PS7 (winget) when it is missing.
- Under PS7, files are **UTF-8**: **accents are allowed** in scripts (probes, actions, lib, server).
- **Exception**: the 3 launchers (`install/start/run.ps1`) stay **ASCII**, since 5.1 must be able to read them long
  enough to switch to pwsh.
- Recommended write encoding: UTF-8 (with BOM if edited on Windows).

## Logging (recoverable logs)
- Everything is written under **`apps/*/var/log/`** (recoverable through the bridge for diagnosis).
- `install.ps1` / `start.ps1`: full transcript (`install_*.log`, `start_*.log`) + `Write-Log` lines (helper of
  `lib/common.ps1`).
- Pode server: error and request logs (`pode-error_*.log`, `pode-request_*.log`) through Pode's logging.
- Rule: a script that can fail **logs** its error to a file (not only on screen), to be diagnosed without copy-paste.

## Cross-cutting rules (2026-08-20)

### 1. No duplication: one feature = one piece of code
All shared logic lives in `apps/backend-pode/lib/common.ps1` and is reused, never copied. Shared helpers in place:
- `Test-Elevated`: is the process an administrator? (used by run/start/install + probes)
- `Test-UpdateTasksAclLock`: is the ACL lock (SYSTEM denied) in place? Compared by **SID** (`S-1-5-18`), independent of
  the language. Used by `lock.probe` AND the action `update-mode-off`.
- `Invoke-Native`: runs a native command and returns `{ Ok; ExitCode; Output }`. Its arguments are **raw**: the call
  operator quotes them itself.
- `Start-ChildProcess`: the **only** road to launch a process with arguments (**D116**). It is given **raw** values; it
  quotes them through `ConvertTo-ProcessArgument`, following the rules of `CommandLineToArgvW`. A direct
  `Start-Process` is refused by `check-probes`.
- `ConvertTo-ProcessArgument` / `ConvertTo-PSLiteral`: two worlds, two escapings -- a value in a Windows **command
  line**, a value in **PowerShell source** built as text.
On the front end, rendering a card is centralised in `cardHtml(m, groupLabel)` (reused by the full render AND the
per-card refresh).

### 2. Always handle errors, output and return codes
Every call to a command / a service / a script must:
- capture the output (stdout + stderr, e.g. `2>&1`),
- check the return code (`$LASTEXITCODE` for .exe, `try/catch` for cmdlets),
- log on failure, and report an honest result (never a false success).
Examples: `update-mode-off` really checks the lock is in place (helper) and logs `icacls`/`takeown`; actions return the
real `result.ok`; the front end shows « Réussi » only if `result.ok` is not `false`.
