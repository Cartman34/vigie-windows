<# Sonde : session de jeu et allocation des ressources. LECTURE SEULE.

   C'est un OUTIL DE DIAGNOSTIC : quand le jeu rame, la carte doit permettre de voir
   qui prend quoi -- processeur, GPU, VRAM, memoire, entrees/sorties -- et de reperer
   l'application qui pompe pendant la partie.

   Mesures (aucun compteur localise -- le systeme est en francais) :
     - CPU   : delta de TotalProcessorTime entre deux instantanes (~0,9 s), normalise
               par le nombre de coeurs ;
     - GPU   : compteurs '\GPU Engine(*)' sommes par PID, plafonnes a 100 ;
     - VRAM  : '\GPU Process Memory(*)\Local Usage' par PID -- « Dedicated Usage »
               additionne des vues qui se recouvrent (6,94 Go annonces pour 1,70 reels) ;
               total reel de la carte : registre pilote (HardwareInformation.qwMemorySize
               -- Win32_VideoController.AdapterRAM MENT au-dela de 4 Go, constate) ;
     - E/S   : delta Read+WriteTransferCount de Win32_Process sur la meme fenetre
               (disque ET reseau confondus -- Windows ne ventile pas par processus sans
               ETW ; le libelle le dit honnetement) ;
     - RAM   : WorkingSet64.

   TEST SANS JEU (docs/en/developing/modules.md) : VIGIE_FAKE_GAME=<nom> force ce processus a etre
   traite comme le jeu ; les valeurs restent reelles. Charge GPU reelle :
   scripts/dev/gpu-load.html (voir la recette dans modules.md).
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$gameGpuMin   = [int](Get-ModuleSetting -Unit 'gaming' -Key 'GameGpuMinPct');   if (-not $gameGpuMin)   { $gameGpuMin = 15 }
$otherCpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherCpuWarnPct'); if (-not $otherCpuWarn) { $otherCpuWarn = 1 }
$otherGpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherGpuWarnPct'); if (-not $otherGpuWarn) { $otherGpuWarn = 15 }
$vramWarn     = [int](Get-ModuleSetting -Unit 'gaming' -Key 'VramWarnPct');     if (-not $vramWarn)     { $vramWarn = 90 }
$tempWarn     = [int](Get-ModuleSetting -Unit 'gaming' -Key 'GpuTempWarnC');   if (-not $tempWarn)     { $tempWarn = 87 }

