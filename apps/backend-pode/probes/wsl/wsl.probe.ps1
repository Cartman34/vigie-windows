# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    Probe: WSL2. READ ONLY. It does NOT call wsl.exe -- that call can hang -- and reads the
    registry and the processes instead. Fast, and nothing can freeze on it.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$installed = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
$default = '(aucune)'
# WSL distributions are installed PER USER. The server runs under the service account, so the
# ambient hive would be its own -- and it has never installed WSL. The REQUESTER's hive is read
# instead, falling back to the hives of the signed-in users (D113).
$wslHives = @()
$requester = Get-StateAccount
if ($requester) { $wslHives += @(Get-AccountRegistryRoot -Account $requester) }
$wslHives += @(Get-UserRegistryRoots)
foreach ($hive in ($wslHives | Where-Object { $_ })) {
    try {
        $lxss = Join-Path $hive 'SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
        $guid = (Get-ItemProperty $lxss -Name DefaultDistribution -ErrorAction SilentlyContinue).DefaultDistribution
        if (-not $guid) { continue }
        $distName = (Get-ItemProperty (Join-Path $lxss $guid) -Name DistributionName -ErrorAction SilentlyContinue).DistributionName
        if ($distName) { $default = $distName; break }
    } catch { }
}
$running = [bool](Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue)

# THE MEMORY OF ITS VIRTUAL MACHINE (WSL-STATE). On 18/09 vmmemWSL held 14 to 16 GB and Windows warned of saturation;
# the card said "Actif", nothing more. What it holds IN RAM and what it has COMMITTED are read apart, as on the
# Resources card (Get-ProcessMemoryUse): the committed figure was shown as "memory" until 18/09, 2 GB above the truth.
$fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
$vmBytes = 0.0
$vmCommitted = 0.0
$memoryUse = Get-ProcessMemoryUse
foreach ($vm in @(Get-Process -Name 'vmmemWSL' -ErrorAction SilentlyContinue)) {
    if ($memoryUse.ContainsKey($vm.Id)) { $vmBytes += $memoryUse[$vm.Id].Ram; $vmCommitted += $memoryUse[$vm.Id].Committed }
}
$physical = Get-MemoryStatus
$physicalBytes = if ($physical) { $physical.TotalPhys } else { 0 }
$warnPct = [int](Get-ModuleSetting -Unit 'wsl' -Key 'VmMemoryWarnPct')
# THE BOUND THE USER SET, read in the .wslconfig of the one who asks: a personal file, in their own profile.
$wslConfigPath = if ($requester) { Join-Path $env:SystemDrive (Join-Path 'Users' (Join-Path $requester '.wslconfig')) } else { '%USERPROFILE%\.wslconfig' }
$bound = $null
$reclaim = $null
if ($requester -and (Test-PathSafe $wslConfigPath)) {
    $section = ''
    foreach ($line in @(Get-Content -LiteralPath $wslConfigPath -ErrorAction SilentlyContinue)) {
        $t = "$line".Trim()
        if ($t -match '^\[(.+)\]$') { $section = $Matches[1].Trim().ToLowerInvariant(); continue }
        if ($section -eq 'wsl2' -and $t -match '^memory\s*=\s*(\S+)') { $bound = $Matches[1] }
        if ($section -eq 'experimental' -and $t -match '^autoMemoryReclaim\s*=\s*(\S+)') { $reclaim = $Matches[1] }
    }
}
$vmPct = if ($physicalBytes) { [math]::Round(100 * $vmBytes / $physicalBytes) } else { 0 }
$vmStatus = if (-not $vmBytes) { 'neutral' } elseif ($vmPct -ge $warnPct) { 'warn' } else { 'ok' }
# THREE CASES WITHOUT A FIGURE, each said as it is: WSL absent, its virtual machine stopped, or a reading refused.
$vmRunning = [bool](Get-Process -Name 'vmmemWSL' -ErrorAction SilentlyContinue)
$vmValue = if (-not $installed) { 'Sans objet : WSL absent' }
           elseif (-not $vmRunning) { 'Aucune : machine virtuelle arrêtée' }
           elseif (-not $memoryUse.Count) { 'Illisible' }
           else { ($vmBytes / 1GB).ToString('N1', $fr) + ' Go en mémoire vive (' + $vmPct + ' %), ' + ($vmCommitted / 1GB).ToString('N1', $fr) + ' Go engagés' }
