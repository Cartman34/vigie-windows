# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, games, log, paths, store, var, watch-engine
<#
    Intent: THE HISTORY OF A MEASURE, kept as a series: one file per day per measure, a point written only when it says something new, and a window of it read back for a graph. The purge is part of the subject -- a history that grows without limit is a disk that fills.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# Resolves the history's configuration in LAYERS (the same logic as the config, D33):
# internal defaults -> the History section of config.psd1 (overridden by config.local.psd1)
# -> the per-measurement setting, the most specific winning. Without -MeasureId: the global
# values. With it: the EFFECTIVE values of that measurement (RetentionDays, IntervalMinutes,
# MaxLines). RetentionDays <= 0 on a measurement means: stop sampling it.
function Get-HistoryConfig {
    param([string]$Backend = (Get-BackendRoot), [string]$MeasureId, [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    $h = $Config.History
    $res = @{ Enabled = $true; RetentionDays = 90; MaxLinesPerMeasure = 50000; Measures = @{} }
    if ($h -is [hashtable]) {
        if ($h.ContainsKey('Enabled'))            { $res.Enabled            = [bool]$h.Enabled }
        if ($h.ContainsKey('RetentionDays'))      { $res.RetentionDays      = [int]$h.RetentionDays }
        if ($h.ContainsKey('MaxLinesPerMeasure')) { $res.MaxLinesPerMeasure = [int]$h.MaxLinesPerMeasure }
        if ($h.Measures -is [hashtable])          { $res.Measures           = $h.Measures }
    }
    if (-not $MeasureId) { return $res }
    $cat = $script:MeasureCatalog[$MeasureId]
    $eff = @{
        Enabled         = $res.Enabled
        RetentionDays   = $res.RetentionDays
        MaxLines        = $res.MaxLinesPerMeasure
        IntervalMinutes = $(if ($cat -and $cat.ContainsKey('IntervalMinutes')) { [int]$cat.IntervalMinutes } else { 0 })
        # HOW MUCH MUST IT MOVE TO COUNT? Below that, it is noise: a GPU swinging between 22
        # and 25 % within the same minute tells nothing, and writing it three times only
        # fills the disk. 0 means every variation counts.
        Tolerance       = $(if ($cat -and $cat.ContainsKey('Tolerance')) { [double]$cat.Tolerance } else { 0 })
    }
    $mo = $res.Measures[$MeasureId]
    if ($mo -is [hashtable]) {
        if ($mo.ContainsKey('RetentionDays'))   { $eff.RetentionDays   = [int]$mo.RetentionDays }
        if ($mo.ContainsKey('IntervalMinutes')) { $eff.IntervalMinutes = [int]$mo.IntervalMinutes }
        if ($mo.ContainsKey('Tolerance'))       { $eff.Tolerance       = [double]$mo.Tolerance }
    }
    # Zero retention means the measurement is off. The existing file is NOT deleted:
    # destroying an archive stays a manual and deliberate gesture.
    if ($eff.RetentionDays -le 0) { $eff.Enabled = $false }
    return $eff
}

# Appends ONE line to a history file, under that file's mutex (the same convention as
# Update-StateJson). It is necessary: two simultaneous recomputations really do exist -- a
# forced request and a background refresh -- and their writes must not interleave.
<#
    ONE FILE PER MEASUREMENT AND PER DAY: var/history/<measure>/<YYYY-MM-DD>.jsonl

    A single file per measurement grew endlessly, and the purge had to READ IT WHOLE, parse
    every line, throw the old ones away and rewrite everything -- under the lock, blocking the
    writes. Cut up by day, purging comes down to DELETING files: no reading, no parsing, no
    rewriting. Reading a 24-hour window now opens one file or two instead of walking ninety
    days to throw 98 % of them away.
#>
function Get-MeasureDayFile {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId,
        [datetime]$Day = [datetime]::UtcNow
    )
    $dir = Join-Path (Get-VarPath -Backend $Backend -Kind 'history') $MeasureId
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null } catch { }
    }
    Join-Path $dir ($Day.ToUniversalTime().ToString('yyyy-MM-dd') + '.jsonl')
}

<#
    THE LOCK'S NAME TAKES THE MEASUREMENT INTO ACCOUNT, not only the file.

    Since the split by day, every file of a given day is called the same thing
    (2026-09-01.jsonl): a lock named after the file alone would make the disk measurement wait
    because the network one is writing. Two measurements have nothing to share.
