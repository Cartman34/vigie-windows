# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- ouvre une fenetre : elle doit s'afficher chez le DEMANDEUR
<# The open-windows-update action: it opens the Windows Update settings (a manual installation).
   Intent: install nothing -- it respects the principle "nothing without consent". Usage: cited by the Windows Update card. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:windowsupdate'
    @{ message = "Fenêtre Windows Update ouverte. Pour installer : déverrouillez (Mode MAJ), installez, puis re-verrouillez."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir Windows Update : $($_.Exception.Message)"; result = @{ ok = $false } }
}
