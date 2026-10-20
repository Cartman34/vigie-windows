# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    Intent: the one place where everything the back end shares lives, so that no mechanism
    exists twice -- the card contract, the configuration, the token, the aggregation of the
    probes, the running of the actions, the data paths. It depends on nothing of Pode, so a
    script, a probe or a worker can load it without a server.
    Usage: dot-source it (`. (Join-Path $backend 'lib/common.ps1')`) before anything else,
    and look here FIRST for a function that already does what you are about to write; add
    one here rather than beside it, and never a second way to do the same thing.
#>

<#
    THE PIECES, SOURCED HERE, AND THIS FILE IS THEIR FACADE (S28).

    Every caller dot-sources this one file and nothing else -- a route, a probe, an action, a background task.
    What used to be 11 910 lines in one place is leaving by subject, and the callers do not change: that is what
    makes the cut provable, since the surface loaded has to stay identical.

    THE FLOOR IS FROZEN: `paths`, `format`, and the pieces that will follow them, depend on nothing of the project
    and never call upwards. Above them, subjects call each other as the subject requires, with one rule: no cycle.
#>
. "$PSScriptRoot/paths.ps1"         # the landmarks of the tree, and "does this path exist?"
. "$PSScriptRoot/var.ps1"           # where what the app generates may be written, and by which account
. "$PSScriptRoot/win-accounts.ps1"  # win-accounts
. "$PSScriptRoot/probe-file.ps1"    # probe-file
. "$PSScriptRoot/requester.ps1"     # requester
. "$PSScriptRoot/log.ps1"           # writing down what happened, in one shape
. "$PSScriptRoot/lock.ps1"          # lock
. "$PSScriptRoot/property.ps1"      # writing a value on a dictionary or an object, one gesture
. "$PSScriptRoot/store.ps1"         # writing a JSON file without losing what another writer wrote
. "$PSScriptRoot/series.ps1"        # series
. "$PSScriptRoot/retention.ps1"     # retention
. "$PSScriptRoot/format.ps1"        # sizes, dates, PowerShell literals: shaping a value into text
. "$PSScriptRoot/native.ps1"        # elevation, command lines, running a native command
. "$PSScriptRoot/git.ps1"           # git
. "$PSScriptRoot/service-clone.ps1" # service-clone
. "$PSScriptRoot/install-copy.ps1"  # install-copy
. "$PSScriptRoot/privileges.ps1"    # privileges
. "$PSScriptRoot/win-acl.ps1"       # win-acl
. "$PSScriptRoot/win-tasks.ps1"     # win-tasks
. "$PSScriptRoot/task-ailment.ps1"  # task-ailment
. "$PSScriptRoot/contract.ps1"      # the shape of what the panel receives: a field, an action, a card
. "$PSScriptRoot/action-resources.ps1" # action-resources
. "$PSScriptRoot/disk-tree.ps1"     # walking the disk one level at a time (D60)
. "$PSScriptRoot/games.ps1"         # recognising a game, and the tally of a session
. "$PSScriptRoot/updates.ps1"       # updates
. "$PSScriptRoot/update-audit.ps1"  # update-audit
. "$PSScriptRoot/device-guard.ps1"  # device-guard
. "$PSScriptRoot/packages.ps1"      # packages
. "$PSScriptRoot/hardware.ps1"      # hardware
. "$PSScriptRoot/power.ps1"         # power
. "$PSScriptRoot/config.ps1"        # config
. "$PSScriptRoot/version.ps1"       # version
. "$PSScriptRoot/deployment.ps1"    # deployment
. "$PSScriptRoot/server-process.ps1" # server-process
. "$PSScriptRoot/client-app.ps1"    # client-app
. "$PSScriptRoot/notifications.ps1" # notifications
. "$PSScriptRoot/accounts.ps1"      # accounts
. "$PSScriptRoot/sessions.ps1"      # sessions
. "$PSScriptRoot/rights.ps1"        # rights
. "$PSScriptRoot/settings.ps1"      # settings
. "$PSScriptRoot/stage.ps1"         # stage
. "$PSScriptRoot/audit.ps1"         # audit
. "$PSScriptRoot/elevation.ps1"     # elevation
. "$PSScriptRoot/residents.ps1"     # residents
. "$PSScriptRoot/watch-engine.ps1"  # watch-engine
. "$PSScriptRoot/watches.ps1"       # watches
. "$PSScriptRoot/tasks.ps1"         # tasks
. "$PSScriptRoot/scheduler.ps1"     # scheduler
. "$PSScriptRoot/probes.ps1"        # probes
. "$PSScriptRoot/measures.ps1"      # measures
. "$PSScriptRoot/operations.ps1"    # operations
. "$PSScriptRoot/naming.ps1"        # naming
. "$PSScriptRoot/probe-cache.ps1"   # what the probes have produced, and how old it is
. "$PSScriptRoot/probe-run.ps1"     # running a probe, one at a time, and keeping its answer
. "$PSScriptRoot/card-shape.ps1"    # what a card gains before it leaves: freshness, rights, the operation on it
. "$PSScriptRoot/state.ps1"         # state


