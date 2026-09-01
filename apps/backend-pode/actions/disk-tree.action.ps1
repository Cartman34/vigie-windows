# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- lecture seule : n'exige aucun privilege (D65)
# @libelle: Explorer l'arborescence | dialog | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre l'explorateur d'arborescence du disque.

   L'interface l'intercepte pour ouvrir sa fenetre, puis demande les niveaux au fur et a
   mesure (GET /disk/tree?path=...). Ce fichier repond quand meme quelque chose d'utile
   -- le premier niveau -- pour qu'un appel direct de l'API ne tombe pas dans le vide. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$chemin = if ($Params -and $Params.path) { "$($Params.path)" } else { $null }
try {
    if (-not $chemin) {
        $f = Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.json'
        if (-not (Test-Path -LiteralPath $f)) { throw "Aucune analyse disponible : lancez d'abord l'analyse de l'espace." }
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        $chemin = if ($j.result -and $j.result.root) { "$($j.result.root)" } else { "$($j.scan.root)" }
    }
    $niveau = Get-DiskTreeLevel -Path $chemin -Backend $backend
    @{
        message = ("Arborescence de " + $niveau.path + " : " + @($niveau.children).Count + " dossier(s).")
        result  = @{ ok = $true; ui = 'disk-tree'; level = $niveau }
    }
} catch {
    @{ message = "$($_.Exception.Message)"; result = @{ ok = $false } }
}
