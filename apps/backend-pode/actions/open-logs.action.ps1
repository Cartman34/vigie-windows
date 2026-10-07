# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Ouvrir les journaux | manual | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre le dossier des journaux de CE compte dans l'explorateur.

   Les journaux vivent par compte (Get-VarRoot) : on ouvre ceux du compte qui execute le
   serveur, pas un dossier devine. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$folder = Get-VarPath -Backend $backend -Kind 'log'
if (-not (Test-Path -LiteralPath $folder)) {
    return @{ message = "Aucun journal pour l'instant : $folder"; result = @{ ok = $false } }
}
Start-ChildProcess -FilePath 'explorer.exe' -Arguments @($folder) | Out-Null
@{ message = "Journaux ouverts : $folder"; result = @{ ok = $true } }
