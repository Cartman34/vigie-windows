<#
    common.ps1 - Bibliotheque partagee du backend. Aucune dependance a Pode.
    Fabriques d'objets (contrat), config, jeton, agregation des sondes (avec
    journalisation par sonde), execution des actions, utilitaires.
#>

<#
    « CE CHEMIN EXISTE-T-IL ? » NE DOIT JAMAIS FAIRE TOMBER UN APPELANT.

    Test-Path LEVE sur un chemin dont les droits sont refuses -- le profil d'un autre
    compte, typiquement. Sous « ErrorActionPreference = Stop », la question emporte alors
    tout le script. Constate deux fois le 29/08 : une sonde entiere en erreur, et une
    relance de trays interrompue, dans les deux cas parce qu'on demandait si un dossier
    existait.

    Un refus d'acces N'EST PAS une reponse a la question posee : on ne sait pas si le
    chemin existe, et « je ne sais pas » se traite comme « non » ici -- on ne peut de
    toute facon rien en faire.

    Regle du depot : un appel systeme qui se repete devient une fonction a nous.
#>
function Test-PathSafe {
    param([string]$Path)
    if (-not $Path) { return $false }
    try { return [bool](Test-Path -LiteralPath $Path -ErrorAction Stop) } catch { return $false }
}

function Get-BackendRoot { Split-Path $PSScriptRoot -Parent }

# LES LIBELLES SONT DISPONIBLES PARTOUT OU common.ps1 L'EST -- c'est-a-dire dans le
# serveur, les sondes, les actions et les travailleurs. Sans ce chargement ici, chaque
# fichier devrait penser a charger i18n.ps1, et celui qui l'oublierait ne casserait
# qu'a l'execution, sur la ligne qui affiche : le pire endroit pour l'apprendre.
# console-ui.ps1 apporte le vocabulaire d'affichage ET, par ricochet, les libelles :
# les deux fichiers sont voisins et l'un charge l'autre. Charger common.ps1 suffit donc
# a tout avoir. Sans cela, un fichier du backend converti a Write-Ok mourait sur
# « terme non reconnu » -- a l'execution, sur sa ligne d'affichage.
$script:_uiLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/console-ui.ps1'
if (Test-Path -LiteralPath $script:_uiLib) { . $script:_uiLib }

# Le secret de compte : sa pose, ses droits, sa relecture mefiante. Ce fichier existait
# depuis le 28/08 sans etre charge nulle part -- du code qu'aucun test ne voyait.
$script:_secretLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/account-secret.ps1'
if (Test-Path -LiteralPath $script:_secretLib) { . $script:_secretLib }

# --- Reperes de l'arborescence ------------------------------------------------
# Le depot contient PLUSIEURS apps (apps/backend, apps/frontend, apps/tray,
# apps/atelier) plus scripts/ et doc/. Ces reperes sont calcules ICI et nulle
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
    # winget (et d'autres outils modernes) emettent de l'UTF-8 ; PowerShell decodait avec
    # la page de code OEM (850) et chaque accent devenait « ├® » -- jusque dans les
    # messages d'erreur montres a l'utilisateur. On force UTF-8 le temps de la capture.
    $avant = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
    try {
        $out = & $File @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        try { [Console]::OutputEncoding = $avant } catch { }
    }
    # winget decore sa sortie de sequences ANSI (surlignage) : illisibles une fois
    # capturees, on les retire. [...lettre = la forme CSI standard.
    $texte = (($out | Out-String).TrimEnd()) -replace "\[[0-9;]*[A-Za-z]", ''
    [pscustomobject]@{ Ok = ($code -eq 0); ExitCode = $code; Output = $texte }
}

# Fusionne des cles dans un fichier JSON d'etat (lecture-fusion-ecriture ATOMIQUE),
# serialise par un mutex nomme derive du fichier : plusieurs ecrivains (actions,
# workers detaches) ne s'ecrasent pas entre eux. Regle : un seul code pour ecrire
# les fichiers de var/cache (netmeasure.json, pkgupdates.json, ...).
function Update-StateJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Set,
        # Profondeur de serialisation. 8 suffit aux etats plats ; un ARBRE (analyse du
        # disque) depasse cette limite et ConvertTo-Json tronque alors en SILENCE.
        [int]$Depth = 8
    )
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
        ($data | ConvertTo-Json -Depth $Depth) | Out-File -FilePath $tmp -Encoding UTF8
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
    param([Parameter(Mandatory)][string[]]$Names, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    $cacheFile = Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'cache' -File 'state-cache.json'
    # TEST-PATHSAFE : sur le var d'un autre compte, Test-Path LEVE au lieu de dire « non ».
    if (-not (Test-PathSafe $cacheFile)) { return }
    try {
        $obj = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $ht = @{}
        foreach ($pp in $obj.PSObject.Properties) { $ht[$pp.Name] = $pp.Value }
        $changed = $false
        <#
            ON RETIRE AUSSI LES ENTREES PAR COMPTE.

            Une action cite la SONDE (« comptes.probe.ps1 ») ; depuis que les cartes
            personnelles ont une cle par compte, les vraies entrees s'appellent
            « comptes.probe.ps1@fhaza », « comptes.probe.ps1@Famille »... L'invalidation ne
            retirait donc plus rien, et la carte gardait son rendu d'avant la mise a jour.
        #>
        foreach ($k in $Names) {
            foreach ($present in @($ht.Keys)) {
                if ($present -eq $k -or $present -like ($k + '@*')) {
                    $ht.Remove($present); $changed = $true
                }
            }
        }
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
        try { Write-Log -Backend $Backend -Name 'updatelock' -Level 'WARN' -Message (Get-Label 'common.refuse-le-serveur-est' $Etat) } catch { }
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
        Write-Log -Backend $Backend -Name 'updatelock' -Message (Get-Label 'common.obtenu-verrouacl-noautoupdate-tachesdesactivees' $Etat $voie $obtenu $($etatReel.aclLock) $($etatReel.noAutoUpdate) $($etatReel.tasksDisabled))
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
        try { Write-Log -Backend $Backend -Name 'deviceguard' -Level 'WARN' -Message (Get-Label 'common.refuse-le-serveur-est' $Feature) } catch { }
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
        Write-Log -Backend $Backend -Name 'deviceguard' -Message (Get-Label 'common.ecrit-configavant-configapres-actif' $Feature $cible $ecrit $($avant[$Feature].configured) $($apres[$Feature].configured) $($apres[$Feature].running) $hvciCoupeAussi $sauvegarde $(if ($erreurs.Count) { ' erreurs=' + ($erreurs -join ' | ') } else { '' }))
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

# Le PROXY DNS LOCAL, s'il existe : le service Windows dont le processus ecoute sur le
# port 53. Detection par COMPORTEMENT et non par nom -- Acrylic aujourd'hui, n'importe
# quel autre demain, et null s'il n'y en a pas.
function Get-LocalDnsProxyService {
    try {
        $ep = Get-NetUDPEndpoint -LocalPort 53 -ErrorAction Stop | Select-Object -First 1
        if (-not $ep -or -not $ep.OwningProcess) { return $null }
        $svc = Get-CimInstance Win32_Service -Filter "ProcessId=$($ep.OwningProcess)" -ErrorAction Stop |
               Select-Object -First 1
        if ($svc) { return [pscustomobject]@{ Name = $svc.Name; DisplayName = $svc.DisplayName; Pid = $ep.OwningProcess } }
    } catch { }
    return $null
}

# Traduit EN CLAIR un message d'echec de gestionnaire de paquets : ce que ca veut dire,
# et quoi faire. Le message brut de l'outil est du jargon (constate : « technologie
# d'installation differente » n'evoque rien) ; la carte doit porter l'explication.
function Get-PkgFailureAdvice {
    param([string]$Reason)
    if (-not $Reason) { return $null }

    if ($Reason -match 'technologie d.installation est diff|install technology is different') {
        return ("En clair : cette application a été installée à l'origine par un autre canal " +
                "que winget (préinstallée avec Windows, installateur classique, Store...) ; winget refuse de mettre à jour par-dessus. " +
                "Que faire : réinstaller l'application depuis son installateur officiel — l'installation est " +
                "remplacée proprement, les données et profils sont conservés.")
    }
    # « Deja fait » n'est PAS un echec : winget refuse parce que la version installee est
    # deja au moins aussi recente. Vu avec Edge, qui s'etait mis a jour tout seul par son
    # propre canal entre la verification et le clic -- Vigie proposait donc une mise a jour
    # accomplie, puis l'affichait en ECHEC. Reconnaitre ce motif permet de retirer la ligne
    # au lieu de l'accuser.
    if ($Reason -match 'Aucune version de package plus|No newer package versions are available|No applicable (update|upgrade) found|No available upgrade found') {
        return "En clair : c'est déjà fait — la version installée est au moins aussi récente que celle proposée. La liste datait d'avant. Rien à faire."
    }
    if ($Reason -match '0x80070005|acc.s refus|access is denied') {
        return "En clair : Windows a refusé l'accès. Que faire : réessayer ; si ça persiste, un antivirus ou un verrou de fichier bloque l'écriture."
    }
    if ($Reason -match '1603|0x80070643') {
        return "En clair : l'installateur du paquet a échoué (erreur générique MSI). Que faire : redémarrer Windows puis réessayer — c'est la cause la plus fréquente."
    }
    return $null
}

# L'echec dit-il simplement que LE TRAVAIL EST DEJA FAIT ? Alors la ligne n'a plus rien
# a faire dans une liste de mises a jour a proposer.
function Test-PkgFailureIsDone {
    param([string]$Reason)
    if (-not $Reason) { return $false }
    return [bool]($Reason -match 'Aucune version de package plus|No newer package versions are available|No applicable (update|upgrade) found|No available upgrade found')
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

    $sorties = @(); $echecs = @(); $raisons = @{}; $redemarrage = $false; $dernier = 0
    foreach ($p in $liste) {
        # .Replace et non -replace : un identifiant de paquet ('Microsoft.VC++', 'a.b')
        # contient des caracteres que le moteur d'expressions regulieres interpreterait.
        $argv = @($mg.upgOne | ForEach-Object { "$_".Replace('{pkg}', $p) })
        $r = Invoke-Native -File $cmd.Source -Arguments $argv
        $rb = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
        if ($rb) { $redemarrage = $true }
        if (-not ($r.Ok -or $rb)) {
            # La RAISON de l'echec : la derniere ligne parlante de la sortie winget --
            # c'est elle qui dit quoi faire (« technologie d'installation differente... »).
            $ligneUtile = @(("$($r.Output)" -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
            $motif = if ($ligneUtile) { "$ligneUtile".Trim() } else { '' }
            # « Rien de plus recent a installer » n'est pas un echec : le paquet est deja
            # a jour (il s'est mis a jour par son propre canal depuis la verification).
            # Le compter comme rate faisait rougir toute l'operation et affichait une
            # erreur sur un travail qui n'avait rien a faire -- constate avec Edge.
            if (Test-PkgFailureIsDone -Reason $motif) {
                $sorties += ("=== $p (code $($r.ExitCode)) === deja a jour, ignore")
                continue
            }
            $echecs += $p
            if ($motif) { $raisons[$p] = $motif }
        }
        $dernier = $r.ExitCode
        $sorties += ("=== $p (code $($r.ExitCode)) ===" + [Environment]::NewLine + "$($r.Output)")
    }
    return @{ ok = ($echecs.Count -eq 0); supported = $true; exit = $dernier; reboot = $redemarrage
              output = ($sorties -join ([Environment]::NewLine + [Environment]::NewLine))
              count = $liste.Count; failed = @($echecs); reasons = $raisons }
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
    if (-not $started) { return @{ message = "Impossible de lancer l'opération sur $($known.label)."; result = @{ ok = $false } } }
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
<#
    LE REGLAGE DE LA MACHINE SE RANGE SUR LA MACHINE.

    config.local.psd1 s'annonce comme « les reglages propres A CETTE MACHINE »... et vit
    DANS CHAQUE COPIE. Sur un poste de developpement, le depot en avait un (« dev ») et
    l'installation partagee n'en avait pas -- donc « prod ». Une seule machine, deux
    reponses contradictoires a la question « est-ce un poste de developpement ? », et
    l'installation qui repondait NON sur la machine ou tout est developpe.

    Ce qui decrit la MACHINE vit desormais a un seul endroit, hors de toute copie :
    %ProgramData%\Sowapps\Vigie\machine.psd1. Toutes les copies le lisent, aucune ne le
    possede, et un deploiement ne peut plus l'effacer.

    config.local.psd1 garde son role -- ce qui est propre a CETTE COPIE (un port d'essai,
    un chemin d'outillage) -- et reste la couche la plus specifique.
#>
# LE NOM DE LA TACHE SERVEUR, une seule fois. Il vivait dans install-service.ps1, que le
# serveur ne charge pas : la relance ne pouvait donc pas savoir a qui appartient le
# processus qu'elle arrete.
function Get-ServiceTaskName { return 'Vigie - Serveur' }

function Get-ComputerDataRoot {
    <#
        LE DOSSIER DE CET ORDINATEUR : %ProgramData%\Sowapps\Vigie.

        Il ne depend d'AUCUNE installation. C'est ce qui compte : ce qui doit survivre au
        remplacement -- voire a la disparition -- du dossier installe se range ici, jamais
        sous l'installation elle-meme.
    #>
    $base = $env:ProgramData
    if (-not $base) { $base = Join-Path $env:SystemDrive 'ProgramData' }
    return (Join-Path (Join-Path $base 'Sowapps') 'Vigie')
}

function Get-ComputerConfigPath {
    <#
        NE PAS CONFONDRE avec Get-MachineConfigPath, qui existe deja plus bas et designe
        les reglages LIVRES dans le depot (config/<fichier>). J'avais repris son nom : ma
        definition etait ecrasee en silence par la sienne, et l'appel echouait sur un
        parametre obligatoire qui n'etait pas le mien. Deux notions, deux noms.
    #>
    return (Join-Path (Get-ComputerDataRoot) 'machine.psd1')
}

function Get-Config {
    param([string]$Backend = (Get-BackendRoot))
    # Fusion en QUATRE couches (D33), de la plus generale a la plus specifique :
    #   config/common.psd1  ->  apps/<app>/config/config.psd1  ->  machine.psd1  ->  config.local.psd1
    $cfg = @{}
    $commonPath = Join-Path (Get-RepoRoot) 'config/common.psd1'
    if (Test-Path -LiteralPath $commonPath) {
        try { (Import-PowerShellDataFile -Path $commonPath).GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value } }
        catch { throw ("config/common.psd1 illisible : " + $_.Exception.Message) }
    }
    $appCfg = Import-PowerShellDataFile -Path (Join-Path $Backend 'config/config.psd1')
    foreach ($k in $appCfg.Keys) { $cfg[$k] = $appCfg[$k] }
    # LA MACHINE, avant la copie : ce qu'elle declare vaut pour toutes ses installations.
    $computerPath = Get-ComputerConfigPath
    if (Test-Path -LiteralPath $computerPath) {
        try {
            $computerCfg = Import-PowerShellDataFile -Path $computerPath
            foreach ($k in $computerCfg.Keys) { $cfg[$k] = $computerCfg[$k] }
        } catch { throw ("machine.psd1 illisible (" + $computerPath + ") : " + $_.Exception.Message) }
    }
    $localPath = Join-Path $Backend 'config/config.local.psd1'
    if (Test-Path -LiteralPath $localPath) {
        try { $local = Import-PowerShellDataFile -Path $localPath }
        catch { throw ("config.local.psd1 illisible (" + $localPath + ") : " + $_.Exception.Message) }
        foreach ($k in $local.Keys) { $cfg[$k] = $local[$k] }
    }
    $cfg
}

<#
    DECLARER CE QU'EST CETTE MACHINE.

    Ecrit par l'installation et par le deploiement, quand ils partent d'un DEPOT : c'est
    un fait constate au moment ou l'on agit, pas un reglage a saisir. On n'ecrase que les
    cles qu'on apporte -- le reste du fichier appartient a qui l'a ecrit.
#>
function Set-ComputerConfigValue {
    param([Parameter(Mandatory)][hashtable]$Values)
    $path = Get-ComputerConfigPath
    $dir  = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cfg = [ordered]@{}
    if (Test-Path -LiteralPath $path) {
        try {
            $previous = Import-PowerShellDataFile -Path $path
            foreach ($k in $previous.Keys) { $cfg[$k] = $previous[$k] }
        } catch { }
    }
    foreach ($k in $Values.Keys) { $cfg[$k] = $Values[$k] }

    $lines = @('@{')
    $lines += "    # Ce que cette MACHINE est, pour TOUTES ses installations de Vigie."
    $lines += "    # Ecrit par Vigie au deploiement ; modifiable a la main."
    foreach ($k in $cfg.Keys) {
        $v = $cfg[$k]
        $rendered = if ($v -is [bool]) { if ($v) { '$true' } else { '$false' } }
                 elseif ($v -is [int] -or $v -is [long]) { "$v" }
                 else { "'" + ("$v" -replace "'", "''") + "'" }
        $lines += ("    {0} = {1}" -f $k, $rendered)
    }
    $lines += '}'
    [System.IO.File]::WriteAllText($path, ($lines -join [Environment]::NewLine),
                                   (New-Object System.Text.UTF8Encoding($true)))
    return $path
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
# Numero de VERSION du produit : celui de l'installation, ou celui du depot.
#
# UN SEUL numero (D96), et il n'est plus tenu a la main : une archive porte sa marque de
# fabrication, un depot repond par son dernier TAG. Un fichier VERSION a cote des tags
# donnait deux reponses possibles a « quelle version tourne ici ? ».
#
# Une tentative a ete ecartee avant celle-ci : les TICKS de la date du fichier
# (« version 639231069781032063 »), un jeton de changement deguise en version, illisible
# et incomparable. Ce role de jeton revient a Get-AppBuildId, ci-dessous.
function Get-AppVersion {
    param([string]$Backend = (Get-BackendRoot))
    # UNE SEULE definition : la marque de l'installation si elle en a une (archive
    # deployee), sinon ce que git dit du depot. Plus de fichier VERSION (D96).
    $m = Get-BuildStamp -Root (Get-RepoRoot)
    if ($m -and $m.version -and $m.version -ne 'sans version') { return "$($m.version)" }
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

# --- IDENTITE PRECISE D'UNE VERSION : le numero ET le commit -----------------
#
# « Au niveau technique je conseille de prendre la version ET le commit. » Le numero dit
# ce qu'on a voulu livrer ; le commit dit ce qui a REELLEMENT ete livre. Deux
# deploiements du meme v0.1 peuvent differer de vingt commits -- et c'est exactement le
# cas d'un poste de developpement.
#
# La marque est POSEE DANS L'ARCHIVE au moment de la fabrication (fichier BUILD, une
# ligne « version commit date »), parce qu'une installation deployee n'a pas de depot
# git : elle ne peut pas se decrire elle-meme autrement.
# LA VERSION D'UN DEPOT : le dernier TAG, et ce qui a ete commit depuis.
#
# Il n'y a plus qu'UN SEUL numero (D96). Un fichier VERSION tenu a la main a cote des
# tags, c'etait deux numeros a maintenir -- et ils divergeaient : la carte de debogage
# affichait « v0.1 » quand l'installation deployee affichait « v0.1.6 ».
#
# `git describe` dit tout : « v0.1.6 » si on est pile sur le tag, « v0.1.6+6 » s'il y a
# eu six commits depuis. C'est la version PRECISE, et elle ne se maintient pas.
<#
    APPELER GIT ET GARDER SON REFUS.

    Get-GitVersion et Get-GitCommit ecrasaient l'erreur (« 2>$null ») et rendaient $null.
    Le 30/08, la carte annoncait donc « Depot de ce poste : sans version » -- sans dire si
    le dossier etait illisible, si git manquait, ou s'il refusait de travailler dans un
    depot appartenant a quelqu'un d'autre. Trois causes, trois gestes differents, et
    aucune trace pour trancher.

    On garde donc le refus. Il n'interrompt rien -- une version inconnue n'est pas une
    panne -- mais il devient DISABLE : Get-BuildStamp le rapporte, et la carte le dit.
#>
$script:GitLastError = $null
function Invoke-Git {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)
    $script:GitLastError = $null
    $git = (Get-Command git -ErrorAction SilentlyContinue)
    if (-not $git) {
        $script:GitLastError = 'git est introuvable pour ce compte.'
        return $null
    }
    try {
        $err = @()
        $out = & $git.Source -C $Path @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $err += "$_"; } else { $_ }
        }
        if ($err.Count) { $script:GitLastError = (($err | Select-Object -First 2) -join ' ') }
        return @($out | Where-Object { "$_".Trim() })
    } catch {
        $script:GitLastError = $_.Exception.Message
        return $null
    }
}

# Le dernier refus de git, ou $null. Lu juste apres un appel.
function Get-GitLastError { return $script:GitLastError }

function Get-GitVersion {
    param([string]$Path = (Get-RepoRoot))
    try {
        $d = @(Invoke-Git -Path $Path -Arguments @('describe', '--tags') | Select-Object -First 1)[0]
        if (-not $d) { return $null }
        $d = "$d".Trim()
        # git rend « v0.1.6-6-g813205f » : on garde « v0.1.6+6 », plus court a lire, et
        # le commit est deja affiche a cote.
        if ($d -match '^(.*)-(\d+)-g[0-9a-f]+$') { return ($Matches[1] + '+' + $Matches[2]) }
        return $d
    } catch { return $null }
}

function Get-GitCommit {
    param([string]$Path = (Get-RepoRoot), [switch]$Court)
    try {
        $forme = if ($Court) { '%h' } else { '%H' }
        $c = @(Invoke-Git -Path $Path -Arguments @('log', '-1', "--format=$forme") | Select-Object -First 1)[0]
        if ($c) { return "$c".Trim() }
    } catch { }
    return $null
}

# La marque d'une installation : version, commit, date. Lue dans le fichier BUILD s'il
# existe (installation deployee), sinon calculee depuis git (poste de developpement).
function Get-BuildStamp {
    param([string]$Root = (Get-RepoRoot))
    $f = Join-Path $Root 'BUILD'
    if (Test-Path -LiteralPath $f) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            if ($j -and $j.version) { return $j }
        } catch { }
    }
    # Hors archive, la version est celle que git connait : le dernier tag (+ commits).
    # SI GIT REFUSE, ON GARDE SON MOT : « sans version » ne dit pas si le dossier est
    # illisible, si git manque, ou s'il refuse un depot appartenant a un autre compte.
    $v = Get-GitVersion -Path $Root
    $c = Get-GitCommit -Path $Root
    return [pscustomobject][ordered]@{
        version = $(if ($v) { $v } else { 'sans version' })
        commit  = $c
        at      = $null
        source  = 'depot'
        error   = $(if ($v -and $c) { $null } else { Get-GitLastError })
    }
}

<#
    LE DEPOT SOURCE DE CETTE MACHINE, ou $null.

    Trois cas, un seul resultat :
      - on tourne DANS un depot -> c'est lui ;
      - on tourne depuis une installation qui sait d'ou elle vient, et ce depot est
        toujours la -> c'est lui ;
      - machine ordinaire -> $null, et la reference devient la version publiee. C'est la
        bonne question la-bas : personne n'y a de depot.
#>
function Get-LocalRepoPath {
    param([string]$Backend = (Get-BackendRoot))
    <#
        LE DEPOT DE CET ORDINATEUR, ou $null. SANS AUCUN JUGEMENT.

        J'avais mis un garde-fou ici : « pas de depot hors du mode dev ». C'etait faux --
        un poste de PRODUCTION peut tres bien avoir un depot local et deployer depuis lui,
        ou preferer les versions publiees. « dev » et « prod » ne repondent pas a cette
        question-la.

        Celui qui y repond existe deja : UpdateSource. Cette fonction se contente donc de
        dire OU est le depot, s'il y en a un ; le choix appartient a Get-UpdateRoute.
    #>
    $here = Get-RepoRoot
    if (Test-PathSafe (Join-Path $here '.git')) { return $here }
    # LE CHEMIN VIENT DE L'ORDINATEUR, pas du BUILD de la copie : un deploiement reecrit
    # le BUILD, tandis que la declaration de l'ordinateur, elle, ne bouge pas.
    $declared = "$((Get-Config -Backend $Backend).SourcePath)"
    if (-not $declared) { return $null }
    # Le depot a pu etre deplace ou supprime depuis : on verifie qu'il en est encore un.
    if (-not (Test-PathSafe (Join-Path $declared '.git'))) { return $null }
    return $declared
}

<#
    D'OU VIENDRAIT LA PROCHAINE VERSION ?

    UNE SEULE RESOLUTION, POUR TOUT LE MONDE : le bouton « Mettre a jour » l'emprunte pour
    savoir quoi faire, la carte l'emprunte pour savoir a QUOI se comparer. C'est la seule
    facon que la carte reponde a la vraie question -- « est-ce que ce bouton changerait
    quelque chose ? » -- au lieu de se comparer a ce qui lui tombe sous la main.

    Le reglage existe deja : UpdateSource, dans la configuration.
      local   : le depot de cet ordinateur (on fabrique, et on pose le tag)
      release : la derniere version publiee sur GitHub
      clone   : une branche ou un tag precis, rapporte depuis GitHub
      auto    : le depot s'il y en a un, sinon la version publiee -- c'est le defaut

    CE N'EST PAS LA MEME QUESTION QUE « dev ou prod » : un poste de production peut avoir
    un depot local et deployer depuis lui. J'avais confondu les deux.
#>
<#
    LE CLONE DU SERVICE -- son dossier, et d'ou il se synchronise.

    Un service ne travaille JAMAIS dans le depot d'une personne (D112) : il a son propre
    clone, qu'il possede, et fabrique depuis lui. Le chemin est defini ici et nulle part
    ailleurs -- vigie-fetch l'utilisait sous le nom « $travail\depot », en le recomposant.
#>
<#
    POSER LE TAG DE VERSION -- ET CE N'EST PAS AU SERVICE DE LE FAIRE.

    Regle d'origine : on marque une version par un TAG, uniquement au moment d'un
    deploiement, increment fixe. Elle ne change pas -- « moi je marque rien, le
    deploiement actuel en dev marque une version et la pousse ».

    Ce qui change, c'est QUI l'execute. Un tag pose par un compte de service n'a pas
    d'auteur, son push n'a pas d'identifiants, et git refuse d'ecrire dans le depot d'une
    personne (D112). L'action « tag-version » appelle donc cette fonction DANS LA SESSION
    du demandeur, sous son compte, dans son depot.

    Le calcul du prochain numero vit ici, dans la bibliotheque : les deux chemins -- le
    bouton et la ligne de commande -- doivent donner le meme.
#>
function Get-NextDeploymentTag {
    param([Parameter(Mandatory)][string]$RepoPath)
    # La base vient du DERNIER TAG : c'est le seul numero que le projet maintient (D96).
    $base = '0.1'
    $last = @(Invoke-Git -Path $RepoPath -Arguments @('describe', '--tags', '--abbrev=0') | Select-Object -First 1)[0]
    if ("$last" -match '^v?(\d+\.\d+)\.\d+$') { $base = $Matches[1] }
    $max = 0
    foreach ($t in @(Invoke-Git -Path $RepoPath -Arguments @('tag', '--list', ("v" + $base + ".*")))) {
        if ("$t" -match ('^v' + [regex]::Escape($base) + '\.(\d+)$')) {
            $x = [int]$Matches[1]
            if ($x -gt $max) { $max = $x }
        }
    }
    return ('v' + $base + '.' + ($max + 1))
}

<#
    LA VERSION QUI SERA POSEE -- pas celle d'ou l'on part.

    « v0.1.33+13 » n'est pas un numero de version : c'est « le tag v0.1.33, plus treize
    commits ». C'est la bonne facon de decrire un depot en cours de route, et la mauvaise
    facon d'annoncer un deploiement -- l'utilisateur lisait « De v0.1.33 vers v0.1.33+13 »
    partout, alors que ce qui allait etre installe est v0.1.34.

    En stage dev, un deploiement POSE un tag (D96) : ces treize commits deviennent une
    version. On annonce donc celle-la. Ailleurs -- stage prod, ou rien a poser -- on
    annonce ce qu'on lit, sans rien promettre.

    Une seule definition, parce que la meme phrase est dite a deux endroits : le journal de
    l'installation et la carte Deploiement.
#>
function Get-IncomingVersion {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Version,
        [string]$RepoPath,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not $Version) { return $Version }
    # « +N » = des commits par-dessus le dernier tag. Sans lui, rien ne sera pose.
    if ($Version -notmatch '^v?\d+\.\d+\.\d+\+\d+$') { return $Version }
    if ((Get-DeclaredStage -Backend $Backend) -ne 'dev') { return $Version }
    if (-not $RepoPath -or -not (Test-PathSafe $RepoPath)) { return $Version }
    $next = $null
    try { $next = Get-NextDeploymentTag -RepoPath $RepoPath } catch { }
    if ($next) { return $next }
    return $Version
}

<#
    DECLARER LE DEPOT DE CONFIANCE POUR GIT, A L'ECHELLE DE L'ORDINATEUR.

    Depuis git 2.35, git refuse d'ouvrir un depot appartenant a quelqu'un d'autre :
    « detected dubious ownership ». L'app serveur tourne sous un compte de service, le
    depot appartient a une personne -- mesure le 30/08, meme la LECTURE est refusee, et
    le clone du service ne pouvait donc pas se creer.

    On leve le refus pour CE chemin, et rien d'autre. Ce n'est pas un droit d'ecriture :
    les ACL ne bougent pas, et le service n'ecrit jamais dans ce depot -- le tag est pose
    dans la session du proprietaire (D112).

    Pose a l'echelle machine, la ou l'ordinateur declare deja d'ou vient son code : la
    declaration et la confiance sont le meme geste.
#>
function Set-GitSafeDirectory {
    param([Parameter(Mandatory)][string]$RepoPath)
    <#
        DEUX CHEMINS, PAS UN.

        Declarer le dossier de travail ne suffit pas : lors d'un CLONE LOCAL, git ouvre
        « <depot>/.git » et c'est ce chemin-la qu'il verifie -- son refus le nomme
        d'ailleurs mot pour mot. Avec la seule entree « <depot> », le clone du service
        restait refuse apres declaration (constate le 30/08, trois deploiements de suite).
    #>
    $rootPath = "$RepoPath".Replace([char]92, [char]47).TrimEnd([char]47)
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory')) |
              ForEach-Object { "$_".Replace([char]92, [char]47).TrimEnd([char]47) }
    $added = $false
    foreach ($wanted in @($rootPath, ($rootPath + '/.git'))) {
        if ($declared -contains $wanted) { continue }
        $null = Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--add', 'safe.directory', $wanted)
        if (Get-GitLastError) { throw (Get-GitLastError) }
        $added = $true
    }
    return $added
}

function New-DeploymentTag {
    param([Parameter(Mandatory)][string]$RepoPath, [switch]$Push)
    $tag = Get-NextDeploymentTag -RepoPath $RepoPath
    # -f absent VOLONTAIREMENT : un tag ne se reecrit pas. S'il existe deja, c'est que ce
    # deploiement a deja eu lieu -- on le dit et on continue.
    $null = Invoke-Git -Path $RepoPath -Arguments @('tag', '-a', $tag, '-m', ("Deploiement du " + (Get-Date -Format 'dd/MM/yyyy HH:mm')))
    $failure = Get-GitLastError
    $pushed = $false
    if (-not $failure -and $Push) {
        # Le tag ne vaut que s'il est partage. L'echec de pousse n'est PAS fatal : un
        # deploiement doit aboutir meme sans reseau.
        $null = Invoke-Git -Path $RepoPath -Arguments @('push', 'origin', $tag)
        $pushed = -not (Get-GitLastError)
    }
    return [pscustomobject][ordered]@{ tag = $tag; posed = (-not $failure); pushed = $pushed; error = $failure }
}

function Get-ServiceClonePath {
    param([string]$Backend = (Get-BackendRoot))
    Join-Path (Join-Path (Get-VarRoot -Backend $Backend) 'update') 'depot'
}

<#
    L'ADRESSE D'OU LE CLONE SE SYNCHRONISE.

    En production : le depot public. Sur un poste de developpement : le depot local, pour
    fabriquer ce qui vient d'etre ecrit sans avoir a le pousser d'abord. Meme mecanisme,
    seule l'adresse change -- c'est un reglage, pas une seconde conception.
#>
function Get-UpdateRemote {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = Get-Config -Backend $Backend
    $remoteUrl = "$($cfg.UpdateRemote)".Trim()
    if ($remoteUrl) { return $remoteUrl }
    $repo = Get-LocalRepoPath -Backend $Backend
    if ($repo) { return $repo }
    return "$($cfg.RepositoryUrl)"
}

<#
    SYNCHRONISER LE CLONE, ET DIRE CE QU'IL CONTIENT.

    « Si ca ne met pas a jour le depot du service avant, ca ne sert a rien : ca doit voir
    les commits du depot de dev. » Exact -- comparer a un clone perime ne compare rien.
    On rafraichit donc AVANT de lire, avec un court repit : depuis un depot local le fetch
    coute quelques centaines de millisecondes, mais une carte ne doit pas le payer a chaque
    affichage. Le bouton « Actualiser » (-Force) le force.

    Rend la marque (version, commit) de la reference visee, ou $null avec l'erreur de git.
#>
function Sync-ServiceClone {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force, [int]$TtlSeconds = 300)
    $cloneDir  = Get-ServiceClonePath -Backend $Backend
    $remoteUrl = Get-UpdateRemote -Backend $Backend
    $wantedRef    = "$((Get-Config -Backend $Backend).UpdateRef)".Trim()
    $stampFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'clone-sync.json'

    if (-not $Force -and (Test-Path -LiteralPath $stampFile)) {
        try {
            $j = Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalSeconds
            if ($age -lt $TtlSeconds -and "$($j.remote)" -eq $remoteUrl) {
                return [pscustomobject][ordered]@{ path = $cloneDir; remote = $remoteUrl; ref = "$($j.ref)"
                                                   version = "$($j.version)"; commit = "$($j.commit)"
                                                   error = $(if ($j.error) { "$($j.error)" } else { $null }) }
            }
        } catch { }
    }

    $failure = $null
    if (-not (Test-PathSafe (Join-Path $cloneDir '.git'))) {
        $parentDir = Split-Path $cloneDir -Parent
        if (-not (Test-Path -LiteralPath $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        $null = Invoke-Git -Path $parentDir -Arguments @('clone', '--quiet', $remoteUrl, $cloneDir)
        $failure = Get-GitLastError
    } else {
        # L'adresse a pu changer (passage dev <-> prod) : on la remet avant de tirer.
        $null = Invoke-Git -Path $cloneDir -Arguments @('remote', 'set-url', 'origin', $remoteUrl)
        $null = Invoke-Git -Path $cloneDir -Arguments @('fetch', '--quiet', '--tags', '--prune', 'origin')
        $failure = Get-GitLastError
    }

    $tagVersion = $null; $headCommit = $null
    if (Test-PathSafe (Join-Path $cloneDir '.git')) {
        # Sans reference imposee, on suit la branche par defaut du remote.
        $target = $(if ($wantedRef) { $wantedRef } else { 'origin/HEAD' })
        $headCommit = @(Invoke-Git -Path $cloneDir -Arguments @('rev-parse', $target) | Select-Object -First 1)[0]
        if (-not $headCommit -and -not $wantedRef) {
            $headCommit = @(Invoke-Git -Path $cloneDir -Arguments @('rev-parse', 'origin/main') | Select-Object -First 1)[0]
        }
        if ($headCommit) {
            $tagVersion = @(Invoke-Git -Path $cloneDir -Arguments @('describe', '--tags', "$headCommit") | Select-Object -First 1)[0]
            if ($tagVersion -and $tagVersion -match '^(.*)-(\d+)-g[0-9a-f]+$') { $tagVersion = ($Matches[1] + '+' + $Matches[2]) }
        } else {
            $failure = Get-GitLastError
        }
    }

    <#
        ON N'ENREGISTRE PAS UN ECHEC POUR CINQ MINUTES.

        Le repit sert a ne pas refaire un fetch reussi a chaque affichage. Un ECHEC, lui,
        se repare souvent d'un geste -- declarer le depot de confiance pour git, par
        exemple : le figer ferait mentir la carte cinq minutes de plus, alors que tout est
        deja rentre dans l'ordre. On le rend, on ne le gele pas.
    #>
    if (-not $failure) {
        try {
            (@{ at = (Get-Date).ToUniversalTime().ToString('o'); remote = $remoteUrl; ref = $wantedRef
                version = $tagVersion; commit = $headCommit; error = $null } | ConvertTo-Json) |
                Set-Content -LiteralPath $stampFile -Encoding UTF8
        } catch { }
    }

    return [pscustomobject][ordered]@{ path = $cloneDir; remote = $remoteUrl; ref = $wantedRef
                                       version = $tagVersion; commit = $headCommit; error = $failure }
}

function Get-UpdateRoute {
    param([string]$Backend = (Get-BackendRoot))
    $choice = 'auto'
    try {
        $c = "$((Get-Config -Backend $Backend).UpdateSource)".Trim().ToLowerInvariant()
        if ($c -in @('auto', 'local', 'release', 'clone')) { $choice = $c }
    } catch { }
    $repo = Get-LocalRepoPath -Backend $Backend
    # « LOCAL » N'EST PLUS UNE VOIE POUR LE SERVICE (D112) : fabriquer dans le depot d'une
    # personne, c'est y ecrire des tags sous une identite de service et se faire refuser
    # par git. Un depot declare devient donc l'ADRESSE du clone, pas le lieu de travail.
    if ($choice -eq 'local') { $choice = 'clone' }
    if ($choice -eq 'auto')  { $choice = $(if ($repo) { 'clone' } else { 'release' }) }
    return [pscustomobject][ordered]@{ route = $choice; repo = $repo }
}

# Ecrit la marque : appele par la fabrication de l'archive, une seule fois.
function Write-BuildStamp {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Version, [string]$Commit)
    $o = [ordered]@{ version = $Version; commit = $Commit
                     at = (Get-Date).ToUniversalTime().ToString('o'); source = 'archive' }
    ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $Root 'BUILD') -Encoding UTF8
}

