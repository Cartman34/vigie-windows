# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, paths, probe-file, settings, store, var
<#
    Intent: WHAT THE PROBES HAVE ALREADY PRODUCED, AND HOW OLD IT IS: the file where every probe's last answer is
    kept, which probe answers for a given card, which entries have gone stale against the delay each one
    declares, and writing one entry back without touching the others. It answers questions about the cache and
    computes nothing.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# NOBODY AGES MORE THAN A DAY (the owner, 01/09): every card recomputes itself from time to time, at least once
# a day, and never all of them at once. "Never all" is held by the scheduler, which takes one per pass; "at least
# once a day" is held here. Without it a generous delay -- the accounts are at one hour -- would let a card stay
# for days on a false measurement if nobody looked at it.
$script:ProbeCacheMaxTtl = 86400
$script:ProbeCacheDefaultTtl = 30

function Get-ProbeCacheFile {
    param([Parameter(Mandatory)][string]$Backend)
    $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
    $dir = Split-Path $file -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $file
}

# THE CACHE AS IT STANDS. It is loaded ALWAYS, even when everything is to be recomputed: forcing means
# "recompute", not "forget everything". Starting from an empty cache made the cards disappear one by one from the
# file during a recomputation, and a simultaneous reader received a TRUNCATED state.
function Get-ProbeCache {
    param([Parameter(Mandatory)][string]$Path)
    $cache = @{}
    if (Test-Path $Path) {
        try {
            $j = Get-Content $Path -Raw | ConvertFrom-Json
            foreach ($pr in $j.PSObject.Properties) { $cache[$pr.Name] = $pr.Value }
        } catch { }
    }
    return $cache
}

# ONE ENTRY, WRITTEN MERGED.
#
# The whole file used to be rewritten from the in-memory copy: two simultaneous recomputations -- a forced
# request and the background refresh -- clobbered each other, and an entry already corrected went back to its old
# value, so a card in error rose again after being fixed. Rewriting ONLY the probe just computed removes the race.
#
# Depth 24: a card may carry a TREE (the disk analysis). At the default depth, ConvertTo-Json truncates IN
# SILENCE and the deep branches reach the interface EMPTY -- seen on 26/08, lines with neither name nor size.
function Set-ProbeCacheEntry {
    # The entry may be EMPTY: a probe that answered nothing leaves the key as it stood, and that write is the one
    # that says so. A mandatory parameter would refuse it, where the old code wrote it without blinking.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Key, $Entry)
    try { Update-StateJson -Path $Path -Set @{ $Key = $Entry } -Depth 24 | Out-Null } catch { }
}

function New-ProbeCacheEntry {
    param([Parameter(Mandatory)]$Module, [Parameter(Mandatory)][string]$Stamp)
    return [ordered]@{ module = $Module; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $Stamp }
}

# THE PROBE FILES THAT TAKE PART, the switched-off modules left out (D48): their probes leave the computation AND
# the display. The filter works on the PARENT FOLDER -- a module is a folder.
function Get-ActiveProbeFiles {
    param([Parameter(Mandatory)][string]$Backend)
    $probesDir = Join-Path $Backend 'probes'
    $files = @(Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -ErrorAction SilentlyContinue | Sort-Object FullName)
    $off = @(Get-InactiveUnits -Backend $Backend)
    if ($off.Count -gt 0) {
        $files = @($files | Where-Object { $off -notcontains (Split-Path (Split-Path $_.FullName -Parent) -Leaf) })
    }
    return $files
}

<#
    WHICH PROBE ANSWERS FOR THE CARD AIMED AT?

    The cache says so: each entry carries the module the probe returned, or its array of modules. "-Only" aims at
    probes by their FILE NAME, as a card's button aims at a card: both feed the same list, and there is only one
    mechanism.

    THE CACHE DOES NOT KNOW EVERYTHING: IT ONLY KNOWS WHAT IT HAS ALREADY SEEN. That correspondence was read from
    the cache alone. A card never computed does not appear there, so its button aimed at NOTHING: the response
    came back 200, with no field, still "not measured yet", and the card could never fill again -- not by its
    button, not by the page, not by the installation. Measured on 01/09. The probe's folder carries its card's
    name: when the cache does not answer, the disk is asked, and it always knows.
