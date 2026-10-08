# @author Florent HAZARD <f.hazard@sowapps.com>
<# A probe: the gaming session and how the resources are shared out. READ ONLY.

   Intent: be a DIAGNOSTIC TOOL. When the game stutters, the card must let one see who takes what -- processor,
   GPU, VRAM, memory, input/output -- and spot the application draining the machine during the game.
   Usage: it is run by the scheduler like any probe. To test it WITHOUT a game (doc/en/developing/modules.md),
   VIGIE_FAKE_GAME=<name> forces that process to be treated as the game; the values stay real. For a real GPU
   load: scripts/dev/gpu-load.html (the recipe is in modules.md).

   The measurements (no localised counter -- the system is in French):
     - CPU   : the delta of TotalProcessorTime between two snapshots (~0.9 s), normalised by the number of cores;
     - GPU   : the '/GPU Engine(*)' counters summed per PID, capped at 100;
     - VRAM  : '/GPU Process Memory(*)/Local Usage' per PID -- Dedicated Usage adds up views that overlap
               (6.94 GB announced for 1.70 real); the card's real total comes from the driver's registry key
               (HardwareInformation.qwMemorySize -- Win32_VideoController.AdapterRAM LIES beyond 4 GB, observed);
     - I/O   : the delta of Read+WriteTransferCount from Win32_Process over the same window (disc AND network
               together -- Windows does not break it down per process without ETW; the label says so honestly);
     - RAM   : private working set (Get-ProcessMemoryUse), what the process alone holds in RAM. WorkingSet64
               counted the shared pages once per process: 7.9 GB for Chrome's 48 processes, which held 2.2 GB
               (19/09).
#>


#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$gameGpuMin   = [int](Get-ModuleSetting -Unit 'gaming' -Key 'GameGpuMinPct');   if (-not $gameGpuMin)   { $gameGpuMin = 15 }
$otherCpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherCpuWarnPct'); if (-not $otherCpuWarn) { $otherCpuWarn = 1 }
$otherGpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherGpuWarnPct'); if (-not $otherGpuWarn) { $otherGpuWarn = 15 }
$vramWarn     = [int](Get-ModuleSetting -Unit 'gaming' -Key 'VramWarnPct');     if (-not $vramWarn)     { $vramWarn = 90 }
$tempWarn     = [int](Get-ModuleSetting -Unit 'gaming' -Key 'GpuTempWarnC');   if (-not $tempWarn)     { $tempWarn = 87 }

# The foreground process: the best clue to the game while a session is active.
# FULL SCREEN is measured here too: it is a game's behaviour, not a name.
# NB: the type carries a NEW name (Win) because a type already loaded in the server cannot be completed --
# Add-Type would be ignored and the new methods absent.
$fgPid = 0
$fgPleinEcran = $false
try {
    if (-not ('VigieProbe.Win' -as [type])) {
        Add-Type -Namespace VigieProbe -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int GetWindowThreadProcessId(System.IntPtr hWnd, out int pid);
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT r);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int GetSystemMetrics(int i);
'@
    }
    $h = [VigieProbe.Win]::GetForegroundWindow()
    if ($h -ne [IntPtr]::Zero) {
        [void][VigieProbe.Win]::GetWindowThreadProcessId($h, [ref]$fgPid)
        $r = New-Object VigieProbe.Win+RECT
        if ([VigieProbe.Win]::GetWindowRect($h, [ref]$r)) {
            # The MAIN screen: a window on a second screen is not seen as full screen. That is an accepted limit,
            # not an oversight.
            $width = [VigieProbe.Win]::GetSystemMetrics(0)
            $height = [VigieProbe.Win]::GetSystemMetrics(1)
            if ($width -gt 0 -and $height -gt 0) {
                $fgPleinEcran = (($r.Right - $r.Left) -ge ($width * 0.98) -and ($r.Bottom - $r.Top) -ge ($height * 0.98))
            }
        }
    }
} catch { }

# --- Instantane 1 : CPU + E/S cumulees ---------------------------------------
<#
    THE MEASURING WINDOW STARTS HERE, before the first snapshot, and not after it.

    It used to start after: a process's processor time was therefore counted over (end of the first snapshot + the
    wait + start of the second), but divided by the wait alone. Everything was inflated by the time it takes to walk
    six hundred processes -- on 29/09 the card reported a peak of 121,7 % for a game, which no process can reach:
    100 % means every core.
