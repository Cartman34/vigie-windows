# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHOD: game markers surround the executable.

   The most expensive one -- it touches the disk -- and the broadest: this is the one that
   catches the indie game, launched without a store, that no inventory knows.

   We look next to the executable and up to three folders above: an engine (UnityPlayer.dll,
   Unreal's Paks), an SDK (steam_api, EOSSDK), a store (Ubisoft's uplay_r1_loader64.dll,
   GOG's Galaxy) or middleware (Bink, FMOD).

   COUNTER-SIGNAL: a Chromium/Electron shell is never a game, however much GPU it uses --
   ChatGPT was announced as "game detected" on 25/08. #>
param($Process)
if (-not $Process.Path) { return }
$folder = Split-Path $Process.Path -Parent
if (-not $folder) { return }
foreach ($shell in @('chrome_100_percent.pak', 'chrome.dll', 'icudtl.dat', 'resources\app.asar')) {
    if (Test-Path -LiteralPath (Join-Path $folder $shell)) { return }
}
$markers = @('steam_api.dll', 'steam_api64.dll', 'steam_appid.txt', 'UnityPlayer.dll',
             'EOSSDK-Win64-Shipping.dll', 'Content\Paks', '.egstore',
             'uplay_r1_loader.dll', 'uplay_r1_loader64.dll', 'UbisoftGameLauncher.dll',
             'Galaxy.dll', 'Galaxy64.dll', 'goggame-galaxyFileList.bin', '.build.info',
             'bink2w64.dll', 'binkw32.dll', 'GameAssembly.dll',
             'fmod.dll', 'fmodstudio.dll', 'fmodstudio64.dll')
$current = $folder
for ($level = 0; $level -lt 3 -and $current; $level++) {
    foreach ($marker in $markers) {
        if (Test-Path -LiteralPath (Join-Path $current $marker)) {
            return ('marqueur de jeu à côté de l''exécutable (' + $marker + ')')
        }
    }
    $current = Split-Path $current -Parent
}
