# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    A probe: the state of the Windows Update lock. READ ONLY, fast.
    Intent: say whether automatic updates are held back, and say nothing one cannot know -- the ACL lock is only
    reliable and applicable if the server is an administrator, so otherwise it is shown as neutral rather than as
    a false warning. Usage: it is run by the scheduler like any probe.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# ONE single reading of the state for the whole subject (D15): the probe, the actions and the audit share
# Get-UpdateLockState. The probe used to copy the list of task folders and the policy test -- two more copies to
# maintain.
$state = Get-UpdateLockState

$elevated = $state.elevated
$locked   = $state.autoUpdatesOff
$aclLock  = $state.aclLock
$disabled = $state.tasksDisabled
$ready    = $state.tasksReady

$taskLines = @($state.tasks | Sort-Object path, name | ForEach-Object { "{0}{1} : {2}" -f $_.path, $_.name, $_.state })
$taskDetail = if ($taskLines.Count) { "État réel des tâches de mise à jour :`n- " + ($taskLines -join "`n- ") } else { "Aucune tâche listée (lecture impossible)." }

# The CARD's status = functional health. Automatic updates held back (NoAutoUpdate) = the function is working.
# The ACL lock, if it is missing, stays a LINE warning (with no impact) but does not degrade the card.
# The pending restart no longer lives here: it is a GENERAL state of the machine, carried by the Windows card
# (probes/system/os.probe.ps1) with its restart action.
$status = if (-not $locked) { 'warn' } else { 'ok' }

$fullyLocked = $state.locked   # verrou complet = MAJ auto coupees ET verrou ACL applique (defini dans Get-UpdateLockState)
$actions = @()
if ($fullyLocked) { $actions += New-Action -Id 'update-mode-on'  -Label 'Mode MAJ (déverrouiller)' -Confirm `
        -Impact ("Rend à Windows Update ses tâches planifiées et remet les mises à jour automatiques. " +
                 "À partir de là, Windows peut télécharger, installer ET REDÉMARRER la machine de lui-même.") `
        -Usage "Le temps d'installer les mises à jour en attente. On reverrouille juste après." `
        -Reversible "Oui, avec « Verrouiller maintenant » — c'est l'action inverse, et elle est immédiate." -Help "Déverrouille Windows Update pour installer des mises à jour manuellement. Le re-verrouillage vient ensuite. Aucun redémarrage forcé." }
else         { $actions += New-Action -Id 'update-mode-off' -Severity 'fix' -Label 'Verrouiller maintenant'      -Confirm `
        -Impact ("Désactive les tâches planifiées de Windows Update et pose un verrou sur leurs fichiers (ACL), " +
                 "puis coupe les mises à jour automatiques. Windows ne redémarrera plus la machine de lui-même.") `
        -Usage "C'est l'état normal de cette machine : les mises à jour se font sur décision, jamais d'office." `
        -Reversible "Oui, avec « Mode MAJ (déverrouiller) »." -Help "Applique le verrouillage complet : coupe les mises à jour automatiques ET pose le verrou ACL qui empêche Windows de réactiver les tâches de mise à jour. Aucun redémarrage forcé." }
$actions += New-Action -Id 'run-audit' -Label "Lancer l'audit" -Help "Ouvre un rapport détaillé de l'état de Windows Update : verrouillage, stratégies, redémarrage en attente, tâches planifiées, services. Il est aussi gardé dans les journaux de Vigie. Lecture seule : ne modifie rien."

if ($elevated) {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value ([bool]$aclLock) -Kind 'bool' -Status $(if ($aclLock) {'ok'} else {'warn'}) `
        -Help "Verrou de permissions empêchant Windows de recréer/réactiver les tâches de mise à jour. « Non » = verrou non appliqué (fréquent après une grosse MAJ ou un passage en Mode MAJ)." `
        -FixAction 'update-mode-off' -Guide "« Résoudre » applique le verrou (re-verrouillage)."
} else {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value 'Serveur non élevé' -Kind 'text' -Status 'neutral' `
        -Help "Ce verrou de permissions nécessite un serveur en administrateur pour être lu et appliqué de façon fiable." `
        -Guide "Une fois le serveur redémarré, avec l'UAC, ce verrou pourra être vérifié et appliqué."
}

# SCOPE: the lock applies to the whole computer.
New-ModuleObject -Id 'wu-lock' -Theme 'windows-update' -Label 'Verrouillage des mises à jour' -Scope 'machine' -Status $status -Fields @(
    New-Field -Key 'autoUpdatesEnabled' -Label 'MAJ automatiques' -Value ([bool](-not $locked)) -Kind 'bool' -Status $(if ($locked) {'ok'} else {'warn'}) `
        -Help "Si Oui, Windows installe les mises à jour et peut redémarrer tout seul. Verrouillé = Non." `
        -FixAction 'update-mode-off' -Guide "« Résoudre » re-verrouille (coupe les MAJ automatiques). Nécessite un serveur en administrateur."
    $aclField
    New-Field -Key 'tasksDisabled' -Label 'Tâches désactivées' -Value $disabled -Kind 'number' -Status 'neutral' -Help "Nombre de tâches de mise à jour désactivées. Dépliez pour l'état réel de chaque tâche." -Guide $taskDetail
    New-Field -Key 'tasksReady' -Label 'Tâches actives' -Value $ready -Kind 'number' -Status 'neutral' -Help "Tâches de mise à jour encore actives (souvent protégées par Windows ; inoffensives tant que les MAJ auto sont coupées)."
) -Actions $actions
