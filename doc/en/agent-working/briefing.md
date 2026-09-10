# Vigie — resuming the project (read this first)

> **What this document is for (owner's instruction)**: to resume work after a lost session —
> **only what is useful right now**. No journal: the past lives in `git log` and
> `CHANGELOG.md`, the rules in `decisions.md`.

**This document is THE entry point, whatever the agent.** It assumes no particular tool: a
file loaded automatically by one agent or another (`CLAUDE.md` for Claude Code) is only an
**optional** shortcut to here, and never carries a rule that could not be found in this
repository. If that shortcut does not exist, nothing is lost — one just has to remember to
open this file.

**This document is read, and what follows applies.** It is not self-sufficient: it opens a
chain, and each link obliges the next.

1. `disciplines.md` — **in full**, to be held continuously. It is how one works here, not a
   list of tips. The first one in it, **NODO**, stops everything: the moment the owner writes
   that word, nothing changes until he lifts it. And the one that decides the product's
   quality: **a request is judged against the model**, never by bending what exists to fit
   the new thing in.
2. `../../progress/decisions.md` — the settled arbitrations. They **impose themselves**: one
   does not redesign over them, one searches first
   (`scripts/dev/decisions.ps1 -About "…"`).
3. `../../progress/targeting/` then `../../progress/implemented/` — the target, then the real
   state. A request from the owner is translated **into the target first**.

None of this is optional because one believes one remembers. **An agent whose context has
been compacted has nothing left but its summary**: the rules, the decisions and the design
have disappeared, and what it believes it knows of the repository has aged. First gesture on
return, before any conclusion, any deletion, any delivery:

```powershell
pwsh -File scripts/dev/restore-context.ps1          # the disciplines, the document map, the real state
pwsh -File scripts/dev/restore-context.ps1 -Court   # without the text of the disciplines
```

See the discipline "Coming back from a context compaction".

## The project

**Vigie**: a **local** dashboard for one Windows PC. Repository: `vigie-windows`.

> ⚠️ "HYPERION" is **not** a code name for the project: it is the **owner's machine name**.
> Every occurrence in code, identifiers or documentation is a **genericity defect** (a
> hard-coded machine value) to be removed, not an inheritance to keep.

- **PowerShell + Pode** back end (`apps/backend-pode/`), listens on **127.0.0.1:47600**,
  Bearer token + anti-CSRF + action whitelist.
- **Plain HTML/JS** front end (`apps/frontend-web/index.html`), serves the mock
  `apps/frontend-web/mock/state.json` if the back end is absent.
- **WinForms client app** (`apps/tray/tray.ps1`): tray icon = the app's status (gauge), menu,
  dedicated window (Edge/Chrome `--app`).
- The most intrusive capability, to be handled with care: **locking Windows Update** (ACL
  deny on SYSTEM over the task folders) to block forced restarts, without hiding real
  updates.

> **Do not confuse it with the Atelier.** "Vigie" = the application (PowerShell + Pode, port
> 47600, elevated). "**Atelier**" = the development tool (PHP, port 47610, never elevated,
> `apps/atelier/`). See **D28**, **D29** and `apps/atelier/README.md`.

## Permanent design rules

- **We speak French, the code is in English.**
- No duplication (shared helpers in `apps/backend-pode/lib/common.ps1`).
- **Always** handle errors + output + return code (`Invoke-Native`).
- Scripts are **idempotent**. **PS7 + UTF-8 with accents** (the launchers stay ASCII).
- **Open subjects are designated by their number** (`S01`, `S02`…) — the register is
  `notes/subjects.md`, and the owner answers by number. **An alert status is verified before
  being displayed**: a deliberate trade-off (HVCI off…) is described neutrally, it does not
  raise an alert — check the real state and THIS machine's constraints before asserting.
- **Check prerequisites up front.** **Validate before saying "ready"** (never invent a
  validation).
- **Ordinary tests = CONTRACT tests** (**D63**): parser + `check-probes.ps1` (read-only
  probes, invariants). Running an action or a worker for real, or driving the app end to end,
  is an integration test: it is **asked for**, every time.
- **Nothing consumes the machine without authorisation** (**D62**): GPU/CPU load, heavy test,
  benchmark — we ask EVERY time. A past permission does not carry over. Rare branches are
  validated by simulation (`VIGIE_FAKE_<WHAT>`).

### Validation disciplines — in this order, before any delivery

| What is touched | What is run | What it catches |
|---|---|---|
| a **module** (creation/evolution) | follow **`../developing/modules.md`** — THE reference, to be quoted in any subagent brief touching probes | a forgotten D48/D49/D57 rule |
| any `.ps1` | `[Parser]::ParseFile` on each file | the syntax, **nothing more** |
| a **probe** | `pwsh -File .\scripts\check-probes.ps1 -Only <probe\|module>` (dev, targeted — D51) then `-All` before delivery | the real execution + the **D49**/**D50** invariants |
| `apps/frontend-web/index.html` | reload the **served** page (`http://127.0.0.1:47600`) and read the console | JS syntax and runtime errors |
| a contract (`openapi.yaml`) | re-reading — no YAML parser on this machine | nothing automatic, to be said as such |

**The parser is not enough** (**D50bis**): a parameter passed twice gets through it without a
word and makes a card disappear at runtime. It happened, was delivered, and was announced as
done.

**A GUARDRAIL NOW EXISTS**: `scripts/check-probes.ps1` refuses any control character in
`apps/`, `scripts/`, `config/` and `doc/`, and names the file and the line. It was proven by
deliberately laying the trap. Run it after any scripted write.

**THE BACKSLASHES IN MY EDITING SCRIPTS GET EATEN** — an expensive trap, hit five times on
26/08. `\\` often arrives **single** in the written file, and `\t`, `\25`, `\b` become
**control characters** (tab, 0x15, backspace). Symptoms lived through: a `(^|\\)` regex that
silently did nothing and broke the whole account inventory; a CSS chevron displayed as "B8";
a path `apps\tray\tray.ps1` turned into tabs, and therefore not found. **Remedy**: do not
write a literal backslash when it can be avoided — nested `Join-Path`, `Split([char]92)`, a
chevron drawn in CSS — and read the written file back (`cat -A`) at the slightest doubt.

**Every scripted write of a source file is ATOMIC**: write to `file.tmp`, check the size,
then replace. A script that crashes mid-`write()` on a file opened for writing leaves a
**truncated** file — it happened on 24/08 (index.html at 0 bytes, committed and pushed to
main by the shell chain that followed). And never chain `git commit` after a script with a
plain newline: `&&` only.

**A rendered file (`.html`) is NEVER edited with the Edit/Write tools** (**D47**): the panel
preview then opens the file as `file://` and steals the owner's focus. Go through an exact
replacement script — and re-run the JS string guardrail afterwards (an unterminated
single-quoted string, a regular expression cut by a newline: two writing layers have already
eaten escapes).

**Redeploying** = commit on the branch, `git merge --ff-only` into `main` from the main
checkout, `git push origin main`, then ask the server for the update:

```powershell
pwsh -File scripts/dev/ask-vigie.ps1 -Type vigie-update -Module vigie
```

It fetches, builds, installs and restarts on its own. **Restarting the client app does NOT
restart the server**: the old one becomes an orphan and `$startServer` exits immediately
since the port answers — one then serves stale code indefinitely.

- **Touching a probe ⇒ run `scripts/check-probes.ps1`**: the parser does not see a parameter
  passed twice, execution does (**D50bis**).
- **Every settled decision is recorded in `../../progress/decisions.md`**, and a decision
  settled on figures deposits them in `notes/evidence/` (**D119**).

## Architecture (contract-first)

- `apps/backend-pode/api/openapi.yaml` = source of truth for the REST contract.
- Probe = `apps/backend-pode/probes/<theme>/*.probe.ps1`, returns 1 module OR an array of
  modules.
- Action = `apps/backend-pode/actions/<id>.action.ps1`, returns `@{ message; result }`.
  `result.invalidate=@('x.probe.ps1')` forces a recompute.
- Aggregation + cache (mtime+TTL, single-flight, serve-stale): `Get-State` in `common.ps1`.
- **Background tasks**: `Start-DetachedAction` (hidden pwsh worker); e.g. packages via
  `Start-PkgJob` + `apps/backend-pode/workers/pkg-job.worker.ps1`. A long action answers
  `result.async=$true` + `module`; the front end puts the card in "busy" and polls it until
  it finishes.

## Current state of the product (summary — the detail is in the code and the docs)

Vigie runs in production: elevated client app (a scheduled task it repairs itself) + Pode
server on 47600 + single-page front end + PHP Atelier on 47610 (launched by hand:
`pwsh -File apps/atelier/atelier.ps1`).

**Publisher: Sowapps; author: Florent HAZARD** (D72). Shared installation:
`C:\Program Files\Sowapps\Vigie`; per-account data: `%LOCALAPPDATA%\Sowapps\Vigie`.

**Installation (D81)**: a single entry point, **`setup.cmd` at the root**. It checks the
account is an administrator, elevates, installs PowerShell 7 **for the machine**
(`C:\Program Files\PowerShell\7` — winget no longer having an MSI package, the official MSI
is downloaded as a fallback), Pode, the token, this account's startup task, and launches
Vigie. Every return code is read.

**Delivery (D76)**: when a feature is finished, **I merge into `main`** — the server in his
session serves the repository, so it receives it directly (a new card appears on reload; a
new route waits for a server restart). The **other accounts** run
`C:\Program Files\Sowapps\Vigie`: they receive nothing without an **explicit deployment**,
which is asked for.

Modules: Windows Update (native lock, updates by choice grouped by maker, date of the last
scan), System (**Storage**: D57 threshold, background consumption analysis D60/D61, tree
requested **level by level**), **Accounts** (D67), Security, Network, WSL, Tools & packages,
Games (detection by facts: Game Bar, Steam library, engine, full screen — D64).

Settings (D56): notifications, modules **in an accordion** (D71), users, appearance, about.
**21 named notifications** declared by the modules (D68), filtered by rights with critical
cases surfaced (D70). Icons: in-house font (D58), bell after Font Awesome, puzzle, users —
board in the Atelier (`design-systeme.html`).

Desktop notifications go through **one door with several tools**
(`../../progress/targeting/notifications.md`): the client app describes an event, and the
first tool able to show it wins.

Reference docs: `../developing/modules.md` (create/maintain a module), `../developing/design.md`
(design system), `../../progress/decisions.md` (all the rules, D01→D120).

### Work queue

It lives in **`local/docs/`**, which is **never committed**: the state right now and the list
of what is left change every session and belong to this machine alone. This document carries
only what holds durably.

## The state of the owner's machine — to know before concluding anything

- **Windows Update is LOCKED** (`NoAutoUpdate=1`, ACL lock in place): this is wanted and was
  asked for. Vigie's actions lift the lock for the time it takes to act, then put it back.
- **A restart has been pending** since updates were installed.
- **Permanent registry/active discrepancy on VBS**: the registry says 0, VBS is running all
  the same. Never conclude a pending switch from it — the restart prompt must appear only
  after a switch made **from Vigie**.
- **Edge is installed but does not start** (exits in under a second, no window). Chrome is the
  default browser and works.
- **DNS goes through Acrylic** (local DNS proxy, `AcrylicDNSProxySvc` service, 127.0.0.1 on
  Wi-Fi): an Acrylic failure looks like "no internet any more" — the DNS field on the Network
  card tells the difference.
- **`netsh wlan` fails** (error 5): neither signal strength nor SSID by that route.
- **git is only in the user PATH**, not the machine one: an elevated process does not find it
  without a resolved path.
- **Node is not installed** and will not be (**D06**); **no YAML parser** either.
- **The execution policy is `AllSigned` for the machine**: `powershell.exe -File
  <unsigned script>` is refused. What has to run there passes a **command**, never a file.

## Working with subagents (authorised by the owner)

**Frame set by the owner**: up to **3 subagents**, each in **its own worktree**, each
**merging into `main` itself**. They are **persistent**: send a subject back to one rather
than starting a new one, they keep their context. "Do not stuff them" — one subject at a
time, framed; the main agent's role is **orchestration**.

### A split that worked

Split by **disjoint files**, not by theme: two agents in `common.ps1` at the same time is a
guaranteed conflict. The split that held: probes on one side · package managers and back end
on the other · documentation alone (it touches no `.ps1`). The main agent keeps the front end
(`index.html`) and the foundation.

### What a brief must contain, without exception

1. **Where to read** — `doc/en/agent-working/briefing.md` then the precise decisions (`D15`,
   `D43`, `D47`…), not "read the docs".
2. **The subject, only one**, with the existing model to copy when there is one ("study
   `wu-list-pending.action.ps1` before writing").
3. **The non-negotiable rules**: accented French for the owner, comments in English,
   identifiers in English, ellipses reserved for an action in progress, validation by the
   Parser **and** `check-probes.ps1`, never a `Co-Authored-By` line.
4. **The known traps**, named — otherwise they rediscover them at their own cost:
   `--disable-interactivity` for winget, `netsh wlan` failing here, the `file://` preview
   stealing focus.
5. **What it must NOT touch**: another agent's files, and the **server restart** (port 47600)
   which the main agent keeps for itself.
6. **Machine caution**: "do not leave the machine in a state different from the one you found
   it in" — essential the moment one touches the Windows Update lock or VBS.
7. **The expected answer format**: two or three sentences — what changed, what was checked
   **under real conditions**, what remains uncertain.

### What they brought that I would not have found alone

They **execute** instead of re-reading, and report what the brief had wrong. Real examples:
`$pid` is read-only and the exception was swallowed by an empty `catch`; the winget column
split gave a version as a package identifier; a missing registry key made the lock fail
**silently** on a fresh machine; and above all the correction of my own brief —
`Get-AdminRoot` exists next to `Get-ToolsPath`, my `grep` saw only the second.

**Lesson**: an agent that disputes the brief is often right. Check for yourself before
deciding, then give it the corrected subject.

### Observed limits

- The worktree's isolation can **refuse** git commands aimed at the shared repository; they
  then work around it with `git push origin HEAD:main` from their worktree. Consequence:
  **the local `main` ends up behind**, so `git pull` before any merge.
- They cannot judge a visual result: what is seen stays with the main agent, through the
  **served** page (never `file://`).

## Decisions

See `../../progress/decisions.md` — each entry says whether it was asked for by the owner or
taken by the agent: tray icon = option B (graduations + heel confirmed); name = repository
"Vigie Windows" (slug `vigie-windows`), interface "Vigie" instead of "Control Panel".

## GitHub repository (current state)

**Publication is done.** The repository `Cartman34/vigie-windows` is populated; the initial
import is commit **`e45a062`** ("Vigie — import initial"), branch **`main`**.

**Source of truth today**: `C:\EspaceRestreint\Workspaces\Git\vigie-windows`. That is the git
repository, and that is **where** we work (Claude Code opens in that folder).

**Former workspace**:
`C:\EspaceRestreint\Workspaces\AiTeam\LocalWork\hyperion-control-panel` — **being retired**,
it is no longer the source. Do not edit there, do not copy from there. Per **D07** it is
**renamed** (suffix `.old`) and not deleted; deletion will happen only after explicit
confirmation that everything works from the repository.

### git config / access (still valid)

- `credential.helper=manager`; `user.name` / `user.email` already set.
- Remote over **HTTPS**: `https://github.com/Cartman34/vigie-windows.git`.
- Authentication: a *fine-grained* token (All repos + **Contents R/W**), remembered by the
  Credential Manager at the first push. Username = `Cartman34`, Password = the **token** (not
  the GitHub password).
- Zero-token alternative: SSH remote `git@github.com:Cartman34/vigie-windows.git` with the
  local key.
- **The service account holds none of these credentials**, and cannot ask for them: session 0
  has no desktop where a prompt could be answered. That is why the version tag is posed by
  the requester's client app.
- `.gitignore` already excludes the API token (`apps/backend-pode/var/secrets/`), the state
  (`apps/backend-pode/var/cache/`), the logs and `local/`. Before any commit, `git status`
  must show NEITHER `var/secrets/`, NOR `var/cache/`, NOR `apps/*/var/log/`, NOR `*.bak-*`.

### Agent rights (**D40**)

`.claude/settings.json` is **versioned** and grants tools at the tool level (`"Bash"`,
`"PowerShell"`, without parentheses): no permission prompt any more, including on compound
commands. Do **not** go back to pattern rules (`Bash(git *)`): they cover only statically
analysable commands, which was the cause of the problem. A `PreToolUse` hook judging the text
was tried and then **removed** (unavoidable false positives, +1 s per command) — the full
history is in **D40**, do not do it again.

## Environment constraints (important)

> This section describes the REAL working machine. It replaces the former one, which
> described an ephemeral Linux VM and no longer applies: the project is now edited directly
> on the machine, in the git repository.

### Tools present

- **PowerShell 7** (`pwsh`): present. It is the validation tool for PowerShell code.
- **Windows PowerShell 5.1** (`powershell.exe`): present, and it is the only host that sees
  the WinRT projection — see `../../progress/targeting/notifications.md`.
- **Python 3.11**: present (used by `apps/tray/assets/generate-icons.py`).
- **Chocolatey**, **git**, **php**, **composer**, **symfony-cli**: present.
- **git** works normally: repository, branches and worktrees operational. **HTTPS** to
  GitHub, token remembered by the Credential Manager.

### Tools ABSENT (and deliberately not installed)

- **Node / npm**: absent from the machine (checked: PATH, nvm, fnm, volta, scoop, Chocolatey
  packages, and a search for `node.exe` under Program Files / LOCALAPPDATA / APPDATA /
  ProgramData). The project has **no** JS dependency: no `package.json`, no build step, a
  single HTML file served as is. So we do not install Node (see **D06**).

### How to validate (NEVER invent a validation)

- **PowerShell**: `[System.Management.Automation.Language.Parser]::ParseFile(...)` on every
  `.ps1` / `.psd1` changed, and the real output is reported.
- **Front-end JavaScript**: load `apps/frontend-web/index.html` over `file://` in a browser
  and read the console (**D06**). A syntax error prevents the whole `<script>` block from
  running: checking that a constant defined at the end of the script exists is enough to
  prove the file parses. This test also covers runtime errors and the fallback to
  `mock/state.json`.
- **Launchers** (`.cmd`, `.vbs`): must stay **pure ASCII** (checked byte by byte). The rest of
  the code is **UTF-8 with accents**.

### Privileges

- The agent's session is **not elevated**. Any operation on the scheduled task (registered as
  `RunLevel Highest`) requires an administrator PowerShell launched by the owner:
  `install-autostart.ps1`, `uninstall-autostart.ps1`, `uninstall-legacy.ps1`.

### Never to be committed

- `apps/backend-pode/var/secrets/` (API token), `apps/backend-pode/var/cache/`,
  `apps/*/var/log/`, `*.bak-*`. The `.gitignore` already covers them; check `git status`
  before every commit all the same.
