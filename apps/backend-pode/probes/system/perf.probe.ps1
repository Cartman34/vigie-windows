# @author Florent HAZARD <f.hazard@sowapps.com>
<# Sonde : ressources (RAM / CPU / uptime). LECTURE SEULE, rapide.

   EVERY ALERT GIVES ITS REASONS (doc/en/developing/modules.md, section "What a card must say"). On 18/09 the card said
   "RAM 93 %" and nothing else, while the virtual machine of WSL held 14 GB and Windows warned of saturation: the
   committed memory, the figure those warnings follow, was not even shown. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
# ASKED OF WINDOWS DIRECTLY (scripts/lib/system-metrics.ps1): through WMI these readings took 1.7 s on 18/09.
$memory = Get-MemoryStatus
$freeGB = if ($memory) { [math]::Round($memory.AvailPhys/1GB,1) } else { 0 }
$totGB  = if ($memory) { [math]::Round($memory.TotalPhys/1GB,1) } else { 0 }
$ramPct = if ($totGB) { [math]::Round(($totGB-$freeGB)/$totGB*100) } else { 0 }
# THE COMMITTED MEMORY AGAINST ITS LIMIT (physical memory plus page file): when it reaches the limit, Windows refuses
# allocations and warns of saturation, whatever the free RAM says.
$commitGB = if ($memory) { $memory.CommitUsed/1GB } else { 0 }
$limitGB  = if ($memory) { $memory.CommitLimit/1GB } else { 0 }
$commitPct = if ($limitGB) { [math]::Round($commitGB/$limitGB*100) } else { 0 }
$cpuLoad = Get-ProcessorLoad
$cpu = if ($null -ne $cpuLoad) { $cpuLoad } else { 0 }
$up = [TimeSpan]::FromMilliseconds([Environment]::TickCount64)
$upTxt = "{0}j {1}h {2}m" -f $up.Days, $up.Hours, $up.Minutes

$ramStatus    = if ($ramPct -ge 90) { 'warn' } else { 'ok' }
$commitStatus = if ($commitPct -ge 97) { 'error' } elseif ($commitPct -ge 90) { 'warn' } else { 'ok' }
$cpuStatus    = if ($cpu -ge 90) { 'warn' } else { 'neutral' }

# WHO CONSUMES, grouped by application: one line per process name, summed. Measured only when something alerts, so
# that a quiet card costs nothing more. A technical name is shown with its Windows description (D64).
# Processes Windows gives no description for, named by what they are.
$script:KnownProcessNames = @{ 'vmmemWSL' = 'Sous-système Linux WSL'; 'vmmem' = 'Mémoire des invités Hyper-V' }
function Get-TopMemoryApplications {
    param([int]$Count = 10)
    $groups = @(Get-Process -ErrorAction SilentlyContinue | Group-Object ProcessName | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Description = ''; Count = $_.Count; Bytes = [double](($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum); Group = $_.Group }
    } | Sort-Object Bytes -Descending | Select-Object -First $Count)
    # THE DESCRIPTION IS READ FOR THE LINES SHOWN ONLY: reading it for three hundred processes took seconds (18/09).
    foreach ($g in $groups) {
        if ($script:KnownProcessNames.ContainsKey($g.Name)) { $g.Description = $script:KnownProcessNames[$g.Name]; continue }
        foreach ($p in $g.Group) { try { if ($p.Description) { $g.Description = "$($p.Description)"; break } } catch { } }
    }
    return $groups
}
function Format-ApplicationName {
    param($Application)
    if ($Application.Description -and $Application.Description -ne $Application.Name) { return ($Application.Description + ' (' + $Application.Name + ')') }
    return $Application.Name
}

$memoryGuide = $null
$memoryTable = $null
if ($ramStatus -ne 'ok' -or $commitStatus -ne 'ok') {
    $top = @(Get-TopMemoryApplications)
    if ($top.Count) {
        $rows = @(foreach ($a in $top) {
            ,@((Format-ApplicationName $a), "$($a.Count)", (($a.Bytes/1GB).ToString('N1', $fr) + ' Go'))
        })
        $memoryTable = @{ columns = @('Application', 'Processus', 'Mémoire privée'); rows = $rows }
        $firsts = @($top | Select-Object -First 3 | ForEach-Object { (Format-ApplicationName $_) + ' : ' + (($_.Bytes/1GB).ToString('N1', $fr)) + ' Go' })
        $memoryGuide = "Ce qui occupe le plus la mémoire : " + ($firsts -join ' ; ') + '.' + [Environment]::NewLine + [Environment]::NewLine +
                       "Le détail par application est dans le tableau. Fermer ou redémarrer l'application la plus lourde libère sa part ; le Gestionnaire des tâches permet de le faire."
    }
}

