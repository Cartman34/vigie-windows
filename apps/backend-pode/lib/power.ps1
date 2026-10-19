# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: MAINS OR BATTERY, and how much is left. Two readings, asked of Windows, with a simulation door for testing what a low battery does to the panel.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    ONE WATCH ROUND. Returns the list of events raised, or an empty array.

    It runs the readings that are DUE, compares them, and on a change has the declared cards
    recomputed THROUGH THE EXISTING PATH (Get-State -Only). No second mechanism.
#>
<#
    THE GAME UNDER WAY: one single fact, written by the Gaming probe, read back by its sentinel.

    The probe knows which game is running -- it has just proved it, with two snapshots of
    every process to back it. The sentinel, on the other hand, must stay cheap: it runs every
    minute, permanently. So it does not redo the work, it reads what the probe noted: the
    name, the process, the start time and THE BATTERY CHARGE AT THE START -- without which
    "the battery is draining during the game" cannot be said, only "the battery is low",
    which is not the same information.

    The session lives in var/run: it does not survive a restart, and rightly so -- neither
    does a game.
#>
<#
    THE STATE OF THE POWER SUPPLY, in one place: on mains or not, and the charge.

    The Gaming probe and its sentinel asked the same question in two places, with two
    pieces of code: two chances to drift apart. And above all, neither was TESTABLE without
    unplugging the machine and starting a game -- which is to say never.

    VIGIE_FAKE_BATTERY=<percentage> simulates a machine on battery at that charge, as
    VIGIE_FAKE_GAME simulates a game (doc/en/developing/modules.md). The two together replay
    the whole scene: a game draining the battery.
#>
<#
    IS IT CHARGING OR DRAINING? That is the fact to watch, not the source.

    Being "on mains" says little: plugged in but discharging means a charger that cannot keep
    up; unplugged, it is normal. What matters, and what must wake a card, is the DIRECTION of
    the current.

    Returns 'charge', 'decharge', 'stable' (nothing coming in or going out: a full battery on
    mains) or 'aucune' (a machine with no battery). A reading, with no wake-up and no
    computation.
#>
function Get-PowerFlow {
    if ($env:VIGIE_FAKE_BATTERY) { return 'decharge' }
    $b = Get-CimInstance -Namespace 'root/wmi' -ClassName 'BatteryStatus' -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if (-not $b) { return 'aucune' }
    if ($b.Discharging) { return 'decharge' }
    if ($b.Charging)    { return 'charge' }
    return 'stable'
}

function Get-BatteryState {
    if ($env:VIGIE_FAKE_BATTERY) {
        return @{ OnBattery = $true; Pct = [int]$env:VIGIE_FAKE_BATTERY; Simulated = $true }
    }
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    # No battery at all (a desktop machine): on mains, and no charge to speak of.
    if (-not $battery) { return @{ OnBattery = $false; Pct = $null; Simulated = $false } }
    # BatteryStatus 1 = discharging; any other value means the mains is supplying it.
    return @{ OnBattery = ($battery.BatteryStatus -eq 1)
              Pct       = [int]$battery.EstimatedChargeRemaining
              Simulated = $false }
}
