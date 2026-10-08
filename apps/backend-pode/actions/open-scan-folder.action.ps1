# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Ouvrir le dossier | manual | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens Windows Explorer on a folder of the disc analysis.

   Intent: let one go and look where the space went, in one click. Vigie deletes NOTHING: it opens Explorer, the
   user decides.
   Usage: it is called from the Storage card's tree. CAUTION: the path comes from the client. So we open only
   what really is an EXISTING FOLDER, and only UNDER THE ROOT THAT WAS ANALYSED (var/cache/diskscan.json) --
   otherwise it would be a way of making the application open anything at all. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$path = if ($Params -and $Params.path) { "$($Params.path)" } else { $null }
if (-not $path) { return @{ message = "Aucun dossier precise."; result = @{ ok = $false } } }

# The allowed root is the one of the last analysis.
$rootPath = 'C:' + [char]92
try {
    $f = Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.json'
    if (Test-Path -LiteralPath $f) {
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        if ($j.result -and $j.result.root) { $rootPath = "$($j.result.root)" }
        elseif ($j.scan -and $j.scan.root) { $rootPath = "$($j.scan.root)" }
    }
} catch { }

$plein = $null
try { $plein = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path } catch { }
if (-not $plein -or -not (Test-Path -LiteralPath $plein -PathType Container)) {
    return @{ message = "Dossier introuvable : $path"; result = @{ ok = $false } }
}
if (-not $plein.ToLower().StartsWith($rootPath.ToLower())) {
    return @{ message = "Ce dossier n'appartient pas a l'analyse en cours."; result = @{ ok = $false } }
}

Start-ChildProcess -FilePath 'explorer.exe' -Arguments @($plein)
@{ message = ("Dossier ouvert : " + $plein); result = @{ ok = $true } }
