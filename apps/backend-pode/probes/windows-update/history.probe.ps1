# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    Sonde : historique Windows Update. LECTURE SEULE, RAPIDE.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$os       = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$lastBoot = if ($os) { $os.LastBootUpTime.ToUniversalTime().ToString('o') } else { $null }

$wm    = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -ErrorAction SilentlyContinue).Start
$wmTxt = switch ($wm) { 4 {'Désactivé'} 3 {'Manuel'} 2 {'Auto'} default {'inconnu'} }

# « Ouvrir le dossier » ouvre un dossier d'administration CONFIGURE (Get-AdminRoot). Qu'il
# depende d'un chemin de la machine est legitime -- mais un bouton qui ne peut rien faire
# est pire que pas de bouton : sans chemin configure, ou s'il pointe dans le vide,
# l'action n'est pas proposee du tout.
$actions = @()
$adminRoot = $null
try { $adminRoot = Get-AdminRoot -Backend $backend } catch { }
if ($adminRoot -and (Test-Path -LiteralPath $adminRoot)) {
    $actions += New-Action -Id 'open-folder' -Label 'Ouvrir le dossier' -Kind 'manual' `
        -Help ("Ouvre le dossier d'outils d'administration dans l'explorateur Windows : " + $adminRoot)
}

New-ModuleObject -Id 'wu-history' -Theme 'windows-update' -Label 'Historique' -Status 'ok' -Fields @(
    New-Field -Key 'lastReboot' -Label 'Dernier redémarrage' -Value $lastBoot -Kind 'date' -Status 'neutral' `
        -Help 'Date et heure du dernier démarrage de Windows.'
    New-Field -Key 'waasMedic' -Label 'WaaSMedic (démarrage)' -Value $wmTxt -Kind 'text' -Status $(if ($wmTxt -eq 'Désactivé') {'ok'} else {'neutral'}) `
        -Help 'Service Windows Update Medic : répare et réactive automatiquement Windows Update (défait les désactivations). Désactivé = neutralisé ; Manuel/Auto = il peut encore agir.'
) -Actions $actions
