<# Sonde : jeu en cours et distribution des ressources. LECTURE SEULE.

   Ce qu'elle repond : quel jeu tourne (processus au premier plan ou plus gros
   consommateur GPU), quelle part de la machine il prend, et surtout si UNE AUTRE
   application pompe des ressources pendant la partie -- c'est la question posee.

   Mesures SANS compteurs de processus localises (le systeme est en francais, les
   chemins '\Process(*)' n'existent pas ici) :
     - CPU : delta de TotalProcessorTime entre deux instantanes Get-Process (~0,9 s),
       normalise par le nombre de coeurs ;
     - GPU : compteurs '\GPU Engine(*)' (non localises, verifies sur la machine),
       sommes par PID puis plafonnes a 100 ;
     - RAM : WorkingSet64 du second instantane.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$gameGpuMin   = [int](Get-ModuleSetting -Unit 'gaming' -Key 'GameGpuMinPct');   if (-not $gameGpuMin)   { $gameGpuMin = 15 }
$otherCpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherCpuWarnPct'); if (-not $otherCpuWarn) { $otherCpuWarn = 20 }
$otherGpuWarn = [int](Get-ModuleSetting -Unit 'gaming' -Key 'OtherGpuWarnPct'); if (-not $otherGpuWarn) { $otherGpuWarn = 15 }

# Processus au premier plan : c'est le meilleur indice du jeu si la partie est active.
$fgPid = 0
try {
    if (-not ('VigieProbeFg' -as [type])) {
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

# CPU par delta : deux instantanes a ~0,9 s d'ecart.
$coeurs = [Math]::Max(1, [int]$env:NUMBER_OF_PROCESSORS)
$avant = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try { $avant[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { }
}
$t0 = Get-Date
Start-Sleep -Milliseconds 900

# GPU pendant l'attente n'est pas possible en parallele simple : on le lit juste apres.
$gpuParPid = @{}
$gpuDispo = $false
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

$duree = ((Get-Date) - $t0).TotalMilliseconds
$procs = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try {
        $cpu = 0.0
        if ($avant.ContainsKey($p.Id)) {
            $cpu = ($p.TotalProcessorTime.TotalMilliseconds - $avant[$p.Id]) / $duree * 100.0 / $coeurs
        }
        $gpu = [Math]::Min(100.0, [double]($gpuParPid[$p.Id]))
        $procs[$p.Id] = [pscustomobject]@{
            Id = $p.Id; Name = $p.ProcessName
            Cpu = [Math]::Round([Math]::Max(0.0, $cpu), 1)
            Gpu = [Math]::Round($gpu, 1)
            RamGb = [Math]::Round($p.WorkingSet64 / 1GB, 2)
        }
    } catch { }
}

# Bruit systeme a ne jamais presenter comme « une appli qui pompe ».
$bruit = @('Idle','System','Memory Compression','Registry','csrss','dwm','svchost',
           'MsMpEng','SearchIndexer','fontdrvhost','WmiPrvSE','conhost','pwsh','powershell')

# Le jeu : le premier plan s'il consomme du GPU, sinon le plus gros GPU au-dessus du seuil.
$jeu = $null
if ($fgPid -and $procs.ContainsKey($fgPid) -and $procs[$fgPid].Gpu -ge $gameGpuMin -and $bruit -notcontains $procs[$fgPid].Name) {
    $jeu = $procs[$fgPid]
}
if (-not $jeu) {
    $cand = $procs.Values | Where-Object { $bruit -notcontains $_.Name -and $_.Gpu -ge $gameGpuMin } |
            Sort-Object Gpu -Descending | Select-Object -First 1
    if ($cand) { $jeu = $cand }
}

$fields = @()

if (-not $gpuDispo) {
    # Regle du projet : une information attendue mais absente est un avertissement
    # qui demande une solution, pas une ligne muette.
    $fields += New-Field -Key 'gpu' -Label 'Compteurs GPU' -Value 'indisponibles' -Kind 'text' -Status 'warn' `
        -Help "Les compteurs de performance GPU de Windows ne répondent pas." `
        -Guide "Sans eux, impossible d'attribuer le GPU aux processus.`nPiste : redémarrer, ou reconstruire les compteurs : lodctr /R (invite administrateur)."
}

if ($jeu) {
    $fields += New-Field -Key 'game' -Label 'Jeu détecté' -Value $jeu.Name -Kind 'text' -Status 'ok' `
        -Help "Processus au premier plan (ou plus gros consommateur GPU) au-dessus du seuil de détection."
    $fields += New-Field -Key 'game-res' -Label 'Ressources du jeu' `
        -Value ("CPU {0} % · GPU {1} % · RAM {2} Go" -f $jeu.Cpu, $jeu.Gpu, $jeu.RamGb) -Kind 'text' -Status 'neutral' `
        -Help "Part de la machine consommée par le jeu à l'instant de la mesure."

    # Les autres applis qui pompent PENDANT la partie : c'est la question posee.
    $pompeurs = @($procs.Values | Where-Object {
        $_.Id -ne $jeu.Id -and $bruit -notcontains $_.Name -and
        ($_.Cpu -ge $otherCpuWarn -or $_.Gpu -ge $otherGpuWarn)
    } | Sort-Object { $_.Cpu + $_.Gpu } -Descending | Select-Object -First 5)
    if ($pompeurs.Count -gt 0) {
        $lignes = @($pompeurs | ForEach-Object { "- {0} : CPU {1} % · GPU {2} % · RAM {3} Go" -f $_.Name, $_.Cpu, $_.Gpu, $_.RamGb })
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

# Dans tous les cas : le podium des consommateurs, utile meme hors partie.
# Vigie mesure depuis pwsh : s'afficher soi-meme en tete du podium serait du bruit.
$top = @($procs.Values | Where-Object { @('Idle','System','Memory Compression','Registry','pwsh','powershell','conhost') -notcontains $_.Name } |
         Sort-Object { $_.Cpu * 1.5 + $_.Gpu } -Descending | Select-Object -First 5)
$topLignes = @($top | ForEach-Object { "- {0} : CPU {1} % · GPU {2} % · RAM {3} Go" -f $_.Name, $_.Cpu, $_.Gpu, $_.RamGb })
$fields += New-Field -Key 'top' -Label 'Plus gros consommateurs' -Value ("{0}" -f (@($top)[0].Name)) -Kind 'text' -Status 'neutral' `
    -Help "Les cinq processus qui consomment le plus à l'instant de la mesure (détail en dépliant)." `
    -Guide ($topLignes -join "`n")

$statut = if (($fields | Where-Object { $_.status -eq 'warn' })) { 'warn' } else { 'ok' }
New-ModuleObject -Id 'gaming' -Theme 'gaming' -Label 'Session de jeu' -Status $statut -Fields $fields
