# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses: paths
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

function New-VigieClientAction {
    param([Parameter(Mandatory)][string]$Pwsh, [Parameter(Mandatory)][string]$Client)
    $arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Client + '"'
    $conhost = Get-HeadlessConsolePath
    if ($conhost) { return (New-ScheduledTaskAction -Execute $conhost -Argument ('--headless "' + $Pwsh + '" ' + $arg)) }
    return (New-ScheduledTaskAction -Execute $Pwsh -Argument $arg)
}

<#
    HOW A CLIENT APP IS STARTED -- written ONCE, used by everyone who builds that task.

    It was written in three places: the installer, the repair of the legacy task, and the enabling of an account. On
    29/09 I changed one of them and the two others kept the old line, so the fault stayed exactly where it had been
    reported. Three copies of a launch line is three launch lines.

    conhost --headless creates the console WITHOUT a window. "-WindowStyle Hidden" only hides one that Windows has
    already made: unnoticed on an administrator account, an empty terminal at every logon on a standard one, and a
    flash that steals the focus whenever a deployment restarts a client app.
#>
function Get-HeadlessConsolePath {
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    if (Test-PathSafe $conhost) { return $conhost }
    return $null
}