#>
<#
    AND IT COVERS THE WHOLE COMPUTER, not one session.

    It was named "Local\...". A Local lock exists ONLY inside one Windows session: the server app writes from the
    service's session, a client app from its account's, and each took a DIFFERENT lock bearing the same name. The
    one that can really hurt is the purge, which REWRITES a file while another session appends to it.

    "Global\" is shared by the whole computer. It needs an explicit access right: created by the elevated service
    account, its default list would stop an ordinary client app from opening it -- and that app would then write
    with NO lock at all, which is worse than the disease. Get-HistoryMutex grants the right as it creates it.
#>
function Get-HistoryMutexName {
    param([Parameter(Mandatory)][string]$Path)
    $leaf   = Split-Path $Path -Leaf
    $parent = Split-Path (Split-Path $Path -Parent) -Leaf
    return ('Global\VigieHistory_' + (($parent + '_' + $leaf) -replace '[^A-Za-z0-9]', '_'))
}

<#
    THE LOCK ITSELF, OPEN TO EVERY ACCOUNT ON THE COMPUTER.

    One door: everything touching the history comes through here, and nobody builds a Mutex by hand. The right is
    granted as it is created -- anyone may take it and give it back -- otherwise only the service account that
    created it could use it at all.

    If none of that works, it returns $null and the caller writes anyway: a history with no lock beats no history,
    and the writing itself is built to hold (see Add-HistoryLine).
#>
function Get-HistoryMutex {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $rules = New-Object System.Security.AccessControl.MutexSecurity
        $everyone = New-Object System.Security.Principal.SecurityIdentifier(
            [System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $rules.AddAccessRule((New-Object System.Security.AccessControl.MutexAccessRule(
            $everyone,
            ([System.Security.AccessControl.MutexRights]'Synchronize, Modify'),
            [System.Security.AccessControl.AccessControlType]::Allow)))
        $created = $false
        return [System.Threading.MutexAcl]::Create($false, $Name, [ref]$created, $rules)
    } catch { }
    # MutexAcl is not everywhere: fall back on a plain lock, which is enough between processes of one account, and
    # on the resilient write for the rest.
    try { return (New-Object System.Threading.Mutex($false, $Name)) } catch { }
    try { return [System.Threading.Mutex]::OpenExisting($Name) } catch { }
    return $null
}

<#
    THE LAST SAFETY NET, AND NOTHING MORE.

    A measurement must not be able to fill the disk because it has started changing at every
    pass. The guard reads in one system call -- the SIZE of the day's file -- without counting
    or parsing anything. Past it, the measurement does not fall silent: it is THROTTLED to one
    line a minute (the file's date says when the last one landed). Falling silent at noon
    would leave us blind to the real incident of the afternoon.

    With the rule "the same value is never written twice", this net should never serve: if it
    triggers, that is a DEFECT to correct, and that is why it says so in the log.
#>
<#
    THE LAST POINTS ALREADY WRITTEN, without rereading the file.

    We only read the END of the file (two kilobytes are enough for a few lines): the cost
    does not depend on the file size, even after thousands of points. Returns, newest
    first: the value, and the OFFSET where its line starts -- that offset is what allows
    erasing the last line without rewriting everything.
#>
function Get-HistoryTailPoints {
    param([Parameter(Mandatory)][string]$Path, [int]$Count = 2)
    $tail = @()
    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($fi.Length -le 0) { return $tail }
        $size = [int][Math]::Min($fi.Length, 2048)
        $start  = $fi.Length - $size
        $buffer = New-Object byte[] $size
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $null = $fs.Seek($start, [IO.SeekOrigin]::Begin)
            $null = $fs.Read($buffer, 0, $size)
        } finally { $fs.Dispose() }
        $text = [Text.Encoding]::UTF8.GetString($buffer)
        # The buffer's first line is probably cut in half: it is thrown away, unless the file
        # was read from its very beginning.
        $lines = $text -split "`r?`n"
        if ($start -gt 0 -and $lines.Count) { $lines = $lines[1..($lines.Count - 1)] }
        # The offset of each line kept, counted back from the end.
        $offset = $fi.Length
        for ($i = $lines.Count - 1; $i -ge 0 -and $tail.Count -lt $Count; $i--) {
            $l = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($l)) { continue }
            $offset -= ([Text.Encoding]::UTF8.GetByteCount($l) + [Environment]::NewLine.Length)
            $o = $null
            try { $o = $l | ConvertFrom-Json } catch { continue }
            $v = 0.0
            if (-not [double]::TryParse("$($o.v)", [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return @() }
            $at = $null
            try { $at = ConvertTo-UtcDate $o.at } catch { }
            $tail += [pscustomobject]@{ V = $v; At = $at; Offset = $offset }
        }
    } catch { return @() }
    return $tail
}

<#
    A POINT BETWEEN ITS TWO NEIGHBOURS SAYS NOTHING: WE ERASE IT.

    When a point arrives, the PREVIOUS one becomes judgeable: if it sits between the one
    before it and the one being written, it lies on the line joining them -- it can be
    deduced, so it is not kept. Only TURNING POINTS remain: the extremes of the
    fluctuations, which carry the whole shape of the curve and all its records.

    So we look BACKWARDS, at write time: no delay, no second pass, and the current day
    stays accurate to the second. Erasing costs one call -- the file is truncated at the
    offset of its last line, never rewritten.

    TWO GUARDS:
      - the tolerance: a turn smaller than it is not a turn, it is noise;
      - the heartbeat: never erase if that would dig a hole longer than fifteen minutes,
        or "stable" could no longer be told from "nothing measures any more".
#>
function Remove-RedundantHistoryPoint {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][double]$NewValue,
        [double]$Tolerance = 0,
        [int]$HeartbeatMinutes = 15
    )
    $tail = @(Get-HistoryTailPoints -Path $Path -Count 2)
    if ($tail.Count -lt 2) { return $false }
    $previous = $tail[0]      # N-1, celui qu'on juge
    $beforeThat   = $tail[1]      # N-2
    $low  = [Math]::Min($beforeThat.V, $NewValue) - $Tolerance
    $high = [Math]::Max($beforeThat.V, $NewValue) + $Tolerance
    if ($previous.V -lt $low -or $previous.V -gt $high) { return $false }
    if ($beforeThat.At -and ([datetime]::UtcNow - $beforeThat.At).TotalMinutes -ge $HeartbeatMinutes) { return $false }
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $fs.SetLength($previous.Offset) } finally { $fs.Dispose() }
        return $true
    } catch { return $false }
}

