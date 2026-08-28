# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
<# Action toggle-vbs : active ou desactive la securite par virtualisation (VBS).

   Capacite NATIVE du produit : aucune dependance a un outillage hors depot. Toute la
   logique (elevation, sauvegarde du registre, ecriture, relecture, compte rendu) vit
   dans Invoke-DeviceGuardToggle / Set-DeviceGuardFeature (lib/common.ps1) -- les deux
   bascules ne different que par le nom de la fonction visee. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

Invoke-DeviceGuardToggle -Feature 'vbs' -Backend $backend
