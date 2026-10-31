# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, action-resources, contract, format, log, native, paths, var, win-accounts
<#
    Intent: WHAT IS RUNNING, FOR EVERYONE (D95), AND WHO HOLDS WHAT (D93): the mark a card wears while it is busy, the resources an action takes, the lock that keeps two actions off the same thing, and the fate of a background task -- kept, then said.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- A CARD'S BACKGROUND TASK: saying it, and for as long as it lasts --------
#
# The owner's rule: "a card that launches an action in the background should go into the
# operation-running state immediately". The interface marks it from the click, but that
# marking does not survive the first refresh: it is the SERVER that must carry the truth, or
# the card goes calm again while the work continues -- seen on 26/08 during the installation
# of PowerShell 7 from the Accounts card.
#
# The mark carries the process id of what was launched: for as long as it lives, the card is
# busy; the moment it dies, the mark clears itself. Nothing to clean up by hand, and a brutal
# stop does not leave a card busy for ever.
function Get-ModuleBusyMarkPath {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'run' -File ('busy-' + $Module + '.json')
}

function Set-ModuleBusyMark {
    param(
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][string]$Label,
        [int]$ProcessId,
        [string]$Action = '',
        # What this work TAKES UP: it is what will allow refusing whatever would disturb it,
        # and only that (D93).
        [string[]]$Resources = @(),
        # The card button that spins when it is not the action itself, the launch time, the operation's log.
        [string]$Button = '',
        [string]$At = '',
        [string]$Log = '',
        # HOW LONG THIS WORK MAY TAKE before it is treated as stuck. Carried by the mark so that the READER can
        # judge: if the process that set the mark is blocked, it can no longer judge anything itself.
        [int]$MaxSeconds = 0,
        [string]$Backend = (Get-BackendRoot)
    )
    $f = Get-ModuleBusyMarkPath -Module $Module -Backend $Backend
    $d = Split-Path $f -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    if (-not $Resources -or -not $Resources.Count) { $Resources = @(Get-ActionResources -Type $Action -Module $Module) }
    $o = [ordered]@{ label = $Label; pid = $ProcessId; action = $Action
                     resources = @($Resources)
                     button = $Button; log = $Log; maxSeconds = $MaxSeconds
                     at = $(if ($At) { $At } else { (Get-Date).ToUniversalTime().ToString('o') }) }
    try { ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath $f -Encoding UTF8 } catch { }
}

