# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: card-shape, games, log, paths, probe-cache, probe-run, probes, rights, scheduler, settings, version
<#
    Intent: THE STATE THE PANEL READS: every card gathered in one answer, served from the cache or recomputed, with what each probe cost. It sits at the top of the graph without being put there -- it calls everything, and nothing calls it.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

function Get-State {
    param(
        [string]$Backend = (Get-BackendRoot),
        [switch]$Force,
        # Seconds to wait for the recomputation lock. 0 means give up if a computation is
        # already running. Only an EXPLICIT request from the user waits; the background
        # refresh gives up, or the workers pile up blocking one another.
        [int]$WaitSeconds = 0,
        <#
            WHO ARE WE COMPUTING FOR? A card that names its reader has one cache entry per
            account. The background refresh runs with no session: it did not know who to keep
            its result for, so those cards were left out of the deferred work and recomputed
            INSIDE each request -- 2 seconds for the accounts, 5 for the deployment, at every
            display.

            So it is told who. The account travels all the way to the worker, which writes
            under the right key, and nothing forces a computation while somebody waits.
        #>
        [string]$Account,
        # A TARGETED RECOMPUTATION: the identifier of the module whose values must be fresh,
        # and OF THAT ONE ONLY. It is what a card's "Refresh" button asks for: to be given
        # the recomputed result, and not the last known value while a background refresh
        # lags behind -- seen on the Gaming card, which announced "no game" while the probe
        # already saw the game under way.
        [string]$ForceModule = '',
        <#
            THE PROBES TO RECOMPUTE, AND THOSE ALONE.

            The background refresh called Get-State -Force: it recomputed ALL SEVENTEEN
            probes, including the ones just done. A full pass takes a minute and a half --
            lock 11 s, gaming 14 s, deployment 13 s -- and during that time the others' delays
            expire: the next request deferred again, started another full pass, and the
            machine never stopped. Measured on 31/08 in state_20260831.log: passes chaining
            without a break, and a /state taking 27 seconds.

            So it is given the exact list of what is stale.
        #>
        [string[]]$Only = @()
    )
    $cacheFile = Get-ProbeCacheFile -Backend $Backend
    <#
        THE WHOLE RESPONSE IS TIMED, NOT ONLY THE CARDS.

        The per-card detail gave 140 ms while the response took several SECONDS: the time was
        elsewhere -- reading the cache, walking the probes, the module catalogue -- and showed
        nowhere. A partial stopwatch is worse than none: it acquits what it does not measure.

        Every phase is measured, returned in "timings" and written to the log.
    #>
    $tPhase = [Diagnostics.Stopwatch]::StartNew()
    $phases = [ordered]@{}
    $markPhase = {
        param([string]$phaseName)
        $phases[$phaseName] = [math]::Round($tPhase.Elapsed.TotalMilliseconds, 1)
        $tPhase.Restart()
    }

    $cache = Get-ProbeCache -Path $cacheFile
    & $markPhase 'lecture-cache'

    $targetedProbes = @(Get-TargetedProbes -Backend $Backend -Cache $cache -Only $Only -ForceModule $ForceModule)
    & $markPhase 'ciblage'

    $probeFiles = @(Get-ActiveProbeFiles -Backend $Backend)
    # WHO IS ASKING: the cards that name their reader have their own entry per account.
    $stateRequester = $(if ($PSBoundParameters.ContainsKey('Account')) { $Account } else { Get-RequesterAccount })
    # THE GAME MODE, read once per pass: during a game, the cards that do not watch it space themselves out.
    $inGame = [bool](Get-GameModeName -Backend $Backend)
    $stale = @(Get-StaleProbes -Backend $Backend -Cache $cache -ProbeFiles $probeFiles -Account $stateRequester `
                               -Targeted $targetedProbes -Force:$Force -InGame:$inGame)

    <#
        NOTHING IS COMPUTED BECAUSE SOMEONE IS LOOKING (D124, and the owner said it again on 29/09: he expects
        EVERY computation to happen in the background, asynchronously).

        A request serves the cache, always. What has to be computed is computed by the scheduler, at the interval
        each module declares, whether a session is open or not. Two exceptions, and they are not requests:

          - "-Only", which is the background worker itself saying WHICH computation it is running;
          - a card asked for explicitly ("-ForceModule", the refresh button), which no longer computes here
            either: it is marked due, the scheduler takes it within thirty seconds, and the panel reads the
            result when it is written.

        The old version recomputed all seventeen every time: the delays of the others expired during the pass, the
        next request started another one, and the machine never stopped -- /state at 27 seconds (measured on
        31/08).
    #>
    if (-not $Force -and $stale.Count -gt 0) {
        if ($Only -and @($Only).Count) {
            $stale = @($stale | Where-Object { ($targetedProbes -contains $_.Key) -or ($targetedProbes -contains $_.Name) })
        } else {
            if ($targetedProbes.Count) {
                try {
                    Reset-RefreshDue -Backend $Backend -Probes @(
                        $stale | Where-Object { ($targetedProbes -contains $_.Key) -or ($targetedProbes -contains $_.Name) } |
                                 ForEach-Object { $_.Name })
                } catch { }
            }
            $stale = @()
        }
    }

    if ($stale.Count -gt 0) {
        # Where the run came from, for the log: an explicit request waits (WaitSeconds > 0 or -Force), and the
        # rest is a background refresh.
        $origine = if ($Force -or $ForceModule -or $WaitSeconds -gt 0) { 'forced' } else { 'background' }
        Invoke-StaleProbes -Backend $Backend -Stale $stale -CacheFile $cacheFile -Cache $cache `
                           -Account $stateRequester -Origin $origine -WaitSeconds $WaitSeconds
    }

    <#
        WHAT EACH CARD COSTS IS MEASURED. Not the total: the detail.

        "I want to see what takes time to load, card by card." Without that, a slow /state is
        a single figure from which nothing can be deduced -- it took a day to find that the 28
        seconds came from a rights check, and not from the probes everyone suspected.

        The time is carried by the card itself (the "ms" field) and summarised in the "state"
        log. It counts the SERVICE: reading the cache, the state of the operations, the rights
        of the actions -- everything happening while the page waits.
    #>
    & $markPhase 'fraicheur'
    $modules = @()
    $chrono = @{}
    $refreshByCard = Get-CardRefreshInfo -Backend $Backend -Account $stateRequester
    foreach ($pf in $probeFiles) {
        $t = [Diagnostics.Stopwatch]::StartNew()
        $e = $cache[(Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester)]
        $t.Stop()
        # HELD BACK? The pace travels with the card, computed here so that no probe has to know about it: the
        # interface says it in the card's header, and only on the cards actually slowed down.
        $pace = Get-ProbePace -Backend $Backend -Name $pf.Name -InGame:$inGame
        if (-not ($e -and $e.module)) { continue }
        foreach ($mm in @($e.module)) {
            $modules += $mm
            if ($mm -and $mm.id) { $chrono["$($mm.id)"] = [double]$t.Elapsed.TotalMilliseconds }
            if ($mm -and $pace.HeldBack) { Set-CardValue -Card $mm -Key 'pace' -Value @{ seconds = $pace.Seconds; reason = 'jeu' } }
            if ($mm -and $mm.id) {
                Add-CardFreshness -Card $mm -Backend $Backend -ProbeName $pf.Name -Entry $e `
                                  -Declaration (@($refreshByCard["$($mm.id)"])[0])
            }
            # TO BE RECOMPUTED: the card shows, and says it is waiting for its measurement.
            if ($mm -and $e.pending) { Set-CardValue -Card $mm -Key 'pending' -Value $true }
        }
    }

    & $markPhase 'assemblage'
    # A PROBE ALWAYS HAS ITS CARD, WITHOUT EXCEPTION: one that has never produced anything gets a waiting card
    # rather than leaving a hole in the page.
    $known = @($modules | ForEach-Object { "$($_.id)" })
    foreach ($pf in $probeFiles) {
        $unit = Split-Path (Split-Path $pf.FullName -Parent) -Leaf
        if ($known -contains $unit) { continue }
        $e = $cache[(Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester)]
        if ($e -and $e.module) { continue }
        $modules += (New-PendingCard -ProbeFile $pf.FullName)
        $chrono[$unit] = 0
    }

    foreach ($m in $modules) {
        if (-not $m -or -not $m.id) { continue }
        Add-CardBusy -Card $m -Backend $Backend
    }
    foreach ($m in $modules) { Add-CardFixActions -Card $m -Backend $Backend }
    foreach ($m in $modules) {
        $rightsMs = Add-CardRights -Card $m -Backend $Backend
        if ($m -and $m.id) {
            $ms = [math]::Round(([double]$chrono["$($m.id)"] + $rightsMs), 1)
            $chrono["$($m.id)"] = $ms
            Set-CardValue -Card $m -Key 'ms' -Value $ms
        }
    }

    & $markPhase 'chronometrage'
    # THE DETAIL, IN THE LOG: one line, sorted from the slowest to the quickest.
    try {
        $timingLines = @($chrono.GetEnumerator() | Sort-Object Value -Descending |
                          ForEach-Object { "$($_.Key)=$($_.Value)ms" })
        if ($timingLines.Count) {
            Write-Log -Backend $Backend -Name 'state' -NoEcho `
                      -Message ("service par carte : " + ($timingLines -join ' '))
            Write-Log -Backend $Backend -Name 'state' -NoEcho `
                      -Message ("phases : " + (($phases.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)ms" }) -join ' '))
        }
    } catch { }

    & $markPhase 'droits-et-operations'
    $present = @($modules | Select-Object -ExpandProperty theme -Unique)
    $themes  = @($script:ThemeCatalog | Where-Object { $present -contains $_.id })
    # THE MODULE CATALOGUE was taken out of the object so it could be MEASURED: as long as
    # it was written inside the final construction, its cost drowned in "the rest".
    $unites = @(Get-UnitCatalog -Backend $Backend)
    & $markPhase 'catalogue-modules'
    # THE REST: version, build stamp, machine name. Measured too, or "the rest" becomes the
    # place where time hides again.
    $version = (Get-AppVersion -Backend $Backend)
    $build   = (Get-AppBuildId -Backend $Backend)
    & $markPhase 'identite-de-version'

    [pscustomobject][ordered]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        version     = $version
        build       = $build
        host        = "$env:COMPUTERNAME"
        themes      = $themes
        modules     = @($modules)
        # THE DETAIL OF THE TIME, in the response: what is not measured gets suspected.
        timings     = $phases
        # ALL the folder-modules, disabled ones included (D48): that is what lets the
        # management view offer to switch back on what is no longer displayed.
        units       = $unites
    }
}
