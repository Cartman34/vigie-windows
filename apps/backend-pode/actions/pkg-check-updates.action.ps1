# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# An action: it checks ONE manager's updates (in the background).
   Intent: answer at once and let the card follow. The manager is deduced from the module that was clicked
   (pkg-<id>) or from params.mgr. An immediate answer (async): the card goes to "under way" and refreshes itself. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$mgr = $null
if ($Params -and $Params.mgr) { $mgr = "$($Params.mgr)" }
elseif ($Module) { $mgr = ($Module -replace '^pkg-', '') }
if (-not $mgr) { return @{ message = "Gestionnaire non précisé."; result = @{ ok = $false } } }

Start-PkgJob -Mgr $mgr -Op 'check' -Backend $backend
