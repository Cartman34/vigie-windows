# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, config, elevation, log, paths, task-ailment, win-tasks
<#
    Intent: VIGIE'S OWN SCHEDULED TASKS: the structure they must have, what their history says, the ailments they report and the repair that puts them back. A task that never ran says so, instead of looking healthy.
    Usage: dot-sourced by common.ps1, never run on its own.
#>


<#
    THE LEGACY NAME IS NORMALISED, AND IT DOES NOT WAIT FOR A BREAKDOWN.

    D117 gave everybody one scheme, "Vigie - <account>". But the rename rode on the repair
    path, and the repair path skips a healthy task -- so the one machine that carried the
    old name kept it for ever. Measured on 06/09, right after deploying D117: Famille was
    correctly named, fhaza's task was still plain "Vigie", because nothing was wrong with
    it. A convention that only applies to broken things is not a convention.

    THE NEW ONE IS BORN BEFORE THE OLD ONE DIES, always: Set-VigieAccountEnabled rebuilds
    the task under the new name, we CHECK it exists, and only then does the old one go. A
    failure in between leaves the account with two tasks -- never with none.

    Returns the new name when the rename happened, $null when it did not (and the caller
    then keeps working with the task it has).
#>
function Rename-VigieLegacyTask {
    param(
        [Parameter(Mandatory)][string]$Account,
        [string]$Backend = (Get-BackendRoot)
    )
    $newName = Get-VigieAccountTaskName -Name $Account
    if ($newName -eq 'Vigie') { return $null }   # ceinture : jamais se renommer en soi-meme
    try {
        $null = Set-VigieAccountEnabled -Name $Account -Enabled $true -Backend $Backend
        if (-not (Get-ScheduledTask -TaskName $newName -ErrorAction SilentlyContinue)) { return $null }
        Unregister-ScheduledTask -TaskName 'Vigie' -Confirm:$false -ErrorAction Stop
        return $newName
    } catch { return $null }
}





