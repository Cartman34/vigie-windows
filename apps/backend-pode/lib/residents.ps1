# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, log, native, paths, settings, var
<#
    Intent: WHAT LIVES ALONGSIDE THE SERVER APP: everything else in Vigie is triggered -- a request, a timer, a button -- while a RESIDENT stays alive, listens, and holds a state. The mechanism assumes nothing about what a resident does.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    SENTINELS: CHEAP READINGS, AND AN EVENT WHEN THE VALUE CHANGES.

    This is NOT recomputing cards in a loop. A card is expensive -- thirteen seconds for the
    deployment one -- and most of what it holds does not move within the minute. So a few
    precise, cheap FACTS are read instead, declared by each module; when a reading changes it
    raises an event, and it is the event that recomputes the cards the module named.

    A module declares:
      - a "<key>.watch.ps1" file in its folder: ONE reading, ONE comparable value -- a
        boolean, a number, a short string. Nothing else.
      - a "Sentinels" entry in its module.psd1: the cadence, and the cards to recompute.

    The detail: doc/progress/targeting/surveillance.md.
#>

<#
    RESIDENTS: WHAT LIVES ALONGSIDE THE SERVER APP (target: targeting/residents.md).

    Everything else in Vigie is triggered -- a request, a timer, a button. A RESIDENT stays
    alive instead: it listens, it consumes, it holds a state. The first need that requires
    one is the subscription to process starts, but the mechanism assumes NOTHING about what
    a resident does.

    A module declares one in its module.psd1:

        Residents = @(
            @{ Key = 'game'; Label = '<the label the card displays>' }
        )

    and drops a "<key>.resident.ps1" script next to it. The server arms it at startup, stops
    it with itself, re-arms it if it dies, and its state is visible.
#>
function Get-ResidentDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    if (-not (Test-PathSafe $probesDir)) { return @() }
    $off = @(Get-InactiveUnits -Backend $Backend)
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if ($off -contains $dir.Name) { continue }
        $decl = $null
        try { $decl = Import-PowerShellDataFile -Path (Join-Path $dir.FullName 'module.psd1') } catch { }
        if (-not $decl -or -not $decl.Residents) { continue }
        foreach ($r in @($decl.Residents)) {
            if (-not $r.Key) { continue }
            $script = Join-Path $dir.FullName ("$($r.Key).resident.ps1")
            if (-not (Test-PathSafe $script)) { continue }
            $out += [pscustomobject]@{
                Unit   = $dir.Name
                Key    = "$($r.Key)"
                Label  = $(if ($r.Label) { "$($r.Label)" } else { "$($r.Key)" })
                Script = $script
            }
        }
    }
    return $out
}

# A RESIDENT'S STATE, written by ITSELF: it says it is alive by rewriting it. The server
# only reads it -- a resident that no longer beats is dead, even if its process still
# exists.
function Get-ResidentStatePath {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key)
    Get-VarPath -Backend $Backend -Kind 'run' -File ('resident-' + $Key + '.json')
}

function Get-ResidentState {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key)
    $path = Get-ResidentStatePath -Backend $Backend -Key $Key
    if (-not (Test-PathSafe $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Set-ResidentState {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][hashtable]$Fields
    )
    $path = Get-ResidentStatePath -Backend $Backend -Key $Key
    $state = [ordered]@{}
    $known = Get-ResidentState -Backend $Backend -Key $Key
    if ($known) { foreach ($prop in $known.PSObject.Properties) { $state[$prop.Name] = $prop.Value } }
    foreach ($name in $Fields.Keys) { $state[$name] = $Fields[$name] }
    $state['at'] = ([datetime]::UtcNow).ToString('o')
    try {
        $tmp = "$path.tmp"
        ($state | ConvertTo-Json -Depth 6) | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $path -Force
    } catch { }
}

<#
    ALIVE? Two conditions, and both count: its process exists, and it has beaten recently.
    A frozen process satisfies the first and not the second -- exactly the case we want to
    see.