# THE LABELS ARE AVAILABLE WHEREVER common.ps1 IS -- that is, in the server, the probes, the
# actions and the workers. Without loading them here, every file would have to remember to
# load i18n.ps1, and whoever forgot would only break at run time, on the line that displays:
# the worst possible place to learn it.
# console-ui.ps1 brings the display vocabulary AND, through it, the labels: the two files are
# neighbours and one loads the other. Loading common.ps1 is therefore enough to have it all.
# Without this, a back-end file converted to Write-Ok died on "term not recognised" -- at run
# time, on its display line.
$script:_uiLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/console-ui.ps1'
if (Test-Path -LiteralPath $script:_uiLib) { . $script:_uiLib }

# The account secret: laying it down, its rights, reading it back suspiciously. This file had
# existed since 28/08 without being loaded anywhere -- code no test could see.
$script:_secretLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/account-secret.ps1'
if (Test-Path -LiteralPath $script:_secretLib) { . $script:_secretLib }

# Who listens on a port, asked of Windows directly: Get-PortListener, Get-UdpEndpointOwner (26 s through WMI on 14/09).
$script:_portLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/tcp-ports.ps1'
if (Test-Path -LiteralPath $script:_portLib) { . $script:_portLib }

# Memory and processor load, asked of Windows directly: Get-MemoryStatus, Get-ProcessorLoad (1.7 s through WMI on 18/09).
$script:_metricsLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/system-metrics.ps1'
if (Test-Path -LiteralPath $script:_metricsLib) { . $script:_metricsLib }

# Who holds a file, asked of Windows directly: Get-FileHolders, through the Restart Manager. Names what blocks (D127).
$script:_lockLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/file-locks.ps1'
if (Test-Path -LiteralPath $script:_lockLib) { . $script:_lockLib }












































































































$script:ThemeCatalog = @(
    [pscustomobject]@{ id = 'windows-update'; label = 'Windows Update' }
    [pscustomobject]@{ id = 'system';         label = 'Système' }
    [pscustomobject]@{ id = 'accounts';       label = 'Comptes' }
    [pscustomobject]@{ id = 'wsl';            label = 'WSL' }
    [pscustomobject]@{ id = 'security';       label = 'Sécurité' }
    [pscustomobject]@{ id = 'network';        label = 'Réseau' }
    [pscustomobject]@{ id = 'tools';          label = 'Outils & paquets' }
    [pscustomobject]@{ id = 'gaming';         label = 'Gaming' }
    # Last in the list: it is a troubleshooting tool, off by default (D85).
    [pscustomobject]@{ id = 'debug';          label = 'Débogage' }
)















































# --- Aggregating the probes (logged) ----------------------------------------
# How long a probe's cache stays valid, in seconds: short for what moves fast, long for what
# is stable.
# THE GAME MODE: WHILE A GAME RUNS, VIGIE STEPS BACK.
#
# Measured on 28/09, an ACOdyssey session of 77 minutes: 383 card recomputations, 1582 s of processing, 34 % of one
# core without pause -- 400 s for the packages card alone (winget, choco, pip), 301 s for the gaming card, 213 s for
# the network. The game stuttered, and Vigie had its share in it. Every request from the interface hands one stale
# probe to a background task; with caches of five seconds, everything is always stale.
#
# During a game, the cards that speak of the game keep their pace; the others go to a quarter of an hour at least,
# and the heavy ones to an hour. An explicit request (the card's refresh button) always goes through: the game mode
# slows the background down, it forbids nothing.
# THE CARDS THAT STILL WATCH THE GAME, each with the pace it keeps while playing. They are the only ones left
# quick, so they would otherwise run far more often than before -- the opposite of the aim: the gaming card costs
# 5.5 s per recomputation (244 times on 28/09, 22 minutes of processor for the day alone).
$script:GameModeUseful = @{ 'gaming.probe.ps1' = 30; 'perf.probe.ps1' = 20; 'self.probe.ps1' = 120; 'vigie.probe.ps1' = 300 }
$script:GameModeHeavy  = @('packages.probe.ps1', 'deployment.probe.ps1', 'lock.probe.ps1', 'pending.probe.ps1',
                           'accounts.probe.ps1', 'history.probe.ps1', 'wsl.probe.ps1', 'os.probe.ps1')


