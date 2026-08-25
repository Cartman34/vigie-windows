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

$outFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.json'

# Une analyse deja en cours ne se relance pas : on le dit au lieu d'en lancer une seconde
# qui doublerait la charge disque pour le meme resultat.
try {
    if (Test-Path -LiteralPath $outFile) {
        $j = Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json
        if ($j.scan -and $j.scan.running -and $j.scan.startedAt) {
            $depuis = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.scan.startedAt)).TotalMinutes
            if ($depuis -lt 60) {
                return @{ message = "Une analyse est déjà en cours."
                          result = @{ ok = $true; async = $true; module = 'disk-usage'; invalidate = @('diskusage.probe.ps1') } }
            }
        }
    }
} catch { }

$worker = Join-Path $backend 'workers/disk-scan.worker.ps1'
$lance = $false
try {
    $null = Start-DetachedAction -Script $worker -Backend $backend `
        -ArgsMap @{ root = $racine; depth = $profondeur; top = $topN }
    $lance = $true
} catch { }
if (-not $lance) { return @{ message = "Impossible de lancer l'analyse du disque."; result = @{ ok = $false } } }

@{
    message = "Analyse de $racine lancée en tâche de fond."
    result  = @{ ok = $true; async = $true; module = 'disk-usage'; invalidate = @('diskusage.probe.ps1') }
}
