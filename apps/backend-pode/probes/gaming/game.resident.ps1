# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    RESIDENT: it knows when a game starts, within a second.

    IT MEASURES NOTHING. It subscribes to process starts and stops -- Windows tells it --
    and hands every new process to identification, which applies its methods
    (probes/gaming/identify). When nothing launches, it costs nothing.

    This replaces the former detection: it read GPU counters every minute, cost two and a
    half seconds, sometimes came back empty, and the card then announced "no game" --
    Odyssey recognised at one reading, ignored at the next (02/09).

    IT LIVES WITH THE SERVER APP (targeting/residents.md): the server arms it, it stops as
    soon as the server is gone, the server re-arms it if it dies. While arming it SWEEPS the
    running processes, to catch a game started while it was away.

    THE SUBSCRIPTION REQUIRES ELEVATION: denied from an ordinary session, granted to the
    server app. A denial is not silence -- it is written into the resident's state.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Backend,
    [Parameter(Mandatory)][int]$ServerPid
)
$ErrorActionPreference = 'Stop'
. (Join-Path $Backend 'lib/common.ps1')

$KEY = 'game'

# A process descriptor, shaped the way identification methods expect it.
function Get-ProcessDescriptor {
    param([int]$ProcessId, [int]$ParentId = 0)
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return $null }
    $path = $null
    try { $path = $proc.Path } catch { }
    if (-not $path) { return $null }
    if (-not $ParentId) {
        $ParentId = Get-ParentProcessId -ProcessId $ProcessId
    }
    $parentPath = $null
    if ($ParentId) { try { $parentPath = (Get-Process -Id $ParentId -ErrorAction Stop).Path } catch { } }
    [pscustomobject]@{
        Id = $ProcessId; Name = $proc.ProcessName; Path = $path
        ParentId = $ParentId; ParentPath = $parentPath
    }
}

# A game session begins. We note who, where, why -- and the battery charge, without which
# "it is draining while you play" cannot be said.
function Open-GameSession {
    param($Descriptor, $Verdict, [int]$SessionId = -1, [string]$Sid)
    $known = Get-GameSession -Backend $Backend
    if ($known -and [int]$known.processId -eq [int]$Descriptor.Id) { return }
    $battery = Get-BatteryState
    $session = [ordered]@{
        name       = (Get-AppDisplayName -ProcessName $Descriptor.Name -Path $Descriptor.Path -Complet)
        processId  = $Descriptor.Id
        path       = $Descriptor.Path
        # WHO STARTED IT. Identification reads this parent to recognise a game (20-launcher);
        # the card needs it too, to tell the platform's own components apart from strangers.
        launcher   = $Descriptor.ParentPath
        reason     = $Verdict.Reason
        method     = $Verdict.Method
        sessionId  = $SessionId
        sid        = $Sid
        startedAt  = ([datetime]::UtcNow).ToString('o')
        startPct   = $(if ($null -ne $battery.Pct) { [int]$battery.Pct } else { -1 })
    }
    try {
        $path = Get-GameSessionPath -Backend $Backend
        ($session | ConvertTo-Json -Depth 4) | Out-File -FilePath $path -Encoding UTF8
        Write-Log -Backend $Backend -Name 'state' -NoEcho -Message ("jeu detecte : " + $session.name + " -- " + $Verdict.Reason)
    } catch { }
}

# --- Arming ---------------------------------------------------------------------
$subscribed = $false
try {
    # STARTS ONLY. The stop events were subscribed too and did nothing but rewrite the state file, each one: twice the
    # queue for no information (19/09).
    $null = Register-CimIndicationEvent -ClassName Win32_ProcessStartTrace -SourceIdentifier 'vigieGameStart' -ErrorAction Stop
    $subscribed = $true
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $PID; state = 'arme'; error = $null }
} catch {
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $PID; state = 'abonnement refuse'
                                                             error = "$($_.Exception.Message)" }
}

