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

**Three moves, no command line.**

1. Download `vigie-<version>.zip` from the [Releases page](https://github.com/Cartman34/vigie-windows/releases).
2. Unzip it **somewhere permanent** — not `Downloads`, not a temporary folder: Vigie will start from that path every
   time you log in.
3. Open the folder you get and double-click **`setup.cmd`**. Windows asks for your consent to elevate: accept.

Vigie installs itself, adds itself to your session start, and opens. There is nothing else to do and nothing to
reinstall afterwards: `setup.cmd` takes care of whatever the machine is missing. If you ever close Vigie,
`scripts\run.cmd` brings it back.

*If the Releases page is empty, no version has been published yet: see the git route below.*

**The other routes** — git clone, command line, what each script does, uninstalling — live in
[Install](doc/en/operating/install.md). What you are looking at on first launch:
[Getting started](doc/en/using/getting-started.md).

## Read this before you install

Vigie is not a passive monitor. Three things you must know:

1. **It can lock Windows Update.** It is a feature you switch on and off from the
   application, not a state imposed on you. When the lock is on, automatic updates are switched off
   (`NoAutoUpdate`) and an ACL lock prevents Windows from re-enabling its update tasks.
   No update installs itself, and **no reboot is ever forced** — but nothing installs
   itself either. Keeping a machine patched becomes *your* deliberate act, from Vigie's
   "Update mode" or from Windows Settings. See [Windows Update](doc/en/using/windows-update.md).
2. **It runs as administrator.** Reading and applying that lock means registry writes
   under `HKLM`, scheduled-task changes and ACL changes. The scheduled task that starts
   Vigie is registered with the highest privileges, and starting it by hand triggers a
   UAC prompt. Every elevation is explained in a window *before* the UAC prompt appears.
3. **It listens on 127.0.0.1 only** — never on a network interface. The API requires a
   bearer token, checks the request origin, and only runs actions from a fixed
   whitelist. There is one known residual risk (the token is injected into the served
   page), described honestly in [Security](doc/en/operating/security.md).

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

Full detail, card by card: [What Vigie monitors](doc/en/using/features.md).

## Documentation

| | |
|---|---|
| [Documentation index](doc/en/README.md) | everything, in one page |
| [Installation](doc/en/operating/install.md) | archive or git clone, autostart, uninstall |
| [Getting started](doc/en/using/getting-started.md) | first launch, tray icon, reading a card |
| [What Vigie monitors](doc/en/using/features.md) | every card and every action |
| [Windows Update](doc/en/using/windows-update.md) | the lock, update mode, installing updates |
| [Security](doc/en/operating/security.md) | elevation, local binding, token, residual risk |
| [Configuration](doc/en/operating/configuration.md) | port, external tooling, local overrides |
| [Troubleshooting](doc/en/using/troubleshooting.md) | logs, tray commands, common failures |
| **[Development](doc/en/developing/README.md)** | architecture, probes and actions, contributing |

## Requirements

- **Windows 10 or 11.**
- **An administrator account**: Vigie changes Windows Update settings and registers a startup task.
- **A browser.** Edge or Chrome for the dedicated window, with no address bar; any browser for the ordinary page.

The rest is plumbing that `setup.cmd` puts in place itself — you neither install it nor need to know what it is. The
detail is in [Install](doc/en/operating/install.md) for whoever wants to read it.

## Licence

No licence file is present in the repository yet.
