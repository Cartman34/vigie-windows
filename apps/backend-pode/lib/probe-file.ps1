# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, paths, var
<#
    Intent: WHAT A PROBE FILE DECLARES, read without running it: whether it keeps one result per account, the key its result is filed under, the stamp of its newest result, and the delay that applies to it right now. Questions only -- erasing a result or recording a run is probes.ps1.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