function Write-HistoryPoint {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId,
        [Parameter(Mandatory)]$Point,
        # EVENTS are never compacted: each one is a unique fact, and "in between" means
        # nothing for a state.
        [switch]$Compact,
        [double]$Tolerance = 0,
        [int]$MaxBytes = 5242880
    )
    $file = Get-MeasureDayFile -Backend $Backend -MeasureId $MeasureId
    $fi = $null
    try { $fi = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue } catch { }
    if ($fi -and $fi.Length -ge $MaxBytes) {
        if (([datetime]::UtcNow - $fi.LastWriteTimeUtc).TotalSeconds -lt 60) { return $false }
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -NoEcho `
                        -Message (Get-Label 'common.historique-bride' $MeasureId) } catch { }
    }
    # The PREVIOUS point becomes judgeable now that the next one is known.
    if ($Compact) {
        $v = 0.0
        if ([double]::TryParse("$($Point.v)", [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
            $null = Remove-RedundantHistoryPoint -Path $file -NewValue $v -Tolerance $Tolerance
        }
    }
    return (Add-HistoryLine -Path $file -Line ($Point | ConvertTo-Json -Compress -Depth 4))
}

<#
    A LINE GOES IN WHOLE, OR NOT AT ALL.

    The lock comes first, and it now covers the whole computer. But a lock can be missing -- an account without the
    right to open it, a wait that expires -- and what was written then had no protection at all.

    So the write itself refuses sharing: the file is opened to APPEND, for EXCLUSIVE writing, the line goes in one
    call, and the file closes. Another process writing at the same instant does not get in -- it retries, and
    returns $false if it never does. A lost line shows in the count; a half-written one does not.
#>
function Add-HistoryLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Line, [int]$Tries = 5)
    $mx = Get-HistoryMutex -Name (Get-HistoryMutexName -Path $Path)
    $got = $false
    try {
        if ($mx) {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
        }
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Line + [Environment]::NewLine)
        for ($i = 0; $i -lt $Tries; $i++) {
            try {
                $fs = [IO.File]::Open($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Dispose() }
                return $true
            } catch [System.IO.IOException] {
                # SOMEONE ELSE HOLDS THE FILE: wait a little and try again. That is the normal case when two
                # processes write within the same second, not a failure.
                Start-Sleep -Milliseconds (30 * ($i + 1))
            } catch { return $false }
        }
        return $false
    } finally {
        if ($got) { try { $mx.ReleaseMutex() } catch { } }
        if ($mx) { try { $mx.Dispose() } catch { } }
    }
}

# Samples the measurements of ONE probe, just after its successful recomputation (a single
# call site: the loop of Get-State). It consults the catalogue, applies the minimum interval
# through the index (history-index.json: lastAt, lastValue and lastKey per measurement,
# written by Update-StateJson and therefore merged under a mutex), and appends to
# var/history/<measureId>.jsonl. It also triggers the purge, at most once per 24 h.
# Best effort from end to end: no failure ever reaches the recomputation.
function Write-MeasureSamples {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Probe,
        [Parameter(Mandatory)]$Modules
    )
    try {
        # THE MOMENT IS ITS OWN. This function used to read $nowUtc from whoever called it -- Get-State defines one
        # before recomputing, so it worked by the accident of scope, and failed in silence anywhere else: the catch
        # below turned it into a warning saying the sampling was skipped. Caught on 16/10 while adding a measure.
        $nowUtc = [datetime]::UtcNow
        $ids = @($script:MeasureCatalog.Keys | Where-Object { $script:MeasureCatalog[$_].Probe -eq $Probe })
        if ($ids.Count -eq 0) { return }
        $cfg = Get-Config -Backend $Backend
        $global = Get-HistoryConfig -Backend $Backend -Config $cfg
        if (-not $global.Enabled) { return }
        # Read once for the whole pass: a game running changes the pace of some measures.
        $inGameMeasures = [bool](Get-GameModeName -Backend $Backend)
        $indexFile = Get-VarPath -Backend $Backend -Kind 'history' -File 'history-index.json'
        $index = $null
        if (Test-Path -LiteralPath $indexFile) {
            try { $index = Get-Content -LiteralPath $indexFile -Raw | ConvertFrom-Json } catch { }
        }
        foreach ($id in ($ids | Sort-Object)) {
            $cat = $script:MeasureCatalog[$id]
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg
            if (-not $eff.Enabled) { continue }
            $sample = $null
            try { $sample = & $cat.Extract $Modules } catch { $sample = $null }
            if ($null -eq $sample -or $null -eq $sample.v) { continue }
            $prop  = if ($index) { $index.PSObject.Properties[$id] } else { $null }
            $entry = if ($prop) { $prop.Value } else { $null }
            # A keyed measurement, tied to an external one: a point is written only when the
            # key changes. The key read back goes through ConvertTo-UtcDate: ConvertFrom-Json
            # returns the stored date as a [datetime] (D44), and comparing it as it stands
            # with the extractor's 'o' string NEVER matched -- seen in testing, one point per
            # recomputation.
            if ($sample.key -and $entry -and $entry.lastKey) {
                $prevKey = "$($entry.lastKey)"
                try { $prevKey = (ConvertTo-UtcDate $entry.lastKey).ToString('o') } catch { }
                if ($prevKey -eq "$($sample.key)") { continue }
            }
            # An ordinary gauge: the minimum interval since the last point.
            # WHILE A GAME RUNS, a measure may ask for a closer pace (IntervalMinutesInGame): the enquiry needs the
            # minute, the rest of the day does not.
            $interval = [int]$eff.IntervalMinutes
            if ($inGameMeasures -and $cat.IntervalMinutesInGame) { $interval = [int]$cat.IntervalMinutesInGame }
            if ((-not $sample.key) -and $interval -gt 0 -and $entry -and $entry.lastAt) {
                try {
                    $last = ConvertTo-UtcDate $entry.lastAt
                    if ($last -and ($nowUtc - $last).TotalMinutes -lt $interval) { continue }
                } catch { }
            }
            # THE SAME VALUE IS NEVER WRITTEN TWICE.
            #
            # The value noted is not a raw measurement: it is the one the CARD displays, so
            # already rounded to what matters -- space in GB, the GPU in per cent, latency in
            # ms. Two identical readings therefore carry the same information, and rewriting
            # it only fills the disk.
            #
            # A HEARTBEAT: after fifteen minutes, a point is written anyway. Without it a
            # flat series becomes a hole, and "stable" can no longer be told from "nothing
            # measures any more" -- which is quite another piece of news.
            # THE TOLERANCE DOES NOT FILTER HERE: it serves the compaction of a closed day,
            # where the next point is known and a real turn can be told from a fluctuation.
            # At write time, that is not yet known.
            # Not rewriting the SAME value, on the other hand, requires knowing nothing.
            $noise = $false
            if ($entry -and $null -ne $entry.lastValue) {
                if ("$($entry.lastValue)" -eq "$($sample.v)") { $noise = $true }
                # A HEARTBEAT: after fifteen minutes a point is written anyway. Without it a
                # flat series becomes a hole, and "stable" can no longer be told from
                # "nothing measures any more" -- which is quite another piece of news.
                if ($noise -and $entry.lastAt) {
                    try {
                        $last = ConvertTo-UtcDate $entry.lastAt
                        if ($last -and ($nowUtc - $last).TotalMinutes -ge 15) { $noise = $false }
                    } catch { $noise = $false }
                }
            }
            if ($noise) { continue }
            # Optional field n: a NAME attached to the point, such as a session's game -- it
            # is what will answer "what was running at that hour?".
            $obj = [ordered]@{ at = $nowUtc.ToString('o'); v = $sample.v }
            if ($sample.n) { $obj.n = "$($sample.n)" }
            if (Write-HistoryPoint -Backend $Backend -MeasureId $id -Point $obj -Compact -Tolerance $eff.Tolerance) {
                $set = @{ lastAt = $nowUtc.ToString('o'); lastValue = $sample.v }
                if ($sample.key) { $set.lastKey = "$($sample.key)" }
                try { Update-StateJson -Path $indexFile -Set @{ $id = $set } | Out-Null } catch { }
            }
        }
        # The purge: at most once per 24 h, carried by a recomputation already under way, so
        # there is never a wake-up of its own. The date is laid BEFORE purging, so that two
        # simultaneous recomputations do not start two purges.
        $due = $true
        $pp = if ($index) { $index.PSObject.Properties['purgedAt'] } else { $null }
        if ($pp -and $pp.Value) {
            try {
                $p = ConvertTo-UtcDate $pp.Value
                if ($p -and ($nowUtc - $p).TotalHours -lt 24) { $due = $false }
            } catch { }
        }
        if ($due) {
            try { Update-StateJson -Path $indexFile -Set @{ purgedAt = $nowUtc.ToString('o') } | Out-Null } catch { }
            Invoke-HistoryPurge -Backend $Backend
            try { $null = Invoke-LogPurge -Backend $Backend } catch { }
        }
    } catch {
        # The history OBSERVES, it does not arbitrate: no failure ever reaches Get-State.
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (Get-Label 'common.historique-echantillonnage-ignore' $Probe $_.Exception.Message) } catch { }
    }
}

<#
    THE LOGS ARE KEPT 30 DAYS, then deleted. The requirement: doc/progress/targeting/components.md, in its section
    on retention. Everything under var/log counts -- the logs, the diagnostic copies of other
    accounts, the .reg backups -- and a folder left empty goes too. A log still being written is recent, so it stays.
#>
function Invoke-LogPurge {
    param([string]$Backend = (Get-BackendRoot))
    $days = 30
    try { $configured = [int]((Get-Config -Backend $Backend).LogRetentionDays); if ($configured -gt 0) { $days = $configured } } catch { }
    $dir = Get-VarPath -Backend $Backend -Kind 'log'
    $limit = (Get-Date).AddDays(-$days)
    $removed = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        if ($file.LastWriteTime -ge $limit) { continue }
        try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $removed++ } catch { }
    }
    <#
        AND A CEILING IN MEGABYTES, because an age is not a size.

        Thirty days of logs weighed 166 MB for the service account on 29/09 -- 703 files, several of them 4 MB a day
        -- on a machine whose disk was down to 31 GB. An age alone bounds nothing: a busy day writes ten times what a
        quiet one writes. Past the ceiling, the OLDEST files go, one by one, until the total is back under it.

        WHAT IS NEVER TOUCHED: anything written in the last hour. A log being written is the one being read when
        something goes wrong, and it is never the one to sacrifice.
    #>
    $maxMb = 60
    try { $configured = [int]((Get-Config -Backend $Backend).LogMaxMb); if ($configured -gt 0) { $maxMb = $configured } } catch { }
    if ($maxMb -gt 0) {
        $recent = (Get-Date).AddHours(-1)
        $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime)
        $total = ($files | Measure-Object Length -Sum).Sum
        foreach ($f in $files) {
            if ($total -le ($maxMb * 1MB)) { break }
            if ($f.LastWriteTime -ge $recent) { continue }
            try {
                $size = $f.Length
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $total -= $size
                $removed++
            } catch { }
        }
    }
    foreach ($folder in @(Get-ChildItem -LiteralPath $dir -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                          Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue).Count) {
            Remove-Item -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    return $removed
}

# Purges the files of var/history/: a retention in days (global, overridden per measurement)
# PLUS a ceiling in lines, a size guard so that a badly set interval cannot fill the disk.
# Rewriting is ATOMIC (.tmp, a guard, then Move-Item) under the file's mutex. Unreadable
# lines, from an interrupted write, are removed and counted, never blocking. probe-runs.jsonl
# is NOT concerned: it lives in var/cache/ and keeps its own purge by size (D52).
function Invoke-HistoryPurge {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $cfg = Get-Config -Backend $Backend
        $dir = Get-VarPath -Backend $Backend -Kind 'history'
        $nowUtc = [datetime]::UtcNow

        # PURGING THE PER-DAY FILES: we DELETE, we read nothing back. The file's name carries
        # its date -- which is all one needs to decide.
        foreach ($measure in @(Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue)) {
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $measure.Name -Config $cfg
            if ($eff.RetentionDays -le 0) { continue }
            $limit = $nowUtc.Date.AddDays(-$eff.RetentionDays)
            foreach ($day in @(Get-ChildItem -Path $measure.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
                $date = [datetime]::MinValue
                if (-not [datetime]::TryParseExact([IO.Path]::GetFileNameWithoutExtension($day.Name), 'yyyy-MM-dd',
                        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) { continue }
                if ($date -lt $limit) {
                    try {
                        Remove-Item -LiteralPath $day.FullName -Force -ErrorAction Stop
                        Write-Log -Backend $Backend -Name 'state' -NoEcho `
                                  -Message (Get-Label 'common.historique-jour-supprime' $measure.Name $day.Name)
                    } catch { }
                    continue
                }

            }
        }

        # THE OLD FLAT FILES, on the other hand, are still purged line by line: they carry no
        # date in their name. That path will disappear with them.
        $files = @(Get-ChildItem -Path $dir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
        foreach ($fi in $files) {
            $id  = [IO.Path]::GetFileNameWithoutExtension($fi.Name)
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg
            # Retention <= 0: the measurement is no longer sampled, but an existing archive is
            # never emptied -- that stays a manual gesture.
            if ($eff.RetentionDays -le 0) { continue }
            $cutoff = $nowUtc.AddDays(-$eff.RetentionDays)
            $mx = Get-HistoryMutex -Name (Get-HistoryMutexName -Path $fi.FullName)
            $got = $false
            try {
                try { $got = $mx.WaitOne(5000) }
                catch [System.Threading.AbandonedMutexException] { $got = $true }
                catch { $got = $false }
                if (-not $got) { continue }
                $lines = [IO.File]::ReadAllLines($fi.FullName)
                $keep = New-Object System.Collections.Generic.List[string]
                $dropped = 0
                foreach ($l in $lines) {
                    if ([string]::IsNullOrWhiteSpace($l)) { $dropped++; continue }
                    $o = $null
                    try { $o = $l | ConvertFrom-Json } catch { $dropped++; continue }
                    $at = $null
                    try { $at = ConvertTo-UtcDate $o.at } catch { }
                    if (-not $at -or $at -lt $cutoff) { $dropped++; continue }
                    $keep.Add($l)
                }
                if ($eff.MaxLines -gt 0 -and $keep.Count -gt $eff.MaxLines) {
                    $excess = $keep.Count - $eff.MaxLines
                    $keep.RemoveRange(0, $excess)
                    $dropped += $excess
                }
                if ($dropped -gt 0) {
                    $tmp = $fi.FullName + '.tmp'
                    [IO.File]::WriteAllLines($tmp, $keep, [Text.UTF8Encoding]::new($false))
                    # A size guard: if lines are kept, the .tmp cannot be empty.
                    $ok = (Test-Path -LiteralPath $tmp) -and ($keep.Count -eq 0 -or (Get-Item -LiteralPath $tmp).Length -gt 0)
                    if ($ok) { Move-Item -Path $tmp -Destination $fi.FullName -Force }
                    else { try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { } }
                    Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'common.historique-purge-de-ligne' $fi.Name $dropped $keep.Count)
                }
            } finally {
                if ($got) { try { $mx.ReleaseMutex() } catch { } }
                try { $mx.Dispose() } catch { }
            }
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (Get-Label 'common.historique-purge-en-echec' $_.Exception.Message) } catch { }
    }
}

