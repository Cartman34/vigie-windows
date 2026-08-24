<#
    common.ps1 - Bibliotheque partagee du backend. Aucune dependance a Pode.
    Fabriques d'objets (contrat), config, jeton, agregation des sondes (avec
    journalisation par sonde), execution des actions, utilitaires.
#>

function Get-BackendRoot { Split-Path $PSScriptRoot -Parent }

# --- Reperes de l'arborescence ------------------------------------------------
# Le depot contient PLUSIEURS apps (apps/backend, apps/frontend, apps/tray,
# apps/atelier) plus scripts/ et docs/. Ces reperes sont calcules ICI et nulle
# part ailleurs : aucun script ne doit recomposer un chemin inter-apps a la main.
function Get-RepoRoot { Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent }
function Get-AppsRoot { Split-Path (Get-BackendRoot) -Parent }
# Les noms de dossiers d'apps portent leur TECHNO : ce sont des implementations
# remplacables (principe n.1). Ils ne sont ecrits QU'ICI ; tout le code passe par
# Get-AppPath. Seul le bootstrap fait exception (voir la note plus bas).
function Get-AppPath {
    param([Parameter(Mandatory)][ValidateSet('backend','frontend','tray','atelier')][string]$Role)
    $folder = switch ($Role) {
        'backend'  { 'backend-pode' }    # PowerShell + Pode
        'frontend' { 'frontend-web' }    # HTML/CSS/JS, sans framework ni build
        'tray'     { 'tray' }            # pas de suffixe : n'implemente aucun contrat
        'atelier'  { 'atelier' }         # idem
    }
    Join-Path (Get-AppsRoot) $folder
}

# NOTE sur le bootstrap : un script qui doit CHARGER cette bibliotheque ne peut pas
# encore appeler Get-AppPath. Le nom du dossier backend y figure donc en clair
# (tray.ps1, scripts/*.ps1). C'est inevitable : il faut savoir ou est la bibliotheque
# avant de pouvoir s'en servir. Ces lignes sont signalees par un commentaire.

# --- Helpers partages (regle : une fonctionnalite = un seul code) -----------

# Le processus courant est-il eleve (administrateur) ?
function Test-Elevated {
    try {
        return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# Execute une commande native en traitant sortie ET code de retour (regle :
# toujours traiter erreurs/affichages/codes de retour). Renvoie un objet uniforme.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @())
    $out = & $File @Arguments 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{ Ok = ($code -eq 0); ExitCode = $code; Output = (($out | Out-String).TrimEnd()) }
}

# Fusionne des cles dans un fichier JSON d'etat (lecture-fusion-ecriture ATOMIQUE),
# serialise par un mutex nomme derive du fichier : plusieurs ecrivains (actions,
# workers detaches) ne s'ecrasent pas entre eux. Regle : un seul code pour ecrire
# les fichiers de var/cache (netmeasure.json, pkgupdates.json, ...).
function Update-StateJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][hashtable]$Set)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $leaf = (Split-Path $Path -Leaf) -replace '[^A-Za-z0-9]', '_'
    $mx = $null; $held = $false
    try {
        $mx = New-Object System.Threading.Mutex($false, "Local\VigieState_$leaf")
        try { $held = $mx.WaitOne(5000) }
        catch [System.Threading.AbandonedMutexException] { $held = $true }
        catch { $held = $false }
        $data = @{}
        if (Test-Path $Path) {
            try { $j = Get-Content $Path -Raw | ConvertFrom-Json; foreach ($pp in $j.PSObject.Properties) { $data[$pp.Name] = $pp.Value } } catch { }
        }
        foreach ($k in $Set.Keys) { $data[$k] = $Set[$k] }
        $tmp = "$Path.tmp"
        ($data | ConvertTo-Json -Depth 8) | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $Path -Force
        return $data
    } finally {
        if ($held -and $mx) { try { $mx.ReleaseMutex() } catch { } }
        if ($mx) { try { $mx.Dispose() } catch { } }
    }
}

# Invalide (supprime) des entrees du cache d'etat : les sondes citees seront
# recalculees au prochain /state. Code unique (reutilise par Invoke-ActionById
# ET les workers detaches). Best-effort, ecriture atomique.
function Remove-ProbeCache {
    param([Parameter(Mandatory)][string[]]$Names, [string]$Backend = (Get-BackendRoot))
    $cacheFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
    if (-not (Test-Path $cacheFile)) { return }
    try {
        $obj = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $ht = @{}
        foreach ($pp in $obj.PSObject.Properties) { $ht[$pp.Name] = $pp.Value }
        $changed = $false
        foreach ($k in $Names) { if ($ht.ContainsKey($k)) { $ht.Remove($k); $changed = $true } }
        if ($changed) {
            $tmp = "$cacheFile.tmp"
            ($ht | ConvertTo-Json -Depth 25) | Out-File -FilePath $tmp -Encoding UTF8
            Move-Item -Path $tmp -Destination $cacheFile -Force
        }
    } catch { }
}

# --- Machinerie Windows Update : LE catalogue ------------------------------------
# Chemins, comptes et taches du verrouillage, definis UNE SEULE FOIS (D15). La sonde,
# la lecture d'etat, la pose du verrou et l'audit y puisent tous : ces listes etaient
# auparavant recopiees dans la sonde, dans le helper de lecture et dans un script
# EXTERIEUR au depot -- trois copies qui ne pouvaient que diverger.
function Get-UpdateTaskCatalog {
    [ordered]@{
        # Strategie : NoAutoUpdate=1 coupe les mises a jour automatiques.
        RegAu    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
        RegWu    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        RegUx    = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        # Comptes vises, en SID : jamais par nom, qui est traduit selon la langue de Windows.
        SidSystem = 'S-1-5-18'
        SidAdmins = 'S-1-5-32-544'
        # Dossiers de taches sur DISQUE : c'est la que se pose le verrou de permissions.
        Dirs = @(
            "$env:windir\System32\Tasks\Microsoft\Windows\UpdateOrchestrator"
            "$env:windir\System32\Tasks\Microsoft\Windows\WindowsUpdate"
            "$env:windir\System32\Tasks\Microsoft\Windows\InstallService"
            "$env:windir\System32\Tasks\Microsoft\Windows\WaaSMedic"
        )
        # Memes dossiers vus par le PLANIFICATEUR (lecture d'etat).
        TaskPaths = @(
            '\Microsoft\Windows\UpdateOrchestrator\'
            '\Microsoft\Windows\WindowsUpdate\'
            '\Microsoft\Windows\InstallService\'
            '\Microsoft\Windows\WaaSMedic\'
        )
        # Les SEULES taches que Windows laisse desactiver. Les autres sont protegees :
        # tenter de les basculer echoue, c'est normal et ce n'est pas une panne.
        Managed = @(
            [pscustomobject]@{ Path = '\Microsoft\Windows\WindowsUpdate\';  Name = 'Scheduled Start' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'RestoreDevice' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'ScanForUpdates' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'ScanForUpdatesAsUser' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'SmartRetry' }
        )
        # Services de la machinerie de MAJ (WaaSMedicSvc est le « reparateur » qui defait
        # les reglages : son etat explique bien des retours en arriere inexpliques).
        Services = @('wuauserv','UsoSvc','WaaSMedicSvc','BITS','DoSvc','InstallService')
    }
}

# Le verrou ACL (refus d'ecriture a SYSTEM) est-il pose sur le dossier de taches ?
# Comparaison par SID (S-1-5-18), independante de la langue et de la traduction du compte.
function Test-UpdateTasksAclLock {
    param([string]$Path = (Get-UpdateTaskCatalog).Dirs[0])
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    # icacls est la source autoritaire (c'est aussi ce que pose update-mode.ps1). Le seul
    # refus applique est celui de SYSTEM : une entree (DENY) => verrou pose. "(DENY)" n'est
    # PAS localise par icacls -> test fiable quelle que soit la langue de Windows.
    try {
        $r = Invoke-Native -File 'icacls.exe' -Arguments @($Path)
        if ($r.Output -match '\(DENY\)') { return $true }
    } catch { }
    # Repli .NET (par SID) si icacls indisponible.
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $sysSid = New-Object System.Security.Principal.SecurityIdentifier(
            [System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        foreach ($ace in $acl.Access) {
            if ($ace.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Deny) { continue }
            try { if (($ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])) -eq $sysSid) { return $true } } catch { }
        }
    } catch { }
    return $false
}

# Etat REEL et complet du verrouillage Windows Update. LECTURE SEULE.
#
# C'est la seule lecture d'etat du sujet : la sonde l'affiche, les actions s'en servent
# pour dire ce qui a ete OBSERVE apres avoir agi (D43), l'audit la reprend telle quelle.
#
# `locked` = verrou COMPLET : mises a jour automatiques coupees ET verrou de permissions
# pose. Les deux moities repondent a des questions differentes et ne se confondent pas.
function Get-UpdateLockState {
    $cat = Get-UpdateTaskCatalog
    $noAuto = $null
    try { $noAuto = (Get-ItemProperty -Path $cat.RegAu -Name NoAutoUpdate -ErrorAction SilentlyContinue).NoAutoUpdate } catch { }
    $taches = @()
    foreach ($p in $cat.TaskPaths) {
        # -ErrorAction Ignore et non SilentlyContinue : un dossier vide ou dont l'acces est
        # refuse (c'est precisement l'effet du verrou) fait lever une erreur que
        # SilentlyContinue masque a l'ecran mais empile quand meme dans $Error. L'absence
        # est ici une information attendue, rapportee plus bas, pas un incident a collecter.
        foreach ($t in (Get-ScheduledTask -TaskPath $p -ErrorAction Ignore)) {
            $taches += [pscustomobject]@{ path = "$($t.TaskPath)"; name = "$($t.TaskName)"; state = "$($t.State)" }
        }
    }
    $acl = Test-UpdateTasksAclLock
    $autoOff = ($noAuto -eq 1)
    [ordered]@{
        elevated       = (Test-Elevated)
        noAutoUpdate   = $noAuto
        autoUpdatesOff = $autoOff
        aclLock        = $acl
        locked         = ($autoOff -and $acl)
        tasks          = @($taches)
        tasksDisabled  = @($taches | Where-Object { $_.state -eq 'Disabled' }).Count
        tasksReady     = @($taches | Where-Object { $_.state -ne 'Disabled' }).Count
    }
}