<#
    WHAT A CARD COSTS DECIDES HOW LONG IT KEEPS.

    Every request from the interface hands ONE stale probe to a background task. With a cache of five seconds, a
    card is stale at almost every request, and the cheapness of the reading stops mattering: measured over the day
    of 28/09, the packages card was recomputed 305 times for 1128 s of processing (3.7 s each, winget, choco, pip)
    and the network card 171 times for 713 s. Nobody asked for winget five times a minute.

    The durations below therefore follow the COST, not the wish: a card that takes seconds keeps for minutes. What
    keeps the cards honest is elsewhere and untouched -- an action invalidates the cards it changes, the refresh
    button forces a recomputation, and a sentinel recalculates its cards the moment its value moves (connection,
    power, game). The storage card is the exception: while an analysis runs, it carries its progress, and a
    progress shown once a minute is not a progress.
#>
$script:ProbeTtls = @{
    # 15, not 8: the card costs 1.1 s per recomputation, and nobody reads the processor load eight times a minute.
    'perf.probe.ps1'    = 15
    # 60, not 15: the probe takes 4.2 s (connection test with timeouts), and the 'internet' sentinel recalculates
    # this card the moment the connection moves.
    'net.probe.ps1'     = 60
    # 60, not 600: the card carries the memory of the virtual machine, which moves by gigabytes; the probe costs 0.1 s.
    'wsl.probe.ps1'     = 60
    # 60 at rest, 5 while a space analysis runs (Get-ProbeTtlNow): the card carries its progress (D60), and a
    # progress refreshed once a minute is not a progress.
    'disk.probe.ps1'    = 60
    # 300, not 5: winget, choco and pip are questioned each time, 3.7 s per pass. An upgrade invalidates this card
    # itself (result.invalidate), so nothing waits five minutes to be seen.
    'packages.probe.ps1' = 300
    # 60: the 'power' sentinel already recalculates this card whenever the current changes direction.
    'power.probe.ps1'   = 60
    'history.probe.ps1' = 120
    'firewall.probe.ps1'= 120
    'defender.probe.ps1'= 300
    'vbs.probe.ps1'     = 300
    'lock.probe.ps1'    = 600
    'pending.probe.ps1' = 900
    # ACCOUNTS CHANGE RARELY: creating a Windows account does not happen within the day. One
    # hour, and the refresh button of that card for whoever has just created one.
    'accounts.probe.ps1' = 3600
    # THE DEPLOYMENT, on the other hand, MUST SEE A COMMIT ARRIVE -- and it is deferrable, so
    # this short delay costs the request nothing: it leaves with the value already known.
    'deployment.probe.ps1' = 60
    'os.probe.ps1'      = 3600
    # THE SYSTEM LOG: read in 0.08 s, and a serious error must show within the minute.
    'events.probe.ps1'  = 60
    # VIGIE'S OWN PROCESSES: a runaway must show within the minute, and the reading costs a few milliseconds.
    'self.probe.ps1'    = 30
    # 30, not 10: 5.5 s per recomputation on 28/09 -- the most expensive card of all, and the one a game keeps quick.
    'gaming.probe.ps1'  = 30
}



