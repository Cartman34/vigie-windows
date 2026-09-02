# @author Florent HAZARD <f.hazard@sowapps.com>
<# READING: is the current game draining the battery?

   CHEAP, and that is the condition: this runs for ever, even with no session open. It does
   NOT look for the game -- finding it again would cost two snapshots of every process. It
   reads the session opened by the Gaming card (var/run/game-session.json), checks the
   process is still alive, and compares today's charge with the one at the start of play.

   The value is COMPARABLE and moves in STEPS: "baisse-10", then "baisse-15"... Every step
   crossed is a change, hence an event, hence a recomputation of the Gaming card -- and the
   toggle of its "Alimentation" field is what sends the Windows bubble (D54). Without steps,
   a continuous drain would have raised a single event, at the very beginning.

   See doc/progress/targeting/surveillance.md.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$session = Get-GameSession -Backend $backend
if (-not $session) { 'non'; return }

# Plugged in, or no battery at all: nothing to report.
$battery = Get-BatteryState
if (-not $battery.OnBattery -or $null -eq $battery.Pct) { 'non'; return }

$drop = [int]$session.startPct - [int]$battery.Pct
$threshold = [int](Get-ModuleSetting -Unit 'gaming' -Key 'BatteryDropWarnPct'); if (-not $threshold) { $threshold = 10 }
if ($drop -lt $threshold) { 'non'; return }

# Five-point steps: we warn again when the drain deepens, not at every reading.
'baisse-' + ([math]::Floor($drop / 5) * 5)