#>
function Test-ResidentAlive {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key,
        [int]$BeatSeconds = 180
    )
    $state = Get-ResidentState -Backend $Backend -Key $Key
    if (-not $state -or -not $state.processId) { return $false }
    if (-not (Get-ResidentProcess -State $state)) { return $false }
    if (-not $state.at) { return $false }
    try { return ((([datetime]::UtcNow) - (ConvertTo-UtcDate $state.at)).TotalSeconds -lt $BeatSeconds) }
    catch { return $false }
}

<#
    ARMING. A resident runs in ITS OWN process, not in one of the server's runspaces: Pode
    recycles those, and a subscription placed in one would vanish without a word. A process
    can be seen, watched and killed.

    It inherits the server's rights -- that is what lets the process-start subscription
    exist at all, since an ordinary session is denied (measured on 02/09).

    THE SERVER'S PROCESS NUMBER IS HANDED OVER: the resident stops when the server stops.
    That is the only way to hold "no resident outlives the server app" without leaving an
    orphan nobody can see or kill.
#>
function Start-Resident {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)]$Declaration
    )
    # ARMED ONLY WHEN ITS PROCESS IS GONE (Invoke-ResidentPass), so nothing is stopped here: Vigie stops no process on
    # its own (owner, 18/09). The state is only cleared of the vanished number.
    Set-ResidentState -Backend $Backend -Key $Declaration.Key -Fields @{ processId = $null; state = 'arrete' }
    $pwsh = $null
    try { $pwsh = (Get-Process -Id $PID).Path } catch { }
    if (-not $pwsh) { $pwsh = 'pwsh.exe' }
    try {
        # Raw values: Start-ChildProcess quotes them (D116). Passing them bare to
        # Start-Process is what killed this child at every arming on 02/09 -- the shared
        # install lives under "C:\Program Files\Sowapps\Vigie", and "C:\Program" is not a
        # script.
        $child = Start-ChildProcess -FilePath $pwsh `
                    -Arguments @('-NoProfile', '-File', $Declaration.Script,
                                 '-Backend', $Backend, '-ServerPid', $PID) `
                    -Options @{ PassThru = $true; WindowStyle = 'Hidden' }
        Set-ResidentState -Backend $Backend -Key $Declaration.Key -Fields @{
            processId = $child.Id; serverPid = $PID; state = 'arme'
            armedAt = ([datetime]::UtcNow).ToString('o'); error = $null }
        return $true
    } catch {
        Set-ResidentState -Backend $Backend -Key $Declaration.Key -Fields @{
            processId = $null; state = 'echec'; error = "$($_.Exception.Message)" }
        return $false
    }
}

<#
    THE PASS: arms what is missing, re-arms what is dead. Called by the same one-minute
    loop as the sentinels -- one rhythm, one place.
#>
function Invoke-ResidentPass {
    param([string]$Backend = (Get-BackendRoot))
    $started = @()
    foreach ($declaration in @(Get-ResidentDeclarations -Backend $Backend)) {
        # RE-ARMED WHEN ITS PROCESS IS GONE, NEVER BECAUSE IT BEATS LATE. A slow process is not dead: re-arming it on a
        # late beat started a second one beside it, then a third, 115 on 17/09. A late beat is shown on the card.
        if (Test-ResidentProcessPresent -Backend $Backend -Key $declaration.Key) { continue }
        if (Start-Resident -Backend $Backend -Declaration $declaration) {
            $started += $declaration.Key
            try { Write-Log -Backend $Backend -Name 'state' -NoEcho -Message ("resident arme : " + $declaration.Label) } catch { }
        }
    }
    return $started
}

# WHAT CAN BE SAID OF EACH RESIDENT, for a card or a diagnosis: a watch nobody knows the
# health of is worth nothing.
<#
    ALIVE DOES NOT MEAN OPERATIONAL.

    A resident whose process runs and beats may have placed nothing: its subscription was
    denied, and it says so in its state. Believing it works because it breathes is exactly
    the mistake that would announce "no game" while measuring nothing. What it placed is
    therefore reported ALWAYS, without exception.
