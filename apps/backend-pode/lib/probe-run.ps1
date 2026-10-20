# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: card-shape, lock, log, measures, probe-cache, probes
<#
    Intent: RUNNING A PROBE AND KEEPING WHAT IT ANSWERED: one at a time for a given probe, the account it is
    computing for said just before and taken back just after, the result written entry by entry, and a card
    carrying the failure when it throws. WHICH probes are stale is probe-cache's answer; this one runs them.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    ONE LOCK PER PROBE WHEN ONE PROBE IS COMPUTED (D124).

    A single global lock made the scheduler's limit a decoration: three launches would simply have queued behind
    each other. Computing SEVERAL probes still takes the shared lock -- that path is the explicit refresh, and it
    is the one that must not be run twice at once. A single-probe worker and a multi-probe refresh can therefore
    overlap on the same probe; it costs one wasted pass, and the cache write is protected file by file.
#>
function Get-ProbeRecomputeLock {
    param([string]$Probe = '')
    if ($Probe) { return (Get-SessionLockName -Family 'StateRecompute' -Key $Probe) }
    return (Get-SessionLockName -Family 'StateRecompute')
}

<#
    THE PROBES THAT ARE RECOMPUTED, IN ORDER, AND WRITTEN ONE BY ONE.

    The slow ones go last, so a page waiting on an explicit refresh gets the quick cards first.

    FOR WHOM is said just before the probe runs and taken back just after: a probe dot-sources this library
    itself, so nothing else reaches it (D128). A global left behind would answer for the next computation, which
    may be for somebody else or for nobody.

    Each result is written as it is produced, not at the end: a recomputation interrupted half-way has still
    recorded what it managed to do.
#>
function Invoke-ProbeRecompute {
    param(
        [Parameter(Mandatory)][string]$Backend,
        [Parameter(Mandatory)]$Stale,
        [Parameter(Mandatory)][string]$CacheFile,
        [Parameter(Mandatory)][hashtable]$Cache,
        [string]$Account = '',
        [string]$Origin = 'background'
    )
    foreach ($sp in $Stale) {
        $t0 = Get-Date
        try {
            $global:VigieStateAccount = $Account
            $m = & $sp.File
            $elapsedMs = [int]((Get-Date) - $t0).TotalMilliseconds
            if ($m) { $Cache[$sp.Key] = New-ProbeCacheEntry -Module $m -Stamp $sp.Stamp }
            Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms $elapsedMs -Origin $Origin `
                           -Outcome ($(if ($m) { 'ok' } else { 'empty' })) -Modules @($m).Count
            Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'common.sonde-recalculee-ms' $sp.Name $elapsedMs)
            # History: samples the catalogue's measurements AFTER a successful recomputation. Best effort -- the
            # function never fails.
            if ($m) { Write-MeasureSamples -Backend $Backend -Probe $sp.Name -Modules @($m) }
        } catch {
            Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms ([int]((Get-Date) - $t0).TotalMilliseconds) `
                           -Origin $Origin -Outcome 'error' -Detail $_.Exception.Message
            Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' `
                      -Message (Get-Label 'common.sonde-erreur' $sp.Name $_.Exception.Message)
            $errCard = New-ProbeErrorCard -ProbeFile $sp.File -ProbeName $sp.Name -Message $_.Exception.Message
            $Cache[$sp.Key] = New-ProbeCacheEntry -Module $errCard -Stamp $sp.Stamp
        } finally {
            $global:VigieStateAccount = $null
        }
        Set-ProbeCacheEntry -Path $CacheFile -Key $sp.Key -Entry $Cache[$sp.Key]
    }
}

<#
    THE RECOMPUTATION IS SINGLE-FLIGHT: one at a time, and whoever does not get in serves the cache as it stands.

    An EXPLICIT request -- the refresh button -- WAITS its turn; ordinary requests do not wait. With a wait of
    zero for everyone, the button did nothing as soon as a background refresh held the lock: it handed back at
    once.

    A PERSONAL CARD MUST BE COMPUTED NOW, or it never will be. The background refresh runs with no session: it
    writes under the anonymous key, never under "@<account>". If the request asking for it does not wait for the
    lock, its entry stays stale indefinitely -- seen on 30/08: the card announced v0.1.29-dev5 while the
    installation was at v0.1.30, and two calls in a row gave the same answer. So for those cards we wait our turn,
    even without an explicit request.

    Waiting is capped at 75 seconds, below the client's own delay: waiting longer than it does would mean working
    for a request already abandoned.
#>
function Invoke-StaleProbes {
    param(
        [Parameter(Mandatory)][string]$Backend,
        [Parameter(Mandatory)]$Stale,
        [Parameter(Mandatory)][string]$CacheFile,
        [Parameter(Mandatory)][hashtable]$Cache,
        [string]$Account = '',
        [string]$Origin = 'background',
        [int]$WaitSeconds = 0
    )
    # The slow ones last.
    $slow = @('lock.probe.ps1', 'pending.probe.ps1', 'wsl.probe.ps1')
    $ordered = @($Stale | Sort-Object @{ Expression = { if ($slow -contains $_.Name) { 1 } else { 0 } } }, Name)
    $lockName = $(if ($ordered.Count -eq 1) { Get-ProbeRecomputeLock -Probe $ordered[0].Name } else { Get-ProbeRecomputeLock })
    $lock = Get-NamedLock -Name $lockName
    $held = $false
    try {
        $perAccount = @($ordered | Where-Object { $_.PerAccount }).Count
        $seconds = [Math]::Max($WaitSeconds, $(if ($perAccount) { 30 } else { 0 }))
        $waitMs = [Math]::Min($seconds, 75) * 1000
        if ($lock) {
            try { $held = $lock.WaitOne($waitMs) }
            catch [System.Threading.AbandonedMutexException] { $held = $true }
            catch { $held = $false }
        }
        if (-not $held) { return }
        Invoke-ProbeRecompute -Backend $Backend -Stale $ordered -CacheFile $CacheFile -Cache $Cache `
                              -Account $Account -Origin $Origin
    } finally {
        if ($held -and $lock) { try { $lock.ReleaseMutex() } catch { } }
        if ($lock) { try { $lock.Dispose() } catch { } }
    }
}
