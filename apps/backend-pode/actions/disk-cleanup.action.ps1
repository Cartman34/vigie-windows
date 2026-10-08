# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Nettoyage de disque... | manual | fix   -- affiche quand un champ cite cette action (D66)
<# An action: it opens Windows's disc cleanup tool. Intent: lead the user to the tool rather than delete anything in their place. Usage: cited by the Storage card. #>
param([string]$Module, [hashtable]$Params)
Start-Process cleanmgr.exe
@{ message = 'Outil de nettoyage de disque ouvert.'; result = @{ ok = $true } }
