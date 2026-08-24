# Probes and actions

[Development](README.md) · [Documentation index](../README.md) · [Français](../../fr/developpement/sondes-et-actions.md)

The back end is a **generic engine**. It does not hard-code a single card: it discovers
probes on disk. Adding a card, or a button, means dropping a file. The contract does not
change and the front end does not change.

---

## Probe — reading state

**Location:** `apps/backend-pode/probes/<theme>/<name>.probe.ps1`

**Contract:** the script writes to standard output one object conforming to the `Module`
schema of the OpenAPI contract — or an array of them, when one probe legitimately produces
several cards (that is how there is one card per package manager).

**Rules:**

- **Fast and side-effect-free.** A probe reads; it never changes anything. Slow calls (WSL,
  for instance) must be bounded by a timeout.
- **Never call the heavy scripts.** A probe reads the registry, the tasks, the ACLs
  directly. Anything long belongs in an action plus a worker, with the probe merely
  reading the result file the worker wrote.
- Give it a TTL in the table in `lib/common.ps1` if the default 30 s does not suit.

```powershell
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

New-ModuleObject -Id 'my-card' -Theme 'system' -Label 'My card' -Status 'ok' -Fields @(
    New-Field -Key 'value' -Label 'Something' -Value 42 -Kind 'number' -Unit 'GB' -Status 'ok' `
        -Help "What this is, in plain language." `
        -Guide "What to do about it when it goes wrong."
) -Actions @(
    New-Action -Id 'my-action' -Label 'Do the thing' -Kind 'confirm' -Severity 'fix' -Confirm
)
```

### `New-Field`

| Parameter | Notes |
|---|---|
| `Key`, `Label`, `Value` | required |
| `Kind` | `bool` · `number` · `text` · `date` |
| `Unit` | displayed after the value |
| `Status` | `ok` · `warn` · `error` · `neutral` |
| `Help` | what this field *is* — plain language, no jargon |
| `Guide` | what to do when it is wrong: what it means, the risk of ignoring it, the options |
| `FixAction` | the id of the action that resolves this field |
| `Table` | structured detail: `@{ columns = @(...); rows = @(@(...), ...) }`. Dozens of lines crammed into a string stay unreadable wherever you put them; a table can be scanned |

### `New-Action`

| Parameter | Notes |
|---|---|
| `Id`, `Label` | required. The label says **what the action does** — never a generic "Fix" |
| `Kind` | chooses the **icon**, i.e. *how it happens*: `immediate` · `confirm` (yes/no) · `dialog` (a choice window inside the app) · `manual` (hands over to external software) |
| `Severity` | chooses the **colour**, i.e. *what it is worth*: `neutral` (grey) · `info` (blue, read-only or opening something) · `fix` (green, corrects something) |
| `Confirm` | require confirmation before running |
| `BusyLabel` | shown while running. It must say what is happening — "Upgrading…", not "In progress…". Ellipses are reserved for an action under way; a resting label never carries one |

Kind and severity used to be conflated, so the colour followed the shape and taught the
reader nothing. Keep them distinct.

### `New-ModuleObject`

`Id`, `Theme`, `Label`, `Status` are required; `Fields`, `Actions` optional. `-Busy` marks
the card as working, and `-BusyAction` names the action actually running — without it the
UI animates every button on the card and you cannot tell which one is working.

---

## Action — doing something

**Location:** `apps/backend-pode/actions/<id>.action.ps1`, with `<id>` matching
`^[a-z0-9-]{1,40}$`. Declared by a probe in its `actions[]`, invoked by
`POST /actions {type, module, params}`.

**Returns** `@{ message; result }`. Useful keys in `result`:

| Key | Effect |
|---|---|
| `ok` | success or failure, as actually observed |
| `invalidate` | `@('lock.probe.ps1')` — force these probes to recompute now |
| `async` | `$true` when the work continues in a worker |
| `module` | the card the front end should poll while `async` |

```powershell
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
# ...
@{ message = 'Done.'; result = @{ ok = $true; invalidate = @('my.probe.ps1') } }
```

### Rules

1. **Never interpolate client input into a command.** `params` never reach a shell. Each
   action is a fixed script on disk; the resolved path is confined to `actions/`.
2. **Handle output and exit code** — use the shared `Invoke-Native`.
3. **Verify the result; do not trust the return code.** After a change, re-read the system
   and report what you actually obtained. `update-mode-off` is the model: it runs the
   script, logs the raw `icacls` output, then re-tests the ACL and the registry key and
   distinguishes full success, partial success and failure.
4. **Do not copy an invocation.** If two actions need the same operation, it belongs in a
   shared helper in `lib/common.ps1` — `Set-UpdateLock` exists precisely because the lock
   was about to be invoked from a third place.
5. **Review it in [Security](../security.md)** if it touches system security.

### Long actions

Anything measured in minutes goes to a worker:

```powershell
$null = Start-DetachedAction -Script (Join-Path $backend 'workers/my.worker.ps1') `
                             -ArgsMap @{ foo = 'bar' } -Backend $backend
@{ message = 'Started in the background.'
   result  = @{ ok = $true; async = $true; module = 'my-card'
                invalidate = @('my.probe.ps1') } }
```

The worker writes its progress into `var/cache/<name>.json` via `Update-StateJson` (mutex
protected), and the probe merely reads that file. Add a **staleness guard**: a job can die
without writing anything, and without an expiry its "running" flag never clears — the
package cards give up after 45 minutes for exactly that reason.

---

## Existing examples worth reading

| File | Why |
|---|---|
| `probes/windows-update/lock.probe.ps1` | rich fields, conditional actions, honest handling of "not elevated" |
| `probes/tools/packages.probe.ps1` | one probe, several cards, busy state, stale-job guard |
| `actions/update-mode-off.action.ps1` | verifying the real outcome instead of the return code |
| `actions/wu-install.action.ps1` | explicit selection, detached worker, lock lifted and put back |
| `actions/net-speedtest.action.ps1` | merging a result into a shared cache file |

## Next

- [Architecture](architecture.md) — where all this sits
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml) — the contract
- [Security](../security.md) — the rules an action must respect
