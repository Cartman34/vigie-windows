# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Paramètres de jeu | manual | info   -- bouton PERMANENT de sa carte (D114)
<# An action: it opens Windows's gaming settings.

   Intent: lead the user to the right place rather than act in their place, which is the second family of D66
   buttons. That is where the game bar, Game Mode and the captures are set -- what surrounds a game without
   Vigie having to touch any of it. Usage: it is cited by the Gaming card. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:gaming-gamebar'
    @{ message = "Paramètres de jeu ouverts."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir : $($_.Exception.Message)"; result = @{ ok = $false } }
}
