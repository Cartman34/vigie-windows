# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Options d'alimentation | manual | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens Windows's power options.

   Intent: lead the user to where the power mode is chosen rather than act in their place -- changing the plan
   would change the behaviour of the whole machine. It is offered as the resolution when the machine runs on
   battery during a game. Usage: it is cited by the Gaming and Power cards. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:powersleep'
    @{ message = "Options d'alimentation ouvertes. Sur secteur, la machine donne toute sa puissance."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir les options d'alimentation : $($_.Exception.Message)"; result = @{ ok = $false } }
}
