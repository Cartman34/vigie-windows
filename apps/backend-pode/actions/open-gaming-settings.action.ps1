# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Paramètres de jeu | manual | info   -- bouton PERMANENT de sa carte (D114)
<# Action : ouvre les parametres de jeu de Windows.

   C'est la que se reglent la barre de jeu, le mode Jeu et les captures -- ce qui entoure une partie sans que Vigie ait a y toucher. Vigie n'agit pas a la place de l'utilisateur : elle le mene
   au bon endroit, ce qui est la seconde famille de boutons de D66. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:gaming-gamebar'
    @{ message = "Paramètres de jeu ouverts."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir : $($_.Exception.Message)"; result = @{ ok = $false } }
}
