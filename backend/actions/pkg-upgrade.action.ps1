<# Action : met a jour TOUS les paquets d'UN gestionnaire (en tache de fond).
   Gestionnaire deduit du module (pkg-<id>) ou de params.mgr. Modifie le systeme
   -> a confirmer cote UI. Reponse immediate (async) : carte "Mise a jour en cours". #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$mgr = $null
if ($Params -and $Params.mgr) { $mgr = "$($Params.mgr)" }
elseif ($Module) { $mgr = ($Module -replace '^pkg-', '') }
if (-not $mgr) { return @{ message = "Gestionnaire non précisé."; result = @{ ok = $false } } }

Start-PkgJob -Mgr $mgr -Op 'upgrade' -Backend $backend
