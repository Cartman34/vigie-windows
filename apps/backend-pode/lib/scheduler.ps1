# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, config, log, operations, paths, probes, series, server-process, settings, store, var, watch-engine
<#
    Intent: THE SCHEDULER COMPUTES, A REQUEST NEVER DOES (D124, D125): what each card declares about its cadence, which modes slow it down, when it is due again, and the pass that goes round and recomputes what has fallen due. The ceiling on background tasks lives here too (D126).
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    THE SCHEDULER -- WHAT THE SERVER COMPUTES BY ITSELF, AND WHEN (D124).

    The watch loop reacted to a CHANGE and to nothing else. "A game is running" does not change during the game, so no
    card was recomputed and nothing was sampled: of a game of more than two hours on 28/09 the session kept four passes
    and 430 seconds, all taken while a client app happened to be alive, and it closed nine hours late. Regular sampling
    was resting on whoever was looking.

    WHAT IS SCHEDULED IS A COMPUTATION, NOT A CARD. A computation feeds the cards it declares -- several cards from one
    computation, several computations for one card -- and nothing here assumes one of each.

    EVERYTHING IS DECIDED ON ELAPSED TIME. A computation is due when the seconds since its last start exceed its
    interval. The loop's thirty-second beat is a beat, never a unit: a skipped beat shifts nothing.

    THE LIMIT IS A SETTING. RefreshMaxParallel launches run at once, three by default, zero meaning no limit. A
    computation already running is never started again unless it declares Parallel.

    A COMPUTATION THAT FAILS STEPS ASIDE. Its next attempt is pushed back, doubling at each failure up to a cap, so a
    broken computation stops being the oldest one and stops taking the place of the others.

    A COMPUTATION THAT RUNS TOO LONG IS NAMED. Past its MaxSeconds it is logged, written to the history and shown on
    the self-watch card, and it stops counting against the limit. It is never stopped: the owner alone decides that.
#>
# WHY THE LAST LAUNCH DID NOT HAPPEN: 'plafond' when the guard turned it away to protect the machine, empty
# otherwise. Read by the scheduler, which does not count a regulation as a failure.
function Get-LastChildRefusal { return "$script:LastChildRefusal" }

function Get-RefreshConfig {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = $null
    try { $cfg = (Get-Config -Backend $Backend).Refresh } catch { }
    $out = @{ MaxParallel = 3; MaxChildren = 12; RefreshReserve = 2; DefaultMaxSeconds = 300; FailBackoffSeconds = 60; FailBackoffMaxSeconds = 3600 }
    if ($cfg) {
        foreach ($k in @($out.Keys)) {
            try { if ($null -ne $cfg[$k]) { $out[$k] = [int]$cfg[$k] } } catch { }
        }
    }
    $out
}

<#
    ONE DISCOVERY FOR EVERY DECLARATION. Sentinels, modes and computations are all sections of the same module.psd1,
    read the same way, with inactive modules left out the same way. Written three times, it would drift three ways.
