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
    New-Field -Key 'vbs'  -Label 'Sécurité par virtualisation (VBS)' -Value $vbsOn -Kind 'bool' -Status $statutVbs `
        -Help "Windows isole ses fonctions de sécurité dans une machine virtuelle, hors d'atteinte d'un programme malveillant qui aurait pris le contrôle du système." `
        -Guide $(if ($vbsOn) {
            "Ce que c'est : les secrets de Windows (mots de passe en mémoire, contrôles d'intégrité) tournent dans un espace isolé par l'hyperviseur. Un logiciel malveillant qui obtient les droits administrateur ne peut pas y accéder.`n`n" +
            "État actuel : activée. C'est la position recommandée.`n`n" +
            "Contrepartie à connaître : l'hyperviseur ralentit les autres usages de la virtualisation (WSL, VirtualBox, VMware) — de quelques pourcents à un facteur deux selon les cas. Le bouton « Basculer VBS » permet de la désactiver si ces performances comptent davantage pour vous."
        } else {
            "Ce que c'est : sans VBS, les secrets de Windows résident dans la mémoire ordinaire. Un logiciel malveillant qui obtient les droits administrateur peut les lire.`n`n" +
            "Pourquoi c'est signalé : la protection est disponible sur cette machine mais désactivée.`n`n" +
            "Ce que vous pouvez faire :`n" +
            "- l'activer avec « Basculer VBS » (redémarrage nécessaire) — plus sûr ;`n" +
            "- la laisser désactivée en connaissance de cause si vous utilisez intensivement WSL ou des machines virtuelles, dont les performances en dépendent."
        })
    New-Field -Key 'hvci' -Label 'Intégrité mémoire (HVCI)' -Value $hvciOn -Kind 'bool' -Status $statutHvci `
        -Help "Windows vérifie la signature de chaque pilote avant de le charger dans le noyau, et refuse ceux qui ne sont pas signés." `
        -Guide $(if ($hvciOn) {
            "Ce que c'est : tout code qui s'exécute au cœur de Windows (pilotes) doit être signé. Cela ferme la porte aux attaques par pilote vulnérable, technique courante des rançongiciels.`n`n" +
            "État actuel : activée. C'est la position recommandée.`n`n" +
            "Contrepartie à connaître : un pilote ancien ou non signé sera refusé, et la virtualisation est plus lente."
        } else {
            "Ce que c'est : sans intégrité mémoire, un pilote non signé — ou un pilote signé mais vulnérable — peut s'exécuter dans le noyau avec tous les droits. C'est la voie d'entrée privilégiée des rançongiciels récents.`n`n" +
            "Pourquoi c'est signalé : la protection existe sur cette machine mais n'est pas active. Windows la désactive parfois tout seul quand il détecte un pilote incompatible.`n`n" +
            "Ce que vous pouvez faire :`n" +
            "- l'activer avec « Basculer intégrité mémoire » (redémarrage nécessaire). Si Windows refuse, il nomme le pilote fautif : mettez-le à jour, puis réessayez ;`n" +
            "- la laisser désactivée si un matériel indispensable en dépend (pilote ancien), en sachant ce que cela coûte ;`n" +
            "- vérifier d'abord que VBS est activée : l'intégrité mémoire s'appuie dessus."
        })
) -Actions @(
    New-Action -Id 'toggle-vbs' -Severity 'fix'  -Label 'Basculer VBS' -Confirm -Help "Active ou désactive la sécurité basée sur la virtualisation (VBS). Redémarrage requis. Impacte les performances de virtualisation (WSL/VM)."
    New-Action -Id 'toggle-hvci' -Severity 'fix' -Label 'Basculer intégrité mémoire' -Confirm -Help "Active ou désactive l'intégrité mémoire (HVCI). Redémarrage requis. Peut dégrader les performances de virtualisation."
)
