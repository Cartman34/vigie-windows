# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, paths, series, store, var, win-accounts
<#
    Intent: IS A GAME RUNNING, AND HOW DID THE SESSION GO? Recognising a game among the processes -- by the
    store libraries it was installed in, then by what it does to the machine -- then keeping the tally of the
    session: how long, what got in its way, and what is worth telling at the end.
    Usage: dot-sourced by common.ps1, never run on its own. The recognition is DECLARED, never guessed from a
    rendering, and the tally is written as it goes: a session one has to reconstruct afterwards is lost (S28).
#>

<#
    THE MACHINE'S GAME LIBRARIES, read once and kept.

    Steam declares its libraries in its configuration; other stores register the folder of
    each installed game. All of it lives PER USER for Steam and in the machine store for the
    others: we therefore read hive by hive, never the service account's HKCU (D113).

    This is one identification method, and the most limited: it only knows the big stores.
    An indie game launched without a platform will never be there.
#>
$script:GameLibraries = $null
$script:GameLibrariesAt = [datetime]::MinValue
function Get-GameLibraryPaths {
    param([int]$TtlMinutes = 10)
    if ($script:GameLibraries -and (([datetime]::UtcNow - $script:GameLibrariesAt).TotalMinutes -lt $TtlMinutes)) {
        return $script:GameLibraries
    }
    $found = @()
    # --- Steam: the libraries declared, in each user's own configuration -----------
    foreach ($hive in @(Get-UserRegistryRoots)) {
        try {
            $steamPath = (Get-ItemProperty (Join-Path $hive 'Software\Valve\Steam') -Name 'SteamPath' -ErrorAction Stop).SteamPath
            if (-not $steamPath) { continue }
            $root = ($steamPath -replace '/', '\')
            $found += @{ Label = 'une bibliotheque Steam'; Path = (Join-Path $root 'steamapps\common') }
            $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    $lib = ($m.Groups[1].Value -replace '\\\\', '\')
                    $found += @{ Label = 'une bibliotheque Steam'; Path = (Join-Path $lib 'steamapps\common') }
                }
            }
        } catch { }
    }
    # --- Ubisoft Connect: the folder of each installed game ------------------------
    foreach ($base in @('HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs',
                        'HKLM:\SOFTWARE\Ubisoft\Launcher\Installs')) {
        try {
            foreach ($key in (Get-ChildItem $base -ErrorAction Stop)) {
                $dir = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallDir
                if ($dir) { $found += @{ Label = 'la bibliotheque Ubisoft Connect'; Path = ($dir -replace '/', '\') } }
            }
        } catch { }
    }
    # --- GOG Galaxy ----------------------------------------------------------------
    foreach ($base in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games')) {
        try {
            foreach ($key in (Get-ChildItem $base -ErrorAction Stop)) {
                $dir = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).path
                if ($dir) { $found += @{ Label = 'la bibliotheque GOG'; Path = $dir } }
            }
        } catch { }
    }
    # --- Epic Games: one manifest per game, in the machine's data ------------------
    try {
        $manifests = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
        foreach ($file in @(Get-ChildItem -LiteralPath $manifests -Filter '*.item' -File -ErrorAction Stop)) {
            $item = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($item.InstallLocation) { $found += @{ Label = 'la bibliotheque Epic Games'; Path = "$($item.InstallLocation)" } }
        }
    } catch { }

    $script:GameLibraries = @($found | Where-Object { $_.Path })
    $script:GameLibrariesAt = [datetime]::UtcNow
    return $script:GameLibraries
}

<#
    IS IT A GAME? Several METHODS, and one that speaks is enough.

    They live in probes/gaming/identify/, one file each, ordered by COST: the file name
    carries its rank, and we stop at the first that answers. None is complete -- their union
    is -- and adding one tomorrow costs a file, nothing else.

    WE NEVER JUDGE ON AN EXECUTABLE'S NAME (D64). What is ruled out upfront is ruled out on
    its LOCATION: what lives in the Windows folder is not a game.

    BOTH VERDICTS ARE REMEMBERED -- game AND not-game. An executable that starts a hundred
    times is examined once. The memory carries the CRITERIA FINGERPRINT: change a criterion,
    add a method, and everything is examined again, once.
#>
<#
    A STORE'S OWN FOLDER HOLDS THE STORE, NOT A GAME.

    Ubisoft Connect keeps nine UplayWebCore processes alive next to upc.exe, and each one
    answered two methods at once: started by a store (20) and game markers around the
    executable (50) -- the launcher's folder does hold uplay_r1_loader64.dll. Each new one
    took the session over, so on 03/09 the card announced "UplayWebCore" while Odyssey was
    the process actually consuming the machine.

    The rule judges the LOCATION, like the Windows one: a process sitting DIRECTLY in the
    store's program folder is the store's machinery. A game never sits there -- Steam puts
    them under steamapps\common, Ubisoft in its own game folder -- so nothing real is lost.
#>
function Test-PathInGameStoreFolder {
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Path)
    if (-not $Path) { return $false }
    $folder = ''
    try { $folder = Split-Path $Path -Parent } catch { }
    if (-not $folder) { return $false }
    $separator = [string][char]92
    $folder = "$folder".ToLower().TrimEnd([char]92)
    # THE CONCATENATION STAYS OUT OF THE ARRAY: inside one, the comma binds tighter than the
    # plus, and @('a' + 'b', 'c' + 'd') quietly builds something else entirely.
    $stores = @('steam', 'ubisoft game launcher', 'ubisoft connect', 'gog galaxy',
                'battle.net', 'eadesktop')
    foreach ($store in $stores) {
        if ($folder.EndsWith($separator + $store)) { return $true }
    }
    return $false
}

function Get-GameCriteriaFingerprint {
    param([string]$Backend = (Get-BackendRoot))
    $dir = Join-Path $Backend 'probes/gaming/identify'
    $parts = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $parts += ($file.Name + '@' + $file.LastWriteTimeUtc.ToString('o'))
    }
    # THIS LIBRARY IS A CRITERION TOO: what rules a process out before any method runs lives
    # here. Leaving it out of the fingerprint left the old verdicts standing while the rule
    # that made them had changed -- and a wrong verdict, once memorised, never comes back up.
    try {
        $self = Get-Item -LiteralPath (Join-Path $Backend 'lib/common.ps1') -ErrorAction Stop
        $parts += ('common.ps1@' + $self.LastWriteTimeUtc.ToString('o'))
    } catch { }
    return ($parts -join '|')
}

