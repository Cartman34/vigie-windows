# @droits: admin   -- reecrire une tache planifiee exige l'elevation (D65)
# @libelle: Reparer le demarrage de Vigie | immediate | fix   -- affiche quand un champ cite cette action (D66)
<# Action : remet d'aplomb les taches de demarrage DE VIGIE, et rien d'autre.

   Autorise explicitement par l'utilisateur : « l'app peut auto-corriger le systeme tant
   que c'est du pur Vigie ». On ne touche donc qu'aux taches nommees « Vigie » ou
   « Vigie - <compte> », jamais a autre chose.

   Le cas qui a motive ceci : les taches pointaient vers un pwsh installe dans le profil
   d'un compte, disparu apres un changement d'installation de PowerShell. Windows n'a
   rien dit -- la tache existait, se lancait, et mourait aussitot. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$faits = @(Repair-VigieTasks -Backend $backend)
if (-not $faits.Count) {
    return @{ message = "Rien a reparer : les taches de demarrage de Vigie sont saines."
              result  = @{ ok = $true; invalidate = @('comptes.probe.ps1') } }
}
$ok = @($faits | Where-Object { $_.repare })
$ko = @($faits | Where-Object { -not $_.repare })
$detail = (($faits | ForEach-Object {
    "{0} : {1} -> {2}" -f $_.tache, $_.mal, $(if ($_.repare) { 'reparee' } else { 'ECHEC : ' + $_.erreur })
}) -join [Environment]::NewLine)

@{
    message = ("{0} tache(s) reparee(s)" -f $ok.Count) + $(if ($ko.Count) { ", {0} en echec" -f $ko.Count } else { '' }) + "."
    result  = @{ ok = ($ko.Count -eq 0); detail = $detail; invalidate = @('comptes.probe.ps1') }
}
