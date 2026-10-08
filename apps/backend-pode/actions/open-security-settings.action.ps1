# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Sécurité Windows | manual | info   -- bouton PERMANENT de sa carte (D114)
<# An action: it opens Windows Security.

   Intent: lead the user to the right place rather than act in their place, which is the second family of D66
   buttons. That is where the antivirus state and the firewall's are read, and where a scan is started again or
   a protection that was switched off is switched back on. Usage: it is cited by the Security cards. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'windowsdefender:'
    @{ message = "Sécurité Windows ouverte."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir : $($_.Exception.Message)"; result = @{ ok = $false } }
}