function Get-GameVerdictPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'game-verdicts.json'
}

function Test-ProcessIsGame {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)]$Process
    )
    $unknown = [pscustomobject]@{ IsGame = $false; Reason = $null; Method = $null }
    if (-not $Process -or -not $Process.Path) { return $unknown }
    $path = "$($Process.Path)"
    # What lives in Windows is not a game: ruled out on its LOCATION, never on its name.
    if ($path.ToLower().StartsWith("$env:SystemRoot".ToLower())) { return $unknown }
    # Neither is what lives in a store's OWN folder (see below).
    if (Test-PathInGameStoreFolder -Path $path) { return $unknown }

    $key = $path.ToLower()
    $file = Get-GameVerdictPath -Backend $Backend
    $fingerprint = Get-GameCriteriaFingerprint -Backend $Backend
    # THE MEMORY IS READ ONCE PER PASS, not once per process. Parsing this file for every running process cost 45 ms
    # each -- the bulk of the 5.5 s the gaming card took on 28/09, with a hundred processes to judge. It is kept in
    # memory for as long as the file has not changed.
    $memory = $null
    $written = $null
    try { if (Test-PathSafe $file) { $written = (Get-Item -LiteralPath $file).LastWriteTimeUtc } } catch { }
    if ($script:GameVerdictMemory -and $script:GameVerdictWritten -eq $written) {
        $memory = $script:GameVerdictMemory
    } elseif ($written) {
        try { $memory = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } catch { }
        $script:GameVerdictMemory = $memory
        $script:GameVerdictWritten = $written
    }
    if ($memory -and "$($memory.fingerprint)" -ne $fingerprint) { $memory = $null }
    if ($memory -and $memory.verdicts -and $memory.verdicts.PSObject.Properties[$key]) {
        $known = $memory.verdicts.PSObject.Properties[$key].Value
        return [pscustomobject]@{ IsGame = [bool]$known.game; Reason = "$($known.reason)"; Method = "$($known.method)" }
    }

    $verdict = $unknown
    $dir = Join-Path $Backend 'probes/gaming/identify'
    foreach ($method in @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $reason = $null
        try { $reason = & $method.FullName -Process $Process } catch { $reason = $null }
        $reason = "$($reason | Select-Object -Last 1)".Trim()
        if ($reason) {
            $verdict = [pscustomobject]@{ IsGame = $true; Reason = $reason; Method = $method.BaseName }
            break
        }
    }

    # We keep the answer, whatever it is.
    $store = [ordered]@{ fingerprint = $fingerprint; verdicts = [ordered]@{} }
    if ($memory -and $memory.verdicts) {
        foreach ($prop in $memory.verdicts.PSObject.Properties) { $store.verdicts[$prop.Name] = $prop.Value }
    }
    $store.verdicts[$key] = [ordered]@{ game = $verdict.IsGame; reason = $verdict.Reason
                                        method = $verdict.Method; at = ([datetime]::UtcNow).ToString('o') }
    try {
        $tmp = "$file.tmp"
        ($store | ConvertTo-Json -Depth 6) | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $file -Force
        # The memory follows what has just been written: without this, the next process reads the file again.
        $script:GameVerdictMemory = ($store | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
        try { $script:GameVerdictWritten = (Get-Item -LiteralPath $file).LastWriteTimeUtc } catch { $script:GameVerdictWritten = $null }
    } catch { }
    return $verdict
}

