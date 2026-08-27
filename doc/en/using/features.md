# What Vigie monitors

[Documentation index](../README.md) · [Français](../../fr/using/features.md)

Every card below exists in the code today (a *probe* under
`apps/backend-pode/probes/`); every button is a real *action* under
`apps/backend-pode/actions/`. Nothing here is planned or aspirational.

Cards appear only when they are relevant: no WSL card without WSL, one package-manager
card per manager actually found in your `PATH`.

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
