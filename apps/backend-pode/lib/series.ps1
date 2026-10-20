# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, lock, log, paths, var
<#
    Intent: A SERIES OF POINTS IN A FILE, ONE FILE A DAY: appending a point without rereading what is there, erasing the last one when it repeats the previous value, reading back only the end of the file, and cutting a window out of it. It knows nothing of WHAT is measured -- that is measures.ps1.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
    $mx = Get-NamedLock -Name (Get-LockName -Family 'History' -Path $Path)
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