if ($requester -and $installed) { $vmValue += if ($bound) { ' · bornée à ' + $bound } else { ' · non bornée' } }
$vmGuide = $null
$vmReason = $null
if ($vmStatus -eq 'warn') {
    $suggestGb = [math]::Max(4, [math]::Round($physicalBytes / 1GB / 4))
    $vmReason = 'La machine virtuelle de WSL occupe ' + ($vmBytes / 1GB).ToString('N1', $fr) + ' Go de mémoire vive, ' + $vmPct + ' %'
    $vmGuide = $vmReason + '. Ce chiffre comprend le cache de fichiers de Linux : dans WSL, « free » le compte comme disponible, mais pour Windows cette mémoire est occupée tant que WSL ne la rend pas.' + [Environment]::NewLine + [Environment]::NewLine +
               $(if ($bound) { "Elle est bornée à $bound dans $wslConfigPath. Pour la réduire, y abaisser la ligne « memory= » de la section [wsl2], par exemple :" }
                 else { "Rien ne la borne : sans réglage, WSL peut prendre jusqu'à la moitié de la mémoire vive. Pour la borner soi-même, ouvrir le fichier $wslConfigPath (le créer s'il n'existe pas) et y écrire :" }) +
               [Environment]::NewLine + "[wsl2]" + [Environment]::NewLine + "memory=$($suggestGb)GB" + [Environment]::NewLine + [Environment]::NewLine +
               $(if ($reclaim -and $reclaim -notmatch '^(?i)dropcache$') {
                   "Le même fichier règle, dans la section [experimental], « autoMemoryReclaim=$reclaim » : avec « gradual », Linux rend son cache lentement ; avec « disabled », jamais. « dropCache », la valeur par défaut selon Microsoft, le rend aussitôt." + [Environment]::NewLine + [Environment]::NewLine
               } else { '' }) +
               "Le réglage s'applique au prochain démarrage de WSL : le bouton « Arrêter » ci-dessous l'arrête, comme « wsl --shutdown » ; ce qui tourne sous Linux est coupé."
}

# =============================================================================
# HOW SERIOUS "INACTIVE" IS -- a product decision, ONE LINE TO CHANGE.
# The field AND the card derive from it, so they can no longer contradict each other.
#   'error'   -> red    : WSL being inactive is said plainly    (current choice, D20)
#   'warn'    -> orange : worth watching, without alarming
#   'neutral' -> grey   : an ordinary state, no alert
# =============================================================================
$inactiveSeverity = 'error'

# A readable, coloured status (Actif/Inactif) rather than a bare Yes/No.
$statutValue = if ($running) { 'Actif' } else { 'Inactif' }
$statutStat  = if ($running) { 'ok' } else { $inactiveSeverity }

# The card carries the SAME judgement as the field: one source of truth.
# WSL being absent stays neutral -- the computer is not blamed for not having installed it.
$st = if (-not $installed) { 'neutral' } elseif ($running -and $vmStatus -eq 'warn') { 'warn' } elseif ($running) { 'ok' } else { $inactiveSeverity }

# Start, restart, stop: only the buttons the current state makes sense of.
$wslActions = @()
if ($installed) {
    if ($running) {
        $wslActions += New-Action -Id 'wsl-restart' -Severity 'fix'  -Label 'Redémarrer' -Confirm `
        -Impact "Arrêt complet de WSL puis relance : mêmes conséquences qu'un arrêt, suivies d'un démarrage propre." `
        -Usage "Quand une distribution ne répond plus, ou après avoir changé sa configuration (.wslconfig)." `
        -Reversible "Sans objet : c'est un redémarrage." -Kind 'confirm' -Help "Arrête puis relance WSL. Les programmes WSL non sauvegardés seront fermés."
        $wslActions += New-Action -Id 'wsl-shutdown' -Label 'Arrêter'    -Confirm `
        -Impact ("Arrête toutes les distributions Linux et la machine virtuelle qui les héberge. Les programmes " +
                 "qui y tournent sont coupés : ce qui n'est pas enregistré est perdu. Docker Desktop, s'il " +
                 "s'appuie sur WSL, s'arrête aussi.") `
        -Usage "Pour libérer la mémoire prise par WSL, ou avant de sauvegarder son disque virtuel." `
        -Reversible "Oui : WSL repart tout seul à la prochaine commande Linux." -Kind 'confirm' -Help "Arrête proprement toutes les distributions WSL en cours."
    } else {
        $wslActions += New-Action -Id 'wsl-start' -Severity 'fix'    -Label 'Démarrer'   -Kind 'immediate' -Help "Démarre WSL (boot de la distribution par défaut)."
    }
}

<#
    WHAT WSL SAID, REPORTED WORD FOR WORD.

    WSL speaks only on the console of whoever runs it, and nothing of it reaches the Windows journal: a warning
    is therefore seen by the person typing, once, and by nobody afterwards. A key written in the wrong section of
    `.wslconfig` was ignored for weeks that way -- the reclaiming of memory it was meant to switch on never ran,
    and WSL kept everything it took.

    This card does not judge the configuration: judging it would mean writing a second WSL, which would be wrong
    the day WSL changes. It REPEATS what WSL answered, and that is the job (the owner, 25/10).

    The reading is taken in the session of an account, by the task that already measures what the distributions
    hold: the configuration and the distributions belong to the account, and the service account has neither.