function Get-ModuleBusyMark {
    # ANOTHER ACCOUNT'S ROOT, because an operation is marked WHERE IT RUNS. A client task works in its account's
    # session and writes at home (D65); the reader is the elevated server, and it is the one that gathers.
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    $f = Get-ModuleBusyMarkPath -Module $Module -Backend $Backend -VarRoot $VarRoot
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $o = $null
    try { $o = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json } catch { }
    if (-not $o) { return $null }
    $alive = $false
    try {
        $process = Get-Process -Id ([int]$o.pid) -ErrorAction Stop
        $alive = $true
        # A PROCESS ID IS REUSED. A process born well after the mark is not the one it names.
        try {
            $markedAt = ConvertTo-UtcDate $o.at
            if ($markedAt -and $process.StartTime.ToUniversalTime() -gt $markedAt.AddSeconds(5)) { $alive = $false }
        } catch { }
    } catch { $alive = $false }
    if (-not $alive) {
        # A PROCESS GONE WITHOUT A RESULT IS A FAILURE, never a silent end: the disappearance of the mark was read
        # as "finished" (12/09). A result written since the launch means the operation did end properly.
        $lastRun = Get-ModuleLastRun -Module $Module -Backend $Backend -VarRoot $VarRoot
        $resultAt = if ($lastRun) { ConvertTo-UtcDate $lastRun.at } else { $null }
        $launchedAt = ConvertTo-UtcDate $o.at
        # IN SOMEBODY ELSE'S VAR WE NEITHER WRITE NOR ERASE: the process that marked is theirs, the result is
        # theirs to write, and a reader passing by must not conclude in their name. We simply stop reporting it.
        if (-not $VarRoot) {
            if (-not $resultAt -or ($launchedAt -and $resultAt -lt $launchedAt)) {
                Set-ModuleLastRun -Module $Module -Action "$($o.action)" -Label "$($o.label)" -Code -1 -Log "$($o.log)" `
                                  -Error (Get-Label 'common.operation-sans-resultat') -Backend $Backend
            }
            Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
    return $o
}


# --- WHAT IS RUNNING, FOR EVERYONE (D95) -------------------------------------
#
# The notifications lived in the PAGE: a second window open knew nothing of an operation
# launched from the first, and a page opened AFTER a deployment had left saw no trace of it
# at all. The server, on the other hand, knows: it holds the operation marks and their
# results.
#
# So the complete state is returned -- what is running, and what has just finished -- and
# every page agrees with it. The server is the source, the pages are reflections.
<#
    WHAT IS RUNNING, AND WHAT IS PUBLISHED OF IT.

    A watch task comes round every thirty seconds: showing each one would put something permanently in "what is
    running", for information nobody reads. Its mark still always exists -- that is what makes a hang visible --
    but it is PUBLISHED only past its ceiling. -IncludeWatch returns everything, for the debug card, which does
    want the whole list.

    While all is well: nothing. The moment a task overruns: it appears like any other operation.
#>
<#
    EVERY VAR WHERE AN OPERATION MAY BE MARKED: the server's own, and one per account.

    WHY. An operation marks itself WHERE IT RUNS, and that is not always here. A client task works in its
    account's session, so it writes in that account's var (D65) -- and the three readers of the protocol looked
    in one single folder, the server's. Measured on 16/10: `pkg-inventory` alive for 24 minutes, 154 MB, 54 s of
    processor, and /operations answering `running: []`, `results: []`. The protocol makes that route the ONLY
    door where the state of an operation is read; the door was looking in one room.

    Reading another account's profile needs elevation, which the server has. Without it, nothing is found there
    and the answer is simply what is visible -- never a refusal passed off as "nothing is running".
#>
function Get-OperationVarRoots {
    param([string]$Backend = (Get-BackendRoot))
    # The first entry is OURS, named by an empty root: the writer's own var, resolved as usual.
    $roots = @([pscustomobject]@{ Account = ''; VarRoot = '' })
    foreach ($account in @(Get-EnabledAccounts -Backend $Backend)) {
        $name = "$($account.name)"
        if (-not $name) { continue }
        $root = $null
        try { $root = Get-AccountVarRoot -Account $name } catch { }
        if (-not $root -or -not (Test-PathSafe $root)) { continue }
        # OUR OWN VAR IS NOT READ TWICE: on a development workstation the server runs under the person's account,
        # so their profile IS our var and every mark would be reported in duplicate.
        if ("$root".TrimEnd([char]92, [char]47) -ieq "$(Get-VarRoot -Backend $Backend)".TrimEnd([char]92, [char]47)) { continue }
        $roots += [pscustomobject]@{ Account = $name; VarRoot = $root }
    }
    return $roots
}

function Get-RunningOperations {
    param([string]$Backend = (Get-BackendRoot), [switch]$IncludeWatch)
    $ops = @()
    foreach ($where in @(Get-OperationVarRoots -Backend $Backend)) {
        $folder = Split-Path (Get-ModuleBusyMarkPath -Module 'x' -Backend $Backend -VarRoot $where.VarRoot) -Parent
        if (-not (Test-PathSafe $folder)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)) {
            $module = ($f.BaseName -replace '^busy-', '')
            $m = Get-ModuleBusyMark -Module $module -Backend $Backend -VarRoot $where.VarRoot
            if (-not $m) { continue }
            # THE PROCESS NUMBER TRAVELS TOO. The protocol says the mark carries it, and that /operations is the
            # ONE place where an operation's state is read. The route dropped it, so through the door the protocol
            # designates nobody could tell a live operation from a dead one -- the check existed, reading the mark
            # directly, elsewhere. Found on 06/10 while proving the protocol on a 613-second disk analysis.
            <#
                AND THE READER SAYS WHETHER IT IS LATE.

                The mark carries its own ceiling; here we compare it to the clock. The judgement has to live on this
                side: a watch task that hangs hangs the timer with it, and nothing in that runspace can report
                anything any more. This function runs in the HTTP request, which is another thread -- so a blocked
                task is seen even when everything else is frozen.
            #>
            $maxSeconds = 0
            try { $maxSeconds = [int]$m.maxSeconds } catch { }
            $running = 0
            try { $running = [int]([datetime]::UtcNow - (ConvertTo-UtcDate $m.at)).TotalSeconds } catch { }
            $ops += [pscustomobject][ordered]@{
                module    = $module
                # WHOSE SESSION IT RUNS IN, empty when it is the server's own. Two accounts can inventory their
                # packages at the same second: same module, two operations, and the reader must not merge them.
                account   = "$($where.Account)"
                label     = "$($m.label)"
                action    = "$($m.action)"
                pid       = [int]$m.pid
                resources = @($m.resources)
                # ISO, WITH ITS ZONE. The mark is written in ISO, but ConvertFrom-Json hands back a date OBJECT:
                # written out again as a string, it left under the culture of the service account -- UTC with no
                # zone at all. The page read that as a local time and announced two hours for an operation
                # started one minute earlier, seen on 17/10 during a real installation.
                at        = $(try { (ConvertTo-UtcDate $m.at).ToString("o") } catch { "$($m.at)" })
                seconds   = $running
                maxSeconds = $maxSeconds
                overdue   = ($maxSeconds -gt 0 -and $running -gt $maxSeconds)
            }
        }
    }
    if (-not $IncludeWatch) {
        $ops = @($ops | Where-Object { "$($_.module)" -ne 'veille' -or $_.overdue })
    }
    return $ops
}

# The RECENT results: what finished recently enough that a page opened since still has reason
# to show it. Past that, it is history: it lives on the card concerned, not in the
# notifications.
function Get-RecentOperationResults {
    param([int]$Minutes = 15, [string]$Backend = (Get-BackendRoot))
    $res = @()
    $limit = [datetime]::UtcNow.AddMinutes(-$Minutes)
    foreach ($where in @(Get-OperationVarRoots -Backend $Backend)) {
      $folder = Split-Path (Get-ModuleLastRunPath -Module 'x' -Backend $Backend -VarRoot $where.VarRoot) -Parent
      if (-not (Test-PathSafe $folder)) { continue }
      foreach ($f in @(Get-ChildItem -LiteralPath $folder -Filter 'lastrun-*.json' -File -ErrorAction SilentlyContinue)) {
        $module = ($f.BaseName -replace '^lastrun-', '')
        $r = Get-ModuleLastRun -Module $module -Backend $Backend -VarRoot $where.VarRoot
        if (-not $r) { continue }
        $when = ConvertTo-UtcDate $r.at
        if (-not $when -or $when -lt $limit) { continue }
        $res += [pscustomobject][ordered]@{
            module  = $module
            account = "$($where.Account)"
            label   = "$($r.label)"
            action  = "$($r.action)"
            code    = [int]$r.code
            seconds = [int]$r.seconds
            log     = "$($r.log)"
            error   = "$($r.error)"
            at      = $(try { (ConvertTo-UtcDate $r.at).ToString("o") } catch { "$($r.at)" })
        }
      }
    }
    return $res
}


# The resources currently HELD, and by what. The live marks are read back: a mark whose
# process is dead holds nothing any more, and it clears itself as it is read.
function Get-HeldResources {
    param([string]$Backend = (Get-BackendRoot))
    $tenues = @()
    # EVERY SESSION'S MARKS: a resource taken by a client task is taken for the whole machine. Reading our own
    # folder alone let an action start on something already in use elsewhere.
    foreach ($where in @(Get-OperationVarRoots -Backend $Backend)) {
        $folder = Split-Path (Get-ModuleBusyMarkPath -Module 'x' -Backend $Backend -VarRoot $where.VarRoot) -Parent
        if (-not (Test-PathSafe $folder)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)) {
            $module = ($f.BaseName -replace '^busy-', '')
            $m = Get-ModuleBusyMark -Module $module -Backend $Backend -VarRoot $where.VarRoot
            if (-not $m) { continue }
            foreach ($r in @($m.resources)) {
                if ("$r") { $tenues += [pscustomobject]@{ resource = "$r"; label = "$($m.label)"; module = $module; account = "$($where.Account)" } }
            }
        }
    }
    return $tenues
}

# Can THIS action be launched now? Returns $null if so, otherwise the reason, in plain words.
function Test-ActionResourcesFree {
    param([Parameter(Mandatory)][string]$Type, [string]$Module, [string]$Backend = (Get-BackendRoot))
    $veut = @(Get-ActionResources -Type $Type -Module $Module)
    if (-not $veut.Count) { return $null }
    $tenues = @(Get-HeldResources -Backend $Backend)
    if (-not $tenues.Count) { return $null }
    foreach ($t in $tenues) {
        # 'machine' crosses everything, in both directions.
        if ($t.resource -eq 'machine' -or $veut -contains 'machine' -or $veut -contains $t.resource) {
            return ("« " + $t.label + " » est en cours et utilise déjà " +
                    $(if ($t.resource -eq 'machine') { "toute la machine" } else { "la même ressource (" + $t.resource + ")" }) +
                    ". Nouvel essai possible quand cette opération sera terminée.")
        }
    }
    return $null
}

<#
    THE PROTOCOL AROUND A PIECE OF WORK, IN ONE GESTURE.

    Mark before, measure, clear, say what happened. It was written out by hand at every place that respected the
    protocol -- and simply ABSENT wherever nobody had written it out: a client task ran for 24 minutes with no
    mark and no result (16/10), because respecting the protocol meant remembering five steps.

    Two policies, because the callers are not alike:
      - a WATCH task reports only when it overruns -- a result every five seconds would bury the real ones -- and
        leaves the mark alone, since the round that encloses it owns one of its own;
      - an OPERATION reports always, and takes its mark down when it ends (D82, D43).

    The work's own value is handed back, and a failure is RECORDED then re-thrown: the caller stays the one who
    decides, and the result exists either way.
#>
function Invoke-MarkedTask {
    param(
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Body,
        [string]$Action = '',
        [string]$Button = '',
        # HOW TO NAME THIS WORK in the overrun line, phrased by the caller, who alone knows whether it is one of
        # its watches or a task running for an account. One sentence then serves every kind of task.
        [string]$What = '',
        [int]$MaxSeconds = 0,
        [switch]$ReportOnlyWhenOverdue,
        [switch]$KeepMark,
        [string]$Backend = (Get-BackendRoot)
    )
    Set-ModuleBusyMark -Module $Module -Label $Label -ProcessId $PID -Action $Action -Button $Button `
                       -MaxSeconds $MaxSeconds -Backend $Backend
    # THE DURATION OF THE WORK, NOT THE TIME ON THE CLOCK. The machine went to sleep at 21:07 with a watch round
    # under way and woke at 06:53: the round was credited with 35 157 seconds for a ceiling of 10, logged as an
    # error, and the real overruns drowned among false ones. This counter does not advance while the machine
    # sleeps. The clock still says WHEN it started, which is a different question (S22).
    $t0 = Get-ActiveMilliseconds
    $result = $null
    $failure = $null
    try { $result = & $Body }
    catch { $failure = $_ }
    $seconds = [int](((Get-ActiveMilliseconds) - $t0) / 1000)
    $overdue = ($MaxSeconds -gt 0 -and $seconds -gt $MaxSeconds)
    if (-not $KeepMark) { Clear-ModuleBusyMark -Module $Module -Backend $Backend }
    $say = $failure -or $overdue -or -not $ReportOnlyWhenOverdue
    if ($say) {
        $code = 0
        $reason = ''
        if ($failure) { $code = 1; $reason = "$($failure.Exception.Message)" }
        elseif ($overdue) { $code = 1; $reason = (Get-Label 'common.veille-trop-longue' $MaxSeconds) }
        try {
            Set-ModuleLastRun -Module $Module -Action $Action -Label $Label -Code $code -Seconds $seconds `
                              -Error $reason -Backend $Backend
        } catch { }
        if ($code -ne 0) {
            try {
                Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' `
                          -Message (Get-Label 'common.tache-depassement' $(if ($What) { $What } else { $Action }) $seconds $MaxSeconds)
            } catch { }
        }
    }
    if ($failure) { throw $failure }
    return $result
}

# --- THE FATE OF A BACKGROUND TASK: keep it, then say it ---------------------
#
# "Following errors is paramount": an asynchronous action cannot fail in silence. The watcher
# (workers/watched-action.worker.ps1) writes here what it observed; the card's probe reads it
# back and turns it into a line, green or red.
function Get-ModuleLastRunPath {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'cache' -File ('lastrun-' + $Module + '.json')
}


function Set-ModuleLastRun {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Action = '', [string]$Label = '',
        [Parameter(Mandatory)][int]$Code,
        [int]$Seconds = 0, [string]$Log = '', [string]$Error = '',
        [string]$Backend = (Get-BackendRoot)
    )
    # THE REASON RATHER THAN THE CODE, as soon as it can be read.
    if (-not $Error -and $Code -ne 0 -and $Log) {
        $lu = Get-FailureReasonFromLog -Log $Log
        if ($lu) { $Error = $lu }
    }
    $f = Get-ModuleLastRunPath -Module $Module -Backend $Backend
    $d = Split-Path $f -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $o = [ordered]@{ action = $Action; label = $Label; code = $Code; seconds = $Seconds
                     log = $Log; error = $Error; at = (Get-Date).ToUniversalTime().ToString('o') }
    try { ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath $f -Encoding UTF8 } catch { }
}

function Get-ModuleLastRun {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    $f = Get-ModuleLastRunPath -Module $Module -Backend $Backend -VarRoot $VarRoot
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch { return $null }
}

function Clear-ModuleLastRun {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    Remove-Item -LiteralPath (Get-ModuleLastRunPath -Module $Module -Backend $Backend -VarRoot $VarRoot) `
                -Force -ErrorAction SilentlyContinue
}

function Clear-ModuleBusyMark {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    Remove-Item -LiteralPath (Get-ModuleBusyMarkPath -Module $Module -Backend $Backend) `
                -Force -ErrorAction SilentlyContinue
}

# THE ONLY WAY TO LAUNCH AN ASYNCHRONOUS OPERATION. The rules: doc/progress/targeting/operations.md, in the
# section on the protocol of the asynchronous operations. A PowerShell worker and an external program take the same road:
# the watcher runs either one, waits for its end and writes the result. The busy mark is written HERE,
# with the watcher's process id, before the action answers.
function Start-Operation {
    param(
        [Parameter(Mandatory)][string]$Module,     # the card concerned (module id)
        [Parameter(Mandatory)][string]$Action,     # the action id, which names the operation for the pages
        [Parameter(Mandatory)][string]$Label,      # what the pages display
        [string[]]$Probes = @(),                   # probes to recompute at the end
        [string]$Worker = '',                      # either a worker of workers/, run by this pwsh...
        [hashtable]$ArgsMap = @{},
        [string]$File = '',                        # ...or an external program
        [string[]]$Arguments = @(),
        [string]$Log = '',
        [string]$Button = '',                      # the card button that spins, when it is not the action
        [string]$Backend = (Get-BackendRoot)
    )
    $exe = $null
    try { $exe = (Get-Process -Id $PID).Path } catch { }
    if (-not $exe) { $exe = 'pwsh.exe' }
    if ($Worker) {
        $workerPath = Join-Path (Join-Path $Backend 'workers') $Worker
        if (-not (Test-Path -LiteralPath $workerPath)) { throw "Worker introuvable : $workerPath" }
        $workerArgs = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($ArgsMap | ConvertTo-Json -Compress -Depth 6)))
        $File = $exe
        $Arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $workerPath,
                       '-Backend', $Backend, '-ArgsB64', $workerArgs)
    }
    if (-not $File) { throw 'Start-Operation : ni worker ni programme.' }
    if (-not $Log) {
        $Log = Join-Path (Get-LogDir -Backend $Backend) ($Action + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    }
    $watcher = Join-Path (Join-Path $Backend 'workers') 'watched-action.worker.ps1'
    if (-not (Test-Path -LiteralPath $watcher)) { throw "Veilleur introuvable : $watcher" }
    $payload = @{ module = $Module; action = $Action; label = $Label; probes = @($Probes)
                  file = $File; arguments = @($Arguments); log = $Log }
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress -Depth 6)))
    # The previous result goes at launch: the card would otherwise show yesterday's failure during today's work.
    Clear-ModuleLastRun -Module $Module -Backend $Backend
    # Taken BEFORE the start: a watcher that ends at once writes a result dated after this, not before.
    $launchedAt = (Get-Date).ToUniversalTime().ToString('o')
    $p = $null
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $exe
        # ArgumentList, NOT Arguments: .NET quotes each value itself (D116).
        foreach ($piece in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                             '-File', $watcher, '-Backend', $Backend, '-ArgsB64', $b64)) {
            [void]$psi.ArgumentList.Add([string]$piece)
        }
        $psi.UseShellExecute  = $false
        $psi.CreateNoWindow   = $true
        $psi.WindowStyle      = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.WorkingDirectory = $Backend
        $p = [System.Diagnostics.Process]::Start($psi)
    } catch {
        # A launch that fails is a result too, and the card must be able to say it.
        Set-ModuleLastRun -Module $Module -Action $Action -Label $Label -Code -1 -Log $Log -Error $_.Exception.Message -Backend $Backend
        throw
    }
    if (-not $p) {
        Set-ModuleLastRun -Module $Module -Action $Action -Label $Label -Code -1 -Log $Log `
                          -Error (Get-Label 'common.operation-non-lancee') -Backend $Backend
        return $null
    }
    # THE MARK EXISTS BEFORE THE ANSWER. Written by the watcher once started, it arrived after the action had
    # answered, and the page took the Windows Update installation for finished (12/09).
    Set-ModuleBusyMark -Module $Module -Label $Label -ProcessId $p.Id -Action $Action -Button $Button `
                       -At $launchedAt -Log $Log -Backend $Backend
    return $p.Id
}

