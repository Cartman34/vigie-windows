# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, log, measures, operations, paths, settings, var
<#
    Intent: THE MECHANISM OF A WATCH, WHICH KNOWS NO WATCH: what each unit declares as a sentinel, where the loop keeps its last reading, how a change becomes a sample, and the wrapper that marks a task as busy, times it and reports an overrun. Wrapping a new task in it is all there is to do; WHICH watches run is watches.ps1.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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

# A sentinel's history identifier. ONE single place builds it: the reading and the writing
# cannot drift apart.
function Get-SentinelMeasureId {
    param([Parameter(Mandatory)][string]$Key)
    return ('watch.' + $Key)
}