#>
$t0 = Get-Date
$coeurs = [Math]::Max(1, [int]$env:NUMBER_OF_PROCESSORS)
$beforeCpu = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try { $beforeCpu[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { }
}
# READ FROM THE KERNEL IN ONE CALL (Get-ProcessTransferBytes, 14 ms): through Win32_Process each reading took 0.55 s.
$beforeIo = Get-ProcessTransferBytes
# THE GPU COUNTERS, read from PDH directly (VigiePdh, scripts/lib/system-metrics.ps1): the first reading goes with
# snapshot 1, the second with snapshot 2, so the engine utilisation -- a rate -- is measured over the same 900 ms as
# the processor and the disk. Get-Counter took 6.3 s for the engines alone and 1 s for each memory counter (18/09).
#
# VRAM PER PROCESS: "Local Usage", not "Dedicated Usage". Measured on 26/08 on this computer: the sum of Dedicated Usage
# gave 6.94 GB while the adapter held only 1.70 GB -- dwm alone weighed more than the VRAM in use (reported by the user:
# "the figures do not look consistent"). Dedicated Usage adds up overlapping views (the compositor references the
# surfaces of the other applications). Local Usage totalled 1.69 GB, exactly what the card held: it tells the truth,
# application by application. Dedicated Usage stays as a fallback when Local Usage is missing: an imperfect value is
# better than none.
$pdh = $null
$engineCounter = -1; $vramCounter = -1; $adapterCounter = -1
try {
    $pdh = [VigiePdh]::new()
    $engineCounter  = $pdh.Add('\GPU Engine(*)\Utilization Percentage')
    $vramCounter    = $pdh.Add('\GPU Process Memory(*)\Local Usage')
    if ($vramCounter -lt 0) { $vramCounter = $pdh.Add('\GPU Process Memory(*)\Dedicated Usage') }
    $adapterCounter = $pdh.Add('\GPU Adapter Memory(*)\Dedicated Usage')
    [void]$pdh.Collect()
} catch { $pdh = $null }

Start-Sleep -Milliseconds 900

# --- GPU and VRAM per process ---------------------------------------------------
$gpuParPid = @{}; $vramParPid = @{}; $luidParPid = @{}; $gpuDispo = $false
$vramUtilisee = 0.0
if ($pdh -and $pdh.Collect()) {
    if ($engineCounter -ge 0) {
        $gpuDispo = $true
        foreach ($s in $pdh.Read($engineCounter)) {
            if ($s.Key -match '^pid_(\d+)_luid_0x[0-9A-Fa-f]+_0x([0-9A-Fa-f]+)_') {
                $gp = [int]$Matches[1]
                $lu = [Convert]::ToInt64($Matches[2], 16)
                $gpuParPid[$gp] = [double]($gpuParPid[$gp]) + $s.Value
                # WHICH ADAPTER works for this process: needed to spot a game rendered by the integrated card (Optimus)
                # instead of the dedicated one.
                if (-not $luidParPid.ContainsKey($gp)) { $luidParPid[$gp] = @{} }
                $luidParPid[$gp][$lu] = [double]($luidParPid[$gp][$lu]) + $s.Value
            }
        }
    }
    foreach ($s in $pdh.Read($vramCounter)) {
        if ($s.Key -match '^pid_(\d+)_') {
            $gp = [int]$Matches[1]
            $vramParPid[$gp] = [double]($vramParPid[$gp]) + $s.Value
        }
    }
    foreach ($s in $pdh.Read($adapterCounter)) { $vramUtilisee += $s.Value }
}
if ($pdh) { $pdh.Dispose() }

# --- Instantane 2 + assemblage ------------------------------------------------
$elapsed = ((Get-Date) - $t0).TotalMilliseconds
$afterIo = Get-ProcessTransferBytes
$memoryUse = Get-ProcessMemoryUse

$procs = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try {
        $cpu = 0.0
        if ($beforeCpu.ContainsKey($p.Id)) {
            $cpu = ($p.TotalProcessorTime.TotalMilliseconds - $beforeCpu[$p.Id]) / $elapsed * 100.0 / $coeurs
        }
        $ioMo = 0.0
        if ($beforeIo.ContainsKey($p.Id) -and $afterIo.ContainsKey($p.Id)) {
            $ioMo = [Math]::Max(0.0, ($afterIo[$p.Id] - $beforeIo[$p.Id]) / $elapsed * 1000.0 / 1MB)
        }
        # The executable's path: it is what lets us say whether this is a GAME (see further down). Out of reach for
        # protected processes -- we accept that, we do not guess.
        $path = $null
        try { $path = $p.Path } catch { }
        $procs[$p.Id] = [pscustomobject]@{
            Id = $p.Id; Name = $p.ProcessName; Path = $path
            Cpu    = [Math]::Round([Math]::Min(100.0, [Math]::Max(0.0, $cpu)), 1)
            Gpu    = [Math]::Round([Math]::Min(100.0, [double]($gpuParPid[$p.Id])), 1)
            VramGb = [Math]::Round([double]($vramParPid[$p.Id]) / 1GB, 2)
            RamGb  = [Math]::Round($(if ($memoryUse.ContainsKey($p.Id)) { $memoryUse[$p.Id].Ram } else { 0.0 }) / 1GB, 2)
            IoMbs  = [Math]::Round($ioMo, 1)
        }
    } catch { }
}

# --- The graphics card, or cards ----------------------------------------------
$gpus = @(); $vramTotale = 0.0
try {
    $gpus = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion)
    # The REAL VRAM total: the driver's registry key (AdapterRAM caps at 4 GB).
    $cles = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' `
            -Name 'HardwareInformation.qwMemorySize' -ErrorAction SilentlyContinue
    $vramTotale = ($cles | ForEach-Object { [double]$_.'HardwareInformation.qwMemorySize' } |
                   Measure-Object -Maximum).Maximum
} catch { }

