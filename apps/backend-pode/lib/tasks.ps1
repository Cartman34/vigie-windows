# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, client-app, config, elevation, format, log, paths, stage
<#
    Intent: VIGIE'S OWN SCHEDULED TASKS: the structure they must have, what their history says, the ailments they report and the repair that puts them back. A task that never ran says so, instead of looking healthy.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    IS THAT TASK REALLY RUNNING?

    A scheduled task killed by a shutdown can stay in state Running with no process left.
    Declared MultipleInstances=IgnoreNew, it then IGNORES every logon trigger: the account
    never gets Vigie again, and rebooting does not clear it. Measured on 04/09 -- « Vigie -
    Famille » still Running at 22:15, last run 18:38, no process, no icon on that session.

    So we do not believe the state: we look for the process the task launches, owned by the
    account the task runs as. No process, no run.
#>
function Test-VigieTaskProcessAlive {
    param([Parameter(Mandatory)]$Task)
    $action = @($Task.Actions)[0]
    $file = $null
    if ("$($action.Arguments)" -match '-File\s+"([^"]+)"') { $file = $Matches[1] }
    if (-not $file) { return $true }   # rien a comparer : on ne conclut pas
    $wanted = (Split-Path $file -Leaf)
    $owner = ("$($Task.Principal.UserId)" -split [regex]::Escape([string][char]92))[-1]
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue)) {
        if ("$($p.CommandLine)" -notlike ('*' + $wanted + '*')) { continue }
        $who = $null
        try { $who = "$((Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop).User)" } catch { }
        # NO READABLE OWNER, NO VERDICT: a process we can see without knowing whose it is
        # remains a reason to stay silent.
        if (-not $who -or $who -eq $owner) { return $true }
    }
    return $false
}

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

function Get-VigieTaskStructureAilment {
    param([Parameter(Mandatory)]$Task)
    $a = @($Task.Actions)[0]
    if (-not $a) { return "la tâche ne lance rien" }
    $exe = "$($a.Execute)".Trim('"')
    if (-not $exe) { return "aucun interpréteur" }
    <#
        THE INTERPRETER IS NOT ALWAYS WHAT THE TASK EXECUTES. Since 29/09 a client app is started through
        "conhost --headless <interpreter> ...", which is what keeps an empty terminal off the screen. The checks below
        are about the INTERPRETER -- a MSIX package, a path inside a profile -- so that is what must be read, wherever
        it sits. Reading conhost instead would have declared every one of those faults cured.
    #>
    if ((Split-Path $exe -Leaf) -ieq 'conhost.exe' -and "$($a.Arguments)" -match '--headless\s+"([^"]+)"') {
        $exe = $Matches[1]
    }
    if (-not (Test-Path -LiteralPath $exe)) { return "l'interpréteur n'existe plus : $exe" }
    # EXISTING IS NOT ENOUGH. Two paths look valid and are nonetheless unusable:
    #   - an MSIX package (C:\Program Files\WindowsApps\...) can only be launched by the
    #     accounts it is REGISTERED for, and its folder stays on disk after deregistration:
    #     Test-Path answers yes, the launch fails;
    #   - a path inside an account's profile (C:\Users\somebody\...) is unreadable by the
    #     others.
    # That is exactly what stopped Vigie starting for "Famille" (D79, D83).
    $profilesFolder = Join-Path $env:SystemDrive 'Users'
    $msixFolder    = Join-Path $env:ProgramFiles 'WindowsApps'
    if ($exe.StartsWith($msixFolder, [StringComparison]::OrdinalIgnoreCase)) {
        return "interpréteur MSIX, enregistré par compte : $exe"
    }
    if ($exe.StartsWith($profilesFolder, [StringComparison]::OrdinalIgnoreCase)) {
        return "interpréteur dans un profil, illisible par les autres comptes : $exe"
    }
    if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
        $launched = $Matches[1]
        if (-not (Test-Path -LiteralPath $launched)) { return ("l'application n'est plus là : " + $launched) }
        <#
            EXISTING IS NOT ENOUGH HERE EITHER: the task must launch THE client app of the current installation. On
            30/09 the folder was renamed, the old copy stayed behind, and the task went on naming it -- the file was
            still there, so nothing was declared broken, and the account ran two client apps at once, each with its
            own icon. A task that starts another application than the one installed cannot do its job.
        #>
        $expected = Join-Path (Join-Path (Get-RepoRoot) 'apps') (Join-Path 'client' 'client.ps1')
        if ((Test-Path -LiteralPath $expected) -and ($launched.Trim() -ine $expected)) {
            return ("la tâche lance une autre application que celle installée : " + $launched)
        }
    }
    <#
        A WINDOW NOBODY ASKED FOR IS NOT A BREAKDOWN, and saying it here was a mistake -- measured within the minute
        on 29/09: this function feeds the deployment card, which then announced, in red, that two accounts had no working
        client app -- about client apps that were running perfectly. A structural ailment says the task CANNOT work. An old launch
        line works; it merely shows a window, and that is repaired by rewriting the task at the next installation,
        not by alarming whoever reads the card.
    #>
    # DISABLED is structural: the task is there, well formed, and Windows refuses to launch
    # it. One gesture repairs it (Enable-ScheduledTask), so it belongs here and not to the
    # history.
    if ("$($Task.State)" -eq 'Disabled') { return "la tâche est désactivée dans Windows" }

    # STUCK IN "RUNNING": structural too, and one gesture repairs it (Stop-ScheduledTask).
    # While that state lasts, no logon starts anything -- the task is declared IgnoreNew.
    if ("$($Task.State)" -eq 'Running' -and -not (Test-VigieTaskProcessAlive -Task $Task)) {
        return "Windows la croit en cours alors que rien ne tourne : elle ne redémarrera plus"
    }

    # NO READABILITY VERDICT HERE, and that is a choice.
    #
    # This same check serves to CHOOSE a task's path (Set-VigieAccountEnabled) and proves
    # itself there: it did send "Famille" away from the repository, unreadable for
    # it, towards the shared installation. But when it JUDGES an existing task, it declared
    # unreadable a file that the same function, called from an ordinary session on the same
    # file and the same account, called readable.
    #
    # A diagnosis that contradicts itself depending on the observer diagnoses nothing -- and
    # showing "broken" on something that works is worse than staying silent (D105). Until
    # that gap is understood, the question is only asked at the moment a task is written,
    # where a mistake is corrected at once.

    # A TASK THAT LAUNCHES THE REPOSITORY is a structural fault: the working folder may be
    # unreadable to the account starting -- "Famille" has no right at all on
    # C:\EspaceRestreint, and neither has VigieService -- and it may move or disappear. The
    # task then starts nothing, without a word.
    #
    # It is NOT a matter of the declared environment: Vigie always runs from the shared
    # installation, development included. In dev it is the SOURCE of what is deployed there
    # that changes -- a branch rather than a published version -- and that reads in the
    # version number. Comparing the location with the declaration therefore reported a
    # permanent gap with nothing to repair (seen on 30/08).
    if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
        if ((Get-PathStage -Path $Matches[1]) -ne 'prod') {
            return "elle démarre depuis le dépôt de travail, pas depuis l'installation partagée"
        }
    }

    return $null
}

