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

$reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
          (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

# Statut de la CARTE = sante fonctionnelle. Les MAJ auto coupees (NoAutoUpdate) = fonction OK.
# Le verrou ACL, s'il manque, reste un avertissement de LIGNE (sans impact) mais ne degrade pas la carte.
# Le redemarrage en attente ne met PLUS la carte en erreur : le champ correspondant vaut
# « warn » (issue normale d'une MAJ installee, cf. plus bas), et une carte ne peut pas etre
# plus grave que le pire de ses champs — sinon l'utilisateur lit « Problème » sans trouver
# une seule ligne en rouge. C'est New-ModuleObject qui garantit desormais cette borne.
$status = if ($reboot -or -not $locked) { 'warn' } else { 'ok' }

$fullyLocked = $etat.locked   # verrou complet = MAJ auto coupees ET verrou ACL applique (defini dans Get-UpdateLockState)
$actions = @()
if ($fullyLocked) { $actions += New-Action -Id 'update-mode-on'  -Label 'Mode MAJ (déverrouiller)' -Confirm -Help "Déverrouille Windows Update pour installer des mises à jour manuellement. Pensez à re-verrouiller ensuite. Aucun redémarrage forcé." }
else         { $actions += New-Action -Id 'update-mode-off' -Severity 'fix' -Label 'Verrouiller maintenant'      -Confirm -Help "Applique le verrouillage complet : coupe les mises à jour automatiques ET pose le verrou ACL qui empêche Windows de réactiver les tâches de mise à jour. Aucun redémarrage forcé." }
$actions += New-Action -Id 'run-audit' -Label "Lancer l'audit" -Help "Génère un rapport détaillé de l'état de Windows Update (stratégies, tâches, services, redémarrage en attente) dans les journaux de Vigie. Lecture seule : ne modifie rien."

if ($elevated) {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value ([bool]$aclLock) -Kind 'bool' -Status $(if ($aclLock) {'ok'} else {'warn'}) `
        -Help "Verrou de permissions empêchant Windows de recréer/réactiver les tâches de mise à jour. « Non » = verrou non appliqué (fréquent après une grosse MAJ ou un passage en Mode MAJ)." `
        -FixAction 'update-mode-off' -Guide "Cliquez Résoudre pour appliquer le verrou (re-verrouillage)."
} else {
    $aclField = New-Field -Key 'aclLock' -Label 'Verrou ACL des tâches' -Value 'serveur non élevé' -Kind 'text' -Status 'neutral' `
        -Help "Ce verrou de permissions nécessite un serveur en administrateur pour être lu et appliqué de façon fiable." `
        -Guide "Redémarrez le serveur (il demandera l'UAC) : ce verrou pourra alors être vérifié et appliqué."
}

# Redemarrage : propose SEULEMENT quand il est utile, et toujours annulable.
# Le calcul « un compte a rebours court-il encore ? » vit dans Test-RestartCountdown
# (lib/common.ps1) : la carte de la virtualisation en a besoin elle aussi, et il etait
# ecrit ici seul (D15).
$restartPending = Test-RestartCountdown -Backend $backend
if ($restartPending) {
    $actions += New-Action -Id 'system-restart-cancel' -Label 'Annuler le redémarrage' -Severity 'fix' `
        -BusyLabel 'Annulation…' -Confirm -Help "Annule le redémarrage programmé. Windows reste allumé."
} elseif ($reboot) {
    $actions += New-Action -Id 'system-restart' -Label 'Redémarrer Windows' -Severity 'fix' `
        -BusyLabel 'Redémarrage programmé…' -ConfirmTwice -Kind 'confirm' `
        -Help "Redémarre Windows dans 60 secondes pour terminer les mises à jour installées. Enregistrez votre travail : toutes les applications seront fermées. Le redémarrage reste annulable pendant le délai."
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
