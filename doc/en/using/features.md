# What Vigie monitors

[Documentation index](../README.md) · [Français](../../fr/using/features.md)

Every card below exists in the code today (a *probe* under
`apps/backend-pode/probes/`); every button is a real *action* under
`apps/backend-pode/actions/`. Nothing here is planned or aspirational.

Cards appear only when they are relevant: no WSL card without WSL, one package-manager
card per manager actually found in your `PATH`.

---

## The interface, in detail

### The tray menu

Right-clicking the icon opens this menu. The tray polls the server every 8 seconds: the gauge colour is never more than
a few seconds behind.

| Entry | Effect |
|---|---|
| **Show the application** | opens the dashboard in a dedicated window (Edge or Chrome in `--app` mode: no address bar, no tabs) |
| Open in the browser | opens the dashboard in an ordinary tab |
| *Status: …* | not clickable — the current state, spelled out |
| Restart the application | restarts the tray app, and the server with it |
| Restart the server | stops then restarts the Pode server |
| Open the logs | opens the server's log folder in Explorer |
| About Vigie | opens the GitHub repository |
| Quit | closes Vigie (the server stops with it) |

The dedicated window needs a Chromium browser. Failing that, use "Open in the browser".

### The anatomy of a card

The **stripe under the page header** is the API connection: green = live data, amber = mock (the server is unreachable
and the page fell back to a sample set), red = error. Do not confuse it with the **stripe on a card's left edge**,
which carries the status of THAT module:

| Status | Meaning |
|---|---|
| Green | compliant, nothing to do |
| Amber | worth watching |
| Red | a problem |
| Neutral | informational, or not measurable right now |

A left stripe that **blinks** means a background task is running on that card: package upgrade, disk analysis, network
measurement. The page polls that card on its own, and you may close the browser: the task carries on.

### The button icons

| Icon | Meaning |
|---|---|
| Triangle | runs immediately |
| Amber warning triangle | asks for confirmation first |
| Checklist | opens a window where you choose what gets applied |
| Outgoing arrow | hands over to external software (Windows Settings, disk cleanup, Explorer) |

---

## Windows Update

Detailed on its own page: **[Windows Update](windows-update.md)**. Summary:

| Card | Shows | Buttons |
|---|---|---|
| **Update lock** | automatic updates on/off, ACL lock on the task folders, number of disabled vs. still-active update tasks (expand for the real state of each one), pending reboot | *Update mode (unlock)* or *Lock now* — whichever applies, always with confirmation — and *Run the audit* |
| **System update** | updates detected in the local Windows Update cache, last online scan and its result, current or last installation | *Check for updates* (online scan, runs in the background), *Install updates* (opens a list, you pick), *Open Windows Update* |
| **History** | last reboot, WaaSMedic startup state | *Open the folder* — offered **only** when an administration folder is configured |

A **pending reboot is shown as amber, not red**: it is the normal outcome of a successful
installation, not a failure. Vigie never reboots your machine.

## System

| Card | Shows | Buttons |
|---|---|---|
| **Windows** | edition, activation, build | — |
| **Disk C:** | free space, the alert threshold, used percentage, total size. Turns amber below the threshold. | *Disk Cleanup…* (opens Windows' `cleanmgr`) |
| **Resources** | RAM used (%), RAM free, CPU (%), uptime. Amber above 90 % on RAM or CPU. | — |

## Power

| Card | Shows | Buttons |
|---|---|---|
| **Power** | source (mains or battery), battery level, which way the current flows, and above all: **is the charger keeping up?** | *Power options* (opens Windows Settings) |

This card exists **only on a machine with a battery**: a desktop has nothing to say about it. Its point is the case you
cannot see otherwise: plugged in **and** discharging. That means the charger does not cover what the machine draws —
the CPU and GPU will be throttled, and the battery will drain despite being plugged in. The card turns amber and says
so in plain words.

## Gaming

| Card | Shows | Buttons |
|---|---|---|
| **Gaming** | graphics card, VRAM used against the real total, GPU temperature, detected game and what it consumes, other greedy applications during play, power | *Task Manager*, *Device Manager* |

This is a **diagnostic tool**: when the game stutters, the card shows who takes what — CPU, GPU, VRAM, memory, I/O —
and names the application draining resources mid-game. It fixes nothing by itself and changes no setting: it looks.

## Network

| Card | Shows | Buttons |
|---|---|---|
| **Network** | Internet connectivity, connection type, network name, Wi-Fi state, local IP, public IP, IPv6, MAC address, active VPN, latency, download and upload throughput, and when the measurement was taken | *Get the public IP*, *Measure throughput/latency* |

Latency and throughput are **not** measured continuously — they read "not measured" until
you press the button. The measurement pings `1.1.1.1` and transfers roughly 10 MB down and
5 MB up against Cloudflare's speed endpoint. That is the one place Vigie talks to the
outside world on your behalf, and only when you ask.

## Security

| Card | Shows | Buttons |
|---|---|---|
| **Antivirus** | the primary antivirus name, whether it is active, whether its definitions are up to date, and any other product detected. Inactive = red. | — |
| **Firewall** | the state of each Windows Firewall profile. A disabled profile is red. | — |
| **Virtualisation security** | VBS and memory integrity (HVCI) | *Toggle VBS*, *Toggle memory integrity* — both with confirmation |

Both toggles are **native**: they write the value into the registry
(`HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard`), after dropping a `.reg` backup into
Vigie's logs. They require an **administrator** server and say so plainly otherwise.

**They only take effect on reboot.** The card shows it: while the request is not applied, a
*Pending reboot* line appears and the *Restart Windows* button — deferred by 60 seconds,
cancellable — is offered on that card. Clicking the toggle again before rebooting simply
**cancels the request**.

Turning VBS off also turns memory integrity off, since it cannot run without VBS; the
converse is not true — turning VBS on does not silently enable memory integrity. If a value
still does not apply after a reboot, it is enforced by UEFI or by a corporate policy, and
Vigie cannot override it.

## WSL

| Card | Shows | Buttons |
|---|---|---|
| **WSL2** | whether WSL is installed, the default distribution, and a coloured *Active / Inactive* status | *Start* when it is stopped; *Restart* and *Shut down* when it is running |

Only the buttons that make sense for the current state are shown. Inactive turns both the
field **and** the card red.

## Package managers

One card per manager found in your `PATH`, from this catalogue:

| Manager | Version | Check for updates | Upgrade all |
|---|---|---|---|
| winget | yes | yes | yes |
| Chocolatey | yes | yes | yes |
| Scoop | yes | yes | yes |
| npm | yes | yes | yes |
| RubyGems | yes | yes | yes |
| pnpm | yes | yes | — |
| pip (Python) | yes | yes | — |
| Yarn, pipx, Cargo, .NET SDK | yes | — | — |

Each card shows the installed version and its path, plus the number of available updates
and the list of packages once you have checked. *Check for updates* and *Upgrade* both run
as **detached background jobs**: the card goes busy, the page polls it, and closing the
browser does not interrupt anything. A job that produces nothing for 45 minutes is
considered dead and the card stops spinning.

If no manager is found, a single neutral card says so.

---

## What Vigie never does

- It never reboots your machine, and never lets Windows do it while the lock is on.
- It never installs a Windows update you did not select — an empty selection is refused
  rather than read as "all of them".
- It never listens outside `127.0.0.1`.
- It never builds a shell command out of anything the browser sent it.

See [Security](../operating/security.md) for the whole picture.