# L'installation partagee est-elle a jour par rapport a ce depot ? Rend un constat
# lisible, jamais un simple booleen : « pareil », « en retard de 12 commits », « inconnu ».
<#
    L'INSTALLATION PARTAGEE EST-ELLE A JOUR -- ET PAR RAPPORT A QUOI ?

    La reference n'est pas la meme partout, et c'etait tout le defaut : on comparait
    toujours a « Get-RepoRoot », qui EST l'installation quand l'app serveur tourne dedans.

      - un depot existe sur le poste -> reference « depot » : on compare les commits ;
      - sinon -> reference « publiee » : sur une machine ordinaire, la seule chose qui a
        du sens est la derniere version publiee.

    Rien n'est devine : quand on ne peut pas trancher, `same` vaut $null et l'appelant le
    DIT. « Conforme » par defaut est le pire des verdicts -- il rassure sans rien savoir.
#>
function Compare-SharedInstall {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force)
    $installed = Get-SharedInstallPath
    if (-not $installed) { return $null }
    $there   = Get-BuildStamp -Root $installed
    $route   = Get-UpdateRoute -Backend $Backend
    $behind  = $null
    $here    = $null
    $same    = $null
    $reference = 'aucune'
    $remote  = $null

    # ON SE COMPARE A CE QUE LE BOUTON IRAIT CHERCHER, jamais a autre chose.
    if ($route.route -eq 'clone') {
        # ET ON RAFRAICHIT AVANT DE LIRE : comparer a un clone perime ne compare rien.
        $sync = Sync-ServiceClone -Backend $Backend -Force:$Force
        $reference = 'clone'
        $remote = $sync.remote
        # CE QUI SERA POSE, pas « le tag plus N commits » : c'est la version qu'on lira
        # sur l'installation apres le deploiement.
        $aPoser = Get-IncomingVersion -Version "$($sync.version)" -RepoPath $sync.path -Backend $Backend
        $here = [pscustomobject][ordered]@{ version = $(if ($aPoser) { $aPoser } else { 'sans version' })
                                            commit = $sync.commit; at = $null; source = 'clone'
                                            error = $sync.error }
        if ($sync.commit -and $there.commit) {
            if ($sync.commit -eq $there.commit) { $behind = 0; $same = $true }
            else {
                $same = $false
                # Le compte se fait DANS LE CLONE : c'est lui qui a les deux commits.
                $c = @(Invoke-Git -Path $sync.path -Arguments @('rev-list', '--count', ($there.commit + '..' + $sync.commit)) |
                       Select-Object -First 1)[0]
                if ("$c" -match '^\d+$') { $behind = [int]$c }
            }
        }
    } else {
        $published = Get-LatestPublishedVersion -Backend $Backend
        if ($published) {
            $reference = 'publiee'
            $here = [pscustomobject][ordered]@{ version = $published; commit = $null; at = $null
                                                source = 'release'; error = $null }
            $same = (Test-SameVersion -A $published -B "$($there.version)")
        }
    }

    [pscustomobject][ordered]@{
        path = $installed; here = $here; there = $there; behind = $behind
        reference = $reference; repo = $route.repo; remote = $remote; same = $same
    }
}

# Deux numeros designent-ils la meme version ? « v0.1.26 » et « 0.1.26 » : oui.
function Test-SameVersion {
    param([string]$A, [string]$B)
    return (("$A".TrimStart('v', 'V').Trim()) -eq ("$B".TrimStart('v', 'V').Trim()))
}

<#
    LA DERNIERE VERSION PUBLIEE, ou $null.

    Interrogee au plus une fois par demi-journee : la reponse change rarement, et une carte
    ne doit pas dependre du reseau pour s'afficher. Hors ligne, quota GitHub atteint,
    depot prive : on rend $null, et la carte dit « pas encore verifie » plutot que
    d'inventer un verdict.

    L'ECHEC EST ENREGISTRE LUI AUSSI : sans cela, une machine hors ligne rappellerait
    GitHub a chaque affichage.
#>
function Get-LatestPublishedVersion {
    param([string]$Backend = (Get-BackendRoot))
    $f = Get-VarPath -Backend $Backend -Kind 'cache' -File 'published-version.json'
    if (Test-Path -LiteralPath $f) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalHours
            if ($age -lt 12) { return $(if ($j.version) { "$($j.version)" } else { $null }) }
        } catch { }
    }
    $version = $null
    try {
        $repo = "$((Get-Config -Backend $Backend).Repository)"
        if (-not $repo) { $repo = 'Cartman34/vigie-windows' }
        $rep = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/releases/latest') `
                                 -Headers @{ 'User-Agent' = 'Vigie'; 'Accept' = 'application/vnd.github+json' } `
                                 -TimeoutSec 8 -ErrorAction Stop
        if ($rep -and $rep.tag_name) { $version = "$($rep.tag_name)" }
    } catch { }
    try {
        (@{ at = (Get-Date).ToUniversalTime().ToString('o'); version = $version } | ConvertTo-Json) |
            Set-Content -LiteralPath $f -Encoding UTF8
    } catch { }
    return $version
}

<#
    RELANCER L'APP SERVEUR -- UNE SEULE MISE EN OEUVRE.

    Elle vivait dans l'action « server-restart ». La mise a jour en avait besoin aussi, et
    la recopier aurait fait deux chemins pour un seul geste : le jour ou l'un est corrige,
    l'autre ment. Elle est donc ici, et les deux appellent la meme.

    ON NE PEUT PAS SE TUER ET SE RELANCER SOI-MEME : le processus qui meurt n'execute plus
    rien. Un RELANCEUR DETACHE s'en charge -- il arrete le serveur, attend que le port se
    libere, puis demarre le suivant. Il attend le PORT et non un delai : deux serveurs sur
    le meme port, c'est le second qui meurt.

    -Wait : attendre que plus aucune operation ne tienne la machine. Sans limite de temps,
    volontairement -- une operation qui dure a une raison de durer, et l'interrompre est
    precisement ce qu'on veut eviter. C'est ainsi que la mise a jour se relance : elle
    demande la relance en commencant, et le relanceur patiente jusqu'a ce qu'elle ait fini.

    LE PID VIENT DU PORT, pas de $PID : l'appelant n'est pas toujours le serveur. Le
    script de demarrage, lui, est DIT par l'appelant -- c'est celui de l'installation qui
    tourne, pas forcement celui du depot d'ou l'on parle.
#>
<#
    ARRETER L'APP SERVEUR, ET CONSTATER QU'ELLE EST ARRETEE.

    On modifiait ses fichiers pendant qu'elle tournait, et on ne l'arretait qu'apres, au
    moment de remettre la tache en service. On ecrasait donc du code sous un processus
    vivant -- il continuait avec l'ancien en memoire, et le moindre fichier relu en cours
    de route melangeait deux versions.

    UN ARRET SE CONSTATE. Le port se libere, c'est un fait : on l'attend, contrairement a
    un demarrage qu'on ne guette jamais. Et on arrete la TACHE d'abord -- sinon Windows
    la considere en cours d'execution et la relance sous nos pieds.

    Rend $true si plus rien n'ecoute a la fin.
#>
<#
    LE VERROU D'INSTALLATION -- UNE SEULE A LA FOIS.

    Deux installations simultanees se marchent dessus : l'une arrete ce que l'autre vient
    de demarrer, l'une copie pendant que l'autre sauvegarde. C'est imperatif de l'empecher.

    LE VERROU DIT QUI LE TIENT -- numero de processus et heure -- et un verrou dont le
    processus n'existe plus est IGNORE. Sans cela, une installation interrompue
    brutalement condamnerait le poste jusqu'a une suppression a la main, ce qu'on
    s'interdit : ce qui manque manque dans l'installation, jamais dans une commande a
    taper.

    Il vit avec la declaration de l'ordinateur, hors de l'installation partagee : il doit
    survivre a une copie et rester lisible par les deux points d'entree.
#>
function Get-InstallLockPath {
    Join-Path (Split-Path (Get-ComputerConfigPath) -Parent) 'install.lock'
}

function Get-InstallLockHolder {
    $path = Get-InstallLockPath
    if (-not (Test-PathSafe $path)) { return $null }
    $held = $null
    try { $held = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $held -or -not $held.pid) { return $null }
    # LE PROCESSUS EXISTE-T-IL ENCORE ? C'est la seule question qui compte : un verrou
    # orphelin ne protege rien, il bloque.
    $alive = $false
    try { $alive = [bool](Get-Process -Id ([int]$held.pid) -ErrorAction Stop) } catch { }
    if (-not $alive) { return $null }
    return $held
}

function Lock-Install {
    $held = Get-InstallLockHolder
    if ($held) { return $null }
    $path = Get-InstallLockPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $mine = [ordered]@{ pid = $PID; account = (Get-ProcessAccount); at = (Get-Date).ToUniversalTime().ToString('o') }
    ($mine | ConvertTo-Json -Compress) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Unlock-Install {
    # ON NE RETIRE QUE LE SIEN. Retirer celui d'un autre reviendrait a autoriser ce qu'on
    # vient d'interdire.
    $path = Get-InstallLockPath
    if (-not (Test-PathSafe $path)) { return }
    try {
        $held = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($held -and [int]$held.pid -ne $PID) { return }
    } catch { }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

<#
    LE DEPLOIEMENT EST-IL POSSIBLE ? -- des controles rapides, avant d'arreter quoi que
    ce soit.

    On arretait Vigie, puis on decouvrait que la copie ne passait pas : dossier verrouille,
    disque plein. Ces deux questions se posent en quelques millisecondes, et evitent
    d'arreter pour rien.

    On ne cherche pas a prevoir TOUTES les pannes -- seulement celles qui coutent moins a
    verifier qu'a subir. Rend $null si tout va bien, la raison sinon.
#>
function Test-DeploymentPossible {
    param([Parameter(Mandatory)][string]$Destination, [long]$NeededBytes = 0)
    $parent = Split-Path $Destination -Parent
    if (-not (Test-PathSafe $parent)) { return ("dossier d'accueil introuvable : " + $parent) }

    # ECRITURE : on essaie, c'est la seule preuve. Un test de droits mentirait (heritage,
    # redirections, antivirus qui bloque a l'ecriture reelle).
    $probe = Join-Path $parent ('.vigie-write-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Set-Content -LiteralPath $probe -Value 'x' -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch { return ("écriture refusée dans " + $parent + " : " + $_.Exception.Message) }

    <#
        PLACE : DEUX ENDROITS, ET PLUS FORCEMENT LE MEME DISQUE.

        On pose la nouvelle version a destination, et on garde la precedente en
        sauvegarde -- qui vit desormais a l'echelle de la machine, pas sous
        l'installation. Compter « deux fois, sur le disque de destination » etait juste
        tant que les deux etaient au meme endroit ; avec une destination sur un autre
        disque, cela reservait le double la ou il n'en faut qu'un, et rien la ou la
        sauvegarde va reellement s'ecrire.
    #>
    if ($NeededBytes -gt 0) {
        foreach ($lieu in @($parent, (Get-InstallBackupRoot))) {
            try {
                $racine = $lieu
                while ($racine -and -not (Test-Path -LiteralPath $racine)) { $racine = Split-Path $racine -Parent }
                if (-not $racine) { continue }
                $drive = (Get-Item -LiteralPath $racine).PSDrive
                if ($drive -and $null -ne $drive.Free -and $drive.Free -lt $NeededBytes) {
                    return ("espace disque insuffisant sur " + $drive.Name + " : " +
                            (Format-ByteSize -Bytes $drive.Free) + " libres, " +
                            (Format-ByteSize -Bytes $NeededBytes) + " nécessaires")
                }
            } catch { }
        }
    }
    return $null
}

<#
    SAUVEGARDER, VERIFIER, RESTAURER.

    La copie ecrase l'installation en place : si elle echoue a mi-chemin, l'ancienne
    version est deja detruite et on demarrerait une installation incomplete.

    La sauvegarde vit HORS de l'installation partagee -- sinon elle doublerait le volume et
    la sauvegarde suivante la sauvegarderait -- et porte la version qu'elle contient, pour
    qu'on sache ce qu'on restaure. Elle est supprimee des que la copie est verifiee : elle
    n'existe que le temps du risque.
#>
function Get-InstallBackupRoot {
    <#
        HORS DE L'INSTALLATION, TOUJOURS.

        La sauvegarde vivait sous var/ de l'app serveur, c'est-a-dire DANS le dossier
        qu'elle sert a restaurer : le filet etait accroche au trapeze. Trois facons d'y
        perdre : une copie qui ecrase le dossier emporte la sauvegarde avec, une
        desinstallation aussi, et le setup.cmd du dossier installe ne peut pas restaurer
        ce que ce meme dossier contenait.

        Elle vit donc a l'echelle de la MACHINE, la ou vit deja machine.psd1 : le dossier
        source peut disparaitre, l'installation peut etre remplacee, la version
        precedente reste la.
    #>
    Join-Path (Get-ComputerDataRoot) 'backup'
}

function Backup-Install {
    param([Parameter(Mandatory)][string]$Source, [string]$Backend = (Get-BackendRoot))
    if (-not (Test-PathSafe $Source)) { return $null }
    # L'ANCIEN EMPLACEMENT NE SURVIT PAS A UNE INSTALLATION. Il etait sous var/ de l'app
    # serveur ; le laisser la, c'est garder une copie entiere de Vigie que plus rien ne
    # lit et que personne ne pense a effacer. L'installation nettoie, elle est
    # idempotente -- pas de commande a passer a la main.
    $ancien = Join-Path (Get-VarRoot -Backend $Backend) 'backup'
    if (Test-Path -LiteralPath $ancien) {
        Remove-Item -LiteralPath $ancien -Recurse -Force -ErrorAction SilentlyContinue
    }
    $stamp = Get-BuildStamp -Root $Source
    $name = 'installation-' + $(if ($stamp.version) { "$($stamp.version)" -replace '[^\w\.\+-]', '_' } else { 'inconnue' })
    $root = Get-InstallBackupRoot -Backend $Backend
    $dest = Join-Path $root $name
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $dest -Recurse -Force -ErrorAction Stop
    return $dest
}

<#
    LA COPIE EST-ELLE VALIDE ? On ne demande pas si elle « semble » faite : on lit la
    marque de version qu'on attendait et les fichiers sans lesquels Vigie ne demarre pas.
#>
function Test-InstallCopy {
    param([Parameter(Mandatory)][string]$Destination, [string]$ExpectedVersion)
    foreach ($needed in @('apps/backend-pode/start.ps1', 'apps/tray/tray.ps1', 'apps/backend-pode/lib/common.ps1')) {
        if (-not (Test-PathSafe (Join-Path $Destination $needed))) { return ("fichier manquant : " + $needed) }
    }
    if ($ExpectedVersion) {
        $stamp = Get-BuildStamp -Root $Destination
        if (-not (Test-SameVersion -A "$($stamp.version)" -B $ExpectedVersion)) {
            return ("version posée « " + "$($stamp.version)" + " » au lieu de « " + $ExpectedVersion + " »")
        }
    }
    return $null
}

<#
    EXTRAIRE UNE ARCHIVE, ET RENDRE LE DOSSIER QU'ON DEPLOIERA.

    L'archive porte un dossier racine « vigie-<version> » : c'est SON contenu qu'on
    installe, pas un dossier de plus dans Program Files.
#>
function Expand-InstallArchive {
    param([Parameter(Mandatory)][string]$Zip)
    if (-not (Test-PathSafe $Zip)) { throw ("archive introuvable : " + $Zip) }
    $temp = Join-Path $env:TEMP ('vigie-deploy-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $temp -Force
    $roots = @(Get-ChildItem -Path $temp -Directory)
    if ($roots.Count -eq 1) { return $roots[0].FullName }
    return $temp
}

<#
    COPIER VERS L'INSTALLATION PARTAGEE, SANS PERDRE LES REGLAGES DE L'ORDINATEUR.

    Les reglages poses sur cette machine survivent au deploiement : mis de cote, puis
    remis. Les ecraser a chaque livraison serait une regression a chaque mise a jour.

    var/ n'existe pas dans l'installation -- les donnees vivent dans les profils (D97) --
    mais on ne le supprime pas si quelqu'un en a cree un : on ne detruit que ce qu'on sait
    remplacer.
#>
function Copy-InstallFrom {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Source)) { throw ("source introuvable : " + $Source) }

    $kept = $null
    $configDir = Join-Path $Destination 'config'
    if (Test-PathSafe $configDir) {
        $kept = Join-Path $env:TEMP ('vigie-cfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $kept -Force | Out-Null
        foreach ($pattern in @('*.local.*', 'actions.policy.json')) {
            Get-ChildItem -Path $configDir -File -Filter $pattern -ErrorAction SilentlyContinue |
                ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $kept -Force }
        }
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force -ErrorAction Stop

    if ($kept) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Get-ChildItem -Path $kept -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $configDir -Force
        }
        Remove-Item -LiteralPath $kept -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Restore-Install {
    param([Parameter(Mandatory)][string]$Backup, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Backup)) { throw "aucune sauvegarde à restaurer" }
    Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'var' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item -Path (Join-Path $Backup '*') -Destination $Destination -Recurse -Force -ErrorAction Stop
}

function Get-PortListener {
    <#
        QUI ECOUTE SUR CE PORT ? Rend la connexion, ou $null. NE LEVE JAMAIS.

        Get-NetTCPConnection LEVE quand rien n'ecoute -- « No matching
        MSFT_NetTCPConnection objects found » -- alors que « personne n'ecoute » est une
        reponse parfaitement normale, et meme celle qu'on espere quand on vient d'arreter
        l'app serveur. Les appelants l'entouraient donc d'un try/catch vide ; sous
        transcription, l'erreur est quand meme ecrite dans le journal d'installation, en
        anglais, au milieu du recit. Constate le 31/08 : deux pavés rouges dans un
        deploiement qui s'etait parfaitement passe.

        Un appel systeme qui ment sur ce qu'est une erreur s'enveloppe une fois, ici.
    #>
    param([Parameter(Mandatory)][int]$Port)
    $found = $null
    try { $found = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue } catch { }
    if (-not $found) { return $null }
    return @($found)[0]
}

function Stop-ServerApp {
    param([string]$Backend = (Get-BackendRoot), [int]$Port = 0, [int]$TimeoutSec = 30)
    if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }

    try { Stop-ScheduledTask -TaskName (Get-ServiceTaskName) -ErrorAction SilentlyContinue } catch { }
    $held = Get-PortListener -Port $Port
    if ($held) {
        try { Stop-Process -Id ([int]$held.OwningProcess) -Force -ErrorAction Stop } catch { }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-PortListener -Port $Port)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Start-ServerRelauncher {
    param(
        [Parameter(Mandatory)][string]$StartScript,
        [int]$Port = 0,
        [switch]$Wait,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-PathSafe $StartScript)) { throw ("start.ps1 introuvable : " + $StartScript) }
    if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }

    $target = $null
    $c = Get-PortListener -Port $Port
    if ($c) { $target = [int]$c.OwningProcess }
    if (-not $target) { throw ("Aucune app serveur n'ecoute sur le port " + $Port + ".") }

    $pwsh = $null
    try { $pwsh = (Get-Process -Id $PID).Path } catch { }
    if (-not $pwsh) { $pwsh = 'pwsh.exe' }

    # Le dossier des marques d'occupation vient de Get-VarPath, jamais d'un chemin
    # recompose : une seule definition, et elle vit ici.
    $runDir = Get-VarPath -Backend $Backend -Kind 'run'
    $waitBlock = if ($Wait) { @"
`$run = '$runDir'
while (`$true) {
    `$marques = @(Get-ChildItem -LiteralPath `$run -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)
    if (-not `$marques.Count) { break }
    Start-Sleep -Seconds 3
}
"@ } else { '' }

    <#
        LE SERVEUR APPARTIENT A SA TACHE : ON RELANCE LA TACHE.

        Je lancais start.ps1 moi-meme. Resultat le 30/08 : la mise a jour a tue le serveur
        et le successeur n'a jamais tenu -- lance depuis une session elevee, il tournait
        sous LE MAUVAIS COMPTE et mourait avec elle. Vigie est restee morte, tache
        « Ready », port muet.

        La tache, elle, sait ce qu'elle lance : le bon compte, sans session ouverte, avec
        ses droits. On l'arrete et on la redemarre. start.ps1 en direct ne reste que pour
        le cas ou il n'y a pas de tache -- un serveur lance a la main, en developpement.
    #>
    $taskName = Get-ServiceTaskName
    $parTache = $false
    try { $parTache = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction Stop) } catch { }

    $arret = if ($parTache) { @"
try { Stop-ScheduledTask -TaskName '$taskName' -ErrorAction SilentlyContinue } catch { }
try { Stop-Process -Id $target -Force -ErrorAction SilentlyContinue } catch { }
"@ } else { @"
try { Stop-Process -Id $target -Force -ErrorAction SilentlyContinue } catch { }
"@ }

    $demarrage = if ($parTache) { @"
Start-ScheduledTask -TaskName '$taskName'
"@ } else { @"
Start-Process -FilePath '$pwsh' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$StartScript' -WindowStyle Hidden
"@ }

    $script = @"
Start-Sleep -Milliseconds 400
$waitBlock
$arret
`$fin = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt `$fin) {
    `$occupe = `$null
    try { `$occupe = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop } catch { }
    if (-not `$occupe) { break }
    Start-Sleep -Milliseconds 300
}
$demarrage
"@

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pwsh
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $script)) {
        [void]$psi.ArgumentList.Add($a)
    }
    [void][System.Diagnostics.Process]::Start($psi)
    return $target
}

