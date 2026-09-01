# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Paramètres de stockage | manual | info   -- bouton PERMANENT de sa carte (D114)
<# Action : ouvre les parametres de stockage de Windows.

   C'est la que Windows montre ce qui occupe le disque par categorie, et que s'active l'assistant de stockage qui libere de la place tout seul. Vigie n'agit pas a la place de l'utilisateur : elle le mene
   au bon endroit, ce qui est la seconde famille de boutons de D66. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:storagesense'
    @{ message = "Paramètres de stockage ouverts."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir : $($_.Exception.Message)"; result = @{ ok = $false } }
}