#>
$wslSaid = @()
$wslSilent = $false
$saidForNow = $true
$usage = Get-WslUsage -Backend $backend
if ($usage) {
    $wslSaid = @(@($usage.messages) | Where-Object { "$_".Trim() })
    $wslSilent = [bool]$usage.timedOut
    # IS IT STILL ABOUT THE WSL RUNNING NOW? What WSL said concerns the start that read the configuration. If the
    # machine has restarted since, the warning is a memory, and it is said as such instead of being asserted.
    $heardFor = "$($usage.messagesVm)"
    $nowVm = ''
    foreach ($vm in @(Get-Process -Name 'vmmemWSL', 'wslservice' -ErrorAction SilentlyContinue)) {
        try { $nowVm = $vm.StartTime.ToUniversalTime().ToString('o'); break } catch { }
    }
    if ($wslSaid.Count -and $heardFor -and $nowVm -and $heardFor -ne $nowVm) { $saidForNow = $false }
}
$saidStatus = 'ok'
$saidValue = 'Rien à signaler'
if ($wslSaid.Count -and $saidForNow) { $saidStatus = 'warn'; $saidValue = "$($wslSaid.Count) avertissement(s)" }
elseif ($wslSaid.Count) { $saidStatus = 'neutral'; $saidValue = "$($wslSaid.Count) avertissement(s) au démarrage précédent" }
elseif ($wslSilent) { $saidStatus = 'warn'; $saidValue = "WSL n'a pas répondu dans le délai" }
elseif (-not $usage) { $saidStatus = 'neutral'; $saidValue = 'Pas encore demandé' }
$saidGuide = $null
if ($wslSaid.Count) {
    $saidGuide = $(if ($saidForNow) { "Ce que WSL a répondu, mot pour mot :" } else { "Ce que WSL avait répondu lors d'un démarrage précédent de sa machine virtuelle — elle a redémarré depuis, et il n'a rien répété :" }) + [Environment]::NewLine + [Environment]::NewLine +
                 (($wslSaid | ForEach-Object { '« ' + $_ + ' »' }) -join [Environment]::NewLine) +
                 [Environment]::NewLine + [Environment]::NewLine +
                 "Vigie ne juge pas la configuration de WSL : elle rapporte ce que WSL dit, parce que lui seul " +
                 "sait ce qu'il accepte. Ces lignes ne s'affichent nulle part ailleurs — WSL ne les écrit ni " +
                 "dans le journal de Windows, ni dans un fichier." + [Environment]::NewLine + [Environment]::NewLine +
                 "WSL ne relit sa configuration qu'au démarrage de sa machine virtuelle : interrogé pendant " +
                 "qu'il tourne, il ne répète rien. C'est pourquoi ce qu'il a dit est conservé."
} elseif ($wslSilent) {
    $saidGuide = "WSL n'a pas répondu dans les trente secondes qui lui étaient laissées. L'appel a été coupé, " +
                 "rien n'est resté en attente. Une machine virtuelle froide peut être lente : si cela se " +
                 "reproduit à chaque relevé, c'est que WSL ne répond plus."
}

# A MIXED SCOPE, and this card is what 'mixed' exists for: WSL is installed for the computer, while the default
# distribution is each account's own choice, read in the requester's hive. Every field says which one it speaks of.
if ($saidStatus -eq 'warn' -and $st -eq 'ok') { $st = 'warn' }
New-ModuleObject -Id 'wsl' -Theme 'wsl' -Label 'WSL2' -Scope 'mixed' -Status $st -Fields @(
    New-Field -Key 'installed' -Label 'WSL installé'      -Scope 'machine' -Value $installed -Kind 'bool' -Status $(if ($installed) {'ok'} else {'neutral'}) -Help 'Sous-système Windows pour Linux présent sur la machine.'
    New-Field -Key 'default'   -Label 'Distribution défaut' -Scope 'user' -Value $default -Kind 'text' -Status 'neutral' -Help 'Distribution WSL par défaut, lue dans le registre du compte qui regarde : chaque compte a la sienne.'
    New-Field -Key 'running'   -Label 'Statut' -Scope 'machine' -Value $statutValue -Kind 'text' -Status $statutStat -Help 'État actuel de WSL (Actif si un processus vmmem/wslservice tourne, sinon Inactif).'
    New-Field -Key 'said'      -Label 'Ce que WSL signale' -Scope 'user' -Value $saidValue -Kind 'text' -Status $saidStatus -Guide $saidGuide `
        -Help "Les avertissements que WSL imprime quand on lui parle. Il ne les écrit nulle part ailleurs : sans cette ligne, ils ne sont vus que par celui qui tape la commande."
    New-Field -Key 'vmMemory'  -Label 'Mémoire de la machine virtuelle' -Scope 'machine' -Value $vmValue -Kind 'text' -Status $vmStatus -Guide $vmGuide -Reason $vmReason `
        -FixAction $(if ($vmStatus -eq 'warn' -and $running) { 'wsl-shutdown' } else { $null }) `
        -Help "Mémoire vive réellement occupée par la machine virtuelle qui fait tourner les distributions Linux, cache de fichiers de Linux compris, puis la mémoire qu'elle s'est réservée, et la borne réglée dans .wslconfig."
) -Actions $wslActions
