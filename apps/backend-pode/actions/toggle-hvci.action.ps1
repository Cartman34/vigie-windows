# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
<# The toggle-hvci action: it switches memory integrity (HVCI) on or off.

   Intent: be a NATIVE ability of the product -- no dependency on tooling outside the repository. All the
   reasoning (the elevation, the registry backup, the write, the read-back, the report) lives in
   Invoke-DeviceGuardToggle / Set-DeviceGuardFeature (lib/common.ps1) -- the two switches differ only by the name
   of the function they aim at. Usage: it is called from the Virtualisation security card. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

Invoke-DeviceGuardToggle -Feature 'hvci' -Backend $backend