#>
function Get-TargetedProbes {
    param(
        [Parameter(Mandatory)][string]$Backend,
        [Parameter(Mandatory)][hashtable]$Cache,
        [string[]]$Only = @(),
        [string]$ForceModule = ''
    )
    $targeted = @()
    foreach ($n in @($Only)) { if ("$n".Trim()) { $targeted += "$n".Trim() } }
    if (-not $ForceModule) { return $targeted }
    foreach ($probeName in @($Cache.Keys)) {
        $e = $Cache[$probeName]
        if (-not $e -or -not $e.module) { continue }
        foreach ($mm in @($e.module)) {
            if ("$($mm.id)" -eq $ForceModule) { $targeted += "$probeName" }
        }
    }
    if (-not $targeted.Count) {
        $probeDir = Join-Path (Join-Path $Backend 'probes') $ForceModule
        if (Test-PathSafe $probeDir) {
            foreach ($pf in @(Get-ChildItem -LiteralPath $probeDir -Filter '*.probe.ps1' -File -ErrorAction SilentlyContinue)) {
                $targeted += $pf.Name
            }
        }
    }
    return $targeted
}

<#
    WHICH ENTRIES HAVE GONE STALE, AND HOW LATE EACH ONE IS.

    The age is computed ENTIRELY in UTC. The date is written in UTC; it used to be compared with the LOCAL time.
    On a machine at UTC+2 every entry therefore looked two hours old: not one was ever judged fresh, the cache was
    useless, and every call recomputed the twelve probes -- some twenty seconds, ten of them for the `lock` probe
    alone.

    HOW LATE, RELATIVE TO ITS OWN DELAY, is what decides which goes first: a network card valid for 15 s is five
    times later than a system card valid for an hour at the same instant.
#>
function Get-StaleProbes {
    param(
        [Parameter(Mandatory)][string]$Backend,
        [Parameter(Mandatory)][hashtable]$Cache,
        [Parameter(Mandatory)]$ProbeFiles,
        [string]$Account = '',
        [string[]]$Targeted = @(),
        [switch]$Force,
        [switch]$InGame
    )
    $nowUtc = [datetime]::UtcNow
    $stale = @()
    foreach ($pf in $ProbeFiles) {
        $name = $pf.Name
        $stamp = "$($pf.LastWriteTimeUtc.Ticks)"
        $key = Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $Account
        $ttl = Get-ProbeTtlNow -Name $name -Default $script:ProbeCacheDefaultTtl -Backend $Backend -InGame:$InGame
        if ($ttl -gt $script:ProbeCacheMaxTtl) { $ttl = $script:ProbeCacheMaxTtl }
        $entry = $Cache[$key]
        $fresh = $false
        # Forcing makes everything stale, without erasing anything. A probe AIMED AT is stale by definition: that
        # is the whole meaning of the request.
        if (-not $Force -and ($Targeted -notcontains $key) -and ($Targeted -notcontains $name) -and
            $entry -and $entry.at -and ("$($entry.codeStamp)" -eq $stamp)) {
            try {
                $at = ConvertTo-UtcDate $entry.at
                if ($at -and ($nowUtc - $at).TotalSeconds -lt $ttl) { $fresh = $true }
            } catch { }
        }
        if ($fresh) { continue }
        $age = $ttl + 1
        try { if ($entry -and $entry.at) { $age = ($nowUtc - (ConvertTo-UtcDate $entry.at)).TotalSeconds } } catch { }
        $stale += [pscustomobject]@{
            File = $pf.FullName; Name = $name; Key = $key; Stamp = $stamp
            Overdue = $(if ($ttl -gt 0) { $age / $ttl } else { $age })
            PerAccount = (Test-ProbeIsPerAccount -ProbeFile $pf.FullName)
        }
    }
    return $stale
}

# THE PACE THAT APPLIES NOW, AND THE ONE THAT USUALLY APPLIES. A card is said to be held back only when it
# matters: twice its usual pace AND at least two minutes. Saying "held back" for twenty seconds instead of
# fifteen would be noise on every card of a game session.
function Get-ProbePace {
    param([Parameter(Mandatory)][string]$Backend, [Parameter(Mandatory)][string]$Name, [switch]$InGame)
    $now  = Get-ProbeTtlNow -Name $Name -Default $script:ProbeCacheDefaultTtl -Backend $Backend -InGame:$InGame
    $base = Get-ProbeTtlNow -Name $Name -Default $script:ProbeCacheDefaultTtl -Backend $Backend -Base
    return [pscustomobject]@{ Seconds = $now; Base = $base; HeldBack = ($now -ge [Math]::Max(120, 2 * $base)) }
}
