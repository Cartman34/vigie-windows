# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: client-app, config, format, log, measures, operations, packages, paths, scheduler, settings, state, store, var
<#
    Intent: CHEAP READINGS, AND AN EVENT WHEN THE VALUE CHANGES: not recomputing cards in a loop. A module declares one reading and one comparable value; when it changes, the cards that module named are recomputed.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# The LOCAL DNS PROXY, if there is one: the Windows service whose process listens on port
# 53. Detected by BEHAVIOUR rather than by name -- Acrylic today, anything else tomorrow,
# and null when there is none.
function Get-LocalDnsProxyService {
    try {
        $owner = Get-UdpEndpointOwner -Port 53
        if (-not $owner) { return $null }
        $svc = Get-ServiceByProcessId -ProcessId $owner
        if ($svc) { return [pscustomobject]@{ Name = $svc.Name; DisplayName = $svc.DisplayName; Pid = $owner } }
    } catch { }
    return $null
}

function Get-WatchDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    if (-not (Test-PathSafe $probesDir)) { return @() }
    $off = @(Get-InactiveUnits -Backend $Backend)
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if ($off -contains $dir.Name) { continue }
        $decl = $null
        try { $decl = Import-PowerShellDataFile -Path (Join-Path $dir.FullName 'module.psd1') } catch { }
        if (-not $decl -or -not $decl.Sentinels) { continue }
        foreach ($v in @($decl.Sentinels)) {
            if (-not $v.Key) { continue }
            $script = Join-Path $dir.FullName ("$($v.Key).watch.ps1")
            if (-not (Test-PathSafe $script)) { continue }
            $out += [pscustomobject]@{
                Unit     = $dir.Name
                Key      = "$($v.Key)"
                Label    = $(if ($v.Label) { "$($v.Label)" } else { "$($v.Key)" })
                Seconds  = $(if ($v.Seconds) { [int]$v.Seconds } else { 900 })
                Cards    = @($v.Cards)
                Script   = $script
            }
        }
    }
    return $out
}

# WHERE THE LAST READING IS KEPT. A file, beside the state cache: it is neither a
# measurement to expose nor a setting -- it is the loop's own memory.
function Get-WatchMemoryPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'watch.json'
}

<#
    WHAT EACH APPLICATION TOOK DURING A GAME, AND FOR HOW LONG.

    A card shows an instant. "Chrome at 12 %" says nothing about a session: it may have been a spike between two
    loading screens, or an hour of theft. On 16/09 the greedy-application alert went out fourteen times, and the
    owner recognised the window compositor -- a process that cannot be the culprit, since it draws the game itself.
    The threshold was one percent of the processor, all cores together, read over nine hundred milliseconds.

    So the session keeps a TALLY, not a stream: one entry per application, updated at each pass -- how many passes it
    was seen, the sum of its shares, its peaks, its first and last sighting. Its weight never grows with the length of
    the game. When the game ends, the tally becomes a summary, and the card can say: "during your session of 1 h 35,
    the window compositor held 10 % of the processor for 1 h 04".

    Nothing here measures anything: the gaming card has already measured, this only accumulates.
#>


# One history line for a sentinel: the state reached, the one it came from, and the cards the
# change had recomputed. Best effort from end to end: the watch OBSERVES, it does not
# arbitrate -- a failed write must never stop a recomputation from starting.
function Write-SentinelSample {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key,
        [string]$From,
        [Parameter(Mandatory)][string]$To,
        [string[]]$Cards = @()
    )
    try {
        $cfg = Get-Config -Backend $Backend
        if (-not (Get-HistoryConfig -Backend $Backend -Config $cfg).Enabled) { return }
        $id = Get-SentinelMeasureId -Key $Key
        if (-not (Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg).Enabled) { return }
        $obj = [ordered]@{ at = ([datetime]::UtcNow).ToString('o'); v = $To }
        if ($From) { $obj.from = $From }
        if ($Cards.Count) { $obj.cards = @($Cards) }
        # A sentinel already writes ONLY on a change: no heartbeat here, and a flat series of
        # events is not a gap, it is an absence of events.
        $null = Write-HistoryPoint -Backend $Backend -MeasureId $id -Point $obj
    } catch { }
}