# Ecriture NATIVE du verrou : ni script externe, ni dependance hors depot.
# Interne -- l'unique porte d'entree reste Set-UpdateLock, qui constate le resultat.
#
# Idempotence : chaque geste est deja ecrit pour supporter d'etre rejoue. Poser un refus
# deja pose, desactiver une tache deja desactivee ou reecrire NoAutoUpdate a la meme
# valeur ne change rien et ne doit RIEN signaler d'anormal.
function Invoke-UpdateLockNative {
    param(
        [Parameter(Mandatory)][ValidateSet('pose','leve')][string]$Etat,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = Get-UpdateTaskCatalog
    $sys = '*' + $cat.SidSystem
    $adm = '*' + $cat.SidAdmins
    $trace = New-Object System.Collections.Generic.List[string]
    $noter = { param($m) $trace.Add([string]$m) }

    # 1) Strategie : couper ou rendre les mises a jour automatiques.
    # La cle de strategie n'existe PAS sur une machine neuve : l'ecriture y echouait
    # silencieusement. On la cree -- c'est ce qui fait la difference entre « ca marche
    # chez moi » et « ca marche sur une installation propre ».
    $valeur = if ($Etat -eq 'pose') { 1 } else { 0 }
    try {
        if (-not (Test-Path -LiteralPath $cat.RegAu)) { New-Item -Path $cat.RegAu -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $cat.RegAu -Name 'NoAutoUpdate' -Value $valeur -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        & $noter "NoAutoUpdate = $valeur"
    } catch {
        & $noter "NoAutoUpdate : ECHEC -- $($_.Exception.Message)"
    }

    # 2) Rendre les dossiers ecrivables AVANT toute autre chose. Meme pour poser le
    # verrou : on ne peut pas desactiver une tache dans un dossier dont l'acces est
    # refuse. Retirer un refus absent est sans effet -- donc rejouable.
    foreach ($d in $cat.Dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $r1 = Invoke-Native -File 'icacls.exe' -Arguments @($d, '/remove:d', $sys, '/t', '/c', '/q')
        $r2 = Invoke-Native -File 'icacls.exe' -Arguments @($d, '/grant', ($sys + ':(OI)(CI)F'), '/t', '/c', '/q')
        & $noter ("deverrouillage " + (Split-Path $d -Leaf) + " : remove:d=" + $r1.ExitCode + " grant=" + $r2.ExitCode)
    }

    # 3) Taches gerees : desactiver (pose) ou reactiver (levee). Les autres taches du
    # dossier sont protegees par Windows et ne se basculent pas -- ce n'est pas un echec.
    foreach ($m in $cat.Managed) {
        try {
            if ($Etat -eq 'pose') { Disable-ScheduledTask -TaskName $m.Name -TaskPath $m.Path -ErrorAction Stop | Out-Null }
            else                  { Enable-ScheduledTask  -TaskName $m.Name -TaskPath $m.Path -ErrorAction Stop | Out-Null }
            & $noter ("tache " + $m.Name + " -> " + $(if ($Etat -eq 'pose') { 'desactivee' } else { 'activee' }))
        } catch {
            # Tache absente selon l'edition de Windows, ou protegee : on le note, on continue.
            & $noter ("tache " + $m.Name + " : ignoree -- " + $_.Exception.Message)
        }
    }

    if ($Etat -eq 'pose') {
        # 4) Verrou de permissions : prendre la main sur les dossiers, garder l'acces aux
        # administrateurs, puis REFUSER a SYSTEM la creation et la modification. C'est ce
        # refus qui empeche Windows de recreer ses taches et de forcer un redemarrage.
        foreach ($d in $cat.Dirs) {
            if (-not (Test-Path -LiteralPath $d)) { continue }
            $nom = Split-Path $d -Leaf
            $rt = Invoke-Native -File 'takeown.exe' -Arguments @('/f', $d, '/r', '/a', '/d', 'O')
            $rg = Invoke-Native -File 'icacls.exe'  -Arguments @($d, '/grant', ($adm + ':(OI)(CI)F'), '/t', '/c')
            $rd = Invoke-Native -File 'icacls.exe'  -Arguments @($d, '/deny',  ($sys + ':(OI)(CI)(WD,AD,DC)'), '/t', '/c')
            & $noter ("verrouillage $nom : takeown=" + $rt.ExitCode + " grant=" + $rg.ExitCode + " deny=" + $rd.ExitCode)
            if (-not $rd.Ok) { & $noter ("  detail deny $nom : " + (($rd.Output -split "`r?`n" | Select-Object -Last 3) -join ' | ')) }
        }
    } else {
        # 4bis) Levee : prevenir Windows que la strategie a change, sinon l'interface de
        # Windows Update continue d'afficher l'ancien reglage jusqu'a son propre cycle.
        $uso = Join-Path $env:windir 'System32\UsoClient.exe'
        if (Test-Path -LiteralPath $uso) {
            $ru = Invoke-Native -File $uso -Arguments @('RefreshSettings')
            & $noter ("UsoClient RefreshSettings : exit=" + $ru.ExitCode)
        }
    }
    return @($trace)
}

# Pose ou leve le verrou des mises a jour. UNIQUE porte d'entree en ECRITURE (D15) :
# les actions update-mode-on / update-mode-off, l'installation et l'analyse des MAJ
# passent toutes par ici. Sans cela, chaque appelant recopierait la manoeuvre.
#
# Implementation NATIVE : le verrouillage est une capacite du produit, pas un service
# rendu par un script exterieur au depot. Un outillage `ToolsPath` fourni et portant
# `update-mode.ps1` reste PREFERE quand il existe (installations historiques), mais son
# absence n'empeche plus rien.
#
# Renvoie $true si l'etat demande est REELLEMENT obtenu, relu APRES coup et jamais deduit
# du fait qu'aucune commande n'a leve d'erreur (D43).
function Set-UpdateLock {
    param(
        [Parameter(Mandatory)][ValidateSet('pose','leve')][string]$Etat,
        [string]$Backend = (Get-BackendRoot)
    )
    # Sans elevation, icacls et takeown echouent en silence et on croirait avoir verrouille.
    # On refuse AVANT d'agir : l'appelant a un etat faux a annoncer, pas une demi-mesure.
    if (-not (Test-Elevated)) {
        try { Write-Log -Backend $Backend -Name 'updatelock' -Level 'WARN' -Message "$Etat : refuse, le serveur n'est pas administrateur." } catch { }
        return $false
    }
    $voie = 'native'
    $trace = @()
    $script = $null
    $tools = Get-ToolsPath -Backend $Backend
    if ($tools) {
        $candidat = Join-Path $tools 'update-mode.ps1'
        if (Test-Path -LiteralPath $candidat) { $script = $candidat; $voie = 'outillage' }
    }
    try {
        if ($script) {
            if ($Etat -eq 'pose') { & $script -Off *> $null } else { & $script -On *> $null }
        } else {
            $trace = Invoke-UpdateLockNative -Etat $Etat -Backend $Backend
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'updatelock' -Level 'ERROR' -Message "$Etat ($voie) : $($_.Exception.Message)" } catch { }
    }
    # CONSTAT : on relit l'etat reel, c'est lui qui fait foi.
    $etatReel = Get-UpdateLockState
    $obtenu = if ($Etat -eq 'pose') { $etatReel.aclLock } else { -not $etatReel.aclLock }
    try {
        foreach ($t in $trace) { Write-Log -Backend $Backend -Name 'updatelock' -Message "  $t" }
        Write-Log -Backend $Backend -Name 'updatelock' -Message (
            "$Etat ($voie) : obtenu=$obtenu verrouACL=$($etatReel.aclLock) NoAutoUpdate=$($etatReel.noAutoUpdate) tachesDesactivees=$($etatReel.tasksDisabled)")
    } catch { }
    return [bool]$obtenu
}

# --- Securite de la virtualisation (VBS / HVCI) ---------------------------------
# LE catalogue du sujet, defini une seule fois (D15) : cles de registre, noms de valeurs
# et libelles. La sonde, la lecture d'etat et la bascule y puisent tous.
#
# Ce qui distingue ce sujet du verrou Windows Update : une valeur ecrite ici ne prend
# effet qu'au REDEMARRAGE. Il y a donc DEUX etats a ne jamais confondre --
#   `configured` : ce que demande le registre (ce qu'on ecrit, verifiable tout de suite) ;
#   `running`    : ce que Windows execute reellement (ne bougera qu'apres un redemarrage).
function Get-DeviceGuardCatalog {
    $racine = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    [ordered]@{
        Root      = $racine
        RootReg   = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard'   # forme attendue par reg.exe
        Features  = [ordered]@{
            vbs  = [pscustomobject]@{
                Key = $racine; Name = 'EnableVirtualizationBasedSecurity'
                Label = 'Sécurité par virtualisation (VBS)'; Court = 'VBS'
            }
            hvci = [pscustomobject]@{
                Key = "$racine\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = 'Enabled'
                Label = 'Intégrité mémoire (HVCI)'; Court = 'intégrité mémoire'
            }
        }
    }
}

# Marqueur des bascules DEMANDEES et pas encore effectives (var/cache). Il sert a deux
# choses : savoir quoi afficher (« demandé, effectif au redémarrage ») et sur quelle
# valeur basculer quand on reclique avant d'avoir redemarre.
function Get-DeviceGuardMarkerPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'deviceguard.json'
}

# Etat REEL et complet de VBS / HVCI. LECTURE SEULE.
#
# Pour chaque fonction :
#   configured : valeur du registre (0/1), $null si la valeur n'existe pas
#   running    : ce que Windows execute maintenant (Win32_DeviceGuard)
#   requested  : ce que Vigie a demande et qui attend un redemarrage ($null sinon)
#   pending    : une demande de Vigie n'est pas encore effective
#   effective  : l'etat a AFFICHER et celui sur lequel une bascule s'appuie -- la demande
#                en attente si elle existe, sinon ce qui tourne. Basculer depuis `running`
#                alors qu'une demande attend ferait revenir en arriere sans le dire.
function Get-DeviceGuardState {
    param([string]$Backend = (Get-BackendRoot))
    $cat = Get-DeviceGuardCatalog
    $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $running = @{
        vbs  = [bool]($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2)
        hvci = [bool]($dg -and ($dg.SecurityServicesRunning -contains 2))
    }
    $marque = @{}
    try {
        $f = Get-DeviceGuardMarkerPath -Backend $Backend
        if (Test-Path -LiteralPath $f) {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $marque[$p.Name] = $p.Value }
        }
    } catch { }

    $etat = [ordered]@{ elevated = (Test-Elevated); vbsStatus = $(if ($dg) { [int]$dg.VirtualizationBasedSecurityStatus } else { $null }) }
    foreach ($id in $cat.Features.Keys) {
        $f = $cat.Features[$id]
        $cfg = $null
        try {
            $v = (Get-ItemProperty -LiteralPath $f.Key -Name $f.Name -ErrorAction SilentlyContinue).$($f.Name)
            if ($null -ne $v) { $cfg = [int]$v }
        } catch { }
        $dem = $null
        try { if ($marque[$id] -and $null -ne $marque[$id].requested) { $dem = [int]$marque[$id].requested } } catch { }
        # Une demande qui correspond deja a ce qui tourne n'est plus en attente : le
        # marqueur se perime tout seul au redemarrage, sans delai arbitraire a regler.
        $enAttente = ($null -ne $dem -and [bool]$dem -ne $running[$id])
        $etat[$id] = [ordered]@{
            label      = $f.Label
            court      = $f.Court
            configured = $cfg
            running    = $running[$id]
            requested  = $(if ($enAttente) { $dem } else { $null })
            pending    = $enAttente
            effective  = $(if ($enAttente) { [bool]$dem } else { $running[$id] })
        }
    }
    $etat['pending'] = ($etat.vbs.pending -or $etat.hvci.pending)
    $etat
}

# Sauvegarde de la cle DeviceGuard AVANT toute ecriture, dans var/log.
# Un reglage de demarrage se defait mal a la main : on garde de quoi revenir en arriere.
function Backup-DeviceGuardKey {
    param([string]$Backend = (Get-BackendRoot))
    $cat = Get-DeviceGuardCatalog
    $f = Join-Path (Get-LogDir -Backend $Backend) ('deviceguard_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.reg')
    try {
        $r = Invoke-Native -File 'reg.exe' -Arguments @('export', $cat.RootReg, $f, '/y')
        # D43 : la sauvegarde existe quand le FICHIER est la, pas quand l'appel est passe.
        if ((Test-Path -LiteralPath $f) -and $r.Ok) { return $f }
    } catch { }
    return $null
}

