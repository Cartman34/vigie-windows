# Configuration

[Documentation index](README.md) · [Français](../fr/configuration.md)

Vigie ships with a **generic, versioned** configuration that works on any machine, and
takes machine-specific values from a **local file that git ignores**. You never edit the
versioned file to adapt Vigie to your PC.

Each value is defined in exactly one place; everything else derives from it.

---

## The three layers

Each app merges, in order — the most specific wins:

| File | Scope | Versioned |
|---|---|---|
| `config/common.psd1` | shared by every local server in the repository | yes |
| `apps/backend-pode/config/config.psd1` | Vigie's own settings | yes |
| `apps/backend-pode/config/config.local.psd1` | **your machine** | **no** (`.gitignore`) |

### `config/common.psd1`

| Key | Value | Meaning |
|---|---|---|
| `BindAddress` | `127.0.0.1` | listening address for **every** server in the repository. Strictly local — nothing here is ever meant to be exposed. |
| `PortRangeStart` / `PortRangeEnd` | `47600` / `47699` | the port range reserved for the project. Each app picks one from it. |

### `apps/backend-pode/config/config.psd1`

| Key | Default | Meaning |
|---|---|---|
| `Port` | `47600` | Vigie's listening port |
| `ApiBase` | `/api/v1` | prefix for the REST routes |
| `ToolsPath` | *(empty)* | optional external tooling folder — no longer gates Windows Update, see below |

The dashboard URL and the API URL are **derived** from these (`Get-AppUrl`, `Get-ApiUrl`);
they are never written out a second time anywhere in the code.

---

## Your local overrides

```powershell
Copy-Item apps/backend-pode/config/config.local.sample.psd1 apps/backend-pode/config/config.local.psd1
```

Put in it **only** what cannot be generic. Any key present overrides `config.psd1`; any
key absent keeps the default. **Never put a secret in it** — the API token lives in
`apps/backend-pode/var/secrets/`, on its own.

```powershell
@{
    ToolsPath = 'C:\path\to\LocalAgentAdmin\tools'
    # Port = 47601   # only if 47600 is already taken on this machine
}
```

Restart the server after changing it (tray menu → *Restart the server*).

---

## External tooling

`ToolsPath` is **optional** and no longer gates the Windows Update lock.

**Native, no tooling needed** — *Update mode (unlock)*, *Lock now* and *Run the audit* are
implemented in this repository (`lib/common.ps1`: `Set-UpdateLock`, `Invoke-UpdateAudit`).
They only require the server to run **as administrator**, and say so plainly when it does
not. If `ToolsPath` is set **and** contains `update-mode.ps1`, Vigie prefers that script, so
existing installs keep their behaviour — but its absence blocks nothing.

**Still external** — these three actions call scripts that do not ship with the repository.
Without `ToolsPath` they return a clear message instead of failing obscurely.

| Action | Script it calls |
|---|---|
| *Toggle VBS* | `<parent>\toggle-vbs.ps1` |
| *Toggle memory integrity* | `<parent>\toggle-hvci.ps1` |
| *Open the folder* | opens the administration root in Explorer |

**Everything else works without it**: every probe reads the system natively.

---

## Where Vigie writes

Each app keeps its own files under its own `var/`. None of this is versioned.

| Path | Contents |
|---|---|
| `apps/backend-pode/var/secrets/api.token` | the API token, generated on first run |
| `apps/backend-pode/var/cache/` | aggregated state and background-job results |
| `apps/backend-pode/var/log/` | `install_*`, `run_*`, `start_*`, Pode error and request logs |
| `apps/tray/var/log/` | `tray_*` logs |
| `apps/tray/var/run/` | the tray's heartbeat and command files |

## The version number

The product version lives in the file **`VERSION`** at the repository root, and nowhere
else. It holds the bare number (`0.1`); the `v` prefix is added once, when displaying.
It changes only on a deliberate decision, not with every commit.

## Next

- [Troubleshooting](troubleshooting.md) — reading those logs
- [Development](development/README.md) — the reasoning behind this layout