# --- The history of measurements (series) -------------------------------------
# Values already computed by the probes are noted IN PASSING: the only hook is a probe's
# successful recomputation inside Get-State -- no probe writes by itself, and the history has
# no cadence of its own. Storage: one JSONL file per measurement in var/history/ (distinct
# from var/cache/: a lost history does not recompute itself). Best effort: a write error is
# logged and never makes a recomputation fail.
#
# THE catalogue of measurements (D15: one value, one definition). For each of them: the
# source probe, its nature (gauge/event), its unit, the default minimum interval (which the
# configuration can override, see Get-HistoryConfig) and the extractor, which reads the value
# from the MODULES THE PROBE RETURNED -- never by running anything again.
# The extractor returns $null (nothing to note) or @{ v = <value>; key = <optional token> }.
# `key` serves measurements tied to an external one: a point is written only when it changes.
# For instance net.latency only has a NEW value when `measAt` moves, whatever the number of
# recomputations of the probe between two throughput or latency measurements.
$script:MeasureCatalog = @{
    <#
        VIGIE MEASURES HERSELF.

        On 16/10 the owner asked whether 325 Mo for the server app was a lot, and whether it GROWS. Nothing could
        answer: the catalogue held the machine's processor, memory, commit, latency, free space and the game's
        graphics card -- nothing about Vigie. A reading taken in a message answers for one instant and dies with
        the message; a series answers for good, and survives a restart.

        The card already measures it (`vigie-self`, field `memory`, the sum over every process of Vigie). All that
        was missing was to keep it. Tolerance of twenty megabytes: below that, the figure has not moved for anyone
        reading it, and the history does not swell for nothing.

        It depends on the `debug` module being enabled, since that is the card which measures. Disabled, the series
        simply has no points -- which is honest, and visible.
    #>
    'vigie.memory' = @{
        Probe = 'self.probe.ps1'; Kind = 'gauge'; Unit = 'Mo'; IntervalMinutes = 10; Tolerance = 20
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'vigie-self' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'memory' } | Select-Object -First 1
            if ($null -eq $f -or $null -eq $f.value) { return $null }
            $v = 0.0
            if (-not [double]::TryParse("$($f.value)", [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
            return @{ v = $v }
        }
    }
    'disk.free' = @{
        # Tolerance: one gigabyte. Below that, free space has not moved for whoever reads it.
        Probe = 'disk.probe.ps1'; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 30; Tolerance = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'storage' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'free' } | Select-Object -First 1
            if ($null -eq $f -or $null -eq $f.value) { return $null }
            $v = 0.0
            if (-not [double]::TryParse("$($f.value)", [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
            return @{ v = $v }
        }
    }
    # A game session (the gaming module): noted ONLY while a game runs -- the very presence of
    # the points tells the session (start, end, intensity). The game's name travels with each
    # point (field n), to answer "why was it slow last night?" without displaying anything
    # (Q2: recording only).
    'game.gpu' = @{
        # Tolerance: five points. A GPU swinging between 22 and 25 % tells nothing -- that is
        # the noise of an instantaneous measurement, not a variation of the game.
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = '%'; IntervalMinutes = 1; Tolerance = 5
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $r = @($m.fields) | Where-Object { "$($_.key)" -eq 'game-res' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $r) { return $null }
            if ("$($r.value)" -notmatch 'GPU\s+([0-9]+(?:[.,][0-9]+)?)\s*%') { return $null }
            return @{ v = [double](($Matches[1]) -replace ',', '.'); n = "$($g.value)" }
        }
    }
    'game.vram' = @{
        # Tolerance: two hundred megabytes, the precision of what is displayed.
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 1; Tolerance = 0.2
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $r = @($m.fields) | Where-Object { "$($_.key)" -eq 'game-res' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $r) { return $null }
            if ("$($r.value)" -notmatch 'VRAM\s+([0-9]+(?:[.,][0-9]+)?)\s*Go') { return $null }
            return @{ v = [double](($Matches[1]) -replace ',', '.'); n = "$($g.value)" }
        }
    }
    'game.hogs' = @{
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = 'applis'; IntervalMinutes = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $h = @($m.fields) | Where-Object { "$($_.key)" -eq 'hogs' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $h) { return $null }
            # THE VALUE NAMES, IT NO LONGER COUNTS: it reads "Chrome and 2 more" in French since 06/09, while the extractor
            # looked for a leading number -- so the history of 28/09 read zero greedy application for a whole
            # session. The count is read from the sentence, and the NAMES travel with the point.
            $text = "$($h.value)"
            $n = 0
            if ($text -match '^([0-9]+)') { $n = [int]$Matches[1] }
            elseif ($text -match '^Aucune') { $n = 0 }
            elseif ($text -match 'et\s+([0-9]+)\s+autres') { $n = [int]$Matches[1] + 1 }
            elseif ($text -match '\set\s') { $n = 2 }
            elseif ($text.Trim()) { $n = 1 }
            return @{ v = [double]$n; n = $(if ($n) { $text } else { "$($g.value)" }) }
        }
    }
    <#
        WHAT THE COMPUTER WAS DOING, NOT ONLY THE GAME.

        On 28/09 a game stuttered for 77 minutes and nothing could say why: the game's GPU and VRAM were recorded,
        the processor, the memory in use and the committed memory were not. These three follow the Resources card,
        at all times -- they serve any enquiry, not only games -- and every point carries THE NAME OF THE GAME
        running when there is one: the series is then read session by session.
    #>
    'perf.cpu' = @{
        # One point every five minutes at rest, every minute while a game runs: these series serve an enquiry,
        # and nobody needs the processor load of every second (owner, 28/09).
        Probe = 'perf.probe.ps1'; IntervalMinutesInGame = 1; Kind = 'gauge'; Unit = '%'; IntervalMinutes = 5; Tolerance = 10
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'perf' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'cpu' } | Select-Object -First 1
            if (-not $f -or $null -eq $f.value) { return $null }
            $point = @{ v = [double]$f.value }
            $game = Get-GameModeName
            if ($game) { $point.n = $game }
            return $point
        }
    }
    'perf.ram' = @{
        # One point every five minutes at rest, every minute while a game runs: these series serve an enquiry,
        # and nobody needs the processor load of every second (owner, 28/09).
        Probe = 'perf.probe.ps1'; IntervalMinutesInGame = 1; Kind = 'gauge'; Unit = '%'; IntervalMinutes = 5; Tolerance = 2
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'perf' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'ramUsed' } | Select-Object -First 1
            if (-not $f) { return $null }
            if ("$($f.value)" -notmatch '\(([0-9]+)\s*%\)') { return $null }
            $point = @{ v = [double]$Matches[1] }
            $game = Get-GameModeName
            if ($game) { $point.n = $game }
            return $point
        }
    }
    'perf.commit' = @{
        # One point every five minutes at rest, every minute while a game runs: these series serve an enquiry,
        # and nobody needs the processor load of every second (owner, 28/09).
        Probe = 'perf.probe.ps1'; IntervalMinutesInGame = 1; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 5; Tolerance = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'perf' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'commit' } | Select-Object -First 1
            if (-not $f) { return $null }
            if ("$($f.value)" -notmatch '^([0-9]+(?:[.,][0-9]+)?)\s*Go') { return $null }
            $point = @{ v = [double](($Matches[1]) -replace ',', '.') }
            $game = Get-GameModeName
            if ($game) { $point.n = $game }
            return $point
        }
    }
    'net.latency' = @{
        # Tolerance: five milliseconds. Below that, it is the normal variation of a ping.
        Probe = 'net.probe.ps1'; Kind = 'gauge'; Unit = 'ms'; IntervalMinutes = 0; Tolerance = 5
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'net' } | Select-Object -First 1
            if (-not $m) { return $null }
            $lat = @($m.fields) | Where-Object { "$($_.key)" -eq 'latency' } | Select-Object -First 1
            $mea = @($m.fields) | Where-Object { "$($_.key)" -eq 'measAt' }  | Select-Object -First 1
            # No date field means latency never measured: nothing to note.
            if (-not $lat -or -not $mea -or $null -eq $mea.value) { return $null }
            # The displayed value is text ("23 ms"): the number is extracted from it.
            if ("$($lat.value)" -notmatch '^\s*([0-9]+(?:[.,][0-9]+)?)\s*ms') { return $null }
            $v = [double](($Matches[1]) -replace ',', '.')
            # The key is the measurement's date, NORMALISED: ConvertFrom-Json returns
            # sometimes a string, sometimes a [datetime] (D44) -- comparing the raw forms
            # would write a point at every recomputation.
            $key = $null
            try { $key = (ConvertTo-UtcDate $mea.value).ToString('o') } catch { return $null }
            return @{ v = $v; key = $key }
        }
    }
}

























