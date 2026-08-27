# Configuration

[Documentation index](../README.md) · [Français](../../fr/operating/configuration.md)

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

`ToolsPath` is **optional**. **No Vigie feature depends on it any more.**

**Everything is native** — the Windows Update lock (*Update mode*, *Lock now*), its *audit*,
and the *VBS* and *memory integrity* toggles are implemented in this repository
(`lib/common.ps1`: `Set-UpdateLock`, `Invoke-UpdateAudit`, `Set-DeviceGuardFeature`). They
only require the server to run **as administrator**, and say so plainly when it does not.

If `ToolsPath` is set **and** contains `update-mode.ps1`, Vigie prefers that script for the
lock, so existing installs keep their behaviour — but its absence blocks nothing.

**The one remaining use** is *Open the folder*, which opens the administration root (the
`<parent>` of `ToolsPath`) in Explorer. That is legitimate: the button only means anything
if there is a folder to open. With no path configured — or one pointing nowhere — the card
**does not offer the button at all**, rather than showing a dead one.

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

- [Troubleshooting](../using/troubleshooting.md) — reading those logs
- [Development](../developing/README.md) — the reasoning behind this layout