# --- Journalisation ---------------------------------------------------------
# --- Donnees d'execution : apps/<app>/var/ (convention Symfony) -----------------
# Tout ce que l'app GENERE ou gere en local vit sous var/ : cache, journaux, etat,
# secrets generes. Rien de tout cela n'est versionne.
# Ces chemins sont ecrits ICI et nulle part ailleurs : ils etaient auparavant
# recomposes a la main dans 8 fichiers (actions, sondes, workers).
# L'installation est-elle INSCRIPTIBLE par le compte qui execute ? (D65)
#
# Deux situations, et une seule regle pour les distinguer : l'ecriture reelle.
#   - depot de DEV (ou installation dans un espace personnel) : var/ s'ecrit sur place,
#     comme depuis toujours -- rien ne change ;
#   - installation PARTAGEE (Program Files) : un compte standard n'y ecrit pas. Ses
#     donnees d'execution vont alors dans son profil, ou il est chez lui.
# On ne DEVINE pas d'apres le chemin : on tente d'ecrire, une fois, et on retient.
$script:VarRacineCache = $null
function Get-VarRoot {
    param([string]$Backend = (Get-BackendRoot))
    # LE CACHE EST PAR APPLICATION, pas global.
    #
    # Il ne tenait aucun compte de son argument : le premier appel figeait LA racine, et
    # tous les suivants recevaient celle-la quel que soit le -Backend demande. Le tray
    # ecrivait donc son battement de coeur dans le var/ du serveur, ou l'emetteur d'ordres
    # ne le cherchait pas -- « relance impossible, tray deja arrete » alors qu'il tournait
    # (constate le 28/08). Chaque app garde ses fichiers sous SON var/ (D33) : le cache
    # doit donc etre indexe par application.
    if ($null -eq $script:VarRacineCache) { $script:VarRacineCache = @{} }
    $cle = "$Backend".TrimEnd([char]92, [char]47).ToLowerInvariant()
    if ($script:VarRacineCache.ContainsKey($cle)) { return $script:VarRacineCache[$cle] }

    # INSTALLEE DANS PROGRAM FILES : les donnees vont dans le profil du compte, JAMAIS
    # a cote du programme. Le serveur tourne eleve, il POURRAIT ecrire la -- et c'est
    # precisement le piege : tous les comptes partageraient alors le meme jeton, le meme
    # cache et les memes reglages, alors que chacun doit avoir les siens (D65). Le test
    # d'ecriture ci-dessous ne verrait rien, puisqu'il reussirait.
    $programmes = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($p in $programmes) {
        if ("$Backend".StartsWith("$p", [StringComparison]::OrdinalIgnoreCase)) {
            $script:VarRacineCache[$cle] = Join-Path (Get-UserConfigDir) 'var'
            return $script:VarRacineCache[$cle]
        }
    }

    # Ailleurs (depot de developpement, dossier personnel) : sur place si on peut y
    # ecrire, sinon dans le profil.
    $surPlace = Join-Path $Backend 'var'
    $ok = $false
    try {
        if (-not (Test-Path -LiteralPath $surPlace)) {
            New-Item -ItemType Directory -Path $surPlace -Force -WhatIf:$false | Out-Null
        }
        $temoin = Join-Path $surPlace ('.ecriture-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        [IO.File]::WriteAllText($temoin, 'x')
        Remove-Item -LiteralPath $temoin -Force -ErrorAction SilentlyContinue
        $ok = $true
    } catch { $ok = $false }
    $script:VarRacineCache[$cle] = if ($ok) { $surPlace } else { Join-Path (Get-UserConfigDir) 'var' }
    return $script:VarRacineCache[$cle]
}

<#
    UNE CARTE EST-ELLE LA MEME POUR TOUT LE MONDE ?

    La plupart le sont : l'espace disque, les mises a jour, le pare-feu ne dependent pas de
    qui regarde. Mais la carte des comptes ecrit « (vous) » a cote d'un nom -- et ce rendu
    part dans state-cache.json, qui est COMMUN. Le premier a ouvrir Vigie y laissait donc
    son « vous », servi ensuite a tous les autres.

    Une sonde le declare dans son module.psd1 :  PerAccount = $true.

    La declaration vaut mieux qu'une devinette : on ne peut pas lire dans un rendu s'il
    depend de la personne, et le supposer pour toutes couterait un recalcul par compte pour
    rien. check-probes verifie que celles qui parlent du demandeur l'ont declare.
#>
$script:ProbePerAccount = @{}
function Test-ProbeIsPerAccount {
    param([Parameter(Mandatory)][string]$ProbeFile)
    $folder = Split-Path $ProbeFile -Parent
    if ($script:ProbePerAccount.ContainsKey($folder)) { return $script:ProbePerAccount[$folder] }
    $answer = $false
    try {
        $decl = Join-Path $folder 'module.psd1'
        if (Test-Path -LiteralPath $decl) {
            $d = Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop
            $answer = [bool]$d.PerAccount
        }
    } catch { }
    $script:ProbePerAccount[$folder] = $answer
    return $answer
}

<#
    LA CLE DU CACHE : le nom de la sonde, et le compte quand le rendu en depend.

    « comptes.probe.ps1@Famille » et « comptes.probe.ps1@fhaza » cohabitent dans le meme
    fichier sans se marcher dessus. Sans demandeur identifie, la cle est « @? » : une
    session anonyme a son entree a elle, ou personne n'est « vous ».
#>
function Get-ProbeCacheKey {
    param([Parameter(Mandatory)][string]$ProbeFile, [string]$Account)
    $leaf = Split-Path $ProbeFile -Leaf
    if (-not (Test-ProbeIsPerAccount -ProbeFile $ProbeFile)) { return $leaf }
    return ($leaf + '@' + $(if ($Account) { $Account } else { '?' }))
}

function Get-VarPath {
    param(
        [string]$Backend = (Get-BackendRoot),
        <#
            LA RACINE D'UN AUTRE COMPTE, quand on doit ecrire ailleurs que chez soi.

            Le var d'une installation dans Program Files vit dans le profil du compte qui
            EXECUTE (D65) : celui du service pour l'app serveur. L'installation, elle,
            tourne sous la personne qui a clique -- elle nettoyait donc SON cache, pendant
            que la carte continuait de lire celui du service. Get-AccountVarRoot donne la
            bonne racine ; elle passe par ici plutot que d'etre recomposee a la main.
        #>
        [string]$VarRoot,
        # 'history' : series de mesures (doc/archives/conception/historique-cible.md). Distinct de
        # 'cache' : un cache perdu se recalcule, un historique perdu ne se recalcule pas.
        # 'run' : etat VIVANT, valable le temps d'un processus (marqueurs de tache de
        # fond). Il ne se sauvegarde pas et ne se relit pas apres un redemarrage.
        [Parameter(Mandatory)][ValidateSet('cache','log','secrets','history','run')][string]$Kind,
        [string]$File
    )
    $dir = Join-Path $(if ($VarRoot) { $VarRoot } else { Get-VarRoot -Backend $Backend }) $Kind
    # TEST-PATHSAFE, ET UNE CREATION QUI NE CRIE PAS. Sur le var d'un AUTRE compte,
    # Test-Path LEVE au lieu de repondre « non » et New-Item ecrit quatre pavés rouges --
    # alors qu'on venait seulement lire un chemin pour en effacer un fichier. Un appelant
    # qui n'a pas le droit s'en apercevra en n'y trouvant rien, sans polluer le journal.
    if (-not (Test-PathSafe $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false -ErrorAction SilentlyContinue | Out-Null
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
        # UNE LIGNE VIDE EST UNE LIGNE. Le journal d'installation relaie ce qu'affiche
        # chaque sous-script, blancs de mise en page compris : sans cette autorisation,
        # chaque respiration produisait un « Cannot bind argument to parameter Message »
        # dans le transcript -- du bruit rouge sur une installation qui se passait bien.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [string]$Level = 'INFO',
        [string]$Name  = 'app',
        [string]$Backend = (Get-BackendRoot),
        # Ecrire SANS reafficher : la ligne est deja a l'ecran, on ne veut que la garder.
        [switch]$NoEcho
    )
    $dir  = Get-LogDir -Backend $Backend
    $file = Join-Path $dir ($Name + '_' + (Get-Date -Format 'yyyyMMdd') + '.log')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $file -Value $line -Encoding UTF8 } catch { }

    # L'ECRAN ET LE FICHIER NE DISENT PAS LA MEME CHOSE, et c'est voulu. Le fichier garde
    # l'horodatage et le niveau : c'est lui qu'on relit des semaines apres. L'ecran, lui,
    # parle la langue de tous les autres scripts (scripts/lib/console-ui.ps1).
    #
    # POURQUOI : le 28/08, une etape d'installation a echoue ; son ERROR est sorti en gris
    # au milieu de vingt lignes grises, et l'utilisateur ne pouvait pas le voir. Un niveau
    # de journal qui ne se distingue pas a l'ecran ne sert a rien.
    #
    # Le repli existe parce que common.ps1 est charge par des scripts qui n'ont pas besoin
    # de l'affichage (le serveur, les sondes) : on ne leur impose pas la dependance.
    if ($NoEcho) { return }
    $hasUi = [bool](Get-Command Write-Fail -ErrorAction SilentlyContinue)
    switch ($Level) {
        'ERROR' { if ($hasUi) { Write-Fail $Message } else { Write-Host $line -ForegroundColor Red } }
        'WARN'  { if ($hasUi) { Write-Warn $Message } else { Write-Host $line -ForegroundColor Yellow } }
        default { if ($hasUi) { Write-Info $Message } else { Write-Host $line } }
    }
}


# =============================================================================
#  QUI PARLE AU SERVEUR ? -- secret de compte, ticket d'ouverture, cookie de session
# =============================================================================
#
# LE PROBLEME. Un seul serveur eleve repond a toute la machine. Sans moyen de savoir
# QUEL compte est derriere une requete, il ne peut ni refuser une action a un compte
# standard, ni servir a chacun ses propres reglages : tout le monde herite de ceux du
# compte qui fait tourner le serveur. C'est ce qui se passe aujourd'hui.
#
# TROIS OBJETS, ET ON NE LES CONFOND PAS (conception, section Q1) :
#
#   secret du compte   durable   dans SON profil, ACL explicite, lui seul le lit
#   ticket d'ouverture 30 s      passe en URL par le tray, consomme une seule fois
#   cookie de session  navigateur  identifie la page ensuite ; HttpOnly, donc hors de
#                                  portee du JavaScript de la page
#
# POURQUOI CE DETOUR plutot que de mettre le secret dans l'URL. Une URL se retrouve dans
# l'historique du navigateur, dans les journaux, dans un copier-coller. Un ticket qui
# meurt en 30 secondes et ne sert qu'une fois n'a aucune valeur une minute plus tard.
#
# CE QUE LE SERVEUR NE STOCKE PAS : le secret. Il n'en garde rien -- il RELIT le fichier
# du compte au moment de verifier. Etant eleve, il en a le droit ; et il n'y a donc
# aucune copie a proteger, a synchroniser, ou a revoquer.

<#
    RELANCER LES TRAYS DE TOUS LES COMPTES.

    Apres une mise a jour, seul le tray qui l'a lancee repartait. Les autres continuaient
    de tourner avec le code d'AVANT, charge en memoire depuis une installation qui vient
    d'etre remplacee sous leurs pieds -- jusqu'a la prochaine ouverture de session.

    On depose donc un ordre « restart » dans le dossier de chaque compte : leur tray le
    lit dans la seconde et se relance seul. Aucun droit particulier n'est requis d'eux,
    et celui qui ne tourne pas n'a rien a faire -- il demarrera avec le nouveau code.

    Le serveur est eleve : il peut ecrire dans le profil des autres. Un tray qui n'a
    jamais tourne n'a pas de dossier d'ordres, et on ne lui en cree pas : rien a relancer.
#>
<#
    ARRETER ET DEMARRER LES APP CLIENTES -- PAR LEUR TACHE, TOUJOURS.

    C'est la tache qui sait sous quelle identite lancer, et pour l'app cliente d'un AUTRE
    compte c'est le seul moyen : la demarrer en direct demanderait ses identifiants.

    UNE TACHE D'APP CLIENTE EST INTERACTIVE : Windows refuse de la demarrer pour un compte
    sans session. « Ouverte » ne veut pas dire « active » -- un compte laisse par
    « Changer d'utilisateur » garde une session DECONNECTEE, et sa tache y demarre tres
    bien (verifie le 30/08, deux sessions coexistaient). Un compte sans session n'est donc
    pas une erreur : son app cliente repartira a sa prochaine ouverture, avec le nouveau
    code.
#>
function Stop-TrayTasks {
    param([string]$Backend = (Get-BackendRoot))
    $stopped = @()
    foreach ($c in @(Get-EnabledAccounts -Backend $Backend)) {
        if (-not $c.task) { continue }
        try { Stop-ScheduledTask -TaskName "$($c.task)" -ErrorAction Stop } catch { }
        $stopped += [pscustomobject]@{ name = "$($c.name)"; task = "$($c.task)" }
    }
    return $stopped
}

function Start-TrayTasks {
    param([Parameter(Mandatory)]$Accounts)
    $started = @()
    foreach ($a in @($Accounts)) {
        if (-not $a.task) { continue }
        try {
            Start-ScheduledTask -TaskName "$($a.task)" -ErrorAction Stop
            $started += "$($a.name)"
        } catch { }
    }
    return $started
}

<#
    LES APP CLIENTES LANCEES HORS TACHE.

    Arreter la tache ne tue pas ce qu'elle n'a pas lance : une app cliente demarree a la
    main -- essai de developpement -- continuerait de tourner sur des fichiers qu'on
    remplace. On balaie donc ce qui reste, en visant ce qui EXECUTE le script de l'app
    cliente, quel que soit le compte : l'installation est elevee, elle les voit tous.

    Rend le nombre de processus arretes.
#>
function Stop-StandaloneTrays {
    $killed = 0
    $leaf = 'tray.ps1'
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
        $line = "$($p.CommandLine)"
        if (-not $line -or $line -notmatch [regex]::Escape($leaf)) { continue }
        if ([int]$p.ProcessId -eq $PID) { continue }
        try { Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction Stop; $killed++ } catch { }
    }
    return $killed
}

function Send-TrayRestartToAll {
    # « Sauf moi » veut dire « sauf CELUI QUI DEMANDE » : son app cliente vient de faire la
    # mise a jour et se relance elle-meme. Le compte du service, lui, n'a pas d'app cliente.
    # Personne d'identifie : on previent TOUT LE MONDE. C'est le bon defaut -- une app
    # cliente relancee pour rien redemarre en deux secondes ; une qui garde l'ancien code
    # ment jusqu'a la prochaine ouverture de session.
    param([string]$Except = (Get-RequesterAccount))
    $touches = @()
    # Les comptes qui ont une app cliente : ceux dont la tache de demarrage existe.
    $avecAppCliente = @()
    try { $avecAppCliente = @(Get-EnabledAccounts | ForEach-Object { "$($_.name)" }) } catch { }
    $users = Join-Path $env:SystemDrive 'Users'
    if (-not (Test-Path -LiteralPath $users)) { return $touches }
    foreach ($profil in @(Get-ChildItem -LiteralPath $users -Directory -ErrorAction SilentlyContinue)) {
        if ($Except -and $profil.Name -ieq $Except) { continue }
        # UN PROFIL QU'ON NE PEUT PAS LIRE N'EST PAS UNE ERREUR. Depuis une session sans
        # droits, le simple test d'existence sur le dossier d'un autre compte LEVE -- et
        # sous « ErrorActionPreference = Stop », il emporte toute la fonction. Le serveur
        # est eleve et n'a pas ce souci, mais une fonction ne doit pas dependre de qui
        # l'appelle : on passe au suivant, en silence.
        # AVOIR UN DOSSIER D'ORDRES NE VEUT PAS DIRE AVOIR UNE APP CLIENTE. Le compte du
        # service en a un -- l'app SERVEUR y depose ses marques d'occupation -- et il a
        # donc recu un ordre « restart » que personne ne lira jamais : « Relance demandee
        # aux autres comptes : Famille, fhaza, VigieService » (constate le 30/08).
        #
        # Ce qui prouve qu'un compte a une app cliente, c'est SA TACHE DE DEMARRAGE.
        if ($avecAppCliente -notcontains $profil.Name) { continue }
        $run = $null
        try { $run = Get-AccountRunDir -Account $profil.Name } catch { continue }
        if (-not $run) { continue }
        if (-not (Test-PathSafe $run)) { continue }
        # ON N'A PAS A SAVOIR SI LE TRAY TOURNE. Un tray efface les ordres en attente a son
        # demarrage : un ordre depose pour un tray absent ne survit pas a son retour, et
        # celui-ci demarre de toute facon avec le nouveau code. Verifier son battement de
        # coeur ajoutait un acces disque et une condition pour rien.
        try {
            Set-Content -LiteralPath (Join-Path $run 'restart') -Value 'update' -Encoding ASCII -NoNewline
            $touches += $profil.Name
        } catch { }
    }
    return $touches
}

# La racine des donnees d'un AUTRE compte. Le chemin etait recopie a la main dans le
# diagnostic ; une seule definition vaut mieux qu'un accord entre deux copies.
<#
    LE COMPTE SOUS LEQUEL TOURNE L'APP SERVEUR.

    Il etait ecrit dans install-service.ps1, qui n'est pas la bibliotheque : tout ce qui
    doit ecrire ou lire CHEZ LUI -- l'installation qui nettoie le cache de la carte, par
    exemple -- aurait recopie le nom. Une seule definition, comme pour le nom de la tache.
#>
function Get-ServiceAccountName { 'VigieService' }

function Get-AccountVarRoot {
    param([Parameter(Mandatory)][string]$Account)
    $profil = Join-Path $env:SystemDrive (Join-Path 'Users' $Account)
    if (-not (Test-PathSafe $profil)) { return $null }
    return (Join-Path (Join-Path (Join-Path (Join-Path $profil 'AppData') 'Local') 'Sowapps') 'Vigie/var')
}

<#
    LE COMPTE QUI EXECUTE CE PROCESSUS. Pas « la personne ».

    La distinction n'avait aucune importance tant que l'app serveur tournait sous le
    compte de quelqu'un : $env:USERNAME tombait juste PAR ACCIDENT. Depuis qu'elle tourne
    en service sous « VigieService », chaque endroit qui disait $env:USERNAME pour dire
    « la personne devant l'ecran » designe le service -- et le 29/08 la carte Comptes a
    donc affiche « VOUS » sur VigieService, et l'a sorti de la liste des comptes
    techniques.

    Deux notions, deux fonctions, plus jamais melangees :
      - Get-ProcessAccount   : QUI EXECUTE. Vrai pour l'app cliente (elle EST la personne)
                               et pour les scripts lances a la main.
      - Get-ActionRequester  : QUI DEMANDE, lu dans le cookie de session. C'est la personne,
                               cote app serveur, et c'est ce qu'il faut presque toujours.

    check-probes refuse desormais $env:USERNAME partout ailleurs : le prochain qui ecrira
    ce raccourci se le verra dire avant de livrer, pas trois semaines plus tard.
#>
function Get-ProcessAccount {
    return "$env:USERNAME"
}

# Le SID d'un compte local, par son nom. Rend $null si le compte n'existe pas.
function Get-AccountSid {
    param([Parameter(Mandatory)][string]$Account)
    try { return (New-Object System.Security.Principal.NTAccount($Account)).Translate(
                    [System.Security.Principal.SecurityIdentifier]).Value } catch { return $null }
}

<#
    Le secret presente est-il bien celui de ce compte ?

    On RELIT le fichier du compte, avec sa verification d'ACL : si ses droits ont bouge
    depuis qu'il a ete pose, Get-AccountSecret leve et on refuse. Un secret qu'un tiers a
    pu lire ne vaut rien, et le refuser bruyamment vaut mieux que l'accepter en silence.
#>
function Test-AccountSecret {
    param(
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][string]$Secret
    )
    if (-not $Secret) { return $false }
    $varRoot = Get-AccountVarRoot -Account $Account
    if (-not $varRoot) { return $false }
    $sid = Get-AccountSid -Account $Account
    if (-not $sid) { return $false }
    $known = $null
    try { $known = Get-AccountSecret -VarRoot $varRoot -OwnerSid $sid } catch {
        try { Write-Log -Level 'ERROR' -Name 'session' -Message ("Secret du compte " + $Account + " refuse : " + $_.Exception.Message) } catch { }
        return $false
    }
    if (-not $known) { return $false }
    return ($known -ceq $Secret)
}

# --- Ou vivent tickets et sessions ------------------------------------------------------
#
# Dans le var DU SERVEUR, sous une ACL fermee : un identifiant de session est une
# information d'authentification au meme titre qu'un secret. Le dossier est pose avec la
# meme fonction que les secrets, donc avec la meme rigueur.
function Get-SessionStorePath {
    param([string]$Kind = 'sessions', [string]$Backend = (Get-BackendRoot))
    $dir = Join-Path (Join-Path (Get-VarRoot -Backend $Backend) 'auth') $Kind
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
            Set-SecretFolderAcl -Path (Split-Path $dir -Parent) -OwnerSid $me
        } catch { }
    }
    return $dir
}

# L'AGE SE COMPTE EN SECONDES, PAS EN DATES. Une date ecrite en JSON revient en objet
# DateTime, deja convertie dans la culture locale : « 08/28/2026 20:43:31 ». La reparser
# echouait, l'exception passait inapercue, et l'age restait vide -- autrement dit un
# ticket n'expirait JAMAIS. Un nombre n'a ni culture ni type surprise.
function Get-EpochSeconds {
    return [double]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0)
}

function New-RandomId {
    $bytes = [byte[]]::new(24)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
}

# Un ticket d'ouverture, valable une fois et trente secondes.
function New-OpenTicket {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $id = New-RandomId
    $file = Join-Path (Get-SessionStorePath -Kind 'tickets' -Backend $Backend) ($id + '.json')
    (@{ account = $Account; at = (Get-EpochSeconds) } | ConvertTo-Json -Compress) |
        Out-File -FilePath $file -Encoding UTF8
    return $id
}

# Consomme un ticket : rend le compte, ou $null. Le fichier est SUPPRIME dans tous les
# cas -- un ticket presente une fois, valide ou perime, ne doit pas pouvoir resservir.
function Use-OpenTicket {
    param([Parameter(Mandatory)][string]$Ticket, [string]$Backend = (Get-BackendRoot))
    if ($Ticket -notmatch '^[A-Za-z0-9]{8,64}$') { return $null }
    $file = Join-Path (Get-SessionStorePath -Kind 'tickets' -Backend $Backend) ($Ticket + '.json')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $data = $null
    try { $data = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { }
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    if (-not $data) { return $null }
    if (((Get-EpochSeconds) - [double]$data.at) -gt 30) { return $null }
    return "$($data.account)"
}

# Ouvre une session et rend son identifiant, celui que portera le cookie.
<#
    L'URL D'OUVERTURE : LE SEUL CHEMIN POUR EN DEMANDER UNE.

    Le geste est toujours le meme -- lire le secret de SON compte, le presenter au
    serveur, recevoir une adresse a usage unique -- et il s'ecrivait a deux endroits :
    dans l'app cliente et dans l'outil de questions. Deux exemplaires, donc deux
    comportements a tenir : ils n'avaient deja pas le meme delai d'attente.

    ON NE PEUT DEMANDER QUE POUR SOI. Le secret vit dans le profil du compte, avec une ACL
    explicite : personne d'autre ne le lit, et c'est precisement ce qui fait qu'il prouve
    une identite. Pour ouvrir une session au nom d'un autre compte, il faut etre dans SA
    session.

    Rend $null si quoi que ce soit echoue -- l'appelant ouvre alors la page sans
    identification plutot que de refuser d'ouvrir.
#>
function Get-OpenUrl {
    param(
        [string]$Account = (Get-ProcessAccount),
        [string]$BaseUrl,
        [int]$TimeoutSec = 10,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not $BaseUrl) { $BaseUrl = Get-AppUrl -Backend $Backend }
    $BaseUrl = $BaseUrl.TrimEnd('/')
    $secret = $null
    try {
        $secret = Get-AccountSecret -VarRoot (Get-AccountVarRoot -Account $Account) `
                                    -OwnerSid (Get-AccountSid -Account $Account) -Create
    } catch { return $null }
    if (-not $secret) { return $null }
    $body = @{ account = $Account; secret = $secret } | ConvertTo-Json -Compress
    $reply = $null
    try {
        $reply = Invoke-RestMethod -Method Post -Uri ($BaseUrl + '/api/v1/session/ticket') `
                                   -ContentType 'application/json' -Body $body `
                                   -Headers @{ Origin = $BaseUrl } -TimeoutSec $TimeoutSec
    } catch { return $null }
    if (-not ($reply -and $reply.ok -and $reply.ticket)) { return $null }
    return ($BaseUrl + '/?t=' + $reply.ticket)
}

function New-AccountSession {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $id = New-RandomId
    $file = Join-Path (Get-SessionStorePath -Kind 'sessions' -Backend $Backend) ($id + '.json')
    (@{ account = $Account; at = (Get-EpochSeconds) } | ConvertTo-Json -Compress) |
        Out-File -FilePath $file -Encoding UTF8
    return $id
}

<#
    LE COMPTE DERRIERE UNE SESSION, ou $null.

    UNE SESSION NE PERIME PAS. Elle expirait au bout de 24 heures : passe ce delai, la
    fenetre restait ouverte mais n'appartenait plus a personne -- « vous » disparaissait
    de la carte des comptes et les actions ne savaient plus qui demandait, sans que rien
    ne l'annonce. Or ce qui est jetable, c'est l'URL D'OUVERTURE : 30 secondes, une seule
    presentation. Ce qu'elle laisse, l'identite, doit durer, sinon il faut en redemander
    une a chaque fois pour un poste ou la personne n'a pas change.

    Une session se termine autrement : le fichier est supprime, ou le compte cesse d'etre
    active.
#>
function Get-SessionAccount {
    param([Parameter(Mandatory)][string]$SessionId, [string]$Backend = (Get-BackendRoot))
    if ($SessionId -notmatch '^[A-Za-z0-9]{8,64}$') { return $null }
    $file = Join-Path (Get-SessionStorePath -Kind 'sessions' -Backend $Backend) ($SessionId + '.json')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $data = $null
    try { $data = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { return $null }
    return "$($data.account)"
}

# --- Fabriques d'objets du contrat -----------------------------------------
# Nom de processus -> nom LISIBLE, celui que Windows affiche lui-meme.
#
# « csrss » ne dit rien a personne (signale par l'utilisateur le 25/08). Le vrai nom est
# dans les informations de version de l'executable (FileDescription) : « Processus
# d'execution client-serveur », « Explorateur Windows », « Google Chrome ». On le lit sur
# le FICHIER et non sur le processus : les processus proteges (csrss, lsass) refusent
# l'acces a leur module principal, alors que leur fichier se lit sans probleme.
#
# Le nom technique n'est pas jete : il est conserve entre parentheses, parce que c'est lui
# qu'on retrouve dans le Gestionnaire des taches.
$script:AppNameCache = @{}
function Get-AppDisplayName {
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [string]$Path,
        # Sans -Complet, on ne rend que le nom lisible (pour une valeur de champ courte).
        [switch]$Complet
    )
    $cle = $ProcessName.ToLower()
    if (-not $script:AppNameCache.ContainsKey($cle)) {
        $desc = $null
        $exe = $Path
        if (-not $exe) {
            # Processus protege : son chemin est refuse, mais un binaire systeme du meme
            # nom se lit tres bien. On ne DEVINE pas : on verifie que le fichier existe.
            $candidat = Join-Path $env:SystemRoot ("System32\" + $ProcessName + ".exe")
            if (Test-Path -LiteralPath $candidat) { $exe = $candidat }
        }
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            try {
                $d = "$([System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileDescription)".Trim()
                if ($d -and $d -ne $ProcessName) { $desc = $d }
            } catch { }
        }
        $script:AppNameCache[$cle] = $desc
    }
    $lisible = $script:AppNameCache[$cle]
    if (-not $lisible) {
        # Faute de mieux, on affiche le nom du processus -- mais avec une MAJUSCULE :
        # c'est un nom propre a l'ecran (« Claude », pas « claude »), et une valeur de
        # carte commence toujours par une majuscule.
        if ($ProcessName.Length -gt 1) { return $ProcessName.Substring(0,1).ToUpper() + $ProcessName.Substring(1) }
        return $ProcessName.ToUpper()
    }
    if ($Complet) { return "$lisible ($ProcessName)" }
    return $lisible
}

# Ce qu'on dit d'une application quand on survole son nom : chemin ABSOLU d'abord (demande
# utilisateur), puis editeur et version, puis les processus reels derriere le nom.
#
# HOMONYMES : deux processus du meme nom peuvent venir de DEUX binaires differents (deux
# installations de chrome, un faux « svchost » pose ailleurs que dans System32). On ne
# choisit pas a la place de l'utilisateur : tous les emplacements distincts sont dits, et
# le fait qu'il y en ait plusieurs est annonce.
function Get-AppInfoTip {
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [string[]]$Paths = @(),
        [int[]]$Ids = @()
    )
    $lignes = @()
    $chemins = @($Paths | Where-Object { $_ } | Sort-Object -Unique)
    if ($chemins.Count -eq 0) {
        # Processus protege (csrss, lsass...) : Windows refuse son chemin. Si un binaire
        # systeme du meme nom EXISTE, on le nomme -- en disant que c'est le binaire attendu
        # et non le chemin lu, la nuance compte pour qui traque un imposteur.
        $sys = Join-Path $env:SystemRoot ("System32\" + $ProcessName + ".exe")
        if (Test-Path -LiteralPath $sys) {
            $lignes += "Chemin non communiqué (processus protégé par Windows)."
            $lignes += "Binaire système attendu : $sys"
            $chemins = @($sys)
        } else {
            $lignes += "Chemin : non communiqué (processus protégé par Windows)."
        }
    } elseif ($chemins.Count -eq 1) {
        $lignes += "$($chemins[0])"
    } else {
        $lignes += "$($chemins.Count) emplacements différents pour ce nom :"
        foreach ($c in ($chemins | Select-Object -First 4)) { $lignes += "- $c" }
    }
    $ref = @($chemins | Select-Object -First 1)[0]
    if ($ref -and (Test-Path -LiteralPath $ref)) {
        try {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ref)
            $editeur = "$($vi.CompanyName)".Trim()
            $version = "$($vi.FileVersion)".Trim()
            $detail = @($editeur, $version | Where-Object { $_ }) -join ' · '
            if ($detail) { $lignes += $detail }
        } catch { }
    }
    $pids = @($Ids | Where-Object { $_ -gt 0 })
    if ($pids.Count -eq 1) { $lignes += "1 processus (PID $($pids[0]))" }
    elseif ($pids.Count -gt 1) {
        $vus = @($pids | Select-Object -First 6) -join ', '
        $suite = if ($pids.Count -gt 6) { '…' } else { '' }
        $lignes += "$($pids.Count) processus (PID $vus$suite)"
    }
    $lignes -join "`n"
}

# --- ARBORESCENCE DU DISQUE, NIVEAU PAR NIVEAU (D60, revu le 26/08) ------------
# L'interface ne recoit JAMAIS l'arbre entier : elle demande UN niveau, et redemande
# quand l'utilisateur deplie. Exigence utilisateur -- un arbre complet, c'est un JSON
# qui grossit sans limite et une carte qui transporte ce que personne ne regardera.
#
# Deux sources, dans cet ordre :
#   1. le CACHE de la derniere analyse (var/cache/diskscan.json) : deja calcule, gratuit ;
#   2. un CALCUL PARTIEL a la demande, quand le niveau demande est au-dela de ce que
#      l'analyse a conserve. On ne parcourt alors QUE le sous-arbre demande.
# Ce qui est calcule a la demande est memorise (diskscan-levels.json) : deplier deux fois
# le meme dossier ne le reparcourt pas.
$script:SEP = [string][char]92

# Taille totale d'un dossier, en un seul passage .NET. Bornee dans le temps : au-dela on
# rend ce qu'on a en le DISANT (partiel), plutot que de faire attendre l'interface.
function Measure-FolderQuick {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutMs = 8000
    )
    $opts = [System.IO.EnumerationOptions]::new()
    $opts.IgnoreInaccessible    = $true
    $opts.RecurseSubdirectories = $true
    $opts.AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
    $taille = [long]0; $nb = 0; $partiel = $false
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    try {
        $di = [System.IO.DirectoryInfo]::new($Path)
        foreach ($f in $di.EnumerateFiles('*', $opts)) {
            $taille += [long]$f.Length
            $nb++
            if (($nb % 4096) -eq 0 -and $chrono.ElapsedMilliseconds -gt $TimeoutMs) { $partiel = $true; break }
        }
    } catch { }
    [pscustomobject]@{ Size = $taille; Files = $nb; Partial = $partiel }
}

# Les enfants DIRECTS de $Path, du plus gros au plus petit.
function Get-DiskTreeLevel {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Backend = (Get-BackendRoot),
        [int]$Top = 0
    )
    $etatFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan.json'
    $etat = $null
    if (Test-Path -LiteralPath $etatFile) {
        try { $etat = Get-Content -LiteralPath $etatFile -Raw | ConvertFrom-Json } catch { }
    }
    if (-not $etat -or -not $etat.tree) { throw "Aucune analyse disponible : lancez d'abord l'analyse de l'espace." }

    $racine = if ($etat.result -and $etat.result.root) { "$($etat.result.root)" } else { "$($etat.scan.root)" }
    $total  = [long]$etat.tree.s
    if ($Top -le 0) {
        $Top = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanTop' -Backend $Backend)
        if ($Top -le 0) { $Top = 10 }
    }

    # Le chemin demande doit appartenir a l'analyse : on n'explore pas le disque sur
    # demande d'un client, on explore l'arbre deja analyse.
    $plein = $Path
    try { $plein = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { }
    if (-not $plein.ToLower().StartsWith($racine.ToLower())) { throw "Hors de l'analyse en cours : $Path" }

    $pct = { param($o) if ($total -gt 0) { ('{0:N1}' -f ([double]$o / $total * 100)) } else { '0,0' } }

    # 1) Le cache de l'analyse contient-il deja ce niveau ?
    $noeud = $etat.tree
    $coupe = $racine.TrimEnd([char]92).Length
    $reste = $plein.Substring([Math]::Min($coupe, $plein.Length)).Trim([char]92)
    $trouve = $true
    if ($reste) {
        foreach ($pas in ($reste.Split([char]92))) {
            if (-not $pas) { continue }
            $suivant = @($noeud.k | Where-Object { "$($_.n)" -eq $pas })[0]
            if (-not $suivant) { $trouve = $false; break }
            $noeud = $suivant
        }
    }
    if ($trouve -and $noeud -and $noeud.k -and @($noeud.k).Count) {
        $enfants = @($noeud.k | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | ForEach-Object {
            [ordered]@{
                n = "$($_.n)"; path = (Join-Path $plein "$($_.n)")
                s = [long]$_.s; size = (Format-ByteSize ([long]$_.s))
                pct = (& $pct ([long]$_.s)); f = [int]$_.f; more = $true
            }
        })
        $fichiers = @($noeud.t | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | ForEach-Object {
            [ordered]@{ n = "$($_.n)"; size = (Format-ByteSize ([long]$_.s)) }
        })
        $autres = $null
        if ($noeud.o) { $autres = [ordered]@{ c = [int]$noeud.o.c; size = (Format-ByteSize ([long]$noeud.o.s)) } }
        return [pscustomobject]@{ path = $plein; source = 'analyse'; children = $enfants; files = $fichiers; others = $autres }
    }

    # 2) Niveau non conserve par l'analyse : CALCUL PARTIEL, borne a ce dossier.
    $memo = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan-levels.json'
    $cle  = $plein.ToLower()
    try {
        if (Test-Path -LiteralPath $memo) {
            $m = Get-Content -LiteralPath $memo -Raw | ConvertFrom-Json
            $e = $m.PSObject.Properties | Where-Object { $_.Name -eq $cle } | Select-Object -First 1
            if ($e -and $e.Value) {
                return [pscustomobject]@{ path = $plein; source = 'memoire'; children = @($e.Value.children); files = @($e.Value.files); others = $null }
            }
        }
    } catch { }

    $opts = [System.IO.EnumerationOptions]::new()
    $opts.IgnoreInaccessible    = $true
    $opts.RecurseSubdirectories = $false
    $opts.AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
    $di = $null
    try { $di = [System.IO.DirectoryInfo]::new($plein) } catch { }
    if (-not $di -or -not $di.Exists) { throw "Dossier introuvable : $plein" }

    $sous = @()
    try { $sous = @($di.EnumerateDirectories('*', $opts)) } catch { }
    $calcules = @(foreach ($d in $sous) {
        $mes = Measure-FolderQuick -Path $d.FullName
        [ordered]@{
            n = $d.Name; path = $d.FullName; s = [long]$mes.Size
            size = (Format-ByteSize ([long]$mes.Size)); pct = (& $pct ([long]$mes.Size))
            f = [int]$mes.Files; more = $true; partial = [bool]$mes.Partial
        }
    })
    $calcules = @($calcules | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $Top)

    $fic = @()
    try {
        $fic = @($di.EnumerateFiles('*', $opts) | Sort-Object Length -Descending | Select-Object -First $Top | ForEach-Object {
            [ordered]@{ n = $_.Name; size = (Format-ByteSize ([long]$_.Length)) }
        })
    } catch { }

    try {
        Update-StateJson -Path $memo -Depth 12 -Set @{ $cle = @{ children = $calcules; files = $fic; at = (Get-Date).ToUniversalTime().ToString('s') } } | Out-Null
    } catch { }
    return [pscustomobject]@{ path = $plein; source = 'calcul'; children = $calcules; files = $fic; others = $null }
}

# Taille en octets -> texte lisible (une seule decimale : « 12,4 Go »). Point unique de
# mise en forme des tailles : une carte qui affiche des octets bruts n'apprend rien.
function Format-ByteSize {
    param([Parameter(Mandatory)][long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} To' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} Go' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} Mo' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} Ko' -f ($Bytes / 1KB)) }
    return ("$Bytes o")
}

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
        [hashtable]$Table,
        # ARBORESCENCE repliable (S13b/D60) : @{ n; path; size; pct; k = @(...) }. Un
        # tableau met a plat ce qui est hierarchique ; un arbre se parcourt de branche en
        # branche, ce qui est justement la question posee (« ou part la place ? »).
        $Tree
    )
    $f = [ordered]@{ key = $Key; label = $Label; value = $Value; kind = $Kind }
    if ($Unit)      { $f['unit']      = $Unit }
    if ($Status)    { $f['status']    = $Status }
    if ($Help)      { $f['help']      = $Help }
    if ($FixAction) { $f['fixAction'] = $FixAction }
    if ($Guide)     { $f['guide']     = $Guide }
    if ($Table -and $Table.rows -and @($Table.rows).Count) { $f['table'] = $Table }
    if ($Tree) { $f['tree'] = $Tree }
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
        [switch]$ConfirmTwice,
        # --- CE QU'UNE CONFIRMATION DOIT DIRE (D91) ------------------------------
        # « Cette action modifie votre systeme » ne renseigne personne. Avant de dire
        # oui, on veut savoir CE QUI CHANGE sur la machine, POURQUOI on ferait ca, et
        # SI on peut revenir en arriere. Les details techniques de surface sont les
        # bienvenus : un nom de service, une cle de registre, un redemarrage requis.
        #
        #   -Impact     : ce qui change concretement, ici et maintenant.
        #   -Usage      : dans quel cas on s'en sert (l'intention).
        #   -Reversible : comment revenir en arriere -- ou pourquoi on ne peut pas.
        [string]$Impact,
        [string]$Usage,
        [string]$Reversible,

        <#
            -From / -To : L'ACTION FAIT PASSER D'UN ETAT A UN AUTRE, et on le MONTRE.

            « De v0.1.25 vers v0.1.25+1 » colle au bout d'une phrase se lit mal et se
            perd. Deux valeurs et une fleche se lisent d'un coup d'oeil -- c'est ce que
            l'on veut savoir avant de cliquer.

            -FromNote / -ToNote portent le detail sous chaque valeur : un commit, une
            date. Facultatifs : en production, le numero de version se suffit.
        #>
        [string]$From,
        [string]$To,
        [string]$FromNote,
        [string]$ToNote,

        <#
            -Steps : CE QUI VA SE PASSER, DANS L'ORDRE.

            Une action longue enchaine plusieurs phases -- deployer, redemarrer, verifier.
            Les enumerer dans une phrase les noie ; les montrer alignees dit d'un coup
            d'oeil combien il y en a, et laquelle finit le travail.

            La derniere est l'ETAT D'ARRIVEE, pas une phase : elle se distingue.
        #>
        [string[]]$Steps = @()
    )
    $a = [ordered]@{ id = $Id; label = $Label }
    if ($Confirm -or $ConfirmTwice) { $a['confirm'] = $true }
    if ($ConfirmTwice) { $a['confirmTwice'] = $true }
    if ($Help)    { $a['help']    = $Help }
    if ($Impact)     { $a['impact']     = $Impact }
    if ($Usage)      { $a['usage']      = $Usage }
    if ($Steps -and $Steps.Count) { $a['steps'] = @($Steps) }
    if ($From -or $To) {
        $a['transition'] = @{ from = "$From"; to = "$To"; fromNote = "$FromNote"; toNote = "$ToNote" }
    }
    if ($Reversible) { $a['reversible'] = $Reversible }
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
    # CE QUE L'ACTION MOBILISE (D93). L'interface s'en sert pour griser juste ce qu'il
    # faut ; le serveur, lui, arbitre pour de bon.
    $res = @(Get-ActionResources -Type $Id)
    if ($res.Count) { $a['resources'] = @($res) }
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
        [string]$BusyAction,
        # Ce que l'operation en cours mobilise : sans cela, l'interface ne peut que tout
        # bloquer ou ne rien bloquer.
        [string[]]$BusyResources = @()
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
    if ($Busy) {
        $br = if ($BusyResources.Count) { @($BusyResources) } elseif ($BusyAction) { @(Get-ActionResources -Type $BusyAction) } else { @() }
        if ($br.Count) { $o['busyResources'] = @($br) }
    }
    [pscustomobject]$o
}

