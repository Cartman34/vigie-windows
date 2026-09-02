# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHODE : Windows lui-meme l a enregistre comme jeu (Game Bar).

   Une lecture de registre. Ce que le systeme sait deja vaut mieux que ce qu on devine.

   LA RUCHE DU BON UTILISATEUR : ce reglage vit chez chaque personne, et l app serveur
   tourne sous un compte de service qui n a ni Game Bar ni jeux (D113). On lit donc la
   ruche de tous les utilisateurs connectes. #>
param($Process)
if (-not $Process.Path) { return }
$cible = "$($Process.Path)".ToLower()
foreach ($hive in @(Get-UserRegistryRoots)) {
    try {
        $children = Join-Path $hive 'System\GameConfigStore\Children'
        foreach ($key in (Get-ChildItem $children -ErrorAction Stop)) {
            $exe = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).MatchedExeFullPath
            if ($exe -and "$exe".ToLower() -eq $cible) { return 'reconnu comme jeu par Windows (Game Bar)' }
        }
    } catch { }
}
