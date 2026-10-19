# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, paths, scheduler, var
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

<#
    IS A CARD THE SAME FOR EVERYONE?

    Most are: disk space, updates and the firewall do not depend on who is looking. But the
    accounts card marks one name as being the reader's own -- and that rendering goes into
    state-cache.json, which is SHARED. So the first person to open Vigie left that mark
    there, and it was served to everyone else.

    A probe declares it in its module.psd1:  PerAccount = $true.

    Declaring beats guessing: one cannot read inside a rendering to tell whether it depends on
    the person, and assuming it for all of them would cost one recomputation per account for
    nothing. check-probes verifies that the ones speaking of the requester have declared it.
#>
$script:ProbePerAccount = @{}
function Test-ProbeIsPerAccount {
    param([Parameter(Mandatory)][string]$ProbeFile)
    $folder = Split-Path $ProbeFile -Parent
    if ($script:ProbePerAccount.ContainsKey($folder)) { return $script:ProbePerAccount[$folder] }
    $answer = $false
    try {
        $decl = Join-Path $folder 'module.psd1'
        if (Test-Path -LiteralPath $decl) {
            $d = Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop
            $answer = [bool]$d.PerAccount
        }
    } catch { }
    $script:ProbePerAccount[$folder] = $answer
    return $answer
}

<#
    THE CACHE KEY: the probe's name, and the account when the rendering depends on it.

    "accounts.probe.ps1@Famille" and "accounts.probe.ps1@fhaza" live side by side in the same
    file without treading on each other. With no requester identified the key is "@?": an
    anonymous session has an entry of its own, where nobody is the reader.
#>
function Get-ProbeCacheKey {
    param([Parameter(Mandatory)][string]$ProbeFile, [string]$Account)
    $leaf = Split-Path $ProbeFile -Leaf
    if (-not (Test-ProbeIsPerAccount -ProbeFile $ProbeFile)) { return $leaf }
    return ($leaf + '@' + $(if ($Account) { $Account } else { '?' }))
}

<#
    WHEN WAS THIS COMPUTATION'S RESULT LAST WRITTEN? The scheduler needs it to tell a computation that FAILED from one
    that merely returned a card in error: a card saying "no internet" is a result, an exception is not. Get-State
    swallows a probe's error to keep serving the others, so the proof of a failure is that the cache did not move.
#>
function Get-ProbeCacheStamp {
    # ACCOUNT: the entry of THAT account alone. The scheduler now computes per account for a per-account probe, so
    # the proof that ITS computation wrote something is its own entry, not the newest of all.
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Probe, [string]$Account)
    try {
        $path = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
        if (-not (Test-PathSafe $path)) { return '' }
        <#
            THE MOST RECENT OF THE MATCHING ENTRIES, never the first one met.

            A probe whose rendering depends on who looks has ONE entry PER ACCOUNT (D109): accounts.probe.ps1@fhaza,
            accounts.probe.ps1@Famille. The scheduler computes with no requester, so it writes its own entry -- and
            this function was answering with whichever entry came first in the file. It was therefore comparing the
            stamp of SOMEONE ELSE'S entry before and after, saw it unchanged, and the worker concluded "the
            computation wrote nothing". Measured on 30/09: the accounts card had failed eight times in a row that
            way, while its computation was working perfectly.

            The proof that a computation wrote something is that the NEWEST stamp moved, whoever it belongs to.
        #>
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $newest = $null
        $newestAt = $null
        foreach ($pr in $j.PSObject.Properties) {
            $name = "$($pr.Name)"
            if ($Account) {
                if ($name -ne ($Probe + '@' + $Account)) { continue }
            } elseif (-not ($name -eq $Probe -or $name.StartsWith($Probe + '@'))) { continue }
            $raw = "$($pr.Value.at)"
            if (-not $raw) { continue }
            $when = $null
            try { $when = ConvertTo-UtcDate $raw } catch { }
            if (-not $when) { if (-not $newest) { $newest = $raw }; continue }
            if (-not $newestAt -or $when -gt $newestAt) { $newestAt = $when; $newest = $raw }
        }
        if ($newest) { return $newest }
    } catch { }
    return ''
}

$script:GameModeFloor  = 900      # the other cards: a quarter of an hour at least
$script:GameModeHeavyTtl = 3600   # the heavy ones: one hour

# A probe's cache duration at this instant, game mode included. With no game running, it is the table below.
# -Base gives the duration OUTSIDE any game: comparing the two says whether a card is held back, and the card then
# says so itself rather than leaving the reader with a figure quietly twenty minutes old (28/09).
function Get-ProbeTtlNow {
    param([Parameter(Mandatory)][string]$Name, [int]$Default = 30, [string]$Backend = (Get-BackendRoot), [switch]$InGame, [switch]$Base)
    if ($Base) { return $(if ($script:ProbeTtls.ContainsKey($Name)) { [int]$script:ProbeTtls[$Name] } else { $Default }) }
    $ttl = $(if ($script:ProbeTtls.ContainsKey($Name)) { [int]$script:ProbeTtls[$Name] } else { $Default })
    # THE STORAGE CARD FOLLOWS ITS ANALYSIS: while the scan writes its progress, the card must show it moving.
    if ($Name -eq 'disk.probe.ps1') {
        try {
            $scanFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan.json'
            if ((Test-PathSafe $scanFile) -and (([datetime]::UtcNow - (Get-Item -LiteralPath $scanFile).LastWriteTimeUtc).TotalMinutes -lt 2)) { return 5 }
        } catch { }
    }
    if (-not $InGame) { return $ttl }
    if ($script:GameModeUseful.ContainsKey($Name)) { return [Math]::Max($ttl, [int]$script:GameModeUseful[$Name]) }
    if ($script:GameModeHeavy -contains $Name) { return [Math]::Max($ttl, $script:GameModeHeavyTtl) }
    return [Math]::Max($ttl * 20, $script:GameModeFloor)
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
