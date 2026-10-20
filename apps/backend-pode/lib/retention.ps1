# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, lock, log, paths, series, var
<#
    Intent: WHAT IS THROWN AWAY, AND WHEN: the logs past their age, and the history points past the window their measurement declares. A purge REWRITES a file another writer may be appending to, which is why it takes the lock.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
            $mx = Get-NamedLock -Name (Get-LockName -Family 'History' -Path $fi.FullName)
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