<#
    THE MAKER'S NAME, WHEN THE MAKER SPELLS IT SEVERAL WAYS.

    Windows Update hands out the provider of each driver, and the same company writes
    itself as it pleases: "INTEL", "Intel Corporation" and "Intel(R) Corporation" were
    three separate piles for twenty-one updates on 10/09, out of sixteen spellings for
    twelve makers.

    TWO STAGES, AND THE ORDER MATTERS. First a mechanical fold, which knows nothing and
    cannot be wrong about a brand: upper case, decorations and punctuation dropped, then
    the legal-form suffixes at the END of the name only -- "Corp" inside a name stays.
    Only what survives that reaches the second stage, config/vendor-names.json, a written
    table for the case no text processing will ever solve: two genuinely different names
    for one maker (D118).

    The label shown is never a manufactured string: either the table's name, or a spelling
    actually seen -- mixed case preferred over shouting, then the most frequent.
#>
$script:VendorSuffixes = @('CORPORATION', 'CORP', 'INCORPORATED', 'INC', 'LIMITED', 'LTD',
                           'COMPANY', 'CO', 'GMBH', 'AG', 'AB', 'SA', 'BV', 'NV', 'LLC', 'PLC',
                           'TECHNOLOGY', 'TECHNOLOGIES', 'SEMICONDUCTOR', 'SEMICONDUCTORS',
                           'SYSTEMS', 'ELECTRONICS', 'SOFTWARE')





































































