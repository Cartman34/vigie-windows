# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
<# The pkg-open-gui action: it opens the package manager's graphical interface.
   Intent: lead the user to the tool rather than act in their place. The twin of open-windows-update: it installs
   nothing, it OPENS an external program.
   Usage: it is called from a package card. The target is not written here: Get-PkgGui resolves it from the
   catalogue AND checks that it is really there. So the button never appears without a target, and the action
   refuses cleanly if the program has gone between the display and the click. #>
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