$script:ThemeCatalog = @(
    [pscustomobject]@{ id = 'windows-update'; label = 'Windows Update' }
    [pscustomobject]@{ id = 'system';         label = 'Système' }
    [pscustomobject]@{ id = 'accounts';       label = 'Comptes' }
    [pscustomobject]@{ id = 'wsl';            label = 'WSL' }
    [pscustomobject]@{ id = 'security';       label = 'Sécurité' }
    [pscustomobject]@{ id = 'network';        label = 'Réseau' }
    [pscustomobject]@{ id = 'tools';          label = 'Outils & paquets' }
    [pscustomobject]@{ id = 'gaming';         label = 'Gaming' }
    # Dernier de la liste : c'est un outil de depannage, eteint par defaut (D85).
    [pscustomobject]@{ id = 'debug';          label = 'Débogage' }
)

# --- Agregation des sondes (journalisee) -----------------------------------
# Duree de validite du cache par sonde (secondes) : court pour ce qui bouge vite,
# long pour ce qui est stable.
$script:ProbeTtls = @{
    'perf.probe.ps1'    = 8
    'net.probe.ps1'     = 15
    'wsl.probe.ps1'     = 600
    # Court : la carte Stockage porte la progression de l'analyse d'espace (D60), et
    # la sonde ne fait que lire deux JSON -- la recalculer coute quelques dizaines de ms.
    'disk.probe.ps1'    = 5
    'history.probe.ps1' = 120
    'firewall.probe.ps1'= 120
    'defender.probe.ps1'= 300
    'vbs.probe.ps1'     = 300
    'lock.probe.ps1'    = 600
    'pending.probe.ps1' = 900
    'comptes.probe.ps1' = 300
    'os.probe.ps1'      = 3600
    'packages.probe.ps1'= 5
    'gaming.probe.ps1'  = 10
    # L'alimentation change d'un instant a l'autre (on debranche, une pointe de
    # charge fait lacher le chargeur) : une valeur vieille d'une minute ne veut
    # deja plus rien dire.
    'power.probe.ps1'   = 15
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
# --- Historique des mesures (series) ------------------------------------------
# Etape 1 du plan doc/archives/conception/historique-migration.md. On note AU PASSAGE des
# valeurs deja calculees par les sondes : le seul point d'accroche est le recalcul
# reussi d'une sonde dans Get-State -- aucune sonde n'ecrit elle-meme, aucune cadence
# propre a l'historique. Stockage : un fichier JSONL par mesure dans var/history/
# (distinct de var/cache/ : un historique perdu ne se recalcule pas). Best-effort :
# une erreur d'ecriture se journalise et ne fait jamais echouer un recalcul.

# LE catalogue des mesures (D15 : une valeur, une definition). Pour chaque mesure :
# la sonde source, la nature (gauge/event), l'unite, l'intervalle minimal par defaut
# (surchargable par la config, voir Get-HistoryConfig) et l'extracteur, qui lit la
# valeur dans les MODULES RENDUS par la sonde (jamais en relancant quoi que ce soit).
# L'extracteur rend $null (rien a noter) ou @{ v = <valeur>; key = <jeton optionnel> }.
# `key` sert aux mesures liees a une mesure externe : on n'ecrit que quand il change.
# Exemple : net.latency n'a une valeur NOUVELLE que quand `measAt` change, quel que
# soit le nombre de recalculs de la sonde entre deux mesures de debit/latence.
$script:MeasureCatalog = @{
    'disk.free' = @{
        Probe = 'disk.probe.ps1'; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 30
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'storage' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'free' } | Select-Object -First 1
            if ($null -eq $f -or $null -eq $f.value) { return $null }
            $v = 0.0
            if (-not [double]::TryParse("$($f.value)", [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
            return @{ v = $v }
        }
    }
    # Session de jeu (module gaming) : notee UNIQUEMENT quand un jeu tourne -- la
    # presence meme des points raconte la session (debut, fin, intensite). Le nom du
    # jeu accompagne chaque point (champ n), pour repondre a « pourquoi ca ramait
    # hier soir ? » sans rien afficher (Q2 : enregistrement seul).
    'game.gpu' = @{
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = '%'; IntervalMinutes = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $r = @($m.fields) | Where-Object { "$($_.key)" -eq 'game-res' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $r) { return $null }
            if ("$($r.value)" -notmatch 'GPU\s+([0-9]+(?:[.,][0-9]+)?)\s*%') { return $null }
            return @{ v = [double](($Matches[1]) -replace ',', '.'); n = "$($g.value)" }
        }
    }
    'game.vram' = @{
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $r = @($m.fields) | Where-Object { "$($_.key)" -eq 'game-res' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $r) { return $null }
            if ("$($r.value)" -notmatch 'VRAM\s+([0-9]+(?:[.,][0-9]+)?)\s*Go') { return $null }
            return @{ v = [double](($Matches[1]) -replace ',', '.'); n = "$($g.value)" }
        }
    }
    'game.hogs' = @{
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = 'applis'; IntervalMinutes = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $h = @($m.fields) | Where-Object { "$($_.key)" -eq 'hogs' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $h) { return $null }
            $n = 0
            if ("$($h.value)" -match '^([0-9]+)') { $n = [int]$Matches[1] }
            return @{ v = [double]$n; n = "$($g.value)" }
        }
    }
    'net.latency' = @{
        Probe = 'net.probe.ps1'; Kind = 'gauge'; Unit = 'ms'; IntervalMinutes = 0
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'net' } | Select-Object -First 1
            if (-not $m) { return $null }
            $lat = @($m.fields) | Where-Object { "$($_.key)" -eq 'latency' } | Select-Object -First 1
            $mea = @($m.fields) | Where-Object { "$($_.key)" -eq 'measAt' }  | Select-Object -First 1
            # Pas de champ de date = latence jamais mesuree : rien a noter.
            if (-not $lat -or -not $mea -or $null -eq $mea.value) { return $null }
            # La valeur affichee est un texte ("23 ms") : on en extrait le nombre.
            if ("$($lat.value)" -notmatch '^\s*([0-9]+(?:[.,][0-9]+)?)\s*ms') { return $null }
            $v = [double](($Matches[1]) -replace ',', '.')
            # La cle est la date de la mesure, NORMALISEE : ConvertFrom-Json rend tantot
            # une chaine, tantot un [datetime] (D44) -- comparer les formes brutes ecrirait
            # un point a chaque recalcul.
            $key = $null
            try { $key = (ConvertTo-UtcDate $mea.value).ToString('o') } catch { return $null }
            return @{ v = $v; key = $key }
        }
    }
}

# Resout la configuration de l'historique en COUCHES (meme logique que la config, D33) :
# defauts internes -> section History de config.psd1 (surchargee par config.local.psd1)
# -> reglage par mesure, la plus specifique gagne. Sans -MeasureId : les valeurs
# globales. Avec : les valeurs EFFECTIVES de la mesure (RetentionDays, IntervalMinutes,
# MaxLines). RetentionDays <= 0 sur une mesure = ne plus l'echantillonner.
function Get-HistoryConfig {
    param([string]$Backend = (Get-BackendRoot), [string]$MeasureId, [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    $h = $Config.History
    $res = @{ Enabled = $true; RetentionDays = 90; MaxLinesPerMeasure = 50000; Measures = @{} }
    if ($h -is [hashtable]) {
        if ($h.ContainsKey('Enabled'))            { $res.Enabled            = [bool]$h.Enabled }
        if ($h.ContainsKey('RetentionDays'))      { $res.RetentionDays      = [int]$h.RetentionDays }
        if ($h.ContainsKey('MaxLinesPerMeasure')) { $res.MaxLinesPerMeasure = [int]$h.MaxLinesPerMeasure }
        if ($h.Measures -is [hashtable])          { $res.Measures           = $h.Measures }
    }
    if (-not $MeasureId) { return $res }
    $cat = $script:MeasureCatalog[$MeasureId]
    $eff = @{
        Enabled         = $res.Enabled
        RetentionDays   = $res.RetentionDays
        MaxLines        = $res.MaxLinesPerMeasure
        IntervalMinutes = $(if ($cat -and $cat.ContainsKey('IntervalMinutes')) { [int]$cat.IntervalMinutes } else { 0 })
    }
    $mo = $res.Measures[$MeasureId]
    if ($mo -is [hashtable]) {
        if ($mo.ContainsKey('RetentionDays'))   { $eff.RetentionDays   = [int]$mo.RetentionDays }
        if ($mo.ContainsKey('IntervalMinutes')) { $eff.IntervalMinutes = [int]$mo.IntervalMinutes }
    }
    # Retention nulle = mesure coupee. Le fichier existant n'est PAS supprime :
    # detruire une archive reste un geste manuel et volontaire.
    if ($eff.RetentionDays -le 0) { $eff.Enabled = $false }
    return $eff
}

# Append d'UNE ligne dans un fichier d'historique, sous le mutex du fichier
# (Local\VigieHistory_<leaf>, meme convention que Update-StateJson). Necessaire :
# deux recalculs simultanes existent reellement (requete forcee + rafraichissement
# de fond) et leurs ecritures ne doivent pas s'entremeler.
function Add-HistoryLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Line)
    $leaf = (Split-Path $Path -Leaf) -replace '[^A-Za-z0-9]', '_'
    $mx = New-Object System.Threading.Mutex($false, "Local\VigieHistory_$leaf")
    $got = $false
    try {
        try { $got = $mx.WaitOne(2000) }
        catch [System.Threading.AbandonedMutexException] { $got = $true }
        catch { $got = $false }
        if (-not $got) { return $false }
        [IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        return $true
    } finally {
        if ($got) { try { $mx.ReleaseMutex() } catch { } }
        try { $mx.Dispose() } catch { }
    }
}

# Echantillonne les mesures d'UNE sonde, juste apres son recalcul reussi (appel
# unique : la boucle de Get-State). Consulte le catalogue, applique l'intervalle
# minimal via l'index (history-index.json : lastAt/lastValue/lastKey par mesure,
# ecrit par Update-StateJson donc fusion sous mutex), appende dans
# var/history/<measureId>.jsonl. Declenche aussi la purge, au plus 1 fois par 24 h.
# Best-effort de bout en bout : jamais d'echec remonte au recalcul.
function Write-MeasureSamples {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Probe,
        [Parameter(Mandatory)]$Modules
    )
    try {
        $ids = @($script:MeasureCatalog.Keys | Where-Object { $script:MeasureCatalog[$_].Probe -eq $Probe })
        if ($ids.Count -eq 0) { return }
        $cfg = Get-Config -Backend $Backend
        $global = Get-HistoryConfig -Backend $Backend -Config $cfg
        if (-not $global.Enabled) { return }
        $indexFile = Get-VarPath -Backend $Backend -Kind 'history' -File 'history-index.json'
        $index = $null
        if (Test-Path -LiteralPath $indexFile) {
            try { $index = Get-Content -LiteralPath $indexFile -Raw | ConvertFrom-Json } catch { }
        }
        $nowUtc = [datetime]::UtcNow
        foreach ($id in ($ids | Sort-Object)) {
            $cat = $script:MeasureCatalog[$id]
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg
            if (-not $eff.Enabled) { continue }
            $sample = $null
            try { $sample = & $cat.Extract $Modules } catch { $sample = $null }
            if ($null -eq $sample -or $null -eq $sample.v) { continue }
            $prop  = if ($index) { $index.PSObject.Properties[$id] } else { $null }
            $entry = if ($prop) { $prop.Value } else { $null }
            # Mesure a cle (liee a une mesure externe) : on n'ecrit que si la cle change.
            # La cle relue passe par ConvertTo-UtcDate : ConvertFrom-Json rend la date
            # stockee en [datetime] (D44), la comparer telle quelle a la chaine 'o' de
            # l'extracteur ne matchait JAMAIS -- constate en test, un point par recalcul.
            if ($sample.key -and $entry -and $entry.lastKey) {
                $prevKey = "$($entry.lastKey)"
                try { $prevKey = (ConvertTo-UtcDate $entry.lastKey).ToString('o') } catch { }
                if ($prevKey -eq "$($sample.key)") { continue }
            }
            # Gauge ordinaire : intervalle minimal depuis le dernier point.
            if ((-not $sample.key) -and $eff.IntervalMinutes -gt 0 -and $entry -and $entry.lastAt) {
                try {
                    $last = ConvertTo-UtcDate $entry.lastAt
                    if ($last -and ($nowUtc - $last).TotalMinutes -lt $eff.IntervalMinutes) { continue }
                } catch { }
            }
            $file = Get-VarPath -Backend $Backend -Kind 'history' -File ($id + '.jsonl')
            # Champ optionnel n : un NOM attache au point (ex. le jeu d'une session) --
            # c'est lui qui permettra de repondre « qu'est-ce qui tournait a cette heure ? ».
            $obj = [ordered]@{ at = $nowUtc.ToString('o'); v = $sample.v }
            if ($sample.n) { $obj.n = "$($sample.n)" }
            $line = ($obj | ConvertTo-Json -Compress -Depth 4)
            if (Add-HistoryLine -Path $file -Line $line) {
                $set = @{ lastAt = $nowUtc.ToString('o'); lastValue = $sample.v }
                if ($sample.key) { $set.lastKey = "$($sample.key)" }
                try { Update-StateJson -Path $indexFile -Set @{ $id = $set } | Out-Null } catch { }
            }
        }
        # Purge : au plus une fois par 24 h, adossee a un recalcul deja en cours (jamais
        # de reveil dedie). La date est posee AVANT de purger, pour que deux recalculs
        # simultanes ne lancent pas deux purges.
        $due = $true
        $pp = if ($index) { $index.PSObject.Properties['purgedAt'] } else { $null }
        if ($pp -and $pp.Value) {
            try {
                $p = ConvertTo-UtcDate $pp.Value
                if ($p -and ($nowUtc - $p).TotalHours -lt 24) { $due = $false }
            } catch { }
        }
        if ($due) {
            try { Update-StateJson -Path $indexFile -Set @{ purgedAt = $nowUtc.ToString('o') } | Out-Null } catch { }
            Invoke-HistoryPurge -Backend $Backend
        }
    } catch {
        # L'historique OBSERVE, il n'arbitre pas : jamais d'echec remonte a Get-State.
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (Get-Label 'common.historique-echantillonnage-ignore' $Probe $_.Exception.Message) } catch { }
    }
}

# Purge des fichiers de var/history/ : retention en jours (globale, surchargee par
# mesure) PLUS plafond de lignes (garde-fou de taille : un intervalle mal regle ne
# doit pas remplir le disque). Reecriture ATOMIQUE (.tmp + garde + Move-Item) sous
# le mutex du fichier. Les lignes illisibles (ecriture interrompue) sont eliminees
# et comptees, jamais bloquantes. probe-runs.jsonl n'est PAS concerne : il vit dans
# var/cache/ et garde sa purge par taille propre (D52).
function Invoke-HistoryPurge {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $cfg = Get-Config -Backend $Backend
        $dir = Get-VarPath -Backend $Backend -Kind 'history'
        $files = @(Get-ChildItem -Path $dir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
        $nowUtc = [datetime]::UtcNow
        foreach ($fi in $files) {
            $id  = [IO.Path]::GetFileNameWithoutExtension($fi.Name)
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg
            # Retention <= 0 : la mesure n'est plus echantillonnee, mais on ne vide
            # jamais une archive existante -- geste manuel uniquement.
            if ($eff.RetentionDays -le 0) { continue }
            $cutoff = $nowUtc.AddDays(-$eff.RetentionDays)
            $leaf = ($fi.Name) -replace '[^A-Za-z0-9]', '_'
            $mx = New-Object System.Threading.Mutex($false, "Local\VigieHistory_$leaf")
            $got = $false
            try {
                try { $got = $mx.WaitOne(5000) }
                catch [System.Threading.AbandonedMutexException] { $got = $true }
                catch { $got = $false }
                if (-not $got) { continue }
                $lines = [IO.File]::ReadAllLines($fi.FullName)
                $keep = New-Object System.Collections.Generic.List[string]
                $dropped = 0
                foreach ($l in $lines) {
                    if ([string]::IsNullOrWhiteSpace($l)) { $dropped++; continue }
                    $o = $null
                    try { $o = $l | ConvertFrom-Json } catch { $dropped++; continue }
                    $at = $null
                    try { $at = ConvertTo-UtcDate $o.at } catch { }
                    if (-not $at -or $at -lt $cutoff) { $dropped++; continue }
                    $keep.Add($l)
                }
                if ($eff.MaxLines -gt 0 -and $keep.Count -gt $eff.MaxLines) {
                    $excess = $keep.Count - $eff.MaxLines
                    $keep.RemoveRange(0, $excess)
                    $dropped += $excess
                }
                if ($dropped -gt 0) {
                    $tmp = $fi.FullName + '.tmp'
                    [IO.File]::WriteAllLines($tmp, $keep, [Text.UTF8Encoding]::new($false))
                    # Garde de taille : si on garde des lignes, le .tmp ne peut pas etre vide.
                    $ok = (Test-Path -LiteralPath $tmp) -and ($keep.Count -eq 0 -or (Get-Item -LiteralPath $tmp).Length -gt 0)
                    if ($ok) { Move-Item -Path $tmp -Destination $fi.FullName -Force }
                    else { try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { } }
                    Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'common.historique-purge-de-ligne' $fi.Name $dropped $keep.Count)
                }
            } finally {
                if ($got) { try { $mx.ReleaseMutex() } catch { } }
                try { $mx.Dispose() } catch { }
            }
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (Get-Label 'common.historique-purge-en-echec' $_.Exception.Message) } catch { }
    }
}

# Interprete une fenetre de lecture de l'historique ("24h", "7d") en [TimeSpan].
# $null = forme invalide : la route repond alors 400, la fonction ne devine jamais.
# Bornes larges mais finies : une fenetre enorme n'est pas une erreur de forme,
# elle lit simplement tout le fichier (la retention borne deja les donnees).
function ConvertTo-HistoryWindow {
    param([string]$Window)
    if (-not $Window) { return $null }
    if ($Window -notmatch '^([0-9]{1,4})([hd])$') { return $null }
    $n = [int]$Matches[1]
    if ($n -le 0) { return $null }
    if ($Matches[2] -eq 'h') { return [TimeSpan]::FromHours($n) }
    return [TimeSpan]::FromDays($n)
}