#>
function Get-UnitDeclarations {
    param([Parameter(Mandatory)][string]$Section, [string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    if (-not (Test-PathSafe $probesDir)) { return @() }
    $off = @(Get-InactiveUnits -Backend $Backend)
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if ($off -contains $dir.Name) { continue }
        $decl = $null
        try { $decl = Import-PowerShellDataFile -Path (Join-Path $dir.FullName 'module.psd1') } catch { }
        if (-not $decl -or -not $decl[$Section]) { continue }
        foreach ($entry in @($decl[$Section])) {
            if (-not $entry) { continue }
            $out += [pscustomobject]@{ Unit = $dir.Name; Dir = $dir.FullName; Entry = $entry }
        }
    }
    return $out
}

<#
    THE MODES. Today "in a game" and "not in a game"; tomorrow whatever a module declares -- nothing here knows about
    games. Several modes can be active at once.

    A mode reads a SENTINEL by default, and that is the DRY answer: the watch loop already reads them, their last value
    is already in memory, and a mode then costs nothing at all. A module needing its own reading declares Script
    instead, and gets a <key>.mode.ps1 read like a sentinel.
#>
$script:ModeOffValues = @('', 'non', 'no', 'aucun', 'inconnu', 'erreur', '0', 'false')

function Get-ModeDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $out = @()
    foreach ($d in @(Get-UnitDeclarations -Section 'Modes' -Backend $Backend)) {
        $key = "$($d.Entry.Key)"
        if (-not $key) { continue }
        $script = $null
        if ($d.Entry.Script) {
            $script = Join-Path $d.Dir "$($d.Entry.Script)"
            if (-not (Test-PathSafe $script)) { continue }
        }
        $off = @($script:ModeOffValues)
        if ($d.Entry.Off) { $off = @(@($d.Entry.Off) | ForEach-Object { "$_".ToLowerInvariant() }) + @('') }
        $out += [pscustomobject]@{
            Unit     = $d.Unit
            Key      = $key
            Label    = $(if ($d.Entry.Label) { "$($d.Entry.Label)" } else { $key })
            Sentinel = $(if ($d.Entry.Sentinel) { "$($d.Entry.Sentinel)" } else { $null })
            Script   = $script
            Off      = $off
        }
    }
    return $out
}

function Get-ActiveModes {
    param([string]$Backend = (Get-BackendRoot))
    $active = @()
    $memory = $null
    foreach ($m in @(Get-ModeDeclarations -Backend $Backend)) {
        $value = $null
        if ($m.Sentinel) {
            if ($null -eq $memory) {
                $memory = @{}
                try {
                    $path = Get-WatchMemoryPath -Backend $Backend
                    if (Test-PathSafe $path) {
                        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                        foreach ($pr in $j.PSObject.Properties) { $memory[$pr.Name] = "$($pr.Value.value)" }
                    }
                } catch { }
            }
            $value = "$($memory[$m.Sentinel])"
        } elseif ($m.Script) {
            try { $value = "$(& $m.Script 2>$null | Select-Object -Last 1)".Trim() } catch { $value = '' }
        }
        if ($m.Off -notcontains "$value".Trim().ToLowerInvariant()) { $active += $m.Key }
    }
    return $active
}

<#
    THE COMPUTATIONS A MODULE DECLARES.

        Refresh = @(
            @{ Key = 'gaming'; Probe = 'gaming.probe.ps1'; Cards = @('gaming')
               Seconds = @{ default = 600; game = 30 }; MaxSeconds = 60 }
        )

    Seconds holds ONE interval per mode, plus "default"; the first active mode that declares one wins. No interval at
    all means the computation only ever runs when someone asks for it -- which is what every card does today.
#>
<#
    THE ACCOUNTS WHOSE SESSION IS OPEN, by name. Their registry hive is mounted only while they are logged in, which
    is exactly the question -- and it costs nothing, where establishing the list of accounts costs two seconds.
#>
<#
    THE ACCOUNTS WITH AN OPEN SESSION -- AND NEVER THE ONE THE SERVER APP RUNS AS.

    Its hive is loaded like any other, so it was counted among them: the scheduler computed a per-account card FOR
    THE SERVICE ACCOUNT, which owns nothing a person installed and has no screen to look at one. Measured on 06/10,
    `packages.probe.ps1@VigieService` sat in the cache beside `@fhaza` and `@Famille`, holding a reading nobody would
    ever read. The owner put it plainly: the service account has no package manager, therefore no card.

    It is the one entry in this list that cannot be a reader -- the whole client-task mechanism exists because it has
    no session of its own (D113). Leaving it out is the definition, not an optimisation.
#>
function Get-OpenSessionAccounts {
    $names = @()
    $self = $null
    try { $self = [Security.Principal.WindowsIdentity]::GetCurrent().Name.Split([char]92)[-1] } catch { }
    foreach ($hive in @(Get-UserRegistryRoots)) {
        try {
            $sid = "$hive".Split([char]92)[-1]
            $name = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate(
                        [System.Security.Principal.NTAccount]).Value.Split([char]92)[-1]
            if (-not $name) { continue }
            if ($self -and $name -eq $self) { continue }
            if ($names -notcontains $name) { $names += $name }
        } catch { }
    }
    return @($names)
}

