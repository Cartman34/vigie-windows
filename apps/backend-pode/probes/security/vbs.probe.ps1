<# Sonde : sécurité de la virtualisation (VBS / intégrité mémoire). LECTURE SEULE. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
$vbsOn  = [bool]($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2)
$hvciOn = [bool]($dg -and ($dg.SecurityServicesRunning -contains 2))
# VBS et HVCI sont un COMPROMIS (sécurité contre performances de virtualisation), pas une
# conformité : cette sonde les rapportait donc en 'neutral'. Décision de l'utilisateur : une
# carte porte un statut normal comme les autres. Activé = conforme, désactivé = à voir.
$statutVbs  = if ($vbsOn)  { 'ok' } else { 'warn' }
$statutHvci = if ($hvciOn) { 'ok' } else { 'warn' }
$statutMod  = if ($vbsOn -and $hvciOn) { 'ok' } else { 'warn' }
New-ModuleObject -Id 'vbs' -Theme 'security' -Label 'Sécurité de la virtualisation' -Status $statutMod -Fields @(
    New-Field -Key 'vbs'  -Label 'VBS' -Value $vbsOn -Kind 'bool' -Status $statutVbs `
        -Help 'Virtualization-Based Security : isole des fonctions de sécurité dans un environnement virtualisé. Plus sûr, mais coût en performances de virtualisation (WSL/VM).'
    New-Field -Key 'hvci' -Label 'Intégrité mémoire (HVCI)' -Value $hvciOn -Kind 'bool' -Status $statutHvci `
        -Help 'Hypervisor-Enforced Code Integrity : bloque le code noyau non signé. Peut dégrader nettement les perfs de virtualisation.'
) -Actions @(
    New-Action -Id 'toggle-vbs' -Severity 'fix'  -Label 'Basculer VBS' -Confirm -Help "Active ou désactive la sécurité basée sur la virtualisation (VBS). Redémarrage requis. Impacte les performances de virtualisation (WSL/VM)."
    New-Action -Id 'toggle-hvci' -Severity 'fix' -Label 'Basculer intégrité mémoire' -Confirm -Help "Active ou désactive l'intégrité mémoire (HVCI). Redémarrage requis. Peut dégrader les performances de virtualisation."
)
