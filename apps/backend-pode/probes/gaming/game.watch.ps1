# @author Florent HAZARD <f.hazard@sowapps.com>
<# RELEVE : un jeu tourne-t-il ?

   ELLE NE CHERCHE RIEN. Le resident (game.resident.ps1) sait, a la seconde, quand un jeu
   demarre ; cette sentinelle lit son resultat et le rend comparable. Elle ignore qui l a
   ecrit, et le resident ignore qu elle existe.

   TROIS ETATS, et le troisieme compte autant que les deux autres : le nom du jeu, « aucun »,
   ou « inconnu » quand le resident est mort -- une mesure absente n est pas une absence de
   jeu. C est ce que l ancienne detection ne savait pas dire.

   Elle reste le FILET : si le resident meurt, l ecart se voit au passage suivant.
   Voir doc/progress/targeting/gaming.md.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
if (-not (Test-ResidentAlive -Backend $backend -Key 'game')) { 'inconnu'; return }
$session = Get-GameSession -Backend $backend
if ($session -and $session.name) { "$($session.name)"; return }
'aucun'
