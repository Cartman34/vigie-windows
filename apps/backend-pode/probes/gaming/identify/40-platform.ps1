# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHODE : l executable est installe dans une bibliotheque de jeux.

   Steam range ses jeux dans des bibliotheques declarees ; les autres boutiques ont leur
   dossier d installation. On compare des CHEMINS, jamais des noms.

   CETTE METHODE N EST PAS SUFFISANTE, et c est voulu : elle ne connait que les grosses
   boutiques et ignore le jeu independant lance sans plateforme. C est pourquoi il y en a
   d autres.

   Les bibliotheques sont lues une fois et gardees en memoire (Get-GameLibraryPaths) :
   ouvrir la configuration de Steam a chaque processus qui demarre couterait pour rien. #>
param($Process)
if (-not $Process.Path) { return }
$cible = "$($Process.Path)".ToLower()
foreach ($library in @(Get-GameLibraryPaths)) {
    if (-not $library.Path) { continue }
    if ($cible.StartsWith("$($library.Path)".ToLower())) { return ('installe dans ' + $library.Label) }
}
