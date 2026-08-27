# Windows Update

[Documentation index](../README.md) · [Français](../../fr/using/windows-update.md)

This is Vigie's headline feature and the one that changes how your machine behaves. Read
it before you press anything on the *Update lock* card.

---

## The problem it solves

Windows decides on its own when to download, install and **reboot**. On a machine that is
mid-work, mid-render or mid-transfer, that decision is not yours and cannot be argued
with. Deferral settings buy hours, not control.

## What the lock actually does

When the lock is on:

- **Automatic updates are switched off** — `NoAutoUpdate = 1` under
  `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`.
- **An ACL lock is applied** to the Windows Update scheduled-task folders — a *deny* for
  the `SYSTEM` account on `UpdateOrchestrator`, `WindowsUpdate`, `InstallService` and
  `WaaSMedic`. This is what stops Windows from silently re-enabling the tasks it repairs
  by design.
- Update tasks are disabled. Some remain "Ready" because Windows protects them under
  TrustedInstaller; they are harmless while automatic updates are off, and the card shows
  the real state of every one of them if you expand the field.

What it does **not** do: it does not hide updates, does not block Windows Update as a
service, and does not stop you installing anything. It removes Windows' ability to act
without you.

## Reading the card

| Field | What to make of it |
|---|---|
| **Automatic updates** | *No* is the locked, intended state |
| **ACL lock on tasks** | *No* is common right after a large update or a stint in update mode — press *Lock now* to reapply |
| **Disabled tasks** / **Active tasks** | informational; expand for the actual state of each task |
| **Pending reboot** | amber, and not a fault: an update installed successfully and Windows wants to finish. Reboot when it suits you — Vigie never does it for you |

The card is green when automatic updates are off, amber when they are not, red only when
a reboot is pending.

---

## Installing updates

You have three ways, all of them deliberate.

### From Vigie (recommended)

1. Press **Check for updates** on the *System update* card. This runs a real **online**
   scan against Microsoft's servers — it takes minutes, so it runs as a detached
   background job and the card shows it as busy. The number the card shows the rest of the
   time comes from the local Windows Update cache and is instantaneous.
2. Press **Install updates**. A window lists what was found; **you choose** what to
   install. An empty selection is refused rather than read as "install everything".
3. The installation also runs in the background. Closing the browser does not interrupt
   it.

While scanning or installing, Vigie **lifts its own lock and puts it back afterwards**.
It tells you it is doing so. Undoing by hand a lock the application applied itself would
make no sense, so it is handled internally.

### Update mode

Press **Update mode (unlock)** on the *Update lock* card (confirmation required). Windows
Update is back to normal: install what you want from Windows Settings, reboot when *you*
decide, then come back and press **Lock now**.

Do not forget the second half. While the lock is off, Windows can and will reboot you.

### Windows Settings

The **Open Windows Update** button simply hands you over to the Settings panel. Useful
when you want Windows' own interface; the lock state still applies.

---

## Locking, unlocking and auditing are all native

Both the read and the write side live in this repository. The *Update lock* card reads the
registry, the scheduled tasks and the ACLs itself; `Update mode (unlock)`, `Lock now` and
`Run the audit` act without any outside script either. An install straight from GitHub
therefore gets the whole feature.

The one requirement is **elevation**: setting or lifting the lock changes permissions on
system folders. If the Vigie server is not running as administrator, those buttons say so
in one sentence and touch nothing — rather than half-failing in silence.

`ToolsPath` stays **optional**: if it points at a folder holding `update-mode.ps1`, Vigie
prefers it (existing installs); otherwise it uses its own implementation. Its absence no
longer blocks anything. See [Configuration](../operating/configuration.md#external-tooling).

## Vigie checks the result, it does not trust the return code

After a lock, Vigie re-reads the ACL and the registry key and reports what it actually
obtained:

- both applied → "full lock applied";
- automatic updates off but the ACL refused (folders protected by Windows) → it says so,
  and points at the log file;
- neither → it reports failure, with the log.

You are never told "done" on the strength of a command that merely did not raise an error.

---

## Unlocking for good

Removing Vigie does **not** unlock Windows Update. If you are uninstalling, press
**Update mode (unlock)** first and confirm the *Automatic updates* field reads *Yes*.
Otherwise your machine keeps its automatic updates disabled, with nothing left on screen
to tell you why.

## Next

- [What Vigie monitors](features.md) — the other themes
- [Security](../operating/security.md) — why all this needs administrator rights
