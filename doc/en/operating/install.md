# Installation

[Documentation index](../README.md) · [Français](../../fr/operating/install.md)

Two routes. The **archive** is the recommended one: it needs no git and no developer
tooling. The **git clone** is for people who intend to read or change the code.

> Vigie is version **0.1**. The archive is produced by `scripts/build-release.ps1`, and
> a maintainer attaches it to a GitHub Release. If the Releases page is still empty, no
> version has been published yet and the git route is the one that works.

---

## Prerequisites

| | |
|---|---|
| Windows | 10 or 11 |
| PowerShell | **7** (`pwsh`). `scripts\install.ps1` installs it via winget if it is missing, then asks you to run it again. |
| Pode module | installed by `scripts\install.ps1` (`AllUsers` when elevated, otherwise `CurrentUser`) |
| Rights | administrator, for the Windows Update actions and for the autostart task |
| Browser | Edge or Chrome for the dedicated app window; any browser for the plain page |

There is no Node, no npm, no build step: the front end is one static HTML file.

---

## Route 1 — the published archive (recommended)

1. Go to the [latest release](https://github.com/Cartman34/vigie-windows/releases/latest) — that link always points at the most recent one, without your
   having to know its number — and download `vigie-<version>.zip`. The [full list](https://github.com/Cartman34/vigie-windows/releases) stays available if
   you are after an earlier version.
2. Unzip it wherever you like. It expands into a single `vigie-<version>/` folder, which is only a stepping stone:
   `setup.cmd` **copies Vigie into `C:\Program Files\Sowapps\Vigie`** and it is that copy which runs from then
   on. The unzipped folder can be deleted once the installation is done.
3. Windows marks downloaded files as blocked. Either unblock the folder once:
   ```powershell
   Get-ChildItem -Recurse | Unblock-File
   ```
   or use the `.cmd` launchers below, which bypass the execution policy on purpose.

Then follow [First run](#first-run).

### What is in the archive — and what is not

The archive is the **product**, not the repository. It carries the server, the front end,
the tray app, the installation scripts, this documentation, the licence and the version
file — around 90 files.

Left out on purpose:

| Not included | Why |
|---|---|
| `apps/atelier/` | a development tool (PHP, port 47610) that a user never runs |
| `scripts/build-release.ps1`, `scripts/install-hooks.ps1`, `scripts/hooks/` | maintainer tooling; they need a git repository, which the archive is not |
| `scripts/uninstall-legacy.ps1` | a dated, disposable cleanup for machines installed before the project was renamed — irrelevant to a fresh install |
| The project's internal documents (decision records, backlog, running log, conventions) | the repository's working memory, not user documentation. The doc pages that reference them link to GitHub |
| `apps/*/var/`, `config.local.psd1`, logs, the API token | runtime data and secrets. They are never versioned, so they can never reach the archive |

If you need any of those, take the git route.

## Route 2 — git clone

```powershell
git clone https://github.com/Cartman34/vigie-windows.git
cd vigie-windows
```

Same folder layout, same scripts. Choose this if you want to follow `main`, read the
code, or contribute — see [Development](../developing/README.md).

### What the installer declares when it runs from a repository

Run from a git clone, `setup.cmd` records two things **for the whole computer**, in
`%ProgramData%\Sowapps\Vigie\machine.psd1`:

| | |
|---|---|
| `SourcePath` | where this deployment came from — a **fact**, not an intent |
| `safe.directory` (machine-level git config) | this folder is trusted by git |

**Why the second one.** The server app runs as a service account, and git refuses to open
a repository owned by someone else ("detected dubious ownership"). Without that
declaration the service cannot even **clone** your repository: the "Update" button in the
interface would fail, with nothing explaining why.

It needs elevation. Without it the installer carries on and **says so** — updating from
the interface will keep failing until this is done:

```powershell
git config --system --add safe.directory C:/path/to/your/repo
```

**The environment is never deduced.** Finding a repository does not make a machine a
development one: `Environment` (`dev` or `prod`) is declared in
`appsackend-pode\config\config.local.psd1`, and it does not say where the code comes
from — `UpdateSource` / `UpdateRemote` do. The two are independent: a development
environment may pull from a remote repository, and a production one from a local clone.

---

## First run

Everything lives in `scripts\`. Every script is **idempotent**: running it twice does no
harm.

### 1. Prerequisites, once

**The simplest way: double-click `setup.cmd`.** It asks for elevation itself (a Windows prompt to accept), makes the
first pass with Windows PowerShell — `pwsh` may not exist yet at install time — then the second one with PowerShell 7
once that is in place.

From a command line, in an **administrator** terminal:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

`install.ps1` switches itself to PowerShell 7 if you started it from 5.1, registers the NuGet provider, trusts the
PSGallery repository, installs **Pode**, generates the local API token, and checks for the WebView2 runtime. It writes
a transcript to `var\log\install_*.log`.

**It starts by copying itself into `C:\Program Files\Sowapps\Vigie`**, then carries on from that copy: that is
the one the startup task will launch. Two exceptions, where Vigie stays where it is — a **git clone** (a development
machine, where Vigie runs from the sources) and an installation **already** at that location. Machine settings already
present at the destination (`config/*.local.*`, `actions.policy.json`) are preserved: updating does not reset your
choices.

**Your data never lives next to the program.** Token, logs, caches and one account's settings go to
`%LOCALAPPDATA%\Sowapps\Vigie`. The server runs elevated, so it *could* write into Program Files — and that is
exactly the trap: every account would then share one token and one set of settings, when each must have its own.

**Elevation is not optional when PowerShell 7 is missing**: the install runs machine-wide (`--scope machine`), or
winget drops the package into the current account's profile and the other accounts cannot start Vigie.

### 2. Start Vigie

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

or double-click `scripts\run.cmd`.

`run.ps1` relaunches itself under PowerShell 7 and **elevates through UAC** — the server
must run as administrator to read and apply the Windows Update lock. It installs Pode
automatically if it is still missing, refuses to start a second server if one is already
listening (it just opens the browser instead), and only opens the browser once the port
actually answers. `-NoBrowser` skips opening a tab.

The dashboard is at <http://127.0.0.1:47600/>. The REST API is under `/api/v1`.

### 3. Make it permanent (optional but expected)

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

or double-click `scripts\install-autostart.cmd`.

Before any UAC prompt, a window lists exactly what will be changed and lets you refuse
without any system prompt appearing at all. What it does:

- registers a scheduled task named **`Vigie`**, triggered at logon, running
  `apps\tray\tray.ps1` hidden with the **highest privileges**;
- creates a desktop shortcut `Vigie.url` pointing at the dashboard;
- starts the task immediately, so the tray icon appears right away.

Exit codes: `0` installed, `1` a prerequisite is missing, `3` you refused.

`scripts\start-vigie.vbs` starts that task silently afterwards, and
`scripts\install-autostart.vbs` is the silent variant of the installer.

---

## Uninstalling

### Remove the autostart

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\uninstall-autostart.ps1
```

Removes the `Vigie` scheduled task and the desktop shortcut. **No application file is
deleted**; re-install at any time with `install-autostart.ps1`. Exit code `3` means you
refused at the explanation window.

### Remove Vigie entirely

After the step above, delete two folders:

- the program, `C:\Program Files\Sowapps\Vigie` (or wherever you launched it from, if you work from a git
  clone);
- your data, `%LOCALAPPDATA%\Sowapps\Vigie` — settings, logs and caches. **Each account has its own**: an
  account that has used Vigie keeps its own until you erase them from that account.

Nothing else of Vigie lives outside those — apart from what you asked it to change on the system:

> **Important:** uninstalling Vigie does **not** unlock Windows Update. If you locked it,
> unlock it *before* removing Vigie, otherwise your machine stays with automatic updates
> disabled. See [Windows Update](../using/windows-update.md#unlocking-for-good).

### Leftovers from a pre-rename installation

Machines installed before the project was renamed to Vigie carry an orphan scheduled task
and shortcut. A dated, disposable script cleans them up — **it ships with the repository
only, not with the archive**, since it cannot apply to a fresh install:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\uninstall-legacy.ps1 -WhatIf
pwsh -ExecutionPolicy Bypass -File .\scripts\uninstall-legacy.ps1 -LegacyWorkspace 'C:\path\to\old-folder'
```

`-WhatIf` shows what it would do and changes nothing. The old workspace is **renamed**
with a `.old` suffix, never deleted — removing it stays your deliberate act. Exit codes:
`0` done, `2` at least one step failed, `3` refused.

---

## Next

- [Getting started](../using/getting-started.md) — the tray icon, the dashboard, your first action
- [Configuration](configuration.md) — port, external tooling, machine-local overrides
- [Troubleshooting](../using/troubleshooting.md) — when one of these steps does not go as written