# --- Initial sweep: what is already running --------------------------------------
# Without it, a game started during an update would stay invisible until its next start.
try {
    $lastBeat = Get-Date
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        # IT BEATS WHILE IT SWEEPS: on a slow computer the sweep alone outlasted the 180 s the server allows (17/09).
        if (((Get-Date) - $lastBeat).TotalSeconds -ge 20) {
            Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ sweepingAt = ([datetime]::UtcNow).ToString('o') }
            $lastBeat = Get-Date
        }
        $descriptor = Get-ProcessDescriptor -ProcessId $proc.Id
        if (-not $descriptor) { continue }
        $verdict = Test-ProcessIsGame -Backend $Backend -Process $descriptor
        if ($verdict.IsGame) { Open-GameSession -Descriptor $descriptor -Verdict $verdict; break }
    }
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ scannedAt = ([datetime]::UtcNow).ToString('o') }
} catch { }

# --- The resident's life ---------------------------------------------------------
$superseded = $false
while ($true) {
    # IT DIES WITH THE SERVER. Without this check, an update would leave a subscribed
    # orphan nobody could see or kill.
    if (-not (Get-Process -Id $ServerPid -ErrorAction SilentlyContinue)) { break }
    # A REPLACED COPY STOPS: the state names the copy the server armed last, and it is not this one.
    $own = Get-ResidentState -Backend $Backend -Key $KEY
    if ($own -and $own.processId -and [int]$own.processId -ne $PID) { $superseded = $true; break }

    <#
        THE QUEUE NEVER SILENCES THE HEARTBEAT. The beat used to come only once every queued start had been judged --
        40 ms each, up to 300 -- and each one also rewrote the state file. On 18/09 the beat stopped from 16:28 to 17:46,
        twenty minutes after Windows restarted, while the process was alive: the sentinel said "inconnu", no game could be
        detected, and Vigie looked absent. The beat now goes out every 5 s even in the middle of a queue, the state is
        written once per batch, and a long queue is logged, with its length and its duration, so that the next one is
        measured instead of guessed.
    #>
    if ($subscribed) {
        $batch = @(Get-Event -ErrorAction SilentlyContinue)
        if ($batch.Count) {
            $batchWatch = [Diagnostics.Stopwatch]::StartNew()
            $lastBeat = Get-Date
            foreach ($event in $batch) {
                try {
                    $indication = $event.SourceEventArgs.NewEvent
                    if ($event.SourceIdentifier -eq 'vigieGameStart') {
                        $descriptor = Get-ProcessDescriptor -ProcessId ([int]$indication.ProcessID) -ParentId ([int]$indication.ParentProcessID)
                        if ($descriptor) {
                            $verdict = Test-ProcessIsGame -Backend $Backend -Process $descriptor
                            if ($verdict.IsGame) {
                                Open-GameSession -Descriptor $descriptor -Verdict $verdict `
                                                 -SessionId ([int]$indication.SessionID) -Sid "$($indication.Sid)"
                            }
                        }
                    }
                } catch { }
                Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
                if (((Get-Date) - $lastBeat).TotalSeconds -ge 5) {
                    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ beatAt = ([datetime]::UtcNow).ToString('o') }
                    $lastBeat = Get-Date
                }
            }
            Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ lastEventAt = ([datetime]::UtcNow).ToString('o') }
            if ($batch.Count -ge 100 -or $batchWatch.Elapsed.TotalSeconds -ge 30) {
                Write-Log -Backend $Backend -Name 'state' -NoEcho -Message ("detection des jeux : " + $batch.Count + " demarrages de processus traites en " +
                                                                           [math]::Round($batchWatch.Elapsed.TotalSeconds, 1) + " s")
            }
        }
    }

    # THE HEARTBEAT: this is what proves we are alive. A frozen process still exists but
    # stops beating, and the server will re-arm it. IT NEVER WRITES ITS OWN NUMBER here: every copy doing so on 17/09
    # hid the older ones from the server, which then killed only one of them.
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ beatAt = ([datetime]::UtcNow).ToString('o') }
    Start-Sleep -Seconds 5
}

Unregister-Event -SourceIdentifier 'vigieGameStart' -ErrorAction SilentlyContinue
# A REPLACED COPY LEAVES THE STATE ALONE: it belongs to the copy that replaced it.
if (-not $superseded) { Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $null; state = 'arrete' } }
