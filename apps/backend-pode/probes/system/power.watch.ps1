# @author Florent HAZARD <f.hazard@sowapps.com>
<# READING: is current flowing into the battery, or out of it?

   THE SOURCE IS NOT WHAT WE WATCH. "Mains" or "battery" says little on its own: plugged in
   yet discharging means the charger cannot keep up; unplugged, it is normal. What matters
   is the DIRECTION of the current, and that is what must wake the Power card -- plugging in
   or out then shows without anyone looking, where a display alone serves the cache.

   Returns 'charge', 'decharge', 'stable' or 'aucune'. One WMI read, nothing else.
   See doc/progress/targeting/surveillance.md.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
Get-PowerFlow
