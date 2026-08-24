<#
    Sonde : etat du verrouillage Windows Update. LECTURE SEULE, rapide.
    Le verrou ACL n'est fiable/applicable que si le serveur est administrateur :
    sinon on l'affiche comme neutre plutot qu'un faux avertissement.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$elevated = Test-Elevated

$au     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$noAuto = (Get-ItemProperty -Path $au -Name NoAutoUpdate -ErrorAction SilentlyContinue).NoAutoUpdate
$locked = ($noAuto -eq 1)

$paths = @('\Microsoft\Windows\UpdateOrchestrator\','\Microsoft\Windows\WindowsUpdate\',
           '\Microsoft\Windows\InstallService\','\Microsoft\Windows\WaaSMedic\')
$tasks = foreach ($p in $paths) { Get-ScheduledTask -TaskPath $p -ErrorAction SilentlyContinue }
$disabled = @($tasks | Where-Object { $_.State -eq 'Disabled' }).Count
$ready    = @($tasks | Where-Object { $_.State -ne 'Disabled' }).Count
$taskLines = @($tasks | Sort-Object TaskPath, TaskName | ForEach-Object { "{0}{1} : {2}" -f $_.TaskPath, $_.TaskName, $_.State })
$taskDetail = if ($taskLines.Count) { "État réel des tâches de mise à jour :`n- " + ($taskLines -join "`n- ") } else { "Aucune tâche listée (lecture impossible)." }

$reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
          (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

$aclLock = Test-UpdateTasksAclLock

# Statut de la CARTE = sante fonctionnelle. Les MAJ auto coupees (NoAutoUpdate) = fonction OK.
# Le verrou ACL, s'il manque, reste un avertissement de LIGNE (sans impact) mais ne degrade pas la carte.
$status = if ($reboot) { 'error' } elseif ($locked) { 'ok' } else { 'warn' }

$fullyLocked = $locked -and $aclLock   # verrou complet = MAJ auto coupees ET verrou ACL applique
$actions = @()
if ($fullyLocked) { $actions += New-Action -Id 'update-mode-on'  -Label 'Mode MAJ (déverrouiller)' -Confirm -Help "Déverrouille Windows Update pour installer des mises à jour manuellement. Pensez à re-verrouiller ensuite. Aucun redémarrage forcé." }
else         { $actions += New-Action -Id 'update-mode-off' -Severity 'fix' -Label 'Verrouiller maintenant'      -Confirm -Help "Applique le verrouillage complet : coupe les mises à jour automatiques ET pose le verrou ACL qui empêche Windows de réactiver les tâches de mise à jour. Aucun redémarrage forcé." }
$actions += New-Action -Id 'run-audit' -Label "Lancer l'audit" -Help "Génère un rapport détaillé de l'état de Windows Update. Lecture seule."

if ($elevated) {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value ([bool]$aclLock) -Kind 'bool' -Status $(if ($aclLock) {'ok'} else {'warn'}) `
        -Help "Verrou de permissions empêchant Windows de recréer/réactiver les tâches de mise à jour. « Non » = verrou non appliqué (fréquent après une grosse MAJ ou un passage en Mode MAJ)." `
        -FixAction 'update-mode-off' -Guide "Cliquez Résoudre pour appliquer le verrou (re-verrouillage)."
} else {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value 'serveur non élevé' -Kind 'text' -Status 'neutral' `
        -Help "Ce verrou de permissions nécessite un serveur en administrateur pour être lu et appliqué de façon fiable." `
        -Guide "Redémarrez le serveur (il demandera l'UAC) : ce verrou pourra alors être vérifié et appliqué."
}

New-ModuleObject -Id 'wu-lock' -Theme 'windows-update' -Label 'Verrouillage des mises à jour' -Status $status -Fields @(
    New-Field -Key 'autoUpdatesEnabled' -Label 'MAJ automatiques' -Value ([bool](-not $locked)) -Kind 'bool' -Status $(if ($locked) {'ok'} else {'warn'}) `
        -Help "Si Oui, Windows installe les mises à jour et peut redémarrer tout seul. Verrouillé = Non." `
        -FixAction 'update-mode-off' -Guide "Cliquez Résoudre pour re-verrouiller (coupe les MAJ automatiques). Nécessite un serveur en administrateur."
    $aclField
    New-Field -Key 'tasksDisabled' -Label 'Tâches désactivées' -Value $disabled -Kind 'number' -Status 'neutral' -Help "Nombre de tâches de mise à jour désactivées. Dépliez pour l'état réel de chaque tâche." -Guide $taskDetail
    New-Field -Key 'tasksReady' -Label 'Tâches actives' -Value $ready -Kind 'number' -Status 'neutral' -Help "Tâches de mise à jour encore actives (souvent protégées par Windows ; inoffensives tant que les MAJ auto sont coupées)."
    # Un redemarrage en attente n'est PAS une erreur : c'est l'issue NORMALE d'une mise a
    # jour installee. Le marquer en rouge faisait passer la carte entiere en « Problème »
    # alors que tout s'etait bien passe. C'est un point a traiter, donc « à voir ».
    New-Field -Key 'rebootPending' -Label 'Redémarrage en attente' -Value ([bool]$reboot) -Kind 'bool' -Status $(if ($reboot) {'warn'} else {'ok'}) `
        -Help "Une mise à jour est installée mais ne sera active qu'après un redémarrage de Windows." `
        -Guide $(if ($reboot) {
            "Ce que c'est : une mise à jour a été installée ; Windows a besoin de redémarrer pour la terminer. Ce n'est pas une panne.`n`n" +
            "Le risque à ne rien faire : les correctifs installés ne protègent pas encore, et Windows finira par redémarrer de lui-même si le verrouillage est levé.`n`n" +
            "Ce que vous pouvez faire :`n" +
            "- redémarrer quand cela vous arrange (menu Démarrer > Redémarrer) — c'est la seule action qui lève cet état ;`n" +
            "- continuer à travailler : Vigie ne force jamais un redémarrage, et le verrou du Mode MAJ empêche Windows de le faire."
        } else {
            "Aucun redémarrage en attente : toutes les mises à jour installées sont actives."
        })
) -Actions $actions
