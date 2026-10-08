# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Paramètres de stockage | manual | info   -- bouton PERMANENT de sa carte (D114)
<# An action: it opens Windows's storage settings.

   Intent: lead the user to the right place rather than act in their place, which is the second family of D66
   buttons. That is where Windows shows what the disc is used by, per category, and where the storage assistant
   that frees space on its own is switched on. Usage: it is cited by the Storage card. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:storagesense'
    @{ message = "Paramètres de stockage ouverts."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir : $($_.Exception.Message)"; result = @{ ok = $false } }
}