<#
    WHAT A BOTTLENECK IS, AND WHAT IT IS NOT.

    A saturated machine is not a bottleneck: a game alone at 95 % of the processor simply uses the computer it was
    given. Dust is not one either -- ten processes at one percent are the ordinary life of Windows. A bottleneck is a
    moment when the machine is at its ceiling AND something OTHER than the game takes a share worth the name, on its
    own (owner, 28/09).

    Memory is the exception: when the committed memory reaches its limit, the computer brakes whoever is at fault, so
    no culprit has to be named for the moment to count.

    A single reading is not a bottleneck either: two consecutive ones are needed, one minute, so that a loading screen
    does not become a verdict.
#>
$script:GameJamCpuTotal = 85     # % de charge processeur totale au-dela duquel la machine est au plafond
$script:GameJamCpuOther = 10     # % qu'une application etrangere doit prendre A ELLE SEULE pour gener
$script:GameJamGpuTotal = 95     # % de la carte graphique : un GPU plein bride le jeu plus vite que le processeur
$script:GameJamGpuOther = 5      # % de GPU vole au jeu : plus bas, parce qu'il coute plus cher
$script:GameJamMemPct   = 90     # % de memoire engagee : au-dela, Windows puise dans le fichier d'echange

function Get-GameTallyPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'run' -File 'game-tally.json'
}

function Get-GameSessionsPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'history' -File 'game-sessions.jsonl'
}

