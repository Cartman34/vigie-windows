# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHOD: the process was started by a game store.

   The cheapest one: the parent path already comes with the event, nothing to read. A game
   often starts through an intermediate launcher -- Odyssey starts from upc.exe -- and that
   parentage is a fact, not a guess.

   WE JUDGE THE PARENT PATH, never its name alone: a "steam.exe" dropped anywhere proves
   nothing. #>
param($Process)
if (-not $Process.ParentPath) { return }
$parent = "$($Process.ParentPath)".ToLower()
$stores = @(
    @{ Marker = 'steam\steam.exe';                          Name = 'Steam' }
    @{ Marker = 'ubisoft game launcher\upc.exe';            Name = 'Ubisoft Connect' }
    @{ Marker = 'ubisoft connect\upc.exe';                  Name = 'Ubisoft Connect' }
    @{ Marker = 'epic games\launcher';                      Name = 'Epic Games' }
    @{ Marker = 'gog galaxy\galaxyclient.exe';              Name = 'GOG Galaxy' }
    @{ Marker = 'battle.net\battle.net.exe';                Name = 'Battle.net' }
    @{ Marker = 'electronic arts\eadesktop\eadesktop.exe'; Name = 'EA' }
)
foreach ($store in $stores) {
    if ($parent -like ('*' + $store.Marker)) { return ('lancé par ' + $store.Name) }
}