# What Get-VigieTaskHistoryAilment says of a task never launched: the cards tell it apart from a failed launch.
function Get-VigieTaskNeverRunText { "la tâche n'a jamais été exécutée" }

# The COMPLETE state: the structure first, then the history.
function Get-VigieTaskHistoryAilment {
    param([Parameter(Mandatory)]$Task)
    $a = @($Task.Actions)[0]
    if (-not $a) { return $null }
    # A TASK WHOSE CLIENT APP IS ALIVE HAS NOTHING LEFT TO CONFIRM. Its last result can be a start refused because
    # it was already running (0x800710E0 under IgnoreNew): on 13/09 an update started fhaza's running task, and the
    # card said "never started" of a client app in front of him. The process decides, not the state, which a
    # re-registration resets while the instance still runs.
    if (Test-VigieTaskProcessAlive -Task $Task) { return $null }
    # A TASK HEALTHY ON PAPER MAY NEVER HAVE RUN.
    #
    # Everything above examines the DEFINITION: the interpreter exists, the script exists.
    # That says nothing about what happened. So "Vigie activée" was displayed for an account
    # where Vigie had never started once -- seen on Famille on 28/08: the task present, the
    # session open, and no log anywhere.
    $info = $null
    try { $info = $Task | Get-ScheduledTaskInfo -ErrorAction Stop } catch { }
    if ($info) {
        # UNSIGNED, AND THAT IS THE WHOLE PROBLEM. Windows returns an HRESULT on 32 unsigned
        # bits: 0x800710E0 is 2 147 946 720, beyond Int32. The cast threw, and the whole
        # action failed on "Cannot convert value ... to type System.Int32" -- at the precise
        # moment one was trying to read why a task had failed.
        $code = [long]$info.LastTaskResult
        # The codes that are NOT failures: 0 success; 0x00041301 running; 0x00041302
        # termination requested; 0x00041303 never launched (handled just below).
        $benins = @(0, 267009, 267010, 267011)
        $jamais = (-not $info.LastRunTime) -or ($info.LastRunTime.Year -lt 2000) -or ($code -eq 267011)
        if ($jamais) { return (Get-VigieTaskNeverRunText) }
        if ($benins -notcontains $code) {
            # A FAILURE OLDER THAN THE INSTALLED CODE CONCERNS NOBODY ANY MORE.
            #
            # The "Famille" task had failed at 05:55; the fix was deployed at 08:44. Going on
            # showing it asked the user to "confirm" the failure of a program that no longer
            # exists -- while the deployment had happened by itself. So the failure's date is
            # compared with that of the file the task launches: if the application has changed
            # since, we say nothing.
            $since = $null
            if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
                try { $since = (Get-Item -LiteralPath $Matches[1] -ErrorAction Stop).LastWriteTime } catch { }
            }
            if ($since -and $since -gt $info.LastRunTime) { return $null }
            return ("la dernière exécution a échoué (code 0x" + ([uint32]$code).ToString('X8') + ", le " +
                    (Format-DateForDisplay $info.LastRunTime) + ")")
        }
    }
    return $null
}

function Get-VigieTaskAilment {
    param([Parameter(Mandatory)]$Task)
    $mal = Get-VigieTaskStructureAilment -Task $Task
    if ($mal) { return $mal }
    return (Get-VigieTaskHistoryAilment -Task $Task)
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