# ADDS ONE PASS TO THE TALLY of the running session. $Apps carries what the card has just measured, grouped by
# application: Name, Label, Cpu, Gpu, VramGb, RamGb, IoMbs. Never throws.
function Add-GameTallyPass {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Apps,
        # THE STATE OF THE MACHINE at this pass, which the card has just measured: total processor load, total
        # graphics load, committed memory. Without them, a bottleneck cannot be told from a busy game.
        [double]$CpuTotal = -1,
        [double]$GpuTotal = -1,
        [double]$MemoryPct = -1,
        # The names that belong to the game (the game, its launcher, its components): they never make a bottleneck.
        [string[]]$GameNames = @(),
        # The time between two passes is counted here, from the tally itself: the caller does not have to know it.
        # Capped at five minutes so that a computer put to sleep in the middle of a game does not count as played.
        [int]$MaxGapSeconds = 300
    )
    try {
        $path = Get-GameTallyPath -Backend $Backend
        $tally = $null
        if (Test-PathSafe $path) { try { $tally = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { } }
        $sessionKey = "$($Session.startedAt)"
        # THE SAME SESSION, COMPARED AS A DATE AND NOT AS TEXT: ConvertFrom-Json turns an ISO date into [datetime]
        # (D44), which prints differently from what was written -- every pass then started a new tally, and the
        # session stayed at one pass for ever (caught on the second test, 28/09).
        $sameSession = $false
        if ($tally -and $tally.session) {
            try { $sameSession = ((ConvertTo-UtcDate $tally.session) -eq (ConvertTo-UtcDate $sessionKey)) } catch { $sameSession = $false }
        }
        if (-not $sameSession) {
            $tally = [pscustomobject]@{ session = $sessionKey; game = "$($Session.name)"; startedAt = $sessionKey
                                        lastAt = $null; passes = 0; seconds = 0; apps = [pscustomobject]@{}
                                        jamCpuSeconds = 0; jamGpuSeconds = 0; jamMemSeconds = 0
                                        jamCpuPasses = 0; jamGpuPasses = 0; jamMemPasses = 0
                                        lostSeconds = 0; breaks = @()
                                        satCpuBefore = $false; satGpuBefore = $false; satMemBefore = $false }
        }
        <#
            WHAT THE CAP DROPS IS WRITTEN DOWN, otherwise the count cannot be questioned.

            On 05/10 a session lasting 2 h 06 was counted as 1 h 41, and nothing in the record could say where the
            twenty-five minutes had gone. The cap is right -- a computer asleep in the middle of a game is not played
            time -- but a count one cannot audit is a count one cannot believe. Each interruption longer than the cap
            is now kept: when it started, how long it lasted. Bounded to the ten longest, so a session stays one line.
        #>
        $SecondsSinceLast = 0
        $gapSeconds = 0
        if ($tally.lastAt) {
            try {
                $gapSeconds = [int][Math]::Max(0, ([datetime]::UtcNow - (ConvertTo-UtcDate $tally.lastAt)).TotalSeconds)
                $SecondsSinceLast = [int][Math]::Min($MaxGapSeconds, $gapSeconds)
            } catch { }
        }
        if ($gapSeconds -gt $MaxGapSeconds) {
            $tally.lostSeconds = [int]$tally.lostSeconds + ($gapSeconds - $MaxGapSeconds)
            $breaks = @($tally.breaks) | Where-Object { $_ }
            $breaks += [pscustomobject]@{ at = "$($tally.lastAt)"; seconds = $gapSeconds }
            $tally.breaks = @($breaks | Sort-Object { [int]$_.seconds } -Descending | Select-Object -First 10)
        }
        $tally.passes = [int]$tally.passes + 1
        $tally.seconds = [int]$tally.seconds + $SecondsSinceLast
        # AT ITS CEILING? Told for this pass, and counted only if the previous one said the same.
        $satCpu = ($CpuTotal -ge 0 -and $CpuTotal -ge $script:GameJamCpuTotal)
        $satGpu = ($GpuTotal -ge 0 -and $GpuTotal -ge $script:GameJamGpuTotal)
        $satMem = ($MemoryPct -ge 0 -and $MemoryPct -ge $script:GameJamMemPct)
        $jamCpu = ($satCpu -and [bool]$tally.satCpuBefore)
        $jamGpu = ($satGpu -and [bool]$tally.satGpuBefore)
        $jamMem = ($satMem -and [bool]$tally.satMemBefore)
        # COUNTED IN PASSES AND IN SECONDS: the seconds say how long it lasted, the passes say that it happened --
        # two readings a second apart would otherwise weigh nothing at all.
        if ($jamCpu) { $tally.jamCpuSeconds = [int]$tally.jamCpuSeconds + $SecondsSinceLast; $tally.jamCpuPasses = [int]$tally.jamCpuPasses + 1 }
        if ($jamGpu) { $tally.jamGpuSeconds = [int]$tally.jamGpuSeconds + $SecondsSinceLast; $tally.jamGpuPasses = [int]$tally.jamGpuPasses + 1 }
        if ($jamMem) { $tally.jamMemSeconds = [int]$tally.jamMemSeconds + $SecondsSinceLast; $tally.jamMemPasses = [int]$tally.jamMemPasses + 1 }
        $tally.satCpuBefore = $satCpu
        $tally.satGpuBefore = $satGpu
        $tally.satMemBefore = $satMem
        # NOT $apps: PowerShell does not distinguish case, and the local list would silently overwrite the -Apps
        # parameter -- the tally then recorded nobody (caught on the first test, 28/09).
        $tallied = @{}
        foreach ($prop in $tally.apps.PSObject.Properties) { $tallied[$prop.Name] = $prop.Value }
        foreach ($app in @($Apps)) {
            if (-not $app -or -not $app.Name) { continue }
            $key = "$($app.Name)"
            $e = $tallied[$key]
            if (-not $e) {
                $e = [pscustomobject]@{ label = "$($app.Label)"; passes = 0; seconds = 0
                                        cpu = 0.0; gpu = 0.0; ram = 0.0; cpuMax = 0.0; gpuMax = 0.0
                                        jamSeconds = 0; jamCpu = 0.0; jamGpu = 0.0; jamPasses = 0 }
            }
            # IN THE WAY? Only while the machine is at its ceiling, only if this application is not the game's, and
            # only if it takes a share on its own -- dust at one percent never blocks anything.
            if (($jamCpu -or $jamGpu) -and ($GameNames -notcontains "$($app.Name)")) {
                $offender = (($jamCpu -and [double]$app.Cpu -ge $script:GameJamCpuOther) -or
                           ($jamGpu -and [double]$app.Gpu -ge $script:GameJamGpuOther))
                if ($offender) {
                    $e.jamPasses = [int]$e.jamPasses + 1
                    $e.jamSeconds = [int]$e.jamSeconds + $SecondsSinceLast
                    $e.jamCpu = [double]$e.jamCpu + [double]$app.Cpu
                    $e.jamGpu = [double]$e.jamGpu + [double]$app.Gpu
                }
            }
            $e.passes = [int]$e.passes + 1
            $e.seconds = [int]$e.seconds + $SecondsSinceLast
            $e.cpu = [double]$e.cpu + [double]$app.Cpu
            $e.gpu = [double]$e.gpu + [double]$app.Gpu
            $e.ram = [double]$e.ram + [double]$app.RamGb
            if ([double]$app.Cpu -gt [double]$e.cpuMax) { $e.cpuMax = [double]$app.Cpu }
            if ([double]$app.Gpu -gt [double]$e.gpuMax) { $e.gpuMax = [double]$app.Gpu }
            $tallied[$key] = $e
        }
        # BOUNDED: the sixty heaviest applications of the session. A game does not need a census of the computer.
        $keep = @($tallied.GetEnumerator() | Sort-Object { [double]$_.Value.cpu + [double]$_.Value.gpu } -Descending |
                    Select-Object -First 60)
        $ordered = [ordered]@{}
        foreach ($entry in $keep) { $ordered[$entry.Key] = $entry.Value }
        $tally.apps = [pscustomobject]$ordered
        Update-StateJson -Path $path -Set @{ session = $tally.session; game = $tally.game; startedAt = $tally.startedAt; lastAt = ([datetime]::UtcNow).ToString('o')
                                             passes = $tally.passes; seconds = $tally.seconds; apps = $tally.apps
                                             jamCpuSeconds = $tally.jamCpuSeconds; jamGpuSeconds = $tally.jamGpuSeconds
                                             jamMemSeconds = $tally.jamMemSeconds; satCpuBefore = $tally.satCpuBefore
                                             jamCpuPasses = $tally.jamCpuPasses; jamGpuPasses = $tally.jamGpuPasses
                                             jamMemPasses = $tally.jamMemPasses
                                             lostSeconds = $tally.lostSeconds; breaks = @($tally.breaks)
                                             satGpuBefore = $tally.satGpuBefore; satMemBefore = $tally.satMemBefore } | Out-Null
        <#
            AND THE PASS SAYS WHAT IS HAPPENING NOW, not only what the recap will say hours later.

            Everything needed is already computed here: whether the machine is at its ceiling on this pass and on the
            previous one, and which applications take a share of their own while it is. Returning it costs nothing,
            and it is what lets the card name the offender DURING the game -- on 29/09 the card said no other
            application was greedy while Steam held 12,9 % throughout the jams.
        #>
        $now = @()
        if ($jamCpu -or $jamGpu -or $jamMem) {
            foreach ($app in @($Apps)) {
                if (-not $app -or -not $app.Name) { continue }
                if ($GameNames -contains "$($app.Name)") { continue }
                if (($jamCpu -and [double]$app.Cpu -ge $script:GameJamCpuOther) -or
                    ($jamGpu -and [double]$app.Gpu -ge $script:GameJamGpuOther)) {
                    $now += [pscustomobject]@{ Name = "$($app.Name)"; Label = "$($app.Label)"
                                               Cpu = [double]$app.Cpu; Gpu = [double]$app.Gpu }
                }
            }
        }
        $kind = $null; $held = 0
        if ($jamCpu) { $kind = 'cpu'; $held = [int]$tally.jamCpuSeconds }
        elseif ($jamGpu) { $kind = 'gpu'; $held = [int]$tally.jamGpuSeconds }
        elseif ($jamMem) { $kind = 'memory'; $held = [int]$tally.jamMemSeconds }
        return [pscustomobject]@{ Jam = $kind; Seconds = $held
                                  Offenders = @($now | Sort-Object { $_.Cpu + $_.Gpu } -Descending) }
    } catch { }
}