#>
function Test-ResidentOperational {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key
    )
    if (-not (Test-ResidentAlive -Backend $Backend -Key $Key)) { return $false }
    $state = Get-ResidentState -Backend $Backend -Key $Key
    return ($state -and "$($state.state)" -eq 'arme')
}

# ITS PROCESS STILL EXISTS, whatever its beat says: the only condition for leaving a resident alone.
# THE PROCESS A RESIDENT'S STATE NAMES, or $null -- and only if it is still that resident. A process id is reused by
# Windows once its process is gone, and the state survives a restart of the computer: an id alone let any program
# pass for the resident, which was then never re-armed. The process must be a PowerShell started after the arming;
# when its start time cannot be read, the name alone decides.
function Get-ResidentProcess {
    param($State)
    if (-not $State -or -not $State.processId) { return $null }
    $process = Get-Process -Id ([int]$State.processId) -ErrorAction SilentlyContinue
    if (-not $process -or $process.ProcessName -notin @('pwsh', 'powershell')) { return $null }
    if ($State.armedAt) {
        $armed = $null; $started = $null
        try { $armed = ConvertTo-UtcDate $State.armedAt } catch { }
        try { $started = $process.StartTime.ToUniversalTime() } catch { }
        if ($armed -and $started -and $started -lt $armed.AddSeconds(-30)) { return $null }
    }
    return $process
}

function Test-ResidentProcessPresent {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key)
    $state = Get-ResidentState -Backend $Backend -Key $Key
    if (-not $state -or -not $state.processId) { return $false }
    return [bool](Get-ResidentProcess -State $state)
}

function Get-ResidentHealth {
    param([string]$Backend = (Get-BackendRoot))
    foreach ($declaration in @(Get-ResidentDeclarations -Backend $Backend)) {
        $state = Get-ResidentState -Backend $Backend -Key $declaration.Key
        # THE REASONS A SLOW OR DOUBLED RESIDENT IS SHOWN WITH: the age of its beat, what its process uses, and every
        # process running its script -- counted, never stopped.
        $beatAge = $null
        try { if ($state -and $state.at) { $beatAge = [int](([datetime]::UtcNow) - (ConvertTo-UtcDate $state.at)).TotalSeconds } } catch { }
        $process = $null
        $process = Get-ResidentProcess -State $state
        $copies = @()
        try {
            $leaf = Split-Path "$($declaration.Script)" -Leaf
            $copies = @(Get-CimInstance Win32_Process -Filter ("Name='pwsh.exe' AND CommandLine LIKE '%" + $leaf + "%'") -ErrorAction Stop |
                        ForEach-Object { [pscustomobject]@{ Id = [int]$_.ProcessId; StartedAt = $_.CreationDate } })
        } catch { }
        [pscustomobject]@{
            Key       = $declaration.Key
            Label     = $declaration.Label
            Present     = [bool]$process
            Alive       = (Test-ResidentAlive -Backend $Backend -Key $declaration.Key)
            Operational = (Test-ResidentOperational -Backend $Backend -Key $declaration.Key)
            State     = $(if ($state) { "$($state.state)" } else { 'jamais arme' })
            ArmedAt   = $(if ($state) { $state.armedAt } else { $null })
            LastBeat  = $(if ($state) { $state.at } else { $null })
            BeatAge   = $beatAge
            CpuSeconds = $(if ($process) { try { [int]$process.TotalProcessorTime.TotalSeconds } catch { $null } } else { $null })
            # IN RAM, not committed (Get-ProcessMemoryUse): the figures say what is really in RAM (18/09).
            MemoryMb  = $(if ($process) { $use = Get-ProcessMemoryUse; if ($use.ContainsKey($process.Id)) { [int]($use[$process.Id].Ram / 1MB) } else { $null } } else { $null })
            Copies    = $copies
            LastEvent = $(if ($state) { $state.lastEventAt } else { $null })
            Conflict  = $(if ($state) { $state.lastConflict } else { $null })
            Error     = $(if ($state) { $state.error } else { $null })
        }
    }
}
