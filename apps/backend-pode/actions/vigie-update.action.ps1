# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- redeploie hors du profil et relance l'application (D65)
# @libelle: Mettre a jour Vigie | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# An action: it updates Vigie, then restarts it.

   Intent: be a button that does nothing of its own -- it starts THE INSTALLATION, the same one setup.cmd starts,
   described in doc/progress/targeting/install-update.md. Fetch before stopping, check, stop, back up, lay down,
   verify, restart -- it is the installation that knows in which order, and there is no second copy of that
   sequence.
   Usage: it is called from the Deployment card's button. Where the code comes from depends on the machine, and
   the fetch decides on its own (D99): if there is a REPOSITORY on the workstation -- even when the server app
   runs from Program Files, because the installation knows where it came from -- that is the source, and the tag
   is laid on the way. Otherwise, the latest version published on GitHub.

   All of it under the WATCHER (D82): the exit code is observed and reported, so a failed update becomes a red
   line on the card instead of a silence. Code 3 -- already up to date -- is NOT a failure (D77). #>


param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

<#
    THE BUTTON CALLS THE INSTALLATION, NOT SOME OTHER GESTURE.

    It used to start "vigie-update", which did almost the same thing as the installation -- but not quite: two
    roads for one gesture, so two behaviours to maintain and one that drifts. Since 30/08 there is only one,
    described in

    The installation is started DETACHED (the watcher takes care of it): it stops the server app in the middle of
    its sequence, and it is the server app that started it. A child process would die with it and everything that
    follows would never happen.
#>
$script = Join-Path (Get-RepoRoot) 'scripts/install.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    return @{ message = "Script d'installation introuvable : $script"; result = @{ ok = $false } }
}

$journal = Join-Path (Get-LogDir -Backend $backend) ('update_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$pwsh = $null
try { $pwsh = (Get-Process -Id $PID).Path } catch { }
if (-not $pwsh) { $pwsh = 'pwsh.exe' }

$lance = $false
try {
    # RAW VALUES: Start-ChildProcess is what quotes them (D116).
    # WHO ASKS follows the script: it runs detached, under the service's account, and it is in the requester's
    # session that the version tag will be laid (D112).
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
              '-File', $script)
    $requester = Get-RequesterAccount
    if ($requester) { $argv += @('-Requester', $requester) }
    # NO WINDOW: the server has no desktop, it would go nowhere.
    $argv += '-NoWindow'
    # AND WE TELL IT THAT THE "an operation is running" MARK IS ITS OWN: the watcher lays it down before starting
    # it, and the installation refused to run when it saw it.
    $argv += @('-FromAction', 'vigie-update')
    # The DEPLOYMENT card handles the deployments -- and it is always there. The debugging card, for its part, can
    # be switched off: following the operation there would have been invisible.
    $lance = [bool](Start-Operation -Module 'deployment' -Probes @('deployment.probe.ps1') `
                        -Label 'Mise à jour de Vigie' -Action 'vigie-update' `
                        -File $pwsh -Arguments $argv -Log $journal -Backend $backend)
    Write-Log -Backend $backend -Name 'update' -Message (Get-Label 'vigie-update.mise-jour-lancee-journal' $journal)
} catch {
    Write-Log -Backend $backend -Name 'update' -Level 'ERROR' -Message $_.Exception.Message
}

if (-not $lance) { return @{ message = "Impossible de lancer la mise à jour."; result = @{ ok = $false } } }

@{
    message = "Mise à jour lancée. Elle dure une trentaine de secondes, puis Vigie redémarre toute seule."
    result  = @{ ok = $true; async = $true; module = 'deployment'; invalidate = @('deployment.probe.ps1') }
}
