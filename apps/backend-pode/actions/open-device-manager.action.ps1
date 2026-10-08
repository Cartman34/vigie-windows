# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Gestionnaire de périphériques | manual | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens Windows's Device Manager.

   Intent: lead the user to where Windows shows the state of the hardware and offers the driver update. It is
   offered as the resolution when a graphics adapter is missing or the driver's tool is absent. A standard
   account can open it (Windows puts it in read-only mode): so we do not forbid what Windows grants them (D65).
   Usage: it is cited by the Gaming card. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-ChildProcess -FilePath 'mmc.exe' -Arguments @('devmgmt.msc')
    @{ message = "Gestionnaire de périphériques ouvert : section « Cartes graphiques »."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir le Gestionnaire de périphériques : $($_.Exception.Message)"; result = @{ ok = $false } }
}
