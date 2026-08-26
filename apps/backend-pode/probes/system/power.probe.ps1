<# Sonde : ALIMENTATION d'un portable. LECTURE SEULE, rapide.

   La question posee : « je peux etre sur secteur mais SOUS-ALIMENTE, j'aimerais le
   voir et etre alerte ». Le fait qui le prouve est mesurable : branche au secteur ET
   batterie en decharge, c'est que le chargeur ne couvre pas la consommation. Une
   charge qui traine alors que la batterie est loin d'etre pleine dit la meme chose,
   en moins brutal.

   Machine SANS batterie (fixe) : la sonde ne rend RIEN, donc pas de carte.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# root/wmi BatteryStatus est la seule source qui dise les trois choses a la fois :
# secteur present, sens du courant, et sa puissance. Win32_Battery ne donne qu'un
# statut agrege et le pourcentage.
function Get-EtatAlim {
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

$etat = Get-EtatAlim
if (-not $etat) { return }   # pas de batterie : rien a dire

$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
$pct = if ($bat -and $null -ne $bat.EstimatedChargeRemaining) { [int]$bat.EstimatedChargeRemaining } else { $null }

$seuilChargeW = [int](Get-ModuleSetting -Unit 'system' -Key 'ChargeSlowW')
$seuilBatPct  = [int](Get-ModuleSetting -Unit 'system' -Key 'BatteryLowPct')

# --- Sous-alimentation ---------------------------------------------------------
# Une pointe de consommation peut faire basculer la batterie en decharge une seconde
# alors que tout va bien. On ne crie donc qu'apres une SECONDE mesure, prise un peu
# plus tard -- et seulement quand la premiere a vu un probleme : le cas normal ne
# paie pas cette attente.
$soucis = $null
if ($etat.Secteur -and $etat.Decharge) {
    Start-Sleep -Milliseconds 800
    $e2 = Get-EtatAlim
    if ($e2 -and $e2.Secteur -and $e2.Decharge) {
        $w = [math]::Round((([math]::Max($etat.DechMw, $e2.DechMw)) / 1000.0), 1)
        $soucis = "Le secteur ne suit pas : la batterie se décharge" + $(if ($w -gt 0) { " ($w W)" })
    }
} elseif ($etat.Secteur -and $etat.Charge -and $null -ne $pct -and $pct -lt 80) {
    $wc = [math]::Round(($etat.ChargeMw / 1000.0), 1)
    if ($wc -gt 0 -and $wc -lt $seuilChargeW) {
        Start-Sleep -Milliseconds 800
        $e2 = Get-EtatAlim
        if ($e2 -and $e2.Secteur -and $e2.Charge -and (($e2.ChargeMw / 1000.0) -lt $seuilChargeW)) {
            $soucis = "Charge très lente ($wc W) : chargeur sous-dimensionné ou port peu puissant"
        }
    }
}

# --- Ce qui se passe, en clair -------------------------------------------------
$source = if ($etat.Secteur) { 'Secteur' } else { 'Batterie' }
$sens =
    if ($etat.Decharge)  { $w = [math]::Round(($etat.DechMw / 1000.0), 1);   "Décharge de $w W" }
    elseif ($etat.Charge) { $w = [math]::Round(($etat.ChargeMw / 1000.0), 1); "Charge à $w W" }
    else { 'Aucun échange : batterie stable' }

$fields = @()
$fields += New-Field -Key 'source' -Label 'Source' -Value $source -Kind 'text' `
    -Status $(if ($etat.Secteur) { 'ok' } else { 'neutral' }) `
    -Help 'Ce qui alimente la machine en ce moment.'

# CE CHAMP EXISTE TOUJOURS, meme quand tout va bien : le tray notifie sur la BASCULE
# d'un champ, et un champ qui n'apparait qu'en cas de probleme ne bascule jamais.
$fields += $(if ($soucis) {
        New-Field -Key 'under' -Label 'Alimentation' -Value $soucis -Kind 'text' -Status 'warn' `
            -FixAction 'open-power-options' `
            -Help 'Sur secteur, la machine devrait charger. Si elle se décharge quand même, le chargeur ne couvre pas la consommation : le processeur et le GPU vont être bridés, et la batterie se videra malgré le branchement.' `
            -Guide "Vérifiez que le chargeur est bien celui de la machine et qu'il est branché sur le port d'alimentation (pas un port USB-C secondaire ni un dock peu puissant). Sous forte charge, un chargeur trop faible ne suffit pas."
    } elseif (-not $etat.Secteur) {
        New-Field -Key 'under' -Label 'Alimentation' -Value 'Sans objet : sur batterie' -Kind 'text' -Status 'ok' `
            -Help 'La sous-alimentation ne se juge que branché au secteur.'
    } else {
        New-Field -Key 'under' -Label 'Alimentation' -Value 'Suffisante' -Kind 'text' -Status 'ok' `
            -Help 'Le secteur couvre la consommation de la machine.'
    })

if ($null -ne $pct) {
    $batBas = ((-not $etat.Secteur) -and $pct -lt $seuilBatPct)
    $fields += New-Field -Key 'charge' -Label 'Batterie' -Value $pct -Kind 'number' -Unit '%' `
        -Status $(if ($batBas) { 'warn' } else { 'neutral' }) `
        -Help 'Charge restante de la batterie.'
}
$fields += New-Field -Key 'rate' -Label 'Courant' -Value $sens -Kind 'text' -Status 'neutral' `
    -Help 'Puissance échangée avec la batterie : ce qui entre en charge, ce qui sort en décharge.'

New-ModuleObject -Id 'power' -Theme 'system' -Label 'Alimentation' `
    -Status $(if ($soucis) { 'warn' } else { 'ok' }) `
    -Fields $fields `
    -Actions @(New-Action -Id 'open-power-options' -Label 'Options d''alimentation' -Kind 'manual' -Severity 'info' `
                          -Help 'Ouvre les réglages Windows d''alimentation et de mise en veille.')
