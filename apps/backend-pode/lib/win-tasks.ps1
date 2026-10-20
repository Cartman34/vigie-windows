# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: THE WINDOWS TASK SCHEDULER, READ FAST: the tasks of ONE folder, through the scheduler's own interface. Get-ScheduledTask -TaskPath walks the whole tree on every call -- 6 682 ms for four folders, measured on 29/09 -- and the same six tasks are read in 43 ms here. Vigie's own tasks are another subject (tasks.ps1), and the cadence of the cards yet another (scheduler.ps1).
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# The REAL and complete state of the Windows Update locking. READ ONLY.
#
# It is the single state reading of this subject: the probe displays it, the actions use it to
# say what was OBSERVED after acting (D43), and the audit takes it as it stands.
#
# `locked` means the lock is COMPLETE: automatic updates off AND the permission lock laid.
# The two halves answer different questions and are never conflated.
<#
    THE TASKS OF ONE FOLDER, IN FORTY MILLISECONDS INSTEAD OF SIX SECONDS AND A HALF.

    Get-ScheduledTask -TaskPath walks the whole tree on each call: four folders cost 6 682 ms, measured on 29/09, and
    that alone was almost all of the Windows Update lock card. The Task Scheduler's own interface opens a folder and
    lists it: 43 ms for the same six tasks, the same names, the same states.

    The state is given as a number by that interface; it is translated to the words the rest of the code already uses.
    A folder we may not read answers nothing, which is exactly what the cmdlet did -- and here it IS the information:
    the lock is on.
#>
$script:TaskStateNames = @{ 0 = 'Unknown'; 1 = 'Disabled'; 2 = 'Queued'; 3 = 'Ready'; 4 = 'Running' }

function Get-TasksInFolder {
    param([Parameter(Mandatory)][string]$Path)
    $out = @()
    # THE SERVICE, ONCE. Only ITS failure is a reason to fall back: a FOLDER that refuses is an answer, not a breakdown.
    if (-not $script:TaskService) {
        try {
            $svc = New-Object -ComObject Schedule.Service
            $svc.Connect()
            $script:TaskService = $svc
        } catch { $script:TaskService = $null }
    }
    if ($script:TaskService) {
        try {
            $folder = $script:TaskService.GetFolder($Path.TrimEnd([char]92))
            foreach ($task in $folder.GetTasks(1)) {
                $state = $script:TaskStateNames[[int]$task.State]
                if (-not $state) { $state = "$($task.State)" }
                $out += [pscustomobject]@{ path = $Path; name = "$($task.Name)"; state = $state }
            }
        } catch {
            <#
                A FOLDER WE CANNOT OPEN HAS NOTHING TO SAY, and that silence IS the information: it is what the ACL
                lock does to UpdateOrchestrator. Falling back to the cmdlet here cost 3 400 ms per pass to be told
                the same nothing (measured 29/09) -- the whole gain of this function, spent on a refusal.
            #>
        }
        return $out
    }
    # NO SERVICE AT ALL: the cmdlet, slow but present.
    try {
        foreach ($t in (Get-ScheduledTask -TaskPath $Path -ErrorAction Ignore)) {
            $out += [pscustomobject]@{ path = "$($t.TaskPath)"; name = "$($t.TaskName)"; state = "$($t.State)" }
        }
    } catch { }
    return $out
}