# Ecrit la valeur d'UNE fonction. UNIQUE porte d'entree en ECRITURE (D15).
#
# Renvoie un objet (et non un booleen comme Set-UpdateLock) parce qu'il n'y a rien a
# preserver ici : aucun appelant existant, et « ecrit » ne suffit pas a raconter ce qui
# s'est passe -- il faut distinguer « deja a cette valeur », « ecrit, attend le
# redemarrage » et « ecrit mais toujours actif » (valeur imposee par l'UEFI ou une
# strategie). Le resultat est RELU dans le registre, jamais suppose (D43).
function Set-DeviceGuardFeature {
    param(
        [Parameter(Mandatory)][ValidateSet('vbs','hvci')][string]$Feature,
        [Parameter(Mandatory)][bool]$Enable,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = Get-DeviceGuardCatalog
    if (-not (Test-Elevated)) {
        try { Write-Log -Backend $Backend -Name 'deviceguard' -Level 'WARN' -Message "$Feature : refuse, le serveur n'est pas administrateur." } catch { }
        return @{ ok = $false; elevated = $false }
    }
    $cible = [int][bool]$Enable
    $avant = Get-DeviceGuardState -Backend $Backend
    $sauvegarde = Backup-DeviceGuardKey -Backend $Backend

    # Les valeurs a poser. HVCI ne peut PAS tourner sans VBS : desactiver VBS en laissant
    # l'integrite memoire demandee laisse une configuration incoherente, que Windows
    # resout parfois en rallumant VBS. On coupe donc les deux -- et on le DIT.
    # L'inverse n'est pas vrai : activer VBS n'active pas l'integrite memoire dans le dos
    # de l'utilisateur, c'est une decision distincte avec ses propres contreparties.
    $aEcrire = @( [pscustomobject]@{ Id = $Feature; Valeur = $cible } )
    $hvciCoupeAussi = $false
    if ($Feature -eq 'vbs' -and $cible -eq 0) {
        $aEcrire += [pscustomobject]@{ Id = 'hvci'; Valeur = 0 }
        $hvciCoupeAussi = $true
    }

    $erreurs = @()
    foreach ($e in $aEcrire) {
        $f = $cat.Features[$e.Id]
        try {
            # Idempotent : New-Item -Force sur une cle existante ne l'efface pas, et
            # reecrire la meme valeur est sans effet. Rejouer la bascule ne casse rien.
            if (-not (Test-Path -LiteralPath $f.Key)) { New-Item -Path $f.Key -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -Path $f.Key -Name $f.Name -Value $e.Valeur -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        } catch {
            $erreurs += "$($e.Id) : $($_.Exception.Message)"
        }
    }

    # Marqueur : ce que Vigie a demande. Il sert a proposer le redemarrage et a savoir sur
    # quelle valeur rebasculer si l'utilisateur reclique avant d'avoir redemarre.
    try {
        $set = @{}
        foreach ($e in $aEcrire) { $set[$e.Id] = @{ requested = $e.Valeur; at = (Get-Date).ToUniversalTime().ToString('o') } }
        Update-StateJson -Path (Get-DeviceGuardMarkerPath -Backend $Backend) -Set $set | Out-Null
    } catch { }

    # CONSTAT : on relit le REGISTRE, seul etat qui puisse avoir change maintenant.
    # Relire `running` pour juger serait un faux echec garanti -- il ne bougera qu'au
    # redemarrage. C'est la difference a ne pas rater avec le verrou Windows Update.
    $apres = Get-DeviceGuardState -Backend $Backend
    $ecrit = ($apres[$Feature].configured -eq $cible)
    try {
        Write-Log -Backend $Backend -Name 'deviceguard' -Message (
            "$Feature -> $cible : ecrit=$ecrit configAvant=$($avant[$Feature].configured) configApres=$($apres[$Feature].configured) " +
            "actif=$($apres[$Feature].running) hvciCoupeAussi=$hvciCoupeAussi sauvegarde=$sauvegarde" +
            $(if ($erreurs.Count) { ' erreurs=' + ($erreurs -join ' | ') } else { '' }))
    } catch { }

    @{
        ok             = $ecrit
        elevated       = $true
        feature        = $Feature
        value          = $cible
        already        = ($avant[$Feature].configured -eq $cible)
        running        = $apres[$Feature].running
        rebootNeeded   = ($apres[$Feature].running -ne [bool]$cible)
        hvciCoupeAussi = $hvciCoupeAussi
        backup         = $sauvegarde
        errors         = @($erreurs)
        state          = $apres
    }
}

# Bascule d'UNE fonction, du point de vue de l'utilisateur : on inverse ce que la carte
# AFFICHE (`effective`), pas ce qui tourne. Recliquer avant d'avoir redemarre revient
# donc bien a l'etat de depart, au lieu de reecrire deux fois la meme valeur.
#
# Renvoie directement @{ message; result } : les deux actions ne different que par le nom
# de la fonction, il n'y a aucune raison d'ecrire ce compte rendu deux fois (D15).
function Invoke-DeviceGuardToggle {
    param(
        [Parameter(Mandatory)][ValidateSet('vbs','hvci')][string]$Feature,
        [string]$Backend = (Get-BackendRoot)
    )
    $inv = @('vbs.probe.ps1')
    $etat = Get-DeviceGuardState -Backend $Backend
    $nom  = $etat[$Feature].court

    if (-not $etat.elevated) {
        return @{
            message = "Le serveur de Vigie n'est pas administrateur : la bascule $nom est impossible. Relancez Vigie en administrateur (l'invite UAC s'affichera)."
            result  = @{ ok = $false }
        }
    }

    $cible = -not $etat[$Feature].effective
    $r = Set-DeviceGuardFeature -Feature $Feature -Enable $cible -Backend $Backend
    $verbe = if ($cible) { 'activée' } else { 'désactivée' }

    if (-not $r.ok) {
        $det = if (@($r.errors).Count) { ' ' + (@($r.errors) -join ' ; ') } else { '' }
        return @{
            message = "La valeur de $nom n'a pas pu être écrite dans le registre.$det"
            result  = @{ ok = $false; invalidate = $inv }
        }
    }

    $bonus = if ($r.hvciCoupeAussi) { " L'intégrité mémoire est coupée avec elle : elle ne peut pas fonctionner sans VBS." } else { '' }
    $garde = if ($r.backup) { " Sauvegarde du registre : $($r.backup)." } else { " Attention : la sauvegarde du registre n'a pas pu être écrite." }

    if (-not $r.rebootNeeded) {
        # Valeur ecrite ET deja conforme a ce qui tourne : rien a attendre.
        return @{
            message = "$nom déjà $verbe : la configuration et l'état actif concordent, aucun redémarrage nécessaire.$bonus"
            result  = @{ ok = $true; invalidate = $inv }
        }
    }
    $rappel = if ($r.already) { " Cette valeur était déjà demandée : si elle ne s'applique toujours pas après un redémarrage, elle est imposée par l'UEFI ou par une stratégie d'entreprise." } else { '' }
    @{
        message = "$nom sera $verbe au prochain redémarrage de Windows — la demande est écrite, elle ne prend effet qu'au démarrage.$bonus$rappel$garde"
        result  = @{ ok = $true; invalidate = $inv }
    }
}

# Un redemarrage differe est-il en cours (et donc encore annulable) ?
# Borne dans le TEMPS : un compte a rebours expire n'est plus annulable -- soit la machine
# a redemarre, soit il a ete annule ailleurs. Le drapeau seul resterait vrai pour toujours.
# Partage par les cartes qui proposent un redemarrage (Windows Update, virtualisation) :
# ce calcul vivait dans une seule sonde et allait etre recopie dans une seconde (D15).
function Test-RestartCountdown {
    param([string]$Backend = (Get-BackendRoot))
    $f = Get-VarPath -Backend $Backend -Kind 'cache' -File 'restart.json'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    try {
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        if (-not ($j.pending -and $j.at)) { return $false }
        $delaiPrevu = if ($j.delay) { [int]$j.delay } else { 60 }
        $ecoule = ([datetime]::UtcNow - (ConvertTo-UtcDate $j.at)).TotalSeconds
        return ($ecoule -ge 0 -and $ecoule -lt ($delaiPrevu + 15))
    } catch { return $false }
}

# Audit complet de la machinerie Windows Update. LECTURE SEULE, ne modifie rien.
#
# Reimplemente dans le depot : l'audit servait a comprendre pourquoi un verrouillage ne
# tient pas (service reparateur, strategie ecrasee, tache recreee). Une fonction de
# diagnostic qui exige un outillage absent ne sert justement plus quand on en a besoin.
#
# Le rapport va dans var/log/ (convention du projet : tout ce que l'app genere vit sous
# var/), en texte pour etre lu et en JSON pour etre repris.
function Invoke-UpdateAudit {
    param([string]$Backend = (Get-BackendRoot))
    $cat    = Get-UpdateTaskCatalog
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir    = Get-LogDir -Backend $Backend
    $txt    = Join-Path $dir "update-audit_$stamp.txt"
    $json   = Join-Path $dir "update-audit_$stamp.json"
    $lignes = New-Object System.Collections.Generic.List[string]
    $rap    = [ordered]@{}
    $L   = { param($s = '') $lignes.Add([string]$s) }
    $Sec = { param($t) & $L ''; & $L ('===== ' + $t + ' =====') }

    $etat = Get-UpdateLockState
    $rap.at       = (Get-Date).ToString('o')
    $rap.elevated = $etat.elevated
    & $L ("Audit Windows Update du " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "  (administrateur = " + $etat.elevated + ")")
    if (-not $etat.elevated) { & $L "ATTENTION : serveur non administrateur -- une partie de l'etat n'est pas lisible." }

    & $Sec 'Verrouillage'
    & $L ("   Mises a jour automatiques coupees : " + $etat.autoUpdatesOff + "   (NoAutoUpdate=" + $etat.noAutoUpdate + ")")
    & $L ("   Verrou de permissions (ACL)       : " + $etat.aclLock)
    & $L ("   Verrou complet                    : " + $etat.locked)
    $rap.lock = @{ autoUpdatesOff = $etat.autoUpdatesOff; noAutoUpdate = $etat.noAutoUpdate
                   aclLock = $etat.aclLock; locked = $etat.locked }

    & $Sec 'Edition et licence'
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        & $L ("   " + $cv.ProductName + "  (EditionID=" + $cv.EditionID + ")  build " + $cv.CurrentBuild + "." + $cv.UBR)
        $rap.edition = @{ product = "$($cv.ProductName)"; editionId = "$($cv.EditionID)"; build = "$($cv.CurrentBuild).$($cv.UBR)" }
    } catch { & $L "   (illisible)" }

    # Les strategies expliquent la plupart des « le verrou n'a pas tenu » : une valeur
    # ecrite ailleurs (GPO, autre outil) ecrase la notre sans rien dire.
    $vider = {
        param($chemin, $titre)
        & $Sec $titre
        $o = [ordered]@{}
        if (-not (Test-Path -LiteralPath $chemin)) { & $L '   (absente)'; return $o }
        $p = Get-ItemProperty -LiteralPath $chemin -ErrorAction SilentlyContinue
        # Une cle qui EXISTE peut rendre $null (aucune valeur, ou lecture refusee sans
        # elevation). Or $null.PSObject.Properties.Name rend un element $null, qui passe le
        # filtre et sert ensuite d'index -- constate : « the array index evaluated to null ».
        # On ecarte donc explicitement le vide, plutot que de supposer une liste de noms.
        if ($null -eq $p) { & $L '   (illisible ou vide)'; return $o }
        $noms = @($p.PSObject.Properties.Name | Where-Object { $_ -and ("$_" -notlike 'PS*') })
        foreach ($n in $noms) { & $L ("   {0,-40} = {1}" -f $n, $p.$n); $o[$n] = $p.$n }
        if (-not $noms.Count) { & $L '   (vide)' }
        return $o
    }
    $rap.policyWindowsUpdate = & $vider $cat.RegWu 'Strategie WindowsUpdate'
    $rap.policyAu            = & $vider $cat.RegAu 'Strategie WindowsUpdate\AU'
    $rap.ux                  = & $vider $cat.RegUx 'Reglages UX (heures actives, notifications)'

    & $Sec 'Redemarrage en attente'
    $enAttente = [ordered]@{}
    $enAttente.CBS_RebootPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $enAttente.WU_RebootRequired = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $enAttente.PendingFileRename = [bool]((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
    foreach ($k in $enAttente.Keys) { & $L ("   {0,-22} = {1}" -f $k, $enAttente[$k]) }
    $rap.pendingReboot = $enAttente

    & $Sec 'Taches planifiees de mise a jour'
    if (-not @($etat.tasks).Count) { & $L '   (aucune lisible -- acces refuse ?)' }
    foreach ($p in $cat.TaskPaths) {
        $lot = @($etat.tasks | Where-Object { $_.path -eq $p })
        & $L ''
        & $L ("[" + $p + "]")
        if (-not $lot.Count) { & $L '   (aucune / acces refuse)'; continue }
        foreach ($t in $lot) { & $L ("   {0,-34} {1}" -f $t.name, $t.state) }
    }
    $rap.tasks = @($etat.tasks)
    $rap.tasksDisabled = $etat.tasksDisabled
    $rap.tasksReady    = $etat.tasksReady

    & $Sec 'Services de mise a jour'
    $svc = @()
    foreach ($n in $cat.Services) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $s) { & $L ("   {0,-16} (absent)" -f $n); continue }
        $dem = ''
        try { $dem = "$((Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue).StartMode)" } catch { }
        & $L ("   {0,-16} statut={1,-10} demarrage={2}" -f $n, $s.Status, $dem)
        $svc += @{ name = $n; status = "$($s.Status)"; start = $dem }
    }
    # WaaSMedicSvc remet volontiers la machinerie en marche : son mode de demarrage lu
    # dans le registre est plus fiable que celui rapporte par le gestionnaire de services.
    try {
        $wm = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -ErrorAction SilentlyContinue).Start
        if ($null -ne $wm) { & $L ("   WaaSMedicSvc Start (registre) = " + $wm + "  (2=automatique, 3=manuel, 4=desactive)"); $rap.waasMedicStart = $wm }
    } catch { }
    $rap.services = $svc

    & $Sec 'Contexte'
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        & $L ("   Dernier demarrage : " + $os.LastBootUpTime)
        $rap.lastBoot = "$($os.LastBootUpTime)"
    } catch { }
    $hf = @()
    try {
        foreach ($h in (Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5)) {
            & $L ("   {0,-12} {1}" -f $h.HotFixID, $h.InstalledOn)
            $hf += @{ id = "$($h.HotFixID)"; installedOn = "$($h.InstalledOn)" }
        }
    } catch { }
    $rap.hotfixes = $hf

    $ecrit = $false
    try {
        ($lignes -join "`r`n") | Out-File -FilePath $txt  -Encoding UTF8
        ($rap | ConvertTo-Json -Depth 8) | Out-File -FilePath $json -Encoding UTF8
        # D43 : le rapport est « ecrit » quand le fichier EXISTE, pas quand l'appel est passe.
        $ecrit = (Test-Path -LiteralPath $txt) -and (Test-Path -LiteralPath $json)
    } catch {
        try { Write-Log -Backend $Backend -Name 'updateaudit' -Level 'ERROR' -Message $_.Exception.Message } catch { }
    }
    return @{ ok = $ecrit; txt = $txt; json = $json; elevated = $etat.elevated; state = $etat; lines = @($lignes) }
}

# --- Taches de fond (regle : une action lente ne bloque jamais la requete) ---
# Lance un script worker dans un pwsh DETACHE, fenetre cachee (aucune console
# visible, pas de restauration d'onglets Terminal). L'executable pwsh est celui
# du processus courant (generique : aucun chemin d'installation code en dur).
# Les parametres sont passes en JSON base64 (robuste au quoting). Renvoie le PID.
function Start-DetachedAction {
    param(
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$ArgsMap = @{},
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-Path -LiteralPath $Script)) { throw "Worker introuvable : $Script" }
    $exe = $null
    try { $exe = (Get-Process -Id $PID).Path } catch { }
    if (-not $exe) { try { $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { } }
    if (-not $exe) { $exe = 'pwsh.exe' }
    $json = ($ArgsMap | ConvertTo-Json -Compress -Depth 6)
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe
    # NB : pas d'argument -WindowStyle (non implemente hors Windows). L'absence de
    # fenetre est garantie par CreateNoWindow + UseShellExecute=$false ci-dessous.
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script`" -Backend `"$Backend`" -ArgsB64 $b64"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = $Backend
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($p) { return $p.Id } else { return $null }
}

