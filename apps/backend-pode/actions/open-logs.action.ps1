# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Ouvrir les journaux | manual | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens THIS account's logs folder in Explorer.

   Intent: open the right folder and not a guessed one. The logs live per account (Get-VarRoot): we open those of
   the account that runs the server. Usage: it is cited by the Debugging card. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$folder = Get-VarPath -Backend $backend -Kind 'log'
if (-not (Test-Path -LiteralPath $folder)) {
    return @{ message = "Aucun journal pour l'instant : $folder"; result = @{ ok = $false } }
}
Start-ChildProcess -FilePath 'explorer.exe' -Arguments @($folder) | Out-Null
@{ message = "Journaux ouverts : $folder"; result = @{ ok = $true } }
