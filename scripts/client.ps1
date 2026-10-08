# @author Florent HAZARD <f.hazard@sowapps.com>
<#
.SYNOPSIS
    Drives the Vigie client app in the notification area: its state, stopping it, restarting it.

.DESCRIPTION
    Intent: reach an elevated app from an ordinary session without killing it blind. The client app runs ELEVATED:
    from a normal session one can neither read its command line nor signal a kernel object it created, so it had
    to be killed blind, which left its icon behind as a ghost in the notification area.

    Usage: this script drops an ORDER into apps/client/var/run/; the client app reads it and exits cleanly,
    releasing its icon. The same folder carries a heartbeat (client.alive), which makes its state knowable without
    inspecting the process.

    Inspectable by eye, scriptable from anything, and open to change: a new order is a new file name, without
    touching the mechanism.

.PARAMETER Status
    Displays whether the client app is alive, since when, and the state it is showing.

.PARAMETER Stop
    Asks it to stop. It waits for the confirmation through the disappearance of the heartbeat.

.PARAMETER Restart
    Asks the client app to restart itself.

.PARAMETER TimeoutSec
    How long to wait for the confirmation (15 s by default).

.EXAMPLE
    pwsh -File .\scripts\client.ps1 -Status

.EXAMPLE
    pwsh -File .\scripts\client.ps1 -Stop

.NOTES
    Exit codes: 0 = success; 1 = no client app; 2 = the order was not taken into account in time.
    To start the client app: Start-ScheduledTask -TaskName Vigie
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Status')]  [switch] $Status,
    [Parameter(ParameterSetName = 'Stop')]    [switch] $Stop,
    [Parameter(ParameterSetName = 'Restart')] [switch] $Restart,
    # 15 s was too tight. Measured on 26/08: a full restart takes 9 to 11 s (the order read within the second,
    # pwsh plus the C# compilations ~5 s, the first heartbeat 2 s later). On a busy machine -- a deployment under
    # way, precisely -- and the count is reached. So we were declaring a failure on a restart that got there.
    [int] $TimeoutSec = 45
)

$ErrorActionPreference = 'Stop'
$repoRoot  = Split-Path $PSScriptRoot -Parent
# THE SAME COMPUTATION AS THE CLIENT APP, AND THROUGH THE SAME CODE. This path was written by hand: on a shared
# installation, the sender therefore looked for the heartbeat inside Program Files while the client app was
# writing it in the account's profile. Program Files is READ ONLY (D97); it is Get-VarPath that knows where the
# data goes, and nobody else.
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$runDir    = Get-VarPath -Backend (Join-Path $repoRoot 'apps/client') -Kind 'run'
$heartbeat = Join-Path $runDir 'client.alive'

# The client app writes its heartbeat every 8 s: past 30 s, we consider it dead.
$THRESHOLD_SEC = 30

function Get-ClientState {
    if (-not (Test-Path -LiteralPath $heartbeat)) { return $null }
    try {
        # UTF8 explicitly: the state carries accents.
        $parts = (Get-Content -LiteralPath $heartbeat -Raw -Encoding UTF8).Trim() -split ';'
        $age = ([datetime]::Now - [datetime]::Parse($parts[1])).TotalSeconds
        return [pscustomobject]@{ Pid = [int]$parts[0]; AgeSec = [int]$age; Etat = $parts[2] }
    } catch { return $null }
}

function Send-Order {
    param([string] $Name)
    if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Path $runDir -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $runDir $Name) -Value '' -Encoding ASCII -NoNewline
}

# --- Etat --------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Status' -or $Status) {
    $t = Get-ClientState
    if ($t -and $t.AgeSec -le $THRESHOLD_SEC) {
        Write-Info (Get-Label 'client.en-marche-pid' $t.Pid $t.Etat $t.AgeSec)
        exit 0
    }
    if ($t) { Write-Host (Get-Label 'client.arrete-dernier-signe' $t.AgeSec $t.Pid) }
    else    { Write-Host (Get-Label 'client.arrete-aucun-battement') }
    exit 1
}