# Reads a history window ("24h", "7d") as a [TimeSpan].
# $null means an invalid form: the route then answers 400, and this function never guesses.
# The bounds are wide but finite: a huge window is not a malformed one, it simply reads the
# whole file (the retention already bounds the data).
function ConvertTo-HistoryWindow {
    param([string]$Window)
    if (-not $Window) { return $null }
    if ($Window -notmatch '^([0-9]{1,4})([hd])$') { return $null }
    $n = [int]$Matches[1]
    if ($n -le 0) { return $null }
    if ($Matches[2] -eq 'h') { return [TimeSpan]::FromHours($n) }
    return [TimeSpan]::FromDays($n)
}

# Reads the series of ONE measurement for GET /history/{measureId}. Read only, under the
# SAME mutex as the writing: an append may be under way during the reading. Unreadable
# lines, from an interrupted write, are ignored without failing.
# Returns $null when the measurement is not in the catalogue (the route answers 404); otherwise an object matching
# the contract's History schema: points (decimated to ~$MaxPoints for
# a gauge, as they stand for an event -- they are rare) plus a summary computed BEFORE the
# decimation. A file that is missing or empty gives no points and summary.count = 0: a young
# history is not an error.
# THE DEFINITION OF A MEASUREMENT, from the catalogue or from a SENTINEL.
#
# The catalogue is fixed in this file; the sentinels, on the other hand, are declared by the
# modules (module.psd1, the Sentinels key) and so cannot appear in it. Their measurement is
# resolved here, on the fly: the identifier "watch.<key>", nature 'event' -- a state written
# ONLY when it changes, which is exactly what the history's design calls an event. Nothing is
# duplicated: the same var/history/ folder, the same purge, the same
# GET /history/{measureId} route.
function Get-MeasureDefinition {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId
    )
    $cat = $script:MeasureCatalog[$MeasureId]
    if ($cat) { return $cat }
    if ($MeasureId -notlike 'watch.*') { return $null }
    $key = $MeasureId.Substring(6)
    $w = @(Get-WatchDeclarations -Backend $Backend | Where-Object { "$($_.Key)" -eq $key })[0]
    if (-not $w) { return $null }
    return @{ Probe = ''; Kind = 'event'; Unit = ''; IntervalMinutes = 0; Label = "$($w.Label)" }
}

