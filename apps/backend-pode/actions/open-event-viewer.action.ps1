# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- needs no privilege Windows does not already grant (D65)
# @execution: session   -- opens a window: it must appear in the REQUESTER's session
# @libelle: Observateur d'événements | manual | info   -- shown when a field names this action (D66)
<# Action: opens the Windows Event Viewer, where the errors named by the card "Journal Windows" are read in full. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'eventvwr.msc'
    @{ message = "Observateur d'événements ouvert : le journal Système est sous « Journaux Windows »."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir l'Observateur d'événements : $($_.Exception.Message)"; result = @{ ok = $false } }
}
