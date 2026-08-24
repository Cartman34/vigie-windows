<# Sonde : sécurité de la virtualisation (VBS / intégrité mémoire). LECTURE SEULE. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# UNE seule lecture d'etat pour tout le sujet (D15) : la sonde et les bascules partagent
# Get-DeviceGuardState. Elle distingue ce qui TOURNE de ce qui est DEMANDE -- une bascule
# ne prend effet qu'au redemarrage, et la carte doit le dire au lieu de paraitre ignorer
# le clic qu'on vient de lui donner.
$dgEtat = Get-DeviceGuardState -Backend $backend
$vbsOn  = $dgEtat.vbs.running
$hvciOn = $dgEtat.hvci.running
# VBS et HVCI sont un COMPROMIS (sécurité contre performances de virtualisation), pas une
# conformité : cette sonde les rapportait donc en 'neutral'. Décision de l'utilisateur : une
# carte porte un statut normal comme les autres. Activé = conforme, désactivé = à voir.
$statutVbs  = if ($vbsOn)  { 'ok' } else { 'warn' }
$statutHvci = if ($hvciOn) { 'ok' } else { 'warn' }
$statutMod  = if ($vbsOn -and $hvciOn) { 'ok' } else { 'warn' }

# Une bascule demandee et pas encore appliquee est un ETAT A SIGNALER, pas un echec : la
# valeur est ecrite, Windows ne la lira qu'au demarrage. Sans cette ligne, l'utilisateur
# reclique en croyant que rien ne s'est passe.
$attente = @(@($dgEtat.vbs, $dgEtat.hvci) | Where-Object { $_.pending })
$phrase = { param($e) "$($e.label) : " + $(if ($e.requested -eq 1) { 'activation' } else { 'désactivation' }) + ' demandée' }
if ($attente.Count) { $statutMod = 'warn' }

# Actions. Le redemarrage n'est propose QUE lorsqu'il sert : une bascule de CETTE carte
# attend d'etre appliquee. On ne le deduit pas d'un simple ecart entre le registre et
# l'etat actif -- cet ecart peut etre permanent (valeur imposee par l'UEFI), et la carte
# reclamerait alors un redemarrage pour toujours. L'action et son annulation sont celles
# qui existent deja (system-restart / system-restart-cancel) : rien n'est duplique.
$actionsVbs = @(
    New-Action -Id 'toggle-vbs' -Severity 'fix'  -Label 'Basculer VBS' -Confirm -Kind 'confirm' `
        -Help "Active ou désactive la sécurité basée sur la virtualisation (VBS). La valeur est écrite dans le registre et prend effet au prochain redémarrage. Impacte les performances de virtualisation (WSL/VM)."
    New-Action -Id 'toggle-hvci' -Severity 'fix' -Label 'Basculer intégrité mémoire' -Confirm -Kind 'confirm' `
        -Help "Active ou désactive l'intégrité mémoire (HVCI). La valeur est écrite dans le registre et prend effet au prochain redémarrage. Peut dégrader les performances de virtualisation."
)
if (Test-RestartCountdown -Backend $backend) {
    $actionsVbs += New-Action -Id 'system-restart-cancel' -Label 'Annuler le redémarrage' -Severity 'fix' `
        -BusyLabel 'Annulation…' -Confirm -Help "Annule le redémarrage programmé. Windows reste allumé."
} elseif ($attente.Count) {
    $actionsVbs += New-Action -Id 'system-restart' -Label 'Redémarrer Windows' -Severity 'fix' `
        -BusyLabel 'Redémarrage programmé…' -ConfirmTwice -Kind 'confirm' `
        -Help "Redémarre Windows dans 60 secondes pour appliquer la bascule demandée. Enregistrez votre travail : toutes les applications seront fermées. Le redémarrage reste annulable pendant le délai."
}

$champs = @()
$champs += New-Field -Key 'vbs'  -Label 'Sécurité par virtualisation (VBS)' -Value $vbsOn -Kind 'bool' -Status $statutVbs `
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
$champs += New-Field -Key 'hvci' -Label 'Intégrité mémoire (HVCI)' -Value $hvciOn -Kind 'bool' -Status $statutHvci `
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
# Champ present UNIQUEMENT quand une bascule attend le redemarrage : une ligne permanente
# « rien en attente » n'apprendrait rien et encombrerait la carte.
if ($attente.Count) {
    $champs += New-Field -Key 'pendingReboot' -Label 'En attente de redémarrage' `
        -Value (($attente | ForEach-Object { & $phrase $_ }) -join ' ; ') -Kind 'text' -Status 'warn' `
        -Help "Une bascule a été écrite dans le registre. Windows ne la lit qu'au démarrage : elle prendra effet au prochain redémarrage." `
        -Guide ("Ce que c'est : la demande est enregistrée ; l'état affiché au-dessus est encore celui qui tourne.`n`n" +
                "Ce que vous pouvez faire :`n" +
                "- redémarrer Windows — le bouton « Redémarrer Windows » de cette carte le fait avec un délai de 60 secondes, annulable ;`n" +
                "- recliquer sur la bascule pour revenir en arrière : tant que le redémarrage n'a pas eu lieu, cela annule simplement la demande.`n`n" +
                "Si la valeur ne s'applique toujours pas après un redémarrage, elle est imposée par l'UEFI ou par une stratégie d'entreprise, et Vigie ne peut pas passer outre.")
}

New-ModuleObject -Id 'vbs' -Theme 'security' -Label 'Sécurité de la virtualisation' -Status $statutMod `
    -Fields $champs -Actions $actionsVbs
