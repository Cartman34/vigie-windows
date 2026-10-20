# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, games, lock, log, paths, retention, series, store, var, watch-engine
<#
    Intent: THE HISTORY OF A MEASURE, kept as a series: one file per day per measure, a point written only when it says something new, and a window of it read back for a graph. The purge is part of the subject -- a history that grows without limit is a disk that fills.
    Usage: dot-sourced by common.ps1, never run on its own.
#>









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
        $mx = Get-NamedLock -Name (Get-LockName -Family 'History' -Path $file)
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
