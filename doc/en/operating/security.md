# Security

[Documentation index](../README.md) · [Français](../../fr/operating/security.md)

Vigie exposes a local REST API that can change Windows settings, from a process that runs
elevated. That deserves a straight account of what is protected and what is not.

---

## Why it runs as administrator

The Windows Update lock writes under `HKLM`, disables scheduled tasks and applies ACLs on
task folders. Toggling VBS/HVCI is equally privileged. Whatever serves the API therefore
has to be elevated.

- Started by the scheduled task **`Vigie`**, registered with `RunLevel Highest`.
- Started by hand, `run.ps1` **elevates itself through UAC**.
- Not elevated, Vigie does not pretend: the *ACL lock* field reads "server not elevated"
  as a neutral value rather than showing a false warning.

**Before any UAC prompt**, the installation and uninstallation scripts show a window that
lists the concrete changes and what is explicitly *not* touched. Escape and the close
button both mean refuse, and a refusal returns exit code `3` without a single system
prompt appearing. Automated runs use `-Yes`; without a desktop, the scripts explain in the
console and **refuse by default**.

## What is exposed

| | |
|---|---|
| Bind address | **`127.0.0.1` only** — never `0.0.0.0`, never a network interface |
| Port | `47600` |
| API | under `/api/v1`: `GET /health`, `GET /state`, `GET /modules/{id}`, `POST /actions` |
| Authentication | a **bearer token**, required on everything except `/health` |
| Token storage | `apps/backend-pode/var/secrets/api.token`, generated on first run, never committed |

## The four defences

1. **Action whitelist.** The `type` field of `POST /actions` must match
   `^[a-z0-9-]{1,40}$`, checked both at the route and inside the dispatcher, and the
   resolved path is confined to the `actions/` folder. A `type` of `../../..` is rejected.
2. **Anti-CSRF.** On any modifying request, the `Origin`/`Referer` header must match
   `http://127.0.0.1:PORT` or `http://localhost:PORT`, otherwise `403`. This is what stops
   a malicious web page you happen to have open from POSTing to your own machine.
3. **No shell injection.** Actions never build a command from client input. `params` are
   never handed to a shell. Each action is a fixed script on disk.
4. **Nothing sensitive is versioned.** `apps/backend-pode/var/secrets/` (the token),
   `apps/backend-pode/var/cache/` (state) and `apps/*/var/log/` are all covered by
   `.gitignore`.

## The residual risk, stated plainly

The token is **injected into the page** served by `/`, which is itself unauthenticated —
the browser has to be able to load the UI somehow. So **any local process running as you
can fetch `http://127.0.0.1:47600/` and read the token**. Combined with an elevated
server, that is a plausible local privilege-escalation path.

What currently mitigates it: local-only binding, the origin check, and the action
whitelist. What would harden it further, if you need more:

- run the server **unelevated** and elevate only the action at the moment it runs (a UAC
  prompt per action);
- rotate the token periodically;
- restrict the ACL on `apps/backend-pode/var/secrets/api.token`.

None of these are implemented in v0.1.

## Rules for anyone adding an action

- Give it a simple `id` matching `[a-z0-9-]`.
- Never interpolate client input into a command.
- If it touches system security, review it here before merging.

See [Probes and actions](../developing/probes-and-actions.md) for the mechanics, and
[`doc/en/developing/security-review.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/security-review.md) for the project's internal
security review (French).

## What Vigie does not do

- It does not open a port on your network.
- It does not phone home. The only outbound traffic is the public-IP lookup and the
  throughput measurement, and both happen **only when you press the button**.
- It does not collect or transmit anything about your machine.
