# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
<# Action : lance une recherche EN LIGNE des mises a jour Windows.

   A ne pas confondre avec ce qu'affiche la carte : celle-ci lit le cache LOCAL de Windows
   Update, instantanement. Cette action interroge les serveurs Microsoft, ce qui prend des
   minutes -- d'ou le worker detache et l'etat « en cours » sur la carte.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$etaitVerrouille = $false
try { $etaitVerrouille = Test-UpdateTasksAclLock } catch { }

$lance = $false
try {
    $lance = [bool](Start-Operation -Module 'wu-pending' -Action 'wu-scan' -Label 'Recherche en ligne des mises à jour' `
                        -Probes @('pending.probe.ps1', 'lock.probe.ps1') -Worker 'wu-scan.worker.ps1' `
                        -ArgsMap @{ reposerVerrou = $etaitVerrouille } -Backend $backend)
} catch {
    return @{ message = "Impossible de lancer l'analyse : $($_.Exception.Message)"; result = @{ ok = $false } }
}
if (-not $lance) { return @{ message = "Impossible de lancer l'analyse."; result = @{ ok = $false } } }
$avis = if ($etaitVerrouille) { " Le verrou du Mode MAJ est levé le temps de l'analyse, puis reposé." } else { "" }
@{
    message = "Recherche en ligne des mises à jour lancée.$avis"
    result  = @{ ok = $true; async = $true; module = 'wu-pending'; invalidate = @('pending.probe.ps1','lock.probe.ps1') }
}
