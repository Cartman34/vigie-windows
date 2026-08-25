# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : ouvre le Gestionnaire des taches de Windows.

   C'est la resolution proposee quand des applications pompent les ressources pendant une
   partie : Vigie DIT lesquelles, l'utilisateur ferme ce qu'il veut. Vigie ne tue aucun
   processus a sa place -- fermer une application est une decision, pas un automatisme. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'taskmgr.exe'
    @{ message = "Gestionnaire des tâches ouvert. Fermez ce qui n'est pas utile à la partie."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir le Gestionnaire des tâches : $($_.Exception.Message)"; result = @{ ok = $false } }
}
