<# Sonde : session de jeu et allocation des ressources. LECTURE SEULE.

   C'est un OUTIL DE DIAGNOSTIC : quand le jeu rame, la carte doit permettre de voir
   qui prend quoi -- processeur, GPU, VRAM, memoire, entrees/sorties -- et de reperer
   l'application qui pompe pendant la partie.

   Mesures (aucun compteur localise -- le systeme est en francais) :
     - CPU   : delta de TotalProcessorTime entre deux instantanes (~0,9 s), normalise
               par le nombre de coeurs ;
     - GPU   : compteurs '\GPU Engine(*)' sommes par PID, plafonnes a 100 ;
     - VRAM  : compteurs '\GPU Process Memory(*)' (dedie) par PID ;
               total reel de la carte : registre pilote (HardwareInformation.qwMemorySize
               -- Win32_VideoController.AdapterRAM MENT au-dela de 4 Go, constate) ;
     - E/S   : delta Read+WriteTransferCount de Win32_Process sur la meme fenetre
               (disque ET reseau confondus -- Windows ne ventile pas par processus sans
               ETW ; le libelle le dit honnetement) ;
     - RAM   : WorkingSet64.

   TEST SANS JEU (docs/MODULES.md) : VIGIE_FAKE_GAME=<nom> force ce processus a etre
   traite comme le jeu ; les valeurs restent reelles. Charge GPU reelle :
   scripts/dev/gpu-load.html (voir la recette dans MODULES.md).
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$gameGpuMin   = [int](Get-ModuleSetting -Unit 'gaming' -Key 'GameGpuMinPct');   if (-not $gameGpuMin)   { $gameGpuMin = 15 }
$otherCpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherCpuWarnPct'); if (-not $otherCpuWarn) { $otherCpuWarn = 1 }
$otherGpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherGpuWarnPct'); if (-not $otherGpuWarn) { $otherGpuWarn = 15 }
$vramWarn     = [int](Get-ModuleSetting -Unit 'gaming' -Key 'VramWarnPct');     if (-not $vramWarn)     { $vramWarn = 90 }

# Processus au premier plan : meilleur indice du jeu quand la partie est active.
$fgPid = 0
try {
    if (-not ('VigieProbe.Fg' -as [type])) {
        Add-Type -Namespace VigieProbe -Name Fg -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int GetWindowThreadProcessId(System.IntPtr hWnd, out int pid);
'@
    }
    $h = [VigieProbe.Fg]::GetForegroundWindow()
    if ($h -ne [IntPtr]::Zero) { [void][VigieProbe.Fg]::GetWindowThreadProcessId($h, [ref]$fgPid) }
} catch { }