# --- Gestionnaires de paquets (source unique : sonde, verif MAJ ET upgrade) --
# Un seul catalogue : id, libelle, args version, args/mode de MAJ, args upgrade.
# upgArgs vide = pas de mise a jour automatique proposee pour ce gestionnaire.
#
# upgOne = args pour mettre a jour UN SEUL paquet, `{pkg}` etant remplace par son
# identifiant. C'est ce qui rend le CHOIX possible : sans upgOne, le gestionnaire ne sait
# que « tout mettre a jour » et l'interface le dit au lieu de laisser croire au contraire.
#
# gui* = interface graphique du gestionnaire, quand elle existe ET qu'elle est installee.
#   guiKind 'uri' -> protocole verifie dans HKEY_CLASSES_ROOT (le Store n'est pas un .exe)
#   guiKind 'exe' -> executable cherche dans le PATH puis dans guiPaths
# Un bouton qui ouvre un logiciel absent est pire que pas de bouton : la presence est
# verifiee a chaque passage de la sonde, jamais supposee.
function Get-PackageManagerCatalog {
    @(
        [pscustomobject]@{ id='winget'; label='winget';       verArgs=@('--version'); updArgs=@('upgrade','--include-unknown','--disable-interactivity','--accept-source-agreements'); updMode='winget';   upgArgs=@('upgrade','--all','--silent','--include-unknown','--disable-interactivity','--accept-source-agreements','--accept-package-agreements')
                           upgOne=@('upgrade','--id','{pkg}','--silent','--disable-interactivity','--accept-source-agreements','--accept-package-agreements')
                           guiKind='uri'; guiTarget='ms-windows-store://downloadsandupdates'; guiProbe='ms-windows-store'; guiLabel='Ouvrir le Microsoft Store'
                           guiHelp="Ouvre la page « Téléchargements et mises à jour » du Microsoft Store, qui partage le catalogue de winget." }
        [pscustomobject]@{ id='choco';  label='Chocolatey';   verArgs=@('--version'); updArgs=@('outdated','-r','--nocolor');   updMode='chocor';   upgArgs=@('upgrade','all','-y')
                           upgOne=@('upgrade','{pkg}','-y')
                           guiKind='exe'; guiTarget='ChocolateyGUI.exe'; guiProbe='ChocolateyGUI'; guiLabel='Ouvrir Chocolatey GUI'
                           guiHelp="Ouvre Chocolatey GUI, l'interface graphique de Chocolatey (paquet « chocolateygui »)." }
        [pscustomobject]@{ id='scoop';  label='Scoop';        verArgs=@('--version'); updArgs=@('status');                      updMode='lines';    upgArgs=@('update','*');  upgOne=@() }
        [pscustomobject]@{ id='npm';    label='npm';          verArgs=@('-v');        updArgs=@('outdated','-g','--json');      updMode='jsonkeys'; upgArgs=@('update','-g'); upgOne=@() }
        [pscustomobject]@{ id='pnpm';   label='pnpm';         verArgs=@('-v');        updArgs=@('outdated','-g');               updMode='lines';    upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='yarn';   label='Yarn';         verArgs=@('-v');        updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='pip';    label='pip (Python)'; verArgs=@('--version'); updArgs=@('list','--outdated','--format=json'); updMode='jsonlist'; upgArgs=@();        upgOne=@('install','-U','{pkg}') }
        [pscustomobject]@{ id='pipx';   label='pipx';         verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='cargo';  label='Cargo (Rust)'; verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='gem';    label='RubyGems';     verArgs=@('--version'); updArgs=@('outdated');                    updMode='lines';    upgArgs=@('update');      upgOne=@() }
        [pscustomobject]@{ id='dotnet'; label='.NET SDK';     verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
    )
}

# Interface graphique REELLEMENT presente pour un gestionnaire, ou $null.
# Renvoie @{ target; label; help } : de quoi construire le bouton et l'action.
function Get-PkgGui {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg -or -not $mg.guiKind) { return $null }
    $cible = $null
    switch ($mg.guiKind) {
        'uri' {
            # Un protocole non enregistre ouvrirait une boite « application introuvable ».
            if (Test-Path -LiteralPath ("Registry::HKEY_CLASSES_ROOT\" + $mg.guiProbe)) { $cible = $mg.guiTarget }
        }
        'exe' {
            $c = Get-Command $mg.guiProbe -ErrorAction SilentlyContinue
            if ($c -and $c.Source) { $cible = $c.Source }
            else {
                $racine = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { 'C:\ProgramData\chocolatey' }
                foreach ($p in @((Join-Path $racine ('bin\' + $mg.guiTarget)), (Join-Path $racine ('lib\chocolateygui\tools\' + $mg.guiTarget)))) {
                    if (Test-Path -LiteralPath $p) { $cible = $p; break }
                }
            }
        }
    }
    if (-not $cible) { return $null }
    return @{ target = $cible; label = $mg.guiLabel; help = $mg.guiHelp }
}

# Verifie les MAJ disponibles d'UN gestionnaire (appel lent/reseau). Traite la
# sortie ET le code de retour via Invoke-Native.
# Renvoie @{ count; items; pkgs; supported; selectable }.
#   items = chaines d'AFFICHAGE (tronquees a 25, elles remplissent le detail de la carte)
#   pkgs  = liste COMPLETE @{ id; titre; detail }, `id` etant l'identifiant a passer au
#           gestionnaire pour ne mettre a jour QUE ce paquet. Sans lui, aucun choix n'est
#           possible : on ne peut pas demander « lesquels ? » avec des libelles d'affichage.
function Get-PkgUpdates {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $false } }
    $selectable = ($null -ne $mg.upgOne -and @($mg.upgOne).Count -gt 0)
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $selectable } }
    if ($mg.updMode -eq 'none' -or $mg.updArgs.Count -eq 0) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $selectable } }
    $count = 0; $items = @(); $pkgs = @()
    try {
        $r = Invoke-Native -File $cmd.Source -Arguments $mg.updArgs
        $out = "$($r.Output)"
        switch ($mg.updMode) {
            'jsonlist' {
                if ($out.Trim()) {
                    $j = $out | ConvertFrom-Json
                    foreach ($e in @($j)) {
                        $items += ("{0}  {1} -> {2}" -f $e.name, $e.version, $e.latest_version)
                        $pkgs  += [ordered]@{ id = "$($e.name)"; titre = "$($e.name)"; detail = ("{0} -> {1}" -f $e.version, $e.latest_version) }
                    }
                    $count = $items.Count
                }
            }
            'jsonkeys' {
                if ($out.Trim() -and $out.Trim() -ne '{}') {
                    $j = $out | ConvertFrom-Json
                    foreach ($e in @($j.PSObject.Properties)) {
                        $items += ("{0} -> {1}" -f $e.Name, $e.Value.latest)
                        $pkgs  += [ordered]@{ id = "$($e.Name)"; titre = "$($e.Name)"; detail = "$($e.Value.latest)" }
                    }
                    $count = $items.Count
                }
            }
            'chocor' {
                foreach ($l in (($out -split "`r?`n") | Where-Object { $_ -match '\|' })) {
                    $p = $l.Split('|')
                    $items += ("{0}  {1} -> {2}" -f $p[0], $p[1], $p[2])
                    $pkgs  += [ordered]@{ id = "$($p[0])"; titre = "$($p[0])"; detail = ("{0} -> {1}" -f $p[1], $p[2]) }
                }
                $count = $items.Count
            }
            'winget' {
                $lines = @($out -split "`r?`n"); $idx = -1
                for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{3,}') { $idx = $i; break } }
                if ($idx -ge 0 -and $idx -lt ($lines.Count - 1)) {
                    # Colonnes winget : Nom | Id | Version | Disponible | Source. L'Id est la
                    # SEULE colonne utilisable pour cibler un paquet -- le nom n'est pas unique.
                    #
                    # Decoupage a POSITION FIXE, pas sur « deux espaces ou plus » : winget
                    # remplit chaque colonne a la largeur de son plus long element, si bien
                    # qu'un nom long ne laisse qu'UN espace avant l'Id, et qu'un numero de
                    # version large en laisse un seul avant le suivant. Constate en reel :
                    # le decoupage par espaces rendait « 12.0.40664.0 » comme identifiant du
                    # Redistribuable Visual C++ -- une mise a jour aurait vise un paquet
                    # inexistant. Les debuts de colonne sont lus dans la ligne d'en-tete.
                    $hdr = if ($idx -ge 1) { "$($lines[$idx-1])" } else { '' }
                    $debuts = @()
                    if ($hdr.Length) {
                        if ($hdr[0] -ne ' ') { $debuts += 0 }
                        for ($k = 2; $k -lt $hdr.Length; $k++) {
                            if ($hdr[$k] -ne ' ' -and $hdr[$k-1] -eq ' ' -and $hdr[$k-2] -eq ' ') { $debuts += $k }
                        }
                    }
                    $rest = @($lines[($idx+1)..($lines.Count-1)] | Where-Object { $_.Trim() -and $_ -notmatch 'niveau|upgrade|mise' })
                    foreach ($l in $rest) {
                        $cols = @()
                        if ($debuts.Count -ge 2) {
                            for ($c = 0; $c -lt $debuts.Count; $c++) {
                                $s = $debuts[$c]
                                if ($s -ge $l.Length) { $cols += ''; continue }
                                $e = if ($c + 1 -lt $debuts.Count) { [Math]::Min($debuts[$c+1], $l.Length) } else { $l.Length }
                                $cols += $l.Substring($s, $e - $s).Trim()
                            }
                        } else {
                            # Repli si l'en-tete est absent (sortie inattendue) : mieux vaut une
                            # liste approximative que rien du tout.
                            $cols = @(($l -split '\s{2,}') | Where-Object { $_ } | ForEach-Object { "$_".Trim() })
                        }
                        if (-not $cols.Count) { continue }
                        $nom = "$($cols[0])"
                        if (-not $nom) { continue }
                        $items += $nom
                        # PAS de variable nommee $pid : c'est une variable automatique en
                        # lecture seule (identifiant du processus). L'affectation levait une
                        # exception avalee par le catch, et la liste revenait VIDE.
                        $ident = if ($cols.Count -ge 2) { "$($cols[1])" } else { '' }
                        if ($ident) {
                            $det = if ($cols.Count -ge 4 -and $cols[3]) { ("{0} -> {1}" -f "$($cols[2])", "$($cols[3])") } else { $ident }
                            $pkgs += [ordered]@{ id = $ident; titre = $nom; detail = $det }
                        }
                    }
                    $count = $items.Count
                }
            }
            'lines' {
                $items = @(($out -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch '^Name|^-{3,}|is up to date|Everything' })
                $count = $items.Count
            }
        }
    } catch { }
    # La liste choisissable n'est PAS tronquee : on ne peut pas cocher ce qu'on ne voit pas.
    # Seul l'affichage condense de la carte l'est.
    if ($items.Count -gt 25) { $items = @($items[0..24] + "... (+$($items.Count - 25))") }
    return @{ count = $count; items = @($items); pkgs = @($pkgs); supported = $true; selectable = $selectable }
}

# Met a jour les paquets d'UN gestionnaire (appel lent, systeme). Herite de l'elevation
# du serveur. Traite sortie + code de retour. Renvoie @{ ok; supported; exit; output }.
#
# -Pkgs vide  -> comportement historique : TOUT le gestionnaire, en une commande.
# -Pkgs rempli -> une commande PAR paquet (upgOne), donc uniquement ceux-la. Si le
#   gestionnaire ne sait pas cibler un paquet, la selection est ignoree et on retombe sur
#   la mise a jour globale : c'est ce que la fenetre de choix a annonce a l'utilisateur.
function Invoke-PkgUpgrade {
    param([Parameter(Mandatory)][string]$Id, [string[]]$Pkgs)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg) { return @{ ok = $false; supported = $false; output = '' } }
    $liste = @($Pkgs | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" })
    $unParUn = ($liste.Count -gt 0 -and $null -ne $mg.upgOne -and @($mg.upgOne).Count -gt 0)
    if (-not $unParUn -and (-not $mg.upgArgs -or @($mg.upgArgs).Count -eq 0)) { return @{ ok = $false; supported = $false; output = '' } }
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ ok = $false; supported = $false; output = '' } }

    # 3010 = ERROR_SUCCESS_REBOOT_REQUIRED : l'installation a REUSSI, elle demande un
    # redemarrage. Le traiter comme un echec (« ok=False ») etait faux et affichait une
    # erreur sur une operation qui avait fonctionne -- constate sur Chocolatey.
    # 1641 = redemarrage DEJA declenche, meme famille.
    if (-not $unParUn) {
        $r = Invoke-Native -File $cmd.Source -Arguments $mg.upgArgs
        $redemarrage = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
        return @{ ok = ($r.Ok -or $redemarrage); supported = $true; exit = $r.ExitCode
                  reboot = $redemarrage; output = $r.Output; count = 0; failed = @() }
    }

    $sorties = @(); $echecs = @(); $redemarrage = $false; $dernier = 0
    foreach ($p in $liste) {
        # .Replace et non -replace : un identifiant de paquet ('Microsoft.VC++', 'a.b')
        # contient des caracteres que le moteur d'expressions regulieres interpreterait.
        $argv = @($mg.upgOne | ForEach-Object { "$_".Replace('{pkg}', $p) })
        $r = Invoke-Native -File $cmd.Source -Arguments $argv
        $rb = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
        if ($rb) { $redemarrage = $true }
        if (-not ($r.Ok -or $rb)) { $echecs += $p }
        $dernier = $r.ExitCode
        $sorties += ("=== $p (code $($r.ExitCode)) ===" + [Environment]::NewLine + "$($r.Output)")
    }
    return @{ ok = ($echecs.Count -eq 0); supported = $true; exit = $dernier; reboot = $redemarrage
              output = ($sorties -join ([Environment]::NewLine + [Environment]::NewLine))
              count = $liste.Count; failed = @($echecs) }
}

