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
    if ($parent -notlike ('*' + $store.Marker)) { continue }
    <#
        A STORE'S OWN COMPONENT IS NOT A GAME, and it is its own child like any other. On 29/09 the card announced
        "Jeu détecté : Steam Client WebHelper" once the real game had closed: steamwebhelper.exe is started by
        steam.exe, so the parentage was there -- and it proved nothing.

        What separates them is WHERE they live. A game installed through a store lives in its libraries
        (steamapps\common\..., Ubisoft's games folder); the store's helpers live INSIDE the store's own folder,
        beside the executable that started them. Same parent, different house.
    #>
    $storeRoot = ''
    try { $storeRoot = (Split-Path "$($Process.ParentPath)" -Parent).ToLower() } catch { }
    $own = "$($Process.Path)".ToLower()
    if ($storeRoot -and $own -and $own.StartsWith($storeRoot)) {
        # A LIBRARY LIVES INSIDE THE STORE'S FOLDER TOO (steamapps\common\...): being under that folder is not
        # enough, what counts is being under it WITHOUT being in a library. Otherwise every Steam game is refused.
        $inLibrary = $false
        foreach ($library in @('steamapps', '\games', 'gameslibrary', '\library')) {
            if ($own.Contains($library)) { $inLibrary = $true; break }
        }
        if (-not $inLibrary) { return }
    }
    return ('lancé par ' + $store.Name)
}
