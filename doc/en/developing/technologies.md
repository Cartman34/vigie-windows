# Technologies used

Each technology: role, why, alternatives set aside, installation.

## PowerShell (5.1+ / 7)
- **Role**: native engine — drives Windows (registry, tasks, ACL, services).
- **Why**: native access to the host without an intermediate layer; all the existing tooling (`LocalAgentAdmin/`) is
  already PowerShell.
- **Installation**: present natively on Windows.

## Pode (PowerShell module)
- **Role**: web server — serves the front end AND exposes the REST API, in PowerShell.
- **Why**: a single language on the back end; it serves the API while driving Windows natively. Avoids adding PHP/Node
  only to delegate to PowerShell afterwards.
- **Alternatives set aside**: PHP/Node (an extra runtime + a bridge to PowerShell for every privileged action); ASP.NET
  (heavier).
- **Installation**: `Install-Module Pode -Scope CurrentUser` (no admin).
- **Watch out**: Pode isolates routes in runspaces. Context travels through environment variables (`VIGIE_BACKEND`,
  `VIGIE_TOKEN`) and `lib/common.ps1` is re-sourced in each route.

## OpenAPI 3 (apps/backend-pode/api/openapi.yaml)
- **Role**: REST contract, source of truth between front end and back end.
- **Why**: standard, tool-friendly, lets the back end change without touching the front end.

## HTML / CSS / JavaScript (vanilla)
- **Role**: static front end (dashboard).
- **Why**: no dependency, no build; it only `fetch()`es the contract. Light/dark rendering.
- **Alternatives set aside**: SPA framework (React/Vue) — needless at this scale, would add a build.

## WebView2 (to come — CORE-WINDOW)
- **Role**: application window showing the dashboard as a real app.
- **Why**: Edge engine already present on Win10/11; no Electron.
- **Installation**: "Evergreen WebView2 Runtime" if absent.

## Windows scheduled task (to come — CORE-AUTOSTART)
- **Role**: start the back end + the UI at session opening, elevated.
- **Why**: automatic start without a UAC prompt at every action.

## Bearer token + local listening
- **Role**: API security (elevated back end).
- **Why**: 127.0.0.1 limits access to the computer; the token blocks other unauthorised local processes.

## Windows mechanisms driven (reminder, detail in LocalAgentAdmin)
- Windows Update registry (`NoAutoUpdate`...), Update scheduled tasks, ACL/`takeown`/`icacls`, WaaSMedic service.
  Documented on the `LocalAgentAdmin` side.