# Lit la serie d'UNE mesure pour GET /history/{measureId} (etape 2 du plan
# doc/archives/conception/historique-migration.md). Lecture seule, sous le MEME mutex que
# l'ecriture (Local\VigieHistory_<leaf>) : un append peut etre en cours pendant la
# lecture. Les lignes illisibles (ecriture interrompue) sont ignorees sans echouer.
# Rend $null si la mesure n'est pas au catalogue (la route repond 404) ; sinon un
# objet conforme au schema History du contrat : points (decimes a ~$MaxPoints pour
# une gauge, tels quels pour un event -- ils sont rares) + summary calcule AVANT
# decimation. Fichier absent ou vide = points vides, summary.count = 0 : un
# historique jeune n'est pas une erreur.
function Get-MeasureHistory {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId,
        [Parameter(Mandatory)][TimeSpan]$Window,
        [string]$WindowLabel = '',
        [int]$MaxPoints = 200
    )
    $cat = $script:MeasureCatalog[$MeasureId]
    if (-not $cat) { return $null }
    $file = Get-VarPath -Backend $Backend -Kind 'history' -File ($MeasureId + '.jsonl')
    $lines = @()
    if (Test-Path -LiteralPath $file) {
        $leaf = (Split-Path $file -Leaf) -replace '[^A-Za-z0-9]', '_'
        $mx = New-Object System.Threading.Mutex($false, "Local\VigieHistory_$leaf")
        $got = $false
        try {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            # Mutex indisponible : on lit quand meme (pire cas, une ligne finale
            # tronquee, deja geree) plutot que de rendre une erreur au client.
            $lines = [IO.File]::ReadAllLines($file)
        } finally {
            if ($got) { try { $mx.ReleaseMutex() } catch { } }
            try { $mx.Dispose() } catch { }
        }
    }
    $nowUtc = [datetime]::UtcNow
    $cutoff = $nowUtc - $Window
    # Filtre + normalisation. Le fichier est append-only donc deja chronologique ;
    # on retrie malgre tout : une purge interrompue ou une ligne forgee ne doit pas
    # rendre une serie desordonnee.
    $pts = New-Object System.Collections.Generic.List[object]
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { continue }
        $at = $null
        # ConvertFrom-Json rend la date tantot en chaine, tantot en [datetime] (D44) :
        # ConvertTo-UtcDate normalise, comparer sans lui fausserait la fenetre.
        try { $at = ConvertTo-UtcDate $o.at } catch { continue }
        if (-not $at -or $null -eq $o.v) { continue }
        if ($at -lt $cutoff) { continue }
        $v = 0.0
        if (-not [double]::TryParse("$($o.v)", [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { continue }
        $pts.Add([pscustomobject]@{ atUtc = $at; v = $v })
    }
    $sorted = @($pts | Sort-Object atUtc)
    # Summary sur TOUS les points de la fenetre, avant decimation : la decimation
    # peut faire sauter l'extreme, le resume ne doit pas le perdre.
    $summary = [ordered]@{ count = $sorted.Count; min = $null; max = $null; first = $null; last = $null }
    if ($sorted.Count -gt 0) {
        $mesures = $sorted | Measure-Object -Property v -Minimum -Maximum
        $summary.min   = $mesures.Minimum
        $summary.max   = $mesures.Maximum
        $summary.first = $sorted[0].v
        $summary.last  = $sorted[$sorted.Count - 1].v
    }
    # Decimation uniforme par index, premier et dernier points conserves. Les events
    # (etape 4) partiront tels quels : ils sont rares et chaque occurrence compte.
    $kept = $sorted
    if ("$($cat.Kind)" -ne 'event' -and $MaxPoints -gt 0 -and $sorted.Count -gt $MaxPoints) {
        $kept = New-Object System.Collections.Generic.List[object]
        $step = ($sorted.Count - 1) / [double]($MaxPoints - 1)
        $lastIdx = -1
        for ($i = 0; $i -lt $MaxPoints; $i++) {
            $idx = [int][math]::Round($i * $step)
            if ($idx -eq $lastIdx) { continue }   # deux i arrondis au meme index
            $kept.Add($sorted[$idx])
            $lastIdx = $idx
        }
    }
    return [ordered]@{
        measureId = $MeasureId
        kind      = "$($cat.Kind)"
        unit      = "$($cat.Unit)"
        window    = $WindowLabel
        points    = @($kept | ForEach-Object { [ordered]@{ at = $_.atUtc.ToString('o'); v = $_.v } })
        summary   = $summary
    }
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
        [int]$WaitSeconds = 0,
        # RECALCUL CIBLE : identifiant du module dont on veut des valeurs fraiches, et de
        # LUI SEUL. C'est ce que demande le bouton « Rafraichir » d'une carte : rendre le
        # resultat recalcule, et non la derniere valeur connue pendant qu'un
        # rafraichissement de fond traine derriere -- constate sur la carte Jeux, qui
        # annoncait « aucun jeu » alors que la sonde voyait deja la partie en cours.
        [string]$ForceModule = ''
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

    # Quelle sonde produit le module vise ? Le cache le dit : chaque entree porte le
    # module rendu par la sonde (ou son tableau de modules).
    $sondesCiblees = @()
    if ($ForceModule) {
        foreach ($nomSonde in @($cache.Keys)) {
            $e = $cache[$nomSonde]
            if (-not $e -or -not $e.module) { continue }
            foreach ($mm in @($e.module)) {
                if ("$($mm.id)" -eq $ForceModule) { $sondesCiblees += "$nomSonde" }
            }
        }
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
    $unitesCoupees = @(Get-InactiveUnits -Backend $Backend)
    if ($unitesCoupees.Count -gt 0) {
        $probeFiles = @($probeFiles | Where-Object {
            $unitesCoupees -notcontains (Split-Path (Split-Path $_.FullName -Parent) -Leaf)
        })
    }
    # QUI DEMANDE : les cartes qui parlent de « vous » ont leur propre entree par compte.
    $stateRequester = Get-RequesterAccount
    $stale = @()
    foreach ($pf in $probeFiles) {
        $name = $pf.Name; $stamp = "$($pf.LastWriteTimeUtc.Ticks)"
        $key = Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester
        $ttl = if ($script:ProbeTtls.ContainsKey($name)) { $script:ProbeTtls[$name] } else { $defaultTtl }
        $entry = $cache[$key]; $fresh = $false
        # -Force : tout est considere perime, sans rien effacer.
        # Une sonde VISEE est perimee d'office : c'est tout le sens de la demande.
        if (-not $Force -and ($sondesCiblees -notcontains $key) -and $entry -and $entry.at -and ("$($entry.codeStamp)" -eq $stamp)) {
            try {
                $at = ConvertTo-UtcDate $entry.at
                if ($at -and ($nowUtc - $at).TotalSeconds -lt $ttl) { $fresh = $true }
            } catch { }
        }
        if (-not $fresh) { $stale += [pscustomobject]@{ File = $pf.FullName; Name = $name; Key = $key; Stamp = $stamp
                                                        PerAccount = (Test-ProbeIsPerAccount -ProbeFile $pf.FullName) } }
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
        # Une sonde VISEE ne se differe JAMAIS : la reponse doit porter son recalcul.
        # UNE CARTE PAR COMPTE NE SE DIFFERE PAS. Le rafraichissement de fond tourne sans
        # session : il ne sait pas pour qui recalculer, et ecrirait sous la cle anonyme.
        # Ces sondes-la sont rapides -- on les calcule dans la requete qui les demande.
        $sansValeur = @($stale | Where-Object { ($sondesCiblees -contains $_.Key) -or $_.PerAccount -or -not ($cache[$_.Key] -and $cache[$_.Key].module) })
        $aDifferer  = @($stale | Where-Object { ($sondesCiblees -notcontains $_.Key) -and -not $_.PerAccount -and $cache[$_.Key] -and $cache[$_.Key].module })
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
            <#
                UNE CARTE PERSONNELLE DOIT ETRE CALCULEE MAINTENANT, ou elle ne le sera
                jamais. Le rafraichissement de fond tourne sans session : il ecrit sous la
                cle anonyme, jamais sous « @<compte> ». Si la requete qui la demande
                n'attend pas le verrou, son entree reste perimee indefiniment -- constate
                le 30/08 : la carte annoncait v0.1.29-dev5 alors que l'installation etait
                en v0.1.30, et deux appels de suite rendaient la meme reponse.

                On attend donc son tour pour ces cartes-la, meme sans demande explicite.
            #>
            $personnelles = @($stale | Where-Object { $_.PerAccount }).Count
            $secondes = [Math]::Max($WaitSeconds, $(if ($personnelles) { 30 } else { 0 }))
            $attente = [Math]::Min($secondes, 75) * 1000
            try { $got = $mx.WaitOne($attente) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if ($got) {
                # L'origine du passage, pour le journal : une demande explicite attend
                # (WaitSeconds > 0 ou -Force), le reste est un rafraichissement de fond.
                $origine = if ($Force -or $ForceModule -or $WaitSeconds -gt 0) { 'forced' } else { 'background' }
                foreach ($sp in $stale) {
                    $t0 = Get-Date
                    try {
                        $m = & $sp.File
                        $duree = [int]((Get-Date) - $t0).TotalMilliseconds
                        if ($m) { $cache[$sp.Key] = [ordered]@{ module = $m; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp } }
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms $duree -Origin $origine -Outcome ($(if ($m) { 'ok' } else { 'empty' })) -Modules @($m).Count
                        Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'common.sonde-recalculee-ms' $sp.Name $duree)
                        # Historique : echantillonne les mesures du catalogue APRES un
                        # recalcul reussi. Best-effort (la fonction n'echoue jamais).
                        if ($m) { Write-MeasureSamples -Backend $Backend -Probe $sp.Name -Modules @($m) }
                    } catch {
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms ([int]((Get-Date) - $t0).TotalMilliseconds) -Origin $origine -Outcome 'error' -Detail $_.Exception.Message
                        Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (Get-Label 'common.sonde-erreur' $sp.Name $_.Exception.Message)
                        <#
                            UNE ERREUR SE PRESENTE COMME LE RESTE.

                            La carte d'echec s'appelait « comptes.probe.ps1 » et
                            atterrissait sous « Systeme » : le nom d'un fichier, dans le
                            mauvais groupe. Personne ne sait a quelle carte cela
                            correspond, et c'est justement le moment ou il faut le savoir.

                            Le dossier de la sonde EST son module -- probes/<unite>/ --
                            et son module.psd1 porte le libelle affiche. On s'en sert :
                            la carte garde sa place et son nom, et dit ce qui a echoue.
                        #>
                        $unite = Split-Path (Split-Path $sp.File -Parent) -Leaf
                        $libelle = $unite
                        try {
                            $decl = Join-Path (Split-Path $sp.File -Parent) 'module.psd1'
                            if (Test-Path -LiteralPath $decl) {
                                $d = Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop
                                if ($d.Label) { $libelle = "$($d.Label)" }
                            }
                        } catch { }
                        $errMod = New-ModuleObject -Id $sp.Name -Theme $unite -Label $libelle -Status 'error' -Fields @(
                            New-Field -Key 'error' -Label 'Erreur' -Value $_.Exception.Message -Kind 'text' -Status 'error'
                            New-Field -Key 'probe' -Label 'Sonde' -Value $sp.Name -Kind 'text'
                        )
                        $cache[$sp.Key] = [ordered]@{ module = $errMod; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp }
                    }
                    # Ecriture FUSIONNEE, entree par entree, sous mutex (Update-StateJson).
                    #
                    # On reecrivait tout le fichier depuis la copie memoire : deux recalculs
                    # simultanes (la requete forcee et le rafraichissement de fond) se
                    # clobberaient l'un l'autre, et une entree deja corrigee revenait a son
                    # ancienne valeur -- une carte en erreur ressuscitait apres correction.
                    # Ne reecrire QUE la sonde qu'on vient de calculer supprime la course.
                    # -Depth 24 : une carte peut porter un ARBRE (analyse du disque).
                    # A la profondeur par defaut (8), ConvertTo-Json tronque en SILENCE et
                    # les branches profondes arrivent VIDES a l'interface -- constate le
                    # 26/08 : des lignes sans nom ni taille sous chaque dossier.
                    try { Update-StateJson -Path $cacheFile -Set @{ $sp.Key = $cache[$sp.Key] } -Depth 24 | Out-Null } catch { }
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
    foreach ($pf in $probeFiles) {
        $e = $cache[(Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester)]
        if ($e -and $e.module) { $modules += $e.module }
    }

    # INVARIANT (D66) : une action CITEE par un champ (fixAction) doit figurer dans les
    # actions de la carte, sinon l'interface n'a ni libelle ni genre a dessiner et le
    # bouton de resolution n'apparait pas. On complete ici plutot que d'obliger chaque
    # sonde a redeclarer l'action dans sa barre.
    foreach ($m in $modules) {
        $connues = @(@($m.actions) | Where-Object { $_ -and $_.id } | ForEach-Object { "$($_.id)" })
        foreach ($ch in @($m.fields)) {
            $fa = "$($ch.fixAction)"
            if (-not $fa -or $connues -contains $fa) { continue }
            $pres = Get-ActionPresentation -Type $fa -Backend $Backend
            $act = New-Action -Id $fa -Label $pres.label -Kind $pres.kind -Severity $pres.severity `
                              -Help "Résolution proposée par la ligne « $($ch.label) »."
            try { $m.actions = @(@($m.actions) + $act) } catch { }
            $connues += $fa
        }
    }

    # Droits : chaque action dit si elle est lancable par CE compte, et sinon pourquoi
    # (D65). C'est fait ici, une fois pour toutes, plutot que dans chaque sonde.
    foreach ($m in $modules) {
        foreach ($act in @($m.actions)) {
            if (-not $act -or -not $act.id) { continue }
            $droit = Test-ActionAllowed -Type "$($act.id)" -Backend $Backend
            try {
                if ($act -is [System.Collections.IDictionary]) {
                    $act['allowed'] = $droit.allowed
                    if (-not $droit.allowed) { $act['deniedReason'] = $droit.reason }
                } else {
                    Add-Member -InputObject $act -NotePropertyName 'allowed' -NotePropertyValue $droit.allowed -Force
                    if (-not $droit.allowed) { Add-Member -InputObject $act -NotePropertyName 'deniedReason' -NotePropertyValue $droit.reason -Force }
                }
            } catch { }
        }
    }

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

# --- FICHE MATERIELLE : ce qui ne bouge pas ----------------------------------
#
# Deuxieme export demande (l'autre etant l'etat a l'instant) : les caracteristiques
# PHYSIQUES de la machine. On les releve une fois et on les garde : une barrette de
# memoire ne change pas d'un rafraichissement a l'autre, et l'inventaire coute plusieurs
# secondes (CIM sur une dizaine de classes).
#
# Chaque section est independante et defensive : une classe CIM absente ou refusee rend
# une section vide, jamais une erreur -- une fiche partielle vaut mieux que pas de fiche.
function Get-HardwareSpecs {
    param(
        [string]$Backend = (Get-BackendRoot),
        # Releve neuf : apres un changement de materiel, ou depuis l'export.
        [switch]$Force
    )
    $cacheFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'hardware.json'
    if (-not $Force -and (Test-Path -LiteralPath $cacheFile)) {
        try {
            $j = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            $at = ConvertTo-UtcDate $j.at
            # Sept jours : le materiel ne change pas, mais une fiche eternelle survivrait
            # a un changement de disque ou de barrette sans qu'on le sache.
            if ($at -and ([datetime]::UtcNow - $at).TotalDays -lt 7) { return $j }
        } catch { }
    }

    function Lire { param([string]$Classe, [string]$Espace = 'root/cimv2')
        try { return @(Get-CimInstance -Namespace $Espace -ClassName $Classe -ErrorAction Stop) } catch { return @() }
    }
    $go = { param($octets) if ($octets) { [math]::Round(([double]$octets) / 1GB, 1) } else { $null } }

    $cs   = @(Lire 'Win32_ComputerSystem')   | Select-Object -First 1
    $bios = @(Lire 'Win32_BIOS')             | Select-Object -First 1
    $cb   = @(Lire 'Win32_BaseBoard')        | Select-Object -First 1
    $os   = @(Lire 'Win32_OperatingSystem')  | Select-Object -First 1
    $enc  = @(Lire 'Win32_SystemEnclosure')  | Select-Object -First 1

    # Portable ou fixe ? Le type de chassis le dit (8-14 et 30-32 = mobile).
    $mobile = $false
    try {
        foreach ($t in @($enc.ChassisTypes)) {
            if ((8..14) -contains [int]$t -or (30..32) -contains [int]$t) { $mobile = $true }
        }
    } catch { }

    $machine = [ordered]@{
        nom          = "$env:COMPUTERNAME"
        fabricant    = "$($cs.Manufacturer)"
        modele       = "$($cs.Model)"
        famille      = "$($cs.SystemFamily)"
        forme        = $(if ($mobile) { 'Portable' } else { 'Poste fixe' })
        numeroSerie  = "$($bios.SerialNumber)"
        uuid         = "$((@(Lire 'Win32_ComputerSystemProduct') | Select-Object -First 1).UUID)"
        os           = "$($os.Caption)"
        osVersion    = "$($os.Version)"
        osArchi      = "$($os.OSArchitecture)"
        installeLe   = $(try { ([datetime]$os.InstallDate).ToString('o') } catch { '' })
    }

    $carteMere = [ordered]@{
        fabricant = "$($cb.Manufacturer)"
        modele    = "$($cb.Product)"
        version   = "$($cb.Version)"
        bios      = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
        biosDate  = $(try { ([datetime]$bios.ReleaseDate).ToString('o') } catch { '' })
    }

    $processeurs = @(foreach ($c in (Lire 'Win32_Processor')) {
        [ordered]@{
            nom       = "$($c.Name)".Trim()
            fabricant = "$($c.Manufacturer)"
            coeurs    = [int]$c.NumberOfCores
            fils      = [int]$c.NumberOfLogicalProcessors
            frequence = [int]$c.MaxClockSpeed          # MHz
            socket    = "$($c.SocketDesignation)"
            cacheL3Ko = [int]$c.L3CacheSize
        }
    })

    # Type de memoire : le code SMBIOS, traduit. Un numero ne dit rien a personne.
    $typesMem = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'LPDDR4'; 36 = 'LPDDR5' }
    $barrettes = @(foreach ($m in (Lire 'Win32_PhysicalMemory')) {
        $t = $null
        try { if ($typesMem.ContainsKey([int]$m.SMBIOSMemoryType)) { $t = $typesMem[[int]$m.SMBIOSMemoryType] } } catch { }
        [ordered]@{
            emplacement = "$($m.DeviceLocator)"
            tailleGo    = (& $go $m.Capacity)
            type        = $(if ($t) { $t } else { '' })
            vitesse     = [int]$m.Speed                # MT/s
            fabricant   = "$($m.Manufacturer)".Trim()
            reference   = "$($m.PartNumber)".Trim()
        }
    })
    $memoire = [ordered]@{
        totalGo   = (& $go $cs.TotalPhysicalMemory)
        barrettes = $barrettes
        # Ce que la carte mere peut accueillir : utile quand on envisage une extension.
        emplacements = [int]((@(Lire 'Win32_PhysicalMemoryArray') | Select-Object -First 1).MemoryDevices)
    }

    $disques = @(foreach ($d in (Lire 'MSFT_PhysicalDisk' 'root/microsoft/windows/storage')) {
        $bus = switch ([int]$d.BusType) { 7 { 'USB' } 8 { 'RAID' } 11 { 'SATA' } 17 { 'NVMe' } default { '' } }
        $media = switch ([int]$d.MediaType) { 3 { 'Disque dur' } 4 { 'SSD' } 5 { 'SCM' } default { '' } }
        [ordered]@{
            modele    = "$($d.FriendlyName)".Trim()
            tailleGo  = (& $go $d.Size)
            type      = $media
            bus       = $bus
            sante     = $(switch ([int]$d.HealthStatus) { 0 { 'Sain' } 1 { 'A surveiller' } 2 { 'Defaillant' } default { '' } })
            firmware  = "$($d.FirmwareVersion)"
            numeroSerie = "$($d.SerialNumber)".Trim()
        }
    })
    # Repli : sur une machine ou l'espace de noms Storage manque, Win32_DiskDrive suffit.
    if (-not $disques.Count) {
        $disques = @(foreach ($d in (Lire 'Win32_DiskDrive')) {
            [ordered]@{ modele = "$($d.Model)".Trim(); tailleGo = (& $go $d.Size)
                        type = ''; bus = "$($d.InterfaceType)"; sante = ''
                        firmware = "$($d.FirmwareRevision)".Trim(); numeroSerie = "$($d.SerialNumber)".Trim() }
        })
    }

    # LA VRAM NE SE LIT PAS DANS AdapterRAM : ce champ est un entier 32 bits signe, il
    # plafonne a 4 Go et rend n'importe quoi au-dela (une RTX 4070 de 8 Go y apparait
    # avec 4 Go, parfois moins). La vraie valeur est dans le registre du pilote,
    # qwMemorySize, sur 64 bits.
    $vramParNom = @{}
    try {
        $classe = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        # SilentlyContinue et non Stop : une des sous-cles de cette classe est refusee
        # meme a un administrateur (« Requested registry access is not allowed »), et
        # avec Stop l'enumeration s'arretait AVANT la carte NVIDIA -- la VRAM retombait
        # alors sur AdapterRAM, qui plafonne a 4 Go. Constate ici meme.
        foreach ($k in (Get-ChildItem -Path $classe -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $pr = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if ($pr -and $pr.DriverDesc -and $pr.'HardwareInformation.qwMemorySize') {
                $vramParNom["$($pr.DriverDesc)"] = [math]::Round(([double]$pr.'HardwareInformation.qwMemorySize') / 1GB, 1)
            }
        }
    } catch { }

    $graphiques = @(foreach ($g in (Lire 'Win32_VideoController')) {
        $nomG = "$($g.Name)".Trim()
        [ordered]@{
            nom        = $nomG
            vramGo     = $(if ($vramParNom.ContainsKey($nomG)) { $vramParNom[$nomG] } else { (& $go $g.AdapterRAM) })
            pilote     = "$($g.DriverVersion)"
            piloteDate = $(try { ([datetime]$g.DriverDate).ToString('o') } catch { '' })
            resolution = $(if ($g.CurrentHorizontalResolution) { "$($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution)" } else { '' })
        }
    })

    # Ecrans : WmiMonitorID rend des tableaux de codes, pas des chaines.
    $texteWmi = { param($codes) if (-not $codes) { return '' }
        (-join ($codes | Where-Object { $_ -gt 0 } | ForEach-Object { [char][int]$_ })).Trim() }
    $ecrans = @(foreach ($e in (Lire 'WmiMonitorID' 'root/wmi')) {
        $taille = ''
        [ordered]@{
            fabricant = (& $texteWmi $e.ManufacturerName)
            modele    = (& $texteWmi $e.UserFriendlyName)
            serie     = (& $texteWmi $e.SerialNumberID)
            annee     = [int]$e.YearOfManufacture
        }
    })
    # Pouces : classe distincte (dimensions physiques en centimetres).
    $tailles = @(Lire 'WmiMonitorBasicDisplayParams' 'root/wmi')
    for ($i = 0; $i -lt $ecrans.Count -and $i -lt $tailles.Count; $i++) {
        try {
            $l = [double]$tailles[$i].MaxHorizontalImageSize
            $h = [double]$tailles[$i].MaxVerticalImageSize
            if ($l -gt 0 -and $h -gt 0) {
                $ecrans[$i]['pouces'] = [math]::Round([math]::Sqrt($l * $l + $h * $h) / 2.54, 1)
            }
        } catch { }
    }

    # Cartes reseau PHYSIQUES.
    #
    # Win32_NetworkAdapter.PhysicalAdapter ne suffit PAS : il repond « oui » pour le
    # Bluetooth PAN, pour les cartes de VirtualBox ou de VMware, et pour les adaptateurs
    # WAN Miniport. Get-NetAdapter -Physical, lui, s'appuie sur le type de peripherique
    # reel -- on s'en sert comme liste blanche quand il est disponible.
    $reelles = $null
    try { $reelles = @((Get-NetAdapter -Physical -ErrorAction Stop).InterfaceDescription) } catch { }
    $reseau = @(foreach ($a in (Lire 'Win32_NetworkAdapter')) {
        if (-not $a.PhysicalAdapter) { continue }
        if (-not "$($a.MACAddress)") { continue }
        if ($reelles -and ($reelles -notcontains "$($a.Description)")) { continue }
        if (-not $reelles -and "$($a.Name)" -match 'Virtual|Host-Only|Bluetooth|Miniport|Loopback') { continue }
        [ordered]@{
            nom       = "$($a.Name)".Trim()
            fabricant = "$($a.Manufacturer)".Trim()
            mac       = "$($a.MACAddress)"
            # Windows rend 0xFFFFFFFFFFFFFFFF quand le lien n'est pas etabli : cela
            # donnait « 9223372036855 Mb/s » sur la fiche. Au-dela de 100 Gb/s, la
            # valeur ne veut rien dire : on n'affiche rien plutot qu'une absurdite.
            debitMax  = $(if ($a.Speed -and ([double]$a.Speed) -lt 1e11) { [math]::Round(([double]$a.Speed) / 1e6) } else { $null })   # Mb/s
        }
    })

    $batterie = $null
    $bat = @(Lire 'Win32_Battery') | Select-Object -First 1
    if ($bat) {
        $pleine = @(Lire 'BatteryFullChargedCapacity' 'root/wmi') | Select-Object -First 1
        $batterie = [ordered]@{
            nom         = "$($bat.Name)".Trim()
            chimie      = $(switch ([int]$bat.Chemistry) { 3 { 'Nickel-Cadmium' } 4 { 'Nickel-Hydrure' } 5 { 'Lithium-ion' } 6 { 'Zinc-air' } 7 { 'Lithium-polymere' } default { '' } })
            capaciteMwh = $(if ($pleine) { [int]$pleine.FullChargedCapacity } else { $null })
            tension     = $(if ($bat.DesignVoltage) { [int]$bat.DesignVoltage } else { $null })   # mV
        }
    }

    $fiche = [pscustomobject][ordered]@{
        at          = (Get-Date).ToUniversalTime().ToString('o')
        machine     = $machine
        carteMere   = $carteMere
        processeurs = $processeurs
        memoire     = $memoire
        disques     = $disques
        graphiques  = $graphiques
        ecrans      = $ecrans
        reseau      = $reseau
        batterie    = $batterie
    }
    try {
        $d = Split-Path $cacheFile -Parent
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        ($fiche | ConvertTo-Json -Depth 12) | Out-File -FilePath $cacheFile -Encoding UTF8
    } catch { }
    return $fiche
}

# --- TACHE DE FOND D'UNE CARTE : le dire, et tant que ca dure -----------------
#
# Regle de l'utilisateur : « une carte qui lance une action en background devrait passer
# immediatement en statut operation en cours ». L'interface le marque des le clic, mais ce
# marquage ne survit pas au premier rafraichissement : c'est le SERVEUR qui doit porter la
# verite, sinon la carte redevient calme alors que le travail continue -- constate le
# 26/08 pendant l'installation de PowerShell 7 depuis la carte Comptes.
#
# Le marqueur porte le PID du processus lance : tant qu'il vit, la carte est occupee ;
# des qu'il meurt, le marqueur s'efface tout seul. Rien a nettoyer a la main, et un arret
# brutal ne laisse pas une carte occupee pour toujours.
function Get-ModuleBusyMarkPath {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'run' -File ('busy-' + $Module + '.json')
}

function Set-ModuleBusyMark {
    param(
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][string]$Label,
        [int]$ProcessId,
        [string]$Action = '',
        # Ce que ce travail MOBILISE : c'est ce qui permettra de refuser ce qui le
        # generait, et seulement cela (D93).
        [string[]]$Resources = @(),
        [string]$Backend = (Get-BackendRoot)
    )
    $f = Get-ModuleBusyMarkPath -Module $Module -Backend $Backend
    $d = Split-Path $f -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    if (-not $Resources -or -not $Resources.Count) { $Resources = @(Get-ActionResources -Type $Action) }
    $o = [ordered]@{ label = $Label; pid = $ProcessId; action = $Action
                     resources = @($Resources)
                     at = (Get-Date).ToUniversalTime().ToString('o') }
    try { ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath $f -Encoding UTF8 } catch { }
}

function Get-ModuleBusyMark {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    $f = Get-ModuleBusyMarkPath -Module $Module -Backend $Backend
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $o = $null
    try { $o = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json } catch { }
    if (-not $o) { return $null }
    $vivant = $false
    try { $vivant = [bool](Get-Process -Id ([int]$o.pid) -ErrorAction Stop) } catch { $vivant = $false }
    if (-not $vivant) {
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $o
}

# --- CE QUE VIGIE OCCUPE SUR LA MACHINE --------------------------------------
#
# Demande du 27/08 : « ce serait bien de mettre le stockage Vigie (pour tous les
# utilisateurs) et ainsi faire le suivi de la conso de notre app ». Une application qui
# surveille l'espace disque des autres se doit de dire ce qu'elle prend elle-meme.
#
# Trois postes, et ils ne se ressemblent pas :
#   - le PROGRAMME       : l'installation partagee (Program Files), la meme pour tous ;
#   - les DONNEES        : cache, historique, journaux -- UN JEU PAR COMPTE ;
#   - le DEPOT           : sur un poste de developpement, les sources et dist/.
#
# Les donnees des AUTRES comptes ne sont lisibles qu'en etant eleve : sans elevation on
# rend ce qu'on voit, et on le DIT plutot que d'annoncer un total faux.
function Get-VigieFootprint {
    param([string]$Backend = (Get-BackendRoot))

    function Poids {
        param([string]$Chemin)
        if (-not (Test-PathSafe $Chemin)) { return 0 }
        try {
            return [long]((Get-ChildItem -LiteralPath $Chemin -Recurse -File -Force -ErrorAction SilentlyContinue |
                           Measure-Object -Property Length -Sum).Sum)
        } catch { return 0 }
    }

    $partagee = Get-SharedInstallPath
    $programme = Poids $partagee

    # Les donnees de CHAQUE compte : %LOCALAPPDATA%\Sowapps\Vigie, et l'ancien
    # emplacement sans editeur pour les installations d'avant D72.
    $parCompte = @()
    $inaccessibles = 0
    $varDuCompteCourant = $null
    foreach ($c in @(Get-UserAccounts -Backend $Backend)) {
        $local = Join-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $c.name) 'AppData\Local'
        $total = 0
        $vu = $false
        foreach ($d in @((Join-Path (Join-Path $local 'Sowapps') 'Vigie'), (Join-Path $local 'Vigie'))) {
            if (Test-PathSafe $d) { $vu = $true; $total += (Poids $d) }
        }
        # Un dossier present mais illisible rend 0 : on ne peut pas le distinguer d'un
        # dossier vide sans elevation. On compte donc l'incertitude a part.
        if ($vu -and $total -eq 0 -and -not $c.current) { $inaccessibles++ }
        # LE COMPTE COURANT sait ou sont SES donnees : Get-VarRoot fait foi. Sur un poste
        # de developpement elles vivent dans le depot (var/), pas dans %LOCALAPPDATA% --
        # sans cela on annoncait 320 o pour un compte qui en occupe des megaoctets.
        if ($c.current) {
            $sien = Get-VarRoot -Backend $Backend
            if ($sien -and (Test-Path -LiteralPath $sien)) {
                $total = Poids $sien
                $vu = $true
                $varDuCompteCourant = $sien
            }
        }
        if ($vu) { $parCompte += [pscustomobject]@{ name = $c.name; bytes = $total; current = $c.current } }
    }

    # Le depot de developpement, s'il est distinct de l'installation partagee.
    $depot = Get-RepoRoot
    $sources = 0
    if ($depot -and (-not $partagee -or $depot -ne $partagee)) {
        $sources = Poids $depot
        # Le var/ du compte courant est DEJA compte dans les donnees : on le retire du
        # depot, sinon le total le compte deux fois.
        if ($varDuCompteCourant -and $varDuCompteCourant.StartsWith($depot, [StringComparison]::OrdinalIgnoreCase)) {
            $sources = [Math]::Max(0, $sources - (Poids $varDuCompteCourant))
        }
    }

    $donnees = 0
    foreach ($x in $parCompte) { $donnees += $x.bytes }

    [pscustomobject][ordered]@{
        programme     = $programme          # installation partagee
        programmePath = $partagee
        donnees       = $donnees            # somme des donnees par compte
        parCompte     = $parCompte
        sources       = $sources            # depot de developpement (0 en usage normal)
        sourcesPath   = $(if ($sources) { $depot } else { $null })
        total         = ($programme + $donnees + $sources)
        complet       = (Test-IsElevated) -and ($inaccessibles -eq 0)
        inaccessibles = $inaccessibles
    }
}

# --- CE QUI TOURNE, POUR TOUT LE MONDE (D95) ---------------------------------
#
# Les notifications vivaient dans la PAGE : une seconde fenetre ouverte ne savait rien
# d'une operation lancee depuis la premiere, et une page ouverte APRES le depart d'un
# deploiement n'en voyait pas la moindre trace. Or le serveur, lui, sait : il tient les
# marqueurs d'operation et leurs resultats.
#
# On rend donc l'etat complet -- ce qui tourne, et ce qui vient de se terminer -- et
# chaque page s'y accorde. Le serveur est la source, les pages sont des reflets.
function Get-RunningOperations {
    param([string]$Backend = (Get-BackendRoot))
    $ops = @()
    $dossier = Split-Path (Get-ModuleBusyMarkPath -Module 'x' -Backend $Backend) -Parent
    if (Test-Path -LiteralPath $dossier) {
        foreach ($f in @(Get-ChildItem -LiteralPath $dossier -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)) {
            $module = ($f.BaseName -replace '^busy-', '')
            $m = Get-ModuleBusyMark -Module $module -Backend $Backend
            if (-not $m) { continue }
            $ops += [pscustomobject][ordered]@{
                module    = $module
                label     = "$($m.label)"
                action    = "$($m.action)"
                resources = @($m.resources)
                at        = "$($m.at)"
            }
        }
    }
    return $ops
}

# Les resultats RECENTS : ce qui s'est termine assez recemment pour qu'une page ouverte
# entre-temps ait encore interet a le montrer. Au-dela, c'est de l'histoire : elle vit
# sur la carte concernee, pas dans les notifications.
function Get-RecentOperationResults {
    param([int]$Minutes = 15, [string]$Backend = (Get-BackendRoot))
    $res = @()
    $dossier = Split-Path (Get-ModuleLastRunPath -Module 'x' -Backend $Backend) -Parent
    if (-not (Test-Path -LiteralPath $dossier)) { return $res }
    $limite = [datetime]::UtcNow.AddMinutes(-$Minutes)
    foreach ($f in @(Get-ChildItem -LiteralPath $dossier -Filter 'lastrun-*.json' -File -ErrorAction SilentlyContinue)) {
        $module = ($f.BaseName -replace '^lastrun-', '')
        $r = Get-ModuleLastRun -Module $module -Backend $Backend
        if (-not $r) { continue }
        $quand = ConvertTo-UtcDate $r.at
        if (-not $quand -or $quand -lt $limite) { continue }
        $res += [pscustomobject][ordered]@{
            module  = $module
            label   = "$($r.label)"
            action  = "$($r.action)"
            code    = [int]$r.code
            seconds = [int]$r.seconds
            log     = "$($r.log)"
            error   = "$($r.error)"
            at      = "$($r.at)"
        }
    }
    return $res
}

# --- QUI TIENT QUOI : le verrou par RESSOURCE (D93) ---------------------------
#
# Bloquer TOUTES les actions des qu'une operation tourne etait grossier -- et surtout
# ca ne protegeait rien : l'interface grisait des boutons, mais une page restee ouverte
# pouvait toujours envoyer l'action au serveur. C'est le SERVEUR qui doit arbitrer.
#
# Une action declare donc ce qu'elle MOBILISE. Deux actions qui ne partagent aucune
# ressource peuvent tourner ensemble ; vérifier les mises a jour d'un gestionnaire
# pendant qu'une analyse de disque tourne n'a aucune raison d'etre interdit.
#
# La ressource 'machine' est particuliere : elle croise TOUT. C'est celle des gestes qui
# touchent l'installation entiere ou relancent l'application.
$script:RessourcesParAction = @{
    # Ce qui touche l'installation ou relance Vigie : rien d'autre pendant ce temps.
    'vigie-update'         = @('machine')
    'pwsh-install-machine' = @('machine')
    'system-restart'       = @('machine')
    'repair-tasks'         = @('taches')
    # Windows Update : le verrou, l'analyse et l'installation se marchent dessus.
    'update-mode-on'       = @('windows-update')
    'update-mode-off'      = @('windows-update')
    'wu-scan'              = @('windows-update')
    'wu-install'           = @('windows-update')
    'wu-list-pending'      = @('windows-update')
    'run-audit'            = @('windows-update')
    # Gestionnaires de paquets : un seul a la fois, ils partagent le meme installeur.
    'pkg-upgrade'          = @('paquets')
    'pkg-check-updates'    = @('paquets')
    'pkg-list-updates'     = @()               # lecture d'un cache : rien a reserver
    # Disque, reseau, WSL, comptes.
    'disk-analyze'         = @('disque')
    'disk-analyze-stop'    = @()               # ARRETER doit rester possible pendant
    'disk-tree'            = @()               # lecture d'un cache
    'net-speedtest'        = @('reseau')
    'net-dns-flush'        = @('reseau')
    'net-publicip'         = @()
    'wsl-start'            = @('wsl')
    'wsl-restart'          = @('wsl')
    'wsl-shutdown'         = @('wsl')
    'toggle-vbs'           = @('securite')
    'toggle-hvci'          = @('securite')
    'accounts-refresh'     = @('comptes')
    'diag-account-logs'    = @('comptes')
}

# Ce qu'une action mobilise. Par defaut : RIEN -- une action non declaree est supposee
# inoffensive (ouvrir un dossier, lire un cache). On declare ce qui gene, pas l'inverse :
# une liste par defaut trop large finirait par tout bloquer sans qu'on sache pourquoi.
function Get-ActionResources {
    param([Parameter(Mandatory)][string]$Type)
    if ($script:RessourcesParAction.ContainsKey($Type)) { return @($script:RessourcesParAction[$Type]) }
    return @()
}

# Les ressources actuellement TENUES, et par quoi. On relit les marqueurs vivants : un
# marqueur dont le processus est mort ne tient plus rien (il s'efface a la lecture).
function Get-HeldResources {
    param([string]$Backend = (Get-BackendRoot))
    $tenues = @()
    $dossier = Split-Path (Get-ModuleBusyMarkPath -Module 'x' -Backend $Backend) -Parent
    if (-not (Test-Path -LiteralPath $dossier)) { return $tenues }
    foreach ($f in @(Get-ChildItem -LiteralPath $dossier -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)) {
        $module = ($f.BaseName -replace '^busy-', '')
        $m = Get-ModuleBusyMark -Module $module -Backend $Backend
        if (-not $m) { continue }
        foreach ($r in @($m.resources)) {
            if ("$r") { $tenues += [pscustomobject]@{ resource = "$r"; label = "$($m.label)"; module = $module } }
        }
    }
    return $tenues
}

# Peut-on lancer CETTE action maintenant ? Rend $null si oui, sinon la raison, en clair.
function Test-ActionResourcesFree {
    param([Parameter(Mandatory)][string]$Type, [string]$Backend = (Get-BackendRoot))
    $veut = @(Get-ActionResources -Type $Type)
    if (-not $veut.Count) { return $null }
    $tenues = @(Get-HeldResources -Backend $Backend)
    if (-not $tenues.Count) { return $null }
    foreach ($t in $tenues) {
        # 'machine' croise tout, dans les deux sens.
        if ($t.resource -eq 'machine' -or $veut -contains 'machine' -or $veut -contains $t.resource) {
            return ("« " + $t.label + " » est en cours et utilise déjà " +
                    $(if ($t.resource -eq 'machine') { "toute la machine" } else { "la même ressource (" + $t.resource + ")" }) +
                    ". Réessayez quand cette opération sera terminée.")
        }
    }
    return $null
}

# --- LE SORT D'UNE TACHE DE FOND : garde, puis dit ---------------------------
#
# « Le suivi des erreurs est primordial » : une action longue ne peut pas echouer en
# silence. Le veilleur (workers/watched-action.worker.ps1) ecrit ici ce qu'il a constate ;
# la sonde de la carte le relit et en fait une ligne, verte ou rouge.
function Get-ModuleLastRunPath {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'cache' -File ('lastrun-' + $Module + '.json')
}

function Set-ModuleLastRun {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Action = '', [string]$Label = '',
        [Parameter(Mandatory)][int]$Code,
        [int]$Seconds = 0, [string]$Log = '', [string]$Error = '',
        [string]$Backend = (Get-BackendRoot)
    )
    $f = Get-ModuleLastRunPath -Module $Module -Backend $Backend
    $d = Split-Path $f -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $o = [ordered]@{ action = $Action; label = $Label; code = $Code; seconds = $Seconds
                     log = $Log; error = $Error; at = (Get-Date).ToUniversalTime().ToString('o') }
    try { ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath $f -Encoding UTF8 } catch { }
}

function Get-ModuleLastRun {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    $f = Get-ModuleLastRunPath -Module $Module -Backend $Backend
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch { return $null }
}

function Clear-ModuleLastRun {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    Remove-Item -LiteralPath (Get-ModuleLastRunPath -Module $Module -Backend $Backend -VarRoot $VarRoot) `
                -Force -ErrorAction SilentlyContinue
}

function Clear-ModuleBusyMark {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    Remove-Item -LiteralPath (Get-ModuleBusyMarkPath -Module $Module -Backend $Backend) `
                -Force -ErrorAction SilentlyContinue
}

# LA facon de lancer un travail long. Une action ne lance plus rien elle-meme : elle
# passe par ici, et le sort du travail est garanti d'etre constate.
function Start-WatchedAction {
    param(
        [Parameter(Mandatory)][string]$Module,     # carte concernee (id du module)
        [Parameter(Mandatory)][string]$Probe,      # sonde a invalider a la fin
        [Parameter(Mandatory)][string]$Label,      # « Deploiement », « Installation de... »
        [Parameter(Mandatory)][string]$File,       # programme a lancer
        [string[]]$Arguments = @(),
        [string]$Action = '',                      # id de l'action, pour l'interface
        [string]$Log = '',
        [string]$Backend = (Get-BackendRoot)
    )
    $charge = @{ module = $Module; probe = $Probe; label = $Label; action = $Action
                 resources = @(Get-ActionResources -Type $Action)
                 file = $File; arguments = @($Arguments); log = $Log }
    $json = ($charge | ConvertTo-Json -Compress -Depth 6)
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $exe = $null
    try { $exe = (Get-Process -Id $PID).Path } catch { }
    if (-not $exe) { $exe = 'pwsh.exe' }
    $veilleur = Join-Path (Join-Path $Backend 'workers') 'watched-action.worker.ps1'
    if (-not (Test-Path -LiteralPath $veilleur)) { throw "Veilleur introuvable : $veilleur" }
    # Le resultat precedent disparait DES LE LANCEMENT : sinon la carte afficherait
    # l'echec d'hier pendant le travail d'aujourd'hui.
    Clear-ModuleLastRun -Module $Module -Backend $Backend
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName  = $exe
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$veilleur`" -Backend `"$Backend`" -ArgsB64 $b64"
    $psi.UseShellExecute  = $false
    $psi.CreateNoWindow   = $true
    $psi.WindowStyle      = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = $Backend
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($p) { return $p.Id }
    return $null
}

# La ligne que la carte affiche apres coup : rien tant qu'aucun travail n'a eu lieu,
# une ligne verte s'il a reussi, une ligne ROUGE avec le journal s'il a echoue.
function New-LastRunField {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Key = 'lastrun',
        [string]$Backend = (Get-BackendRoot)
    )
    $r = Get-ModuleLastRun -Module $Module -Backend $Backend
    if (-not $r) { return $null }
    $quand = ''
    try { $quand = (ConvertTo-UtcDate $r.at).ToLocalTime().ToString('dd/MM/yyyy HH:mm') } catch { }
    $duree = if ([int]$r.seconds -ge 60) { [string][int]([int]$r.seconds / 60) + ' min' } else { "$([int]$r.seconds) s" }
    if ([int]$r.code -eq 0) {
        # REUSSI : la DATE suffit (regle utilisateur du 27/08). Une operation qui a
        # abouti n'a rien a raconter sur la carte ; la duree et le journal restent
        # disponibles dans le detail de la ligne, pour qui les cherche.
        return (New-Field -Key $Key -Label "$($r.label)" -Value $quand `
                          -Kind 'text' -Status 'ok' `
                          -Help "Dernière opération lancée depuis cette carte : elle a abouti." `
                          -Guide ("Durée : " + $duree +
                                  $(if ($r.log) { [Environment]::NewLine + "Journal : " + $r.log } else { '' })))
    }
    $detail = if ($r.error) { "$($r.error)" } else { "code de sortie " + [int]$r.code }
    return (New-Field -Key $Key -Label "$($r.label)" -Value ("ÉCHEC le " + $quand + " — " + $detail) `
                      -Kind 'text' -Status 'error' `
                      -Help "La dernière opération lancée depuis cette carte a échoué. Elle n'a pas abouti : rien ne s'est fait à moitié sans le dire." `
                      -Guide $(if ($r.log) { "Journal complet : " + $r.log } else { '' }))
}

# --- QUELS COMPTES Windows ont Vigie (D65) ------------------------------------
# L'ordinateur a plusieurs comptes ; l'utilisateur choisit ceux qui ont Vigie, et peut
# changer d'avis a tout moment (exigence : « un outil doit toujours permettre de changer
# quel compte a acces »).
#
# Activer un compte = lui poser SA tache planifiee de demarrage. Rien d'autre : les
# reglages sont deja par compte (couche %LOCALAPPDATA%), et les donnees d'execution
# suivent le compte des que l'installation n'est pas inscriptible (Get-VarRoot).
#
# Le niveau d'execution suit le COMPTE, pas notre envie : `Highest` pour un
# administrateur, `Limited` pour un compte standard. Donner Highest a un compte standard
# ne marcherait pas -- et ne DOIT pas marcher : Vigie ne donne rien de plus que Windows.
$script:VigieTaskPrefix = 'Vigie - '

# QUEL pwsh un AUTRE compte peut-il lancer ?
#
# Piege coute cher, constate le 26/08 : la tache de « Famille » a ete creee avec
# (Get-Command pwsh).Source, qui vaut ici
# C:\Users\fhaza\AppData\Local\Microsoft\WindowsApps\pwsh.exe -- un chemin situe dans
# LE PROFIL DE L'ADMINISTRATEUR. Aucun autre compte ne peut lire ca, et l'alias Store
# renvoie de toute facon vers un paquet MSIX enregistre pour le seul compte qui l'a
# installe. La tache s'est donc creee sans erreur... et n'a jamais rien lance chez
# Famille : Vigie ne demarrait pas, sans le moindre message.
#
# Seule une installation MACHINE (le MSI, sous Program Files) convient. On la cherche, et
# si elle manque, on REFUSE d'activer le compte en disant quoi faire -- plutot que de
# poser une tache qui echouera en silence a chaque ouverture de session.
# COMMENT on installe PowerShell 7 pour la machine. Definition UNIQUE (D15) : le script
# d'installation et le bouton de la carte Comptes lancent exactement la meme chose.
# `--scope machine` est le point essentiel : sans lui, winget pose le paquet MSIX dans le
# profil de celui qui installe, et les autres comptes ne peuvent pas le lancer.
function Get-SharedPwshInstallArgs {
    # --installer-type msi : SANS lui, winget choisit le paquet MSIX et tente de le
    # « provisionner » pour tous les comptes -- operation qui echoue sur cette machine
    # avec 0x80070005 (journal winget du 26/08 : ProvisionPackageOperation). Or c'est
    # justement le MSI qu'on veut : lui pose pwsh.exe dans C:\Program Files\PowerShell\7,
    # un vrai chemin que toutes les sessions peuvent lancer, sans enregistrement par
    # compte. Le MSIX, meme provisionne, reste un paquet par utilisateur.
    @('install', '--id', 'Microsoft.PowerShell', '-e', '--scope', 'machine',
      '--installer-type', 'msi',
      '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements',
      '--silent', '--disable-interactivity')
}

function Get-SharedPwshPath {
    $racines = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($r in $racines) {
        $d = Join-Path $r 'PowerShell'
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $trouves = @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending |
                     ForEach-Object { Join-Path $_.FullName 'pwsh.exe' } |
                     Where-Object { Test-Path -LiteralPath $_ })
        if ($trouves.Count) { return $trouves[0] }
    }
    return $null
}


# Le groupe des administrateurs par son SID : le nom depend de la langue de Windows
# (« Administrateurs » ici, « Administrators » ailleurs) -- le SID, non.
function Test-LocalAccountIsAdmin {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $grp = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
        $membres = @(Get-LocalGroupMember -Group $grp.Name -ErrorAction Stop)
        return [bool](@($membres | Where-Object { "$($_.Name)" -like "*\$Name" }).Count -gt 0)
    } catch { return $false }
}

# Le principal d'une tache s'ecrit « MACHINE\compte » ou « compte » selon l'outil qui
# l'a creee. On compare le NOM DE COMPTE, sans expression reguliere : les echappements de
# l'antislash sont un nid a fautes (une regex mal echappee a fait echouer tout l'inventaire
# des comptes, silencieusement, sur chaque compte de la machine).
function Test-TaskUserIs {
    param([string]$UserId, [Parameter(Mandatory)][string]$Name)
    if (-not $UserId) { return $false }
    # [char]92 = l antislash, construit plutot qu ecrit : les couches d ecriture
    # successives mangent les echappements (constate plusieurs fois ce jour).
    $court = @(("$UserId").Split([char]92))[-1]
    return ($court -eq $Name)
}

# L'INSTALLATION EST-ELLE PARTAGEE ? Autrement dit : un autre compte de la machine
# peut-il seulement LIRE l'application ?
#
# La question n'est pas theorique : sur un poste de developpement (ou un clone du depot),
# Vigie vit dans l'espace personnel de quelqu'un, et proposer de l'activer pour un autre
# compte serait proposer une tache qui echouerait en silence a chaque ouverture de session
# (releve par l'utilisateur). On regarde donc les droits REELS, on ne suppose rien.
#
# Groupes qui, s'ils ont la lecture, rendent l'installation accessible a tous :
#   S-1-5-32-545 Utilisateurs | S-1-1-0 Tout le monde | S-1-5-11 Utilisateurs authentifies
function Test-InstallationPartagee {
    param([string]$Path = (Get-RepoRoot))
    $sids = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        foreach ($ace in $acl.Access) {
            if ("$($ace.AccessControlType)" -ne 'Allow') { continue }
            $sid = $null
            try { $sid = "$($ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value)" } catch { }
            if (-not $sid -or $sids -notcontains $sid) { continue }
            if (("$($ace.FileSystemRights)" -match 'Read|ReadAndExecute|Modify|FullControl')) { return $true }
        }
    } catch { }
    return $false
}

# OU se trouve l'installation PARTAGEE, celle que tous les comptes peuvent lire ?
#
# Sur un poste de developpement, Vigie tourne depuis le depot (illisible par les autres) ;
# une copie deployee peut exister a cote. La tache de demarrage d'un compte doit pointer
# vers CELLE-LA, sinon elle echoue en silence a chaque ouverture de session -- c'est
# exactement le piege releve : le deploiement etait fait, mais la tache aurait vise le
# depot personnel.
function Get-SharedInstallPath {
    # Program Files est lisible par tous les comptes PAR CONSTRUCTION : une installation
    # qui s'y trouve est partagee, sans qu'on ait besoin d'interroger les ACL. On garde la
    # lecture des droits pour les emplacements hors Program Files (choix de l'utilisateur).
    # La version precedente s'appuyait uniquement sur Get-Acl et repondait « non partagee »
    # depuis le serveur alors que le deploiement etait fait -- diagnostic difficile.
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($b in $bases) {
        foreach ($nom in @((Join-Path 'Sowapps' 'Vigie'), 'Vigie')) {
            $c = Join-Path $b $nom
            # Chemin construit par Join-Path : un antislash litteral a deja ete mange par
            # mes outils d ecriture et transforme en tabulations (constate ici meme).
            $marqueur = Join-Path (Join-Path (Join-Path $c 'apps') 'tray') 'tray.ps1'
            if (Test-Path -LiteralPath $marqueur) { return $c }
        }
    }
    # Installation hors Program Files : c'est l'ACL qui tranche.
    if (Test-InstallationPartagee) { return (Get-RepoRoot) }
    return $null
}
# Ce qui CLOCHE, en clair, pour l'afficher. $null si tout va bien.
# DEUX NATURES DE DEFAUT, et une seule se repare.
#
#   STRUCTURE : l'interpreteur, le chemin, l'activation. Ca se corrige tout de suite.
#   HISTOIRE  : la tache n'a jamais tourne, ou son dernier lancement a echoue. Aucune
#               reecriture n'efface ca -- seule sa prochaine execution le dira.
#
# Les confondre menait a reecrire une tache parfaitement saine, puis a reannoncer le meme
# defaut : « reecrite, mais : <exactement ce qu'on venait de lire> » (constate le 28/08).
# ECRIRE UNE PROPRIETE QUI N'EXISTE PEUT-ETRE PAS ENCORE.
#
# Un objet rendu par ConvertFrom-Json a une forme FIGEE : ses proprietes sont celles du
# JSON, et lui en assigner une autre LEVE une erreur. Quand ce JSON est un cache ecrit par
# une version anterieure du produit, tout code qui ajoute un champ casse silencieusement
# -- et la valeur perimee reste affichee. C'est ce qui a fait annoncer « 1 tache hors
# service » pour une tache saine (28/08) : le cache de la veille avait le dernier mot.
#
# A utiliser des qu'on ecrit dans un objet qui PEUT venir d'un cache ou d'une API.
function Set-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if (-not $Object) { return }
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $null -Force
    }
    $Object.$Name = $Value
}

# UN COMPTE PEUT-IL LIRE CE FICHIER ? La question n'est pas theorique : « Famille » a
# tous les droits sur C:\EspaceRestreint et Workspaces, et AUCUN a partir de Git\. Sa
# tache lancait donc un script qu'elle ne pouvait pas ouvrir, et PowerShell rendait 64 --
# « impossible d'ouvrir le fichier » -- sans le moindre journal (constate le 28/08).
#
# ON NE REMONTE PAS LE CHEMIN. Windows accorde par defaut aux utilisateurs le
# « contournement de verification transversale » : traverser un dossier ne demande aucun
# droit dessus, seuls comptent ceux du fichier vise. Remonter chaque niveau ajoutait des
# verdicts qui variaient selon qui posait la question -- une session elevee lisait des ACL
# qu'une session ordinaire ne lisait pas, et les deux ne repondaient pas pareil.
function Test-PathReadableByAccount {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sid,
        # Le compte appartient-il aux administrateurs ? Sans cette precision, on prendrait
        # un droit accorde aux administrateurs pour un droit accorde a tous.
        [switch]$IsAdmin
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $acl = $null
    try { $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop } catch { return $true }   # on ne conclut pas d'une ACL illisible

    # Groupes qui contiennent n'importe quel compte local ORDINAIRE. « Administrateurs »
    # n'en est pas : le compter faisait dire que Famille pouvait lire un dossier reserve a
    # fhaza, aux administrateurs et a SYSTEM -- le garde-fou se trompait exactement comme
    # le code qu'il devait proteger.
    $universal = @('S-1-1-0', 'S-1-5-32-545', 'S-1-5-11')
    if ($IsAdmin) { $universal += 'S-1-5-32-544' }

    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        if (-not ($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read)) { continue }
        $ruleSid = try { $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { '' }
        if ($ruleSid -eq $Sid -or $universal -contains $ruleSid) { return $true }
    }
    return $false
}

function Get-VigieTaskStructureAilment {
    param([Parameter(Mandatory)]$Task)
    $a = @($Task.Actions)[0]
    if (-not $a) { return "la tâche ne lance rien" }
    $exe = "$($a.Execute)".Trim('"')
    if (-not $exe) { return "aucun interpréteur" }
    if (-not (Test-Path -LiteralPath $exe)) { return "l'interpréteur n'existe plus : $exe" }
    # EXISTER NE SUFFIT PAS. Deux chemins sont valides a l'oeil et pourtant inutilisables :
    #   - un paquet MSIX (C:\Program Files\WindowsApps\...) n'est lancable que par les comptes
    #     pour lesquels il est ENREGISTRE, et son dossier reste sur le disque apres
    #     desinscription : Test-Path repond oui, le lancement echoue ;
    #   - un chemin dans le profil d'un compte (C:\Users\quelqu-un\...) est illisible
    #     par les autres.
    # C'est exactement ce qui a empeche Vigie de demarrer chez « Famille » (D79, D83).
    $dossierProfils = Join-Path $env:SystemDrive 'Users'
    $dossierMsix    = Join-Path $env:ProgramFiles 'WindowsApps'
    if ($exe.StartsWith($dossierMsix, [StringComparison]::OrdinalIgnoreCase)) {
        return "interpréteur MSIX, enregistré par compte : $exe"
    }
    if ($exe.StartsWith($dossierProfils, [StringComparison]::OrdinalIgnoreCase)) {
        return "interpréteur dans un profil, illisible par les autres comptes : $exe"
    }
    if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
        if (-not (Test-Path -LiteralPath $Matches[1])) { return ("l'application n'est plus là : " + $Matches[1]) }
    }
    # DESACTIVEE, c'est structurel : la tache est la, bien formee, et Windows refuse de
    # la lancer. Ca se repare d'un geste (Enable-ScheduledTask), donc ca appartient ici
    # et pas a l'histoire.
    if ("$($Task.State)" -eq 'Disabled') { return "la tâche est désactivée dans Windows" }

    # PAS DE VERDICT DE LISIBILITE ICI, et c'est un choix.
    #
    # Cette meme verification sert a CHOISIR le chemin d'une tache (Set-VigieAccountEnabled)
    # et elle y fait ses preuves : elle a bien renvoye « Famille » du depot, illisible pour
    # elle, vers l'installation partagee. Mais quand elle JUGE une tache existante, elle a
    # declare illisible un fichier que la meme fonction, appelee depuis une session
    # ordinaire sur le meme fichier et le meme compte, disait lisible.
    #
    # Un diagnostic qui se contredit selon l'observateur ne diagnostique rien -- et
    # afficher « cassé » sur ce qui marche est pire que se taire (D105). Tant que cet
    # ecart n'est pas compris, la question ne se pose qu'au moment ou l'on ecrit une
    # tache, la ou une erreur se corrige immediatement.

    # UNE TACHE QUI LANCE LE DEPOT est un defaut structurel : le dossier de travail peut
    # etre illisible pour le compte qui demarre -- « Famille » n'a aucun droit sur
    # C:\EspaceRestreint, VigieService non plus -- et il peut bouger ou disparaitre. La
    # tache ne demarre alors rien, sans un mot.
    #
    # Ce n'est PAS une question d'environnement declare : Vigie tourne toujours depuis
    # l'installation partagee, developpement compris. En dev, c'est la SOURCE de ce qu'on
    # y deploie qui change -- une branche plutot qu'une version publiee -- et cela se lit
    # dans le numero de version. Comparer l'emplacement a la declaration signalait donc un
    # ecart permanent qui n'avait rien a reparer (constate le 30/08).
    if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
        if ((Get-PathStage -Path $Matches[1]) -ne 'prod') {
            return "elle démarre depuis le dépôt de travail, pas depuis l'installation partagée"
        }
    }

    return $null
}

# L'etat COMPLET : la structure, puis l'histoire.
function Get-VigieTaskHistoryAilment {
    param([Parameter(Mandatory)]$Task)
    $a = @($Task.Actions)[0]
    if (-not $a) { return $null }
    # UNE TACHE SAINE SUR LE PAPIER PEUT N'AVOIR JAMAIS TOURNE.
    #
    # Tout ce qui precede examine la DEFINITION : l'interpreteur existe, le script existe.
    # Ca ne dit rien de ce qui s'est passe. « Vigie activee » s'affichait donc pour un
    # compte ou Vigie n'avait jamais demarre une seule fois -- constate sur Famille le
    # 28/08 : tache presente, session ouverte, aucun journal nulle part.
    $info = $null
    try { $info = $Task | Get-ScheduledTaskInfo -ErrorAction Stop } catch { }
    if ($info) {
        # NON SIGNE, ET C'EST TOUT LE PROBLEME. Windows rend un HRESULT sur 32 bits non
        # signes : 0x800710E0 vaut 2 147 946 720, au-dela de Int32. Le cast levait, et
        # l'action entiere echouait sur « Cannot convert value ... to type System.Int32 »
        # -- au moment precis ou l'on cherchait a lire pourquoi une tache avait echoue.
        $code = [long]$info.LastTaskResult
        # Les codes qui ne sont PAS des echecs : 0 succes ; 0x00041301 en cours ;
        # 0x00041302 terminaison demandee ; 0x00041303 jamais lancee (traite juste apres).
        $benins = @(0, 267009, 267010, 267011)
        $jamais = (-not $info.LastRunTime) -or ($info.LastRunTime.Year -lt 2000) -or ($code -eq 267011)
        if ($jamais) { return "la tâche n'a jamais été exécutée" }
        if ($benins -notcontains $code) {
            # UN ECHEC PLUS VIEUX QUE LE CODE INSTALLE NE CONCERNE PLUS PERSONNE.
            #
            # La tache de « Famille » avait echoue a 05:55 ; le correctif a ete deploye a
            # 08:44. Continuer a l'afficher demandait a l'utilisateur de « confirmer »
            # l'echec d'un programme qui n'existe plus -- alors que le deploiement, lui,
            # s'etait fait tout seul. On compare donc la date de l'echec a celle du
            # fichier que la tache lance : si l'application a change depuis, on se tait.
            $depuis = $null
            if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
                try { $depuis = (Get-Item -LiteralPath $Matches[1] -ErrorAction Stop).LastWriteTime } catch { }
            }
            if ($depuis -and $depuis -gt $info.LastRunTime) { return $null }
            return ("la dernière exécution a échoué (code 0x" + ([uint32]$code).ToString('X8') + ", le " +
                    $info.LastRunTime.ToString('dd/MM/yyyy HH:mm') + ")")
        }
    }
    return $null
}

function Get-VigieTaskAilment {
    param([Parameter(Mandatory)]$Task)
    $mal = Get-VigieTaskStructureAilment -Task $Task
    if ($mal) { return $mal }
    return (Get-VigieTaskHistoryAilment -Task $Task)
}

# Repare ce qui peut l'etre, et RAPPORTE ce qu'elle a fait. Silencieuse quand tout va
# bien. Ne cree jamais une tache absente : activer un compte reste une decision.
function Repair-VigieTasks {
    param([string]$Backend = (Get-BackendRoot))
    $faits = @()
    if (-not (Test-IsElevated)) { return $faits }
    $taches = @()
    try {
        $taches = @(Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { "$($_.TaskName)" -eq 'Vigie' -or "$($_.TaskName)".StartsWith($script:VigieTaskPrefix) })
    } catch { return $faits }

    foreach ($t in $taches) {
        $nom = "$($t.TaskName)"
        # ON NE REECRIT PAS UNE TACHE SAINE. Un defaut d'HISTOIRE -- jamais lancee, ou
        # dernier lancement en echec -- ne se corrige par aucune ecriture : il se
        # confirmera au prochain demarrage du compte, et pas avant. Le signaler, oui ;
        # pretendre le reparer, non.
        $mal = Get-VigieTaskStructureAilment -Task $t
        if (-not $mal) {
            $histoire = Get-VigieTaskHistoryAilment -Task $t
            if ($histoire) {
                $faits += [pscustomobject]@{ tache = $nom; mal = $histoire; repare = $false; attente = $true }
            }
            continue
        }
        # De QUI est cette tache ? « Vigie - X » le dit dans son nom ; « Vigie » tout court
        # le dit dans SON PRINCIPAL -- on le lit, au lieu de supposer que c'est celui qui
        # regarde. La tache historique appartient a qui l'a posee, pas au demandeur.
        $compte = if ($nom -eq 'Vigie') { ("$($t.Principal.UserId)" -split [regex]::Escape([string][char]92))[-1] }
                  else                  { $nom.Substring($script:VigieTaskPrefix.Length) }
        try {
            if ($nom -eq 'Vigie') {
                # Notre propre tache : on la reecrit avec l'interpreteur de la machine et
                # le chemin ou l'application se trouve REELLEMENT maintenant.
                $pwsh = Get-SharedPwshPath
                if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
                $tray = Join-Path (Join-Path (Get-RepoRoot) 'apps') (Join-Path 'tray' 'tray.ps1')
                if (-not $pwsh -or -not (Test-Path -LiteralPath $tray)) { continue }
                $arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $tray + '"'
                Set-ScheduledTask -TaskName $nom -Action (New-ScheduledTaskAction -Execute $pwsh -Argument $arg) -ErrorAction Stop | Out-Null
            } else {
                # Tache d'un autre compte : Set-VigieAccountEnabled sait la refaire
                # entierement (interpreteur machine, installation partagee, niveau).
                $null = Set-VigieAccountEnabled -Name $compte -Enabled $true -Backend $Backend
            }
            # UNE TACHE DESACTIVEE SE REACTIVE. Vigie savait le DIRE depuis ce matin, et
            # s'arretait la : elle reecrivait l'action puis reannoncait « desactivee »,
            # ce qui n'aide personne. Enable-ScheduledTask est le geste qui manquait.
            # Idempotent : une tache deja active ne bouge pas.
            try { Enable-ScheduledTask -TaskName $nom -ErrorAction Stop | Out-Null } catch { }

            # ON CONSTATE (D43). Reecrire la tache ne guerit pas tout : un ECHEC PASSE
            # reste inscrit dans son historique tant qu'elle n'a pas retourne au travail,
            # c'est-a-dire tant que ce compte n'a pas rouvert de session. Annoncer
            # « reparee » dans ce cas serait un faux succes -- et l'ecran continuerait a
            # afficher « hors service » juste a cote, en se contredisant (vu le 28/08).
            # ON RELIT APRES COUP, pas dans la foulee : Windows rend l'ancien etat pendant
            # un court instant apres une reecriture, et la tache paraissait encore
            # desactivee alors qu'elle ne l'etait deja plus (constate le 28/08).
            Start-Sleep -Milliseconds 400
            $apres = $null
            try { $apres = Get-VigieTaskAilment -Task (Get-ScheduledTask -TaskName $nom -ErrorAction Stop) } catch { }
            if ($apres) {
                $faits += [pscustomobject]@{ tache = $nom; mal = $mal; repare = $false; reste = $apres }
                Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-reecrite-mais' $nom $apres)
            } else {
                $faits += [pscustomobject]@{ tache = $nom; mal = $mal; repare = $true }
                Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-reparee' $nom $mal)
            }
        } catch {
            $faits += [pscustomobject]@{ tache = $nom; mal = $mal; repare = $false; erreur = "$($_.Exception.Message)" }
            Write-Log -Backend $Backend -Name 'comptes' -Level 'ERROR' `
                      -Message (Get-Label 'common.tache-non-reparee' $nom $mal $_.Exception.Message)
        }
    }
    if ($faits.Count) { Clear-ComputerAccountsCache -Backend $Backend }
    return $faits
}

function Get-VigieAccountTaskName {
    param([Parameter(Mandatory)][string]$Name)
    $script:VigieTaskPrefix + $Name
}

# Les comptes de la machine, avec pour chacun : est-il administrateur, Vigie demarre-t-il
# avec lui, et par quelle tache. La tache historique s'appelle « Vigie » tout court : elle
# compte comme active pour le compte qu'elle vise, sinon l'ecran dirait faussement
# « inactif » a l'utilisateur qui s'en sert depuis le debut.
# L'inventaire coute environ deux secondes (comptes, groupes, profils, taches) et ne
# change qu'exceptionnellement : on le MEMORISE. Un jour de validite, un bouton pour
# forcer le releve, et toute activation de compte l'invalide d'elle-meme.
$script:ComptesTTLHeures = 24

function Get-ComputerAccountsCachePath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'accounts.json'
}

function Clear-ComputerAccountsCache {
    param([string]$Backend = (Get-BackendRoot))
    $f = Get-ComputerAccountsCachePath -Backend $Backend
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

# L'ETAT DES TACHES SE RELIT, TOUJOURS.
#
# La liste des comptes est chere a etablir (profils, SID, registre) et change rarement :
# elle se met en cache 24 h. L'etat de leur tache de demarrage, lui, est bon marche a lire
# et peut changer a tout moment -- et s'il ment, il ment sur la seule chose qui compte.
# La carte a affiche « Vigie activee » pendant des heures pour un compte dont la tache
# avait disparu (28/08). Ces trois champs-la ne sont donc jamais servis depuis le cache.
function Update-AccountTasks {
    param([object[]]$Comptes)
    if (-not $Comptes -or -not $Comptes.Count) { return @($Comptes) }
    $taches = @()
    try {
        $taches = @(Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { $_.TaskName -eq 'Vigie' -or $_.TaskName -like ($script:VigieTaskPrefix + '*') })
    } catch {
        # Sans elevation, Windows masque une partie des taches : on ne sait pas, et on ne
        # PRETEND pas savoir. Les valeurs du cache sont conservees telles quelles.
        return @($Comptes)
    }
    foreach ($c in $Comptes) {
        $nom = "$($c.name)"
        $tache = @($taches | Where-Object {
            $_.TaskName -eq (Get-VigieAccountTaskName -Name $nom) -or
            ($_.TaskName -eq 'Vigie' -and (Test-TaskUserIs -UserId "$($_.Principal.UserId)" -Name $nom))
        })[0]
        # UN CACHE PEUT VENIR D'UNE VERSION PLUS ANCIENNE, et ses objets n'ont alors pas
        # les proprietes qu'on veut ecrire. Assigner une propriete absente LEVE, et la
        # valeur d'origine -- perimee -- restait affichee (constate le 28/08 : « 1 tache
        # hors service » pour une tache saine). On les cree si elles manquent.
        Set-ObjectProperty -Object $c -Name 'enabled' -Value ([bool]$tache)
        Set-ObjectProperty -Object $c -Name 'task' -Value $(if ($tache) { "$($tache.TaskName)" } else { $null })
        # DEUX CHAMPS, deux natures : « taskAilment » est ce qui empeche la tache de
        # fonctionner ; « taskPending » est ce qui ne se saura qu'a son prochain
        # demarrage. Les confondre faisait annoncer « hors service » une tache saine.
        $mal = if ($tache) { Get-VigieTaskStructureAilment -Task $tache } else { $null }
        Set-ObjectProperty -Object $c -Name 'taskAilment' -Value $mal
        Set-ObjectProperty -Object $c -Name 'taskPending' `
            -Value $(if ($tache -and -not $mal) { Get-VigieTaskHistoryAilment -Task $tache } else { $null })
    }
    return @($Comptes)
}

<#
    CE QUI DEPEND DE QUI DEMANDE.

    « VOUS » et « ce compte n'est pas un compte technique » ne sont pas des faits sur le
    poste : ce sont des faits sur la RELATION entre le poste et la personne qui regarde.
    Ils se posent donc au moment de repondre, jamais dans le releve mis en cache -- sinon
    le premier a demander fixe la reponse de tous les autres.
#>
<#
    LES QUATRE CERCLES DE COMPTES -- ET CHACUN A SON NOM.

    Chaque appelant refiltrait a sa facon (« Where -not technical » recopie a sept
    endroits), et le seul qui ne l'a pas fait a depose un ordre de relance dans le dossier
    du compte de SERVICE : « Relance demandee aux autres comptes : Famille, fhaza,
    VigieService ». Personne ne devait jamais le lire.

      1. TOUS les comptes de l'ORDINATEUR  Get-ComputerAccounts  -- VigieService en est
      2. les comptes de PERSONNE           Get-UserAccounts      -- il n'en est pas
      3. ceux qui ont Vigie ACTIVEE        Get-EnabledAccounts   -- ils ont une app cliente
      4. ceux qui TOURNENT en ce moment    (tache + app cliente vivante)

    Le cercle 4 n'a pas de fonction : personne n'en a besoin. Une relance s'adresse au
    cercle 3 -- une app cliente eteinte demarrera de toute facon avec le nouveau code, et
    verifier son battement de coeur ajouterait un acces disque pour rien.
#>
# UN compte, par son nom. Recopie a trois endroits sous la forme « Get-ComputerAccounts |
# Where-Object { $_.name -eq X } », avec a chaque fois le meme piege : sans @(...) autour,
# un resultat unique n'est pas un tableau et l'index [0] rend un caractere.
function Get-AccountByName {
    param([Parameter(Mandatory)][string]$Name, [string]$Backend = (Get-BackendRoot))
    @(Get-ComputerAccounts -Backend $Backend | Where-Object { "$($_.name)" -eq $Name })[0]
}

function Get-UserAccounts {
    param([switch]$Force, [string]$Backend = (Get-BackendRoot))
    @(Get-ComputerAccounts -Force:$Force -Backend $Backend | Where-Object { -not $_.technical })
}

function Get-EnabledAccounts {
    param([string]$Backend = (Get-BackendRoot))
    @(Get-UserAccounts -Backend $Backend | Where-Object { $_.enabled })
}

function Add-AccountsPerspective {
    param($Comptes)
    # Sans session, PERSONNE n'est « vous » : c'est plus vrai, et c'est plus sur que de
    # designer le compte du service.
    $requester = Get-RequesterAccount
    foreach ($c in @($Comptes)) {
        $isMe = [bool]$requester -and ("$($c.name)" -eq "$requester")
        $c | Add-Member -NotePropertyName current -NotePropertyValue $isMe -Force
        # Celui qui utilise Vigie en ce moment n'est jamais un compte d'outil.
        if ($isMe) { $c | Add-Member -NotePropertyName technical -NotePropertyValue $false -Force }
    }
    return $Comptes
}

<#
    LES COMPTES DE CET ORDINATEUR -- pas des « comptes Vigie ».

    La fonction s'appelait Get-VigieAccounts : elle ne rend rien qui appartienne a Vigie,
    elle rend les comptes que WINDOWS declare, avec pour chacun ce que Vigie en sait.
    Le nom faisait croire a une liste de comptes autorises, ce qui est le cercle 3.
#>
function Get-ComputerAccounts {
    param(
        [switch]$Force,                       # bouton « Actualiser la liste »
        [string]$Backend = (Get-BackendRoot)
    )
    $cache = Get-ComputerAccountsCachePath -Backend $Backend
    if (-not $Force -and (Test-Path -LiteralPath $cache)) {
        try {
            $j = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalHours
            if ($age -lt $script:ComptesTTLHeures -and $j.users) {
                return (Add-AccountsPerspective (Update-AccountTasks -Comptes @($j.users)))
            }
        } catch { }
    }
    $liste = @(Get-ComputerAccountsFresh -Backend $Backend)
    try {
        $tmp = "$cache.tmp"
        (@{ at = (Get-Date).ToUniversalTime().ToString('s'); users = $liste } | ConvertTo-Json -Depth 6) |
            Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $cache -Force
    } catch { }
    # LA PERSPECTIVE APRES LE CACHE, jamais avant : ce qu'on ecrit sur le disque doit
    # rester vrai pour n'importe qui.
    return (Add-AccountsPerspective $liste)
}

# Le releve REEL, sans cache.
function Get-ComputerAccountsFresh {
    param([string]$Backend = (Get-BackendRoot))
    # PROFILS REELLEMENT UTILISES : c'est LE discriminant entre un compte de personne et un
    # compte d'outil. Win32_UserProfile.LastUseTime dit quand le profil a servi pour de bon
    # (ouverture de session). Le LastLogon du COMPTE, lui, ment : un compte de bac a sable
    # affichait « connecte aujourd'hui » sans avoir jamais ouvert de session -- signale par
    # l'utilisateur, verifie le 26/08 (LastUseTime vide, profil jamais charge).
    $profils = @{}
    try {
        foreach ($up in (Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special })) {
            $cle = "$($up.SID)"
            if ($cle) { $profils[$cle] = $up }
        }
    } catch { }

    # QUELS COMPTES SONT DES COMPTES DE PERSONNE ? Windows le dit lui-meme :
    # Winlogon\SpecialAccounts\UserList liste les comptes MASQUES de l'ecran de connexion
    # (valeur 0). C'est ainsi que les outils declarent leurs comptes de service.
    # Tous les criteres essayes avant etaient faux : le profil (les bacs a sable en ont
    # un), sa date d'usage (invisible hors elevation, d'ou deux verdicts contradictoires
    # entre l'agent et le serveur), son contenu (Desktop present quand meme),
    # l'appartenance au groupe Utilisateurs (ils en sont membres).
    $masquesConnexion = @{}
    try {
        $cleMasques = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if (Test-Path $cleMasques) {
            foreach ($pr in (Get-ItemProperty $cleMasques).PSObject.Properties) {
                if ($pr.Name -like 'PS*') { continue }
                if ([int]$pr.Value -eq 0) { $masquesConnexion[$pr.Name.ToLower()] = $true }
            }
        }
    } catch { }

    $taches = @()
    try { $taches = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq 'Vigie' -or $_.TaskName -like ($script:VigieTaskPrefix + '*') }) } catch { }
    $comptes = @()
    try { $comptes = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled }) } catch { }
    @(foreach ($c in $comptes) {
        $nom = "$($c.Name)"
        $tache = @($taches | Where-Object {
            $_.TaskName -eq (Get-VigieAccountTaskName -Name $nom) -or
            ($_.TaskName -eq 'Vigie' -and (Test-TaskUserIs -UserId "$($_.Principal.UserId)" -Name $nom))
        })[0]
        # VRAI compte ou compte TECHNIQUE ? On ne juge pas sur le NOM (une liste noire
        # serait fausse le jour ou quelqu'un appelle son compte « Sandbox ») mais sur un
        # FAIT : ce profil a-t-il deja servi a ouvrir une session ? Un compte d'outil est
        # cree, parfois authentifie, mais son profil n'est jamais charge.
        # Ce critere ne demande AUCUNE elevation, contrairement a l'inspection du contenu
        # du profil qui avait ete essayee d'abord -- et qui laissait passer les bacs a sable.
        $profil  = Join-Path (Join-Path $env:SystemDrive 'Users') $nom
        $aProfil = Test-Path -LiteralPath $profil
        $up = $profils["$($c.SID)"]
        $dejaServi = [bool]($up -and ($up.LastUseTime -or $up.Loaded))
        # ATTENTION : LastUseTime n'est visible QUE d'un processus eleve. Depuis une
        # session ordinaire, tous les profils paraissent « jamais utilises » -- le critere
        # seul se contredisait donc d'un contexte a l'autre (constate le 26/08 : un compte
        # d'outil ecarte cote agent, affiche cote serveur).
        # Quand on est eleve, on tranche sur le CONTENU du profil : un compte de personne
        # a un Bureau ou des Documents ; un compte d'outil n'en a pas.
        # CE RELEVE NE SAIT PAS QUI REGARDE, et c'est voulu : il est MIS EN CACHE dans un
        # fichier commun. Y ecrire quoi que ce soit de relatif au demandeur, c'est servir
        # a Famille la reponse calculee pour fhaza. Tout ce qui depend de la personne est
        # pose apres coup, par Add-AccountsPerspective.
        $technique = [bool]$masquesConnexion[$nom.ToLower()]

        [pscustomobject][ordered]@{
            name        = $nom
            fullName    = "$($c.FullName)"
            description = "$($c.Description)"
            admin       = (Test-LocalAccountIsAdmin -Name $nom)
            hasProfile  = $aProfil
            technical   = $technique
            # Date de derniere UTILISATION du profil (plus fiable que LastLogon).
            lastUse     = $(if ($up -and $up.LastUseTime) { ([datetime]$up.LastUseTime).ToString('s') } else { $null })
            enabled     = [bool]$tache
            task        = if ($tache) { "$($tache.TaskName)" } else { $null }
            # La tache existe-t-elle VRAIMENT en etat de marche ? Une tache qui pointe
            # vers un interpreteur disparu se lance et meurt aussitot, sans un mot :
            # Vigie ne demarre pas et l'ecran des comptes affiche « activee ». C'est
            # exactement ce qui est arrive le 26/08 (D83).
            taskAilment = if ($tache) { Get-VigieTaskStructureAilment -Task $tache } else { $null }
            # Ce qui attend son prochain demarrage : signale, mais pas « hors service ».
            taskPending = if ($tache -and -not (Get-VigieTaskStructureAilment -Task $tache)) { Get-VigieTaskHistoryAilment -Task $tache } else { $null }
            # Le compte qui execute le serveur en ce moment : l'interface doit pouvoir dire
            # « c'est vous » et empecher de se retirer soi-meme par megarde.
            current     = $false          # pose par Add-AccountsPerspective, jamais mis en cache
            lastLogon   = if ($c.LastLogon) { $c.LastLogon.ToString('s') } else { $null }
        }
    })
}

# Pose (ou retire) la tache de demarrage d'UN compte. Exige l'elevation : creer une tache
# pour autrui est une operation d'administration -- Windows l'exige, Vigie aussi.
function Set-VigieAccountEnabled {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Enabled,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-IsElevated)) { throw "Modifier les comptes autorises demande un compte administrateur." }
    $compte = @(Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })[0]
    if (-not $compte) { throw "Compte inconnu sur cette machine : $Name" }
    # Un AUTRE compte que le sien exige que l'application lui soit lisible.
    if ($Enabled -and -not $compte.current -and -not (Get-SharedInstallPath)) {
        throw "Aucune installation lisible par les autres comptes : deployez d'abord Vigie pour tous, sinon la tache de $Name echouerait a chaque ouverture de session."
    }

    if (-not $Enabled) {
        # On retire la tache DEDIEE. La tache historique « Vigie » n'est pas supprimee
        # ici : elle est le demarrage installe par install-autostart, et son retrait a son
        # propre script (uninstall-autostart) -- supprimer sans le dire serait pire.
        $t = Get-VigieAccountTaskName -Name $Name
        try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop } catch { }
        Clear-ComputerAccountsCache -Backend $Backend
        return (Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })
    }

    # POUR SOI : l'interpreteur courant convient, quel que soit son emplacement.
    # POUR UN AUTRE COMPTE : il lui faut un pwsh installe pour la MACHINE, sinon la tache
    # pointerait dans notre profil et ne lancerait rien chez lui (constate avec Famille).
    $pwsh = if ($compte.current) { (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
            else                 { Get-SharedPwshPath }
    if (-not $pwsh -and $compte.current) { throw "pwsh introuvable : impossible de creer la tache." }
    if (-not $pwsh) {
        throw ("PowerShell 7 n'est installe que pour votre compte (paquet du Store). La tache de " +
               $Name + " pointerait vers un chemin de VOTRE profil, illisible pour lui : Vigie ne " +
               "demarrerait pas, sans message. Installez PowerShell 7 pour toute la machine " +
               "(winget install --id Microsoft.PowerShell --scope machine), puis reactivez ce compte.")
    }
    # Le compte doit pouvoir LIRE ce que sa tache lance.
    # LE CHEMIN SUIT L'ENVIRONNEMENT DECLARE. Poser systematiquement l'installation
    # partagee ferait demarrer un autre compte sur la production alors que la machine se
    # declare en developpement -- et Vigie signalerait ensuite l'ecart qu'elle vient de
    # creer elle-meme.
    # LA LISIBILITE PASSE AVANT LA PREFERENCE. L'environnement declare dit ou l'on
    # VOUDRAIT tourner ; ce que le compte peut LIRE dit ou l'on PEUT tourner. Pointer la
    # tache de « Famille » vers le depot -- illisible pour elle a partir de Git\ -- a
    # produit un code 64, « impossible d'ouvrir le fichier », sans le moindre journal.
    $targetSid = $null
    try { $targetSid = (Get-LocalUser -Name $Name -ErrorAction Stop).SID.Value } catch { }
    if (-not $targetSid) { throw ("Compte introuvable sur cette machine : " + $Name) }

    # L'INSTALLATION PARTAGEE D'ABORD, TOUJOURS. L'environnement declare dit d'ou vient ce
    # qu'on deploie, pas ou ca tourne : une tache qui lance un depot personnel est
    # illisible pour les autres comptes et disparait si le dossier bouge. Le depot ne sert
    # de repli que s'il n'existe aucune installation partagee -- et seulement pour le
    # compte qui la possede.
    $candidates = @((Get-SharedInstallPath), (Get-RepoRoot))
    $appRoot = $null
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $probe = Join-Path (Join-Path $candidate 'apps') (Join-Path 'tray' 'tray.ps1')
        if (-not (Test-Path -LiteralPath $probe)) { continue }
        if (Test-PathReadableByAccount -Path $probe -Sid $targetSid -IsAdmin:([bool]$compte.admin)) {
            $appRoot = $candidate
            break
        }
    }
    if (-not $appRoot) {
        throw ("Aucune copie de Vigie n'est lisible par " + $Name +
               " : deployez-la pour tous les comptes avant de l'activer.")
    }
    $tray = Join-Path $appRoot 'apps/tray/tray.ps1'
    if (-not (Test-Path -LiteralPath $tray)) { throw "Application introuvable : $tray" }

    $arg     = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $tray + '"'
    $action  = New-ScheduledTaskAction -Execute $pwsh -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    # 45 s : pwsh vient du Store (MSIX) et n'est pas toujours pret a l'instant du logon.
    $trigger.Delay = 'PT45S'
    $niveau  = if ($compte.admin) { 'Highest' } else { 'Limited' }
    $princ   = New-ScheduledTaskPrincipal -UserId ("$env:COMPUTERNAME\$Name") -LogonType Interactive -RunLevel $niveau
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                  -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $nomTache = Get-VigieAccountTaskName -Name $Name
    # On CONSTATE (D43) : une creation qui ne leve pas n'est pas une creation qui a eu
    # lieu. Le journal garde la trace des deux, et l'appelant recoit une vraie erreur.
    try {
        Register-ScheduledTask -TaskName $nomTache -Action $action -Trigger $trigger `
            -Principal $princ -Settings $set -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Log -Backend $Backend -Name 'comptes' -Level 'ERROR' -Message (Get-Label 'common.creation-de-la-tache' $nomTache $_.Exception.Message)
        throw ("Windows a refuse de creer la tache pour " + $Name + " : " + $_.Exception.Message)
    }
    $verif = $null
    try { $verif = Get-ScheduledTask -TaskName $nomTache -ErrorAction Stop } catch { }
    if (-not $verif) {
        Write-Log -Backend $Backend -Name 'comptes' -Level 'ERROR' -Message (Get-Label 'common.tache-absente-juste-apres' $nomTache)
        throw ("La tache de " + $Name + " n'existe pas apres creation : Windows l'a refusee sans le dire.")
    }
    Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-creee' $nomTache $princ.UserId $niveau)
    Clear-ComputerAccountsCache -Backend $Backend
    return (Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })
}


# --- OU S'EXECUTE UNE ACTION : sur le serveur, ou sur le bureau d'un compte ? ----------
#
# LE PROBLEME. Un serveur n'a pas d'ecran. Aujourd'hui il en a un par accident -- c'est le
# tray de fhaza qui le lance, donc dans une session de bureau. Le jour ou il devient la
# tache de machine, il tournera en session 0 : « Start-Process explorer.exe » y reussit
# sans que PERSONNE ne voie jamais la fenetre. L'action se declarerait faite, et rien ne
# se passerait a l'ecran.
#
# Et meme aujourd'hui, le probleme existe deja : si Famille demande d'ouvrir un dossier,
# c'est sur le bureau de FHAZA qu'il s'ouvre, parce que c'est la que tourne le serveur.
#
# LA REGLE. Une action declare ou elle doit s'executer, en tete de son fichier :
#     # @execution: session    -- elle s'execute dans la session du DEMANDEUR
#     # @execution: serveur    -- elle n'a besoin de personne (defaut)
# Le silence vaut « serveur » : c'est le cas courant, et une action qui n'ouvre rien n'a
# aucune raison de faire un detour.
#
# « ADMIN » ET « SESSION » VONT TRES BIEN ENSEMBLE, contrairement a ce que j'avais cru.
# Test-ActionAllowed refuse une action admin a un compte standard, et a une fenetre qui
# ne dit pas qui elle est, AVANT toute execution. Une action admin n'est donc demandee que
# par un administrateur -- et la tache de tray d'un administrateur tourne en RunLevel
# Highest, donc elevee. Elle peut faire les deux.
#
# Le jour ou l'on voudra qu'un compte standard VOIE ces boutons et declenche une demande
# d'elevation, ce sera un autre sujet : il faudra qu'un administrateur puisse l'autoriser
# depuis l'interface, pour toutes les instances de Vigie. Hors perimetre aujourd'hui.
function Get-ActionExecutor {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($ligne in (Get-Content -LiteralPath $f -TotalCount 40)) {
                if ($ligne -match '^\s*#\s*@execution\s*:\s*(session|serveur)') { return $Matches[1] }
            }
        }
    } catch { }
    return 'serveur'
}

# Le dossier d'ordres d'un compte : c'est la que son tray regarde, une fois par seconde.
function Get-AccountRunDir {
    param([Parameter(Mandatory)][string]$Account)
    $varRoot = Get-AccountVarRoot -Account $Account
    if (-not $varRoot) { return $null }
    return (Join-Path $varRoot 'run')
}

<#
    FAIRE EXECUTER UNE ACTION PAR LE TRAY D'UN COMPTE.

    On depose un ordre dans son dossier, et on attend son compte rendu. Le tray tourne
    dans SA session, avec SES droits et SON bureau : la fenetre s'ouvre la ou le
    demandeur la voit, et l'action n'obtient rien que Windows lui refuserait.

    LE CANAL D'ORDRES EST UNE SURFACE D'ATTAQUE (conception, C8). Il vit dans le profil du
    compte, ou lui seul et les administrateurs ecrivent. Un dossier ou tout le monde
    pourrait deposer serait un moyen de faire executer n'importe quoi par n'importe qui.

    RIEN N'EST GARANTI DE L'AUTRE COTE : le tray peut etre arrete, la session fermee, le
    compte deconnecte. On rend alors $null, et l'appelant decide -- ici, il execute
    lui-meme, comme avant. Une action qui ne s'ouvre pas sur le bon bureau vaut mieux
    qu'une action qui ne s'ouvre pas du tout.
#>
function Invoke-DesktopAction {
    param(
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][string]$Type,
        [hashtable]$Params,
        [string]$Module,
        [int]$TimeoutSec = 12,
        [string]$Backend = (Get-BackendRoot)
    )
    $runDir = Get-AccountRunDir -Account $Account
    if (-not $runDir) { return $null }
    if (-not (Test-Path -LiteralPath $runDir)) {
        try { New-Item -ItemType Directory -Path $runDir -Force | Out-Null } catch { return $null }
    }
    $id    = New-RandomId
    $order = Join-Path $runDir ('desktop-' + $id + '.json')
    $done  = Join-Path $runDir ('desktop-' + $id + '.done.json')
    $charge = @{ type = $Type; module = $Module; params = $Params; at = (Get-EpochSeconds) }
    try { ($charge | ConvertTo-Json -Compress -Depth 6) | Out-File -FilePath $order -Encoding UTF8 }
    catch { return $null }

    $deadline = (Get-EpochSeconds) + $TimeoutSec
    while ((Get-EpochSeconds) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (Test-Path -LiteralPath $done) {
            $data = $null
            try { $data = Get-Content -LiteralPath $done -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
            Remove-Item -LiteralPath $done -Force -ErrorAction SilentlyContinue
            return $data
        }
    }
    # PAS DE REPONSE : on retire notre ordre. Sans cela, un tray qui revient dans une
    # heure ouvrirait une fenetre que plus personne n'attend.
    Remove-Item -LiteralPath $order -Force -ErrorAction SilentlyContinue
    return $null
}

# --- QUI a le droit de lancer une action (D65) ---------------------------------
# Regle de BASE, choisie par l'utilisateur : Vigie ne permet rien de plus que ce que
# Windows permet deja a ce compte. Un compte standard ne doit pas obtenir par Vigie ce que
# Windows lui refuse -- l'application deviendrait un moyen d'elevation de privileges.
#
# Mais c'est une valeur PAR DEFAUT, pas un dogme : on doit pouvoir changer d'avis sur UNE
# action precise. D'ou deux niveaux :
#   1. la DECLARATION, en tete du fichier d'action : `# @droits: admin` ou `# @droits: tous` ;
#      elle vit a cote du code qu'elle protege, et se lit sans executer le script ;
#   2. la POLITIQUE de la machine, config/actions.policy.json, qui peut ouvrir ou fermer
#      une action nommement -- c'est le point ou l'utilisateur change d'avis.
# En l'absence de declaration : `admin`. Le silence n'ouvre rien.
function Get-ActionRequirement {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    # 1. Politique de la machine (elle tranche).
    try {
        $pol = Get-MachineConfigPath -File 'actions.policy.json'
        if (Test-Path -LiteralPath $pol) {
            $j = Get-Content -LiteralPath $pol -Raw -Encoding UTF8 | ConvertFrom-Json
            $v = $j.PSObject.Properties | Where-Object { $_.Name -eq $Type } | Select-Object -First 1
            if ($v -and "$($v.Value)" -match '^(admin|tous)$') { return "$($v.Value)" }
        }
    } catch { }
    # 2. Declaration de l'action.
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($ligne in (Get-Content -LiteralPath $f -TotalCount 40)) {
                # La valeur peut etre suivie d'un commentaire : on s'arrete au mot, pas a la ligne.
                if ($ligne -match '^\s*#\s*@droits\s*:\s*(admin|tous)') { return $Matches[1] }
            }
        }
    } catch { }
    return 'admin'
}