<#
    WHEN THE DISK EMPTIES FAST, VIGIE LOOKS BY ITSELF.

    The storage card can say where the space went, but only if someone presses the button. On 28/09 the disk went from
    112 GB free to 28 GB without anyone watching, and the answer -- 49,7 GB of debug traces and a virtual disk that
    never gives anything back -- was found by hand, days later.

    THE TRIGGER IS A FALL, NOT A LEVEL. A disk that has been at 30 GB for a year has nothing to explain; one that has
    just lost ten of them in a day does. The history of disk.free already holds what is needed, sampled every thirty
    minutes, and reading it costs a file.

    WHAT HOLDS IT BACK, and each of these was asked for: at most one automatic analysis a day, none while a mode says
    the machine is busy for its owner -- a game --, and none while anything else is already using the machine. The
    analysis itself is the one the button launches, with its own protection against running twice.
#>
<#
    HOW MANY GIGABYTES THE DISK HAS LOST over a window: the highest point of the window against the latest one, read
    from the history that is already sampled every thirty minutes. Separate from the decision that uses it, so the
    decision can be read -- and the reading tested -- without anything being started.

    $null when the history cannot answer: fewer than two points is not "no fall", it is "we do not know".
#>
function Get-DiskFreeFall {
    param([string]$Backend = (Get-BackendRoot), [int]$Hours = 24)
    $history = $null
    try { $history = Get-MeasureHistory -Backend $Backend -MeasureId 'disk.free' -Window ([TimeSpan]::FromHours($Hours)) } catch { }
    if (-not $history) { return $null }
    $values = @(@($history.points) | ForEach-Object { [double]$_.v })
    if ($values.Count -lt 2) { return $null }
    return (($values | Measure-Object -Maximum).Maximum - $values[-1])
}

<#
    WHAT WSL REALLY HOLDS, ASKED TO A CLIENT APP (SYS-DISK).

    A virtual disk never gives back what is freed inside it: 150,7 GB on C: on 28/09, for far less content. Only a
    reading made INSIDE the distribution can tell the difference, and the server app has none -- it runs under a
    service account, where WSL does not exist.

    So the server asks. It writes an order in the account's run folder and the client app runs it in its session, the
    mechanism that already serves every action needing a session (Invoke-ClientTask). The answer is kept for an
    hour: a virtual disk does not change size in a minute, and nobody is ever made to wait for it -- the card reads
    what is written, or says nothing about it.
#>
function Get-WslUsagePath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'wsl-usage.json'
}

function Get-WslUsage {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-WslUsagePath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return $null }
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $j -or -not $j.distributions) { return $null }
        return $j
    } catch { return $null }
}

function Update-WslUsage {
    param([string]$Backend = (Get-BackendRoot), [int]$EveryMinutes = 60)
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    $path = Get-WslUsagePath -Backend $Backend
    <#
        THE GATE IS READ IN TICKS, and it is the third time today that this matters: ConvertFrom-Json turns an ISO
        date back into a [datetime], whose string form is then local and no longer parses (D44). Read as text, the
        gate never held and a client app was asked every thirty seconds instead of every hour -- seen in its log.
    #>
    try {
        if (Test-PathSafe $path) {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $ticks = [long]$j.atTicks
            if ($ticks -and ([datetime]::UtcNow - [datetime]$ticks).TotalMinutes -lt $EveryMinutes) { return $null }
        }
    } catch { }
    # A CLIENT APP THAT BEATS, and nothing else: an account with no session has no WSL to look at either.
    $account = @(Get-ClientWatchRows -Backend $Backend | Where-Object { $_.Status -eq 'ok' } | Select-Object -First 1)
    if (-not $account.Count) { return $null }
    $answer = $null
    try { $answer = Invoke-ClientTask -Account "$($account[0].Account)" -Type 'wsl-usage' -Module 'wsl' -TimeoutSec 20 -Backend $Backend } catch { }
    if (-not $answer -or -not $answer.result -or -not $answer.result.ok) { return $null }
    $entry = [ordered]@{
        at            = ([datetime]::UtcNow).ToString('o')
        atTicks       = ([datetime]::UtcNow).Ticks
        account       = "$($account[0].Account)"
        distributions = @($answer.result.distributions)
    }
    try { Set-Content -LiteralPath $path -Value ($entry | ConvertTo-Json -Depth 6 -Compress) -Encoding UTF8 } catch { }
    return $entry
}