function Get-RefreshDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $out = @()
    $openAccounts = $null
    foreach ($d in @(Get-UnitDeclarations -Section 'Refresh' -Backend $Backend)) {
        $key = "$($d.Entry.Key)"
        $probe = "$($d.Entry.Probe)"
        if (-not $key -or -not $probe) { continue }
        if (-not (Test-PathSafe (Join-Path $d.Dir $probe))) { continue }
        <#
            A MEASURE THAT DEPENDS ON WHO LOOKS IS COMPUTED PER ACCOUNT (D109). The owner settled the scope on
            30/09: every account with an open session.

            The cache of such a probe holds one entry per account. The scheduler computes with no requester, so it
            was writing into its own entry -- one nobody ever reads. Measured on 30/09: the WSL card was recomputed
            every five minutes all day, and what the owner saw was 31 hours old, because his own entry was never
            touched. And since a request computes nothing (D124), it would never have been.

            One declaration per open session, then: their hive is mounted, so they are the ones who may be looking.
            Nobody logged in, nothing to compute -- and nobody to read it either.
        #>
        if (Test-ProbeIsPerAccount -ProbeFile (Join-Path $d.Dir $probe)) {
            if ($null -eq $openAccounts) { $openAccounts = @(Get-OpenSessionAccounts) }
            foreach ($account in $openAccounts) {
                $seconds = @{}
                if ($d.Entry.Seconds -is [hashtable]) {
                    foreach ($k in $d.Entry.Seconds.Keys) { $seconds["$k"] = [int]$d.Entry.Seconds[$k] }
                } elseif ($d.Entry.Seconds) { $seconds['default'] = [int]$d.Entry.Seconds }
                $out += [pscustomobject]@{
                    Unit       = $d.Unit
                    Key        = "$($d.Unit)/$key@$account"
                    Probe      = $probe
                    Account    = $account
                    Cards      = @($d.Entry.Cards)
                    Seconds    = $seconds
                    MaxSeconds = $(if ($d.Entry.MaxSeconds) { [int]$d.Entry.MaxSeconds } else { 0 })
                    Parallel   = [bool]$d.Entry.Parallel
                    OnlyWhen   = "$($d.Entry.OnlyWhen)"
                }
            }
            continue
        }
        $seconds = @{}
        if ($d.Entry.Seconds -is [hashtable]) {
            foreach ($k in $d.Entry.Seconds.Keys) { $seconds["$k"] = [int]$d.Entry.Seconds[$k] }
        } elseif ($d.Entry.Seconds) { $seconds['default'] = [int]$d.Entry.Seconds }
        $out += [pscustomobject]@{
            Unit       = $d.Unit
            Key        = "$($d.Unit)/$key"
            Probe      = $probe
            Cards      = @($d.Entry.Cards)
            Seconds    = $seconds
            MaxSeconds = $(if ($d.Entry.MaxSeconds) { [int]$d.Entry.MaxSeconds } else { 0 })
            Parallel   = [bool]$d.Entry.Parallel
            # ONLYWHEN: a computation only worth its cost in a given state. Listing the packages questions three
            # package managers for 3,7 s: once a day, and never while the machine is busy (owner, 29/09).
            OnlyWhen   = "$($d.Entry.OnlyWhen)"
        }
    }
    return $out
}

# THE INTERVAL THAT APPLIES RIGHT NOW: the first active mode that declares one, else "default", else none.
function Get-RefreshInterval {
    param([Parameter(Mandatory)]$Declaration, [string[]]$Modes = @())
    foreach ($m in @($Modes)) {
        if ($Declaration.Seconds.ContainsKey($m)) { return [int]$Declaration.Seconds[$m] }
    }
    if ($Declaration.Seconds.ContainsKey('default')) { return [int]$Declaration.Seconds['default'] }
    return 0
}

