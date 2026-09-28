# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- reads what Vigie kept of a past session (D65)
# @execution: serveur   -- the sessions are kept by the server app, which alone writes them
# @libelle: Voir le récapitulatif | dialog | info   -- shown when a field names this action (D66)
<# Action: hands over the recap of a game session -- the last one, or the one asked for.

   The recap is ALWAYS a popin (owner, 28/09): there is too much in it for a card, and the same window must open
   whatever the door -- the card's button, the end of a session, the notification, or the list of past games.
   This action only reads; the window is built by the page. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$wanted = if ($Params -and $Params.session) { "$($Params.session)" } else { $null }
$session = $null
if ($wanted) {
    foreach ($s in @(Get-GameSessions -Backend $backend -Last 200)) {
        try { if ((ConvertTo-UtcDate $s.startedAt) -eq (ConvertTo-UtcDate $wanted)) { $session = $s; break } } catch { }
    }
} else {
    $session = Get-LastGameSession -Backend $backend
}
if (-not $session) {
    return @{ message = "Aucune partie gardée pour l'instant : le récapitulatif apparaît à la fin de la première partie."
              result = @{ ok = $false } }
}
@{ message = "Récapitulatif de la partie."; result = @{ ok = $true; session = $session } }
