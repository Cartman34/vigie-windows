# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : verifie (en tache de fond) les MAJ d'UN gestionnaire.
   Gestionnaire deduit du module clique (pkg-<id>) ou de params.mgr.
   Reponse immediate (async) : la carte passe en "en cours" et s'actualise seule. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$mgr = $null
if ($Params -and $Params.mgr) { $mgr = "$($Params.mgr)" }
elseif ($Module) { $mgr = ($Module -replace '^pkg-', '') }
if (-not $mgr) { return @{ message = "Gestionnaire non précisé."; result = @{ ok = $false } } }

Start-PkgJob -Mgr $mgr -Op 'check' -Backend $backend
