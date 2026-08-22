<#
    common.ps1 - Bibliotheque partagee du backend. Aucune dependance a Pode.
    Fabriques d'objets (contrat), config, jeton, agregation des sondes (avec
    journalisation par sonde), execution des actions, utilitaires.
#>

function Get-BackendRoot { Split-Path $PSScriptRoot -Parent }

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
# les fichiers .state (netmeasure.json, pkgupdates.json, ...).
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
    $cacheFile = Join-Path $Backend '.state\state-cache.json'
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

# Le verrou ACL (refus d'ecriture a SYSTEM) est-il pose sur le dossier de taches ?
# Comparaison par SID (S-1-5-18), independante de la langue et de la traduction du compte.
function Test-UpdateTasksAclLock {
    param([string]$Path = "$env:windir\System32\Tasks\Microsoft\Windows\UpdateOrchestrator")
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
function Get-PackageManagerCatalog {
    @(
        [pscustomobject]@{ id='winget'; label='winget';       verArgs=@('--version'); updArgs=@('upgrade','--include-unknown'); updMode='winget';   upgArgs=@('upgrade','--all','--silent','--include-unknown','--accept-source-agreements','--accept-package-agreements') }
        [pscustomobject]@{ id='choco';  label='Chocolatey';   verArgs=@('--version'); updArgs=@('outdated','-r','--nocolor');   updMode='chocor';   upgArgs=@('upgrade','all','-y') }
        [pscustomobject]@{ id='scoop';  label='Scoop';        verArgs=@('--version'); updArgs=@('status');                      updMode='lines';    upgArgs=@('update','*') }
        [pscustomobject]@{ id='npm';    label='npm';          verArgs=@('-v');        updArgs=@('outdated','-g','--json');      updMode='jsonkeys'; upgArgs=@('update','-g') }
        [pscustomobject]@{ id='pnpm';   label='pnpm';         verArgs=@('-v');        updArgs=@('outdated','-g');               updMode='lines';    upgArgs=@() }
        [pscustomobject]@{ id='yarn';   label='Yarn';         verArgs=@('-v');        updArgs=@();                             updMode='none';     upgArgs=@() }
        [pscustomobject]@{ id='pip';    label='pip (Python)'; verArgs=@('--version'); updArgs=@('list','--outdated','--format=json'); updMode='jsonlist'; upgArgs=@() }
        [pscustomobject]@{ id='pipx';   label='pipx';         verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@() }
        [pscustomobject]@{ id='cargo';  label='Cargo (Rust)'; verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@() }
        [pscustomobject]@{ id='gem';    label='RubyGems';     verArgs=@('--version'); updArgs=@('outdated');                    updMode='lines';    upgArgs=@('update') }
        [pscustomobject]@{ id='dotnet'; label='.NET SDK';     verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@() }
    )
}

# Verifie les MAJ disponibles d'UN gestionnaire (appel lent/reseau). Traite la
# sortie ET le code de retour via Invoke-Native. Renvoie @{ count; items; supported }.
function Get-PkgUpdates {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg) { return @{ count = 0; items = @(); supported = $false } }
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ count = 0; items = @(); supported = $false } }
    if ($mg.updMode -eq 'none' -or $mg.updArgs.Count -eq 0) { return @{ count = 0; items = @(); supported = $false } }
    $count = 0; $items = @()
    try {
        $r = Invoke-Native -File $cmd.Source -Arguments $mg.updArgs
        $out = "$($r.Output)"
        switch ($mg.updMode) {
            'jsonlist' {
                if ($out.Trim()) { $j = $out | ConvertFrom-Json; $items = @($j | ForEach-Object { "{0}  {1} -> {2}" -f $_.name, $_.version, $_.latest_version }); $count = $items.Count }
            }
            'jsonkeys' {
                if ($out.Trim() -and $out.Trim() -ne '{}') { $j = $out | ConvertFrom-Json; $items = @($j.PSObject.Properties | ForEach-Object { "{0} -> {1}" -f $_.Name, $_.Value.latest }); $count = $items.Count }
            }
            'chocor' {
                $items = @(($out -split "`r?`n") | Where-Object { $_ -match '\|' } | ForEach-Object { $p = $_.Split('|'); "{0}  {1} -> {2}" -f $p[0], $p[1], $p[2] })
                $count = $items.Count
            }
            'winget' {
                $lines = @($out -split "`r?`n"); $idx = -1
                for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{3,}') { $idx = $i; break } }
                if ($idx -ge 0 -and $idx -lt ($lines.Count - 1)) {
                    $rest = @($lines[($idx+1)..($lines.Count-1)] | Where-Object { $_.Trim() -and $_ -notmatch 'niveau|upgrade|mise' })
                    $items = @($rest | ForEach-Object { (($_ -split '\s{2,}') | Where-Object { $_ })[0] })
                    $count = $items.Count
                }
            }
            'lines' {
                $items = @(($out -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch '^Name|^-{3,}|is up to date|Everything' })
                $count = $items.Count
            }
        }
    } catch { }
    if ($items.Count -gt 25) { $items = @($items[0..24] + "... (+$($items.Count - 25))") }
    return @{ count = $count; items = @($items); supported = $true }
}

