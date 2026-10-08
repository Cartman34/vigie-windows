# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Analyser l'espace | immediate | info   -- affiche quand un champ cite cette action (D66)
<# An action: it starts the analysis of what the disc is used by (in the background).
   Intent: answer at once and let the card follow. An immediate answer (async): the card goes to "under way" and
   follows the progress. The walk itself is in workers/disk-scan.worker.ps1. Usage: from the Storage card. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$rootPath = 'C:\'
if ($Params -and $Params.root -and "$($Params.root)" -match '\S') { $rootPath = "$($Params.root)" }
if (-not (Test-Path -LiteralPath $rootPath)) {
    return @{ message = "Dossier introuvable : $rootPath"; result = @{ ok = $false } }
}

# The module's settings (D57): the depth of detail that is kept, and the number of elements per level.
$profondeur = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanDepth')
$topN       = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanTop')
if (-not $profondeur) { $profondeur = 3 }
if (-not $topN)       { $topN = 10 }

# An analysis already running is refused by the resource lock, which reads the busy mark
# (doc/progress/targeting/operations.md): no expiry of our own any more.
$lance = $false
try {
    $lance = [bool](Start-Operation -Module 'storage' -Action 'disk-analyze' -Label "Analyse de $rootPath" `
                        -Probes @('disk.probe.ps1') -Worker 'disk-scan.worker.ps1' `
                        -ArgsMap @{ root = $rootPath; depth = $profondeur; top = $topN } -Backend $backend)
} catch { }
if (-not $lance) { return @{ message = "Impossible de lancer l'analyse du disque."; result = @{ ok = $false } } }
@{
    message = "Analyse de $rootPath lancée en tâche de fond."
    result  = @{ ok = $true; async = $true; module = 'storage'; invalidate = @('disk.probe.ps1') }
}