# THE PROTOCOL'S FAILURE, WHEN THE WORKER COULD NOT SAY IT. A card whose worker writes its own detail shows the
# last run only when that detail predates the run: a process gone, a launch refused. Otherwise the detail says it.
function New-UnreportedFailureField {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Action = '',
        $WrittenAt = $null,
        [string]$Backend = (Get-BackendRoot)
    )
    $lastRun = Get-ModuleLastRun -Module $Module -Backend $Backend
    if (-not $lastRun -or [int]$lastRun.code -eq 0) { return $null }
    if ($Action -and "$($lastRun.action)" -ne $Action) { return $null }
    $endedAt = ConvertTo-UtcDate $lastRun.at
    $written = if ($WrittenAt) { ConvertTo-UtcDate $WrittenAt } else { $null }
    if ($written -and $endedAt -and $written -ge $endedAt.AddSeconds(-[int]$lastRun.seconds - 5)) { return $null }
    return (New-LastRunField -Module $Module -Backend $Backend)
}

# The line the card shows afterwards: nothing while no work has happened, a green line when
# it succeeded, a RED line with its log when it failed.
function New-LastRunField {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Key = 'lastrun',
        [string]$Backend = (Get-BackendRoot)
    )
    $r = Get-ModuleLastRun -Module $Module -Backend $Backend
    if (-not $r) { return $null }
    $when = ''
    try { $when = Format-DateForDisplay $r.at -AssumeUtc } catch { }
    $elapsedMs = if ([int]$r.seconds -ge 60) { [string][int]([int]$r.seconds / 60) + ' min' } else { "$([int]$r.seconds) s" }
    if ([int]$r.code -eq 0) {
        # SUCCEEDED: the DATE is enough (the owner's rule of 27/08). An operation that
        # succeeded has nothing to tell on the card; the duration and the log stay available
        # in the line's detail, for whoever looks for them.
        return (New-Field -Key $Key -Label "$($r.label)" -Value $when `
                          -Kind 'text' -Status 'ok' `
                          -Help "Dernière opération lancée depuis cette carte : elle a abouti." `
                          -Guide ("Durée : " + $elapsedMs +
                                  $(if ($r.log) { [Environment]::NewLine + "Journal : " + $r.log } else { '' })))
    }
    <#
        THE VALUE SAYS THE STATE, THE DETAIL TELLS THE STORY.

        It used to carry everything: the failure, its date, and the whole sentence saying that an installation was
        already running, under which account, in which process and since when. In a card's right-hand column
        that ran to three lines and pushed the rest away, while the neighbouring lines answer
        in one word. A value is what one reads at a glance.

        So "Echec" stays on the right -- in red, nothing need be added to see it -- and WHEN,
        WHY, HOW LONG and WHERE TO READ go into the line's detail, which exists for that.
    #>
    $detail = if ($r.error) { "$($r.error)" } else { "code de sortie " + [int]$r.code }
    return (New-Field -Key $Key -Label "$($r.label)" -Value 'Échec' `
                      -Kind 'text' -Status 'error' `
                      -Help "La dernière opération lancée depuis cette carte a échoué. Elle n'a pas abouti : rien ne s'est fait à moitié sans le dire." `
                      -Guide ("Le " + $when + " — " + $detail + [Environment]::NewLine +
                              "Durée : " + $elapsedMs +
                              $(if ($r.log) { [Environment]::NewLine + "Journal complet : " + $r.log } else { '' })))
}