function Invoke-DiskWatch {
    param([string]$Backend = (Get-BackendRoot))
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    # NOT WHILE HE IS PLAYING: an analysis walks the whole disk, and that is felt.
    if (@(Get-ActiveModes -Backend $Backend).Count) { return $null }

    $dropGb = 10.0
    $minHours = 24
    try { $dropGb = [double](Get-ModuleSetting -Unit 'system' -Key 'AutoScanDropGb' -Backend $Backend) } catch { }
    try { $minHours = [int](Get-ModuleSetting -Unit 'system' -Key 'AutoScanMinHours' -Backend $Backend) } catch { }
    if ($dropGb -le 0) { return $null }

    $statePath = Get-VarPath -Backend $Backend -Kind 'cache' -File 'disk-watch.json'
    $lastTicks = 0
    try {
        if (Test-PathSafe $statePath) {
            $j = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $lastTicks = [long]$j.lastAt
        }
    } catch { }
    $nowUtc = [datetime]::UtcNow
    if ($lastTicks -and ($nowUtc - [datetime]$lastTicks).TotalHours -lt $minHours) { return $null }

    $fall = Get-DiskFreeFall -Backend $Backend -Hours $minHours
    if ($null -eq $fall -or $fall -lt $dropGb) { return $null }

    $fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $depth = 3; $top = 10
    try { $depth = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanDepth' -Backend $Backend) } catch { }
    try { $top = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanTop' -Backend $Backend) } catch { }
    if (-not $depth) { $depth = 3 }
    if (-not $top) { $top = 10 }
    $started = $false
    try {
        $started = [bool](Start-Operation -Module 'storage' -Action 'disk-analyze' -Label 'Analyse automatique du disque' `
                              -Probes @('disk.probe.ps1') -Worker 'disk-scan.worker.ps1' `
                              -ArgsMap @{ root = 'C:\'; depth = $depth; top = $top } -Backend $Backend)
    } catch { }
    # THE DATE IS WRITTEN EVEN IF THE START FAILED: otherwise a refusal would be retried every thirty seconds.
    try { Set-Content -LiteralPath $statePath -Value (@{ lastAt = $nowUtc.Ticks; fall = $fall; started = $started } | ConvertTo-Json -Compress) -Encoding UTF8 } catch { }
    try {
        Write-Log -Backend $Backend -Name 'state' -Level $(if ($started) { 'INFO' } else { 'WARN' }) -Message (
            "chute d'espace : " + $fall.ToString('N1', $fr) + " Go en " + $minHours + " h, seuil " +
            $dropGb.ToString('N1', $fr) + " Go -- analyse " + $(if ($started) { 'lancee' } else { 'non lancee' }))
    } catch { }
    if (-not $started) { return $null }
    return [pscustomobject]@{ FallGb = $fall; At = $nowUtc }
}

<#
    THE VERDICT ON A FACT THAT COMES FROM A LOG (D127) -- written once, for every card that reads one.

    The log says what HAPPENED; a card says what IS. Three things decide, in this order:

      1. THE MEASURE OF THE MOMENT, when the kind can be checked: it confirms, it denies, or nothing can check it.
         What is confirmed weighs whatever its age; what is denied never weighs.
      2. THE AGE, past which the fact is DECLASSED. Declassed does not mean gone (owner, 30/09): the line stays where
         it was, with its state and its figures, and only stops carrying the card's status.
      3. THE RECURRENCE, which is itself a fact of today. "Three times in seven days" is not an accident, and a line
         that says it teaches more than a line that hides it -- so it is said, always, as soon as there is more than
         one.

    Returns Said (what the line reads), Weight ('ok' when it no longer carries the card) and Recurrence.
#>
function Get-JournalFactVerdict {
    param(
        [Parameter(Mandatory)][datetime]$LastAt,
        [int]$Count = 1,
        [int]$WindowDays = 0,
        # 'en cours', 'termine', 'passe' (a past fact by nature) or 'inconnu'.
        [string]$Still = 'inconnu',
        [string]$Level = 'warn',
        [int]$HighlightMinutes = 60
    )
    $minutes = [int][math]::Floor(((Get-Date) - $LastAt).TotalMinutes)
    if ($minutes -lt 0) { $minutes = 0 }
    $recent = ($HighlightMinutes -le 0 -or $minutes -lt $HighlightMinutes)
    $ago = if ($minutes -lt 60) { "il y a $minutes min" }
           elseif ($minutes -lt 2880) { 'il y a ' + [int][math]::Floor($minutes / 60) + ' h' }
           else { 'il y a ' + [int][math]::Floor($minutes / 1440) + ' j' }
    $recurrence = if ($Count -ge 2 -and $WindowDays -gt 0) {
                      "$Count fois en " + $WindowDays + $(if ($WindowDays -gt 1) { ' jours' } else { ' jour' }) + ", la dernière $ago"
                  } elseif ($Count -ge 2) { "$Count fois, la dernière $ago" } else { $ago }
    $said = switch ($Still) {
        'en cours' { 'en cours' }
        'termine'  { "ce n'est plus le cas" }
        'passe'    { 'arrivé' }
        default    { $(if ($recent) { "on ne sait pas si c'est encore le cas" } else { 'arrivé' }) }
    }
    $weight = if ($Still -eq 'en cours') { $Level }
              elseif ($Still -eq 'termine') { 'ok' }
              elseif ($recent) { $Level }
              else { 'ok' }
    return [pscustomobject]@{ Said = $said; Weight = $weight; Recurrence = $recurrence; Recent = $recent; Minutes = $minutes }
}

<#
    THE EPHEMERAL RANGE OF BOTH PROTOCOLS, READ ONCE AN HOUR AND AFTER EACH START OF WINDOWS.

    Get-EphemeralPortRange runs netsh, which is a process to start: 200 ms per protocol, measured, against 3 ms for
    reading the ports in use. Asking it at every pass of the watch would make the range cost a hundred times what it
    guards. It changes at a setting or a restart, so an hour is generous.

    This was written inside net.probe.ps1 and is now shared with the port watch: one reading, one definition (D15).
#>
function Get-EphemeralPortRanges {
    param([string]$Backend = (Get-BackendRoot))
    $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'dynamic-ports.json'
    $nowT = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $bootAt = $nowT - [long]([Environment]::TickCount64 / 1000)
    $ranges = $null
    if (Test-PathSafe $file) { try { $ranges = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    if ($ranges -and $ranges.tcp -and $ranges.udp -and
        [math]::Abs([long]$ranges.bootAt - $bootAt) -le 120 -and ($nowT - [long]$ranges.readAt) -le 3600) {
        return $ranges
    }
    $tcp = Get-EphemeralPortRange -Protocol 'tcp'
    $udp = Get-EphemeralPortRange -Protocol 'udp'
    if (-not $tcp -or -not $udp) { return $ranges }
    try { $null = Update-StateJson -Path $file -Set @{ bootAt = $bootAt; readAt = $nowT; tcp = $tcp; udp = $udp } } catch { }
    return [pscustomobject]@{ bootAt = $bootAt; readAt = $nowT; tcp = [pscustomobject]$tcp; udp = [pscustomobject]$udp }
}

<#
    THE EPHEMERAL PORTS, WATCHED WHERE THEY EMPTY -- and written only when there is something to read.

    Why: Windows logs "all ephemeral ports are in use" (Tcpip 4231/4266) 75 times since 25/07 on this computer, and
    two identical events are never closer than six hours -- it suppresses the repeats, so the count is a floor, not a
    total. By the time anyone reads the card, the reserve is back to 1 % and the table names processes that had
    nothing to do with it. The card's advice -- close the one holding the most -- was therefore unusable.

    What this does: READS at every pass, which costs 2,8 ms measured for TCP and UDP together, and WRITES only when
    the occupancy reaches PortWatchPercent, or during the PortWatchAfterMinutes that follow one of those events.
    While the reserve is idle, not one line is written: a point every thirty seconds saying "1 %" teaches no one
    anything and fills the disk of the machine whose disk we watch.

    The event log is re-read at most every five minutes, and the answer kept: Get-WinEvent costs far more than the
    port reading it guards, so asking it thirty times a minute would cost more than the whole watch.
#>
function Invoke-PortWatch {
    param([string]$Backend = (Get-BackendRoot))
    $percent = 50
    $afterMin = 15
    try { $percent = [int](Get-ModuleSetting -Unit 'network' -Key 'PortWatchPercent' -Backend $Backend) } catch { }
    try { $afterMin = [int](Get-ModuleSetting -Unit 'network' -Key 'PortWatchAfterMinutes' -Backend $Backend) } catch { }

    $ranges = $null
    try { $ranges = Get-EphemeralPortRanges -Backend $Backend } catch { }
    if (-not $ranges -or -not $ranges.tcp -or -not $ranges.udp) { return $null }
    $usage = @{}
    $worst = 0
    foreach ($proto in 'tcp', 'udp') {
        $range = $ranges.$proto
        $u = $null
        try { $u = Get-EphemeralPortUsage -Protocol $proto -Start ([int]$range.Start) -Count ([int]$range.Count) } catch { }
        if (-not $u -or $u.Limit -le 0) { continue }
        $usage[$proto] = $u
        $pct = [int][math]::Round(100.0 * $u.Used / $u.Limit)
        if ($pct -gt $worst) { $worst = $pct }
    }
    if (-not $usage.Count) { return $null }

    # THE LAST COMPLAINT OF WINDOWS, asked at most every five minutes and kept in between.
    $statePath = Get-VarPath -Backend $Backend -Kind 'cache' -File 'port-watch.json'
    $nowUtc = [datetime]::UtcNow
    $askedTicks = 0
    $eventTicks = 0
    try {
        if (Test-PathSafe $statePath) {
            $j = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $askedTicks = [long]$j.askedAt
            $eventTicks = [long]$j.eventAt
        }
    } catch { }
    if ($afterMin -gt 0 -and (-not $askedTicks -or ($nowUtc - [datetime]$askedTicks).TotalMinutes -ge 5)) {
        try {
            $last = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Tcpip'; Id = 4231, 4266
                                                       StartTime = $nowUtc.ToLocalTime().AddMinutes(-($afterMin + 10)) } -ErrorAction Stop |
                      Sort-Object TimeCreated -Descending | Select-Object -First 1)
            if ($last.Count) { $eventTicks = $last[0].TimeCreated.ToUniversalTime().Ticks }
        } catch { }
        $askedTicks = $nowUtc.Ticks
        try { $null = Update-StateJson -Path $statePath -Set @{ askedAt = $askedTicks; eventAt = $eventTicks } } catch { }
    }
    $afterComplaint = ($afterMin -gt 0 -and $eventTicks -and ($nowUtc - [datetime]$eventTicks).TotalMinutes -le $afterMin)

    # NOTHING TO SAY: the reserve is idle and Windows has not complained. We read, we keep nothing.
    if (-not $afterComplaint -and ($percent -ge 100 -or $worst -lt $percent)) { return $null }

    <#
        AND HERE, AND ONLY HERE, THE COMPLETE READING -- the one that costs.

        The cheap gauge above comes from GetExtendedTcpTable, which lists the CONNECTIONS. A socket merely BOUND to a
        port -- bind() called, neither listening nor connected -- holds that port and appears in none of those tables.
        Measured on 30/09: 128 counted against 381 distinct ephemeral ports really held, 335 of them bound. The
        difference is not noise, it is the whole phenomenon: WSL's network host alone held 244 bound ports that Vigie
        could not see, while the card announced 1 %.

        Get-NetTCPConnection does see them, and costs 1,5 s -- fifty times the cheap reading. It is therefore taken
        only when we have decided there is something to write: at the threshold, or in the minutes that follow a
        complaint from Windows. The rest of the time nobody pays for it.
    #>
    $boundTop = @()
    $distinct = 0
    $held = $null
    try { $held = Get-HeldEphemeralPorts -Start ([int]$ranges.tcp.Start) } catch { }
    if ($held) {
        $distinct = [int]$held.Held
        foreach ($o in @($held.ByProcess | Select-Object -First 5)) {
            $pn = "$((Get-Process -Id $o.ProcessId -ErrorAction SilentlyContinue).ProcessName)"
            if (-not $pn) { $pn = "pid $($o.ProcessId)" }
            $boundTop += @{ n = $pn; pid = [int]$o.ProcessId; c = [int]$o.Count; s = "$($o.States)" }
        }
    }

    $point = [ordered]@{ t = $nowUtc.ToString('o'); v = $worst; why = $(if ($afterComplaint) { 'plainte' } else { 'seuil' }) }
    if ($distinct) { $point.held = $distinct; $point.holders = $boundTop }
    foreach ($proto in 'tcp', 'udp') {
        if (-not $usage[$proto]) { continue }
        $holders = @()
        foreach ($o in @($usage[$proto].ByProcess | Select-Object -First 5)) {
            $name = if ($o.ProcessId -eq 0) { 'TIME_WAIT' } else {
                $pn = "$((Get-Process -Id $o.ProcessId -ErrorAction SilentlyContinue).ProcessName)"
                if (-not $pn) { $pn = "pid $($o.ProcessId)" }
                $pn
            }
            $holders += @{ n = $name; pid = [int]$o.ProcessId; c = [int]$o.Count }
        }
        $point[$proto] = @{ used = [int]$usage[$proto].Used; limit = [int]$usage[$proto].Limit; top = $holders }
    }
    try { $null = Write-HistoryPoint -Backend $Backend -MeasureId 'net.ports' -Point ([pscustomobject]$point) } catch { }
    return [pscustomobject]@{ Percent = $worst; AfterComplaint = $afterComplaint }
}

<#
    WATCH TASKS: WHAT THE SERVER APP DOES BY ITSELF, SEEN LIKE EVERYTHING ELSE.

    Every thirty seconds the server app does seven jobs nobody asked for: reading the sentinels, launching the card
    computations that are due, looking at free disk space, questioning WSL, sampling the ports. None of them showed
    anywhere. If one hung, nothing said so, and the cards it feeds aged in silence -- on 06/10 it took digging
    through logs an ordinary session cannot even open to learn why a card stayed grey.

    CORE-OPERATIONS required it from the start: EVERY operation of Vigie is seen while it lasts. So this was a
    defect, not an improvement -- and the design page had written the opposite.

    THE MECHANISM ALREADY EXISTS and is not doubled: a mark set before, a result written after, /operations serving
    both. A watch task enters it under the reserved module `veille`. Nothing new: no file, no route, no reader.

    WHAT IT COSTS: eight writes of 150 bytes per thirty-second round, 23 000 a day. Measured rather than assumed:
    4 KB per write, 92 MB a day, 34 GB a year -- one hundredth of a percent of an ordinary disk's endurance. The
    price is negligible, and it is the minimum: with no mark there is nothing to look at.

    Full design: doc/progress/targeting/operations.md, in the section on the design that was settled.
#>
function Invoke-WatchCycle {
    param([Parameter(Mandatory)][scriptblock]$Body, [string]$Backend = (Get-BackendRoot))
    # THE ROUND CARRIES A CEILING OF ITS OWN, wider than the sum of theirs: a round that passes it is stuck
    # somewhere, even if no single task declared itself.
    Set-ModuleBusyMark -Module 'veille' -Label (Get-Label 'common.veille-tour') -ProcessId $PID `
                       -Action 'watch-cycle' -Resources @() -MaxSeconds 180 -Backend $Backend
    try { & $Body }
    finally { Clear-ModuleBusyMark -Module 'veille' -Backend $Backend }
}

<#
    ONE WATCH TASK, WRAPPED.

    The body knows nothing of the mark: it measures, it computes, it returns. The wrapper sets, judges and reports.
    Adding a task tomorrow means wrapping it in this function, and nothing else.

    An overrun is written ONCE per occurrence, as an operation result: it then shows among the recent results
    whatever card is switched on, and the card about Vigie's own processes picks it up so the bubble leaves --
    every error reaches the user, a rule the owner restated on 07/10.
#>
function Invoke-WatchTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][int]$MaxSeconds,
        [Parameter(Mandatory)][scriptblock]$Body,
        [string]$Backend = (Get-BackendRoot)
    )
    Set-ModuleBusyMark -Module 'veille' -Label $Label -ProcessId $PID -Action ('watch:' + $Name) `
                       -Resources @() -MaxSeconds $MaxSeconds -Backend $Backend
    $t0 = Get-Date
    try { & $Body }
    finally {
        $seconds = [int]((Get-Date) - $t0).TotalSeconds
        if ($seconds -gt $MaxSeconds) {
            try {
                Set-ModuleLastRun -Module 'veille' -Action ('watch:' + $Name) -Label $Label -Code 1 `
                                  -Seconds $seconds -Error (Get-Label 'common.veille-trop-longue' $MaxSeconds) -Backend $Backend
                Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' `
                          -Message (Get-Label 'common.veille-depassement' $Name $seconds $MaxSeconds)
            } catch { }
        }
    }
}

function Invoke-WatchPass {
    param([string]$Backend = (Get-BackendRoot))
    <#
        SILENT WHILE AN INSTALLATION RUNS -- the target said so, the code did not.

        An update replaces the files under the watch's feet and restarts the server: the
        resident is not armed yet, so the game sentinel reads "inconnu", then "aucun" a
        minute later. Two alerts, on every single deployment, describing nothing but our own
        work -- measured on 03/09 at 09:39 and 09:40. An alert series that fills up with the
        deployments teaches its reader to ignore it.

        The lock already exists and already says it: an installation holds the resource
        'machine'. We ask it, and we say nothing at all -- no reading, no memory write, no
        event. What the pass would have seen is not lost: it is read at the next pass, once
        the machine belongs to us again.
    #>
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    $memoryPath = Get-WatchMemoryPath -Backend $Backend
    $memory = @{}
    if (Test-PathSafe $memoryPath) {
        try { $j = Get-Content $memoryPath -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $memory[$p.Name] = $p.Value } } catch { }
    }
    $now = [datetime]::UtcNow
    $events = @()
    $toRecompute = @()
    $changed = $false

    foreach ($w in @(Get-WatchDeclarations -Backend $Backend)) {
        $known = $memory[$w.Key]
        $due = $true
        if ($known -and $known.at) {
            try { $due = ($now - (ConvertTo-UtcDate $known.at)).TotalSeconds -ge $w.Seconds } catch { }
        }
        if (-not $due) { continue }

        $value = $null
        try { $value = "$(& $w.Script 2>$null | Select-Object -Last 1)".Trim() }
        catch {
            # A READING THAT FAILS IS A VALUE LIKE ANY OTHER: "we do not know" is a state,
            # and its appearance deserves an event as much as any other change.
            #
            # BUT THE VALUE STAYS "erreur", WITHOUT THE MESSAGE. A message often carries a
            # delay, a time or an identifier: it changes at every pass, every pass then
            # passes for a change, and a breakdown that lasts writes one history line a
            # minute -- thousands of lines all saying the same thing. The detail goes to the
            # log, where it costs nothing and where it is looked for when needed.
            $value = 'erreur'
            try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -NoEcho `
                            -Message ("veille : " + $w.Key + " a echoue -- " + $_.Exception.Message) } catch { }
        }

        $before = $(if ($known) { "$($known.value)" } else { $null })
        $memory[$w.Key] = @{ value = $value; at = $now.ToString('o') }
        $changed = $true
        # A READING THAT CHANGES MAKES A LINE OF HISTORY. The watch's memory keeps only the
        # last state -- it answers "where are we?", never "since when?" nor "how many times
        # tonight?". The history keeps the succession of states AND what each one triggered:
        # it is the trace of the alert.
        # The very first reading is written down too, or the series begins in a void.
        if ($null -eq $before -or $before -ne $value) {
            Write-SentinelSample -Backend $Backend -Key $w.Key -From $before -To $value -Cards @($w.Cards)
        }
        if ($null -ne $before -and $before -ne $value) {
            $events += [pscustomobject]@{ Key = $w.Key; Label = $w.Label; From = $before; To = $value; Cards = @($w.Cards) }
            $toRecompute += @($w.Cards)
        }
    }

    if ($changed) {
        try {
            $tmp = "$memoryPath.tmp"
            ($memory | ConvertTo-Json -Depth 6) | Out-File -FilePath $tmp -Encoding UTF8
            Move-Item -Path $tmp -Destination $memoryPath -Force
        } catch { }
    }

    foreach ($e in $events) {
        Write-Log -Backend $Backend -Name 'state' -NoEcho `
                  -Message ("veille : " + $e.Label + " passe de « " + $e.From + " » a « " + $e.To + " »")
    }

    # THE CARDS NAMED, THROUGH THE EXISTING PATH. We aim at the PROBES of the card's folder:
    # the same resolution a card's button uses.
    <#
        A SENTINEL THAT CHANGED ASKS, IT DOES NOT COMPUTE. Computing here held the watch loop for as long as the card
        took -- thirteen seconds for the deployment one -- while the scheduler, one line below, is made for exactly
        this. The card is marked due and taken at this very pass.
    #>
    $cards = @($toRecompute | Where-Object { $_ } | Select-Object -Unique)
    foreach ($card in $cards) {
        $probes = @()
        foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
            if (@($d.Cards) -contains $card) { $probes += $d.Probe }
        }
        if ($probes.Count) { try { Reset-RefreshDue -Backend $Backend -Probes $probes } catch { } }
        else { try { $null = Get-State -Backend $Backend -ForceModule $card -WaitSeconds 30 } catch { } }
    }
    # AND THE SCHEDULER'S PASS (D124): a change is not the only reason to compute. What must be sampled is sampled
    # because the server watches, not because someone is looking.
    Invoke-WatchTask -Name 'scheduler' -Label (Get-Label 'common.veille-ordonnanceur') -MaxSeconds 10 -Backend $Backend -Body {
        try { $null = Invoke-RefreshPass -Backend $Backend } catch { }
    }
    # AND THE DISK, when it empties faster than anyone would notice.
    Invoke-WatchTask -Name 'disk' -Label (Get-Label 'common.veille-disque') -MaxSeconds 5 -Backend $Backend -Body {
        try { $null = Invoke-DiskWatch -Backend $Backend } catch { }
    }
    # AND WHAT WSL HOLDS INSIDE, which only a session can see.
    Invoke-WatchTask -Name 'wsl' -Label (Get-Label 'common.veille-wsl') -MaxSeconds 25 -Backend $Backend -Body {
        try { $null = Update-WslUsage -Backend $Backend } catch { }
    }
    # AND WHICH PACKAGE MANAGERS EACH ACCOUNT HAS, for the same reason: one installed in a profile is invisible from
    # the service account, and winget was missing from the panel until 05/10 for exactly that.
    Invoke-WatchTask -Name 'packages' -Label (Get-Label 'common.veille-paquets') -MaxSeconds 65 -Backend $Backend -Body {
        try { $null = Update-PkgInventory -Backend $Backend } catch { }
    }
    # AND THE EPHEMERAL PORTS, read every pass, written only when they fill or right after Windows complains.
    Invoke-WatchTask -Name 'ports' -Label (Get-Label 'common.veille-ports') -MaxSeconds 5 -Backend $Backend -Body {
        try { $null = Invoke-PortWatch -Backend $Backend } catch { }
    }
    return $events
}

# A sentinel's history identifier. ONE single place builds it: the reading and the writing
# cannot drift apart.
function Get-SentinelMeasureId {
    param([Parameter(Mandatory)][string]$Key)
    return ('watch.' + $Key)
}
