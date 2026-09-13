# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Analyser l'espace | immediate | info   -- affiche quand un champ cite cette action (D66)
<# Action : lance l'analyse de la consommation du disque (tache de fond).
   Reponse immediate (async) : la carte passe en "en cours" et suit la progression.
   Le parcours lui-meme est dans workers/disk-scan.worker.ps1. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$racine = 'C:\'
if ($Params -and $Params.root -and "$($Params.root)" -match '\S') { $racine = "$($Params.root)" }
if (-not (Test-Path -LiteralPath $racine)) {
    return @{ message = "Dossier introuvable : $racine"; result = @{ ok = $false } }
}

# Reglages du module (D57) : profondeur du detail conserve et nombre d'elements par niveau.
$profondeur = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanDepth')
$topN       = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanTop')
if (-not $profondeur) { $profondeur = 3 }
if (-not $topN)       { $topN = 10 }

# An analysis already running is refused by the resource lock, which reads the busy mark
# (doc/progress/targeting/operations.md): no expiry of our own any more.
$lance = $false
try {
    $lance = [bool](Start-Operation -Module 'storage' -Action 'disk-analyze' -Label "Analyse de $racine" `
                        -Probes @('disk.probe.ps1') -Worker 'disk-scan.worker.ps1' `
                        -ArgsMap @{ root = $racine; depth = $profondeur; top = $topN } -Backend $backend)
} catch { }
if (-not $lance) { return @{ message = "Impossible de lancer l'analyse du disque."; result = @{ ok = $false } } }
@{
    message = "Analyse de $racine lancée en tâche de fond."
    result  = @{ ok = $true; async = $true; module = 'storage'; invalidate = @('disk.probe.ps1') }
}
