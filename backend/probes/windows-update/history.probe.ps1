<#
    Sonde : historique Windows Update. LECTURE SEULE, RAPIDE.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$os       = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$lastBoot = if ($os) { $os.LastBootUpTime.ToUniversalTime().ToString('o') } else { $null }

$wm    = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -ErrorAction SilentlyContinue).Start
$wmTxt = switch ($wm) { 4 {'Désactivé'} 3 {'Manuel'} 2 {'Auto'} default {'inconnu'} }

New-ModuleObject -Id 'wu-history' -Theme 'windows-update' -Label 'Historique' -Status 'ok' -Fields @(
    New-Field -Key 'lastReboot' -Label 'Dernier redémarrage' -Value $lastBoot -Kind 'date' -Status 'neutral' `
        -Help 'Date et heure du dernier demarrage de Windows.'
    New-Field -Key 'waasMedic' -Label 'WaaSMedic (demarrage)' -Value $wmTxt -Kind 'text' -Status $(if ($wmTxt -eq 'Désactivé') {'ok'} else {'neutral'}) `
        -Help 'Service Windows Update Medic : repare et reactive automatiquement Windows Update (defait les desactivations). Désactivé = neutralise ; Manuel/Auto = il peut encore agir.'
) -Actions @(New-Action -Id 'open-folder' -Label 'Ouvrir le dossier' -Help "Ouvre le dossier d'outils d'administration dans l'explorateur Windows.")
