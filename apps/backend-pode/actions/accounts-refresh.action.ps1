# @droits: tous   -- ne fait que relire l'etat de la machine (D65)
# @libelle: Actualiser la liste | immediate | info   -- affiche quand un champ cite cette action (D66)
<# Action : refait le releve des comptes de la machine.

   L'inventaire est mémorisé 24 h : il coute deux secondes et ne change qu'exceptionnellement
   (« y'aura pas des nouveaux comptes tous les jours »). Ce bouton sert quand on vient
   d'ajouter ou de retirer un compte Windows et qu'on ne veut pas attendre. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

Clear-VigieAccountsCache -Backend $backend
$liste = @(Get-VigieAccounts -Force -Backend $backend | Where-Object { -not $_.technical })

@{
    message = ("Liste actualisée : " + $liste.Count + " compte(s) utilisateur.")
    result  = @{ ok = $true; invalidate = @('comptes.probe.ps1') }
}
