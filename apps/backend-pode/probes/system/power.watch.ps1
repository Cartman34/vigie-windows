# @author Florent HAZARD <f.hazard@sowapps.com>
<# RELEVE : le courant entre-t-il ou sort-il de la batterie ?

   CE N'EST PAS LA SOURCE QU'ON SURVEILLE. « Secteur » ou « batterie » ne dit rien a
   soi seul : branche mais en decharge, c'est un chargeur qui ne suit pas ; debranche,
   c'est normal. Le fait qui compte est le SENS du courant, et c'est lui qui doit
   reveiller la carte Alimentation -- brancher ou debrancher se voit alors sans que
   personne ne regarde, la ou l'affichage seul sert le cache.

   Rend 'charge', 'decharge', 'stable' ou 'aucune'. Une lecture WMI, rien d'autre.
   Voir doc/progress/targeting/surveillance.md.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
Get-PowerFlow
