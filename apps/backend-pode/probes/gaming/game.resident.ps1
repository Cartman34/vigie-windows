# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    RESIDENT : il sait quand un jeu demarre, a la seconde.

    IL NE MESURE RIEN. Il s abonne aux demarrages et aux arrets de processus -- Windows le
    previent -- et presente chaque nouveau processus a l identification, qui applique ses
    methodes (probes/gaming/identify). Quand rien ne se lance, il ne coute rien.

    C est ce qui remplace l ancienne detection : elle lisait les compteurs GPU toutes les
    minutes, coutait deux secondes et demie, revenait parfois vide, et la carte annoncait
    alors « aucun jeu » -- Odyssey reconnu a un releve, ignore au suivant (02/09).

    IL VIT AVEC L APP SERVEUR (targeting/residents.md) : elle l arme, il s arrete des
    qu elle disparait, elle le rearme s il meurt. En s armant il BALAIE les processus en
    cours, pour rattraper une partie lancee pendant qu il n etait pas la.

    L ABONNEMENT EXIGE L ELEVATION : refuse depuis une session ordinaire, accorde a l app
    serveur. Un refus n est pas un silence -- il s ecrit dans l etat du resident.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Backend,
    [Parameter(Mandatory)][int]$ServerPid
)
$ErrorActionPreference = 'Stop'
. (Join-Path $Backend 'lib/common.ps1')

$KEY = 'game'

# Le descripteur d un processus, tel que les methodes d identification l attendent.
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

# Une partie commence. On note qui, ou, pourquoi -- et la charge de la batterie, sans
# laquelle « elle se vide pendant que vous jouez » ne peut pas se dire.
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

# --- Armement -------------------------------------------------------------------
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

# --- Balayage initial : ce qui tourne deja ---------------------------------------
# Sans lui, une partie lancee pendant une mise a jour resterait invisible jusqu a son
# prochain demarrage.
try {
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        $descriptor = Get-ProcessDescriptor -ProcessId $proc.Id
        if (-not $descriptor) { continue }
        $verdict = Test-ProcessIsGame -Backend $Backend -Process $descriptor
        if ($verdict.IsGame) { Open-GameSession -Descriptor $descriptor -Verdict $verdict; break }
    }
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ scannedAt = ([datetime]::UtcNow).ToString('o') }
} catch { }

# --- La vie du resident ----------------------------------------------------------
while ($true) {
    # IL MEURT AVEC LE SERVEUR. Sans cette verification, une mise a jour laisserait un
    # orphelin abonne que personne ne saurait ni voir ni tuer.
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

    # LE BATTEMENT : c est lui qui prouve qu on est vivant. Un processus fige existe
    # encore mais ne bat plus, et le serveur le rearmera.
    Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $PID }
    Start-Sleep -Seconds 5
}

Unregister-Event -SourceIdentifier 'vigieGameStart' -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier 'vigieGameStop'  -ErrorAction SilentlyContinue
Set-ResidentState -Backend $Backend -Key $KEY -Fields @{ processId = $null; state = 'arrete' }
