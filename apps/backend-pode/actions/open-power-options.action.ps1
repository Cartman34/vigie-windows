# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Options d'alimentation | manual | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre les options d'alimentation de Windows.

   Resolution proposee quand la machine tourne sur batterie pendant une partie : c'est la
   que se choisit le mode d'alimentation. Vigie ne change pas le plan a la place de
   l'utilisateur : cela modifierait le comportement de toute la machine. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:powersleep'
    @{ message = "Options d'alimentation ouvertes. Sur secteur, la machine donne toute sa puissance."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir les options d'alimentation : $($_.Exception.Message)"; result = @{ ok = $false } }
}