# Met a jour TOUS les paquets d'UN gestionnaire (appel lent, systeme). Herite de
# l'elevation du serveur. Traite sortie + code de retour. Renvoie @{ ok; supported; exit; output }.
function Invoke-PkgUpgrade {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg -or -not $mg.upgArgs -or @($mg.upgArgs).Count -eq 0) { return @{ ok = $false; supported = $false; output = '' } }
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ ok = $false; supported = $false; output = '' } }
    $r = Invoke-Native -File $cmd.Source -Arguments $mg.upgArgs
    return @{ ok = $r.Ok; supported = $true; exit = $r.ExitCode; output = $r.Output }
}

# Lanceur GENERIQUE (non bloquant) d'une operation paquet : 'check' ou 'upgrade'.
# Marque la carte "en cours" (avec l'operation), lance le worker detache, rend la
# main immediatement. Code unique partage par les deux actions (pas de duplication).
function Start-PkgJob {
    param(
        [Parameter(Mandatory)][string]$Mgr,
        [ValidateSet('check','upgrade')][string]$Op = 'check',
        [string]$Backend = (Get-BackendRoot)
    )
    $known = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Mgr } | Select-Object -First 1
    if (-not $known) { return @{ message = "Gestionnaire inconnu : $Mgr"; result = @{ ok = $false } } }
    if ($Op -eq 'check'   -and ($known.updMode -eq 'none' -or @($known.updArgs).Count -eq 0)) {
        return @{ message = "Verification non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    if ($Op -eq 'upgrade' -and (-not $known.upgArgs -or @($known.upgArgs).Count -eq 0)) {
        return @{ message = "Mise a jour automatique non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    $stateDir = Join-Path $Backend '.state'
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $outFile = Join-Path $stateDir 'pkgupdates.json'
    # Marque "en cours" (conserve le dernier compte connu pour l'affichage).
    $entry = @{ checking = $true; op = $Op; startedAt = (Get-Date).ToString('s') }
    if (Test-Path $outFile) {
        try {
            $j = Get-Content $outFile -Raw | ConvertFrom-Json; $e = $j.$Mgr
            if ($e -and $null -ne $e.count) { $entry.count = [int]$e.count; $entry.items = @($e.items) }
        } catch { }
    }
    Update-StateJson -Path $outFile -Set @{ $Mgr = $entry } | Out-Null
    # Worker unique (branche sur op). Detache, fenetre cachee : ne bloque pas.
    $worker  = Join-Path $Backend 'workers/pkg-job.worker.ps1'
    $started = $false
    try { $null = Start-DetachedAction -Script $worker -ArgsMap @{ mgr = $Mgr; op = $Op } -Backend $Backend; $started = $true } catch { }
    if (-not $started) { return @{ message = "Impossible de lancer l'operation sur $($known.label)."; result = @{ ok = $false } } }
    $verb = if ($Op -eq 'upgrade') { 'Mise a jour' } else { 'Verification' }
    @{
        message = "$verb de $($known.label) lancee en tache de fond."
        result  = @{ ok = $true; async = $true; module = ("pkg-" + $Mgr); invalidate = @('packages.probe.ps1') }
    }
}


# config.psd1 (versionne) porte LA definition de chaque valeur.
# config.local.psd1 (ignore par git, optionnel) surcharge les SEULES valeurs qui ne
# peuvent pas etre generiques : chemins propres a une machine. Voir config.local.sample.psd1.
function Get-Config {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = Import-PowerShellDataFile -Path (Join-Path $Backend 'config.psd1')
    $localPath = Join-Path $Backend 'config.local.psd1'
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
function New-ToolsMissingResult {
    @{
        message = "Outillage externe non configure. Renseigne ToolsPath dans backend/config.local.psd1 (modele : config.local.sample.psd1)."
        result  = @{ ok = $false }
    }
}

function Get-ApiToken {
    param([string]$Backend = (Get-BackendRoot))
    $dir  = Join-Path $Backend '.secrets'
    $file = Join-Path $dir 'api.token'
    if (-not (Test-Path $file)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
        Set-Content -Path $file -Value $token -NoNewline -Encoding ASCII
    }
    (Get-Content -Path $file -Raw).Trim()
}

# --- Version applicative (change quand index.html change) -------------------
function Get-AppVersion {
    param([string]$Backend = (Get-BackendRoot))
    $idx = Join-Path (Split-Path $Backend -Parent) 'frontend/index.html'
    if (Test-Path $idx) { "$((Get-Item $idx).LastWriteTimeUtc.Ticks)" } else { '0' }
}

# --- Journalisation ---------------------------------------------------------
function Get-LogDir {
    param([string]$Backend = (Get-BackendRoot))
    $d = Join-Path $Backend 'logs'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
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
        [string]$Guide
    )
    $f = [ordered]@{ key = $Key; label = $Label; value = $Value; kind = $Kind }
    if ($Unit)      { $f['unit']      = $Unit }
    if ($Status)    { $f['status']    = $Status }
    if ($Help)      { $f['help']      = $Help }
    if ($FixAction) { $f['fixAction'] = $FixAction }
    if ($Guide)     { $f['guide']     = $Guide }
    [pscustomobject]$f
}
function New-Action {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [switch]$Confirm,
        [string]$Help,
        [ValidateSet('immediate','confirm','manual')][string]$Kind
    )
    $a = [ordered]@{ id = $Id; label = $Label }
    if ($Confirm) { $a['confirm'] = $true }
    if ($Help)    { $a['help']    = $Help }
    $a['kind'] = if ($Kind) { $Kind } elseif ($Confirm) { 'confirm' } else { 'immediate' }
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
        [switch]$Busy
    )
    $o = [ordered]@{
        id = $Id; theme = $Theme; label = $Label; status = $Status
        fields = @($Fields); actions = @($Actions)
    }
    if ($Busy) { $o['busy'] = $true }
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

function Get-State {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force)
    $probesDir = Join-Path $Backend 'probes'
    $cacheFile = Join-Path $Backend '.state\state-cache.json'
    $stateDir  = Split-Path $cacheFile -Parent
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $defaultTtl = 30

    # Charge le cache existant
    $cache = @{}
    if (-not $Force -and (Test-Path $cacheFile)) {
        try { $j = Get-Content $cacheFile -Raw | ConvertFrom-Json; foreach ($pr in $j.PSObject.Properties) { $cache[$pr.Name] = $pr.Value } } catch { }
    }

    # Sondes + fraicheur (invalidation PAR sonde : mtime du fichier + TTL)
    $now = Get-Date
    $probeFiles = @(Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -ErrorAction SilentlyContinue | Sort-Object FullName)
    $stale = @()
    foreach ($pf in $probeFiles) {
        $name = $pf.Name; $stamp = "$($pf.LastWriteTimeUtc.Ticks)"
        $ttl = if ($script:ProbeTtls.ContainsKey($name)) { $script:ProbeTtls[$name] } else { $defaultTtl }
        $entry = $cache[$name]; $fresh = $false
        if ($entry -and $entry.at -and ("$($entry.codeStamp)" -eq $stamp)) {
            try { if ((($now - [datetime]$entry.at).TotalSeconds) -lt $ttl) { $fresh = $true } } catch { }
        }
        if (-not $fresh) { $stale += [pscustomobject]@{ File = $pf.FullName; Name = $name; Stamp = $stamp } }
    }

    # Recalcul en SINGLE-FLIGHT : un seul thread recalcule a la fois ; les autres requetes
    # servent le cache existant immediatement (evite l'effet troupeau -> plus de 408).
    if ($stale.Count -gt 0) {
        $slow  = @('lock.probe.ps1','pending.probe.ps1','wsl.probe.ps1')   # calculees en dernier
        $stale = @($stale | Sort-Object @{ Expression = { if ($slow -contains $_.Name) { 1 } else { 0 } } }, Name)
        $mx = $null; $got = $false
        try {
            $mx = New-Object System.Threading.Mutex($false, 'Local\VigieStateRecompute')
            try { $got = $mx.WaitOne(0) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if ($got) {
                foreach ($sp in $stale) {
                    $t0 = Get-Date
                    try {
                        $m = & $sp.File
                        if ($m) { $cache[$sp.Name] = [ordered]@{ module = $m; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp } }
                        Write-Log -Backend $Backend -Name 'state' -Message ("sonde " + $sp.Name + " recalculee (" + [int]((Get-Date) - $t0).TotalMilliseconds + " ms)")
                    } catch {
                        Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message ("sonde erreur : " + $sp.Name + " : " + $_.Exception.Message)
                        $errMod = New-ModuleObject -Id $sp.Name -Theme 'system' -Label $sp.Name -Status 'error' -Fields @(New-Field -Key 'error' -Label 'Erreur de sonde' -Value $_.Exception.Message -Kind 'text')
                        $cache[$sp.Name] = [ordered]@{ module = $errMod; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp }
                    }
                    # Ecriture incrementale ATOMIQUE : chaque sonde finie est conservee.
                    try {
                        $tmp = "$cacheFile.tmp"
                        ([pscustomobject]$cache) | ConvertTo-Json -Depth 8 | Set-Content -Path $tmp -Encoding UTF8
                        Move-Item -Path $tmp -Destination $cacheFile -Force
                    } catch { }
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
        host        = "$env:COMPUTERNAME"
        themes      = $themes
        modules     = @($modules)
    }
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
