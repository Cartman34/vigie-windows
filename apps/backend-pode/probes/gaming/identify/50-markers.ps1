# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHODE : des marqueurs de jeu entourent l executable.

   La plus chere -- elle touche le disque -- et la plus large : c est elle qui attrape le
   jeu independant, lance sans boutique, qu aucun inventaire ne connait.

   On cherche a cote de l executable, et jusqu a trois dossiers au-dessus : un moteur
   (UnityPlayer.dll, les Paks d Unreal), un SDK (steam_api, EOSSDK), une boutique
   (uplay_r1_loader64.dll d Ubisoft, Galaxy de GOG) ou un middleware (Bink, FMOD).

   ANTI-SIGNAL : une coquille Chromium/Electron n est jamais un jeu, meme si elle consomme
   le GPU -- ChatGPT a ete annonce comme « jeu detecte » le 25/08. #>
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
            return ('marqueur de jeu a cote de l''executable (' + $marker + ')')
        }
    }
    $current = Split-Path $current -Parent
}
