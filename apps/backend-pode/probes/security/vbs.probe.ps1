# @author Florent HAZARD <f.hazard@sowapps.com>
<# A probe: virtualisation security (VBS / memory integrity). READ ONLY. Intent: say which of the two branches of the compromise this computer is on, and report only the state that calls for a gesture. Usage: run by the scheduler like any probe. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# ONE single reading of the state for the whole subject (D15): the probe and the switches share
# Get-DeviceGuardState. It tells what is RUNNING from what is REQUESTED -- a switch only takes effect at the next
# restart, and the card must say so instead of appearing to ignore the click it has just been given.
$dgState = Get-DeviceGuardState -Backend $backend
$vbsOn  = $dgState.vbs.running
$hvciOn = $dgState.hvci.running
# VBS and HVCI are a COMPROMISE (security against virtualisation performance), not a conformity: so this probe
# used to report them as 'neutral'. The owner's decision: a card carries a normal status like the others. Enabled
# = conforming, disabled = to be looked at.
# Disabled is NOT a defect: it is the other branch of the compromise (driver compatibility and virtualisation
# performance against hardening). Checked on this machine: HVCI neither configured nor pending, WSL2 working. The
# warn is reserved for a switch PENDING a restart -- the only state that calls for a gesture.
$statutVbs  = if ($vbsOn)  { 'ok' } else { 'neutral' }
$statutHvci = if ($hvciOn) { 'ok' } else { 'neutral' }
$statutMod  = 'ok'

# A switch that was asked for and not applied yet is a STATE TO REPORT, not a failure: the value is written,
# Windows will only read it at the next start. Without this line, the user clicks again believing nothing
# happened.
$waitMs = @(@($dgState.vbs, $dgState.hvci) | Where-Object { $_.pending })
$phrase = { param($e) "$($e.label) : " + $(if ($e.requested -eq 1) { 'activation' } else { 'désactivation' }) + ' demandée' }
if ($waitMs.Count) { $statutMod = 'warn' }

