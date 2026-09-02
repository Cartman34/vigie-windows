# @author Florent HAZARD <f.hazard@sowapps.com>
<# READING: is a game running?

   IT LOOKS FOR NOTHING. The resident (game.resident.ps1) knows, within a second, when a
   game starts; this sentinel reads its result and turns it into a comparable value. It
   ignores who wrote it, and the resident ignores that it exists.

   THREE STATES, and the third counts as much as the others: the game name, "aucun", or
   "inconnu" when the resident is not operational -- a missing measurement is not an absence
   of game. That is what the former detection could not say.

   It stays the SAFETY NET: if the resident dies, the gap shows at the next pass.
   See doc/progress/targeting/gaming.md.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
if (-not (Test-ResidentOperational -Backend $backend -Key 'game')) { 'inconnu'; return }
$session = Get-GameSession -Backend $backend
if ($session -and $session.name) { "$($session.name)"; return }
'aucun'
