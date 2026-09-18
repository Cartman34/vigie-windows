# Creating and maintaining a module — THE reference

> This document is **the** procedure: every creation or change of a module follows it, and every subagent brief that
> touches probes points here. What follows comes from the decisions (D41, D43, D44, D48, D49, D50, D57) — the detail of
> each rule is in `doc/progress/decisions.md`.

## The model in one sentence

A **module** = a **folder of probes** (`apps/backend-pode/probes/<id>/`), declared by a versioned `module.psd1`; each
**probe** (`*.probe.ps1`) returns one or more **cards**; the user enables/disables the module and sets its
**parameters** in the Settings menu.

## Creating a module, step by step

1. **The folder**: `apps/backend-pode/probes/<id>/` — `<id>` in English, lower case; it is also the theme's identifier
   (group on screen).
2. **The declaration** `module.psd1`:
   ```powershell
   @{
       Label       = 'Nom affiché'          # accented French
       Description = 'Une phrase.'          # shown in Settings > Modules
       Config      = @{ ThresholdX = 10 }   # DEFAULT values, versioned (D57)
       Parameters  = @(                     # the Config keys adjustable on screen
           @{ Key='ThresholdX'; Label='…'; Type='int'; Unit='%'; Help='…' }
       )
   }
   ```
   Every adjustable default lives in `Config`; the probe NEVER reads the local override file — only
   `Get-ModuleSetting -Unit '<id>' -Key 'ThresholdX'` (with a hard-coded fallback should the declaration disappear).
3. **The theme**: add the entry to `$script:ThemeCatalog` (`lib/common.ps1`) — the folder id, a French label.
4. **The TTL**: add the probe to `$script:ProbeTtls` (`lib/common.ps1`) — short if it moves fast (5–15 s), long if it is
   stable (10–60 min). Without an entry: 30 s.
5. **The probe** `<name>.probe.ps1`: at its head, the comment says WHAT IT ANSWERS and how it measures; then
   `New-ModuleObject -Id … -Theme '<folder id>' -Label … -Status … -Fields @(New-Field …)`. READ ONLY: a probe never
   acts.

## What a card must say (D49 — the checker verifies it)

- The **module status** never exceeds that of its worst field.
- Every field carries a **help** (`-Help`): it describes what the field SHOWS (tooltip).
- Every `warn`/`error` field carries **a resolution button** (`-FixAction`) — ALWAYS (**D66**) — and, in addition, a
  `-Guide` that explains. The button repairs, or leads to where the user decides (Task Manager, Device Manager…). What
  cannot be resolved is not alerted: a wait stays **neutral**. `check-probes.ps1` verifies it.
- **Every problem gives its reasons, as far as they can be measured**: the causes, not only the symptom. A resource
  that alerts names what consumes it; a failure names what failed and why. *Asked by the owner on 18/09: the Resources
  card said "RAM 93 %" and nothing else, while the Windows Virtual Machine of WSL held 14 GB.*
- An **expected but missing piece of information** is a `warn` with a lead to a solution, never a silent row.
- During an operation: say **what, out of how many, since when**; afterwards: the **result stays visible**. Ellipses
  are reserved for an action in progress (D50).
- Every action cited by a field must exist in `actions/`; action labels follow `kind`/`severity`/`busyLabel` (D50).

## Testability: a probe must be testable WITHOUT its event

A probe with a branch that only runs in a rare situation (a game running, a failure, a lock in place) must offer a
**way to force that branch** with real data — even if they are worth 0:

- convention: an environment variable `VIGIE_FAKE_<WHAT>` documented at the head of the probe (example:
  `VIGIE_FAKE_GAME='chrome'` treats chrome as the game, `VIGIE_FAKE_BATTERY='88'` simulates a computer on battery at
  88 %);
- **they combine**: together, those two replay a scene that otherwise only happens by unplugging the computer and
  launching a game — so never;
- the simulation does **not** make up values: it forces the **path**, the measurements stay real;
- the test is part of validation before delivery (see below);
- a **manufactured load** (GPU, CPU, disk) is **never started without the user's explicit authorisation, asked again
  every time** (**D62**) — the recipe below is usable only within that frame: `scripts/dev/gpu-load.html` (heavy WebGL)
  opened in a Chrome with a throwaway profile raises the GPU to test game detection — with MANDATORY
  `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling`
  (Chrome freezes the rendering of an occluded window, seen in a remote session), then `taskkill /T` on the launched
  PID and deletion of the profile. Tested on 24/08: chrome seen at 19 % GPU and designated as the game, without
  simulation.

## Validating before delivery (in this order)

> **What follows is the ORDINARY test: the contract, nothing else** (**D63**). Probes are read only. Running an
> **action** or a **worker** for real, or driving the application end to end, is an **integration** test: it is
> **asked** of the user, every time — like any manufactured load (**D62**).

```powershell
# 1. Dev loop: the touched probe, run for real
pwsh -File .\scripts\check-probes.ps1 -Only <id>
# 2. The rare branches, forced (if the probe has any)
$env:VIGIE_FAKE_GAME='chrome'; pwsh -File .\scripts\check-probes.ps1 -Only gaming; Remove-Item Env:VIGIE_FAKE_GAME
# 2 bis. A game draining the battery: both simulations together
$env:VIGIE_FAKE_GAME='chrome'; $env:VIGIE_FAKE_BATTERY='88'; pwsh -File .\scripts\check-probes.ps1 -Only gaming
Remove-Item Env:VIGIE_FAKE_GAME, Env:VIGIE_FAKE_BATTERY
# 3. Before merging: the full pass
pwsh -File .\scripts\check-probes.ps1 -All
```

The parser is not enough (D50bis); the return code is not enough either: the output is **observed** (D43). Dates: UTC
when writing, `ConvertTo-UtcDate` when reading back (D44).

## Maintaining

- A new threshold or setting → a `Config` key + a `Parameters` entry, never a number hard-coded in the probe.
- A change visible on screen → carry it onto the Atelier's "Design système" page in the same delivery
  (`doc/en/developing/design.md`).
- A new module → it appears automatically in Settings > Modules (catalogue); check that disabling/re-enabling works.
- After any served change: reload the **served** page (never `file://`, D47).