# Repairs what can be repaired, and REPORTS what it did. Silent when all is well. It never
# creates a missing task: enabling an account stays a decision.
function Repair-VigieTasks {
    param([string]$Backend = (Get-BackendRoot))
    $repairs = @()
    if (-not (Test-IsElevated)) { return $repairs }
    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { "$($_.TaskName)" -eq 'Vigie' -or "$($_.TaskName)".StartsWith($script:VigieTaskPrefix) })
    } catch { return $repairs }

    foreach ($t in $tasks) {
        $name = "$($t.TaskName)"
        # THE SERVER TASK IS NOT AN ACCOUNT'S: taken by its prefix, it was diagnosed as the task of an account named
        # after its suffix. Its maintenance is service-account-repair.
        if ($name -eq (Get-ServiceTaskName)) { continue }
        # WHOSE task is this? "Vigie - X" says it in its name; plain "Vigie" says it in its
        # PRINCIPAL -- we read that, rather than assume it belongs to whoever is looking.
        # The legacy task belongs to whoever installed it, not to the requester.
        $account = if ($name -eq 'Vigie') { ("$($t.Principal.UserId)" -split [regex]::Escape([string][char]92))[-1] }
                  else                  { $name.Substring($script:VigieTaskPrefix.Length) }

        # THE OLD NAME IS FIXED EVEN WHEN NOTHING IS WRONG, hence BEFORE the diagnosis: a
        # healthy task leaves this loop untouched, so the machine carrying "Vigie" would
        # have kept it for ever (measured on 06/09, right after D117 was deployed).
        if ($name -eq 'Vigie' -and $account) {
            $renamed = Rename-VigieLegacyTask -Account $account -Backend $Backend
            if ($renamed) {
                $repairs += [pscustomobject]@{ task = $name; problem = "elle portait l'ancien nom"; repaired = $true; waiting = $false }
                try { $t = Get-ScheduledTask -TaskName $renamed -ErrorAction Stop } catch { continue }
                $name = $renamed
            }
        }

        # A HEALTHY TASK IS NOT REWRITTEN. A fault of HISTORY -- never launched, or the last
        # launch failed -- is corrected by no writing at all: it will be confirmed at the
        # account's next logon, and not before. Reporting it, yes; claiming to repair it, no.
        $mal = Get-VigieTaskStructureAilment -Task $t
        if (-not $mal) {
            $histoire = Get-VigieTaskHistoryAilment -Task $t
            if ($histoire) {
                $repairs += [pscustomobject]@{ task = $name; problem = $histoire; repaired = $false; waiting = $true }
            }
            continue
        }
        try {
            # UNBLOCK FIRST. A task Windows believes running refuses everything: we end it,
            # which returns its state to the truth, before rewriting it.
            if ("$($t.State)" -eq 'Running' -and -not (Test-VigieTaskProcessAlive -Task $t)) {
                try { Stop-ScheduledTask -TaskName $name -ErrorAction Stop } catch { }
            }
            if ($name -eq 'Vigie') {
                # Our own task: it is rewritten with the machine's interpreter and the path
                # where the application REALLY sits now.
                $pwsh = Get-SharedPwshPath
                if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
                $client = Join-Path (Join-Path (Get-RepoRoot) 'apps') (Join-Path 'client' 'client.ps1')
                if (-not $pwsh -or -not (Test-Path -LiteralPath $client)) { continue }
                Set-ScheduledTask -TaskName $name -Action (New-VigieClientAction -Pwsh $pwsh -Client $client) -ErrorAction Stop | Out-Null
                # AND WE TRY THE RENAME AGAIN (D117). Reaching here means the pass at the top
                # of the loop failed -- the task answers again now that it has been rewritten,
                # so the attempt is worth making a second time.
                if ($account) {
                    $renamed = Rename-VigieLegacyTask -Account $account -Backend $Backend
                    if ($renamed) { $name = $renamed }
                }
            } else {
                # Another account's task: Set-VigieAccountEnabled knows how to rebuild it
                # entirely (machine interpreter, shared installation, run level).
                $null = Set-VigieAccountEnabled -Name $account -Enabled $true -Backend $Backend
            }
            # A DISABLED TASK IS RE-ENABLED. Vigie could SAY it since that morning and
            # stopped there: it rewrote the action, then announced "disabled" again, which
            # helps nobody. Enable-ScheduledTask was the missing gesture.
            # Idempotent: a task already enabled does not move.
            try { Enable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null } catch { }

            # WE OBSERVE (D43). Rewriting the task does not cure everything: a PAST FAILURE
            # stays written in its history for as long as it has not gone back to work, that
            # is, until that account opens a session again. Announcing "repaired" in that
            # case would be a false success -- and the screen would go on showing "out of
            # service" right beside it, contradicting itself (seen on 28/08).
            # WE READ BACK AFTERWARDS, not straight away: Windows returns the old state for a
            # brief moment after a rewrite, and the task still looked disabled when it no
            # longer was (seen on 28/08).
            Start-Sleep -Milliseconds 400
            $after = $null
            try { $after = Get-VigieTaskAilment -Task (Get-ScheduledTask -TaskName $name -ErrorAction Stop) } catch { }
            if ($after) {
                $repairs += [pscustomobject]@{ task = $name; problem = $mal; repaired = $false; remains = $after }
                Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-reecrite-mais' $name $after)
            } else {
                $repairs += [pscustomobject]@{ task = $name; problem = $mal; repaired = $true }
                Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-reparee' $name $mal)
            }
        } catch {
            $repairs += [pscustomobject]@{ task = $name; problem = $mal; repaired = $false; erreur = "$($_.Exception.Message)" }
            Write-Log -Backend $Backend -Name 'comptes' -Level 'ERROR' `
                      -Message (Get-Label 'common.tache-non-reparee' $name $mal $_.Exception.Message)
        }
    }
    if ($repairs.Count) { Clear-ComputerAccountsCache -Backend $Backend }
    return $repairs
}
