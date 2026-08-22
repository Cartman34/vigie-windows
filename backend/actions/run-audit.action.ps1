<# Action run-audit : lance l'audit complet de la machinerie Windows Update.
   Appelle LocalAgentAdmin/tools/audit-update-tasks.ps1 (ecrit un rapport). #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$cfg    = Get-Config -Backend $backend
$script = Join-Path $cfg.ToolsPath 'audit-update-tasks.ps1'
if (-not (Test-Path $script)) { return @{ message = "Script introuvable : $script"; result = @{ ok = $false } } }
& $script *> $null
@{ message = "Audit lance. Rapport ecrit dans le dossier LocalAgentAdmin."; result = @{ ok = $true } }
