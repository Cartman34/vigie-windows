# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Ouvrir les journaux | manual | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre le dossier des journaux de CE compte dans l'explorateur.

   Les journaux vivent par compte (Get-VarRoot) : on ouvre ceux du compte qui execute le
   serveur, pas un dossier devine. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$dossier = Get-VarPath -Backend $backend -Kind 'log'
if (-not (Test-Path -LiteralPath $dossier)) {
    return @{ message = "Aucun journal pour l'instant : $dossier"; result = @{ ok = $false } }
}
Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $dossier + '"') | Out-Null
@{ message = "Journaux ouverts : $dossier"; result = @{ ok = $true } }
