# @author Florent HAZARD <f.hazard@sowapps.com>
<# Probe: the processes of Vigie itself -- the server app and everything it started (CORE-SELFWATCH). READ ONLY.

   Why it exists: on 17/09 the game resident was re-armed while alive, 115 copies held 19 GB, and the memory and the
   network ports of the computer ran out. No card counted Vigie's own processes: the user saw a slow computer and
   "server unreachable", nothing that pointed at Vigie.

   The tree comes from one snapshot of Windows (scripts/lib/system-metrics.ps1, 15 ms for 570 processes). Vigie stops
   none of these processes on its own: the card names them, and the user decides. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')

$maxCount  = [int](Get-ModuleSetting -Unit 'debug' -Key 'SelfMaxProcesses')
$maxMemory = [int](Get-ModuleSetting -Unit 'debug' -Key 'SelfMaxMemoryMb')

$cfg = Get-Config -Backend $backend
$listener = Get-PortListener -Port ([int]$cfg.Port)
$serverId = if ($listener) { [int]$listener.OwningProcess } else { 0 }

# Which resident each process is, from the state every resident writes.
$residentOf = @{}
$residentStates = @()
foreach ($declaration in @(Get-ResidentDeclarations -Backend $backend)) {
    $state = Get-ResidentState -Backend $backend -Key $declaration.Key
    if ($state -and $state.processId) {
        $residentOf[[int]$state.processId] = $declaration.Label
        $residentStates += [pscustomobject]@{ Label = $declaration.Label; ProcessId = [int]$state.processId }
    }
}

$members = @()
if ($serverId) {
    $members += [pscustomobject]@{ ProcessId = $serverId; ParentId = 0; Name = 'pwsh.exe'; Role = 'App serveur' }
    foreach ($d in @(Get-ProcessDescendants -ProcessId $serverId)) {
        $role = if ($residentOf.ContainsKey($d.ProcessId)) { 'Résident ' + $residentOf[$d.ProcessId] }
                elseif ($d.Name -eq 'conhost.exe') { 'Console attachée' }
                elseif ($d.Name -eq 'pwsh.exe') { 'Tâche de fond' }
                else { 'Lancé par Vigie' }
        $members += [pscustomobject]@{ ProcessId = $d.ProcessId; ParentId = $d.ParentId; Name = $d.Name; Role = $role }
    }
}
# A RESIDENT OUTSIDE THE TREE is an orphan: its server was replaced and it kept running. It is still Vigie's.
$orphans = @()
foreach ($r in $residentStates) {
    if (@($members | Where-Object ProcessId -eq $r.ProcessId).Count) { continue }
    if (Get-Process -Id $r.ProcessId -ErrorAction SilentlyContinue) {
        $orphans += $r
        $members += [pscustomobject]@{ ProcessId = $r.ProcessId; ParentId = 0; Name = 'pwsh.exe'; Role = 'Résident ' + $r.Label + ', hors de l''app serveur' }
    }
}

# IN RAM AND COMMITTED, apart (Get-ProcessMemoryUse): the thresholds follow what is really in RAM.
$memoryUse = Get-ProcessMemoryUse
$totalBytes = 0.0
$rows = @()
foreach ($m in $members) {
    $bytes = 0.0
    $committed = 0.0
    $started = ''
    if ($memoryUse.ContainsKey($m.ProcessId)) { $bytes = $memoryUse[$m.ProcessId].Ram; $committed = $memoryUse[$m.ProcessId].Committed }
    try {
        $p = Get-Process -Id $m.ProcessId -ErrorAction Stop
        try { if ($p.StartTime) { $started = $p.StartTime.ToString('dd/MM HH:mm') } } catch { }
    } catch { }
    $totalBytes += $bytes
    $m | Add-Member -NotePropertyName Bytes -NotePropertyValue $bytes
    $rows += ,@($m.Role, $m.Name, "$($m.ProcessId)", (($bytes / 1MB).ToString('N0', $fr) + ' Mo'), (($committed / 1MB).ToString('N0', $fr) + ' Mo'), $started)
}
$totalMb = [math]::Round($totalBytes / 1MB)

$countStatus  = if (-not $serverId) { 'warn' } elseif ($members.Count -gt $maxCount -or $orphans.Count) { 'error' } else { 'ok' }
$memoryStatus = if ($totalMb -gt $maxMemory) { 'error' } else { 'ok' }

$reasons = @()
if ($members.Count -gt $maxCount) {
    $byRole = @($members | Group-Object Role | Sort-Object Count -Descending | Select-Object -First 2 | ForEach-Object { "$($_.Count) × $($_.Name)" })
    $reasons += ("$($members.Count) processus, seuil $maxCount : " + ($byRole -join ', '))
}
if ($orphans.Count) { $reasons += ('résident hors de l''app serveur : ' + ((@($orphans | ForEach-Object { "$($_.Label) (PID $($_.ProcessId))" })) -join ', ')) }
if ($totalMb -gt $maxMemory) {
    $heaviest = @($members | Sort-Object Bytes -Descending | Select-Object -First 2 | ForEach-Object { "$($_.Role) " + (($_.Bytes / 1MB).ToString('N0', $fr)) + ' Mo' })
    $reasons += ("$totalMb Mo, seuil $maxMemory : " + ($heaviest -join ', '))
}
$reason = if ($reasons.Count) { ($reasons -join ' ; ') } else { $null }
$guide = $null
if ($reasons.Count) {
    $guide = "Vigie occupe plus que prévu : " + $reason + '.' + [Environment]::NewLine + [Environment]::NewLine +
             "Le tableau nomme chaque processus avec son rôle. « Redémarrer le serveur » les remplace tous proprement ; Vigie n'arrête aucun processus d'elle-même."
}
$table = if ($rows.Count) { @{ columns = @('Rôle', 'Processus', 'PID', 'En mémoire vive', 'Engagée', 'Démarré'); rows = $rows } } else { $null }
$fix = if ($reasons.Count) { 'server-restart' } else { $null }

$fields = @(
    New-Field -Key 'count' -Label 'Processus de Vigie' -Value $(if ($serverId) { $members.Count } else { 'App serveur introuvable' }) `
        -Kind $(if ($serverId) { 'number' } else { 'text' }) -Status $countStatus -Table $table -Guide $guide -Reason $reason -FixAction $fix `
        -Help "L'app serveur et tout ce qu'elle a lancé : résidents, tâches de fond, consoles. Au-delà du seuil réglé dans les paramètres du module, la carte alerte."
    New-Field -Key 'memory' -Label 'Mémoire de Vigie' -Value $totalMb -Kind 'number' -Unit 'Mo' -Status $memoryStatus -Reason $(if ($memoryStatus -ne 'ok') { $reason } else { $null }) `
        -FixAction $(if ($memoryStatus -ne 'ok') { 'server-restart' } else { $null }) -Guide $(if ($memoryStatus -ne 'ok') { $guide } else { $null }) `
        -Help "Mémoire vive réellement occupée par tous les processus de Vigie réunis."
)
$worst = if ($countStatus -eq 'error' -or $memoryStatus -eq 'error') { 'error' } elseif ($countStatus -eq 'warn') { 'warn' } else { 'ok' }
New-ModuleObject -Id 'vigie-self' -Theme 'debug' -Label 'Processus de Vigie' -Status $worst -Fields $fields
