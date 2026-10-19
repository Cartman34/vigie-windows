# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: contract, format, games, log, measures, operations, paths, probes, rights, scheduler, server-process, settings, store, var, version
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
        # Capped below the client's own delay (90 s): waiting longer than it does would mean
        # working for a request already abandoned.
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
    $probesDir = Join-Path $Backend 'probes'
    $cacheFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
    $stateDir  = Split-Path $cacheFile -Parent
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    <#
        NOBODY AGES MORE THAN A DAY.

        The rule, from the owner on 01/09: every card recomputes itself from time to time, at
        least once a day, and never all of them at once. The "never all" is held by the
        background refresh, which takes only ONE per response; the "at least once a day" is
        held here, by this ceiling.

        Without it, a generous delay would be enough -- the accounts are at one hour -- for a
        card to stay for days on a false measurement if nobody looks at it.
    #>
    $maxTtl = 86400
    $defaultTtl = 30

    # Loads the existing cache. ALWAYS, even with -Force: forcing means "recompute", not
    # "forget everything". Starting from an empty cache made the modules disappear one by one
    # from the file during the recomputation, and a simultaneous reader received a TRUNCATED
    # state -- a card vanished for the length of the refresh.
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

    $cache = @{}
    if (Test-Path $cacheFile) {
        try { $j = Get-Content $cacheFile -Raw | ConvertFrom-Json; foreach ($pr in $j.PSObject.Properties) { $cache[$pr.Name] = $pr.Value } } catch { }
    }
    & $markPhase 'lecture-cache'

    # Which probe produces the module aimed at? The cache says so: each entry carries the
    # module the probe returned, or its array of modules.
    # "-Only" aims at probes by their FILE NAME, as "-ForceModule" aims at a card: both feed
    # the same list, and there is only one mechanism.
    $targetedProbes = @()
    foreach ($n in @($Only)) { if ("$n".Trim()) { $targetedProbes += "$n".Trim() } }
    if ($ForceModule) {
        foreach ($probeName in @($cache.Keys)) {
            $e = $cache[$probeName]
            if (-not $e -or -not $e.module) { continue }
            foreach ($mm in @($e.module)) {
                if ("$($mm.id)" -eq $ForceModule) { $targetedProbes += "$probeName" }
            }
        }
        <#
            THE CACHE DOES NOT KNOW EVERYTHING: IT ONLY KNOWS WHAT IT HAS ALREADY SEEN.

            That card-to-probe correspondence was read ONLY from the cache. A card never
            computed does not appear there, so its button aimed at NOTHING: the response came
            back 200, with no field, still "not measured yet". The card could never fill
            again -- not by its button, not by the page, not by the installation. Measured on
            01/09: GET /modules/deployment?fresh=1 -> 200, 0 fields, pending still true.

            The probe's folder carries its card's name: when the cache does not answer, the
            disk is asked, and it always knows.
        #>
        if (-not $targetedProbes.Count) {
            $probeDir = Join-Path $probesDir $ForceModule
            if (Test-PathSafe $probeDir) {
                foreach ($pf in @(Get-ChildItem -LiteralPath $probeDir -Filter '*.probe.ps1' -File -ErrorAction SilentlyContinue)) {
                    $targetedProbes += $pf.Name
                }
            }
        }
    }

    # Probes and freshness (invalidation PER probe: the file's mtime plus its TTL)
    #
    # The age is computed ENTIRELY in UTC. The date is written in UTC (`ToUniversalTime`); it
    # used to be compared with `Get-Date`, which returns LOCAL time. On a machine at UTC+2
    # every entry therefore looked two hours old: not one was ever judged fresh, the cache was
    # useless, and every call to /state recomputed the twelve probes -- some twenty seconds,
    # ten of them for the `lock` probe alone.
    & $markPhase 'ciblage'
    $nowUtc = [datetime]::UtcNow
    $probeFiles = @(Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -ErrorAction SilentlyContinue | Sort-Object FullName)
    # Modules the user has switched off (D48): their probes leave the computation AND the
    # display. The filter works on the PARENT FOLDER -- a module is a folder.
    $unitsCoupees = @(Get-InactiveUnits -Backend $Backend)
    if ($unitsCoupees.Count -gt 0) {
        $probeFiles = @($probeFiles | Where-Object {
            $unitsCoupees -notcontains (Split-Path (Split-Path $_.FullName -Parent) -Leaf)
        })
    }
    # WHO IS ASKING: the cards that name their reader have their own entry per account.
    $stateRequester = $(if ($PSBoundParameters.ContainsKey('Account')) { $Account } else { Get-RequesterAccount })
    # THE PROBES ARE TOLD who this computation is for, just before each one runs (see Get-StateAccount): they take no
    # argument, and the scheduler has no cookie to read.
    # THE GAME MODE, read once per pass: during a game, the cards that do not watch it space themselves out.
    $inGame = [bool](Get-GameModeName -Backend $Backend)
    $stale = @()
    foreach ($pf in $probeFiles) {
        $name = $pf.Name; $stamp = "$($pf.LastWriteTimeUtc.Ticks)"
        $key = Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester
        $ttl = Get-ProbeTtlNow -Name $name -Default $defaultTtl -Backend $Backend -InGame:$inGame
        if ($ttl -gt $maxTtl) { $ttl = $maxTtl }
        $entry = $cache[$key]; $fresh = $false
        # -Force: everything is considered stale, without anything being erased.
        # A probe AIMED AT is stale by definition: that is the whole meaning of the request.
        if (-not $Force -and ($targetedProbes -notcontains $key) -and ($targetedProbes -notcontains $name) -and
            $entry -and $entry.at -and ("$($entry.codeStamp)" -eq $stamp)) {
            try {
                $at = ConvertTo-UtcDate $entry.at
                if ($at -and ($nowUtc - $at).TotalSeconds -lt $ttl) { $fresh = $true }
            } catch { }
        }
        if (-not $fresh) {
            # HOW LATE IS IT, RELATIVE TO ITS OWN DELAY? That is what decides which goes
            # first: a network card, valid for 15 s, is five times later than a system card
            # valid for an hour at the same instant.
            $age = $ttl + 1
            try { if ($entry -and $entry.at) { $age = ($nowUtc - (ConvertTo-UtcDate $entry.at)).TotalSeconds } } catch { }
            $stale += [pscustomobject]@{ File = $pf.FullName; Name = $name; Key = $key; Stamp = $stamp
                                         Overdue = $(if ($ttl -gt 0) { $age / $ttl } else { $age })
                                         PerAccount = (Test-ProbeIsPerAccount -ProbeFile $pf.FullName) }
        }
    }

    # Recomputation is SINGLE-FLIGHT: one thread recomputes at a time, and the other requests
    # serve the existing cache at once -- which avoids the herd effect, and the 408s with it.
    # SERVE FIRST, RECOMPUTE AFTERWARDS.
    #
    # A stale probe that ALREADY has a cached value must not keep the display waiting: the
    # known value is returned at once and the recomputation happens in the background. Only
    # the probes with NOTHING cached are computed inside the request -- otherwise there would
    # be nothing to show.
    #
    # Before, any staleness blocked the response: depending on the moment, opening Vigie took
    # from 0.3 s to more than 20 s, with nothing explaining the difference to the user.
    # The "Refresh" button (-Force) keeps its recomputation synchronous: that is exactly what
    # it is asked for.
    if (-not $Force -and $stale.Count -gt 0) {
        <#
            A DISPLAY KEEPS NOBODY WAITING.

            Neither the loading of the page nor the automatic polling: they serve what is
            cached, as it stands, and leave. A card not yet known does not display -- it will
            appear when someone has asked for it.

            The one exception is the probe AIMED AT: a card's button, or the refresh button at
            the top of the page, which recompute what they are pointed at. A recomputation is
            ASKED FOR; it does not start by itself because a date has expired.

            What happens BEHIND, on the other hand: one stale probe -- one only, per pass --
            leaves as a detached background task, so the value is ready next time. Nobody
            waits for it.

            The old version recomputed all seventeen every time: the delays of the
            others expired during the pass, the next request started another one, and the
            machine never stopped -- /state at 27 seconds (measured on 31/08).
        #>
        <#
            NOTHING IS COMPUTED BECAUSE SOMEONE IS LOOKING (D124, and the owner said it again on 29/09: he expects
            EVERY computation to happen in the background, asynchronously).

            A request serves the cache, always. What has to be computed is computed by the scheduler, at the interval
            each module declares, whether a session is open or not. Two exceptions, and they are not requests:

              - "-Only", which is the background worker itself saying WHICH computation it is running;
              - a card asked for explicitly ("-ForceModule", the refresh button), which no longer computes here
                either: it is marked due, the scheduler takes it within thirty seconds, and the panel reads the
                result when it is written.
        #>
        $targeted = { param($e) ($targetedProbes -contains $e.Key) -or ($targetedProbes -contains $e.Name) }
        $toRefresh = @()
        if ($Only -and @($Only).Count) {
            $stale = @($stale | Where-Object { (& $targeted $_) })
        } else {
            if ($targetedProbes.Count) {
                try { Reset-RefreshDue -Backend $Backend -Probes @($stale | Where-Object { (& $targeted $_) } | ForEach-Object { $_.Name }) } catch { }
            }
            $stale = @()
        }

        <#
            AND ONE SINGLE PROBE LEAVES AS A BACKGROUND TASK. Non-blocking, rare, per card.

            WHICH ONE? THE LATEST RELATIVE TO ITS OWN DELAY. Taking the first to hand ran all
            seventeen in single file: a network outage -- a card valid for 15 seconds --
            waited its turn behind cards valid for an hour, so a quarter of an hour before
            being seen. The ratio of age to delay puts each back in its place: what moves
            fast goes fast.

            The response is already built by the time we get here: nobody waits. ONE stale
            probe -- the first -- is handed to a detached process, which will recompute it and
            write the result for next time. That is how the Deployment card ends up seeing a
            commit without the page load paying for it.

            ONE only, and one at a time: recomputing all seventeen chained passes of a minute
            and a half that kept restarting one another.
        #>
        <#
            A BACKGROUND WORKER NEVER SPAWNS A BACKGROUND WORKER (29/09, and it cost 79 processes).

            This hand-off is for a REQUEST that found a stale probe. A worker also calls Get-State, so without this
            it hands off in turn, and each hand-off hands off again: the machine filled with pwsh processes within
            two minutes of the deployment. A detached worker carries VIGIE_NO_BACKGROUND and stops the chain here.

            The lock it used to test is per-probe now, so a global test proved nothing: we test the lock of the very
            probe we are about to hand off, which is the only one that matters.
        #>
        $chosen = "$(($toRefresh | Sort-Object Overdue -Descending | Select-Object -First 1).Name)"
        if ($toRefresh.Count -gt 0 -and -not $env:VIGIE_NO_BACKGROUND -and $chosen) {
            $alreadyRunning = $false
            try {
                $tmp = $null
                $lock = 'Local\VigieStateRecompute_' + ($chosen -replace '[^A-Za-z0-9]', '_')
                if ([System.Threading.Mutex]::TryOpenExisting($lock, [ref]$tmp)) {
                    $alreadyRunning = -not $tmp.WaitOne(0)
                    if (-not $alreadyRunning) { try { $tmp.ReleaseMutex() } catch { } }
                    try { $tmp.Dispose() } catch { }
                }
            } catch { }
            if (-not $alreadyRunning) {
                try {
                    $w = Join-Path $Backend 'workers/state-refresh.worker.ps1'
                    $null = Start-DetachedAction -Script $w -Backend $Backend `
                                -ArgsMap @{ account = "$stateRequester"; probe = $chosen }
                } catch { }
            }
        }
    }

    if ($stale.Count -gt 0) {
        $slow  = @('lock.probe.ps1','pending.probe.ps1','wsl.probe.ps1')   # calculees en dernier
        $stale = @($stale | Sort-Object @{ Expression = { if ($slow -contains $_.Name) { 1 } else { 0 } } }, Name)
        <#
            ONE LOCK PER PROBE WHEN ONE PROBE IS COMPUTED (D124). A single global lock made the scheduler's limit a
            decoration: three launches would simply have queued behind each other. Computing SEVERAL probes still takes
            the shared lock -- that path is the explicit refresh, and it is the one that must not be run twice at once.
            A single-probe worker and a multi-probe refresh can therefore overlap on the same probe; it costs one
            wasted pass, and the cache write is protected file by file (Update-StateJson).
        #>
        $lockName = 'Local\VigieStateRecompute'
        if ($stale.Count -eq 1) { $lockName = 'Local\VigieStateRecompute_' + ($stale[0].Name -replace '[^A-Za-z0-9]', '_') }
        $mx = $null; $got = $false
        try {
            $mx = New-Object System.Threading.Mutex($false, $lockName)
            # An EXPLICIT request (-Force, the "Refresh" button) WAITS its turn; ordinary
            # requests do not wait and make do with the cache.
            # With WaitOne(0) for everyone, the button did nothing as soon as a background
            # refresh held the lock: it handed back at once.
            <#
                A PERSONAL CARD MUST BE COMPUTED NOW, or it never will be. The background
                refresh runs with no session: it writes under the anonymous key, never under
                "@<account>". If the request asking for it does not wait for the lock, its
                entry stays stale indefinitely -- seen on 30/08: the card announced v0.1.29-dev5
                while the installation was at v0.1.30, and two calls in a row gave the same
                answer.

                So for those cards we wait our turn, even without an explicit request.
            #>
            $personnelles = @($stale | Where-Object { $_.PerAccount }).Count
            $secondes = [Math]::Max($WaitSeconds, $(if ($personnelles) { 30 } else { 0 }))
            $waitMs = [Math]::Min($secondes, 75) * 1000
            try { $got = $mx.WaitOne($waitMs) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if ($got) {
                # Where the run came from, for the log: an explicit request waits
                # (WaitSeconds > 0 or -Force), and the rest is a background refresh.
                $origine = if ($Force -or $ForceModule -or $WaitSeconds -gt 0) { 'forced' } else { 'background' }
                foreach ($sp in $stale) {
                    $t0 = Get-Date
                    try {
                        # FOR WHOM, said just before the probe runs and taken back just after: a probe dot-sources
                        # this library itself, so nothing else reaches it (D128).
                        $global:VigieStateAccount = $stateRequester
                        $m = & $sp.File
                        $elapsedMs = [int]((Get-Date) - $t0).TotalMilliseconds
                        if ($m) { $cache[$sp.Key] = [ordered]@{ module = $m; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp } }
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms $elapsedMs -Origin $origine -Outcome ($(if ($m) { 'ok' } else { 'empty' })) -Modules @($m).Count
                        Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'common.sonde-recalculee-ms' $sp.Name $elapsedMs)
                        # History: samples the catalogue's measurements AFTER a successful
                        # recomputation. Best effort -- the function never fails.
                        if ($m) { Write-MeasureSamples -Backend $Backend -Probe $sp.Name -Modules @($m) }
                    } catch {
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms ([int]((Get-Date) - $t0).TotalMilliseconds) -Origin $origine -Outcome 'error' -Detail $_.Exception.Message
                        Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (Get-Label 'common.sonde-erreur' $sp.Name $_.Exception.Message)
                        <#
                            AN ERROR LOOKS LIKE EVERYTHING ELSE.

                            The failure card was called "accounts.probe.ps1" and landed under
                            "Systeme": a file's name, in the wrong group. Nobody knows which
                            card that corresponds to, and it is exactly the moment one needs
                            to know.

                            The probe's folder IS its module -- probes/<unit>/ -- and its
                            module.psd1 carries the label displayed. That is used: the card
                            keeps its place and its name, and says what failed.
                        #>
                        $unit = Split-Path (Split-Path $sp.File -Parent) -Leaf
                        $label = $unit
                        try {
                            $decl = Join-Path (Split-Path $sp.File -Parent) 'module.psd1'
                            if (Test-Path -LiteralPath $decl) {
                                $d = Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop
                                if ($d.Label) { $label = "$($d.Label)" }
                            }
                        } catch { }
                        # SCOPE 'machine': a probe that threw says so to everyone. The failure is the computer's,
                        # not an account's -- and the card it replaces may have had either scope.
                        $errMod = New-ModuleObject -Id $sp.Name -Theme $unit -Label $label -Scope 'machine' -Status 'error' -Fields @(
                            New-Field -Key 'error' -Label 'Erreur' -Value $_.Exception.Message -Kind 'text' -Status 'error'
                            New-Field -Key 'probe' -Label 'Sonde' -Value $sp.Name -Kind 'text'
                        )
                        $cache[$sp.Key] = [ordered]@{ module = $errMod; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp }
                    }
                    # Written MERGED, entry by entry, under a mutex (Update-StateJson).
                    #
                    # The whole file used to be rewritten from the in-memory copy: two
                    # simultaneous recomputations -- the forced request and the background
                    # refresh -- clobbered each other, and an entry already corrected went
                    # back to its old value: a card in error rose again after being fixed.
                    # Rewriting ONLY the probe just computed removes the race.
                    # -Depth 24: a card may carry a TREE (the disk analysis).
                    # At the default depth (8), ConvertTo-Json truncates IN SILENCE and the
                    # deep branches reach the interface EMPTY -- seen on 26/08: lines with
                    # neither name nor size under every folder.
                    try { Update-StateJson -Path $cacheFile -Set @{ $sp.Key = $cache[$sp.Key] } -Depth 24 | Out-Null } catch { }
                }
            }
        } finally {
            # AND IT IS TAKEN BACK. A global left behind would answer for the next computation, which may be for
            # somebody else or for nobody.
            $global:VigieStateAccount = $null
            if ($got -and $mx) { try { $mx.ReleaseMutex() } catch { } }
            if ($mx) { try { $mx.Dispose() } catch { } }
        }
    }

    # Assembles the modules from the cache, in the order of the probe files.
    # A probe may return ONE module or an ARRAY of modules (flattened here).
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
    <#
        WHAT THE SCHEDULER KNOWS ABOUT EACH CARD, read ONCE for all of them (S16).

        A value twenty-two hours old looked exactly like a value from this second: nothing, on the card or in the
        contract, told them apart. A card now carries what is needed to know -- when the probe produced what it
        shows, when the scheduler last passed, and the interval that applies -- plus its consecutive failures,
        without which it serves its last successful value in silence.

        Read per card, this would be twenty readings of the same state file for one page.
    #>
    $refreshByCard = @{}
    try {
        $refreshState = Get-RefreshState -Backend $Backend
        $refreshModes = @(Get-ActiveModes -Backend $Backend)
        foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
            $entry = $refreshState[$d.Key]
            $info = [pscustomobject]@{
                Seconds   = (Get-RefreshInterval -Declaration $d -Modes $refreshModes)
                # THE TICKS ARE UTC, and a date built on them is born "unspecified": handed over as is, the page
                # would read it as local time and show a two-hour gap (D44).
                EndedAt   = $(if ($entry -and [long]$entry.lastEndedAt) { ([datetime]::new([long]$entry.lastEndedAt, [DateTimeKind]::Utc)).ToString('o') } else { '' })
                Fails     = $(if ($entry) { [int]$entry.fails } else { 0 })
                LastError = $(if ($entry) { "$($entry.lastError)" } else { '' })
                # STARTED BUT NEVER FINISHED is not the same breakdown as NEVER STARTED, and both looked alike:
                # a card that stops moving, with no failure counted. So the start is said too.
                StartedAt = $(if ($entry -and [long]$entry.lastStartedAt) { ([datetime]::new([long]$entry.lastStartedAt, [DateTimeKind]::Utc)).ToString('o') } else { '' })
            }
            # A per-account card has one declaration per account: the requester's is the one that concerns it.
            if ($d.Account -and "$($d.Account)" -ne "$stateRequester") { continue }
            foreach ($card in @($d.Cards)) {
                if (-not $card) { continue }
                if (-not $refreshByCard.ContainsKey("$card")) { $refreshByCard["$card"] = @() }
                $refreshByCard["$card"] += $info
            }
        }
    } catch { }
    foreach ($pf in $probeFiles) {
        $t = [Diagnostics.Stopwatch]::StartNew()
        $e = $cache[(Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester)]
        $t.Stop()
        # HELD BACK? The pace travels with the card, computed here so that no probe has to know about it: the
        # interface says it in the card's header, and only on the cards actually slowed down.
        $paceNow  = Get-ProbeTtlNow -Name $pf.Name -Default $defaultTtl -Backend $Backend -InGame:$inGame
        $paceBase = Get-ProbeTtlNow -Name $pf.Name -Default $defaultTtl -Backend $Backend -Base
        if ($e -and $e.module) {
            foreach ($mm in @($e.module)) {
                $modules += $mm
                if ($mm -and $mm.id) { $chrono["$($mm.id)"] = [double]$t.Elapsed.TotalMilliseconds }
                # MARKED ONLY WHEN IT MATTERS: twice its usual pace AND at least two minutes. Saying "held back" for
                # twenty seconds instead of fifteen would be noise on every card of a game session.
                if ($mm -and $paceNow -ge [Math]::Max(120, 2 * $paceBase)) {
                    $pace = @{ seconds = $paceNow; reason = 'jeu' }
                    try {
                        if ($mm -is [System.Collections.IDictionary]) { $mm['pace'] = $pace }
                        else { Add-Member -InputObject $mm -NotePropertyName 'pace' -NotePropertyValue $pace -Force }
                    } catch { }
                }
                # FRESHNESS TRAVELS WITH THE CARD (S16): three moments, three different questions -- when the probe
                # produced what is being read, when the scheduler last passed, and how often it is meant to.
                if ($mm -and $mm.id) {
                    try {
                        # ONE DATE FORMAT TOWARDS THE PAGE (D44): the cache keeps "at" in whatever shape
                        # ConvertFrom-Json gave it, which follows the culture. We answer ISO 8601, always.
                        <#
                            AND WHEN THE ENTRY CARRIES NO DATE, WE ASK THE PROBE'S NEWEST STAMP rather than send
                            nothing -- or worse, the year 0001, which is what an unparsable value converts to and
                            what the accounts card was showing. A card holding a value has been computed; the only
                            question is when, and the stamp of its probe answers it.
                        #>
                        $computed = ''
                        try { $u = ConvertTo-UtcDate $e.at; if ($u -and $u.Year -gt 1) { $computed = $u.ToString('o') } } catch { }
                        if (-not $computed) {
                            try {
                                $u = ConvertTo-UtcDate (Get-ProbeCacheStamp -Backend $Backend -Probe $pf.Name)
                                if ($u -and $u.Year -gt 1) { $computed = $u.ToString('o') }
                            } catch { }
                        }
                        $fresh = @{ computedAt = $computed }
                        $decl = @($refreshByCard["$($mm.id)"])[0]
                        if ($decl) {
                            $fresh.seconds = [int]$decl.Seconds
                            if ($decl.EndedAt) { $fresh.refreshedAt = "$($decl.EndedAt)" }
                            if ($decl.StartedAt) { $fresh.startedAt = "$($decl.StartedAt)" }
                            if ([int]$decl.Fails -gt 0) { $fresh.fails = [int]$decl.Fails; $fresh.lastError = "$($decl.LastError)" }
                        }
                        if ($mm -is [System.Collections.IDictionary]) { $mm['freshness'] = $fresh }
                        else { Add-Member -InputObject $mm -NotePropertyName 'freshness' -NotePropertyValue $fresh -Force }
                    } catch { }
                }
                # TO BE RECOMPUTED: the card shows, and says it is waiting for its measurement.
                if ($mm -and $e.pending) {
                    try {
                        if ($mm -is [System.Collections.IDictionary]) { $mm['pending'] = $true }
                        else { Add-Member -InputObject $mm -NotePropertyName 'pending' -NotePropertyValue $true -Force }
                    } catch { }
                }
            }
        }
    }

    <#
        A PROBE ALWAYS HAS ITS CARD. WITHOUT EXCEPTION.

        A card shows full, empty, or in error -- it is never missing. A probe that has never
        produced anything had no cache entry, and therefore no card: a hole in the page, whose
        contents nobody can guess.

        So a waiting card is returned, built on what is known without running anything at all:
        the folder's module.psd1 gives its title, the folder gives its group. It carries a value saying it is
        awaiting measurement, and its button, which is enough to fill it.
    #>
    & $markPhase 'assemblage'
    $known = @($modules | ForEach-Object { "$($_.id)" })
    foreach ($pf in $probeFiles) {
        $unit = Split-Path (Split-Path $pf.FullName -Parent) -Leaf
        if ($known -contains $unit) { continue }
        $e = $cache[(Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester)]
        if ($e -and $e.module) { continue }
        $cardLabel = $unit
        $cardTheme = $unit
        try {
            $decl = Import-PowerShellDataFile -Path (Join-Path (Split-Path $pf.FullName -Parent) 'module.psd1')
            if ($decl.Label) { $cardLabel = "$($decl.Label)" }
            # THE GROUP IS DECLARED, and the folder serves as the default otherwise.
            # "deployment" is not a group: its card is read under "Comptes", and the header
            # displayed "DEPLOYMENT" in English for want of knowing.
            if ($decl.Theme) { $cardTheme = "$($decl.Theme)" }
        } catch { }
        # SCOPE 'machine': this card says only that a measurement has not happened yet, which is true for everyone.
        $modules += (New-ModuleObject -Id $unit -Theme $cardTheme -Label $cardLabel -Scope 'machine' -Status 'neutral' -Fields @() -Actions @())
        $chrono[$unit] = 0
        try { Add-Member -InputObject $modules[-1] -NotePropertyName 'pending' -NotePropertyValue $true -Force } catch { }
    }

    <#
        "AN OPERATION IS RUNNING" IS READ NOW, NOT AT THE TIME OF THE COMPUTATION.

        A probe lays that state while it runs -- and its rendering is then served from the
        cache. An operation started AFTER that computation therefore did not show: the
        Deployment card stayed normal, its buttons active, while the update was running (seen
        on 31/08, the notification announcing "running for 26 s" while the card showed
        nothing).

        It is not a measurement, it is a present fact: it is read again at every response and
        laid over the rendering, whatever its age. The field also disappears by itself when
        the mark is gone.
    #>
    foreach ($m in $modules) {
        if (-not $m -or -not $m.id) { continue }
        $mark = Get-ModuleBusyMark -Module "$($m.id)" -Backend $Backend
        $props = @{ busy = [bool]$mark
                    busyAction = $(if ($mark) { $(if ("$($mark.button)") { "$($mark.button)" } else { "$($mark.action)" }) } else { $null })
                    busyResources = $(if ($mark -and $mark.resources) { @($mark.resources) } else { @() }) }
        foreach ($k in @($props.Keys)) {
            $v = $props[$k]
            try {
                if ($m -is [System.Collections.IDictionary]) {
                    if ($v -or $v -is [array]) { $m[$k] = $v } else { $m.Remove($k) | Out-Null }
                } else {
                    Add-Member -InputObject $m -NotePropertyName $k -NotePropertyValue $v -Force
                }
            } catch { }
        }
    }

    # INVARIANT (D66): an action NAMED by a field (fixAction) must appear among the card's
    # actions, or the interface has neither label nor kind to draw and the fixing button does
    # not appear. It is completed here rather than obliging every probe to redeclare the
    # action in its own bar.
    foreach ($m in $modules) {
        $connues = @(@($m.actions) | Where-Object { $_ -and $_.id } | ForEach-Object { "$($_.id)" })
        foreach ($ch in @($m.fields)) {
            $fa = "$($ch.fixAction)"
            if (-not $fa -or $connues -contains $fa) { continue }
            $pres = Get-ActionPresentation -Type $fa -Backend $Backend
            $act = New-Action -Id $fa -Label $pres.label -Kind $pres.kind -Severity $pres.severity `
                              -Help "Résolution proposée par la ligne « $($ch.label) »."
            try { $m.actions = @(@($m.actions) + $act) } catch { }
            $connues += $fa
        }
    }

    # Rights: every action says whether THIS account can launch it, and if not why (D65). It
    # is done here, once and for all, rather than in each probe.
    foreach ($m in $modules) {
        $tDroits = [Diagnostics.Stopwatch]::StartNew()
        foreach ($act in @($m.actions)) {
            if (-not $act -or -not $act.id) { continue }
            $droit = Test-ActionAllowed -Type "$($act.id)" -Backend $Backend
            try {
                if ($act -is [System.Collections.IDictionary]) {
                    $act['allowed'] = $droit.allowed
                    if (-not $droit.allowed) { $act['deniedReason'] = $droit.reason }
                } else {
                    Add-Member -InputObject $act -NotePropertyName 'allowed' -NotePropertyValue $droit.allowed -Force
                    if (-not $droit.allowed) { Add-Member -InputObject $act -NotePropertyName 'deniedReason' -NotePropertyValue $droit.reason -Force }
                }
            } catch { }
        }
        $tDroits.Stop()
        if ($m -and $m.id) {
            $ms = [math]::Round(([double]$chrono["$($m.id)"] + $tDroits.Elapsed.TotalMilliseconds), 1)
            $chrono["$($m.id)"] = $ms
            try {
                if ($m -is [System.Collections.IDictionary]) { $m['ms'] = $ms }
                else { Add-Member -InputObject $m -NotePropertyName 'ms' -NotePropertyValue $ms -Force }
            } catch { }
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
