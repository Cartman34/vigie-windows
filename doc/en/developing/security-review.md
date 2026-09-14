# Security review

> An **internal** document: the review, to be read again at every action added. The page meant for users is
> [`doc/fr/operating/security.md`](../../fr/operating/security.md) ([English](../operating/security.md)) — it says the
> same without the implementation detail.

The tool exposes a **local** REST API that can drive Windows, potentially from an **elevated** server (automatic
start). This page lists the risks and the measures. To be read again at every action added.

## Threat model
- Listens **strictly on 127.0.0.1** (never 0.0.0.0). No external network access.
- Main threat: another **local process** (or a web page open in the browser) trying to call the API to trigger actions.

## Risks and measures
1. **Arbitrary script execution** through the `type` field of POST /actions (e.g. `type = ../../..`). -> FIXED: whitelist
   `^[a-z0-9-]{1,40}$` in the route AND in `Invoke-ActionById`, + confinement of the resolved path to the `actions/`
   folder (Resolve-Path + StartsWith). Every attempt is rejected.
2. **CSRF / localhost drive-by** (a malicious web page POSTing to 127.0.0.1) -> FIXED: on every modifying request, the
   **Origin/Referer** header must match http://127.0.0.1:PORT or http://localhost:PORT, otherwise 403.
3. **Bearer token** required on the whole API except `/health`. Local listening.
4. **Actions**: do NOT run a command built from client input; `params` are never passed to a shell. Each action is a
   fixed script of the `actions/` folder.

## Residual risk (to know)
- The **token is injected into the page** served by the `/` route (unauthenticated, so the browser can load the UI). A
  local process running **as the user** can therefore read http://127.0.0.1:PORT/ and recover the token. Combined with
  an **elevated** server, this remains a possible local elevation path.
  - Current mitigation: local listening + origin check + whitelist.
  - Recommended hardening if more safety is needed:
    - Run the server **as the user** (not elevated) and elevate **only the action** when it runs (a UAC prompt per
      action).
    - Periodic token rotation.
    - Restrict the ACL of the file `apps/backend-pode/var/secrets/api.token`.

## Rule
Every new action must: carry a simple `id` (`[a-z0-9-]`), never interpolate client input into a command, and be
reviewed here if it touches system security.

## Note: elevated server by design
The server now runs **as administrator** (start.ps1 / run.ps1 ask for UAC if needed), since it must be able to apply
system actions. The protections stay in place: listening on 127.0.0.1, Bearer token, anti-CSRF (local origin),
whitelist + confinement of actions. Residual risk of the injected token: see above; hardening is possible (non-elevated
server + elevation per action) if the surface is ever to be reduced further.