function Get-MeasureHistory {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId,
        [Parameter(Mandatory)][TimeSpan]$Window,
        [string]$WindowLabel = '',
        [int]$MaxPoints = 200
    )
    $cat = Get-MeasureDefinition -Backend $Backend -MeasureId $MeasureId
    if (-not $cat) { return $null }
    # ONLY THE DAYS OF THE WINDOW ARE OPENED. One day more on each side: the window does not
    # begin at midnight, and the files are dated in UTC.
    $lines = @()
    $firstDay = ([datetime]::UtcNow - $Window).Date.AddDays(-1)
    $days = @()
    for ($j = $firstDay; $j -le ([datetime]::UtcNow.Date); $j = $j.AddDays(1)) {
        $days += (Get-MeasureDayFile -Backend $Backend -MeasureId $MeasureId -Day $j)
    }
    # THE OLD FLAT FILE is still read for as long as it exists: nobody loses their history
    # because the filing changed. Nothing is written to it any more.
    $days += (Get-VarPath -Backend $Backend -Kind 'history' -File ($MeasureId + '.jsonl'))
    foreach ($file in $days) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $mx = Get-HistoryMutex -Name (Get-HistoryMutexName -Path $file)
        $got = $false
        try {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            # The mutex is unavailable: we read anyway -- the worst case is a truncated final
            # line, already handled -- rather than returning an error to the client.
            $lines += [IO.File]::ReadAllLines($file)
        } finally {
            if ($got) { try { $mx.ReleaseMutex() } catch { } }
            try { $mx.Dispose() } catch { }
        }
    }
    $nowUtc = [datetime]::UtcNow
    $cutoff = $nowUtc - $Window
    # Filtering and normalising. The file is append-only and therefore already chronological;
    # it is sorted again all the same: an interrupted purge or a forged line must not return
    # a series out of order.
    $pts = New-Object System.Collections.Generic.List[object]
    <#
        SKIPPED LINES ARE COUNTED, AND SAID.

        An unreadable line was skipped in silence. A wholly damaged file therefore returned ZERO points -- exactly
        what a measure never taken returns: the two were indistinguishable on screen (seen on 06/10). Handling an
        error without reporting it is half the rule (components.md).
    #>
    $unreadable = 0
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { $unreadable++; continue }
        $at = $null
        # ConvertFrom-Json returns the date sometimes as a string, sometimes as a [datetime]
        # (D44): ConvertTo-UtcDate normalises, and comparing without it would skew the window.
        try { $at = ConvertTo-UtcDate $o.at } catch { continue }
        if (-not $at -or $null -eq $o.v) { continue }
        if ($at -lt $cutoff) { continue }
        # AN EVENT IS NOT A NUMBER. Its value is a state ("oui", "Actif", "erreur: ..."):
        # handing it to TryParse would throw it away outright.
        # Where it came from and what the change triggered are kept too: that is what makes
        # the difference between a value and an ALERT.
        if ("$($cat.Kind)" -eq 'event') {
            $pts.Add([pscustomobject]@{ atUtc = $at; v = "$($o.v)"; from = "$($o.from)"; cards = @($o.cards) })
            continue
        }
        $v = 0.0
        if (-not [double]::TryParse("$($o.v)", [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { continue }
        $pts.Add([pscustomobject]@{ atUtc = $at; v = $v })
    }
    $sorted = @($pts | Sort-Object atUtc)
    # The summary covers ALL the points of the window, before decimation: decimation can drop
    # the extreme, and the summary must not lose it.
    $summary = [ordered]@{ count = $sorted.Count; min = $null; max = $null; first = $null; last = $null }
    if ($sorted.Count -gt 0 -and "$($cat.Kind)" -eq 'event') {
        $summary.first = $sorted[0].v
        $summary.last  = $sorted[$sorted.Count - 1].v
    }
    elseif ($sorted.Count -gt 0) {
        $mesures = $sorted | Measure-Object -Property v -Minimum -Maximum
        $summary.min   = $mesures.Minimum
        $summary.max   = $mesures.Maximum
        $summary.first = $sorted[0].v
        $summary.last  = $sorted[$sorted.Count - 1].v
    }
    # Uniform decimation by index, the first and last points kept. Events will go through as
    # they are: they are rare, and every occurrence counts.
    $kept = $sorted
    if ("$($cat.Kind)" -ne 'event' -and $MaxPoints -gt 0 -and $sorted.Count -gt $MaxPoints) {
        $kept = New-Object System.Collections.Generic.List[object]
        $step = ($sorted.Count - 1) / [double]($MaxPoints - 1)
        $lastIdx = -1
        for ($i = 0; $i -lt $MaxPoints; $i++) {
            $idx = [int][math]::Round($i * $step)
            if ($idx -eq $lastIdx) { continue }   # deux i arrondis au meme index
            $kept.Add($sorted[$idx])
            $lastIdx = $idx
        }
    }
    return [ordered]@{
        measureId = $MeasureId
        kind      = "$($cat.Kind)"
        unit      = "$($cat.Unit)"
        window    = $WindowLabel
        points    = @($kept | ForEach-Object {
            $pt = [ordered]@{ at = $_.atUtc.ToString('o'); v = $_.v }
            if ("$($cat.Kind)" -eq 'event') { $pt.from = $_.from; $pt.cards = @($_.cards) }
            $pt })
        summary   = $summary
        # WHAT COULD NOT BE READ. Zero points alone did not say whether the measure had never been taken or its
        # file was damaged: the difference is read here.
        unreadable = $unreadable
    }
}
