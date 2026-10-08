# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    Sonde : historique Windows Update. LECTURE SEULE, RAPIDE.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$lastBoot = (Get-BootTime).ToString('o')

$wm    = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -ErrorAction SilentlyContinue).Start
$wmTxt = switch ($wm) { 4 {'Désactivé'} 3 {'Manuel'} 2 {'Auto'} default {'inconnu'} }

# The button that opens the folder opens a CONFIGURED administration folder (Get-AdminRoot). That it depends on a
# path of the machine is legitimate -- but a button that can do nothing is worse than no button: with no path
# configured, or if it points into the void, the action is not offered at all.
$actions = @()
$adminRoot = $null
try { $adminRoot = Get-AdminRoot -Backend $backend } catch { }
if ($adminRoot -and (Test-Path -LiteralPath $adminRoot)) {
    $actions += New-Action -Id 'open-folder' -Label 'Ouvrir le dossier' -Kind 'manual' `
        -Help ("Ouvre le dossier d'outils d'administration dans l'explorateur Windows : " + $adminRoot)
}

# SCOPE: the computer's updates. Windows Update is not an account's business.
New-ModuleObject -Id 'wu-history' -Theme 'windows-update' -Label 'Historique' -Scope 'machine' -Status 'ok' -Fields @(
    New-Field -Key 'lastReboot' -Label 'Dernier redémarrage' -Value $lastBoot -Kind 'date' -Status 'neutral' `
        -Help 'Date et heure du dernier démarrage de Windows.'
    New-Field -Key 'waasMedic' -Label 'WaaSMedic (démarrage)' -Value $wmTxt -Kind 'text' -Status $(if ($wmTxt -eq 'Désactivé') {'ok'} else {'neutral'}) `
        -Help 'Service Windows Update Medic : répare et réactive automatiquement Windows Update (défait les désactivations). Désactivé = neutralisé ; Manuel/Auto = il peut encore agir.'
) -Actions $actions
