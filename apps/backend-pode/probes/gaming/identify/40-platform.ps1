# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHOD: the executable sits in a game library.

   Steam keeps its games in declared libraries; other stores register an install folder per
   game. We compare PATHS, never names.

   THIS METHOD IS NOT ENOUGH, and that is intended: it only knows the big stores and misses
   the indie game launched without any platform. That is why there are others.

   Libraries are read once and kept in memory (Get-GameLibraryPaths): opening Steam's
   configuration for every starting process would cost for nothing. #>
param($Process)
if (-not $Process.Path) { return }
$target = "$($Process.Path)".ToLower()
foreach ($library in @(Get-GameLibraryPaths)) {
    if (-not $library.Path) { continue }
    if ($target.StartsWith("$($library.Path)".ToLower())) { return ('installé dans ' + $library.Label) }
}