# L'action est-elle lancable ICI et MAINTENANT ? Rend un objet parlant : le front doit
# pouvoir DIRE pourquoi un bouton est inerte (une action ne disparait jamais -- D59).
# Ce que l'action AFFICHE quand un champ la cite : libelle, genre, severite. Declares en
# tete du fichier d'action (`# @libelle: Texte | kind | severity`), a cote des droits.
# Sans declaration : « Resoudre », en immediate/fix -- un bouton parlant vaut mieux que
# pas de bouton (D66), mais un libelle precis vaut mieux qu'un mot generique.
function Get-ActionPresentation {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    $label = 'Résoudre'; $kind = 'immediate'; $sev = 'fix'
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($ligne in (Get-Content -LiteralPath $f -TotalCount 40)) {
                if ($ligne -match '^\s*#\s*@libelle\s*:\s*(.+)$') {
                    $bouts = @("$($Matches[1])" -split '\|' | ForEach-Object { $_.Trim() })
                    # Le commentaire qui suit « -- » ne fait pas partie de la declaration.
                    if ($bouts.Count -ge 1 -and $bouts[0]) { $label = ($bouts[0] -replace '\s*--.*$', '').Trim() }
                    if ($bouts.Count -ge 2 -and $bouts[1]) { $kind  = ($bouts[1] -replace '\s*--.*$', '').Trim() }
                    if ($bouts.Count -ge 3 -and $bouts[2]) { $sev   = ($bouts[2] -replace '\s*--.*$', '').Trim() }
                    break
                }
            }
        }
    } catch { }
    [pscustomobject]@{ label = $label; kind = $kind; severity = $sev }
}