# Lanceur GENERIQUE (non bloquant) d'une operation paquet : 'check' ou 'upgrade'.
# Marque la carte "en cours" (avec l'operation), lance le worker detache, rend la
# main immediatement. Code unique partage par les deux actions (pas de duplication).
function Start-PkgJob {
    param(
        [Parameter(Mandatory)][string]$Mgr,
        [ValidateSet('check','upgrade')][string]$Op = 'check',
        # Paquets RETENUS par l'utilisateur. Vide = tout le gestionnaire (comportement
        # historique). Voir Invoke-PkgUpgrade.
        [string[]]$Pkgs,
        [string]$Backend = (Get-BackendRoot)
    )
    $known = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Mgr } | Select-Object -First 1
    if (-not $known) { return @{ message = "Gestionnaire inconnu : $Mgr"; result = @{ ok = $false } } }
    $choisis = @($Pkgs | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" })
    $unParUn = ($choisis.Count -gt 0 -and $null -ne $known.upgOne -and @($known.upgOne).Count -gt 0)
    if ($Op -eq 'check'   -and ($known.updMode -eq 'none' -or @($known.updArgs).Count -eq 0)) {
        return @{ message = "Verification non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    if ($Op -eq 'upgrade' -and -not $unParUn -and (-not $known.upgArgs -or @($known.upgArgs).Count -eq 0)) {
        return @{ message = "Mise a jour automatique non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    $stateDir = Get-VarPath -Backend $Backend -Kind 'cache'
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $outFile = Join-Path $stateDir 'pkgupdates.json'
    # Marque "en cours" (conserve le dernier compte connu pour l'affichage).
    # `sel` = les paquets RETENUS : c'est ce qui permet a la carte de dire exactement
    # ce qui se met a jour (« 1 paquet sur 3 »), au lieu d'un « en cours » muet.
    $entry = @{ checking = $true; op = $Op; startedAt = (Get-Date).ToString('s') }
    if ($Op -eq 'upgrade' -and $choisis.Count -gt 0) { $entry.sel = @($choisis) }
    if (Test-Path $outFile) {
        try {
            $j = Get-Content $outFile -Raw | ConvertFrom-Json; $e = $j.$Mgr
            if ($e -and $null -ne $e.count) {
                $entry.count = [int]$e.count; $entry.items = @($e.items)
                if ($e.pkgs) { $entry.pkgs = @($e.pkgs) }
            }
        } catch { }
    }
    Update-StateJson -Path $outFile -Set @{ $Mgr = $entry } | Out-Null
    # Worker unique (branche sur op). Detache, fenetre cachee : ne bloque pas.
    $worker  = Join-Path $Backend 'workers/pkg-job.worker.ps1'
    $started = $false
    try { $null = Start-DetachedAction -Script $worker -ArgsMap @{ mgr = $Mgr; op = $Op; pkgs = $choisis } -Backend $Backend; $started = $true } catch { }
    if (-not $started) { return @{ message = "Impossible de lancer l'operation sur $($known.label)."; result = @{ ok = $false } } }
    $verb = if ($Op -eq 'upgrade') { 'Mise à jour' } else { 'Vérification' }
    $portee = if ($Op -eq 'upgrade' -and $unParUn) { " ($($choisis.Count) paquet(s) sélectionné(s))" } else { "" }
    @{
        message = "$verb de $($known.label) lancée en tâche de fond$portee."
        result  = @{ ok = $true; async = $true; module = ("pkg-" + $Mgr); invalidate = @('packages.probe.ps1') }
    }
}


# config.psd1 (versionne) porte LA definition de chaque valeur.
# config.local.psd1 (ignore par git, optionnel) surcharge les SEULES valeurs qui ne
# peuvent pas etre generiques : chemins propres a une machine. Voir config.local.sample.psd1.
function Get-Config {
    param([string]$Backend = (Get-BackendRoot))
    # Fusion en trois couches (D33), de la plus generale a la plus specifique :
    #   config/common.psd1 (racine)  ->  apps/<app>/config/config.psd1  ->  config.local.psd1
    $cfg = @{}
    $commonPath = Join-Path (Get-RepoRoot) 'config/common.psd1'
    if (Test-Path -LiteralPath $commonPath) {
        try { (Import-PowerShellDataFile -Path $commonPath).GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value } }
        catch { throw ("config/common.psd1 illisible : " + $_.Exception.Message) }
    }
    $appCfg = Import-PowerShellDataFile -Path (Join-Path $Backend 'config/config.psd1')
    foreach ($k in $appCfg.Keys) { $cfg[$k] = $appCfg[$k] }
    $localPath = Join-Path $Backend 'config/config.local.psd1'
    if (Test-Path -LiteralPath $localPath) {
        try { $local = Import-PowerShellDataFile -Path $localPath }
        catch { throw ("config.local.psd1 illisible (" + $localPath + ") : " + $_.Exception.Message) }
        foreach ($k in $local.Keys) { $cfg[$k] = $local[$k] }
    }
    $cfg
}

# --- Valeurs derivees de la config : definies ICI et nulle part ailleurs ------
# L'adresse et le port n'existent qu'une fois (config.psd1) ; toute URL en derive.
function Get-AppUrl {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    'http://{0}:{1}/' -f $Config.BindAddress, $Config.Port
}
function Get-ApiUrl {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    'http://{0}:{1}{2}' -f $Config.BindAddress, $Config.Port, $Config.ApiBase
}

# --- Outillage externe optionnel (scripts d'administration hors depot) -------
# ToolsPath vide ou introuvable => $null, et les actions concernees rendent un
# message clair au lieu d'echouer obscurement.
function Get-ToolsPath {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    $p = [string]$Config.ToolsPath
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    (Resolve-Path -LiteralPath $p).Path
}
function Get-AdminRoot {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    $tools = Get-ToolsPath -Backend $Backend -Config $Config
    if (-not $tools) { return $null }
    Split-Path $tools -Parent
}
# Reponse commune quand l'outillage externe n'est pas configure (une seule redaction).
# Reponse commune des actions qui dependent ENCORE d'un chemin d'outillage configure.
# Depuis que le verrouillage Windows Update et les bascules VBS / HVCI sont natifs, la
# seule concernee est « ouvrir le dossier » -- et sa sonde ne propose meme plus le bouton
# quand le chemin manque. Ce garde-fou couvre le cas ou le dossier disparait entre
# l'affichage de la carte et le clic.
function New-ToolsMissingResult {
    @{
        message = "Aucun dossier d'outillage n'est configuré. Renseignez ToolsPath dans apps/backend-pode/config/config.local.psd1 (modèle : config.local.sample.psd1)."
        result  = @{ ok = $false }
    }
}

function Get-ApiToken {
    param([string]$Backend = (Get-BackendRoot))
    $dir  = Get-VarPath -Backend $Backend -Kind 'secrets'
    $file = Join-Path $dir 'api.token'
    if (-not (Test-Path $file)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
        Set-Content -Path $file -Value $token -NoNewline -Encoding ASCII
    }
    (Get-Content -Path $file -Raw).Trim()
}

# --- Version applicative (change quand index.html change) -------------------
# Numero de VERSION du produit, lu dans le fichier VERSION a la racine du depot.
#
# UN SEUL endroit le porte (D15). Le projet n'est pas publie : il est en 0.1, et ce numero
# ne change que sur decision explicite de l'utilisateur -- pas au fil des commits.
#
# Deux tentatives ont ete ecartees avant celle-ci :
#   - les TICKS de la date du fichier (« version 639231069781032063 ») : un jeton de
#     changement deguise en version, illisible et incomparable ;
#   - `git describe` : varie a chaque commit, depend de git et du PATH, et faisait
#     apparaitre des etiquettes de travail internes dans l'interface.
# Le role de jeton de changement revient a Get-AppBuildId, ci-dessous.
function Get-AppVersion {
    param([string]$Backend = (Get-BackendRoot))
    $f = Join-Path (Get-RepoRoot) 'VERSION'
    if (Test-Path -LiteralPath $f) {
        $v = "$(Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue)".Trim()
        # Convention du projet : un numero de version s'affiche prefixe de « v ». Le
        # fichier VERSION ne porte QUE le numero ; le prefixe est ajoute ici, une fois,
        # pour qu'il ne se recopie pas dans chaque endroit qui affiche la version.
        if ($v) { return $(if ($v.StartsWith('v')) { $v } else { "v$v" }) }
    }
    return 'inconnue'
}

# Jeton de CHANGEMENT, jamais affiche. Le front le compare au sien et recharge la page des
# qu'il differe. Il doit donc bouger a chaque modification du fichier servi -- ce que ne
# fait pas une empreinte de commit, qui ignore les modifications non validees.
function Get-AppBuildId {
    param([string]$Backend = (Get-BackendRoot))
    $idx = Join-Path (Get-AppPath -Role 'frontend') 'index.html'
    if (Test-Path $idx) { "$((Get-Item $idx).LastWriteTimeUtc.Ticks)" } else { '0' }
}

# --- Journalisation ---------------------------------------------------------
# --- Donnees d'execution : apps/<app>/var/ (convention Symfony) -----------------
# Tout ce que l'app GENERE ou gere en local vit sous var/ : cache, journaux, etat,
# secrets generes. Rien de tout cela n'est versionne.
# Ces chemins sont ecrits ICI et nulle part ailleurs : ils etaient auparavant
# recomposes a la main dans 8 fichiers (actions, sondes, workers).
function Get-VarPath {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][ValidateSet('cache','log','secrets')][string]$Kind,
        [string]$File
    )
    $dir = Join-Path (Join-Path $Backend 'var') $Kind
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null
    }
    if ($File) { return (Join-Path $dir $File) }
    return $dir
}

function Get-LogDir {
    param([string]$Backend = (Get-BackendRoot))
    $d = Get-VarPath -Backend $Backend -Kind 'log'
    # -WhatIf:$false : creer le dossier de journaux est de la plomberie, pas une
    # operation que l'utilisateur simule. Sans cela, -WhatIf empeche toute journalisation.
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force -WhatIf:$false | Out-Null }
    $d
}
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = 'INFO',
        [string]$Name  = 'app',
        [string]$Backend = (Get-BackendRoot)
    )
    $dir  = Get-LogDir -Backend $Backend
    $file = Join-Path $dir ($Name + '_' + (Get-Date -Format 'yyyyMMdd') + '.log')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $file -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}

