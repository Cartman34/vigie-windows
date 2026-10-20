# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, paths, stage, win-tasks
<#
    Intent: WHAT IS WRONG WITH A SCHEDULED TASK, read without touching it: its structure, what its history says, and the one verdict that gathers both. A task that never ran says so instead of looking healthy. REPAIRING is tasks.ps1; this answers questions, which is why the accounts can ask them too.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