<#
    QUI DEMANDE A-T-IL LE DROIT ? -- ET NON : LE SERVEUR EST-IL ELEVE ?

    Cette fonction posait la mauvaise question. Elle repondait « oui » des que
    Test-IsElevated etait vrai -- or le serveur tourne SOUS UN COMPTE DE SERVICE
    ADMINISTRATEUR, donc toujours. Une action « @droits: admin » passait pour n'importe
    qui : un compte standard, et meme un navigateur ouvert sur l'adresse sans aucune
    identification. Pendant ce temps l'ecran des utilisateurs affichait « un compte
    standard n'obtient aucun droit en plus : Vigie lui refuse les actions administrateur ».
    Le texte promettait une garde qui n'existait pas, et le commentaire d'a cote la
    decrivait comme acquise.

    D65 tranche : par defaut Vigie ne permet rien de plus que ce que Windows permet deja a
    ce compte. Une action qui touche la machine se juge donc sur LE DEMANDEUR.

    TROIS REFUS, ET ILS NE DISENT PAS LA MEME CHOSE :
      - on ne sait pas qui demande -- fenetre ouverte sans identification ;
      - on sait, et ce compte n'est pas administrateur ;
      - le demandeur en a le droit, mais le serveur n'est pas eleve : il ne PEUT pas.

    HORS CONTEXTE WEB -- rafraichissement de fond, script lance a la main -- le demandeur
    est celui qui execute. Sans cela, tout ce qui ne vient pas d'un navigateur se verrait
    refuser ses propres actions.
#>
function Test-ActionAllowed {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot),
        [AllowNull()][AllowEmptyString()][string]$Requester
    )
    $besoin = Get-ActionRequirement -Type $Type -Backend $Backend
    if ($besoin -ne 'admin') { return [pscustomobject]@{ allowed = $true; requirement = $besoin; reason = $null } }

    if (-not $PSBoundParameters.ContainsKey('Requester')) {
        $Requester = $(if ($WebEvent) { Get-RequesterAccount } else { Get-ProcessAccount })
    }

    if (-not $Requester) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système, et Vigie ne sait pas qui la demande. Ouvrez le panneau depuis l'icône de Vigie."
        }
    }
    $isAdmin = $false
    try {
        $who = Get-AccountByName -Name $Requester -Backend $Backend
        if ($who) { $isAdmin = [bool]$who.admin }
        else      { $isAdmin = Test-LocalAccountIsAdmin -Name $Requester }
    } catch { $isAdmin = Test-LocalAccountIsAdmin -Name $Requester }

    if (-not $isAdmin) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système : elle demande un compte administrateur. Windows la refuserait de la même façon."
        }
    }
    if (-not (Test-IsElevated)) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système, et l'app serveur ne tourne pas avec les droits nécessaires."
        }
    }
    [pscustomobject]@{ allowed = $true; requirement = 'admin'; reason = $null }
}

# --- OU vivent les reglages : MACHINE puis UTILISATEUR (D65) -------------------
# L'ordinateur a plusieurs comptes Windows et chacun doit avoir SES reglages.
# Trois couches, de la plus generale a la plus personnelle :
#   1. les defauts VERSIONNES        (probes/<module>/module.psd1, Config)
#   2. la couche MACHINE             (config/*.local.* dans l'installation) -- ce qui
#      etait deja regle avant le multi-utilisateur reste donc en place pour tout le monde
#   3. la couche UTILISATEUR         (%LOCALAPPDATA%\Sowapps\Vigie) -- ce compte-ci
# On LIT les trois (la plus personnelle gagne) ; on ECRIT toujours dans la couche
# utilisateur : un compte ne modifie jamais les reglages d'un autre.
#
# Un processus eleve du meme compte partage son LOCALAPPDATA : le serveur eleve et le
# tray ecrivent donc bien au meme endroit que l'utilisateur connecte.
<#
    LES REGLAGES D'UN COMPTE VIVENT CHEZ LUI, ET ON VA LES Y CHERCHER.

    Jusqu'ici cette fonction rendait toujours le dossier du compte qui EXECUTE -- donc
    celui du serveur. Consequence constatee le 28/08 : Famille et fhaza voyaient les
    memes modules, la meme liste de paquets ignores, les memes notifications, parce que
    c'etait la configuration de fhaza dans les deux cas. Masquer une carte chez l'un la
    masquait chez l'autre.

    Avec -Account, on lit le dossier de CE compte. Sans, celui du processus : c'est le
    bon comportement pour un script local ou une tache, qui n'a pas de demandeur.

    On ne CREE rien dans le profil d'un autre : poser un dossier chez quelqu'un qui n'a
    jamais ouvert Vigie n'a pas de sens, et le serveur n'a aucune raison d'ecrire chez
    lui avant qu'il ne le demande.
#>
function Get-AccountConfigDir {
    param([Parameter(Mandatory)][string]$Account)
    $profil = Join-Path $env:SystemDrive (Join-Path 'Users' $Account)
    if (-not (Test-PathSafe $profil)) { return $null }
    return (Join-Path (Join-Path (Join-Path (Join-Path $profil 'AppData') 'Local') 'Sowapps') 'Vigie')
}

function Get-UserConfigDir {
    # Vigie est une application de SOWAPPS : ses donnees vivent sous le nom de l'editeur,
    # comme celles de n'importe quel logiciel installe (Editeur\Produit).
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    $d = Join-Path (Join-Path $base 'Sowapps') 'Vigie'
    if (-not (Test-Path -LiteralPath $d)) {
        try { New-Item -ItemType Directory -Path $d -Force -WhatIf:$false | Out-Null } catch { }
        # Reprise de l'emplacement precedent (sans editeur) : personne ne doit perdre ses
        # reglages parce que le rangement a change.
        $ancien = Join-Path $base 'Vigie'
        if ((Test-Path -LiteralPath $ancien) -and (Test-Path -LiteralPath $d)) {
            try {
                foreach ($x in (Get-ChildItem -LiteralPath $ancien -Force -ErrorAction SilentlyContinue)) {
                    $cible = Join-Path $d $x.Name
                    if (-not (Test-Path -LiteralPath $cible)) { Move-Item -LiteralPath $x.FullName -Destination $cible -Force }
                }
            } catch { }
        }
    }
    $d
}
function Get-UserConfigPath {
    param(
        [Parameter(Mandatory)][string]$File,
        # Le compte dont on veut les reglages. Par defaut : celui qui execute.
        [string]$Account
    )
    if ($Account) {
        $d = Get-AccountConfigDir -Account $Account
        if ($d) { return (Join-Path $d $File) }
    }
    return (Join-Path (Get-UserConfigDir) $File)
}
function Get-MachineConfigPath { param([Parameter(Mandatory)][string]$File) Join-Path (Get-RepoRoot) (Join-Path 'config' $File) }

# --- Gestion des modules (D48) ------------------------------------------------
# Un MODULE (unite) = un DOSSIER de sondes, declare par un module.psd1 versionne.
# L'activation est un choix de l'utilisateur : config/modules.local.psd1, jamais
# versionne. Un module coupe retire ses sondes du calcul, mais reste EXPOSE dans la
# cle units[] du contrat -- sinon l'interface ne pourrait plus proposer de le rallumer.
# Couche utilisateur si elle existe, couche machine sinon (D65). On n'UNIT pas les deux :
# rallumer chez soi un module coupe pour la machine doit rester possible.
# LE DEMANDEUR, PAS L'EXECUTANT. Get-ActionRequester rend le compte de la session quand
# la demande vient d'une page identifiee, et celui du processus sinon : c'est exactement
# la regle voulue pour des reglages personnels.
function Get-UnitsLocalPath { Get-UserConfigPath -File 'modules.local.psd1' -Account (Get-ActionRequester) }

# CE QUE L'UTILISATEUR A EXPLICITEMENT ALLUME. Distinct de « pas eteint » : un module
# peut naitre ETEINT (module.psd1 : DefautActif = $false), et il faut alors savoir si
# l'utilisateur l'a allume pour de bon ou s'il n'a simplement jamais eu d'avis.
function Get-EnabledUnits {
    foreach ($p in @((Get-UnitsLocalPath), (Get-MachineConfigPath -File 'modules.local.psd1'))) {
        if (Test-Path -LiteralPath $p) {
            try { return @((Import-PowerShellDataFile -Path $p).Enabled | ForEach-Object { "$_" }) } catch { return @() }
        }
    }
    return @()
}

# Le module est-il actif, tout compte fait ? Trois cas, dans cet ordre :
#   1. l'utilisateur l'a eteint          -> non
#   2. l'utilisateur l'a allume          -> oui
#   3. personne n'a rien dit             -> ce que declare le module (actif, sauf avis
#                                           contraire ecrit dans module.psd1)
function Test-UnitEnabled {
    param(
        [Parameter(Mandatory)][string]$UnitId,
        [string]$Backend = (Get-BackendRoot)
    )
    if ((Get-DisabledUnits) -contains $UnitId) { return $false }
    if ((Get-EnabledUnits)  -contains $UnitId) { return $true }
    $decl = @{}
    $f = Join-Path (Join-Path (Join-Path $Backend 'probes') $UnitId) 'module.psd1'
    if (Test-Path -LiteralPath $f) {
        try { $decl = Import-PowerShellDataFile -Path $f } catch { }
    }
    if ($decl.ContainsKey('DefautActif')) { return [bool]$decl.DefautActif }
    return $true
}

# La liste des modules a EXCLURE du calcul, defauts compris. C'est elle que consulte
# Get-State : un module eteint ne coute rien, ni calcul ni carte.
function Get-InactiveUnits {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    @(foreach ($d in (Get-ChildItem -Path $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if (-not (Test-UnitEnabled -UnitId $d.Name -Backend $Backend)) { $d.Name }
    })
}

function Get-DisabledUnits {
    foreach ($p in @((Get-UnitsLocalPath), (Get-MachineConfigPath -File 'modules.local.psd1'))) {
        if (Test-Path -LiteralPath $p) {
            try { return @((Import-PowerShellDataFile -Path $p).Disabled | ForEach-Object { "$_" }) } catch { return @() }
        }
    }
    return @()
}

function Set-UnitEnabled {
    param(
        [Parameter(Mandatory)][string]$UnitId,
        [Parameter(Mandatory)][bool]$Enabled
    )
    $off = [System.Collections.Generic.List[string]]::new()
    foreach ($u in (Get-DisabledUnits)) { if ($u -ne $UnitId) { $off.Add($u) } }
    if (-not $Enabled) { $off.Add($UnitId) }
    # ALLUMER se garde aussi : un module qui naît éteint (debogage) doit rester allume
    # apres un redemarrage. Sans cette seconde liste, il se serait ré-éteint tout seul.
    $on = [System.Collections.Generic.List[string]]::new()
    foreach ($u in (Get-EnabledUnits)) { if ($u -ne $UnitId) { $on.Add($u) } }
    if ($Enabled) { $on.Add($UnitId) }
    $listeOn = ($on | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $liste = ($off | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $texte = "@{`n    # Choix de l'utilisateur sur les modules (D48). Fichier ecrit par l'application`n" +
             "    # (vue de gestion des modules), jamais versionne.`n" +
             "    #   Disabled : eteints a la main.`n" +
             "    #   Enabled  : allumes a la main -- utile pour ceux qui naissent eteints (debogage).`n" +
             "    Disabled = @($liste)`n    Enabled = @($listeOn)`n}`n"
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
            enabled     = (Test-UnitEnabled -UnitId $dir.Name -Backend $Backend)
            # Un module de DEBOGAGE ne s'impose pas : il naît éteint et l'écran de
            # gestion doit pouvoir le dire au lieu de laisser croire a une panne.
            offByDefault = ($decl.ContainsKey('DefautActif') -and -not [bool]$decl.DefautActif)
            probes      = @($probes | ForEach-Object { $_.Name -replace '\.probe\.ps1$', '' })
        }
    })
}

