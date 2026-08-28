# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Ouvrir le dossier | manual | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre l'explorateur Windows sur un dossier de l'analyse du disque.

   Sert depuis l'arborescence de la carte Stockage : on voit ou part la place, et on va y
   regarder d'un clic. Vigie n'efface RIEN : elle ouvre l'explorateur, l'utilisateur decide.

   PRUDENCE : le chemin vient du client. On n'ouvre donc que ce qui est reellement un
   DOSSIER EXISTANT, et uniquement SOUS LA RACINE ANALYSEE (var/cache/diskscan.json) --
   sinon ce serait un moyen de faire ouvrir n'importe quoi a l'application. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$chemin = if ($Params -and $Params.path) { "$($Params.path)" } else { $null }
if (-not $chemin) { return @{ message = "Aucun dossier precise."; result = @{ ok = $false } } }

# La racine autorisee est celle de la derniere analyse.
$racine = 'C:' + [char]92
try {
    $f = Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.json'
    if (Test-Path -LiteralPath $f) {
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        if ($j.result -and $j.result.root) { $racine = "$($j.result.root)" }
        elseif ($j.scan -and $j.scan.root) { $racine = "$($j.scan.root)" }
    }
} catch { }

$plein = $null
try { $plein = (Resolve-Path -LiteralPath $chemin -ErrorAction Stop).Path } catch { }
if (-not $plein -or -not (Test-Path -LiteralPath $plein -PathType Container)) {
    return @{ message = "Dossier introuvable : $chemin"; result = @{ ok = $false } }
}
if (-not $plein.ToLower().StartsWith($racine.ToLower())) {
    return @{ message = "Ce dossier n'appartient pas a l'analyse en cours."; result = @{ ok = $false } }
}

Start-Process explorer.exe $plein
@{ message = ("Dossier ouvert : " + $plein); result = @{ ok = $true } }
