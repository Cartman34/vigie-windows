<# Action : met a jour les paquets d'UN gestionnaire (en tache de fond).
   Gestionnaire deduit du module (pkg-<id>) ou de params.mgr. Modifie le systeme
   -> passe par la fenetre de choix (pkg-list-updates). Reponse immediate (async) :
   carte "Mise a jour en cours".

   params.ids = identifiants retenus dans la fenetre de choix (meme cle que wu-install :
   c'est le contrat generique du front pour une action de type 'dialog'). Absent, on met
   a jour TOUT le gestionnaire -- comportement historique, conserve. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$mgr = $null
if ($Params -and $Params.mgr) { $mgr = "$($Params.mgr)" }
elseif ($Module) { $mgr = ($Module -replace '^pkg-', '') }
if (-not $mgr) { return @{ message = "Gestionnaire non précisé."; result = @{ ok = $false } } }

$ids = @()
if ($Params -and $Params.ids) { $ids = @($Params.ids | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" }) }
# '*' est la ligne unique proposee quand le gestionnaire ne sait pas cibler un paquet :
# elle vaut « tout », pas un nom de paquet.
if ($ids.Count -eq 1 -and $ids[0] -eq '*') { $ids = @() }

Start-PkgJob -Mgr $mgr -Op 'upgrade' -Pkgs $ids -Backend $backend
