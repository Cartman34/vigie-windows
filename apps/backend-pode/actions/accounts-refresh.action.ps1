# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- ne fait que relire l'etat de la machine (D65)
# @libelle: Actualiser la liste | immediate | info   -- affiche quand un champ cite cette action (D66)
<# An action: it makes the reading of the machine's accounts again.

   Intent: let one not wait when a Windows account has just been added or removed. The inventory is remembered
   for 24 h: it costs two seconds and changes only exceptionally ("there will not be new accounts every day").
   Usage: it is called from the Accounts card. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

Clear-ComputerAccountsCache -Backend $backend
$liste = @(Get-UserAccounts -Force -Backend $backend)

@{
    message = ("Liste actualisée : " + $liste.Count + " compte(s) utilisateur.")
    result  = @{ ok = $true; invalidate = @('accounts.probe.ps1', 'deployment.probe.ps1') }
}
