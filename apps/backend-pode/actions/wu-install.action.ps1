# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
<# An action: it installs the Windows updates the user CHOSE.

   Intent: install nothing without an explicit choice -- an empty list is refused rather than read as
   "everything".
   Usage: it receives params.ids = the identifiers wu-list-pending returned. The installation leaves in a
   DETACHED worker (it lasts minutes): the HTTP request hands control back at once, the card goes to "under way"
   and updates itself. So closing the browser interrupts nothing. #>
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$ids = @()
if ($Params -and $Params.ids) { $ids = @($Params.ids | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" }) }
if ($ids.Count -eq 0) {
    return @{ message = "Aucune mise à jour sélectionnée."; result = @{ ok = $false } }
}

# The Update Mode lock is a mechanism INTERNAL to the application: it lifts it for the time it takes to install,
# then LAYS IT BACK. The user is warned, not blocked -- asking them to undo by hand a lock the application laid
# down itself makes no sense.
$wasLocked = $false
try { $wasLocked = Test-UpdateTasksAclLock } catch { }

# THE MARK EXISTS BEFORE THE ANSWER, written by Start-Operation: the page no longer takes the installation for
# finished the moment it starts (12/09).
$lance = $false
try {
    $lance = [bool](Start-Operation -Module 'wu-pending' -Action 'wu-install' -Label 'Installation des mises à jour' `
                        -Probes @('pending.probe.ps1', 'lock.probe.ps1') -Worker 'wu-install.worker.ps1' `
                        -ArgsMap @{ ids = $ids; reposerVerrou = $wasLocked } -Button 'wu-list-pending' -Backend $backend)
} catch {
    return @{ message = "Impossible de lancer l'installation : $($_.Exception.Message)"; result = @{ ok = $false } }
}
if (-not $lance) { return @{ message = "Impossible de lancer l'installation."; result = @{ ok = $false } } }
$avis = if ($wasLocked) { " Le verrou du Mode MAJ est levé le temps de l'opération, puis reposé." } else { "" }
@{
    message = "Installation de $($ids.Count) mise(s) à jour lancée en tâche de fond.$avis"
    result  = @{ ok = $true; async = $true; module = 'wu-pending'; invalidate = @('pending.probe.ps1','lock.probe.ps1') }
}
