# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Paramètres Wi-Fi | manual | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens Windows's Wi-Fi settings.

   Intent: lead the user to where the choice is made rather than act in their place. It is offered as the
   resolution when the Wi-Fi association drops: that is where one picks the network, makes a connection again, or
   checks the adapter. Vigie neither cuts nor reconnects the link in the user's place: on a remote workstation, a
   failed reconnection leaves the machine with no network. Usage: it is cited by the Network card. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:network-wifi'
    @{ message = "Paramètres Wi-Fi ouverts."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir les paramètres Wi-Fi : $($_.Exception.Message)"; result = @{ ok = $false } }
}
