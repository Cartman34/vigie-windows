<# Action : bascule VBS via LocalAgentAdmin\toggle-vbs.ps1 (nécessite admin). #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$adminRoot = Get-AdminRoot -Backend $backend
if (-not $adminRoot) { return New-ToolsMissingResult }
$script = Join-Path $adminRoot 'toggle-vbs.ps1'
if (-not (Test-Path $script)) { return @{ message = "Introuvable : $script"; result = @{ ok = $false } } }
& $script *> $null
@{ message = 'Bascule VBS demandee (redémarrage souvent requis).'; result = @{ ok = $true } }