# --- Fabriques d'objets du contrat -----------------------------------------
function New-Field {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][ValidateSet('bool','number','text','date')][string]$Kind,
        [string]$Unit,
        [ValidateSet('ok','warn','error','neutral')][string]$Status,
        [string]$Help,
        [string]$FixAction,
        [string]$Guide,
        # Detail STRUCTURE : @{ columns = @('...'); rows = @(@('...'), ...) }.
        # Une liste de plusieurs dizaines de lignes mise en forme dans une chaine reste
        # illisible ou qu'on l'affiche. Un tableau se parcourt du regard ; le texte, non.
        [hashtable]$Table
    )
    $f = [ordered]@{ key = $Key; label = $Label; value = $Value; kind = $Kind }
    if ($Unit)      { $f['unit']      = $Unit }
    if ($Status)    { $f['status']    = $Status }
    if ($Help)      { $f['help']      = $Help }
    if ($FixAction) { $f['fixAction'] = $FixAction }
    if ($Guide)     { $f['guide']     = $Guide }
    if ($Table -and $Table.rows -and @($Table.rows).Count) { $f['table'] = $Table }
    [pscustomobject]$f
}
function New-Action {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [switch]$Confirm,
        [string]$Help,
        # 'dialog' : ouvre une fenetre de CHOIX dans l'application (liste a cocher).
        # Distinct de 'manual', qui ouvre un LOGICIEL EXTERNE, et de 'confirm', qui ne
        # demande qu'un oui/non. Les trois ne se ressemblaient pas assez a l'ecran.
        [ValidateSet('immediate','confirm','manual','dialog')][string]$Kind,
        # SEVERITE : ce que l'action represente, independamment de la FORME qu'elle prend.
        # `kind` choisit l'ICONE (comment ca se passe : oui/non, fenetre de choix, logiciel
        # externe) ; `severity` choisit la COULEUR (ce que ca vaut) :
        #   neutral = sans enjeu (gris) | info = consultation, ouverture (bleu)
        #   fix     = corrige quelque chose (vert)
        # Les deux etaient confondus : la couleur suivait la forme, ce qui n'apprend rien.
        [ValidateSet('neutral','info','fix')][string]$Severity,
        # Libelle affiche PENDANT l'execution. Il doit dire ce qui se passe -- « Mise à
        # jour… », pas « En cours… ». Les points de suspension sont RESERVES a une action
        # en cours : un libelle au repos n'en porte jamais.
        [string]$BusyLabel,
        # DEUX confirmations distinctes avant execution. Reserve aux gestes qui ferment le
        # travail en cours de l'utilisateur ou touchent la machine entiere : un seul clic
        # de trop ne doit pas suffire.
        [switch]$ConfirmTwice
    )
    $a = [ordered]@{ id = $Id; label = $Label }
    if ($Confirm -or $ConfirmTwice) { $a['confirm'] = $true }
    if ($ConfirmTwice) { $a['confirmTwice'] = $true }
    if ($Help)    { $a['help']    = $Help }
    $a['kind'] = if ($Kind) { $Kind } elseif ($Confirm) { 'confirm' } else { 'immediate' }
    # Defaut raisonnable : ouvrir quelque chose informe, le reste est neutre. Une action
    # corrective doit se declarer -- on ne devine pas qu'elle repare.
    # Defaut : 'info'. Un bouton EST une action : il fait quelque chose, son icone merite
    # une couleur. Le gris etait le defaut, si bien que toute action ordinaire paraissait
    # inerte ; il se DECLARE desormais, pour le cas rare ou il n'y a aucun enjeu.
    # 'fix' se declare aussi : on ne devine pas qu'une action repare.
    $a['severity'] = if ($Severity) { $Severity } else { 'info' }
    # Defaut : le libelle suivi de points de suspension. Correct grammaticalement dans la
    # plupart des cas ; on precise quand la forme nominale est meilleure.
    $a['busyLabel'] = if ($BusyLabel) { $BusyLabel } else { "$Label…" }
    [pscustomobject]$a
}
function New-ModuleObject {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Theme,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][ValidateSet('ok','warn','error','neutral')][string]$Status,
        [object[]]$Fields = @(),
        [object[]]$Actions = @(),
        [switch]$Busy,
        # Identifiant de l'action REELLEMENT en cours. Sans lui, l'interface anime tous les
        # boutons de la carte : on ne sait plus lequel travaille.
        [string]$BusyAction
    )
    # INVARIANT : une carte n'est jamais PLUS GRAVE que le pire de ses champs. Une carte
    # « Problème » (rouge) dont aucune ligne n'est rouge est une contradiction que
    # l'utilisateur voit immediatement, et il n'a nulle part ou aller pour la resoudre.
    # La borne est posee ICI, une seule fois, pour toutes les sondes (aucune ne peut plus
    # l'oublier). Les champs « neutral » ne bornent RIEN : ils ne portent pas de jugement,
    # une carte verte faite de lignes neutres reste legitime.
    $rank = @{ neutral = 0; ok = 1; warn = 2; error = 3 }
    $cap = 0
    foreach ($f in @($Fields)) {
        $s = "$($f.status)"
        if ($s -and $rank.ContainsKey($s) -and $rank[$s] -gt $cap) { $cap = $rank[$s] }
    }
    $effective = $Status
    if ($cap -gt 0 -and $rank["$Status"] -gt $cap) {
        $effective = ($rank.GetEnumerator() | Where-Object { $_.Value -eq $cap }).Name
    }
    $o = [ordered]@{
        id = $Id; theme = $Theme; label = $Label; status = $effective
        fields = @($Fields); actions = @($Actions)
    }
    if ($Busy) { $o['busy'] = $true }
    if ($Busy -and $BusyAction) { $o['busyAction'] = $BusyAction }
    [pscustomobject]$o
}

$script:ThemeCatalog = @(
    [pscustomobject]@{ id = 'windows-update'; label = 'Windows Update' }
    [pscustomobject]@{ id = 'system';         label = 'Système' }
    [pscustomobject]@{ id = 'wsl';            label = 'WSL' }
    [pscustomobject]@{ id = 'security';       label = 'Sécurité' }
    [pscustomobject]@{ id = 'network';        label = 'Réseau' }
    [pscustomobject]@{ id = 'tools';          label = 'Outils & paquets' }
)

# --- Agregation des sondes (journalisee) -----------------------------------
# Duree de validite du cache par sonde (secondes) : court pour ce qui bouge vite,
# long pour ce qui est stable.
$script:ProbeTtls = @{
    'perf.probe.ps1'    = 8
    'net.probe.ps1'     = 15
    'wsl.probe.ps1'     = 600
    'disk.probe.ps1'    = 60
    'history.probe.ps1' = 120
    'firewall.probe.ps1'= 120
    'defender.probe.ps1'= 300
    'vbs.probe.ps1'     = 300
    'lock.probe.ps1'    = 600
    'pending.probe.ps1' = 900
    'os.probe.ps1'      = 3600
    'packages.probe.ps1'= 5
}

# Ramene une date lue depuis JSON a un [datetime] UTC, quelle que soit sa forme.
#
# ConvertFrom-Json convertit parfois lui-meme les chaines ISO-8601 en [datetime] : selon le
# chemin, on recoit une chaine ou un objet, et le Kind peut etre Utc, Local ou Unspecified.
# Comparer sans normaliser donne un age faux de plusieurs heures -- c'est ce qui rendait le
# cache d'etat inoperant. La conversion se fait donc ICI, en un seul endroit.
function ConvertTo-UtcDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    $d = if ($Value -is [datetime]) { $Value }
         else { [datetimeoffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
    switch ($d.Kind) {
        'Local'       { return $d.ToUniversalTime() }
        'Unspecified' { return [datetime]::SpecifyKind($d, [DateTimeKind]::Utc) }
        default       { return $d }
    }
}

# --- Journal des passages de sondes ------------------------------------------
# On conserve SYSTEMATIQUEMENT chaque execution reelle d'une sonde et sa duree, d'ou
# qu'elle vienne : requete de l'utilisateur, rafraichissement de fond, ou controle du
# contrat. Sans cette trace, « Vigie met parfois beaucoup de temps a charger » reste une
# impression : on ne sait ni QUELLE sonde a coute, ni si c'est habituel.
#
# Format : une ligne JSON par execution (JSONL). Append-only, donc pas de relecture du
# fichier pour ecrire -- c'est ce qui le rend utilisable sous concurrence.
# Ce journal est aussi le premier echantillonnage sur lequel l'historique s'appuiera.
$script:ProbeRunMaxBytes = 1.5MB   # au-dela, on ne garde que les passages recents
$script:ProbeRunKeepLines = 5000

function Write-ProbeRun {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Probe,
        [Parameter(Mandatory)][int]$Ms,
        # D'ou vient l'execution : 'forced' (bouton Rafraichir), 'background' (worker),
        # 'check' (controle du contrat).
        [string]$Origin = 'background',
        [ValidateSet('ok','error','empty')][string]$Outcome = 'ok',
        [int]$Modules = 0,
        [string]$Detail
    )
    try {
        $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'probe-runs.jsonl'
        $rec = [ordered]@{
            at      = [datetime]::UtcNow.ToString('o')
            probe   = $Probe
            ms      = $Ms
            origin  = $Origin
            outcome = $Outcome
            modules = $Modules
        }
        if ($Detail) { $rec.detail = $Detail }
        $ligne = ($rec | ConvertTo-Json -Compress -Depth 4)

        $mx = New-Object System.Threading.Mutex($false, 'Local\VigieProbeRuns')
        $got = $false
        try {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if (-not $got) { return }

            [IO.File]::AppendAllText($file, $ligne + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

            # Purge paresseuse : on ne lit le fichier que lorsqu'il a vraiment grossi.
            $fi = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
            if ($fi -and $fi.Length -gt $script:ProbeRunMaxBytes) {
                $lignes = [IO.File]::ReadAllLines($file)
                if ($lignes.Count -gt $script:ProbeRunKeepLines) {
                    $garde = $lignes[($lignes.Count - $script:ProbeRunKeepLines)..($lignes.Count - 1)]
                    [IO.File]::WriteAllLines($file, $garde, [Text.UTF8Encoding]::new($false))
                }
            }
        } finally {
            if ($got) { try { $mx.ReleaseMutex() } catch { } }
            try { $mx.Dispose() } catch { }
        }
    } catch {
        # Le journal ne doit JAMAIS faire echouer une sonde : il observe, il n'arbitre pas.
    }
}

# Relit le journal des passages. Sert au diagnostic (« quelle sonde coute ? ») et,
# plus tard, a l'historique.
function Get-ProbeRuns {
    param(
        [string]$Backend = (Get-BackendRoot),
        [string]$Probe,
        [int]$Last = 200
    )
    $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'probe-runs.jsonl'
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    $lignes = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue)
    $res = @()
    foreach ($l in $lignes) {
        if (-not $l) { continue }
        try { $o = $l | ConvertFrom-Json } catch { continue }
        if ($Probe -and "$($o.probe)" -notlike $Probe) { continue }
        $res += $o
    }
    if ($Last -gt 0 -and $res.Count -gt $Last) { $res = $res[($res.Count - $Last)..($res.Count - 1)] }
    return @($res)
}

