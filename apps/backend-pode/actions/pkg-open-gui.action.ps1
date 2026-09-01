# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
<# Action pkg-open-gui : ouvre l'interface graphique du gestionnaire de paquets.
   Jumelle de open-windows-update : n'installe rien, elle OUVRE un logiciel externe.

   La cible n'est pas ecrite ici : Get-PkgGui la resout depuis le catalogue ET verifie sa
   presence reelle. Le bouton n'apparait donc jamais sans cible, et l'action refuse
   proprement si le logiciel a disparu entre l'affichage et le clic. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$mgr = $null
if ($Params -and $Params.mgr) { $mgr = "$($Params.mgr)" }
elseif ($Module) { $mgr = ($Module -replace '^pkg-', '') }
if (-not $mgr) { return @{ message = "Gestionnaire non précisé."; result = @{ ok = $false } } }

$gui = Get-PkgGui -Id $mgr
if (-not $gui) {
    return @{ message = "Aucune interface graphique installée pour ce gestionnaire."; result = @{ ok = $false } }
}
try {
    Start-Process $gui.target
    @{ message = "$($gui.label) : fenêtre ouverte."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir l'interface : $($_.Exception.Message)"; result = @{ ok = $false } }
}
