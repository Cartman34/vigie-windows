# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: paths, scheduler, var
<#
    Intent: RUNNING THE PROBES AND REMEMBERING WHAT IT COST: whether a card is the same for everyone (PerAccount), where its cache lives, when it was last written, and the log of every real run with its duration.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- Shared helpers (the rule: one feature, one piece of code) ---------------


# Invalidates -- removes -- entries of the state cache: the probes named will be recomputed
# at the next /state. One single piece of code, reused by Invoke-ActionById AND by the
# detached workers. Best effort, written atomically.
function Remove-ProbeCache {
    param([Parameter(Mandatory)][string[]]$Names, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    $cacheFile = Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'cache' -File 'state-cache.json'
    # TEST-PATHSAFE: on another account's var, Test-Path THROWS instead of saying "no".
    if (-not (Test-PathSafe $cacheFile)) { return }
    try {
        $obj = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $ht = @{}
        foreach ($pp in $obj.PSObject.Properties) { $ht[$pp.Name] = $pp.Value }
        $changed = $false
        <#
            THE PER-ACCOUNT ENTRIES GO TOO.

            An action names the PROBE ("accounts.probe.ps1"); since personal cards have one key
            per account, the real entries are called "accounts.probe.ps1@fhaza",
            "accounts.probe.ps1@Famille"... so the invalidation removed nothing at all, and the
            card kept the rendering it had before the update.
        #>
        <#
            INVALIDATING IS NOT FORGETTING.

            The entry used to be deleted. Since a display no longer computes anything, a probe
            with no entry has no card at all: after an installation, Accounts and Deployment had
            purely VANISHED from the page. An empty card, loading, is no trouble at all -- which
            is what had been agreed.

            So the known rendering is kept and marked TO BE RECOMPUTED: the card shows, with its
            title and its place, and says it is waiting for its measurement.
        #>
        foreach ($k in $Names) {
            foreach ($present in @($ht.Keys)) {
                if ($present -eq $k -or $present -like ($k + '@*')) {
                    $entry = $ht[$present]
                    if ($entry -and $entry.module) {
                        # "at" at epoch zero: stale whatever the delay.
                        try { $entry.at = '0001-01-01T00:00:00.0000000Z' } catch { }
                        try { Add-Member -InputObject $entry -NotePropertyName 'pending' -NotePropertyValue $true -Force } catch { }
                        <#
                            AND THE OCCUPANCY DOES NOT SURVIVE IN A KEPT RENDERING (D130).

                            A card computed WHILE an operation ran carries `busy` in its rendering. We keep that
                            rendering so the card does not vanish -- but `busy` is not a value, it is a state, and it
                            was over by the time this ran: this function is called at the END of the operation.
                            Served again, the stale flag greyed the card out of its buttons until the probe
                            recomputed, which for the packages card can be a day. Seen on 06/10: the owner had to
                            press F5. A kept rendering keeps what was measured, never what was happening.
                        #>
                        foreach ($mod in @($entry.module)) {
                            if (-not $mod) { continue }
                            foreach ($champ in @('busy', 'busyAction', 'busyResources')) {
                                try { if ($mod.PSObject.Properties[$champ]) { $mod.PSObject.Properties.Remove($champ) } } catch { }
                            }
                        }
                        $ht[$present] = $entry
                    } else {
                        $ht.Remove($present)
                    }
                    $changed = $true
                }
            }
        }
        if ($changed) {
            $tmp = "$cacheFile.tmp"
            ($ht | ConvertTo-Json -Depth 25) | Out-File -FilePath $tmp -Encoding UTF8
            Move-Item -Path $tmp -Destination $cacheFile -Force
            # AND THE SCHEDULER LEARNS IT: without this an invalidated card would wait out its whole interval.
            try { Reset-RefreshDue -Backend $Backend -Probes $Names } catch { }
        }
    } catch { }
}





# --- The log of probe runs ---------------------------------------------------
# EVERY real run of a probe and its duration are kept, SYSTEMATICALLY, wherever it comes
# from: a user's request, a background refresh, or the contract check. Without that trace,
# "Vigie sometimes takes a long time to load" stays an impression: one knows neither WHICH
# probe cost the time, nor whether it is usual.
#
# Format: one JSON line per run (JSONL). Append-only, so the file is never read back in order
# to write -- which is what makes it usable under concurrency.
# This log is also the first sampling the history will rest on.
$script:ProbeRunMaxBytes = 1.5MB   # au-dela, on ne garde que les passages recents
$script:ProbeRunKeepLines = 5000

function Write-ProbeRun {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Probe,
        [Parameter(Mandatory)][int]$Ms,
        # Where the run came from: 'forced' (the Refresh button), 'background' (a worker),
        # 'check' (the contract check).
        [string]$Origin = 'background',
        [ValidateSet('ok','error','empty')][string]$Outcome = 'ok',
        [int]$Modules = 0,
        [string]$Detail
    )
    try {
        $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'probe-runs.jsonl'
        $rec = [ordered]@{
            at      = [datetime]::UtcNow.ToString('o')
            probe   = $Probe
            ms      = $Ms
            origin  = $Origin
            outcome = $Outcome
            modules = $Modules
        }
        if ($Detail) { $rec.detail = $Detail }
        $line = ($rec | ConvertTo-Json -Compress -Depth 4)

        $mx = New-Object System.Threading.Mutex($false, 'Local\VigieProbeRuns')
        $got = $false
        try {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if (-not $got) { return }

            [IO.File]::AppendAllText($file, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

            # A lazy purge: the file is only read when it has really grown.
            $fi = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
            if ($fi -and $fi.Length -gt $script:ProbeRunMaxBytes) {
                $lines = [IO.File]::ReadAllLines($file)
                if ($lines.Count -gt $script:ProbeRunKeepLines) {
                    $garde = $lines[($lines.Count - $script:ProbeRunKeepLines)..($lines.Count - 1)]
                    [IO.File]::WriteAllLines($file, $garde, [Text.UTF8Encoding]::new($false))
                }
            }
        } finally {
            if ($got) { try { $mx.ReleaseMutex() } catch { } }
            try { $mx.Dispose() } catch { }
        }
    } catch {
        # The log must NEVER make a probe fail: it observes, it does not arbitrate.
    }
}
