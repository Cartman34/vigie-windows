# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : demande l'arret de l'analyse du disque en cours.
   On ne TUE pas le worker : on pose un drapeau qu'il relit a chaque point de progression
   (environ toutes les 1,5 s). Il s'arrete alors proprement et laisse le dernier resultat
   complet en place -- un resultat partiel serait trompeur. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$stopFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.stop'
Set-Content -LiteralPath $stopFile -Value ((Get-Date).ToUniversalTime().ToString('s')) -Encoding UTF8

@{
    message = "Arrêt demandé : l'analyse s'interrompt dans quelques secondes."
    result  = @{ ok = $true; async = $true; module = 'storage'; invalidate = @('disk.probe.ps1') }
}