# --- Parametres de modules (D57) ----------------------------------------------
# Modele valide par l'utilisateur : la CONFIG (module.psd1, versionnee) porte les valeurs
# par DEFAUT ; un PARAMETRE est une surcharge de l'utilisateur, posee via le menu
# Parametres et stockee dans config/parameters.local.json (jamais versionne).
# Chaque parametre a pour defaut une valeur de config -- c'est la regle, pas l'exception.
# On ECRIT dans la couche utilisateur (D65).
function Get-ParametersLocalPath { Get-UserConfigPath -File 'parameters.local.json' -Account (Get-ActionRequester) }

# Lecture d'UNE couche.
function Get-ParameterOverridesFrom {
    param([Parameter(Mandatory)][string]$Path)
    $out = @{}
    if (Test-Path -LiteralPath $Path) {
        try {
            $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($u in $j.PSObject.Properties) {
                $out[$u.Name] = @{}
                foreach ($k in $u.Value.PSObject.Properties) { $out[$u.Name][$k.Name] = $k.Value }
            }
        } catch { }
    }
    return $out
}

# Machine PUIS utilisateur : le reglage personnel gagne, cle par cle (et seulement les
# cles reglees -- le reste continue de suivre la machine, puis le defaut du module).
function Get-ParameterOverrides {
    param([switch]$UtilisateurSeul)
    $out = @{}
    $couches = if ($UtilisateurSeul) { @((Get-ParametersLocalPath)) }
               else { @((Get-MachineConfigPath -File 'parameters.local.json'), (Get-ParametersLocalPath)) }
    foreach ($c in $couches) {
        $couche = Get-ParameterOverridesFrom -Path $c
        foreach ($u in $couche.Keys) {
            if (-not $out.ContainsKey($u)) { $out[$u] = @{} }
            foreach ($k in $couche[$u].Keys) { $out[$u][$k] = $couche[$u][$k] }
        }
    }
    return $out
}

# La valeur EFFECTIVE d'un reglage : surcharge utilisateur si presente, sinon la config
# du module. C'est LE point d'entree des sondes -- elles ne lisent jamais le fichier local.
function Get-ModuleSetting {
    param(
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][string]$Key,
        [string]$Backend = (Get-BackendRoot)
    )
    $sur = Get-ParameterOverrides
    if ($sur.ContainsKey($Unit) -and $sur[$Unit].ContainsKey($Key)) { return $sur[$Unit][$Key] }
    $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $Unit) 'module.psd1'
    if (Test-Path -LiteralPath $declPath) {
        try {
            $d = Import-PowerShellDataFile -Path $declPath
            if ($d.Config -and $d.Config.ContainsKey($Key)) { return $d.Config[$Key] }
        } catch { }
    }
    return $null
}

# Catalogue pour l'interface : chaque module declare (module.psd1) ses parametres
# reglables -- cle, libelle, type, aide -- et la valeur courante est calculee ici.
function Get-ModuleParameterCatalog {
    param([string]$Backend = (Get-BackendRoot))
    # `sur` = ce que CE compte a regle ; `mach` = ce qui est regle pour la machine.
    $sur  = Get-ParameterOverrides -UtilisateurSeul
    $mach = Get-ParameterOverridesFrom -Path (Get-MachineConfigPath -File 'parameters.local.json')
    @(foreach ($u in (Get-UnitCatalog -Backend $Backend)) {
        $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $u.id) 'module.psd1'
        $decl = @{}
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        if (-not $decl.Parameters) { continue }
        $params = @(foreach ($pm in @($decl.Parameters)) {
            $cle = "$($pm.Key)"
            $defaut = if ($decl.Config -and $decl.Config.ContainsKey($cle)) { $decl.Config[$cle] } else { $null }
            # Ce dont ce compte HERITE s'il n'a rien regle : le defaut du module, ou le
            # reglage de la machine s'il y en a un (D65).
            if ($mach.ContainsKey($u.id) -and $mach[$u.id].ContainsKey($cle)) { $defaut = $mach[$u.id][$cle] }
            $courant = if ($sur.ContainsKey($u.id) -and $sur[$u.id].ContainsKey($cle)) { $sur[$u.id][$cle] } else { $defaut }
            [ordered]@{
                key      = $cle
                label    = "$($pm.Label)"
                type     = if ($pm.Type) { "$($pm.Type)" } else { 'int' }
                unit     = if ($pm.Unit) { "$($pm.Unit)" } else { $null }
                help     = if ($pm.Help) { "$($pm.Help)" } else { '' }
                # Bornes de curseur : l'interface propose un reglage guide, la saisie
                # manuelle reste toujours possible (champ nombre synchronise).
                min      = if ($null -ne $pm.Min)  { [int]$pm.Min }  else { $null }
                max      = if ($null -ne $pm.Max)  { [int]$pm.Max }  else { $null }
                step     = if ($null -ne $pm.Step) { [int]$pm.Step } else { $null }
                default  = $defaut
                value    = $courant
                overridden = ($sur.ContainsKey($u.id) -and $sur[$u.id].ContainsKey($cle))
            }
        })
        [pscustomobject][ordered]@{ unit = $u.id; label = $u.label; params = $params }
    })
}

# Pose (ou retire) des surcharges. $null pour une cle = retour a la valeur de config.
# Seules les cles DECLAREES par le module sont acceptees : un parametre non declare
# n'a pas d'interface, il n'a donc pas non plus de surcharge.
function Set-ModuleParameters {
    param(
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][hashtable]$Values,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = @(Get-ModuleParameterCatalog -Backend $Backend | Where-Object { $_.unit -eq $Unit })
    if (-not $cat) { throw "Module sans parametres declares : $Unit" }
    $connues = @($cat[0].params | ForEach-Object { $_.key })
    # UtilisateurSeul : on ne recopie pas les valeurs de la machine dans le fichier
    # personnel -- sinon elles y seraient figees et ne suivraient plus l'installation.
    $sur = Get-ParameterOverrides -UtilisateurSeul
    if (-not $sur.ContainsKey($Unit)) { $sur[$Unit] = @{} }
    foreach ($k in $Values.Keys) {
        if ($connues -notcontains "$k") { throw "Parametre non declare : $Unit.$k" }
        if ($null -eq $Values[$k]) { $sur[$Unit].Remove("$k") }
        else { $sur[$Unit]["$k"] = $Values[$k] }
    }
    if ($sur[$Unit].Count -eq 0) { $sur.Remove($Unit) }
    $p = Get-ParametersLocalPath
    $tmp = "$p.tmp"
    ($sur | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $p -Force
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
# Ecriture : couche utilisateur (D65). Lecture : la sienne si elle existe, celle de la
# machine sinon.
function Get-NotificationSettingsPath { Get-UserConfigPath -File 'notifications.local.json' -Account (Get-ActionRequester) }
function Get-NotificationSettingsReadPath {
    foreach ($p in @((Get-NotificationSettingsPath), (Get-MachineConfigPath -File 'notifications.local.json'))) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Get-NotificationSettingsPath)
}

function Get-NotificationSettings {
    param([string]$Backend = (Get-BackendRoot))
    $s = [ordered]@{ enabled = $true; modules = [ordered]@{}; notifs = [ordered]@{} }
    $p = Get-NotificationSettingsReadPath
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $j.enabled) { $s.enabled = [bool]$j.enabled }
            if ($j.modules) { foreach ($pr in $j.modules.PSObject.Properties) { $s.modules[$pr.Name] = [bool]$pr.Value } }
            if ($j.notifs)  { foreach ($pr in $j.notifs.PSObject.Properties)  { $s.notifs[$pr.Name]  = [bool]$pr.Value } }
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
        [hashtable]$Modules,
        # Table « <module>.<notification> » -> $true/$false. Fusionnee comme le reste.
        [hashtable]$Notifs
    )
    $cur = Get-NotificationSettings -Backend $Backend
    $out = [ordered]@{ enabled = [bool]$cur.enabled; modules = [ordered]@{}; notifs = [ordered]@{} }
    foreach ($k in @($cur.modules.Keys)) { $out.modules["$k"] = [bool]$cur.modules[$k] }
    foreach ($k in @($cur.notifs.Keys))  { $out.notifs["$k"]  = [bool]$cur.notifs[$k] }
    if ($null -ne $Enabled) { $out.enabled = [bool]$Enabled }
    if ($Modules) { foreach ($k in $Modules.Keys) { $out.modules["$k"] = [bool]$Modules[$k] } }
    if ($Notifs)  { foreach ($k in $Notifs.Keys)  { $out.notifs["$k"]  = [bool]$Notifs[$k] } }
    $p = Get-NotificationSettingsPath
    $tmp = "$p.tmp"
    ($out | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $p -Force
    [pscustomobject]$out
}

# --- CATALOGUE DES NOTIFICATIONS (D54, revu le 26/08) -------------------------
# Une notification n'est PAS « une carte » : c'est un EVENEMENT nomme, que le module
# declare. « Session de jeu » ne dit rien a personne ; « Temperature GPU elevee » si.
# (Signale par l'utilisateur : l'ecran listait les cartes, pas les notifications.)
#
# Declaration, dans probes/<module>/module.psd1 :
#   Notifications = @(
#       @{ Key = 'gpu-temp'; Label = 'Temperature GPU elevee'
#          Field = 'gpu-temp'; Card = 'gaming'; Help = '...' }
#   )
# Key   : identifiant stable du reglage (jamais affiche) ;
# Label : ce que l'utilisateur lit ;
# Card / Field : la carte et le champ dont la BASCULE declenche la notification.
#
# Un module sans declaration retombe sur une notification unique par carte : l'ancien
# comportement, pour ne rien perdre en route.
function Get-NotificationCatalog {
    param([string]$Backend = (Get-BackendRoot))
    @(foreach ($u in (Get-UnitCatalog -Backend $Backend)) {
        $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $u.id) 'module.psd1'
        $decl = @{}
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        $notifs = @(foreach ($nn in @($decl.Notifications)) {
            if (-not $nn -or -not $nn.Key) { continue }
            [ordered]@{
                key   = "$($nn.Key)"
                label = "$($nn.Label)"
                help  = if ($nn.Help) { "$($nn.Help)" } else { '' }
                card  = if ($nn.Card) { "$($nn.Card)" } else { '' }
                field = if ($nn.Field) { "$($nn.Field)" } else { '' }
                # QUI peut y faire quelque chose, et faut-il quand meme prevenir ?
                rights   = if ($nn.Droits) { "$($nn.Droits)" } else { 'tous' }
                critical = [bool]$nn.Critique
            }
        })
        [pscustomobject][ordered]@{ unit = $u.id; label = $u.label; enabled = $u.enabled; notifications = $notifs }
    })
}

# Le tray applique la regle SANS refaire la logique : une notification pour ce module
# passe-t-elle ? (global coupe = rien ; sinon le reglage fin, actif par defaut)
function Test-NotificationAllowed {
    param(
        [Parameter(Mandatory)][string]$ModuleId,
        # Cle de la notification declaree par le module. Absente : on juge au niveau du
        # module, comme avant.
        [string]$Key,
        $Settings
    )
    if (-not $Settings) { $Settings = Get-NotificationSettings }
    if (-not [bool]$Settings.enabled) { return $false }
    # DROITS (regle utilisateur, 26/08) : on ne derange pas quelqu'un avec un probleme
    # qu'il ne peut pas resoudre. Une notification dont la resolution exige un
    # administrateur ne s'affiche donc pas pour un compte standard...
    # ...SAUF si elle est declaree CRITIQUE : antivirus coupe, pare-feu ouvert, mises a
    # jour en attente. Dans ce cas l'utilisateur doit savoir, ne serait-ce que pour le
    # signaler a un administrateur -- le tray le lui dit explicitement.
    if ($Key -and -not (Test-IsElevated)) {
        $decl = $null
        foreach ($u in (Get-NotificationCatalog)) {
            if ($u.unit -ne $ModuleId) { continue }
            $decl = @($u.notifications | Where-Object { $_.key -eq $Key })[0]
            break
        }
        if ($decl -and "$($decl.rights)" -eq 'admin' -and -not $decl.critical) { return $false }
    }
    # Reglage FIN (par notification) : il l'emporte sur celui du module.
    if ($Key -and $Settings.notifs) {
        $ref = "$ModuleId.$Key"
        $p = $Settings.notifs.PSObject.Properties | Where-Object { $_.Name -eq $ref } | Select-Object -First 1
        if (-not $p -and ($Settings.notifs -is [System.Collections.IDictionary]) -and $Settings.notifs.Contains($ref)) {
            return [bool]$Settings.notifs[$ref]
        }
        if ($p) { return [bool]$p.Value }
    }
    # `modules` est un DICTIONNAIRE (jamais un objet JSON brut : Get-NotificationSettings
    # normalise) -- l'acces passe donc par ContainsKey. La premiere version interrogeait
    # PSObject.Properties, qui sur un dictionnaire decrit le conteneur et pas les cles :
    # tous les reglages fins etaient silencieusement ignores.
    if ($Settings.modules.Contains("$ModuleId")) { return [bool]$Settings.modules["$ModuleId"] }
    return $true
}

# --- Actions ---------------------------------------------------------------
function New-JobId { [guid]::NewGuid().ToString('N').Substring(0, 12) }

# --- DEUX ENVIRONNEMENTS SUR UNE MEME MACHINE -------------------------------
#
# Le depot (developpement) et l'installation partagee (production locale) coexistent sur
# un poste de developpeur. Savoir LEQUEL repond n'est pas un detail : un correctif
# deploye au mauvais endroit coute une heure a comprendre.
#
# Deux notions, a ne pas confondre :
#   - l'environnement DECLARE : ce que la machine dit vouloir etre (reglage, defaut prod) ;
#   - l'environnement OBSERVE : d'ou le code qui tourne vient REELLEMENT.
# Quand les deux different, c'est un defaut nomme, pas un mystere.
function Get-DeclaredStage {
    param([string]$Backend = (Get-BackendRoot))
    <#
        LE STAGE, PAS « L'ENVIRONNEMENT ».

        « Environnement » ne disait pas de quoi on parlait : ce reglage, le serveur, ou
        l'ordinateur entier ? C'est un STAGE au sens deploiement -- dev, prod, et la place
        pour un « staging » plus tard.

        L'ancien nom reste LU : un config.local.psd1 deja pose sur une machine ne doit pas
        cesser de fonctionner parce qu'on a trouve un meilleur mot.
    #>
    try {
        $cfg = Get-Config -Backend $Backend
        foreach ($k in @('Stage', 'Environment')) {
            $value = "$($cfg.$k)".Trim().ToLowerInvariant()
            if ($value -in @('dev', 'prod')) { return $value }
        }
    } catch { }
    return 'prod'      # defaut : une machine est en production tant qu'on n'a pas dit l'inverse
}

# D'ou vient le code qui tourne : sous Program Files, c'est l'installation partagee ;
# ailleurs, c'est un depot de travail. On lit le CHEMIN, pas une intention.
function Get-PathStage {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        if ("$Path".StartsWith("$root", [StringComparison]::OrdinalIgnoreCase)) { return 'prod' }
    }
    return 'dev'
}

function Get-RunningStage {
    param([string]$Backend = (Get-BackendRoot))
    Get-PathStage -Path $Backend
}

# Le libelle affiche, en clair : « Production » ne dit pas d'ou vient le code.
<#
    L'ENVIRONNEMENT DIT LA SOURCE, PAS L'EMPLACEMENT.

    Les libelles disaient « Developpement (depot) » / « Production (installation
    partagee) », comme si le code tournait a deux endroits. Il n'en tourne qu'un :
    l'installation partagee, developpement compris. Ce qui change, c'est CE QU'ON Y
    DEPLOIE -- une branche du depot, ou une version publiee.
#>
function Get-StageLabel {
    param([Parameter(Mandatory)][ValidateSet('dev', 'prod')][string]$Stage)
    # L'ENVIRONNEMENT NE DIT PAS LA SOURCE. Les deux libelles la nommaient (« source : le
    # depot », « source : versions publiees ») : c'est un REGLAGE A PART (UpdateSource),
    # et une production peut se synchroniser depuis un clone local sans cesser d'en etre
    # une. Deux axes, aucun deduit de l'autre.
    # MAJUSCULE INITIALE : c'est une VALEUR affichee dans une carte, pas un mot au milieu
    # d'une phrase -- check-probes le verifie. Les phrases, elles, ont leurs propres
    # libelles.
    if ($Stage -eq 'dev') { return 'Développement' }
    return 'Production'
}

# --- TRACABILITE : toute action laisse une trace, deux fois ------------------
#
# « On doit toujours pouvoir retrouver et justifier une action de Vigie. » Une trace
# qu'un fichier supprime fait disparaitre n'est pas une trace : chaque action ecrit donc
# AUSSI dans le journal des evenements Windows, la ou un administrateur va deja chercher
# quand il enquete, et d'ou Vigie ne peut pas l'effacer.
#
# Ce qui est trace : les actions REUSSIES, les actions REFUSEES et celles qui ECHOUENT.
# Le refus compte autant que la reussite -- c'est meme lui qu'on relit apres un incident.
$script:VigieEventSource = 'Vigie'
$script:VigieEventLog    = 'Application'

# Identifiants d'evenement, stables : ils servent a filtrer dans l'Observateur.
$script:VigieEventIds = @{ done = 1000; denied = 1001; failed = 1002 }

# La source doit exister AVANT d'ecrire, et la creer exige l'elevation. On la pose a
# l'installation ; ici on se contente de la creer si on peut, et de ne jamais faire
# echouer une action pour un probleme de journal.
function Register-VigieEventSource {
    param([switch]$Quiet)
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($script:VigieEventSource)) { return $true }
    } catch {
        # Sans elevation, meme la LECTURE est refusee : on ne sait pas, donc on n'affirme rien.
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-etat') -ForegroundColor DarkGray }
        return $false
    }
    try {
        [System.Diagnostics.EventLog]::CreateEventSource($script:VigieEventSource, $script:VigieEventLog)
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-source' $script:VigieEventSource) -ForegroundColor Green }
        return $true
    } catch {
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-source-2' $_.Exception.Message) -ForegroundColor Yellow }
        return $false
    }
}

# Le compte qui DEMANDE l'action. Aujourd'hui le serveur tourne dans la session de son
# utilisateur : c'est donc lui. Quand le serveur deviendra une tache machine servant
# plusieurs comptes, seule CETTE fonction changera -- tout le reste de la chaine parle
# deja de « demandeur » et non de « moi ».
<#
    QUI DEMANDE ? Le compte derriere la requete, pas le compte qui fait tourner le serveur.

    Cette fonction rendait l'identite du PROCESSUS -- c'est-a-dire toujours celle du
    serveur. Tant qu'il y avait un serveur par session, c'etait juste par accident. Avec
    un serveur unique pour la machine, c est faux pour tout le monde sauf lui : une action
    demandee par Famille serait journalisee au nom de fhaza, et executee sur SON bureau.

    L'ordre des preuves :
      1. le cookie de session, quand la demande vient d une page identifiee -- la seule
         source qui dise vraiment QUI regarde ;
      2. a defaut, l identite du processus : un script local, une tache planifiee, un
         diagnostic. C est alors le compte du serveur, et c est exact.

    LE NOM EST RENDU SANS SON DOMAINE. « HYPERION\fhaza » ne se joint pas a un chemin de
    profil : Get-AccountVarRoot en tirerait « C:\Users\HYPERION\fhaza ».
#>
<#
    QUI DEMANDE -- ou RIEN.

    Get-ActionRequester doit toujours rendre un nom : il signe le journal d'audit, et une
    trace anonyme ne vaut rien. Il retombe donc sur le compte du processus quand aucune
    session n'est ouverte.

    C'EST EXACTEMENT CE QUI NE VA PAS pour tout ce qui parle de « vous ». Une page ouverte
    sans ticket (un signet, un rechargement) n'a pas de cookie : le repli designe alors le
    compte du service, et la carte Comptes affiche « VOUS » sur VigieService -- constate le
    29/08.

    Cette fonction-ci ne se rabat sur rien : pas de session, pas de personne. A l'appelant
    de dire ce que « personne » signifie chez lui -- souvent « aucun compte n'est vous »,
    parfois « on previent tout le monde ».
#>
function Get-RequesterAccount {
    try {
        if ($WebEvent) {
            $sid = $null
            try { $sid = $WebEvent.Cookies['vigie_session'].Value } catch { }
            if ($sid) {
                $account = Get-SessionAccount -SessionId $sid
                if ($account) { return $account }
            }
        }
    } catch { }
    return $null
}

function Get-ActionRequester {
    try {
        if ($WebEvent) {
            $sid = $null
            try { $sid = $WebEvent.Cookies['vigie_session'].Value } catch { }
            if ($sid) {
                $account = Get-SessionAccount -SessionId $sid
                if ($account) { return $account }
            }
        }
    } catch { }
    try {
        $nom = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
        $sep = $nom.LastIndexOf([char]92)
        if ($sep -ge 0) { $nom = $nom.Substring($sep + 1) }
        return $nom
    } catch { return 'inconnu' }
}

function Write-VigieAudit {
    param(
        [Parameter(Mandatory)][ValidateSet('done', 'denied', 'failed')][string]$Outcome,
        [Parameter(Mandatory)][string]$Action,
        [string]$Module,
        [string]$Requester = (Get-ActionRequester),
        [string]$Rights = 'tous',
        [string]$Detail,
        [int]$Milliseconds = 0,
        [string]$Backend = (Get-BackendRoot)
    )
    $outcomeLabel = switch ($Outcome) {
        'done'   { 'REUSSIE' }
        'denied' { 'REFUSEE' }
        'failed' { 'ECHEC' }
    }
    $entry = ("{0} | action={1} | module={2} | demandeur={3} | droits={4}" -f
              $outcomeLabel, $Action, $(if ($Module) { $Module } else { '-' }), $Requester, $Rights)
    if ($Milliseconds -gt 0) { $entry += (" | duree={0} ms" -f $Milliseconds) }
    if ($Detail) { $entry += (" | " + $Detail) }

    # 1. Le journal de Vigie : le detail, relu pendant un depannage.
    try {
        $level = if ($Outcome -eq 'failed') { 'ERROR' } elseif ($Outcome -eq 'denied') { 'WARN' } else { 'INFO' }
        Write-Log -Backend $Backend -Name 'audit' -Level $level -Message $entry
    } catch { }

    # 2. Le journal des evenements Windows : la trace opposable.
    #
    # ELLE NE DOIT JAMAIS FAIRE ECHOUER L'ACTION. Un journal indisponible est un probleme
    # de journal, pas un probleme d'action -- mais il se voit dans celui de Vigie, sinon
    # on croirait la trace ecrite alors qu'elle ne l'est pas.
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($script:VigieEventSource)) {
            $type = switch ($Outcome) {
                'done'   { [System.Diagnostics.EventLogEntryType]::Information }
                'denied' { [System.Diagnostics.EventLogEntryType]::Warning }
                'failed' { [System.Diagnostics.EventLogEntryType]::Error }
            }
            [System.Diagnostics.EventLog]::WriteEntry(
                $script:VigieEventSource, $entry, $type, $script:VigieEventIds[$Outcome])
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'audit' -Level 'WARN' `
                        -Message (Get-Label 'common.journal-des-evenements-windows' $_.Exception.Message) } catch { }
    }
}

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
    # Garde REELLE : le bouton grise n'est qu'un affichage ; c'est ici que le refus
    # compte, une requete pouvant arriver sans passer par l'interface.
    # TRACE DE BOUT EN BOUT. Ce point est le seul par ou passe une action : c'est donc ici,
    # et nulle part ailleurs, qu'on ecrit qui a demande quoi et ce qui en est sorti. Un
    # REFUS se trace autant qu'une reussite -- c'est meme lui qu'on relit apres un incident.
    $requester = Get-ActionRequester
    $rights    = try { (Get-ActionRequirement -Type $Type -Backend $Backend) } catch { 'tous' }
    $timer    = [System.Diagnostics.Stopwatch]::StartNew()

    $droit = Test-ActionAllowed -Type $Type -Backend $Backend
    if (-not $droit.allowed) {
        Write-VigieAudit -Outcome 'denied' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("raison=" + $droit.reason) -Backend $Backend
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $droit.reason }
    }
    $file = Join-Path $Backend ("actions/$Type.action.ps1")
    $full = try { (Resolve-Path -LiteralPath $file -ErrorAction Stop).Path } catch { $null }
    $actionsDir = (Resolve-Path -LiteralPath (Join-Path $Backend 'actions')).Path
    if (-not $full -or -not $full.StartsWith($actionsDir)) {
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = "Action inconnue : $Type" }
    }
    # LE VERROU EST ICI, pas dans l'interface (D93). Une page restee ouverte peut
    # toujours envoyer une action : c'est le serveur qui doit dire non.
    $conflit = Test-ActionResourcesFree -Type $Type -Backend $Backend
    if ($conflit) {
        Write-VigieAudit -Outcome 'denied' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("ressource occupee : " + $conflit) -Backend $Backend
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $conflit }
    }
    try {
        # DANS QUELLE SESSION ? Une action declaree « session » doit s'executer chez le DEMANDEUR,
        # pas la ou tourne le serveur. On la lui fait executer par son tray ; s'il ne
        # repond pas, on l'execute ici comme avant plutot que de ne rien faire.
        $res = $null
        if ((Get-ActionExecutor -Type $Type -Backend $Backend) -eq 'session' -and $requester -and $requester -ne '-') {
            $relais = Invoke-DesktopAction -Account $requester -Type $Type -Params $Params -Module $Module -Backend $Backend
            if ($relais) {
                $res = @{ message = "$($relais.message)"; result = $relais.result }
            } else {
                try { Write-Log -Backend $Backend -Name 'actions' -Level 'WARN' `
                                -Message ("Action " + $Type + " : le tray de " + $requester + " n'a pas repondu, execution locale.") } catch { }
            }
        }
        if (-not $res) { $res = & $file -Module $Module -Params $Params }
        # Invalidation ciblee du cache : les sondes citees seront recalculees au prochain /state
        try {
            $inv = if ($res -and $res.result -and $res.result.invalidate) { @($res.result.invalidate) } else { @() }
            if ($inv.Count) { Remove-ProbeCache -Names $inv -Backend $Backend }
        } catch { }
        # Une action peut rendre « ok = false » sans lever : c'est un echec, et il se trace
        # comme tel. Se fier au seul try/catch laisserait passer les echecs polis.
        $succeeded = -not ($res -and $res.result -and $res.result.PSObject.Properties['ok'] -and $res.result.ok -eq $false)
        Write-VigieAudit -Outcome $(if ($succeeded) { 'done' } else { 'failed' }) -Action $Type -Module $Module `
                         -Requester $requester -Rights $rights -Detail ("" + $res.message) `
                         -Milliseconds ([int]$timer.ElapsedMilliseconds) -Backend $Backend
        [pscustomobject]@{ jobId = (New-JobId); status = 'done'; message = $res.message; result = $res.result }
    } catch {
        Write-VigieAudit -Outcome 'failed' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("exception : " + $_.Exception.Message) `
                         -Milliseconds ([int]$timer.ElapsedMilliseconds) -Backend $Backend
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

    # LA FENETRE VIT DANS scripts/lib/show-confirm.ps1, et nulle part ailleurs.
    #
    # Elle doit pouvoir s'afficher AVANT la premiere elevation, quand PowerShell 7 n'est
    # pas encore installe : elle est donc ecrite pour tourner aussi sous Windows
    # PowerShell 5.1, et vit hors de cette bibliotheque qui, elle, vise PS7. La dessiner
    # une seconde fois ici aurait garanti que les deux divergent des la premiere retouche.
    $script = $null
    try { $script = Join-Path (Get-RepoRoot) 'scripts/lib/show-confirm.ps1' } catch { }

    if ($script -and (Test-Path -LiteralPath $script)) {
        $exe = $null
        try { $exe = (Get-Process -Id $PID).Path } catch { }
        if (-not $exe) { $exe = 'powershell.exe' }
        # LE TEXTE NE TRAVERSE PAS LA LIGNE DE COMMANDE. Passe en argument, il subit la
        # page de code du processus appele : « securite » y devient « sIcuritI » (constate
        # le 29/08). Ces textes-la sont CONSTRUITS -- ils viennent de l'action, pas d'un
        # libelle -- donc aucune cle ne les designe : ils passent par un fichier, et seul
        # son chemin, en ASCII, franchit la frontiere.
        $payload = Join-Path ([IO.Path]::GetTempPath()) ('vigie-confirm-' + [guid]::NewGuid().ToString('N') + '.json')
        $data = @{ title = "$Title"; summary = "$Summary"
                   changes = ($Changes -join '|'); initiatedBy = "$InitiatedBy" }
        [System.IO.File]::WriteAllText($payload, ($data | ConvertTo-Json -Compress -Depth 4),
                                       (New-Object System.Text.UTF8Encoding($false)))
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script,
                  '-PayloadFile', $payload)
        try {
            & $exe @argv
            # 0 = continuer ; 3 = refus ; 1 = pas d'interface, et le script l'a dit en
            # console. Tout ce qui n'est pas 0 REFUSE : rien ne s'eleve sans consentement.
            return ($LASTEXITCODE -eq 0)
        } catch {
            Write-Host (Get-Label 'common.impossible-afficher-la-fenetre' $_.Exception.Message) -ForegroundColor Yellow
        } finally {
            # DANS UN « finally », pas apres le return : un nettoyage place apres ne
            # s'execute jamais, et le fichier -- qui porte le texte de la fenetre --
            # resterait dans le dossier temporaire a chaque elevation. Et « finally »
            # vient APRES « catch » : l'ordre inverse ne s'analyse pas.
            try { Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

    # Repli : le script est introuvable (installation abimee). On explique en console et
    # on REFUSE -- utiliser -Yes pour un lancement volontairement automatise.
    $nl = [Environment]::NewLine
    Write-Host ""
    if ($InitiatedBy) {
        Write-Host (Get-Label 'common.demande-par-un-agent' $InitiatedBy) -ForegroundColor Yellow
        Write-Host (Get-Label 'common.ce-est-pas-toi') -ForegroundColor Yellow
    }
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $Summary
    if ($Changes.Count) { Write-Host (($Changes | ForEach-Object { "   - $_" }) -join $nl) }
    Write-Host (Get-Label 'common.fenetre-de-confirmation-introuvable') -ForegroundColor Yellow
    return $false
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

    # UTF-8 IMPOSE DES LES DEUX BOUTS. Sans cela, la session elevee ecrit son journal
    # dans la page de code de la console (850 ou 1252 selon la machine) et le parent le
    # relit en UTF-8 : « Trouve » revenait « Trouv├® » (constate le 27/08). Les accents
    # ne sont pas negociables (D41).
    $parts = @('$OutputEncoding=[Text.Encoding]::UTF8;',
               '[Console]::OutputEncoding=[Text.Encoding]::UTF8;',
               '&', (ConvertTo-PSLiteral $ScriptPath))
    foreach ($a in $Arguments) {
        if ($a -like '-*') { $parts += $a } else { $parts += (ConvertTo-PSLiteral ([string]$a)) }
    }
    $cmd = ($parts -join ' ') + ' *> ' + (ConvertTo-PSLiteral $log)

    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-Host (Get-Label 'common.pwsh-introuvable') -ForegroundColor Red; return 1 }

    try {
        $proc = Start-Process $pwshPath -Verb RunAs -Wait -PassThru -WindowStyle Hidden -WhatIf:$false -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
    } catch {
        Write-Host (Get-Label 'common.elevation-refusee-ou-impossible' $_.Exception.Message) -ForegroundColor Yellow
        return 1
    }

    if (Test-Path -LiteralPath $log) {
        Write-Host (Get-Label 'common.compte-rendu-de-la')
        Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ }
        Write-Host (Get-Label 'common.journal' $log)
    } else {
        Write-Host (Get-Label 'common.aucune-sortie-produite-par') -ForegroundColor Yellow
    }
    return $proc.ExitCode
}