# CLOSES THE TALLY and keeps the summary of the session. Returns it, or $null when there was nothing to close.
function Close-GameTally {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-GameTallyPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return $null }
        $tally = $null
        try { $tally = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $tally -or [int]$tally.passes -lt 2) { return $null }
        $apps = @()
        foreach ($prop in $tally.apps.PSObject.Properties) {
            $e = $prop.Value
            $passes = [Math]::Max(1, [int]$e.passes)
            $apps += [pscustomobject]@{
                name = $prop.Name; label = "$($e.label)"
                jamSeconds = [int]$e.jamSeconds
                jamPasses = [int]$e.jamPasses
                jamCpu = $(if ([int]$e.jamPasses -gt 0) { [Math]::Round([double]$e.jamCpu / [int]$e.jamPasses, 1) } else { 0 })
                jamGpu = $(if ([int]$e.jamPasses -gt 0) { [Math]::Round([double]$e.jamGpu / [int]$e.jamPasses, 1) } else { 0 })
                seconds = [int]$e.seconds
                cpu = [Math]::Round([double]$e.cpu / $passes, 1)
                gpu = [Math]::Round([double]$e.gpu / $passes, 1)
                ram = [Math]::Round([double]$e.ram / $passes, 2)
                cpuMax = [Math]::Round([double]$e.cpuMax, 1)
                gpuMax = [Math]::Round([double]$e.gpuMax, 1)
            }
        }
        # THE BOTTLENECKS OF THE SESSION, each with those who were in the way -- and a bottleneck with nobody in the
        # way is dropped, except the memory one, where the machine itself is the brake.
        $jams = @()
        $offenders = @($apps | Where-Object { [int]$_.jamPasses -gt 0 } | Sort-Object { $_.jamCpu + $_.jamGpu } -Descending)
        if ([int]$tally.jamCpuPasses -gt 0 -and @($offenders | Where-Object { $_.jamCpu -gt 0 }).Count) {
            $jams += [pscustomobject]@{ kind = 'cpu'; label = 'Processeur saturé'; seconds = [int]$tally.jamCpuSeconds
                                        who = @($offenders | Where-Object { $_.jamCpu -gt 0 } | Select-Object -First 3 |
                                                ForEach-Object { [pscustomobject]@{ label = $_.label; share = $_.jamCpu } }) }
        }
        if ([int]$tally.jamGpuPasses -gt 0 -and @($offenders | Where-Object { $_.jamGpu -gt 0 }).Count) {
            $jams += [pscustomobject]@{ kind = 'gpu'; label = 'Carte graphique saturée'; seconds = [int]$tally.jamGpuSeconds
                                        who = @($offenders | Where-Object { $_.jamGpu -gt 0 } | Select-Object -First 3 |
                                                ForEach-Object { [pscustomobject]@{ label = $_.label; share = $_.jamGpu } }) }
        }
        if ([int]$tally.jamMemPasses -gt 0) {
            $jams += [pscustomobject]@{ kind = 'memory'; label = 'Mémoire à la limite'; seconds = [int]$tally.jamMemSeconds; who = @() }
        }
        $summary = [ordered]@{
            game = "$($tally.game)"; startedAt = "$($tally.startedAt)"
            endedAt = ([datetime]::UtcNow).ToString('o'); seconds = [int]$tally.seconds; passes = [int]$tally.passes
            lostSeconds = [int]$tally.lostSeconds
            breaks = @(@($tally.breaks) | Where-Object { $_ } | Sort-Object { [int]$_.seconds } -Descending)
            jams = @($jams)
            apps = @($apps | Sort-Object { $_.cpu + $_.gpu } -Descending | Select-Object -First 15)
        }
        Add-HistoryLine -Path (Get-GameSessionsPath -Backend $Backend) -Line ($summary | ConvertTo-Json -Depth 6 -Compress) | Out-Null
        return [pscustomobject]$summary
    } catch { return $null }
}

