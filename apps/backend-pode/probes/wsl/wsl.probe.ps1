# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    Sonde : WSL2. LECTURE SEULE. N'appelle PAS wsl.exe (risque de blocage) :
    lit le registre + les processus. Rapide et sans figeage.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$installed = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
$default = '(aucune)'
# Les distributions WSL sont installees PAR UTILISATEUR. Le serveur tourne sous le compte
# de service : la ruche ambiante serait la sienne, et il n'a jamais installe WSL. On lit
# donc la ruche du DEMANDEUR, et a defaut celles des utilisateurs connectes (D113).
$wslHives = @()
$requester = Get-RequesterAccount
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
# the card said "Actif", nothing more. The process is read directly (0.02 s), its private memory as on the Resources
# card, so the two figures agree.
$fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
$vmBytes = [double]((@(Get-Process -Name 'vmmemWSL' -ErrorAction SilentlyContinue) | Measure-Object PrivateMemorySize64 -Sum).Sum)
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
$vmValue = if ($vmBytes) { ($vmBytes / 1GB).ToString('N1', $fr) + ' Go (' + $vmPct + ' % de la mémoire vive)' } else { 'Aucune : machine virtuelle arrêtée' }
if ($requester) { $vmValue += if ($bound) { ' · bornée à ' + $bound } else { ' · non bornée' } }
$vmGuide = $null
$vmReason = $null
if ($vmStatus -eq 'warn') {
    $suggestGb = [math]::Max(4, [math]::Round($physicalBytes / 1GB / 4))
    $vmReason = 'La machine virtuelle de WSL occupe ' + ($vmBytes / 1GB).ToString('N1', $fr) + ' Go, ' + $vmPct + ' % de la mémoire vive'
    $vmGuide = $vmReason + '. Linux garde en cache ce qu''il a lu, et WSL ne rend cette mémoire à Windows que lentement.' + [Environment]::NewLine + [Environment]::NewLine +
               $(if ($bound) { "Elle est bornée à $bound dans $wslConfigPath. Pour la réduire, y abaisser la ligne « memory= » de la section [wsl2], par exemple :" }
                 else { "Rien ne la borne : sans réglage, WSL peut prendre jusqu'à la moitié de la mémoire vive. Pour la borner soi-même, ouvrir le fichier $wslConfigPath (le créer s'il n'existe pas) et y écrire :" }) +
               [Environment]::NewLine + "[wsl2]" + [Environment]::NewLine + "memory=$($suggestGb)GB" + [Environment]::NewLine + [Environment]::NewLine +
               $(if ($reclaim -and $reclaim -notmatch '^(?i)dropcache$') {
                   "Le même fichier règle, dans la section [experimental], « autoMemoryReclaim=$reclaim » : avec « gradual », Linux rend son cache lentement ; avec « disabled », jamais. « dropCache », la valeur par défaut selon Microsoft, le rend aussitôt." + [Environment]::NewLine + [Environment]::NewLine
               } else { '' }) +
               "Le réglage s'applique au prochain démarrage de WSL : le bouton « Arrêter » ci-dessous l'arrête, comme « wsl --shutdown » ; ce qui tourne sous Linux est coupé."
}

# =============================================================================
# GRAVITE DE L'ETAT "INACTIF" - decision produit, UNE SEULE LIGNE A CHANGER.
# Le champ ET la carte en derivent : ils ne peuvent plus se contredire.
#   'error'   -> rouge  : WSL inactif est signale franchement   (choix actuel, D20)
#   'warn'    -> orange : a surveiller, sans alarmer
#   'neutral' -> gris   : etat normal, aucune alerte
# =============================================================================
$inactiveSeverity = 'error'

# Statut lisible + colore (Actif/Inactif) plutot qu'un simple Oui/Non.
$statutValue = if ($running) { 'Actif' } else { 'Inactif' }
$statutStat  = if ($running) { 'ok' } else { $inactiveSeverity }

# La carte porte le MEME jugement que le champ : une seule source de verite.
# WSL absent reste neutre : on ne reproche pas a la machine de ne pas l'avoir installe.
$st = if (-not $installed) { 'neutral' } elseif ($running -and $vmStatus -eq 'warn') { 'warn' } elseif ($running) { 'ok' } else { $inactiveSeverity }

# Trio start/restart/stop : uniquement les boutons pertinents selon l'etat.
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

New-ModuleObject -Id 'wsl' -Theme 'wsl' -Label 'WSL2' -Status $st -Fields @(
    New-Field -Key 'installed' -Label 'WSL installé'      -Value $installed -Kind 'bool' -Status $(if ($installed) {'ok'} else {'neutral'}) -Help 'Sous-système Windows pour Linux présent sur la machine.'
    New-Field -Key 'default'   -Label 'Distribution défaut' -Value $default -Kind 'text' -Status 'neutral' -Help 'Distribution WSL par défaut (lue dans le registre).'
    New-Field -Key 'running'   -Label 'Statut' -Value $statutValue -Kind 'text' -Status $statutStat -Help 'État actuel de WSL (Actif si un processus vmmem/wslservice tourne, sinon Inactif).'
    New-Field -Key 'vmMemory'  -Label 'Mémoire de la machine virtuelle' -Value $vmValue -Kind 'text' -Status $vmStatus -Guide $vmGuide -Reason $vmReason `
        -FixAction $(if ($vmStatus -eq 'warn' -and $running) { 'wsl-shutdown' } else { $null }) `
        -Help "Mémoire que prend la machine virtuelle qui fait tourner les distributions Linux, et la borne réglée dans .wslconfig."
) -Actions $wslActions
