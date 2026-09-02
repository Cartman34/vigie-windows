# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHOD: Windows itself registered it as a game (Game Bar).

   One registry read. What the system already knows beats what we would guess.

   THE RIGHT USER HIVE: this setting lives with each person, and the server app runs under
   a service account that has neither Game Bar nor games (D113). So we read the hive of
   every signed-in user. #>
param($Process)
if (-not $Process.Path) { return }
$target = "$($Process.Path)".ToLower()
foreach ($hive in @(Get-UserRegistryRoots)) {
    try {
        $children = Join-Path $hive 'System\GameConfigStore\Children'
        foreach ($key in (Get-ChildItem $children -ErrorAction Stop)) {
            $exe = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).MatchedExeFullPath
            if ($exe -and "$exe".ToLower() -eq $target) { return 'reconnu comme jeu par Windows (Game Bar)' }
        }
    } catch { }
}
