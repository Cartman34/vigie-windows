# Troubleshooting

[Documentation index](README.md) · [Français](../fr/depannage.md)

---

## First reflexes

| Question | Answer |
|---|---|
| Is the server alive? | open <http://127.0.0.1:47600/api/v1/health> — it needs no token |
| Is the tray alive? | `pwsh -File .\scripts\tray.ps1 -Status` |
| Where are the logs? | tray menu → **Open the logs**, or `apps\backend-pode\var\log\` |

## Common situations

### The page shows amber "mock" data

The strip under the header is amber: the page could not reach the API and fell back to the
bundled sample `apps/frontend-web/mock/state.json`. The server is not running, or not on
the expected port. Restart it from the tray menu, or run `scripts\run.ps1`.

### Nothing happens at logon

The scheduled task is not registered, or points at a folder that has moved. Re-run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

It is idempotent, and it re-registers the task on the current folder. If you moved or
renamed the Vigie folder, this is the fix.

### The tray icon is red

The server is stopped or failing. Tray menu → **Restart the server**, then **Open the
logs** and read `pode-error_*.log` and the most recent `start_*.log`.

### The tray icon is gone but Vigie is still running

The tray runs elevated, so a normal session cannot signal it directly. Use the dedicated
controller, which drops an order file the tray picks up:

```powershell
pwsh -File .\scripts\tray.ps1 -Status     # alive? since when? showing what?
pwsh -File .\scripts\tray.ps1 -Restart    # relaunch it
pwsh -File .\scripts\tray.ps1 -Stop       # stop it cleanly, releasing the icon
```

Exit codes: `0` success, `1` tray not running, `2` the order was not acted on in time
(default 15 s, `-TimeoutSec` to change). If it times out, the tray may be frozen — look in
`apps\tray\var\log\` and `apps\tray\var\run\`.

To start it again: `Start-ScheduledTask -TaskName Vigie`, or `scripts\start-vigie.vbs`.

### A card spins forever

Background jobs can die without writing anything (machine suspended, process killed).
Package-manager cards give up after **45 minutes** and stop showing as busy. For the
others, restart the server from the tray menu.

### "External tooling not configured"

Expected, and not a bug: the Windows Update lock/unlock, the audit and the VBS toggles
call scripts that do not ship with this repository. See
[Configuration](configuration.md#external-tooling).

### "Lock now" reports the ACL lock could not be applied

Windows protects some of those task folders. Vigie tells you exactly that instead of
claiming success, and points at the log it wrote. Automatic updates are still switched
off, which is the part that matters most — but expect the *ACL lock* field to stay amber.

### The dedicated window will not open

`--app` mode only exists on Chromium browsers. Without Edge or Chrome, use **Open in the
browser** from the tray menu.

### PowerShell refuses to run the scripts

Use the `.cmd` launchers (`scripts\run.cmd`, `scripts\install-autostart.cmd`), which pass
`-ExecutionPolicy Bypass`. If you installed from a downloaded archive, unblock the files
once:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

### "pwsh not found"

PowerShell 7 is missing. `scripts\install.ps1` installs it via winget, then asks you to
run it again. Without winget: <https://aka.ms/powershell-release>.

### Port 47600 is already in use

Set another port in `apps/backend-pode/config/config.local.psd1` — see
[Configuration](configuration.md). Everything else derives from it, including the desktop
shortcut, so re-run `install-autostart.ps1` afterwards.

---

## The log files

| File | Written by |
|---|---|
| `apps\backend-pode\var\log\install_*.log` | `scripts\install.ps1` (full transcript) |
| `apps\backend-pode\var\log\run_*.log` | `scripts\run.ps1` — what it decided and why |
| `apps\backend-pode\var\log\start_*.log` | the server itself |
| `apps\backend-pode\var\log\pode-error_*.log`, `pode-request_*.log` | the Pode runtime |
| `apps\backend-pode\var\log\action-*.log` | individual actions, when they log |
| `apps\tray\var\log\tray_*.log` | the tray app |

Elevated scripts write their output to a log file and the calling process reads it back —
a report from an elevated run is never lost.

## Still stuck

Open an issue on <https://github.com/Cartman34/vigie-windows/issues>, with the relevant
log excerpt, your Windows and PowerShell versions, and whether the server was elevated.
Vigie is at **v0.1 and unpublished**; rough edges are expected.
