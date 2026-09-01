# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Sécurité Windows | manual | info   -- bouton PERMANENT de sa carte (D114)
<# Action : ouvre la Sécurité Windows.

   C'est la que se lisent l'etat de l'antivirus, celui du pare-feu, et que se relance une analyse ou se reactive une protection desactivee. Vigie n'agit pas a la place de l'utilisateur : elle le mene
   au bon endroit, ce qui est la seconde famille de boutons de D66. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'windowsdefender:'
    @{ message = "Sécurité Windows ouverte."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir : $($_.Exception.Message)"; result = @{ ok = $false } }
}
