# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
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

<#
    THE PACKAGES KEPT, UNDER BOTH NAMES THEY ARE GIVEN (D131).

    This action read `ids` and nothing else. On 06/10 a call passed the list under `pkgs`: it arrived empty, and an
    empty list meant "the whole manager". Sixteen programs were installed instead of one. Both names are therefore
    accepted -- a parameter name is not a safety device -- and it is the refusal downstream that protects: with no
    package AND no explicit "all", nothing leaves.
#>
$ids = @()
foreach ($champ in @('ids', 'pkgs')) {
    if ($Params -and $Params.$champ) { $ids += @($Params.$champ | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" }) }
}
$ids = @($ids | Select-Object -Unique)
# '*' is the single line offered when a manager cannot target one package: it means "all", not a package name --
# and "all" is now asked for in so many words.
$tout = ($ids.Count -eq 1 -and $ids[0] -eq '*')
if ($tout) { $ids = @() }

if (-not $ids.Count -and -not $tout) {
    return @{ message = "Aucun paquet désigné : cochez ce qui doit être mis à jour."; result = @{ ok = $false } }
}
Start-PkgJob -Mgr $mgr -Op 'upgrade' -Pkgs $ids -All:$tout -Backend $backend