# A luid -> adapter name table (the DirectX registry base): it is what lets us say whether a process is rendered
# by the dedicated card or by the integrated one.
$nameByLuid = @{}
try {
    foreach ($k in (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\DirectX' -ErrorAction Stop)) {
        $pr = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($pr -and $null -ne $pr.AdapterLuid -and $pr.Description) {
            $nameByLuid[[int64]$pr.AdapterLuid] = "$($pr.Description)"
        }
    }
} catch { }
$hasDedicatedCard = [bool]($nameByLuid.Values | Where-Object { $_ -notmatch 'Intel|UHD|Iris|Basic Render' })

# The Dedicated Usage counter sometimes LIES (dwm seen at 32 GB on an 8 GB card): a per-process value higher than
# the physical VRAM is absurd, so we set it aside.
if ($vramTotale -gt 0) {
    foreach ($pid2 in @($procs.Keys)) {
        if ($procs[$pid2].VramGb -gt ($vramTotale / 1GB)) { $procs[$pid2].VramGb = 0 }
    }
}

# Two distinct natures (the owner's choice):
# - MEASUREMENT noise, never shown: the fake Idle process and Vigie itself;
# - legitimate WINDOWS services: shown if they consume, but ANNOTATED as such -- hiding them would hide
#   information, advising one to close them would be wrong.
$noise = @('Idle','System','Memory Compression','Registry','conhost','pwsh','powershell')
$servicesWindows = @('lsass','services','wininit','winlogon','smss','csrss','dwm','svchost',
                     'MsMpEng','SearchIndexer','fontdrvhost','WmiPrvSE','RuntimeBroker',
                     'SearchHost','taskhostw')

# An APPLICATION = all its processes of the same name, summed. Three separate browser lines say nothing; one
# single aggregated line says who takes what.
function Group-ByApp {
    param($Liste)
    @($Liste | Group-Object Name | ForEach-Object {
        # A READABLE name: a service's internal name speaks to nobody. The path comes from the first process of the
        # group that agrees to give it.
        $paths = @($_.Group | ForEach-Object { $_.Path } | Where-Object { $_ } | Sort-Object -Unique)
        $path = @($paths | Select-Object -First 1)[0]
        [pscustomobject]@{
            Name   = $_.Name
            Label  = (Get-AppDisplayName -ProcessName $_.Name -Path $path -Complet)
            Court  = (Get-AppDisplayName -ProcessName $_.Name -Path $path)
            Tip    = (Get-AppInfoTip -ProcessName $_.Name -Paths $paths -Ids @($_.Group | ForEach-Object { [int]$_.Id }))
            Cpu    = [Math]::Round((($_.Group | Measure-Object Cpu -Sum).Sum), 1)
            Gpu    = [Math]::Round([Math]::Min(100.0, ($_.Group | Measure-Object Gpu -Sum).Sum), 1)
            VramGb = [Math]::Round((($_.Group | Measure-Object VramGb -Sum).Sum), 2)
            RamGb  = [Math]::Round((($_.Group | Measure-Object RamGb -Sum).Sum), 2)
            IoMbs  = [Math]::Round((($_.Group | Measure-Object IoMbs -Sum).Sum), 1)
        }
    })
}

# --- THE GAME: WHAT THE RESIDENT FOUND, NOT A MEASUREMENT ---------------------
#
# DETECTION NO LONGER HAPPENS HERE. A resident (game.resident.ps1) is told by Windows when a
# process starts, and hands it to the identification methods kept in identify/. It keeps the
# current session up to date; this probe READS its result.
#
# WHY THE REVERSAL. Detection relied on instantaneous GPU usage, which served both as the
# entry filter and as proof of activity: reading the counters costs two and a half seconds,
# sometimes comes back empty, and the card then announced "no game". Odyssey was recognised
# at one reading and ignored at the next (02/09). The GPU is still displayed -- it says
# whether the game RENDERS or is paused -- but decides nothing any more.
#
# THREE STATES, not two: a game runs, none runs, or the watch is down. The third was
# announced as the second, and that is what misled.
$game = $null
$gameReasons = $null
# ALIVE IS NOT ENOUGH: a resident that breathes but whose subscription was denied measures
# nothing. Without this distinction the card would say "no game" while it does not know --
# the very mistake this field exists to prevent.
$watchDown = -not (Test-ResidentOperational -Backend $backend -Key 'game')
$watchState = Get-ResidentState -Backend $backend -Key 'game'
$session = Get-GameSession -Backend $backend
if ($env:VIGIE_FAKE_GAME) {
    # Simulation (doc/en/developing/modules.md): the measurements stay real.
    $game = $procs.Values | Where-Object { $_.Name -like $env:VIGIE_FAKE_GAME } |
           Sort-Object Gpu -Descending | Select-Object -First 1
    if ($game) { $gameReasons = @("Simulation (VIGIE_FAKE_GAME=$($env:VIGIE_FAKE_GAME)) : les mesures restent reelles.") }
}
if (-not $game -and $session) {
    $game = $procs[[int]$session.processId]
    if (-not $game) {
        # The process is alive -- Get-GameSession checked -- but is not in our snapshot:
        # we still return what the session knows about it.
        $game = [pscustomobject]@{ Id = [int]$session.processId; Name = "$($session.name)"; Path = "$($session.path)"
                                  Cpu = 0; Gpu = 0; VramGb = 0; RamGb = 0; IoMbs = 0 }
    }
    $gameReasons = @("$($session.reason)")
}

$fields = @()

# --- The graphics card and the VRAM -------------------------------------------
if ($gpus.Count -gt 0) {
    $principal = ($gpus | Sort-Object { $_.Name -match 'Intel|UHD|Iris' } | Select-Object -First 1)
    $gpuLines = @($gpus | ForEach-Object { "- {0} (pilote {1})" -f $_.Name, $_.DriverVersion })
    $fields += New-Field -Key 'gpu-card' -Label 'Carte graphique' -Value $principal.Name -Kind 'text' -Status 'neutral' `
        -Help "La carte qui rend le jeu ; le détail liste tous les adaptateurs et leurs pilotes." `
        -Guide ($gpuLines -join "`n")
} else {
    $fields += New-Field -Key 'gpu-card' -Label 'Carte graphique' -Value 'non détectée' -Kind 'text' -Status 'warn' `
        -Help "Aucun adaptateur graphique remonté par Windows." `
        -FixAction 'open-device-manager' `
        -Guide "Sans adaptateur, le suivi GPU est impossible. Le bouton ouvre le Gestionnaire de périphériques, section Cartes graphiques : c'est là que Windows montre l'état du matériel et propose la mise à jour du pilote."
}
if ($vramTotale -gt 0) {
    $pctVram = [Math]::Round($vramUtilisee / $vramTotale * 100)
    $stVram = if ($pctVram -ge $vramWarn) { 'warn' } else { 'ok' }
    $fields += New-Field -Key 'vram' -Label 'VRAM utilisée' `
        -Value ("{0:N1} / {1:N0} Go ({2} %)" -f ($vramUtilisee/1GB), ($vramTotale/1GB), $pctVram) -Kind 'text' -Status $stVram `
        -Help "Mémoire dédiée de la carte graphique. Pleine, le jeu compense par la RAM : saccades." `
        -Guide "Au-delà de $vramWarn % (réglable), baissez la qualité des textures ou fermez les applis 3D en fond." `
        -Table $(
            $vramAll = @(Group-ByApp ($procs.Values | Where-Object { $_.VramGb -gt 0 }) |
                            Sort-Object VramGb -Descending)
            $vramApps = @($vramAll | Select-Object -First 6)
            # WHAT IS NOT LISTED IS AGGREGATED (asked for by the owner): without this line, the user adds the
            # table up, does not find the total again, and is right to find that inconsistent.
            $vramReste  = @($vramAll | Select-Object -Skip 6)
            $vramLines = @($vramApps | ForEach-Object { ,@($_.Label, $_.VramGb) })
            $tipsVram   = @($vramApps | ForEach-Object { $_.Tip })
            if ($vramReste.Count) {
                $sommeReste = [math]::Round((($vramReste | Measure-Object VramGb -Sum).Sum), 2)
                $vramLines += ,@(("Autres (" + $vramReste.Count + " applications)"), $sommeReste)
                $tipsVram   += (($vramReste | ForEach-Object { $_.Label + " : " + $_.VramGb + " Go" }) -join [Environment]::NewLine)
            }
            @{ columns = @('Application', 'VRAM (Go)')
               rows = $vramLines
               # One tooltip per line: the absolute path, the publisher, the PID (asked for by the owner).
               tips = $tipsVram })
}
if (-not $gpuDispo) {
    $fields += New-Field -Key 'gpu' -Label 'Compteurs GPU' -Value 'indisponibles' -Kind 'text' -Status 'warn' `
        -Help "Les compteurs de performance GPU de Windows ne répondent pas." `
        -FixAction 'perf-counters-rebuild' `
        -Guide "Sans eux, impossible d'attribuer le GPU aux processus.`nLe bouton reconstruit la base des compteurs de Windows (lodctr /R) puis resynchronise WMI, et vérifie ensuite qu'ils répondent. Si ce n'est pas le cas, un redémarrage de Windows les rétablit."
}

# --- The health of the dedicated GPU (nvidia-smi, delivered with the driver) ---
$aNvidia = [bool]($gpus | Where-Object { $_.Name -match 'NVIDIA' })
if ($aNvidia) {
    $smi = 'C:\Windows\System32\nvidia-smi.exe'
    if (Test-Path $smi) {
        try {
            $ln = (& $smi '--query-gpu=temperature.gpu,power.draw,clocks.sm,utilization.gpu,clocks_event_reasons.active' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1)
            if (-not $ln) {
                # Older drivers: the old name of the throttling field.
                $ln = (& $smi '--query-gpu=temperature.gpu,power.draw,clocks.sm,utilization.gpu,clocks_throttle_reasons.active' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1)
            }
            if ($ln) {
                $c = @(($ln -split ',') | ForEach-Object { "$_".Trim() })
                $temp = [int]$c[0]
                # The reasons mask mixes NORMAL power management (idle 0x1, a software power limit 0x4, an
                # application cap 0x2, sync 0x10) with REAL throttling: a hardware slowdown 0x8, a software
                # thermal limit 0x20, a hardware thermal limit 0x40, a hardware power brake 0x80. Mixing them all
                # displayed "throttled" at rest at 48 degrees (observed): a false positive.
                $masque = 0L
                if ($c.Count -ge 5 -and $c[4] -match '^0x[0-9A-Fa-f]+$') {
                    try { $masque = [Convert]::ToInt64($c[4].Substring(2), 16) } catch { }
                }
                $raisons = @()
                if ($masque -band 0x8)  { $raisons += 'ralenti matériel (chaleur ou alimentation)' }
                if ($masque -band 0x40) { $raisons += 'bridage thermique matériel' }
                if ($masque -band 0x80) { $raisons += 'frein de puissance matériel' }
                if (($masque -band 0x20) -and $temp -ge $tempWarn) { $raisons += 'bridage thermique logiciel' }
                $bridage = ($raisons.Count -gt 0)
                $stT = if ($temp -ge $tempWarn -or $bridage) { 'warn' } else { 'ok' }
                $vT = "$temp" + [char]0x00B0 + "C"
                if ($bridage) { $vT += ' (bridée)' }
                $gT = @("Consommation : $($c[1]) W " + [char]0x00B7 + " horloge $($c[2]) MHz " + [char]0x00B7 + " utilisation $($c[3]) %")
                if ($bridage) { $gT += ("La carte BRIDE ses fréquences : " + ($raisons -join ' ; ') + ". À vérifier : la ventilation et les entrées d'air.") }
                elseif ($temp -ge $tempWarn) { $gT += "Au-delà de $tempWarn degrés (réglable), la carte va se brider : chutes de FPS. À vérifier : la ventilation." }
                $fields += New-Field -Key 'gpu-temp' -Label 'Température GPU' -Value $vT -Kind 'text' -Status $stT `
                    -Help "Température de la carte dédiée, et son éventuel bridage (la cause première des chutes de FPS sur portable)." `
                    -Guide ($gT -join "`n")
            }
        } catch { }
    } else {
        $fields += New-Field -Key 'gpu-temp' -Label 'Température GPU' -Value 'indisponible' -Kind 'text' -Status 'warn' `
            -Help "nvidia-smi est absent alors qu'une carte NVIDIA est détectée." `
            -FixAction 'open-device-manager' `
            -Guide "L'outil est livré avec le pilote NVIDIA : son absence signale un pilote incomplet. Le bouton ouvre le Gestionnaire de périphériques pour mettre à jour ou réinstaller le pilote."
    }
}

# --- Power: playing on battery throttles everything ---------------------------
# The same reading as the discharge sentinel, in the same place: the two cannot contradict each other, and
# VIGIE_FAKE_BATTERY simulates both.
$alim = Get-BatteryState
$surSecteur  = -not $alim.OnBattery
$pctBatterie = $alim.Pct
# THE POWER MODE IS NOT STATED HERE. powercfg returns the one of the account that runs -- the service -- and not
# the player's: a value that is right by accident. The machine and its power supply are the subject of the Power
# card; this card only states the effect on the game.

# THE SESSION IS RECORDED HERE, once we know there is one: its sentinel needs the battery charge AT THE START to
# say that it is draining while you play, and it cannot find that out after the fact.
if ($game) { Set-GameSession -Backend $backend -Name (Get-AppDisplayName -ProcessName $game.Name -Path $game.Path -Complet) -ProcessId ([int]$game.Id) -BatteryPct $(if ($null -ne $pctBatterie) { [int]$pctBatterie } else { -1 }) }
else { Clear-GameSession -Backend $backend }
$session = Get-GameSession -Backend $backend
$baisse = 0
if ($session -and -not $surSecteur -and [int]$session.startPct -ge 0 -and $null -ne $pctBatterie) {
    $baisse = [int]$session.startPct - [int]$pctBatterie
}
$dropThreshold = [int](Get-ModuleSetting -Unit 'gaming' -Key 'BatteryDropWarnPct'); if (-not $dropThreshold) { $dropThreshold = 10 }

# --- The game and the resource hogs -------------------------------------------
if ($game) {
    # SAY WHY: naming a detected game without a justification has already pointed at the wrong program.
    $pourquoi = if ($env:VIGIE_FAKE_GAME) { @("Simulation (VIGIE_FAKE_GAME=$($env:VIGIE_FAKE_GAME)) : les mesures restent réelles.") }
                elseif ($gameReasons) { @('Reconnu comme jeu parce que :') + @($gameReasons | ForEach-Object { "- $_" }) }
                else { @() }
    if ($game.Path) { $pourquoi += "Exécutable : $($game.Path)" }
    # The game stays THE game even when it is not rendering: we say so instead of making it disappear (a menu, a
    # pause, a loading screen).
    $auRepos = ($game.Gpu -lt $gameGpuMin)
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' `
        -Value ((Get-AppDisplayName -ProcessName $game.Name -Path $game.Path -Complet) + $(if ($auRepos) { ' (menu ou pause)' } else { '' })) -Kind 'text' -Status 'ok' `
        -Help "Application qui consomme le GPU ET qui présente des signes de jeu (bibliothèque de jeux, moteur, plein écran)." `
        -Guide $(if ($pourquoi.Count) { $pourquoi -join "`n" } else { $null })
    $fields += New-Field -Key 'game-res' -Label 'Ressources du jeu' `
        -Value ("CPU {0} % · GPU {1} % · VRAM {2} Go" -f $game.Cpu, $game.Gpu, $game.VramGb) -Kind 'text' -Status 'neutral' `
        -Help "Part de la machine consommée par le jeu à l'instant de la mesure." `
        -Guide ("RAM : {0} Go`nE/S (disque+réseau) : {1} Mo/s" -f $game.RamGb, $game.IoMbs)

    # On which adapter is the game being rendered? The Optimus trap: the integrated card renders the game while
    # the dedicated one sleeps -- performance halved with no message.
    if ($luidParPid.ContainsKey($game.Id) -and $nameByLuid.Count -gt 0) {
        $luDominant = ($luidParPid[$game.Id].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        $adapterName = $nameByLuid[[int64]$luDominant]
        if ($adapterName) {
            $surIntegree = ($adapterName -match 'Intel|UHD|Iris|Basic Render')
            $stAd = if ($surIntegree -and $hasDedicatedCard) { 'warn' } else { 'ok' }
            $argsAd = @{
                Key = 'game-adapter'; Label = 'Rendu par'; Value = $adapterName; Kind = 'text'; Status = $stAd
                Help = "L'adaptateur graphique qui rend le jeu. Sur ce portable, la carte dédiée doit s'en charger."
            }
            if ($stAd -eq 'warn') {
                $argsAd.Guide = "Le jeu tourne sur la carte INTÉGRÉE alors qu'une carte dédiée existe : performances bridées.`nParamètres Windows > Système > Affichage > Cartes graphiques : ajoutez l'exécutable du jeu et choisissez « Hautes performances »."
            }
            $fields += New-Field @argsAd
        }
    }

    <# WHAT BELONGS TO THE GAME IS NOT A STRANGER.

       Comparing NAMES was not enough. On 07/09, Odyssey was playing and the card reported a
       greedy application: it was Uplay Web Core, a component of the very launcher that had
       started the game. Telling somebody to close a piece of their own game is worse than
       saying nothing.

       So we compare PATHS, as identification does: a process living under the game's folder
       (renderer, anti-cheat, crash handler) or under the launcher's folder (the platform's
       own components) is PART of the session. The launcher is the parent the resident noted
       when it recognised the game -- a fact, not a name to guess.

       A folder too wide would hide everything, so a root that holds more than the game is
       refused: no C:\, no Program Files, nothing shallower than two levels. #>
    $family = @()
    foreach ($path in @("$($game.Path)", "$($session.launcher)")) {
        if (-not $path) { continue }
        $folder = $null
        try { $folder = Split-Path -Parent $path } catch { }
        if (-not $folder) { continue }
        if (($folder.Split([char]92) | Where-Object { $_ }).Count -lt 3) { continue }
        $family += $folder.ToLower().TrimEnd('\') + '\'
    }
    $family = @($family | Sort-Object -Unique)
    function Test-BelongsToGame {
        param($Proc)
        if ($Proc.Name -eq $game.Name) { return $true }
        if (-not $Proc.Path) { return $false }
        $target = "$($Proc.Path)".ToLower()
        foreach ($root in $family) { if ($target.StartsWith($root)) { return $true } }
        return $false
    }
    <#
        WHAT THE SESSION TOOK, PASS AFTER PASS.

        Everything measured is tallied -- the game included -- so that the end of the session can say who held what,
        and for how long. A card shows an instant; a session is a duration, and that is what the owner asks after
        the fact: "during your session of 1 h 35, the window compositor held 10 % of the processor for 1 h 04".
    #>
    $allApps = @(Group-ByApp ($procs.Values | Where-Object { $noise -notcontains $_.Name }))
    # THE STATE OF THE MACHINE goes with the pass: a bottleneck is read from the whole, not from one application.
    # The totals come from what has just been measured; the memory from Windows directly (a few microseconds).
    $cpuTotal = [Math]::Round((($procs.Values | Measure-Object Cpu -Sum).Sum), 1)
    $gpuTotal = [Math]::Round((($procs.Values | Measure-Object Gpu -Sum).Sum), 1)
    $memPct = -1
    $memNow = Get-MemoryStatus
    if ($memNow -and $memNow.CommitLimit -gt 0) { $memPct = [Math]::Round(100 * $memNow.CommitUsed / $memNow.CommitLimit, 1) }
    # THE GAME'S OWN NAMES never make a bottleneck: the game, its launcher, its components.
    $gameNames = @($procs.Values | Where-Object { Test-BelongsToGame -Proc $_ } | ForEach-Object { $_.Name } | Sort-Object -Unique)
    $jamNow = Add-GameTallyPass -Backend $backend -Session $session -Apps $allApps `
                      -CpuTotal $cpuTotal -GpuTotal $gpuTotal -MemoryPct $memPct -GameNames $gameNames

    <#
        WHAT IS IN THE WAY RIGHT NOW -- said during the game, not hours later in the recap.

        On 29/09 the card announced that no other application was greedy while, throughout the jams of a two-hour
        session, Steam held 12,9 % of every core. The greedy alert answers another question: it looks at the whole
        session and demands three minutes of presence. A jam is the opposite -- the machine at its ceiling, right
        now, and whoever takes a share of their own while it lasts.

        The field carries the notification (D54): it turns amber once the jam has lasted the declared minutes, and
        the bubble follows the notification settings like any other.
    #>
    $jamMinutes = [int](Get-ModuleSetting -Unit 'gaming' -Key 'JamNotifyMinutes')
    if (-not $jamMinutes) { $jamMinutes = 5 }
    if ($jamNow -and $jamNow.Jam) {
        $what = switch ("$($jamNow.Jam)") {
            'cpu'    { 'Processeur saturé' }
            'gpu'    { 'Carte graphique saturée' }
            'memory' { 'Mémoire saturée' }
            default  { 'Machine au plafond' }
        }
        $blame = @($jamNow.Offenders | Select-Object -First 2 | ForEach-Object {
            "{0} {1} %" -f $_.Label, ([Math]::Round([Math]::Max($_.Cpu, $_.Gpu), 1)).ToString('N1', $fr) })
        $jamValue = $what + $(if ($blame.Count) { ' · ' + ($blame -join ', ') } else { '' })
        $jamLong = ([int]$jamNow.Seconds -ge ($jamMinutes * 60))
        $fields += New-Field -Key 'jam' -Label 'Ce qui gêne la partie' -Value $jamValue -Kind 'text' `
            -Status $(if ($jamLong) { 'warn' } else { 'neutral' }) `
            -Reason $(if ($jamLong) { ("$what depuis " + $(
                $span = [TimeSpan]::FromSeconds([int]$jamNow.Seconds)
                if ($span.TotalHours -ge 1) { "{0} h {1:00}" -f [int][Math]::Floor($span.TotalHours), $span.Minutes }
                else { "{0} min" -f [int][Math]::Floor($span.TotalMinutes) }) + $(if ($blame.Count) { ' ; en travers : ' + ($blame -join ', ') } else { '' })) } else { $null }) `
            -FixAction $(if ($jamNow.Offenders.Count) { 'open-task-manager' } else { $null }) `
            -Help "La machine est à son plafond et une application étrangère au jeu y prend une part à elle seule. Au-delà du délai réglé, Vigie prévient."
    } else {
        $fields += New-Field -Key 'jam' -Label 'Ce qui gêne la partie' -Value 'Rien' -Kind 'text' -Status 'ok' `
            -Help "La machine n'est pas à son plafond, ou personne d'autre que le jeu n'y prend une part notable."
    }

    <#
        A GREEDY APPLICATION IS ONE THAT LASTS, AND THAT THE GAME DOES NOT NEED.

        The threshold was one percent of the processor, ALL CORES TOGETHER -- a sixth of one core on this computer --
        read over nine hundred milliseconds. The window compositor crossed it merely by drawing the game, and the
        alert went out fourteen times on 16/09 for nothing (reported by the owner on 28/09).

        Two rules now: the share must be worth the word 'greedy' (the default threshold follows), and it must LAST --
        an application seen for less than three minutes of the session is a spike, not a thief. Windows' own
        components keep their place in the table, where they inform, but they never raise the alert on their own:
        the compositor and the client-server runtime work FOR the game.
    #>
    $heldSeconds = @{}
    try {
        $runningTally = Get-Content -LiteralPath (Get-GameTallyPath -Backend $backend) -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($prop in $runningTally.apps.PSObject.Properties) { $heldSeconds[$prop.Name] = [int]$prop.Value.seconds }
    } catch { }
    $greedy = @(Group-ByApp ($procs.Values | Where-Object {
        -not (Test-BelongsToGame -Proc $_) -and $noise -notcontains $_.Name
    }) | Where-Object { ($_.Cpu -ge $otherCpuWarn -or $_.Gpu -ge $otherGpuWarn) -and
                        ($servicesWindows -notcontains $_.Name) -and
                        ([int]$heldSeconds[$_.Name] -ge 180) } |
        Sort-Object { $_.Cpu + $_.Gpu } -Descending)
    $hogs = @($greedy | Select-Object -First 5)
    if ($hogs.Count -gt 0) {
        $recapRows = @($hogs | ForEach-Object {
            $note = if ($servicesWindows -contains $_.Name) { " [service Windows légitime — ne pas fermer]" } else { "" }
            "- {0}{1} : CPU {2} % · GPU {3} % · VRAM {4} Go · E/S {5} Mo/s" -f $_.Label, $note, $_.Cpu, $_.Gpu, $_.VramGb, $_.IoMbs })
        <# A COUNT NAMES NOBODY. "2 detected" forced a trip to the panel to learn WHICH two,
           and a notification is often read without opening anything. The list is already
           ordered by consumption, so the first name is the one worth acting on; beyond two,
           the rest become a number rather than a sentence nobody finishes reading. #>
        $who = switch ($greedy.Count) {
            1       { "$($greedy[0].Court)" }
            2       { "{0} et {1}" -f $greedy[0].Court, $greedy[1].Court }
            default { "{0} et {1} autres" -f $greedy[0].Court, ($greedy.Count - 1) }
        }
        $fields += New-Field -Key 'hogs' -Label 'Autres applis gourmandes' -Value $who `
            -Kind 'text' -Status 'warn' -FixAction 'open-task-manager' `
            -Help "Applications qui consomment beaucoup pendant que le jeu tourne. Les composants du jeu et de sa plateforme de lancement n'y figurent pas : ils font partie de la partie." `
            -Guide (($recapRows + @('', 'Ce qui n''est pas utile a la partie peut se fermer (JAMAIS les services Windows marqués : leur activité est normale) ; les seuils se reglent dans Parametres > Modules > Jeux.')) -join "`n")
    } else {
        $fields += New-Field -Key 'hogs' -Label 'Autres applis gourmandes' -Value 'Aucune' -Kind 'text' -Status 'ok' `
            -Help "Aucune autre application au-dessus des seuils pendant la partie. Les composants du jeu et de sa plateforme de lancement ne comptent pas : ils font partie de la partie."
    }
} elseif ($watchDown) {
    # A MISSING MEASUREMENT IS NOT AN ABSENCE OF GAME. Saying "none" when we do not know is
    # what made the detection look broken yesterday when it simply had not run. We say it,
    # and we hand over what repairs it.
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' -Value 'Surveillance indisponible' -Kind 'text' -Status 'warn' `
        -FixAction 'open-task-manager' `
        -Help "La détection des jeux ne tourne pas : Vigie ne peut ni confirmer ni infirmer qu'une partie est en cours." `
        -Guide ($(if ($watchState -and $watchState.state) { "État de la détection : $($watchState.state)." + $(if ($watchState.error) { " $($watchState.error)" }) }
                  else { "La détection n'a jamais été armée." }) + [Environment]::NewLine +
                "Elle vit à côté de l'app serveur et s'arme avec elle. Si elle reste indisponible, l'app serveur ne " +
                "tourne pas, ou l'abonnement aux démarrages de processus lui a été refusé — il exige les droits administrateur.")
} else {
    # THE SESSION THAT HAS JUST ENDED IS CLOSED HERE, and kept: this is the only place that sees the game gone.
    try { $null = Close-GameTally -Backend $backend } catch { }
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' -Value 'Aucun' -Kind 'text' -Status 'neutral' `
        -Help "Aucune partie en cours. La détection ne mesure pas : elle est prévenue quand un jeu démarre." `
        -Guide ("Un jeu est reconnu à son lancement, par plusieurs méthodes indépendantes : la boutique qui l'a " +
                "lancé, son enregistrement par Windows, sa présence dans une bibliothèque de jeux, ou les " +
                "marqueurs de moteur posés à côté de son exécutable. Une seule qui répond suffit.")
}

# --- Power: a fact about the MACHINE, not about the game ----------------------
# This field used to live inside the "a game is running" branch: with no game detected, no power state was stated
# and the alert about playing on battery could never go out -- two symptoms for one single cause (observed on
# 01/09). The field is now always there; only its STATUS depends on what the machine is rendering, because it is
# 3D rendering on battery that throttles and that deserves the alert.
$rendering = [bool]$game -or ($rejete -and $rejete.Proc.Gpu -ge $gameGpuMin)
if (-not $surSecteur) {
    # THE DROP IS PART OF THE VALUE, and not only of the guide: it is the field's flip that triggers the Windows
    # balloon (D54). A value that does not move warns nobody, even if the battery goes on draining.
    $vide = ($session -and $baisse -ge $dropThreshold)
    $fields += New-Field -Key 'power' -Label 'Alimentation' `
        -Value ("Batterie" + $(if ($null -ne $pctBatterie) { " ($pctBatterie %)" }) +
                $(if ($vide) { " " + [char]0x00B7 + " -$baisse % depuis le début de la partie" })) -Kind 'text' `
        -Status $(if ($rendering -or $vide) { 'warn' } else { 'neutral' }) `
        -FixAction 'open-power-options' `
        -Help "Sur batterie, processeur et carte graphique sont bridés : performances de jeu réduites." `
        -Guide $(if ($vide) { "La partie vide la batterie : $baisse points perdus depuis son début. Le secteur est à brancher — sur batterie, la machine bride aussi le processeur et la carte graphique." }
                 elseif ($rendering) { "Le secteur est à brancher pour la partie." }
                 else { "Rien ne rend en 3D pour l'instant : la bride n'a pas d'effet visible." })
} else {
    $fields += New-Field -Key 'power' -Label 'Alimentation' `
        -Value 'Secteur' -Kind 'text' -Status 'ok' `
        -Help "Sur secteur, la machine donne toute sa puissance."
}

# --- The share-out: the top per DIMENSION, to find who takes what -------------
# An aggregated service host (dozens of services) would dominate without naming anything; the window manager
# stays visible, its compositor VRAM is real information.
$horsBruit = @(Group-ByApp ($procs.Values | Where-Object { $noise -notcontains $_.Name }))
# ONE single TABLE: each application with all its dimensions -- that is the "who takes what" view that was
# asked for, far more readable than one list per dimension.
$meneur = @($horsBruit | Sort-Object { $_.Cpu * 1.5 + $_.Gpu } -Descending)[0]
$repTrie = @($horsBruit | Sort-Object { $_.Cpu * 1.5 + $_.Gpu + $_.VramGb * 10 } -Descending)
$repApps = @($repTrie | Select-Object -First 8)
$repLines = @($repApps |
    ForEach-Object { ,@(($_.Label + $(if ($servicesWindows -contains $_.Name) { ' (Windows)' } else { '' })), $_.Cpu, $_.Gpu, $_.VramGb, $_.RamGb, $_.IoMbs) })
$tipsRep = @($repApps | ForEach-Object { $_.Tip })
# All the rest of the machine, on ONE line: the table becomes addable again.
$repReste = @($repTrie | Select-Object -Skip 8)
if ($repReste.Count) {
    $repLines += ,@(("Autres (" + $repReste.Count + " applications)"),
                     [math]::Round((($repReste | Measure-Object Cpu -Sum).Sum), 1),
                     [math]::Round((($repReste | Measure-Object Gpu -Sum).Sum), 1),
                     [math]::Round((($repReste | Measure-Object VramGb -Sum).Sum), 2),
                     [math]::Round((($repReste | Measure-Object RamGb -Sum).Sum), 2),
                     [math]::Round((($repReste | Measure-Object IoMbs -Sum).Sum), 1))
    $tipsRep += (($repReste | Sort-Object { $_.Cpu + $_.Gpu } -Descending | Select-Object -First 12 |
                  ForEach-Object { $_.Label }) -join [Environment]::NewLine)
}
$fields += New-Field -Key 'top' -Label 'Répartition des ressources' `
    -Value $(if ($meneur) { $meneur.Label } else { '—' }) -Kind 'text' -Status 'neutral' `
    -Help "Les applications les plus consommatrices, toutes dimensions confondues — pour voir qui prend quoi." `
    -Guide "Triées par poids global. E/S = disque et réseau confondus (Windows ne les sépare pas par processus)." `
    -Table @{ columns = @('Application', 'CPU %', 'GPU %', 'VRAM Go', 'RAM Go', 'E/S Mo/s')
              rows = $repLines
              tips = $tipsRep }

$statut = if (($fields | Where-Object { $_.status -eq 'warn' })) { 'warn' } else { 'ok' }
# PERMANENT buttons (D114): what surrounds a game is set in Windows, and the two useful destinations do not depend
# on the state of the card.
# THE MODE SHOWS: while a game lasts, the card does not look like the rest of the time.
# It is a context, not an alert -- its status does not change.
<#
    THE RECAP OF THE LAST SESSION.

    Kept when the game ends, read here: what the session lasted, and who held what, on average and at its peak.
    A line is worth reading only if the application was there: the share of the session it was seen is given with
    its averages, because "10 % of the processor" over four minutes and over an hour are two different facts.
#>
$lastSession = $null
try { $lastSession = Get-LastGameSession -Backend $backend } catch { }
if ($lastSession -and $lastSession.seconds -ge 60) {
    # [Math]::Floor, NEVER [int]: PowerShell ROUNDS a conversion to an integer, and 1 h 35 displayed as 2 h 35.
    $fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    function Format-Span {
        param([int]$Secondes)
        $t = [TimeSpan]::FromSeconds($Secondes)
        if ($t.TotalHours -ge 1) { return ("{0} h {1:00}" -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
        return ("{0} min" -f [int][Math]::Floor($t.TotalMinutes))
    }
    function Format-Share { param($Value) return ([double]$Value).ToString('0.#', $fr) + ' %' }
    $spanText = Format-Span -Secondes ([int]$lastSession.seconds)
    $fin = $null
    try { $fin = (ConvertTo-UtcDate $lastSession.endedAt).ToLocalTime() } catch { }
    $when = if ($fin) { $(if ($fin.Date -eq (Get-Date).Date) { 'terminée à ' + $fin.ToString('HH:mm') } else { 'terminée le ' + $fin.ToString('dd/MM à HH:mm') }) } else { '' }
    # ONE LINE ON THE CARD: the detail lives in the popin (owner, 28/09). The line says which game and what got in
    # the way; the button opens the rest.
    $topJam = @($lastSession.jams) | Select-Object -First 1
    $recapValue = "$($lastSession.game), $spanText" + $(if ($when) { ", $when" } else { '' })
    if ($topJam) { $recapValue += " — $($topJam.label) " + (Format-Span -Secondes ([int]$topJam.seconds)) }
    # THE IDENTITY IS THE END OF THE SESSION, not the line that states it: the line words that end time one way on
    # the day and another way afterwards, and the client app, which watches this field to open the recap, took that
    # wording change for a new session (05/10, recap opened at 06:45 for a session ended the day before at 18:28).
    $fields += New-Field -Key 'last-session' -Label 'Dernière partie' -Value $recapValue -Kind 'text' -Status 'neutral' `
        -Identity "$($lastSession.endedAt)" `
        -FixAction 'game-recap' `
        -Help "La dernière partie gardée : sa durée, et le bouchon qui l'a marquée s'il y en a eu un. Le récapitulatif complet — ce qui a gêné, le jeu, et ce que chaque application a pris — s'ouvre dans sa fenêtre."
}

# SCOPE: the game being played ON THIS COMPUTER, whoever is playing. Processes and loads are read across every
# session, and Game Bar is queried in EVERY account's hive, not in one.
New-ModuleObject -Id 'gaming' -Theme 'gaming' -Label 'Session de jeu' -Scope 'machine' -Status $statut -Fields $fields `
    -Mode $(if ($game) { 'game' } else { $null }) `
    -Actions @(
        # THE RECAP IS A PERMANENT DESTINATION (D114): it reopens whenever wanted, not only at the end of a session.
    New-Action -Id 'game-recap' -Label 'Voir le récapitulatif' -Kind 'dialog' -Severity 'info' `
        -Help "Ouvre le récapitulatif de la dernière partie : ce qui l'a gênée, le jeu, et ce que chaque application a pris."
    New-Action -Id 'game-sessions' -Label 'Parties précédentes' -Kind 'dialog' -Severity 'info' `
        -Help "La liste des parties gardées, trente jours, avec le bouchon marquant de chacune."
    New-Action -Id 'open-gaming-settings' -Label 'Paramètres de jeu' -Kind 'manual' -Severity 'info' `
                   -Help 'Ouvre les réglages de jeu de Windows : barre de jeu, mode Jeu, captures.'
        New-Action -Id 'open-task-manager' -Label 'Gestionnaire des tâches' -Kind 'manual' -Severity 'info' `
                   -Help 'Ouvre le Gestionnaire des tâches pour fermer ce qui pompe pendant la partie.'
    )