# THE SESSIONS KEPT, most recent first. Bounded by -Last: the file holds one line per session, and nobody reads
# forty of them at once. A line that does not parse is skipped, never fatal.
function Get-GameSessions {
    param([string]$Backend = (Get-BackendRoot), [int]$Last = 40)
    $out = @()
    try {
        $path = Get-GameSessionsPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return @() }
        foreach ($line in @(Get-Content -LiteralPath $path -Tail $Last -ErrorAction Stop)) {
            if (-not "$line".Trim()) { continue }
            try { $out += ($line | ConvertFrom-Json) } catch { }
        }
    } catch { return @() }
    [array]::Reverse($out)
    return $out
}

# THE LAST SESSION KEPT, or $null. Read backwards: the file holds one line per session, the last one is the last game.
function Get-LastGameSession {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-GameSessionsPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return $null }
        $lines = @(Get-Content -LiteralPath $path -Tail 1 -ErrorAction Stop)
        if (-not $lines.Count) { return $null }
        return ($lines[-1] | ConvertFrom-Json)
    } catch { return $null }
}

function Get-GameSessionPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'run' -File 'game-session.json'
}

function Get-GameSession {
    param([string]$Backend = (Get-BackendRoot))
    $path = Get-GameSessionPath -Backend $Backend
    if (-not (Test-PathSafe $path)) { return $null }
    $session = $null
    try { $session = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $session -or -not $session.processId) { return $null }
    # THE PROCESS IS WHAT COUNTS. A game that stops does not come back through the probe to
    # say so: without this check, a finished game would stay open until the next computation.
    $proc = Get-Process -Id ([int]$session.processId) -ErrorAction SilentlyContinue
    if (-not $proc) { return $null }
    # AND IT MUST BE THE SAME PROCESS. Windows recycles ids: a closed game whose id is taken
    # over by a browser would make the session last for ever -- seen on 02/09 with a
    # simulated session that outlived its simulation.
    if ($session.path) {
        $exePath = $null
        try { $exePath = $proc.Path } catch { }
        if ($exePath -and "$exePath" -ne "$($session.path)") { return $null }
    }
    return $session
}