function Get-State {
    param(
        [string]$Backend = (Get-BackendRoot),
        [switch]$Force,
        # Secondes d'attente du verrou de recalcul. 0 = renoncer si un calcul tourne deja.
        # Seule une demande EXPLICITE de l'utilisateur attend ; le rafraichissement de fond
        # renonce, sans quoi les workers s'empilent en se bloquant les uns les autres.
        # Plafonne sous le delai du client (90 s) : attendre plus longtemps que lui
        # reviendrait a travailler pour une requete deja abandonnee.
        [int]$WaitSeconds = 0
    )
    $probesDir = Join-Path $Backend 'probes'
    $cacheFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
    $stateDir  = Split-Path $cacheFile -Parent
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $defaultTtl = 30

    # Charge le cache existant. TOUJOURS, meme avec -Force : forcer signifie « recalcule »,
    # pas « oublie tout ». Repartir d'un cache vide faisait disparaitre les modules un a un
    # du fichier pendant le recalcul, et un lecteur simultane recevait un etat AMPUTE --
    # une carte s'evanouissait le temps du rafraichissement.
    $cache = @{}
    if (Test-Path $cacheFile) {
        try { $j = Get-Content $cacheFile -Raw | ConvertFrom-Json; foreach ($pr in $j.PSObject.Properties) { $cache[$pr.Name] = $pr.Value } } catch { }
    }

    # Sondes + fraicheur (invalidation PAR sonde : mtime du fichier + TTL)
    #
    # L'age se calcule ENTIEREMENT en UTC. La date est ecrite en UTC (`ToUniversalTime`) ;
    # elle etait comparee a `Get-Date`, qui rend l'heure LOCALE. Sur un poste a UTC+2,
    # toute entree paraissait donc vieille de deux heures : aucune n'a jamais ete jugee
    # fraiche, le cache ne servait a rien et chaque appel a /state recalculait les douze
    # sondes -- une vingtaine de secondes, dont dix pour la seule sonde `lock`.
    $nowUtc = [datetime]::UtcNow
    $probeFiles = @(Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -ErrorAction SilentlyContinue | Sort-Object FullName)
    # Modules coupes par l'utilisateur (D48) : leurs sondes sortent du calcul ET de
    # l'affichage. Le filtre se fait sur le DOSSIER parent -- un module est un dossier.
    $unitesCoupees = @(Get-DisabledUnits)
    if ($unitesCoupees.Count -gt 0) {
        $probeFiles = @($probeFiles | Where-Object {
            $unitesCoupees -notcontains (Split-Path (Split-Path $_.FullName -Parent) -Leaf)
        })
    }
    $stale = @()
    foreach ($pf in $probeFiles) {
        $name = $pf.Name; $stamp = "$($pf.LastWriteTimeUtc.Ticks)"
        $ttl = if ($script:ProbeTtls.ContainsKey($name)) { $script:ProbeTtls[$name] } else { $defaultTtl }
        $entry = $cache[$name]; $fresh = $false
        # -Force : tout est considere perime, sans rien effacer.
        if (-not $Force -and $entry -and $entry.at -and ("$($entry.codeStamp)" -eq $stamp)) {
            try {
                $at = ConvertTo-UtcDate $entry.at
                if ($at -and ($nowUtc - $at).TotalSeconds -lt $ttl) { $fresh = $true }
            } catch { }
        }
        if (-not $fresh) { $stale += [pscustomobject]@{ File = $pf.FullName; Name = $name; Stamp = $stamp } }
    }

    # Recalcul en SINGLE-FLIGHT : un seul thread recalcule a la fois ; les autres requetes
    # servent le cache existant immediatement (evite l'effet troupeau -> plus de 408).
    # SERVIR D'ABORD, RECALCULER ENSUITE.
    #
    # Une sonde perimee qui possede DEJA une valeur en cache ne doit pas faire attendre
    # l'affichage : on rend la valeur connue tout de suite et on recalcule en tache de
    # fond. Seules les sondes qui n'ont RIEN en cache sont calculees dans la requete --
    # sinon il n'y aurait rien a montrer.
    #
    # Avant, toute peremption bloquait la reponse : selon l'instant, ouvrir Vigie prenait
    # de 0,3 s a plus de 20 s, sans que rien n'explique la difference a l'utilisateur.
    # Le bouton « Rafraichir » (-Force) garde, lui, le recalcul synchrone : c'est ce qu'on
    # lui demande explicitement.
    if (-not $Force -and $stale.Count -gt 0) {
        $sansValeur = @($stale | Where-Object { -not ($cache[$_.Name] -and $cache[$_.Name].module) })
        $aDifferer  = @($stale | Where-Object {      $cache[$_.Name] -and $cache[$_.Name].module  })
        if ($aDifferer.Count -gt 0) {
            $stale = $sansValeur
            # UN SEUL rafraichissement de fond a la fois. On verifie AVANT de lancer :
            # demarrer un processus pour qu'il constate qu'il n'a rien a faire coute une
            # seconde de pwsh a chaque requete, pour rien.
            $dejaEnCours = $false
            try {
                $tmp = $null
                if ([System.Threading.Mutex]::TryOpenExisting('Local\VigieStateRecompute', [ref]$tmp)) {
                    $dejaEnCours = -not $tmp.WaitOne(0)
                    if (-not $dejaEnCours) { try { $tmp.ReleaseMutex() } catch { } }
                    try { $tmp.Dispose() } catch { }
                }
            } catch { }
            if (-not $dejaEnCours) {
                try {
                    $w = Join-Path $Backend 'workers/state-refresh.worker.ps1'
                    $null = Start-DetachedAction -Script $w -Backend $Backend
                } catch { }
            }
        }
    }

    if ($stale.Count -gt 0) {
        $slow  = @('lock.probe.ps1','pending.probe.ps1','wsl.probe.ps1')   # calculees en dernier
        $stale = @($stale | Sort-Object @{ Expression = { if ($slow -contains $_.Name) { 1 } else { 0 } } }, Name)
        $mx = $null; $got = $false
        try {
            $mx = New-Object System.Threading.Mutex($false, 'Local\VigieStateRecompute')
            # Une demande EXPLICITE (-Force, bouton « Rafraichir ») ATTEND son tour ; les
            # requetes ordinaires n'attendent pas et se contentent du cache.
            # Avec WaitOne(0) pour tout le monde, le bouton ne faisait rien des qu'un
            # rafraichissement de fond tenait le verrou : il rendait la main aussitot.
            $attente = [Math]::Min([Math]::Max($WaitSeconds, 0), 75) * 1000
            try { $got = $mx.WaitOne($attente) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if ($got) {
                # L'origine du passage, pour le journal : une demande explicite attend
                # (WaitSeconds > 0 ou -Force), le reste est un rafraichissement de fond.
                $origine = if ($Force -or $WaitSeconds -gt 0) { 'forced' } else { 'background' }
                foreach ($sp in $stale) {
                    $t0 = Get-Date
                    try {
                        $m = & $sp.File
                        $duree = [int]((Get-Date) - $t0).TotalMilliseconds
                        if ($m) { $cache[$sp.Name] = [ordered]@{ module = $m; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp } }
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms $duree -Origin $origine -Outcome ($(if ($m) { 'ok' } else { 'empty' })) -Modules @($m).Count
                        Write-Log -Backend $Backend -Name 'state' -Message ("sonde " + $sp.Name + " recalculee (" + $duree + " ms)")
                    } catch {
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms ([int]((Get-Date) - $t0).TotalMilliseconds) -Origin $origine -Outcome 'error' -Detail $_.Exception.Message
                        Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message ("sonde erreur : " + $sp.Name + " : " + $_.Exception.Message)
                        $errMod = New-ModuleObject -Id $sp.Name -Theme 'system' -Label $sp.Name -Status 'error' -Fields @(New-Field -Key 'error' -Label 'Erreur de sonde' -Value $_.Exception.Message -Kind 'text')
                        $cache[$sp.Name] = [ordered]@{ module = $errMod; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp }
                    }
                    # Ecriture FUSIONNEE, entree par entree, sous mutex (Update-StateJson).
                    #
                    # On reecrivait tout le fichier depuis la copie memoire : deux recalculs
                    # simultanes (la requete forcee et le rafraichissement de fond) se
                    # clobberaient l'un l'autre, et une entree deja corrigee revenait a son
                    # ancienne valeur -- une carte en erreur ressuscitait apres correction.
                    # Ne reecrire QUE la sonde qu'on vient de calculer supprime la course.
                    try { Update-StateJson -Path $cacheFile -Set @{ $sp.Name = $cache[$sp.Name] } | Out-Null } catch { }
                }
            }
        } finally {
            if ($got -and $mx) { try { $mx.ReleaseMutex() } catch { } }
            if ($mx) { try { $mx.Dispose() } catch { } }
        }
    }

    # Assemble les modules depuis le cache (dans l'ordre des fichiers de sondes).
    # Une sonde peut renvoyer UN module ou un TABLEAU de modules (aplati ici).
    $modules = @()
    foreach ($pf in $probeFiles) { $e = $cache[$pf.Name]; if ($e -and $e.module) { $modules += $e.module } }

    $present = @($modules | Select-Object -ExpandProperty theme -Unique)
    $themes  = @($script:ThemeCatalog | Where-Object { $present -contains $_.id })
    [pscustomobject][ordered]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        version     = (Get-AppVersion -Backend $Backend)
        build       = (Get-AppBuildId -Backend $Backend)
        host        = "$env:COMPUTERNAME"
        themes      = $themes
        modules     = @($modules)
        # TOUS les modules-dossiers, y compris desactives (D48) : c'est ce qui permet a
        # la vue de gestion de proposer de rallumer ce qui n'est plus affiche.
        units       = @(Get-UnitCatalog -Backend $Backend)
    }
}

# --- Gestion des modules (D48) ------------------------------------------------
# Un MODULE (unite) = un DOSSIER de sondes, declare par un module.psd1 versionne.
# L'activation est un choix de l'utilisateur : config/modules.local.psd1, jamais
# versionne. Un module coupe retire ses sondes du calcul, mais reste EXPOSE dans la
# cle units[] du contrat -- sinon l'interface ne pourrait plus proposer de le rallumer.
function Get-UnitsLocalPath {
    Join-Path (Get-RepoRoot) 'config/modules.local.psd1'
}

function Get-DisabledUnits {
    $p = Get-UnitsLocalPath
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
        $d = Import-PowerShellDataFile -Path $p
        return @($d.Disabled | ForEach-Object { "$_" })
    } catch { return @() }
}

function Set-UnitEnabled {
    param(
        [Parameter(Mandatory)][string]$UnitId,
        [Parameter(Mandatory)][bool]$Enabled
    )
    $off = [System.Collections.Generic.List[string]]::new()
    foreach ($u in (Get-DisabledUnits)) { if ($u -ne $UnitId) { $off.Add($u) } }
    if (-not $Enabled) { $off.Add($UnitId) }
    $liste = ($off | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $texte = "@{`n    # Modules DESACTIVES par l'utilisateur (D48). Fichier ecrit par l'application`n    # (vue de gestion des modules), jamais versionne. Vide = tout est actif.`n    Disabled = @($liste)`n}`n"
    $p = Get-UnitsLocalPath
    Set-Content -LiteralPath $p -Value $texte -Encoding UTF8
}

function Get-UnitCatalog {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    $off = Get-DisabledUnits
    @(foreach ($dir in (Get-ChildItem -Path $probesDir -Directory | Sort-Object Name)) {
        $decl = @{}
        $declPath = Join-Path $dir.FullName 'module.psd1'
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        $probes = @(Get-ChildItem -Path $dir.FullName -Filter '*.probe.ps1' -File)
        [pscustomobject][ordered]@{
            id          = $dir.Name
            label       = if ($decl.Label) { "$($decl.Label)" } else { $dir.Name }
            description = if ($decl.Description) { "$($decl.Description)" } else { '' }
            enabled     = ($off -notcontains $dir.Name)
            probes      = @($probes | ForEach-Object { $_.Name -replace '\.probe\.ps1$', '' })
        }
    })
}

# --- Reglages des notifications (D54) ----------------------------------------
# Le TRAY notifie sur bascule d'un MODULE (resultat de sonde) ; la couleur de son icone,
# elle, reste le statut de l'APPLICATION -- les deux roles ne se melangent pas.
#
# Reglages : un interrupteur global + un reglage FIN par module. Le global MASQUE, il
# n'ecrase pas : couper tout puis rallumer retrouve les choix fins intacts. C'est pour
# cela que les deux vivent dans des cles separees.
#
# Stockage : config/notifications.local.json a la racine (jamais versionne). JSON et non
# psd1 : ce fichier est ECRIT par le backend (l'interface le modifie via l'API), et le
# tray le RELIT ; JSON se lit et s'ecrit sans peine des deux cotes.
function Get-NotificationSettingsPath {
    Join-Path (Get-RepoRoot) 'config/notifications.local.json'
}

function Get-NotificationSettings {
    param([string]$Backend = (Get-BackendRoot))
    $s = [ordered]@{ enabled = $true; modules = [ordered]@{} }
    $p = Get-NotificationSettingsPath
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $j.enabled) { $s.enabled = [bool]$j.enabled }
            if ($j.modules) { foreach ($pr in $j.modules.PSObject.Properties) { $s.modules[$pr.Name] = [bool]$pr.Value } }
        } catch { }
    }
    [pscustomobject]$s
}

function Set-NotificationSettings {
    param(
        [string]$Backend = (Get-BackendRoot),
        $Enabled,
        # Table module -> $true/$false. FUSIONNEE avec l'existant : ne fournir que ce qui
        # change ; une cle absente garde son reglage (le global ne perd jamais le fin).
        [hashtable]$Modules
    )
    $cur = Get-NotificationSettings -Backend $Backend
    $out = [ordered]@{ enabled = [bool]$cur.enabled; modules = [ordered]@{} }
    foreach ($k in @($cur.modules.Keys)) { $out.modules["$k"] = [bool]$cur.modules[$k] }
    if ($null -ne $Enabled) { $out.enabled = [bool]$Enabled }
    if ($Modules) { foreach ($k in $Modules.Keys) { $out.modules["$k"] = [bool]$Modules[$k] } }
    $p = Get-NotificationSettingsPath
    $tmp = "$p.tmp"
    ($out | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $p -Force
    [pscustomobject]$out
}

# Le tray applique la regle SANS refaire la logique : une notification pour ce module
# passe-t-elle ? (global coupe = rien ; sinon le reglage fin, actif par defaut)
function Test-NotificationAllowed {
    param([Parameter(Mandatory)][string]$ModuleId, $Settings)
    if (-not $Settings) { $Settings = Get-NotificationSettings }
    if (-not [bool]$Settings.enabled) { return $false }
    # `modules` est un DICTIONNAIRE (jamais un objet JSON brut : Get-NotificationSettings
    # normalise) -- l'acces passe donc par ContainsKey. La premiere version interrogeait
    # PSObject.Properties, qui sur un dictionnaire decrit le conteneur et pas les cles :
    # tous les reglages fins etaient silencieusement ignores.
    if ($Settings.modules.Contains("$ModuleId")) { return [bool]$Settings.modules["$ModuleId"] }
    return $true
}

# --- Actions ---------------------------------------------------------------
function New-JobId { [guid]::NewGuid().ToString('N').Substring(0, 12) }

function Invoke-ActionById {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Module,
        [hashtable]$Params,
        [string]$Backend = (Get-BackendRoot)
    )
    # Sécurité : n'accepter qu'un identifiant simple (pas de traversee de chemin)
    if ($Type -notmatch '^[a-z][a-z0-9-]{1,40}$') {
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = "Type d'action invalide." }
    }
    $file = Join-Path $Backend ("actions/$Type.action.ps1")
    $full = try { (Resolve-Path -LiteralPath $file -ErrorAction Stop).Path } catch { $null }
    $actionsDir = (Resolve-Path -LiteralPath (Join-Path $Backend 'actions')).Path
    if (-not $full -or -not $full.StartsWith($actionsDir)) {
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = "Action inconnue : $Type" }
    }
    try {
        $res = & $file -Module $Module -Params $Params
        # Invalidation ciblee du cache : les sondes citees seront recalculees au prochain /state
        try {
            $inv = if ($res -and $res.result -and $res.result.invalidate) { @($res.result.invalidate) } else { @() }
            if ($inv.Count) { Remove-ProbeCache -Names $inv -Backend $Backend }
        } catch { }
        [pscustomobject]@{ jobId = (New-JobId); status = 'done'; message = $res.message; result = $res.result }
    } catch {
        [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $_.Exception.Message }
    }
}

# --- Atelier : present en local ? --------------------------------------------
# L'Atelier est un outil de developpement lance A LA MAIN : l'interface de Vigie ne
# montre un lien vers lui QUE s'il repond vraiment. La detection vit ici (serveur) car
# le front ne peut pas sonder un autre port proprement, et le port de l'Atelier n'est
# defini que dans SA config (D15) -- on la lit, on ne la recopie pas.
function Get-AtelierUrl {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $cfgPath = Join-Path (Get-RepoRoot) 'apps/atelier/config/config.psd1'
        if (-not (Test-Path -LiteralPath $cfgPath)) { return $null }
        $acfg = Import-PowerShellDataFile -Path $cfgPath
        $port = [int]$acfg.Port
        if (-not $port) { return $null }
        $addr = (Get-Config -Backend $Backend).BindAddress
        if (-not $addr) { $addr = '127.0.0.1' }
        # Connexion TCP brute, delai court : sur l'hote local, un port ferme repond
        # immediatement -- ce test ne ralentit pas /health.
        $c = [System.Net.Sockets.TcpClient]::new()
        try {
            if (-not $c.ConnectAsync($addr, $port).Wait(250)) { return $null }
        } finally { $c.Dispose() }
        return ('http://{0}:{1}/apps/atelier/index.html' -f $addr, $port)
    } catch { return $null }
}