<#
    THE STAMP OF THE STATE CACHE -- how the panel learns that something was computed (D124).

    The server cannot push: it answers requests. But the panel already asks /health every fifteen seconds to see
    whether a new version is being served, and that answer costs nothing. It now carries the moment the state cache
    was last written: when it moves, the panel reads the cache again, instead of waiting for its own minute to pass.
    No new route, no new transport, and the panel still never waits for a computation -- it reads what is written.
#>
function Get-StateStamp {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
        if (-not (Test-PathSafe $path)) { return '' }
        return "$((Get-Item -LiteralPath $path -ErrorAction Stop).LastWriteTimeUtc.Ticks)"
    } catch { return '' }
}

function Get-RefreshStatePath {
    param([string]$Backend = (Get-BackendRoot))
    # 'run': a LIVING state. What is running dies with the server, and a pace starts again from the restart.
    Get-VarPath -Backend $Backend -Kind 'run' -File 'refresh.json'
}

function Get-RefreshState {
    param([string]$Backend = (Get-BackendRoot))
    $state = @{}
    try {
        $path = Get-RefreshStatePath -Backend $Backend
        if (Test-PathSafe $path) {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($pr in $j.PSObject.Properties) {
                $e = $pr.Value
                $state["$($pr.Name)"] = @{
                    pid           = [int]$e.pid
                    startedAt     = [long]$e.startedAt
                    lastStartedAt = [long]$e.lastStartedAt
                    lastEndedAt   = [long]$e.lastEndedAt
                    lastMs        = [int]$e.lastMs
                    waiting       = [bool]$e.waiting
                    fails         = [int]$e.fails
                    nextAt        = [long]$e.nextAt
                    long          = [bool]$e.long
                    lastError     = "$($e.lastError)"
                }
            }
        }
    } catch { }
    return $state
}

# ONE KEY AT A TIME, through the helper that locks the file: the workers write their own outcome while the pass writes
# its launches, and neither may lose the other's line.
function Update-RefreshState {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][hashtable]$Entry)
    try { $null = Update-StateJson -Path (Get-RefreshStatePath -Backend $Backend) -Set @{ $Key = $Entry } -Depth 6 } catch { }
}

<#
    DUE NOW. An action that changes something invalidates the cards it changed, and those cards must not then wait
    for their interval -- up to an hour for some. Invalidating therefore also tells the scheduler, which picks them
    up at its next pass, thirty seconds at most.
#>
function Reset-RefreshDue {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string[]]$Probes)
    $state = Get-RefreshState -Backend $Backend
    foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
        if ($Probes -notcontains $d.Probe) { continue }
        $entry = $state[$d.Key]
        if (-not $entry) { $entry = @{ fails = 0 } }
        $entry.lastStartedAt = 0
        $entry.nextAt = 0
        Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
    }
}

