<#
    Sonde : etat du verrouillage Windows Update. LECTURE SEULE, rapide.
    Le verrou ACL n'est fiable/applicable que si le serveur est administrateur :
    sinon on l'affiche comme neutre plutot qu'un faux avertissement.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# UNE seule lecture d'etat pour tout le sujet (D15) : la sonde, les actions et l'audit
# partagent Get-UpdateLockState. La sonde recopiait auparavant la liste des dossiers de
# taches et le test de la strategie -- deux copies de plus a maintenir.
$etat = Get-UpdateLockState

$elevated = $etat.elevated
$locked   = $etat.autoUpdatesOff
$aclLock  = $etat.aclLock
$disabled = $etat.tasksDisabled
$ready    = $etat.tasksReady

$taskLines = @($etat.tasks | Sort-Object path, name | ForEach-Object { "{0}{1} : {2}" -f $_.path, $_.name, $_.state })
$taskDetail = if ($taskLines.Count) { "État réel des tâches de mise à jour :`n- " + ($taskLines -join "`n- ") } else { "Aucune tâche listée (lecture impossible)." }

# Statut de la CARTE = sante fonctionnelle. Les MAJ auto coupees (NoAutoUpdate) = fonction OK.
# Le verrou ACL, s'il manque, reste un avertissement de LIGNE (sans impact) mais ne degrade pas la carte.
# Le redemarrage en attente ne vit PLUS ici : c'est un etat GENERAL de la machine, porte
# par la carte Windows (probes/system/os.probe.ps1) avec son action de redemarrage.
$status = if (-not $locked) { 'warn' } else { 'ok' }

$fullyLocked = $etat.locked   # verrou complet = MAJ auto coupees ET verrou ACL applique (defini dans Get-UpdateLockState)
$actions = @()
if ($fullyLocked) { $actions += New-Action -Id 'update-mode-on'  -Label 'Mode MAJ (déverrouiller)' -Confirm -Help "Déverrouille Windows Update pour installer des mises à jour manuellement. Pensez à re-verrouiller ensuite. Aucun redémarrage forcé." }
else         { $actions += New-Action -Id 'update-mode-off' -Severity 'fix' -Label 'Verrouiller maintenant'      -Confirm -Help "Applique le verrouillage complet : coupe les mises à jour automatiques ET pose le verrou ACL qui empêche Windows de réactiver les tâches de mise à jour. Aucun redémarrage forcé." }
$actions += New-Action -Id 'run-audit' -Label "Lancer l'audit" -Help "Génère un rapport détaillé de l'état de Windows Update (stratégies, tâches, services) dans les journaux de Vigie. Lecture seule : ne modifie rien."

if ($elevated) {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value ([bool]$aclLock) -Kind 'bool' -Status $(if ($aclLock) {'ok'} else {'warn'}) `
        -Help "Verrou de permissions empêchant Windows de recréer/réactiver les tâches de mise à jour. « Non » = verrou non appliqué (fréquent après une grosse MAJ ou un passage en Mode MAJ)." `
        -FixAction 'update-mode-off' -Guide "Cliquez Résoudre pour appliquer le verrou (re-verrouillage)."
} else {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value 'Serveur non élevé' -Kind 'text' -Status 'neutral' `
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
) -Actions $actions
