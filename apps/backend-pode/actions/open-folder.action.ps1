# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action open-folder : ouvre l'explorateur sur le dossier LocalAgentAdmin. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$adminRoot = Get-AdminRoot -Backend $backend
if (-not $adminRoot) { return New-ToolsMissingResult }
Start-Process explorer.exe $adminRoot
@{ message = 'Dossier ouvert dans l''explorateur.'; result = @{ ok = $true } }
