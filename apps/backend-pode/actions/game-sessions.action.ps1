# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- reads what Vigie kept of past sessions (D65)
# @execution: serveur   -- the sessions are kept by the server app, which alone writes them
# @libelle: Parties précédentes | dialog | info   -- shown when a field names this action (D66)
<# Action: the list of the game sessions kept, most recent first.

   One line per game: when, which game, how long, and the bottleneck worth naming. The full recap of any of them is
   one click away, through game-recap: the list is a door, not a report. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$sessions = @(Get-GameSessions -Backend $backend -Last 40)
if (-not $sessions.Count) {
    return @{ message = "Aucune partie gardée pour l'instant."; result = @{ ok = $true; sessions = @() } }
}
# LIGHT ON PURPOSE: the list carries what a line shows, never the whole detail of every session.
$rows = @(foreach ($s in $sessions) {
    $jam = @($s.jams) | Select-Object -First 1
    [pscustomobject]@{
        startedAt = "$($s.startedAt)"; endedAt = "$($s.endedAt)"; game = "$($s.game)"; seconds = [int]$s.seconds
        jam = $(if ($jam) { "$($jam.label)" } else { $null })
        jamSeconds = $(if ($jam) { [int]$jam.seconds } else { 0 })
    }
})
@{ message = "$($rows.Count) partie(s) gardée(s)."; result = @{ ok = $true; sessions = $rows } }