# --- Arret / redemarrage -----------------------------------------------------
$before = Get-ClientState
if (-not $before -or $before.AgeSec -gt $THRESHOLD_SEC) {
    # RESTARTING WHAT IS NO LONGER RUNNING MEANS STARTING IT.
    #
    # We returned 1 saying "nothing to do" -- and the update, which calls this script to reload the new code,
    # concluded there had been a failure while the deployment had succeeded: "the deployment is done, but the
    # restart did not get there" (observed on 28/08). A stop is not a failed restart: it is precisely the case
    # where one has to start.
    if (-not $Restart) {
        Write-Info (Get-Label 'client.deja-arrete-rien')
        exit 0
    }
    Write-Info (Get-Label 'client.arrete-demarrage')
    try {
        Start-ScheduledTask -TaskName 'Vigie' -ErrorAction Stop
    } catch {
        Write-Warn (Get-Label 'client.la-tache-de-demarrage' $_.Exception.Message)
        exit 2
    }
    # WE OBSERVE (D43): a task that has been started does not prove the client app alive.
    $limite = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $limite) {
        Start-Sleep -Milliseconds 800
        $e = Get-ClientState
        if ($e -and $e.AgeSec -le $THRESHOLD_SEC) {
            Write-Info (Get-Label 'client.demarre-pid' $e.Pid)
            exit 0
        }
    }
    Write-Warn (Get-Label 'client.pas-donne-signe')
    exit 2
}

$order = if ($Restart) { 'restart' } else { 'stop' }
$ack   = Join-Path $runDir ($order + '.ack')
Remove-Item -LiteralPath $ack -Force -ErrorAction SilentlyContinue
Send-Order $order
Write-Info (Get-Label 'client.ordre-depose-pid' $order $before.Pid)
# 1) HAS IT READ THE ORDER? The client app lays an acknowledgement down as soon as it consumes it. Without that
#    step, a failure did not say whether one had to troubleshoot a frozen client app or a slow restart: two
#    different causes, two different gestures.
$vuLe = (Get-Date).AddSeconds(10)
$lu = $false
while ((Get-Date) -lt $vuLe) {
    if (Test-Path -LiteralPath $ack) { $lu = $true; break }
    Start-Sleep -Milliseconds 200
}
if ($lu) {
    Remove-Item -LiteralPath $ack -Force -ErrorAction SilentlyContinue
    Write-Info (Get-Label 'client.ordre-lu-par-le')
} else {
    Write-Warn (Get-Label 'client.ordre-pas-lu')
    Write-Info (Get-Label 'client.verifie-apps-client-var')
    exit 2
}

<#
    WE DO NOT WAIT FOR AN APPLICATION TO START.

    A rule already laid down for the server app, and broken here: we were watching for 45 seconds for a NEW
    process number to appear. On 30/08 the restart returned code 2 -- so the installation announced two failures
    -- while the client app was running: the old instance had not released its lock yet when the new one started,
    the new one exited on "already running", and the number never changed.

    THE ACKNOWLEDGEMENT IS THE PROOF. It is written by the client app itself, at the moment it takes the order:
    from then on it stops and sets off again, and how long it takes to do so is no business of whoever asked.

    A STOP, on the other hand, is observed: the heartbeat disappears, which is a fact, not an estimate -- and that
    is precisely what we want to check before handing control back.
#>
if ($Restart) {
    Write-Host (Get-Label 'client.relance-demandee')
    exit 0
}

$fin = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $fin) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-ClientState)) {
        Write-Host (Get-Label 'client.arrete-proprement-icone'); exit 0
    }
}

# The order was indeed read (the acknowledgement arrived): what is missing is the RETURN.
Write-Warn (Get-Label 'client.ordre-lu-mais-rien' $TimeoutSec)
Write-Info (Get-Label 'client.la-relance-peut-etre')
exit 2
