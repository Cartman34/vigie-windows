<# Sonde : sécurité de la virtualisation (VBS / intégrité mémoire). LECTURE SEULE. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
$vbsOn  = [bool]($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2)
$hvciOn = [bool]($dg -and ($dg.SecurityServicesRunning -contains 2))
New-ModuleObject -Id 'vbs' -Theme 'security' -Label 'Sécurité de la virtualisation' -Status 'neutral' -Fields @(
    New-Field -Key 'vbs'  -Label 'VBS' -Value $vbsOn -Kind 'bool' -Status 'neutral' `
        -Help 'Virtualization-Based Security : isole des fonctions de sécurité dans un environnement virtualise. Plus sur, mais cout en performances de virtualisation (WSL/VM).'
    New-Field -Key 'hvci' -Label 'Intégrité mémoire (HVCI)' -Value $hvciOn -Kind 'bool' -Status 'neutral' `
        -Help 'Hypervisor-Enforced Code Integrity : bloque le code noyau non signe. Peut degrader nettement les perfs de virtualisation.'
) -Actions @(
    New-Action -Id 'toggle-vbs'  -Label 'Basculer VBS' -Confirm -Help "Active ou désactivé la sécurité basee sur la virtualisation (VBS). Redémarrage requis. Impacte les performances de virtualisation (WSL/VM)."
    New-Action -Id 'toggle-hvci' -Label 'Basculer intégrité mémoire' -Confirm -Help "Active ou désactivé l'intégrité mémoire (HVCI). Redémarrage requis. Peut degrader les performances de virtualisation."
)
