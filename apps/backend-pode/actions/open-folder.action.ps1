# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s afficher chez le DEMANDEUR
<# The open-folder action: it opens Explorer on the configured administration folder. Intent: lead the user there; it opens nothing if no folder is configured. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$adminRoot = Get-AdminRoot -Backend $backend
if (-not $adminRoot) { return New-ToolsMissingResult }
Start-ChildProcess -FilePath 'explorer.exe' -Arguments @($adminRoot)
@{ message = 'Dossier ouvert dans l''explorateur.'; result = @{ ok = $true } }