# The account that ASKS for the action. Today the server runs inside its user's session, so it is that user. When
# the server becomes a machine task serving several accounts, only THIS function will change -- the rest of the
# chain already speaks of a "requester" and not of "me".
<#
    WHO IS ASKING? The account behind the request, not the account running the server.

    This function used to return the identity of the PROCESS -- that is, always the server's. As long as there was
    one server per session, that was true only by accident. With a single server for the machine it is wrong for
    everybody but him: an action asked for by Famille would be logged in fhaza's name, and run on HIS desktop.

    The order of the proofs:
      1. the session cookie, when the request comes from an identified page -- the only source that really says
         WHO is looking;
      2. failing that, the identity of the process: a local script, a scheduled task, a diagnosis. It is then the
         server's account, and it is accurate.

    THE NAME IS RETURNED WITHOUT ITS DOMAIN. "HYPERION\fhaza" does not join onto a profile path:
    Get-AccountVarRoot would draw "C:\Users\HYPERION\fhaza" from it.
#>



<#
    WHO IS ASKING -- or NOBODY.

    Get-ActionRequester must always return a name: it signs the audit log, and an anonymous trace is worth nothing.
    It therefore falls back on the process's account when no session is open.

    THAT IS EXACTLY WHAT IS WRONG for everything that speaks of "you". A page opened without a ticket (a bookmark,
    a reload) has no cookie: the fallback then designates the service's account, and the Accounts card shows "YOU"
    on VigieService -- observed on 29/08.

    This function falls back on nothing: no session, no person. It is up to the caller to say what "nobody" means
    where it stands -- often "no account is you", sometimes "everybody is warned".
#>



<#
    THE ACCOUNT THE CURRENT COMPUTATION IS FOR -- one door, and probes know no other.

    `Get-RequesterAccount` reads the session cookie of a WEB REQUEST. It therefore answers nothing at all when the
    SCHEDULER computes (D124), which has no requester: the refresh worker runs outside any request. A per-account
    probe that asked it directly saw $null half the time, and silently dropped what belongs to an account -- measured
    on 06/10, the winget card vanished from the panel for the very account that owns winget.

    `Get-State` says who it computes for, here, before running the probes; the cookie remains the fallback for code
    that runs inside a request without going through Get-State.
#>
<#
    AND IT IS A GLOBAL, WHICH IS NOT A SHORTCUT: a script variable cannot cross into a probe.

    Every probe begins by dot-sourcing this library into ITS OWN script scope. That re-runs the line below and
    redefines this function there, so a `$script:` variable set by Get-State was invisible to the probe -- the probe
    read its own copy, freshly reset to $null. Measured on 06/10: the scheduler computed the packages card for
    `fhaza`, the account's inventory held winget, and the card came out without it. Each link worked alone; the chain
    did not.

    Get-State therefore sets it in the global scope, right before running each probe, and clears it after. The window
    is inside the single-flight mutex that already serialises recomputation.
#>
if (-not (Get-Variable -Name 'VigieStateAccount' -Scope Global -ErrorAction SilentlyContinue)) {
    $global:VigieStateAccount = $null
}












