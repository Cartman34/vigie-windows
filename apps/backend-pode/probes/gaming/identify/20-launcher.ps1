# @author Florent HAZARD <f.hazard@sowapps.com>
<# METHODE : le processus a ete lance par une boutique de jeux.

   La moins chere : le chemin du parent est deja dans l evenement, il n y a rien a lire.
   Un jeu passe souvent par un lanceur intermediaire -- Odyssey demarre par upc.exe -- et
   ce lien de parente est un fait, pas une supposition.

   ON JUGE LE CHEMIN DU PARENT, jamais son seul nom : un « steam.exe » pose n importe ou
   ne prouve rien. #>
param($Process)
if (-not $Process.ParentPath) { return }
$parent = "$($Process.ParentPath)".ToLower()
$boutiques = @(
    @{ Marque = 'steam\steam.exe';                        Nom = 'Steam' }
    @{ Marque = 'ubisoft game launcher\upc.exe';          Nom = 'Ubisoft Connect' }
    @{ Marque = 'ubisoft connect\upc.exe';                Nom = 'Ubisoft Connect' }
    @{ Marque = 'epic games\launcher';                    Nom = 'Epic Games' }
    @{ Marque = 'gog galaxy\galaxyclient.exe';            Nom = 'GOG Galaxy' }
    @{ Marque = 'battle.net\battle.net.exe';              Nom = 'Battle.net' }
    @{ Marque = 'electronic arts\eadesktop\eadesktop.exe'; Nom = 'EA' }
)
foreach ($b in $boutiques) {
    if ($parent -like ('*' + $b.Marque)) { return ('lance par ' + $b.Nom) }
}
