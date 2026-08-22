<# Action : bascule intégrité mémoire via LocalAgentAdmin\toggle-memory-integrity.ps1. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$adminRoot = Split-Path (Get-Config -Backend $backend).ToolsPath -Parent
$script = Join-Path $adminRoot 'toggle-memory-integrity.ps1'
if (-not (Test-Path $script)) { return @{ message = "Introuvable : $script"; result = @{ ok = $false } } }
& $script *> $null
@{ message = 'Bascule intégrité mémoire demandee (redémarrage souvent requis).'; result = @{ ok = $true } }
