# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- lecture seule : n'exige aucun privilege (D65)
# @libelle: Explorer l'arborescence | dialog | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens the disc tree explorer.

   Intent: answer something useful even when the interface is not the caller. The interface intercepts it to open
   its own window, then asks for the levels as it goes (GET /disk/tree?path=...). This file still answers
   something useful -- the first level -- so that a direct API call does not fall into the void. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$path = if ($Params -and $Params.path) { "$($Params.path)" } else { $null }
try {
    if (-not $path) {
        $f = Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.json'
        if (-not (Test-Path -LiteralPath $f)) { throw "Aucune analyse disponible : lancez d'abord l'analyse de l'espace." }
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        $path = if ($j.result -and $j.result.root) { "$($j.result.root)" } else { "$($j.scan.root)" }
    }
    $niveau = Get-DiskTreeLevel -Path $path -Backend $backend
    @{
        message = ("Arborescence de " + $niveau.path + " : " + @($niveau.children).Count + " dossier(s).")
        result  = @{ ok = $true; ui = 'disk-tree'; level = $niveau }
    }
} catch {
    @{ message = "$($_.Exception.Message)"; result = @{ ok = $false } }
}