# Processus au premier plan : meilleur indice du jeu quand la partie est active.
# Le PLEIN ECRAN est mesure ici aussi : c'est un comportement de jeu, pas un nom.
# NB : le type porte un nom NEUF (Win) parce qu'un type deja charge dans le serveur ne
# peut pas etre complete -- Add-Type serait ignore et les nouvelles methodes absentes.
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
            # Ecran PRINCIPAL : une fenetre sur un second ecran n'est pas vue comme plein
            # ecran. C'est une limite assumee, pas un oubli.
            $largeur = [VigieProbe.Win]::GetSystemMetrics(0)
            $hauteur = [VigieProbe.Win]::GetSystemMetrics(1)
            if ($largeur -gt 0 -and $hauteur -gt 0) {
                $fgPleinEcran = (($r.Right - $r.Left) -ge ($largeur * 0.98) -and ($r.Bottom - $r.Top) -ge ($hauteur * 0.98))
            }
        }
    }
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
$gpuParPid = @{}; $vramParPid = @{}; $luidParPid = @{}; $gpuDispo = $false
try {
    $g = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
    $gpuDispo = $true
    foreach ($s in $g.CounterSamples) {
        if ($s.InstanceName -match '^pid_(\d+)_luid_0x[0-9A-Fa-f]+_0x([0-9A-Fa-f]+)_') {
            $gp = [int]$Matches[1]
            $lu = [Convert]::ToInt64($Matches[2], 16)
            $gpuParPid[$gp] = [double]($gpuParPid[$gp]) + $s.CookedValue
            # Quel ADAPTATEUR travaille pour ce processus : necessaire pour reperer un
            # jeu rendu par la carte integree (Optimus) au lieu de la dediee.
            if (-not $luidParPid.ContainsKey($gp)) { $luidParPid[$gp] = @{} }
            $luidParPid[$gp][$lu] = [double]($luidParPid[$gp][$lu]) + $s.CookedValue
        }
    }
} catch { }
# VRAM par processus : « Local Usage », et non « Dedicated Usage ».
#
# Mesure du 26/08 sur cette machine : la somme de Dedicated Usage donnait 6,94 Go quand
# l'adaptateur n'occupait que 1,70 Go -- dwm y pesait a lui seul plus que la VRAM occupee
# (signale par l'utilisateur : « les chiffres ne semblent pas coherents »). Dedicated
# Usage additionne des vues qui se recouvrent (le compositeur reference les surfaces des
# autres applications). Local Usage totalisait 1,69 Go, soit exactement l'occupation reelle
# de la carte : c'est lui qui dit vrai, application par application.
$compteurVram = '\GPU Process Memory(*)\Local Usage'
try {
    foreach ($s in (Get-Counter $compteurVram -ErrorAction Stop).CounterSamples) {
        if ($s.InstanceName -match '^pid_(\d+)_') {
            $gp = [int]$Matches[1]
            $vramParPid[$gp] = [double]($vramParPid[$gp]) + $s.CookedValue
        }
    }
} catch {
    # Repli si ce compteur manque : mieux vaut une valeur imparfaite que pas de valeur.
    try {
        foreach ($s in (Get-Counter '\GPU Process Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples) {
            if ($s.InstanceName -match '^pid_(\d+)_') {
                $gp = [int]$Matches[1]
                $vramParPid[$gp] = [double]($vramParPid[$gp]) + $s.CookedValue
            }
        }
    } catch { }
}
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
        # Chemin de l'executable : c'est lui qui permet de dire si c'est un JEU (voir plus
        # bas). Inaccessible pour les processus proteges -- on l'accepte, on ne devine pas.
        $chemin = $null
        try { $chemin = $p.Path } catch { }
        $procs[$p.Id] = [pscustomobject]@{
            Id = $p.Id; Name = $p.ProcessName; Path = $chemin
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

# Table luid -> nom d'adaptateur (base DirectX du registre) : c'est elle qui permet de
# dire si un processus est rendu par la carte dediee ou par l'integree.
$nomParLuid = @{}
try {
    foreach ($k in (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\DirectX' -ErrorAction Stop)) {
        $pr = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($pr -and $null -ne $pr.AdapterLuid -and $pr.Description) {
            $nomParLuid[[int64]$pr.AdapterLuid] = "$($pr.Description)"
        }
    }
} catch { }
$aCarteDediee = [bool]($nomParLuid.Values | Where-Object { $_ -notmatch 'Intel|UHD|Iris|Basic Render' })

# Le compteur « Dedicated Usage » MENT parfois (dwm vu a 32 Go sur une carte de 8) :
# une valeur par processus superieure a la VRAM physique est aberrante, on l'ecarte.
if ($vramTotale -gt 0) {
    foreach ($pid2 in @($procs.Keys)) {
        if ($procs[$pid2].VramGb -gt ($vramTotale / 1GB)) { $procs[$pid2].VramGb = 0 }
    }
}

# Deux natures distinctes (choix utilisateur) :
# - bruit de MESURE, jamais montre : le faux processus Idle et Vigie elle-meme ;
# - services WINDOWS legitimes : montres s'ils consomment, mais ANNOTES comme tels --
#   les masquer cacherait une information, conseiller de les fermer serait faux.
$bruit = @('Idle','System','Memory Compression','Registry','conhost','pwsh','powershell')
$servicesWindows = @('lsass','services','wininit','winlogon','smss','csrss','dwm','svchost',
                     'MsMpEng','SearchIndexer','fontdrvhost','WmiPrvSE','RuntimeBroker',
                     'SearchHost','taskhostw')

# Une APPLICATION = tous ses processus du meme nom, sommes. Trois lignes « chrome »
# separees ne disent rien ; une seule ligne agregee dit qui prend quoi.
function Group-ByApp {
    param($Liste)
    @($Liste | Group-Object Name | ForEach-Object {
        # Nom LISIBLE : « csrss » ne parle a personne. Le chemin vient du premier processus
        # du groupe qui accepte de le donner.
        $chemins = @($_.Group | ForEach-Object { $_.Path } | Where-Object { $_ } | Sort-Object -Unique)
        $chemin = @($chemins | Select-Object -First 1)[0]
        [pscustomobject]@{
            Name   = $_.Name
            Label  = (Get-AppDisplayName -ProcessName $_.Name -Path $chemin -Complet)
            Court  = (Get-AppDisplayName -ProcessName $_.Name -Path $chemin)
            Tip    = (Get-AppInfoTip -ProcessName $_.Name -Paths $chemins -Ids @($_.Group | ForEach-Object { [int]$_.Id }))
            Cpu    = [Math]::Round((($_.Group | Measure-Object Cpu -Sum).Sum), 1)
            Gpu    = [Math]::Round([Math]::Min(100.0, ($_.Group | Measure-Object Gpu -Sum).Sum), 1)
            VramGb = [Math]::Round((($_.Group | Measure-Object VramGb -Sum).Sum), 2)
            RamGb  = [Math]::Round((($_.Group | Measure-Object RamGb -Sum).Sum), 2)
            IoMbs  = [Math]::Round((($_.Group | Measure-Object IoMbs -Sum).Sum), 1)
        }
    })
}

# --- EST-CE UN JEU ? ----------------------------------------------------------
# Consommer le GPU ne fait pas un jeu : une application Chromium/Electron (ChatGPT,
# Discord, VS Code, un navigateur) affiche son interface avec le GPU et se retrouvait
# annoncee comme « jeu detecte » -- signale par l'utilisateur le 25/08.
#
# On ne juge donc PAS sur le nom (aucune liste noire d'applications a maintenir) mais sur
# des FAITS verifiables autour de l'executable :
#   + Windows lui-meme l'a enregistre comme jeu (Game Bar, HKCU\System\GameConfigStore) ;
#   + il est installe dans une bibliotheque Steam REELLE (lue dans la config de Steam) ;
#   + un moteur ou un SDK de jeu est pose a cote (steam_api*.dll, UnityPlayer.dll,
#     Content\Paks d'Unreal, EOSSDK...) ;
#   + sa fenetre occupe tout l'ecran ;
#   - des marqueurs Chromium/Electron sont dans son dossier (chrome_*.pak, app.asar...).
# Au-dessus du seuil, c'est un jeu ; en dessous, la carte dit « aucun » ET pourquoi.
$SCORE_JEU = 3

# Bibliotheques Steam : lues dans la configuration de Steam, jamais devinees.
$steamLibs = @()
try {
    $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction Stop).SteamPath
    if ($sp) {
        $spw = ($sp -replace '/', '\')
        $steamLibs += $spw.ToLower()
        $vdf = Join-Path $spw 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $steamLibs += ($m.Groups[1].Value -replace '\\\\', '\').ToLower()
            }
        }
    }
} catch { }

# Executables que WINDOWS a lui-meme reconnus comme des jeux (Game Bar).
$jeuxWindows = @()
try {
    foreach ($k in (Get-ChildItem 'HKCU:\System\GameConfigStore\Children' -ErrorAction Stop)) {
        $v = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).MatchedExeFullPath
        if ($v) { $jeuxWindows += "$v".ToLower() }
    }
} catch { }

function Get-GameScore {
    param([string]$Path, [bool]$PleinEcran)
    $raisons = @()
    if (-not $Path) { return @{ Score = 0; Raisons = @('exécutable non lisible') } }
    $score = 0
    $dossier = Split-Path $Path -Parent
    # Anti-signal : coquille Chromium/Electron.
    foreach ($m in @('chrome_100_percent.pak', 'chrome.dll', 'icudtl.dat', 'resources\app.asar')) {
        if (Test-Path -LiteralPath (Join-Path $dossier $m)) {
            $score -= 5; $raisons += "application Chromium/Electron (marqueur $m)"; break
        }
    }
    if ($jeuxWindows -contains $Path.ToLower()) { $score += 4; $raisons += 'reconnu comme jeu par Windows (Game Bar)' }
    foreach ($lib in $steamLibs) {
        # « steamapps\common » : c'est LA ou Steam installe les jeux. Viser la racine de la
        # bibliotheque suffirait a faire passer steam.exe lui-meme pour un jeu.
        if ($lib -and $Path.ToLower().StartsWith($lib) -and $Path.ToLower().Contains('steamapps\common')) {
            $score += 3; $raisons += 'installé dans une bibliothèque Steam'; break
        }
    }
    # Moteur ou SDK de jeu, a cote de l'executable ou juste au-dessus (3 niveaux).
    $d = $dossier; $trouve = $null
    for ($i = 0; $i -lt 3 -and $d; $i++) {
        foreach ($m in @('steam_api.dll', 'steam_api64.dll', 'steam_appid.txt', 'UnityPlayer.dll',
                         'EOSSDK-Win64-Shipping.dll', 'Content\Paks', '.egstore')) {
            if (Test-Path -LiteralPath (Join-Path $d $m)) { $trouve = $m; break }
        }
        if ($trouve) { break }
        $d = Split-Path $d -Parent
    }
    if ($trouve) { $score += 3; $raisons += "moteur ou SDK de jeu présent ($trouve)" }
    if ($PleinEcran) { $score += 2; $raisons += 'fenêtre en plein écran' }
    if (-not $raisons.Count) { $raisons += 'aucun signe de jeu autour de l''exécutable' }
    @{ Score = $score; Raisons = $raisons }
}

# Le jeu : simulation, sinon le meilleur candidat GPU qui passe l'examen ci-dessus.
$jeu = $null
$jeuRaisons = $null  # ce qui a fait dire « c'est un jeu » -- affiche au guide
$rejete = $null      # ce qui consommait le plus sans etre un jeu : on le dira
if ($env:VIGIE_FAKE_GAME) {
    $jeu = $procs.Values | Where-Object { $_.Name -like $env:VIGIE_FAKE_GAME } |
           Sort-Object Gpu -Descending | Select-Object -First 1
}
if (-not $jeu) {
    # On n'examine que les vrais candidats (six au plus) : ouvrir le dossier de chaque
    # processus de la machine couterait cher pour rien.
    # Le SEUIL ne filtre plus les candidats : un jeu en pause ou dans un menu retombe sous
    # les 15 % et disparaissait de la carte (signale par l'utilisateur pendant une partie
    # d'Autonauts). C'est desormais l'EXAMEN qui fait foi ; le seuil ne sert plus qu'a dire
    # si le jeu rend activement (voir plus bas). On garde un plancher a 1 % : en dessous, le
    # processus ne rend rien du tout.
    $candidats = @($procs.Values |
        Where-Object { $_.Gpu -ge 1 -and $bruit -notcontains $_.Name -and $servicesWindows -notcontains $_.Name } |
        Sort-Object Gpu -Descending | Select-Object -First 6)
    $examen = @(foreach ($c in $candidats) {
        $sc = Get-GameScore -Path $c.Path -PleinEcran ($c.Id -eq $fgPid -and $fgPleinEcran)
        # Etre au premier plan departage deux jeux possibles, sans jamais en faire un.
        [pscustomobject]@{ Proc = $c; Score = $sc.Score; Raisons = $sc.Raisons; Premier = ($c.Id -eq $fgPid) }
    })
    $retenu = @($examen | Where-Object { $_.Score -ge $SCORE_JEU } |
                Sort-Object @{ Expression = { $_.Score } ; Descending = $true },
                            @{ Expression = { $_.Premier } ; Descending = $true },
                            @{ Expression = { $_.Proc.Gpu } ; Descending = $true })[0]
    if ($retenu) { $jeu = $retenu.Proc; $jeuRaisons = $retenu.Raisons }
    elseif ($examen.Count) { $rejete = @($examen | Sort-Object { $_.Proc.Gpu } -Descending)[0] }
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
            $vramToutes = @(Group-ByApp ($procs.Values | Where-Object { $_.VramGb -gt 0 }) |
                            Sort-Object VramGb -Descending)
            $vramApps = @($vramToutes | Select-Object -First 6)
            # CE QUI N'EST PAS LISTE EST AGREGE (demande utilisateur) : sans cette ligne,
            # l'utilisateur additionne le tableau, ne retrouve pas le total, et a raison
            # de trouver ca incoherent.
            $vramReste  = @($vramToutes | Select-Object -Skip 6)
            $lignesVram = @($vramApps | ForEach-Object { ,@($_.Label, $_.VramGb) })
            $tipsVram   = @($vramApps | ForEach-Object { $_.Tip })
            if ($vramReste.Count) {
                $sommeReste = [math]::Round((($vramReste | Measure-Object VramGb -Sum).Sum), 2)
                $lignesVram += ,@(("Autres (" + $vramReste.Count + " applications)"), $sommeReste)
                $tipsVram   += (($vramReste | ForEach-Object { $_.Label + " : " + $_.VramGb + " Go" }) -join [Environment]::NewLine)
            }
            @{ columns = @('Application', 'VRAM (Go)')
               rows = $lignesVram
               # Une infobulle par ligne : chemin absolu, editeur, PID (demande utilisateur).
               tips = $tipsVram })
}
if (-not $gpuDispo) {
    $fields += New-Field -Key 'gpu' -Label 'Compteurs GPU' -Value 'indisponibles' -Kind 'text' -Status 'warn' `
        -Help "Les compteurs de performance GPU de Windows ne répondent pas." `
        -FixAction 'perf-counters-rebuild' `
        -Guide "Sans eux, impossible d'attribuer le GPU aux processus.`nLe bouton reconstruit la base des compteurs de Windows (lodctr /R) puis resynchronise WMI, et vérifie ensuite qu'ils répondent. Si ce n'est pas le cas, un redémarrage de Windows les rétablit."
}

