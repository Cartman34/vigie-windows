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
        try { $ParentId = [int](Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop).ParentProcessId } catch { }
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
    $null = Register-CimIndicationEvent -ClassName Win32_ProcessStartTrace -SourceIdentifier 'vigieGameStart' -ErrorAction Stop
    $null = Register-CimIndicationEvent -ClassName Win32_ProcessStopTrace  -SourceIdentifier 'vigieGameStop'  -ErrorAction Stop
    $subscribed = $true
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $PID; state = 'arme'; error = $null }
} catch {
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $PID; state = 'abonnement refuse'
                                                             error = "$($_.Exception.Message)" }
}

# --- Initial sweep: what is already running --------------------------------------
# Without it, a game started during an update would stay invisible until its next start.
try {
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        $descriptor = Get-ProcessDescriptor -ProcessId $proc.Id
        if (-not $descriptor) { continue }
        $verdict = Test-ProcessIsGame -Backend $Backend -Process $descriptor
        if ($verdict.IsGame) { Open-GameSession -Descriptor $descriptor -Verdict $verdict; break }
    }
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ scannedAt = ([datetime]::UtcNow).ToString('o') }
} catch { }

# --- The resident's life ---------------------------------------------------------
while ($true) {
    # IT DIES WITH THE SERVER. Without this check, an update would leave a subscribed
    # orphan nobody could see or kill.
    if (-not (Get-Process -Id $ServerPid -ErrorAction SilentlyContinue)) { break }

    if ($subscribed) {
        foreach ($event in @(Get-Event -ErrorAction SilentlyContinue)) {
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
                Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ lastEventAt = ([datetime]::UtcNow).ToString('o') }
            } catch { }
            Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
        }
    }

    # THE HEARTBEAT: this is what proves we are alive. A frozen process still exists but
    # stops beating, and the server will re-arm it.
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $PID }
    Start-Sleep -Seconds 5
}

Unregister-Event -SourceIdentifier 'vigieGameStart' -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier 'vigieGameStop'  -ErrorAction SilentlyContinue
Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $null; state = 'arrete' }
