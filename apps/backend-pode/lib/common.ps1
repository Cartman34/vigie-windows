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

# Pose ou leve le verrou des mises a jour (script update-mode.ps1 de l'outillage).
#
# Ecrit ICI et nulle part ailleurs : les actions update-mode-on / update-mode-off et
# l'installation des MAJ appellent toutes cette fonction. Sans cela, l'installation aurait
# recopie l'invocation du script -- troisieme copie, donc future divergence (D15).
#
# Renvoie $true si l'etat demande est REELLEMENT obtenu, verifie apres coup et non deduit
# du fait que le script n'a pas leve d'erreur (D43).
function Set-UpdateLock {
    param(
        [Parameter(Mandatory)][ValidateSet('pose','leve')][string]$Etat,
        [string]$Backend = (Get-BackendRoot)
    )
    $tools = Get-ToolsPath -Backend $Backend
    if (-not $tools) { return $false }
    $script = Join-Path $tools 'update-mode.ps1'
    if (-not (Test-Path -LiteralPath $script)) { return $false }
    try {
        if ($Etat -eq 'pose') { & $script -Off *> $null } else { & $script -On *> $null }
    } catch { return $false }
    $verrouille = Test-UpdateTasksAclLock
    return $(if ($Etat -eq 'pose') { $verrouille } else { -not $verrouille })
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
        [pscustomobject]@{ id='winget'; label='winget';       verArgs=@('--version'); updArgs=@('upgrade','--include-unknown','--disable-interactivity','--accept-source-agreements'); updMode='winget';   upgArgs=@('upgrade','--all','--silent','--include-unknown','--disable-interactivity','--accept-source-agreements','--accept-package-agreements') }
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
    # 3010 = ERROR_SUCCESS_REBOOT_REQUIRED : l'installation a REUSSI, elle demande un
    # redemarrage. Le traiter comme un echec (« ok=False ») etait faux et affichait une
    # erreur sur une operation qui avait fonctionne -- constate sur Chocolatey.
    # 1641 = redemarrage DEJA declenche, meme famille.
    $redemarrage = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
    return @{ ok = ($r.Ok -or $redemarrage); supported = $true; exit = $r.ExitCode
              reboot = $redemarrage; output = $r.Output }
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
    $stateDir = Get-VarPath -Backend $Backend -Kind 'cache'
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
function New-ToolsMissingResult {
    @{
        message = "Outillage externe non configure. Renseigne ToolsPath dans apps/backend-pode/config/config.local.psd1 (modele : config.local.sample.psd1)."
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
        [string]$BusyLabel
    )
    $a = [ordered]@{ id = $Id; label = $Label }
    if ($Confirm) { $a['confirm'] = $true }
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
    $o = [ordered]@{
        id = $Id; theme = $Theme; label = $Label; status = $Status
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

function Get-State {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force)
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
            try {
                $w = Join-Path $Backend 'workers/state-refresh.worker.ps1'
                # Un seul rafraichissement de fond a la fois : le worker prend le meme
                # verrou que le recalcul synchrone et sort si un autre travaille deja.
                $null = Start-DetachedAction -Script $w -Backend $Backend
            } catch { }
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
            $attente = if ($Force) { 180000 } else { 0 }
            try { $got = $mx.WaitOne($attente) }
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
function Test-IsElevated {
    (New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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