# --- Instantane 1 : CPU + E/S cumulees ---------------------------------------
$coeurs = [Math]::Max(1, [int]$env:NUMBER_OF_PROCESSORS)
$avantCpu = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try { $avantCpu[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { }
}
$avantIo = @{}
try {
    foreach ($w in (Get-CimInstance Win32_Process -Property ProcessId,ReadTransferCount,WriteTransferCount)) {
        $avantIo[[int]$w.ProcessId] = [double]$w.ReadTransferCount + [double]$w.WriteTransferCount
    }
} catch { }
$t0 = Get-Date
Start-Sleep -Milliseconds 900

# --- GPU et VRAM par processus (compteurs non localises, verifies ici) --------
$gpuParPid = @{}; $vramParPid = @{}; $gpuDispo = $false
try {
    $g = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
    $gpuDispo = $true
    foreach ($s in $g.CounterSamples) {
        if ($s.InstanceName -match '^pid_(\d+)_') {
            $gp = [int]$Matches[1]
            $gpuParPid[$gp] = [double]($gpuParPid[$gp]) + $s.CookedValue
        }
    }
} catch { }
try {
    foreach ($s in (Get-Counter '\GPU Process Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples) {
        if ($s.InstanceName -match '^pid_(\d+)_') {
            $gp = [int]$Matches[1]
            $vramParPid[$gp] = [double]($vramParPid[$gp]) + $s.CookedValue
        }
    }
} catch { }
$vramUtilisee = 0.0
try {
    $vramUtilisee = ((Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples |
                     Measure-Object CookedValue -Sum).Sum
} catch { }

# --- Instantane 2 + assemblage ------------------------------------------------
$duree = ((Get-Date) - $t0).TotalMilliseconds
$apresIo = @{}
try {
    foreach ($w in (Get-CimInstance Win32_Process -Property ProcessId,ReadTransferCount,WriteTransferCount)) {
        $apresIo[[int]$w.ProcessId] = [double]$w.ReadTransferCount + [double]$w.WriteTransferCount
    }
} catch { }

$procs = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try {
        $cpu = 0.0
        if ($avantCpu.ContainsKey($p.Id)) {
            $cpu = ($p.TotalProcessorTime.TotalMilliseconds - $avantCpu[$p.Id]) / $duree * 100.0 / $coeurs
        }
        $ioMo = 0.0
        if ($avantIo.ContainsKey($p.Id) -and $apresIo.ContainsKey($p.Id)) {
            $ioMo = [Math]::Max(0.0, ($apresIo[$p.Id] - $avantIo[$p.Id]) / $duree * 1000.0 / 1MB)
        }
        $procs[$p.Id] = [pscustomobject]@{
            Id = $p.Id; Name = $p.ProcessName
            Cpu    = [Math]::Round([Math]::Max(0.0, $cpu), 1)
            Gpu    = [Math]::Round([Math]::Min(100.0, [double]($gpuParPid[$p.Id])), 1)
            VramGb = [Math]::Round([double]($vramParPid[$p.Id]) / 1GB, 2)
            RamGb  = [Math]::Round($p.WorkingSet64 / 1GB, 2)
            IoMbs  = [Math]::Round($ioMo, 1)
        }
    } catch { }
}

# --- La ou les cartes graphiques ---------------------------------------------
$gpus = @(); $vramTotale = 0.0
try {
    $gpus = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion)
    # Total VRAM REEL : le registre du pilote (AdapterRAM plafonne a 4 Go).
    $cles = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' `
            -Name 'HardwareInformation.qwMemorySize' -ErrorAction SilentlyContinue
    $vramTotale = ($cles | ForEach-Object { [double]$_.'HardwareInformation.qwMemorySize' } |
                   Measure-Object -Maximum).Maximum
} catch { }

$bruit = @('Idle','System','Memory Compression','Registry','csrss','dwm','svchost',
           'MsMpEng','SearchIndexer','fontdrvhost','WmiPrvSE','conhost','pwsh','powershell')

# Une APPLICATION = tous ses processus du meme nom, sommes. Trois lignes « chrome »
# separees ne disent rien ; une seule ligne agregee dit qui prend quoi.
function Group-ByApp {
    param($Liste)
    @($Liste | Group-Object Name | ForEach-Object {
        [pscustomobject]@{
            Name   = $_.Name
            Cpu    = [Math]::Round((($_.Group | Measure-Object Cpu -Sum).Sum), 1)
            Gpu    = [Math]::Round([Math]::Min(100.0, ($_.Group | Measure-Object Gpu -Sum).Sum), 1)
            VramGb = [Math]::Round((($_.Group | Measure-Object VramGb -Sum).Sum), 2)
            RamGb  = [Math]::Round((($_.Group | Measure-Object RamGb -Sum).Sum), 2)
            IoMbs  = [Math]::Round((($_.Group | Measure-Object IoMbs -Sum).Sum), 1)
        }
    })
}

# Le jeu : simulation, sinon premier plan consommateur de GPU, sinon plus gros GPU.
$jeu = $null
if ($env:VIGIE_FAKE_GAME) {
    $jeu = $procs.Values | Where-Object { $_.Name -like $env:VIGIE_FAKE_GAME } |
           Sort-Object Gpu -Descending | Select-Object -First 1
}
if (-not $jeu -and $fgPid -and $procs.ContainsKey($fgPid) -and
    $procs[$fgPid].Gpu -ge $gameGpuMin -and $bruit -notcontains $procs[$fgPid].Name) {
    $jeu = $procs[$fgPid]
}
if (-not $jeu) {
    $cand = $procs.Values | Where-Object { $bruit -notcontains $_.Name -and $_.Gpu -ge $gameGpuMin } |
            Sort-Object Gpu -Descending | Select-Object -First 1
    if ($cand) { $jeu = $cand }
}

$fields = @()

# --- Carte graphique et VRAM --------------------------------------------------
if ($gpus.Count -gt 0) {
    $principal = ($gpus | Sort-Object { $_.Name -match 'Intel|UHD|Iris' } | Select-Object -First 1)
    $gLignes = @($gpus | ForEach-Object { "- {0} (pilote {1})" -f $_.Name, $_.DriverVersion })
    $fields += New-Field -Key 'gpu-card' -Label 'Carte graphique' -Value $principal.Name -Kind 'text' -Status 'neutral' `
        -Help "La carte qui rend le jeu ; le détail liste tous les adaptateurs et leurs pilotes." `
        -Guide ($gLignes -join "`n")
} else {
    $fields += New-Field -Key 'gpu-card' -Label 'Carte graphique' -Value 'non détectée' -Kind 'text' -Status 'warn' `
        -Help "Aucun adaptateur graphique remonté par Windows." `
        -Guide "Vérifiez le pilote dans le Gestionnaire de périphériques ; sans adaptateur, le suivi GPU est impossible."
}
if ($vramTotale -gt 0) {
    $pctVram = [Math]::Round($vramUtilisee / $vramTotale * 100)
    $stVram = if ($pctVram -ge $vramWarn) { 'warn' } else { 'ok' }
    $fields += New-Field -Key 'vram' -Label 'VRAM utilisée' `
        -Value ("{0:N1} / {1:N0} Go ({2} %)" -f ($vramUtilisee/1GB), ($vramTotale/1GB), $pctVram) -Kind 'text' -Status $stVram `
        -Help "Mémoire dédiée de la carte graphique. Pleine, le jeu compense par la RAM : saccades." `
        -Guide "Au-delà de $vramWarn % (réglable), baissez la qualité des textures ou fermez les applis 3D en fond.`nLes plus gros occupants VRAM sont dans « Répartition des ressources »."
}
if (-not $gpuDispo) {
    $fields += New-Field -Key 'gpu' -Label 'Compteurs GPU' -Value 'indisponibles' -Kind 'text' -Status 'warn' `
        -Help "Les compteurs de performance GPU de Windows ne répondent pas." `
        -Guide "Sans eux, impossible d'attribuer le GPU aux processus.`nPiste : redémarrer, ou reconstruire les compteurs : lodctr /R (invite administrateur)."
}

# --- Le jeu et les pompeurs ---------------------------------------------------
if ($jeu) {
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' -Value $jeu.Name -Kind 'text' -Status 'ok' `
        -Help "Processus au premier plan (ou plus gros consommateur GPU) au-dessus du seuil de détection."
    $fields += New-Field -Key 'game-res' -Label 'Ressources du jeu' `
        -Value ("CPU {0} % · GPU {1} % · VRAM {2} Go" -f $jeu.Cpu, $jeu.Gpu, $jeu.VramGb) -Kind 'text' -Status 'neutral' `
        -Help "Part de la machine consommée par le jeu à l'instant de la mesure." `
        -Guide ("RAM : {0} Go`nE/S (disque+réseau) : {1} Mo/s" -f $jeu.RamGb, $jeu.IoMbs)

    # Les processus freres du jeu (meme nom : lanceur, anti-triche, rendu) font partie
    # du jeu, pas des pompeurs.
    $pompeurs = @(Group-ByApp ($procs.Values | Where-Object {
        $_.Name -ne $jeu.Name -and $bruit -notcontains $_.Name
    }) | Where-Object { $_.Cpu -ge $otherCpuWarn -or $_.Gpu -ge $otherGpuWarn } |
        Sort-Object { $_.Cpu + $_.Gpu } -Descending | Select-Object -First 5)
    if ($pompeurs.Count -gt 0) {
        $lignes = @($pompeurs | ForEach-Object { "- {0} : CPU {1} % · GPU {2} % · VRAM {3} Go · E/S {4} Mo/s" -f $_.Name, $_.Cpu, $_.Gpu, $_.VramGb, $_.IoMbs })
        $fields += New-Field -Key 'hogs' -Label 'Autres applis gourmandes' -Value ("{0} détectée(s)" -f $pompeurs.Count) `
            -Kind 'text' -Status 'warn' `
            -Help "Applications qui consomment beaucoup pendant que le jeu tourne." `
            -Guide (($lignes + '', 'Fermez ce qui n''est pas utile a la partie ; les seuils se reglent dans Parametres > Modules > Jeux.') -join "`n")
    } else {
        $fields += New-Field -Key 'hogs' -Label 'Autres applis gourmandes' -Value 'aucune' -Kind 'text' -Status 'ok' `
            -Help "Aucune autre application au-dessus des seuils pendant la partie."
    }
} else {
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' -Value 'aucun' -Kind 'text' -Status 'neutral' `
        -Help "Aucun processus n'utilise le GPU au-dessus du seuil de détection (réglable dans Paramètres)."
}

# --- Repartition : le top par DIMENSION, pour trouver qui prend quoi ----------
$horsBruit = @(Group-ByApp ($procs.Values | Where-Object { @('Idle','System','Memory Compression','Registry','pwsh','powershell','conhost') -notcontains $_.Name }))
function Format-Top {
    param($Liste, [string]$Propriete, [string]$Unite)
    @($Liste | Sort-Object $Propriete -Descending | Select-Object -First 3 |
      Where-Object { $_.$Propriete -gt 0 } |
      ForEach-Object { "  {0} : {1} {2}" -f $_.Name, $_.$Propriete, $Unite })
}
$rep = @()
$rep += 'Processeur :';            $rep += Format-Top $horsBruit 'Cpu' '%'
$rep += 'GPU :';                   $rep += Format-Top $horsBruit 'Gpu' '%'
$rep += 'VRAM :';                  $rep += Format-Top $horsBruit 'VramGb' 'Go'
$rep += 'RAM :';                   $rep += Format-Top $horsBruit 'RamGb' 'Go'
$rep += 'E/S (disque+réseau) :';   $rep += Format-Top $horsBruit 'IoMbs' 'Mo/s'
$meneur = @($horsBruit | Sort-Object { $_.Cpu * 1.5 + $_.Gpu } -Descending)[0]
$fields += New-Field -Key 'top' -Label 'Répartition des ressources' `
    -Value $(if ($meneur) { $meneur.Name } else { '—' }) -Kind 'text' -Status 'neutral' `
    -Help "Le top 3 par dimension (processeur, GPU, VRAM, RAM, entrées/sorties) — pour voir qui prend quoi." `
    -Guide ($rep -join "`n")

$statut = if (($fields | Where-Object { $_.status -eq 'warn' })) { 'warn' } else { 'ok' }
New-ModuleObject -Id 'gaming' -Theme 'gaming' -Label 'Session de jeu' -Status $statut -Fields $fields
