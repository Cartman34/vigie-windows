# Architecture

[Development](README.md) · [Documentation index](../README.md) · [Français](../../fr/README.md)

---

## Five principles

1. **Contract-first.** `apps/backend-pode/api/openapi.yaml` is the source of truth. The
   front end knows only the contract; the back end is one implementation of it
   (Pode/PowerShell today, replaceable without touching the front).
2. **Generic and extensible.** No module is hard-coded. The back end **discovers** probes
   (state readers) and actions (side effects), grouped by theme. Adding a card means
   dropping a file — no contract change, no front-end change.
3. **Static front end.** Pure HTML/CSS/JS, no server-side rendering, `fetch()` and nothing
   else. One file.
4. **Never blocking.** Anything slow — package upgrades, network measurement, online
   update scans, WSL — runs as a detached background job. The UI stays responsive and each
   card updates itself.
5. **Security.** Strictly local API, bearer token, anti-CSRF, action whitelist. Never a
   back door. See [Security](../operating/security.md).

## Four apps, one repository

| App | Technology | Role |
|---|---|---|
| `apps/backend-pode` | PowerShell 7 + Pode | serves the front end **and** drives Windows natively — registry, tasks, ACLs, services — with no intermediate layer |
| `apps/frontend-web` | one static HTML file | the dashboard |
| `apps/tray` | PowerShell + WinForms | a **standalone app** that *drives* the back end (starts it, stops it, polls its health) without being part of it |
| `apps/atelier` | PHP | internal visual-validation tool, never part of the product |

Each app owns its own `config/` and its own `var/`. `config/common.psd1` at the root holds
only what is genuinely shared.

## The REST contract

Base `http://127.0.0.1:47600/api/v1`.

| Route | Purpose |
|---|---|
| `GET /health` | is the service answering — the only route without a token |
| `GET /state` | full snapshot: every module, every theme |
| `GET /modules/{id}` | one module, for per-card polling |
| `POST /actions` | trigger an action: `{ type, module, params }` |

A `Module` carries `id`, `theme`, `label`, `status` (`ok` / `warn` / `error` / `neutral`),
`fields[]` and `actions[]`. That is all the front end knows about any card — which is
exactly why a new probe needs no front-end change.

## The request path

```
browser ──GET /state──> Pode ──> Get-State ──> probe cache ──> *.probe.ps1
       <──JSON────────                                    (only the stale ones)

browser ──POST /actions──> whitelist ──> <id>.action.ps1 ──┬─> immediate result
                                                          └─> Start-DetachedAction ──> worker
```

## State aggregation and caching

`Get-State` in `lib/common.ps1` aggregates every probe and caches the result in
`var/cache/state-cache.json`.

- **Per-probe invalidation**, on the probe file's mtime plus a **TTL of its own**: 5 s for
  package managers, 120 s for the firewall, 300 s for the antivirus and VBS, 600 s for the
  update lock, 900 s for pending updates, 3600 s for the OS card. Default 30 s.
- **Single-flight**, guarded by a cross-process mutex: concurrent readers do not each
  trigger the same recomputation.
- **Serve-stale**: a reader arriving mid-refresh gets the previous full state, never a
  half-built one. Forcing a refresh means *recompute*, not *forget everything* — the cache
  is always loaded first, so no card ever vanishes while it rebuilds.
- All timestamps are normalised to UTC in one place. Comparing dates from different kinds
  is what once made the cache silently useless.

An action can return `result.invalidate = @('lock.probe.ps1')` to force specific probes to
recompute, so a card reflects a change immediately instead of at the next TTL.

## Background jobs

`Start-DetachedAction` launches a worker in a hidden, detached `pwsh` — no visible console,
no terminal-tab restoration. Parameters travel as base64 JSON, which is immune to quoting
problems, and the `pwsh` used is the current process's own, so no install path is
hard-coded.

A long action answers immediately with `result.async = $true` plus the `module` to watch.
The front end marks the card busy and polls it until the job finishes. Closing the browser
interrupts nothing.

Workers write their progress into `var/cache/*.json` through `Update-StateJson`, which is
guarded by a cross-process mutex; the matching probe only ever *reads* that file. That is
what keeps probes fast and side-effect-free.

## The tray, and why it is separate

The tray runs elevated. From an ordinary session you can neither read its command line nor
signal a kernel object it created — it had to be killed blind, which left a ghost icon in
the notification area.

So it communicates through files: `scripts/tray.ps1` drops an **order** in
`apps/tray/var/run/`, the tray reads it and exits cleanly, releasing its icon. The same
folder carries a heartbeat (`tray.alive`, rewritten every 8 s) so its state can be known
without inspecting the process. Inspectable by eye, scriptable from anything, and open to
extension: a new order is a new file name, with no change to the mechanism.

## Version and reload

`VERSION` at the repository root holds the product version, and nowhere else. Separately,
a **build id** acts as a change token: the front end compares it with its own every 15
seconds and reloads the page when a new version is being served. Two distinct values, two
distinct jobs — the version is for humans, the build id is never displayed.

## Next

- [Probes and actions](probes-and-actions.md) — the extension points, in practice
- [`apps/backend-pode/api/openapi.yaml`](../../../apps/backend-pode/api/openapi.yaml)
