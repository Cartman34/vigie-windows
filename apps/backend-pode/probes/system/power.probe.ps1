# @author Florent HAZARD <f.hazard@sowapps.com>
<# A probe: the POWER SUPPLY of a laptop. READ ONLY, fast.

   Intent: answer the question that was asked -- "I may be on mains power and yet UNDER-POWERED, I would like to
   see it and be warned". The fact that proves it is measurable: plugged into the mains AND the battery
   discharging means the charger does not cover the consumption. A charge that drags on while the battery is far
   from full says the same thing, less brutally.
   Usage: it is run by the scheduler like any probe.

   A machine WITHOUT a battery (a desktop): the probe returns NOTHING, so there is no card. #>

$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# The WMI BatteryStatus class is the only source that says all three things at once: the mains present, the
# direction of the current, and its power. Win32_Battery gives only an aggregated status and the percentage.
function Get-PowerState {
    $b = Get-CimInstance -Namespace 'root/wmi' -ClassName 'BatteryStatus' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $b) { return $null }
    [pscustomobject]@{
        Secteur   = [bool]$b.PowerOnline
        Charge    = [bool]$b.Charging
        Decharge  = [bool]$b.Discharging
        ChargeMw  = [int]$b.ChargeRate
        DechMw    = [int]$b.DischargeRate
    }
}

$state = Get-PowerState
if (-not $state) { return }   # pas de batterie : rien a dire

$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
$pct = if ($bat -and $null -ne $bat.EstimatedChargeRemaining) { [int]$bat.EstimatedChargeRemaining } else { $null }

$loadWattsThreshold = [int](Get-ModuleSetting -Unit 'system' -Key 'ChargeSlowW')
$batteryPctThreshold  = [int](Get-ModuleSetting -Unit 'system' -Key 'BatteryLowPct')

# --- Under-powering -----------------------------------------------------------
# A spike of consumption can flip the battery into discharge for a second while all is well. So we cry out only
# after a SECOND measurement, taken a little later -- and only when the first saw a problem: the normal case does
# not pay for that wait.

$soucis = $null
if ($state.Secteur -and $state.Decharge) {
    Start-Sleep -Milliseconds 800
    $e2 = Get-PowerState
    if ($e2 -and $e2.Secteur -and $e2.Decharge) {
        $w = [math]::Round((([math]::Max($state.DechMw, $e2.DechMw)) / 1000.0), 1)
        $soucis = "Le secteur ne suit pas : la batterie se décharge" + $(if ($w -gt 0) { " ($w W)" })
    }
} elseif ($state.Secteur -and $state.Charge -and $null -ne $pct -and $pct -lt 80) {
    $wc = [math]::Round(($state.ChargeMw / 1000.0), 1)
    if ($wc -gt 0 -and $wc -lt $loadWattsThreshold) {
        Start-Sleep -Milliseconds 800
        $e2 = Get-PowerState
        if ($e2 -and $e2.Secteur -and $e2.Charge -and (($e2.ChargeMw / 1000.0) -lt $loadWattsThreshold)) {
            $soucis = "Charge très lente ($wc W) : chargeur sous-dimensionné ou port peu puissant"
        }
    }
}

# --- What is happening, in plain words ----------------------------------------
$source = if ($state.Secteur) { 'Secteur' } else { 'Batterie' }
$sens =
    if ($state.Decharge)  { $w = [math]::Round(($state.DechMw / 1000.0), 1);   "Décharge de $w W" }
    elseif ($state.Charge) { $w = [math]::Round(($state.ChargeMw / 1000.0), 1); "Charge à $w W" }
    else { 'Aucun échange : batterie stable' }

$fields = @()
$fields += New-Field -Key 'source' -Label 'Source' -Value $source -Kind 'text' `
    -Status $(if ($state.Secteur) { 'ok' } else { 'neutral' }) `
    -Help 'Ce qui alimente la machine en ce moment.'

# THIS FIELD ALWAYS EXISTS, even when all is well: the client app notifies on a field's FLIP, and a field that
# only appears when there is a problem never flips.
$fields += $(if ($soucis) {
        New-Field -Key 'under' -Label 'Alimentation' -Value $soucis -Kind 'text' -Status 'warn' `
            -FixAction 'open-power-options' `
            -Help 'Sur secteur, la machine devrait charger. Si elle se décharge quand même, le chargeur ne couvre pas la consommation : le processeur et le GPU vont être bridés, et la batterie se videra malgré le branchement.' `
            -Guide "À vérifier : le chargeur doit être celui de la machine, branché sur le port d'alimentation (pas un port USB-C secondaire ni un dock peu puissant). Sous forte charge, un chargeur trop faible ne suffit pas."
    } elseif (-not $state.Secteur) {
        New-Field -Key 'under' -Label 'Alimentation' -Value 'Sans objet : sur batterie' -Kind 'text' -Status 'ok' `
            -Help 'La sous-alimentation ne se juge que branché au secteur.'
    } else {
        New-Field -Key 'under' -Label 'Alimentation' -Value 'Suffisante' -Kind 'text' -Status 'ok' `
            -Help 'Le secteur couvre la consommation de la machine.'
    })

if ($null -ne $pct) {
    $batBas = ((-not $state.Secteur) -and $pct -lt $batteryPctThreshold)
    $fields += New-Field -Key 'charge' -Label 'Batterie' -Value $pct -Kind 'number' -Unit '%' `
        -Status $(if ($batBas) { 'warn' } else { 'neutral' }) `
        -Help 'Charge restante de la batterie.'
}
# "Current" was wrong: a current is measured in amperes, and this value is a POWER, in watts. The direction is
# read in the words (charging at, discharging by) rather than in a sign to be interpreted.
# "Power" on its own read as the consumption of the MACHINE. That is false: only the battery's flow is measurable
# here -- Windows exposes neither the total consumption (no metering interface on this machine) nor what the
# charger supplies. So the label says it, and the guide gives the only honest measurement of the total.


$fields += New-Field -Key 'rate' -Label 'Puissance batterie' -Value $sens -Kind 'text' -Status 'neutral' `
    -Help 'Puissance échangée avec la batterie, en watts : ce qui y entre en charge, ce qui en sort en décharge. Ce n''est PAS la consommation de la machine.' `
    -Guide ("Sur secteur avec une batterie pleine, rien ne circule : il n'y a donc pas de watts à afficher." + [Environment]::NewLine +
            "Windows n'expose pas ce que le chargeur fournit à la machine, et cet ordinateur n'a pas d'interface de comptage d'énergie." + [Environment]::NewLine +
            "Pour connaître la consommation réelle : débranchez. La décharge affichée ici est alors exactement ce que la machine consomme, tout compris.")

# SCOPE: the battery and the power plan of the computer.
New-ModuleObject -Id 'power' -Theme 'system' -Label 'Alimentation' -Scope 'machine' `
    -Status $(if ($soucis) { 'warn' } else { 'ok' }) `
    -Fields $fields `
    -Actions @(New-Action -Id 'open-power-options' -Label 'Options d''alimentation' -Kind 'manual' -Severity 'info' `
                          -Help 'Ouvre les réglages Windows d''alimentation et de mise en veille.')
