# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
# @libelle: Gestionnaire des tâches | manual | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens Windows's Task Manager.

   Intent: lead the user there rather than act in their place. It is the resolution offered when applications are
   draining the resources during a game: Vigie SAYS which ones, the user closes what they want. Vigie kills no
   process in their place -- closing an application is a decision, not an automatism. Usage: cited by the cards. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'taskmgr.exe'
    @{ message = "Gestionnaire des tâches ouvert : ce qui n'est pas utile à la partie peut y être fermé."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir le Gestionnaire des tâches : $($_.Exception.Message)"; result = @{ ok = $false } }
}
