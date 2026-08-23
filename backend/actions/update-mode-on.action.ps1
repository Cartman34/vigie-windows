<# Action update-mode-on : passe en MODE MISE A JOUR (déverrouille).
   Appelle LocalAgentAdmin/tools/update-mode.ps1 -On. Retourne {message,result}. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent          # actions/ -> backend/
. (Join-Path $backend 'lib/common.ps1')
$tools = Get-ToolsPath -Backend $backend
if (-not $tools) { return New-ToolsMissingResult }
$script = Join-Path $tools 'update-mode.ps1'
if (-not (Test-Path $script)) { return @{ message = "Script introuvable : $script"; result = @{ ok = $false } } }
& $script -On *> $null
@{ message = 'Mode mise à jour ACTIVE (déverrouille). Fais tes MAJ, redémarre quand tu veux, puis re-verrouille.'; result = @{ ok = $true } }