function Set-GameSession {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$ProcessId,
        [int]$BatteryPct = -1
    )
    $path = Get-GameSessionPath -Backend $Backend
    $known = Get-GameSession -Backend $Backend
    # SAME PROCESS MEANS SAME GAME: the start is never rebased, or the battery's fall would
    # start from zero at each computation and never cross a threshold.
    if ($known -and [int]$known.processId -eq $ProcessId) { return }
    $exePath = $null
    try { $exePath = (Get-Process -Id $ProcessId -ErrorAction Stop).Path } catch { }
    $session = [ordered]@{
        name      = $Name
        processId = $ProcessId
        path      = $exePath
        startedAt = ([datetime]::UtcNow).ToString('o')
        startPct  = $BatteryPct
    }
    try { ($session | ConvertTo-Json -Depth 4) | Out-File -FilePath $path -Encoding UTF8 } catch { }
}

function Clear-GameSession {
    param([string]$Backend = (Get-BackendRoot))
    $path = Get-GameSessionPath -Backend $Backend
    if (Test-PathSafe $path) { try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch { } }
}

# IS A GAME RUNNING? Its name, or $null. Reads the session state, whose process is checked (Get-GameSession): a
# closed game does not keep Vigie stepped back. Never throws.
function Get-GameModeName {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $session = Get-GameSession -Backend $Backend
        if ($session -and $session.name) { return "$($session.name)" }
    } catch { }
    return $null
}