# --- Idempotence : le serveur ecoute-t-il deja ? ---------------------------
function Test-ServerUp {
    # Pas de valeur par defaut : l'adresse et le port n'ont qu'UNE definition (config.psd1).
    param([Parameter(Mandatory)][string]$Address, [Parameter(Mandatory)][int]$Port)
    try {
        $c = [System.Net.Sockets.TcpClient]::new()
        $c.Connect($Address, $Port)
        $c.Close()
        return $true
    } catch { return $false }
}

# --- Elevation : expliquer AVANT de demander ---------------------------------
# Principe (demande explicite de l'utilisateur, D22) : on n'envoie jamais l'invite
# UAC "nue". On affiche d'abord une fenetre qui dit ce qui va etre modifie et
# pourquoi l'elevation est necessaire, comme le fait Android avant une permission.
# L'utilisateur peut refuser sans qu'aucune invite systeme n'apparaisse.

# Echappe une chaine pour l'inserer dans une commande PowerShell (guillemets simples).
function ConvertTo-PSLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    "'" + $Value.Replace("'", "''") + "'"
}

# Le processus courant est-il eleve ? (une seule redaction de ce test)
# Le test d'elevation n'a qu'UNE implementation (Test-Elevated, plus haut). Ce nom-ci
# est celui qu'emploient les scripts d'installation ; il delegue au lieu de reecrire le
# meme test une seconde fois (D15). Les deux copies existaient et pouvaient diverger.
function Test-IsElevated { Test-Elevated }

# --- Habillage des fenetres (DWM) --------------------------------------------
# Barre de titre sombre et coins arrondis Windows 11. Declare UNE SEULE FOIS ici
# et utilise partout (fenetre de consentement, menu du tray) : la signature
# P/Invoke ne doit pas etre recopiee dans chaque script.
# Sans effet sur les versions de Windows anterieures : l'appel echoue sans dommage.
function Set-WindowChrome {
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [switch]$DarkTitleBar,
        [switch]$RoundedCorners,
        # Couleur de bordure au format COLORREF (0x00BBGGRR). -1 = ne pas toucher.
        [int]$BorderColor = -1
    )
    if ($Handle -eq [IntPtr]::Zero) { return }
    try {
        if (-not ('VigieNative.Dwm' -as [type])) {
            Add-Type -Namespace VigieNative -Name Dwm -MemberDefinition '[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);' -ErrorAction Stop
        }
        # 20 = DWMWA_USE_IMMERSIVE_DARK_MODE, 33 = WINDOW_CORNER_PREFERENCE, 34 = BORDER_COLOR
        if ($DarkTitleBar)   { $v = 1; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 20, [ref]$v, 4) }
        if ($RoundedCorners) { $v = 2; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 33, [ref]$v, 4) }
        if ($BorderColor -ne -1) { $v = $BorderColor; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 34, [ref]$v, 4) }
    } catch { }
}

# D'ou vient ce lancement ? Renvoie une chaine descriptive si un agent automatise
# est detecte, sinon $null (lancement a la main).
# Enjeu de securite : une demande de droits administrateur qui ne vient PAS d'un clic
# de l'utilisateur doit s'annoncer comme telle. Sans cela, un agent pourrait obtenir
# une elevation que l'utilisateur croirait avoir lui-meme declenchee.
function Get-LaunchOrigin {
    if ($env:AI_AGENT)       { return $env:AI_AGENT }
    if ($env:CLAUDECODE)     { return 'Claude Code' }
    if ($env:GITHUB_ACTIONS) { return 'GitHub Actions' }
    if ($env:TF_BUILD)       { return 'Azure Pipelines' }
    return $null
}

# Decoupe un controle en rectangle arrondi. Necessaire pour les menus contextuels :
# DWM (Set-WindowChrome) n'arrondit PAS les fenetres sans cadre standard, ce qui laisse
# un menu a coins carres. La region, elle, s'applique toujours.
# Contrepartie assumee : bords sans anticrenelage et ombre coupee au trace.
function Set-RoundedRegion {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [int]$Radius = 8
    )
    try {
        if ($Radius -le 0 -or $Control.Width -le 0 -or $Control.Height -le 0) { return }
        $w = $Control.Width; $h = $Control.Height
        $d = [Math]::Min($Radius * 2, [Math]::Min($w, $h))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $d, $d, 180, 90)
        $path.AddArc($w - $d, 0, $d, $d, 270, 90)
        $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
        $path.AddArc(0, $h - $d, $d, $d, 90, 90)
        $path.CloseFigure()
        $old = $Control.Region
        $Control.Region = New-Object System.Drawing.Region($path)
        if ($old) { $old.Dispose() }
        $path.Dispose()
    } catch { }
}

# Fenetre explicative. Renvoie $true si l'utilisateur accepte de continuer.
# -AssumeYes court-circuite l'affichage (execution non interactive, tache planifiee).
function Show-ElevationRationale {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Summary,
        [string[]]$Changes = @(),
        # Origine du lancement. Par defaut : detectee automatiquement, pour qu'un agent
        # ne puisse pas masquer son role en oubliant de le declarer.
        [string]$InitiatedBy = (Get-LaunchOrigin),
        [switch]$AssumeYes
    )
    if ($AssumeYes) { return $true }

    $nl = [Environment]::NewLine
    # Decalage vertical si un bandeau d'origine doit etre affiche.
    $off = if ($InitiatedBy) { 40 } else { 0 }
    $bullets = if ($Changes.Count) { ($Changes | ForEach-Object { "   - $_" }) -join $nl } else { '' }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop

        $bg  = [System.Drawing.Color]::FromArgb(22, 27, 34)
        $fg  = [System.Drawing.Color]::FromArgb(230, 237, 243)
        $mut = [System.Drawing.Color]::FromArgb(139, 148, 158)
        $acc = [System.Drawing.Color]::FromArgb(56, 139, 253)

        $form                 = New-Object System.Windows.Forms.Form
        $form.Text            = 'Vigie — autorisation requise'
        $form.StartPosition   = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox     = $false
        $form.MinimizeBox     = $false
        $form.TopMost         = $true
        $form.BackColor       = $bg
        $form.ForeColor       = $fg
        $form.ClientSize      = New-Object System.Drawing.Size(580, (306 + $off))
        # Icone de Vigie plutot que celle de PowerShell : la fenetre doit s'annoncer
        # comme venant de l'application, pas de l'interpreteur qui l'execute.
        try {
            $ico = Join-Path (Get-BackendRoot) 'assets/tray/ok.ico'
            if (Test-Path -LiteralPath $ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }
        } catch { }

        # Bandeau d'origine : visible AVANT tout le reste, car c'est l'information la
        # plus importante si ce n'est pas l'utilisateur qui a declenche l'action.
        $lblOrigin = $null
        if ($InitiatedBy) {
            $lblOrigin           = New-Object System.Windows.Forms.Label
            $lblOrigin.Text      = "Demandé par un agent automatisé : $InitiatedBy" + $nl + "Ce n'est pas toi qui as lancé cette action."
            $lblOrigin.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
            $lblOrigin.ForeColor = [System.Drawing.Color]::FromArgb(210, 153, 34)
            $lblOrigin.BackColor = [System.Drawing.Color]::FromArgb(38, 34, 22)
            $lblOrigin.Padding   = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
            $lblOrigin.Location  = New-Object System.Drawing.Point(24, 16)
            $lblOrigin.Size      = New-Object System.Drawing.Size(532, 44)
        }

        $lblTitle           = New-Object System.Windows.Forms.Label
        $lblTitle.Text      = $Title
        $lblTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        $lblTitle.ForeColor = $fg
        $lblTitle.Location  = New-Object System.Drawing.Point(24, (20 + $off))
        $lblTitle.Size      = New-Object System.Drawing.Size(532, 30)

        $lblBody           = New-Object System.Windows.Forms.Label
        $lblBody.Text      = $Summary
        $lblBody.Font      = New-Object System.Drawing.Font('Segoe UI', 9.5)
        $lblBody.ForeColor = $fg
        $lblBody.Location  = New-Object System.Drawing.Point(24, (56 + $off))
        $lblBody.Size      = New-Object System.Drawing.Size(532, 44)

        $lblChanges           = New-Object System.Windows.Forms.Label
        $lblChanges.Text      = $bullets
        $lblChanges.Font      = New-Object System.Drawing.Font('Segoe UI', 9.5)
        $lblChanges.ForeColor = $fg
        $lblChanges.Location  = New-Object System.Drawing.Point(24, (104 + $off))
        $lblChanges.Size      = New-Object System.Drawing.Size(532, 110)

        $lblUac           = New-Object System.Windows.Forms.Label
        $lblUac.Text      = "Si tu continues, Windows demandera ensuite l'autorisation administrateur." + $nl + "Rien n'est modifié avant cette étape, et tu peux encore refuser."
        $lblUac.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
        $lblUac.ForeColor = $mut
        $lblUac.Location  = New-Object System.Drawing.Point(24, (218 + $off))
        $lblUac.Size      = New-Object System.Drawing.Size(532, 36)

        $btnOk              = New-Object System.Windows.Forms.Button
        $btnOk.Text         = 'Continuer'
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $btnOk.BackColor    = $acc
        $btnOk.ForeColor    = [System.Drawing.Color]::White
        $btnOk.FlatStyle    = 'Flat'
        $btnOk.FlatAppearance.BorderSize = 0
        $btnOk.Size         = New-Object System.Drawing.Size(124, 32)
        $btnOk.Location     = New-Object System.Drawing.Point(432, (260 + $off))

        $btnNo              = New-Object System.Windows.Forms.Button
        $btnNo.Text         = 'Annuler'
        $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $btnNo.BackColor    = [System.Drawing.Color]::FromArgb(33, 38, 45)
        $btnNo.ForeColor    = $fg
        $btnNo.FlatStyle    = 'Flat'
        $btnNo.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(68, 76, 86)
        $btnNo.Size         = New-Object System.Drawing.Size(104, 32)
        $btnNo.Location     = New-Object System.Drawing.Point(318, (260 + $off))

        $controls = @($lblTitle, $lblBody, $lblChanges, $lblUac, $btnOk, $btnNo)
        if ($lblOrigin) { $controls += $lblOrigin }
        $form.Controls.AddRange($controls)
        $form.AcceptButton = $btnOk
        $form.CancelButton = $btnNo          # Echap et la croix ferment en REFUSANT

        # Barre de titre sombre + coins arrondis : coherent avec le reste de Vigie.
        Set-WindowChrome -Handle $form.Handle -DarkTitleBar -RoundedCorners

        $res = $form.ShowDialog()
        $form.Dispose()
        return ($res -eq [System.Windows.Forms.DialogResult]::OK)
    } catch {
        # Pas d'interface graphique (session sans bureau, execution automatisee) :
        # on explique en console et on REFUSE par defaut. Rien ne doit s'elever sans
        # consentement ; utiliser -Yes pour un lancement volontairement automatise.
        Write-Host ""
        if ($InitiatedBy) {
            Write-Host ("Demandé par un agent automatisé : " + $InitiatedBy) -ForegroundColor Yellow
            Write-Host "Ce n'est pas toi qui as lancé cette action." -ForegroundColor Yellow
        }
        Write-Host $Title -ForegroundColor Cyan
        Write-Host $Summary
        if ($bullets) { Write-Host $bullets }
        Write-Host "Interface graphique indisponible : relance avec -Yes pour confirmer." -ForegroundColor Yellow
        return $false
    }
}

# Relance LE MEME script en session elevee en conservant ses parametres, puis
# restitue sa sortie. On ne peut pas rediriger un processus lance avec -Verb RunAs :
# la session elevee ecrit donc dans un journal, qu'on relit ensuite.
# Renvoie le code de retour de la session elevee.
function Invoke-ElevatedSelf {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$LogDir = $env:TEMP
    )
    # -WhatIf ne doit PAS s'appliquer a la relance : c'est le script relance qui doit
    # simuler ses propres operations. Sans -WhatIf:$false, -WhatIf simulerait l'elevation
    # et rien ne s'executerait - on ne verrait donc jamais ce qui allait etre fait.
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name  = [IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $log   = Join-Path $LogDir ('elevated_' + $name + '_' + $stamp + '.log')

    $parts = @('&', (ConvertTo-PSLiteral $ScriptPath))
    foreach ($a in $Arguments) {
        if ($a -like '-*') { $parts += $a } else { $parts += (ConvertTo-PSLiteral ([string]$a)) }
    }
    $cmd = ($parts -join ' ') + ' *> ' + (ConvertTo-PSLiteral $log)

    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-Host "pwsh introuvable." -ForegroundColor Red; return 1 }

    try {
        $proc = Start-Process $pwshPath -Verb RunAs -Wait -PassThru -WindowStyle Hidden -WhatIf:$false -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
    } catch {
        Write-Host ("Elevation refusee ou impossible : " + $_.Exception.Message) -ForegroundColor Yellow
        return 1
    }

    if (Test-Path -LiteralPath $log) {
        Write-Host "----- compte rendu de la session elevee -----"
        Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ }
        Write-Host ("----- journal : " + $log)
    } else {
        Write-Host "Aucune sortie produite par la session elevee." -ForegroundColor Yellow
    }
    return $proc.ExitCode
}