# The actions. The restart is offered ONLY when it serves: a switch of THIS card is waiting to be applied. We do
# not deduce it from a plain gap between the registry and the active state -- that gap can be permanent (a value
# imposed by the UEFI), and the card would then demand a restart for ever. The action and its cancellation are
# the ones that already exist (system-restart / system-restart-cancel): nothing is duplicated.
$actionsVbs = @(
    New-Action -Id 'toggle-vbs' -Severity 'fix'  -Label 'Basculer VBS' -Confirm `
        -Impact ("Écrit la valeur EnableVirtualizationBasedSecurity dans le registre. Rien ne change avant le " +
                 "REDÉMARRAGE de Windows. Activée, la sécurité basée sur la virtualisation isole une partie du " +
                 "système dans un hyperviseur : c'est plus sûr, mais cela coûte des performances — surtout aux " +
                 "machines virtuelles et aux jeux.") `
        -Usage "L'activer pour durcir la machine ; la couper quand on a besoin de toute la puissance ou d'un hyperviseur tiers (VirtualBox, VMware)." `
        -Reversible "Oui : rebasculer et redémarrer. Aucune donnée n'est touchée." -Kind 'confirm' `
        -Help "Active ou désactive la sécurité basée sur la virtualisation (VBS). La valeur est écrite dans le registre et prend effet au prochain redémarrage. Impacte les performances de virtualisation (WSL/VM)."
    New-Action -Id 'toggle-hvci' -Severity 'fix' -Label 'Basculer intégrité mémoire' -Confirm `
        -Impact ("Écrit la valeur HypervisorEnforcedCodeIntegrity dans le registre ; effet au REDÉMARRAGE. " +
                 "Activée, Windows vérifie les pilotes dans l'hyperviseur : un pilote ancien ou non signé peut " +
                 "alors refuser de se charger.") `
        -Usage "L'activer pour bloquer les pilotes douteux ; la couper si un matériel cesse de fonctionner après l'avoir activée." `
        -Reversible "Oui : rebasculer et redémarrer." -Kind 'confirm' `
        -Help "Active ou désactive l'intégrité mémoire (HVCI). La valeur est écrite dans le registre et prend effet au prochain redémarrage. Peut dégrader les performances de virtualisation."
)
if (Test-RestartCountdown -Backend $backend) {
    $actionsVbs += New-Action -Id 'system-restart-cancel' -Label 'Annuler le redémarrage' -Severity 'fix' `
        -BusyLabel 'Annulation…' -Confirm -Help "Annule le redémarrage programmé. Windows reste allumé."
} elseif ($waitMs.Count) {
    $actionsVbs += New-Action -Id 'system-restart' -Label 'Redémarrer Windows' -Severity 'fix' `
        -BusyLabel 'Redémarrage programmé…' -ConfirmTwice -Kind 'confirm' `
        -Help "Redémarre Windows dans 60 secondes pour appliquer la bascule demandée. Le travail en cours est à enregistrer : toutes les applications seront fermées. Le redémarrage reste annulable pendant le délai."
}

$champs = @()
$champs += New-Field -Key 'vbs'  -Label 'Sécurité par virtualisation (VBS)' -Value $vbsOn -Kind 'bool' -Status $statutVbs `
        -Help "Windows isole ses fonctions de sécurité dans une machine virtuelle, hors d'atteinte d'un programme malveillant qui aurait pris le contrôle du système." `
        -Guide $(if ($vbsOn) {
            "Ce que c'est : les secrets de Windows (mots de passe en mémoire, contrôles d'intégrité) tournent dans un espace isolé par l'hyperviseur. Un logiciel malveillant qui obtient les droits administrateur ne peut pas y accéder.`n`n" +
            "État actuel : activée. C'est la position recommandée.`n`n" +
            "Contrepartie à connaître : l'hyperviseur ralentit les autres usages de la virtualisation (WSL, VirtualBox, VMware) — de quelques pourcents à un facteur deux selon les cas. Le bouton « Basculer VBS » permet de la désactiver si ces performances comptent davantage."
        } else {
            "Ce que c'est : sans VBS, les secrets de Windows résident dans la mémoire ordinaire. Un logiciel malveillant qui obtient les droits administrateur peut les lire.`n`n" +
            "Pourquoi c'est signalé : la protection est disponible sur cette machine mais désactivée.`n`n" +
            "Ce qui est possible :`n" +
            "- l'activer avec « Basculer VBS » (redémarrage nécessaire) — plus sûr ;`n" +
            "- la laisser désactivée en connaissance de cause en cas d'usage intensif de WSL ou des machines virtuelles, dont les performances en dépendent."
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
            "Ce qui est possible :`n" +
            "- l'activer avec « Basculer intégrité mémoire » (redémarrage nécessaire). Si Windows refuse, il nomme le pilote fautif : mettez-le à jour, puis réessayez ;`n" +
            "- la laisser désactivée si un matériel indispensable en dépend (pilote ancien), en sachant ce que cela coûte ;`n" +
            "- vérifier d'abord que VBS est activée : l'intégrité mémoire s'appuie dessus."
        })
# A field present ONLY when a switch is waiting for the restart: a permanent line saying nothing is pending
# would teach nothing and clutter the card.
if ($waitMs.Count) {
    $champs += New-Field -Key 'pendingReboot' -Label 'En attente de redémarrage' `
        -Value (($waitMs | ForEach-Object { & $phrase $_ }) -join ' ; ') -Kind 'text' -Status 'warn' `
        -FixAction 'system-restart' `
        -Help "Une bascule a été écrite dans le registre. Windows ne la lit qu'au démarrage : elle prendra effet au prochain redémarrage." `
        -Guide ("Ce que c'est : la demande est enregistrée ; l'état affiché au-dessus est encore celui qui tourne.`n`n" +
                "Ce qui est possible :`n" +
                "- redémarrer Windows — le bouton « Redémarrer Windows » de cette carte le fait avec un délai de 60 secondes, annulable ;`n" +
                "- recliquer sur la bascule pour revenir en arrière : tant que le redémarrage n'a pas eu lieu, cela annule simplement la demande.`n`n" +
                "Si la valeur ne s'applique toujours pas après un redémarrage, elle est imposée par l'UEFI ou par une stratégie d'entreprise, et Vigie ne peut pas passer outre.")
}

# SCOPE: a boot setting of the computer.
New-ModuleObject -Id 'vbs' -Theme 'security' -Label 'Sécurité de la virtualisation' -Scope 'machine' -Status $statutMod `
    -Fields $champs -Actions $actionsVbs
