<# Action open-folder : ouvre l'explorateur sur le dossier LocalAgentAdmin. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$cfg = Get-Config -Backend $backend
Start-Process explorer.exe (Split-Path $cfg.ToolsPath -Parent)
@{ message = 'Dossier ouvert dans l''explorateur.'; result = @{ ok = $true } }