$cpuGuide = $null
$cpuTable = $null
if ($cpuStatus -ne 'neutral') {
    # The processor share needs two readings: the processor time used between them, per application.
    $first = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) { try { $first[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { } }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 500
    $elapsed = $watch.Elapsed.TotalMilliseconds * [Environment]::ProcessorCount
    $cpuTop = @(Get-Process -ErrorAction SilentlyContinue | Group-Object ProcessName | ForEach-Object {
        $used = 0.0
        foreach ($p in $_.Group) { try { if ($first.ContainsKey($p.Id)) { $used += $p.TotalProcessorTime.TotalMilliseconds - $first[$p.Id] } } catch { } }
        [pscustomobject]@{ Name = $_.Name; Count = $_.Count; Pct = $(if ($elapsed) { 100 * $used / $elapsed } else { 0 }) }
    } | Where-Object Pct -gt 0.5 | Sort-Object Pct -Descending | Select-Object -First 8)
    if ($cpuTop.Count) {
        $cpuTable = @{ columns = @('Application', 'Processus', 'Processeur'); rows = @(foreach ($a in $cpuTop) { ,@($a.Name, "$($a.Count)", ([math]::Round($a.Pct).ToString() + ' %')) }) }
        $cpuGuide = "Ce qui occupe le plus le processeur : " + ((@($cpuTop | Select-Object -First 3 | ForEach-Object { $_.Name + ' : ' + [math]::Round($_.Pct) + ' %' })) -join ' ; ') + '.'
    }
}

$commitValue = $commitGB.ToString('N1', $fr) + ' Go sur ' + $limitGB.ToString('N1', $fr)
$worst = if ($commitStatus -eq 'error') { 'error' } elseif ($ramStatus -eq 'warn' -or $commitStatus -eq 'warn' -or $cpuStatus -eq 'warn') { 'warn' } else { 'ok' }
# Bouton PERMANENT (D114) : voir QUI consomme est la suite naturelle de « combien est
# consomme », que la machine aille bien ou non.
New-ModuleObject -Id 'perf' -Theme 'system' -Label 'Ressources' -Status $worst -Fields @(
    New-Field -Key 'ramUsed' -Label 'RAM utilisée' -Value $ramPct  -Kind 'number' -Unit '%'  -Status $ramStatus `
        -FixAction $(if ($ramStatus -ne 'ok') { 'open-task-manager' } else { $null }) -Guide $memoryGuide -Table $memoryTable `
        -Help 'Pourcentage de mémoire vive utilisée.'
    New-Field -Key 'commit' -Label 'Mémoire engagée' -Value $commitValue -Kind 'text' -Status $commitStatus `
        -FixAction $(if ($commitStatus -ne 'ok') { 'open-task-manager' } else { $null }) -Guide $memoryGuide -Table $memoryTable `
        -Help "Mémoire promise aux applications, face à sa limite (mémoire vive plus fichier d'échange). Quand elle atteint la limite, Windows refuse de nouvelles allocations et alerte de saturation, même s'il reste de la mémoire vive libre."
    New-Field -Key 'ramFree' -Label 'RAM libre'    -Value $freeGB  -Kind 'number' -Unit 'Go' -Status 'neutral'                                        -Help 'Mémoire vive disponible.'
    New-Field -Key 'cpu'     -Label 'CPU'          -Value $cpu     -Kind 'number' -Unit '%'  -Status $cpuStatus `
        -FixAction $(if ($cpuStatus -ne 'neutral') { 'open-task-manager' } else { $null }) -Guide $cpuGuide -Table $cpuTable `
        -Help 'Charge processeur instantanée.'
    New-Field -Key 'uptime'  -Label 'Uptime'       -Value $upTxt   -Kind 'text'               -Status 'neutral'                                        -Help 'Durée depuis le dernier démarrage de Windows.'
) `
    -Actions @(New-Action -Id 'open-task-manager' -Label 'Gestionnaire des tâches' -Kind 'manual' -Severity 'info' `
                          -Help 'Ouvre le Gestionnaire des tâches : qui consomme la mémoire et le processeur, en détail.')