# --- Sante du GPU dedie (nvidia-smi, livre avec le pilote) --------------------
$aNvidia = [bool]($gpus | Where-Object { $_.Name -match 'NVIDIA' })
if ($aNvidia) {
    $smi = 'C:\Windows\System32\nvidia-smi.exe'
    if (Test-Path $smi) {
        try {
            $ln = (& $smi '--query-gpu=temperature.gpu,power.draw,clocks.sm,utilization.gpu,clocks_event_reasons.active' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1)
            if (-not $ln) {
                # Pilotes plus anciens : l'ancien nom du champ de bridage.
                $ln = (& $smi '--query-gpu=temperature.gpu,power.draw,clocks.sm,utilization.gpu,clocks_throttle_reasons.active' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1)
            }
            if ($ln) {
                $c = @(($ln -split ',') | ForEach-Object { "$_".Trim() })
                $temp = [int]$c[0]
                # Le masque de raisons melange gestion d'energie NORMALE (repos 0x1,
                # limite logicielle de puissance 0x4, plafond applicatif 0x2, sync 0x10)
                # et VRAIS bridages : ralenti materiel 0x8, thermique logiciel 0x20,
                # thermique materiel 0x40, frein de puissance materiel 0x80. Tout melanger
                # affichait « bridee » au repos a 48 degres (constate) : faux positif.
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
                if ($bridage) { $gT += ("La carte BRIDE ses fréquences : " + ($raisons -join ' ; ') + ". Vérifiez la ventilation et les entrées d'air.") }
                elseif ($temp -ge $tempWarn) { $gT += "Au-delà de $tempWarn degrés (réglable), la carte va se brider : chutes de FPS. Vérifiez la ventilation." }
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

# --- Alimentation : jouer sur batterie bride tout -----------------------------
$surSecteur = $true; $pctBatterie = $null
try {
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bat) {
        $surSecteur = ($bat.BatteryStatus -ne 1)   # 1 = en decharge
        $pctBatterie = [int]$bat.EstimatedChargeRemaining
    }
} catch { }
$plan = ''
try { if ((powercfg /getactivescheme) -match '\(([^)]+)\)') { $plan = $Matches[1] } } catch { }

# --- Le jeu et les pompeurs ---------------------------------------------------
if ($jeu) {
    # DIRE POURQUOI : « jeu detecte : X » sans justification a deja design ChatGPT.
    $pourquoi = if ($env:VIGIE_FAKE_GAME) { @("Simulation (VIGIE_FAKE_GAME=$($env:VIGIE_FAKE_GAME)) : les mesures restent réelles.") }
                elseif ($jeuRaisons) { @('Reconnu comme jeu parce que :') + @($jeuRaisons | ForEach-Object { "- $_" }) }
                else { @() }
    if ($jeu.Path) { $pourquoi += "Exécutable : $($jeu.Path)" }
    # Le jeu reste LE jeu meme quand il ne rend pas : on le dit au lieu de le faire
    # disparaitre (menu, pause, chargement).
    $auRepos = ($jeu.Gpu -lt $gameGpuMin)
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' `
        -Value ((Get-AppDisplayName -ProcessName $jeu.Name -Path $jeu.Path -Complet) + $(if ($auRepos) { ' (menu ou pause)' } else { '' })) -Kind 'text' -Status 'ok' `
        -Help "Application qui consomme le GPU ET qui présente des signes de jeu (bibliothèque de jeux, moteur, plein écran)." `
        -Guide $(if ($pourquoi.Count) { $pourquoi -join "`n" } else { $null })
    $fields += New-Field -Key 'game-res' -Label 'Ressources du jeu' `
        -Value ("CPU {0} % · GPU {1} % · VRAM {2} Go" -f $jeu.Cpu, $jeu.Gpu, $jeu.VramGb) -Kind 'text' -Status 'neutral' `
        -Help "Part de la machine consommée par le jeu à l'instant de la mesure." `
        -Guide ("RAM : {0} Go`nE/S (disque+réseau) : {1} Mo/s" -f $jeu.RamGb, $jeu.IoMbs)

    # Sur quel adaptateur le jeu est-il rendu ? Le piege Optimus : la carte integree
    # rend le jeu pendant que la dediee dort -- performances divisees sans message.
    if ($luidParPid.ContainsKey($jeu.Id) -and $nomParLuid.Count -gt 0) {
        $luDominant = ($luidParPid[$jeu.Id].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        $nomAd = $nomParLuid[[int64]$luDominant]
        if ($nomAd) {
            $surIntegree = ($nomAd -match 'Intel|UHD|Iris|Basic Render')
            $stAd = if ($surIntegree -and $aCarteDediee) { 'warn' } else { 'ok' }
            $argsAd = @{
                Key = 'game-adapter'; Label = 'Rendu par'; Value = $nomAd; Kind = 'text'; Status = $stAd
                Help = "L'adaptateur graphique qui rend le jeu. Sur ce portable, la carte dédiée doit s'en charger."
            }
            if ($stAd -eq 'warn') {
                $argsAd.Guide = "Le jeu tourne sur la carte INTÉGRÉE alors qu'une carte dédiée existe : performances bridées.`nParamètres Windows > Système > Affichage > Cartes graphiques : ajoutez l'exécutable du jeu et choisissez « Hautes performances »."
            }
            $fields += New-Field @argsAd
        }
    }

    # Les processus freres du jeu (meme nom : lanceur, anti-triche, rendu) font partie
    # du jeu, pas des pompeurs.
    $pompeurs = @(Group-ByApp ($procs.Values | Where-Object {
        $_.Name -ne $jeu.Name -and $bruit -notcontains $_.Name
    }) | Where-Object { $_.Cpu -ge $otherCpuWarn -or $_.Gpu -ge $otherGpuWarn } |
        Sort-Object { $_.Cpu + $_.Gpu } -Descending | Select-Object -First 5)
    if ($pompeurs.Count -gt 0) {
        $lignes = @($pompeurs | ForEach-Object {
            $note = if ($servicesWindows -contains $_.Name) { " [service Windows légitime — ne pas fermer]" } else { "" }
            "- {0}{1} : CPU {2} % · GPU {3} % · VRAM {4} Go · E/S {5} Mo/s" -f $_.Label, $note, $_.Cpu, $_.Gpu, $_.VramGb, $_.IoMbs })
        $fields += New-Field -Key 'hogs' -Label 'Autres applis gourmandes' -Value ("{0} détectée(s)" -f $pompeurs.Count) `
            -Kind 'text' -Status 'warn' -FixAction 'open-task-manager' `
            -Help "Applications qui consomment beaucoup pendant que le jeu tourne." `
            -Guide (($lignes + '', 'Fermez ce qui n''est pas utile a la partie (JAMAIS les services Windows marqués : leur activité est normale) ; les seuils se reglent dans Parametres > Modules > Jeux.') -join "`n")
    } else {
        $fields += New-Field -Key 'hogs' -Label 'Autres applis gourmandes' -Value 'aucune' -Kind 'text' -Status 'ok' `
            -Help "Aucune autre application au-dessus des seuils pendant la partie."
    }
    if (-not $surSecteur) {
        $fields += New-Field -Key 'power' -Label 'Alimentation' `
            -Value ("Batterie" + $(if ($null -ne $pctBatterie) { " ($pctBatterie %)" })) -Kind 'text' -Status 'warn' `
            -FixAction 'open-power-options' `
            -Help "Sur batterie, processeur et carte graphique sont bridés : performances de jeu réduites." `
            -Guide ("Branchez le secteur pour la partie." + $(if ($plan) { "`nPlan d'alimentation actif : $plan." }))
    } else {
        $fields += New-Field -Key 'power' -Label 'Alimentation' `
            -Value ("Secteur" + $(if ($plan) { " " + [char]0x00B7 + " $plan" })) -Kind 'text' -Status 'ok' `
            -Help "Sur secteur, la machine donne toute sa puissance."
    }
} else {
    # Quand une application consomme le GPU sans etre un jeu, on ne se tait pas : on dit
    # laquelle et POURQUOI elle n'a pas ete retenue. Sinon « aucun » ressemble a un rate.
    $guideAucun = $null
    if ($rejete) {
        $nomRejete = Get-AppDisplayName -ProcessName $rejete.Proc.Name -Path $rejete.Proc.Path -Complet
        $guideAucun = (@("$nomRejete utilise le GPU ($($rejete.Proc.Gpu) %) mais n'est pas un jeu :") +
                       @($rejete.Raisons | ForEach-Object { "- $_" }) +
                       @('', 'Son activité reste visible dans « Répartition des ressources ».')) -join "`n"
    }
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' -Value 'Aucun' -Kind 'text' -Status 'neutral' `
        -Help $(if ($rejete) { "Aucune application de jeu en cours. Le plus gros consommateur GPU est $(Get-AppDisplayName -ProcessName $rejete.Proc.Name -Path $rejete.Proc.Path -Complet), qui n'en est pas un." }
                else { "Aucun processus n'utilise le GPU au-dessus du seuil de détection (réglable dans Paramètres)." }) `
        -Guide $guideAucun
}

# --- Repartition : le top par DIMENSION, pour trouver qui prend quoi ----------
# svchost agrege (des dizaines de services) dominerait sans rien designer ; dwm reste
# visible, sa VRAM de compositeur est une vraie information.
$horsBruit = @(Group-ByApp ($procs.Values | Where-Object { $bruit -notcontains $_.Name }))
# Un TABLEAU unique : chaque application avec toutes ses dimensions -- c'est la vue
# « qui prend quoi » demandee, bien plus lisible qu'une liste par dimension.
$meneur = @($horsBruit | Sort-Object { $_.Cpu * 1.5 + $_.Gpu } -Descending)[0]
$repTrie = @($horsBruit | Sort-Object { $_.Cpu * 1.5 + $_.Gpu + $_.VramGb * 10 } -Descending)
$repApps = @($repTrie | Select-Object -First 8)
$lignesRep = @($repApps |
    ForEach-Object { ,@(($_.Label + $(if ($servicesWindows -contains $_.Name) { ' (Windows)' } else { '' })), $_.Cpu, $_.Gpu, $_.VramGb, $_.RamGb, $_.IoMbs) })
$tipsRep = @($repApps | ForEach-Object { $_.Tip })
# Tout le reste de la machine, en UNE ligne : le tableau redevient additionnable.
$repReste = @($repTrie | Select-Object -Skip 8)
if ($repReste.Count) {
    $lignesRep += ,@(("Autres (" + $repReste.Count + " applications)"),
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
              rows = $lignesRep
              tips = $tipsRep }

$statut = if (($fields | Where-Object { $_.status -eq 'warn' })) { 'warn' } else { 'ok' }
New-ModuleObject -Id 'gaming' -Theme 'gaming' -Label 'Session de jeu' -Status $statut -Fields $fields