function Invoke-RefreshPass {
    param([string]$Backend = (Get-BackendRoot))
    # SILENT WHILE AN INSTALLATION RUNS, like the rest of the watch: the files move underfoot.
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return @() }
    }
    $decls = @(Get-RefreshDeclarations -Backend $Backend)
    if (-not $decls.Count) { return @() }
    $cfg = Get-RefreshConfig -Backend $Backend
    $state = Get-RefreshState -Backend $Backend
    $modes = @(Get-ActiveModes -Backend $Backend)
    $nowTicks = [datetime]::UtcNow.Ticks
    $running = 0

    # 1. WHAT IS STILL RUNNING, and what only looks like it. A process that is gone leaves its line behind; a process
    #    that overstays is named once and stops holding a place -- it is not stopped.
    foreach ($d in $decls) {
        $entry = $state[$d.Key]
        if (-not $entry -or -not [int]$entry.pid) { continue }
        $alive = $false
        try { $alive = [bool](Get-Process -Id ([int]$entry.pid) -ErrorAction Stop) } catch { }
        if (-not $alive) {
            $entry.pid = 0; $entry.long = $false
            Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
            continue
        }
        # Awake time when the entry carries it; the wall clock for an entry written by the previous version.
        $elapsed = $(if ($entry.startedTick) { ([Environment]::TickCount64 - [long]$entry.startedTick) / 1000 }
                     else { ($nowTicks - [long]$entry.startedAt) / 1e7 })
        $max = $(if ($d.MaxSeconds) { [int]$d.MaxSeconds } else { [int]$cfg.DefaultMaxSeconds })
        if ($elapsed -ge $max -and -not $entry.long) {
            $entry.long = $true
            Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
            try {
                Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                    "calcul trop long : $($d.Key), PID $($entry.pid), " + [int]$elapsed + " s (limite $max s)")
                $line = [ordered]@{ at = ([datetime]::UtcNow).ToString('o'); key = $d.Key
                                    pid = [int]$entry.pid; seconds = [int]$elapsed; max = $max }
                Add-HistoryLine -Path (Get-VarPath -Backend $Backend -Kind 'history' -File 'refresh-long.jsonl') `
                                -Line ($line | ConvertTo-Json -Depth 4 -Compress) | Out-Null
            } catch { }
        }
        # A computation past its limit no longer counts against the limit: the others must not wait for it.
        if (-not $entry.long) { $running++ }
    }

    # 2. WHAT IS DUE, on elapsed time, and never on a number of passes.
    $due = @()
    foreach ($d in $decls) {
        $entry = $state[$d.Key]
        if ($entry -and [int]$entry.pid -and -not $d.Parallel) { continue }
        $interval = Get-RefreshInterval -Declaration $d -Modes $modes
        if ($interval -le 0) { continue }
        if ($d.OnlyWhen -and ($modes -notcontains $d.OnlyWhen)) { continue }
        if ($entry -and [long]$entry.nextAt -gt $nowTicks) { continue }
        $since = [double]::MaxValue
        if ($entry -and [long]$entry.lastStartedAt) { $since = ($nowTicks - [long]$entry.lastStartedAt) / 1e7 }
        if ($since -lt $interval) { continue }
        $due += [pscustomobject]@{ D = $d; Overdue = $since - $interval }
    }

    <#
        3. THE MOST OVERDUE FIRST, up to the limit -- AND A TIE IS BROKEN, NEVER LEFT TO CHANCE.

        A computation that has never run has no last start, so its lateness is infinite. On a fresh state that is
        true of EVERY declaration at once, and Sort-Object gives no order to equal values: three were picked out of
        fifteen, arbitrarily, and the same ones kept being picked. Measured on 30/09, on this computer: the two
        computations of the Debogage module had NEVER been started since the scheduler exists -- no entry, no
        failure, nothing to see. Their cards had been showing a measure 29 hours and 10 days old, as if fresh.

        The key breaks the tie. It is stable, it is ours, and after one pass every declaration has a real timestamp,
        so the order goes back to being decided by lateness alone.
    #>
    $started = @()
    foreach ($item in @($due | Sort-Object @{ Expression = { $_.Overdue }; Descending = $true },
                                            @{ Expression = { $_.D.Key };  Descending = $false })) {
        if ([int]$cfg.MaxParallel -gt 0 -and $running -ge [int]$cfg.MaxParallel) { break }
        $d = $item.D
        # NOT $pid: PowerShell owns that name and refuses to have it written to.
        $childPid = $null
        try {
            $childPid = Start-DetachedAction -Backend $Backend `
                        -Script (Join-Path $Backend 'workers/refresh.worker.ps1') `
                        -ArgsMap @{ key = $d.Key; probe = $d.Probe; account = "$($d.Account)" }
        } catch { }
        <#
            A REFUSED LAUNCH IS A FAILURE OF THE COMPUTATION, and it is counted as one.

            It used to be a bare "continue": nothing written, no entry, no failure, no trace. The card then froze for
            ever while the state stayed silent -- and, worse, a computation that has never started is the latest of
            all, so it came back first at every pass and was refused again. A silent refusal that repeats for ever is
            the shape this very scheduler was written to prevent (D125).

            Counted as a failure, it takes the doubling delay like the others: it stops being the oldest, it stops
            holding the first place, and the card says it.
        #>
        if (-not $childPid) {
            # DEFERRED IS NOT FAILED. The ceiling protects the machine; the calculation simply waits for the next
            # pass, with no doubling delay and no failure counted against it.
            if ((Get-LastChildRefusal) -eq 'plafond') { continue }
            $entry = $state[$d.Key]
            if (-not $entry) { $entry = @{ fails = 0 } }
            $cfgFail = Get-RefreshConfig -Backend $Backend
            $entry.fails = [int]$entry.fails + 1
            $wait = [Math]::Min([int]$cfgFail.FailBackoffSeconds * [Math]::Pow(2, [int]$entry.fails - 1), [int]$cfgFail.FailBackoffMaxSeconds)
            $entry.nextAt = [datetime]::UtcNow.AddSeconds($wait).Ticks
            $entry.lastError = 'le lancement a été refusé (plafond de tâches de fond, ou démarrage impossible)'
            $state[$d.Key] = $entry
            Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
            try {
                Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (
                    "planifie : " + $d.Key + " n'a pas pu demarrer (" + $entry.fails + ") ; prochaine tentative dans " + [int]$wait + " s")
            } catch { }
            continue
        }
        $entry = $state[$d.Key]
        if (-not $entry) { $entry = @{ fails = 0 } }
        $entry.pid = [int]$childPid
        $entry.startedAt = $nowTicks
        # THE CLOCK ON THE WALL SAYS WHEN, THE COUNTER SAYS HOW LONG. A computation started before the machine
        # went to sleep and finished after it woke up was credited with the whole night: 34 722 332 ms read on
        # 16/10 for a card that had worked a few seconds. This counter does not advance while the machine sleeps.
        $entry.startedTick = [Environment]::TickCount64
        $entry.lastStartedAt = $nowTicks
        $entry.long = $false
        $state[$d.Key] = $entry
        Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
        $started += $d.Key
        $running++
    }
    return $started
}

<#
    WHAT THE SCHEDULER HAS TO SAY, read by the self-watch card -- which only reads, never acts (D14).
#>
function Get-RefreshRows {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = Get-RefreshConfig -Backend $Backend
    $state = Get-RefreshState -Backend $Backend
    $modes = @(Get-ActiveModes -Backend $Backend)
    $nowTicks = [datetime]::UtcNow.Ticks
    $rows = @()
    foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
        $entry = $state[$d.Key]
        $interval = Get-RefreshInterval -Declaration $d -Modes $modes
        $said = $(if ($interval -gt 0) { "toutes les $interval s" } else { 'à la demande' })
        $status = 'ok'
        if ($entry -and [int]$entry.pid) {
            $elapsed = [int]$(if ($entry.startedTick) { ([Environment]::TickCount64 - [long]$entry.startedTick) / 1000 }
                               else { ($nowTicks - [long]$entry.startedAt) / 1e7 })
            $said = "en cours depuis $elapsed s"
            if ($entry.long) { $said = "TROP LONG : $elapsed s"; $status = 'warn' }
        } elseif ($entry -and $entry.waiting) {
            # WAITING IS NOT FAILING, and the card must not say the second when it is the first: without a living
            # client app, a measure that belongs to an account cannot be computed, and nothing is broken.
            $said = "$($entry.lastError)"
            $status = 'neutral'
        } elseif ($entry -and [int]$entry.fails) {
            $said = "$($entry.fails) échec(s) : $($entry.lastError)"
            $status = 'warn'
        }
        $rows += [pscustomobject]@{
            Key    = $d.Key
            Said   = $said
            Status = $status
            Ms     = $(if ($entry) { [int]$entry.lastMs } else { 0 })
            At     = $(if ($entry -and [long]$entry.lastEndedAt) { [datetime]([long]$entry.lastEndedAt) } else { $null })
        }
    }
    return $rows
}
