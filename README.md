# Vigie

**English** · [Français](README.fr.md)

**A local control panel for one Windows PC.** Vigie watches Windows Update, disk, memory,
network, WSL, security and your package managers, and shows the whole thing as a set of
cards in a browser window. Its headline feature: it **can hold Windows Update shut** —
a lock you switch on and off as you please — so Windows cannot reboot your machine on its
own, while still letting you install updates whenever *you* decide to.

> **Nothing leaves your machine.** Vigie sends no data over the Internet: it reads your
> PC's state, shows it locally, and that is all. No account, no telemetry, no remote
> server. The only network access it makes is the one you trigger yourself: measuring
> throughput, reading your public IP, or asking a package manager whether updates exist.

Repository: <https://github.com/Cartman34/vigie-windows>

> **Version 0.1 — not released yet.** There is no published release, no installer and no
> stability promise. The code runs on the author's machine; expect rough edges, and read
> the points below before installing it on yours.

---

## Get started

> Vigie touches Windows Update and runs as administrator: the three points in
> [Read this before you install](#read-this-before-you-install) are worth the minute.

The recommended route is the **archive from GitHub Releases** — no git, no clone.

**One file, at the root: `setup.cmd`. Double-click it.** Prerequisites,
PowerShell 7 **machine-wide**, the Pode module, the logon autostart, and Vigie itself,
started.

| | File | What it does |
|---|---|---|
| 1 | **`setup.cmd`** | **The whole install.** Asks for administrator rights (a Windows prompt to accept): PowerShell 7 is installed **machine-wide**, not just for your account. Run it **once**. |
| 2 | **`scripts\run.cmd`** | Starts Vigie again if you closed it. The browser opens on <http://127.0.0.1:47600/> once the server is actually listening. |

Before that first double-click: download `vigie-<version>.zip` from the
[Releases page](https://github.com/Cartman34/vigie-windows/releases) and unzip it
**somewhere permanent** — not `Downloads`, not a temp folder: the scheduled task will
point at this path. It expands into a single `vigie-<version>/` folder. *If that page is
empty, no version has been tagged yet: take the git route below.*

> **Why the install needs elevation.** Vigie starts from a scheduled task, one per
> account, and that task runs `pwsh`. **If** PowerShell 7 were installed for a single
> account only (the Store package), it would live inside that account's profile: no other
> account could start Vigie. So `setup.cmd` installs it **machine-wide**
> (`C:\Program Files\PowerShell\7`).

From a terminal instead, if you prefer — the install needs an **administrator** terminal,
and Windows PowerShell will do, since `pwsh` is not there yet:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\run.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

The git route, what each script does, and how to uninstall:
[Installation](docs/en/install.md). First run and how to read the dashboard:
[Getting started](docs/en/getting-started.md).

## Read this before you install

Vigie is not a passive monitor. Three things you must know:

1. **It can lock Windows Update.** It is a feature you switch on and off from the
   application, not a state imposed on you. When the lock is on, automatic updates are switched off
   (`NoAutoUpdate`) and an ACL lock prevents Windows from re-enabling its update tasks.
   No update installs itself, and **no reboot is ever forced** — but nothing installs
   itself either. Keeping a machine patched becomes *your* deliberate act, from Vigie's
   "Update mode" or from Windows Settings. See [Windows Update](docs/en/windows-update.md).
2. **It runs as administrator.** Reading and applying that lock means registry writes
   under `HKLM`, scheduled-task changes and ACL changes. The scheduled task that starts
   Vigie is registered with the highest privileges, and starting it by hand triggers a
   UAC prompt. Every elevation is explained in a window *before* the UAC prompt appears.
3. **It listens on 127.0.0.1 only** — never on a network interface. The API requires a
   bearer token, checks the request origin, and only runs actions from a fixed
   whitelist. There is one known residual risk (the token is injected into the served
   page), described honestly in [Security](docs/en/security.md).

---

## What it actually does

| Theme | Cards |
|---|---|
| **Windows Update** | update lock (auto-updates, ACL lock, disabled vs. active tasks, pending reboot), pending updates (online scan, selective install), history (last reboot, WaaSMedic) |
| **System** | Windows edition/activation/build, C: free space against a threshold, RAM/CPU/uptime |
| **Network** | connectivity, connection type, Wi-Fi, local IP, public IP, IPv6, MAC, VPN, on-demand latency and throughput measurement |
| **Security** | antivirus (name, active, up to date), firewall profiles, VBS and memory integrity (HVCI) |
| **WSL** | installed, default distribution, running/stopped, start / restart / shut down |
| **Package managers** | one card per manager found in `PATH` (winget, Chocolatey, Scoop, npm, pnpm, Yarn, pip, pipx, Cargo, RubyGems, .NET SDK) — version, available updates, background upgrade |

Full detail, card by card: [What Vigie monitors](docs/en/features.md).

## Documentation

| | |
|---|---|
| [Documentation index](docs/en/README.md) | everything, in one page |
| [Installation](docs/en/install.md) | archive or git clone, autostart, uninstall |
| [Getting started](docs/en/getting-started.md) | first launch, tray icon, reading a card |
| [What Vigie monitors](docs/en/features.md) | every card and every action |
| [Windows Update](docs/en/windows-update.md) | the lock, update mode, installing updates |
| [Security](docs/en/security.md) | elevation, local binding, token, residual risk |
| [Configuration](docs/en/configuration.md) | port, external tooling, local overrides |
| [Troubleshooting](docs/en/troubleshooting.md) | logs, tray commands, common failures |
| **[Development](docs/en/development/README.md)** | architecture, probes and actions, contributing |

## Requirements

- Windows 10 or 11.
- **PowerShell 7** (`pwsh`), **machine-wide** (`C:\Program Files\PowerShell\7`) — installed by
  `setup.cmd` if absent. The scheduled tasks run it: an install limited to one
  account would stop the others from starting Vigie.
- The **Pode** PowerShell module — installed by the same script.
- Administrator rights, for the Windows Update actions and the autostart task.
- A Chromium-based browser (Edge or Chrome) for the dedicated app window; any browser
  works for the plain page.

No Node, no build step, no package manager: the front end is a single static HTML file.

## Licence

No licence file is present in the repository yet.
