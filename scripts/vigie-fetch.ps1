# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    vigie-fetch.ps1 -- brings back an archive of Vigie, ready to be deployed. IT DEPLOYS NOTHING.

    Intent: do one thing only -- obtain a checked `.zip` and write its path on the last line of its output. It is
    the installation that lays it down afterwards. Separating the two avoids the worst case: a half-finished fetch
    overwriting an installation that worked.

    Usage: it is called by the installation, or by hand to build a release. Exit codes, all distinct so that the
    caller knows WHAT to say:
      0 = the archive is ready (its path is the last line)
      1 = a missing prerequisite (git absent, an unreadable folder...)
      2 = the network or GitHub did not answer
      3 = already up to date: nothing to do, and that is not an error (D77)
      4 = the reference that was asked for does not exist
      5 = what was brought back is not usable (an unreadable or truncated archive)

    THREE ROADS, and a rule for choosing when one does not say (-Source auto):
      - `local`   : the repository is there (a development workstation) -> we build from it.
      - `release` : otherwise -> we download the latest version published on GitHub.
      - `clone`   : as soon as a reference is forced (-Ref), because a branch or a precise commit does not exist
                    as a release.

    THE NETWORK. This is the only place where Vigie goes looking for CODE outside, and never on its own
    initiative: it has to be asked. What is downloaded comes from the official repository over HTTPS; there is no
    signature to verify, and we do not pretend otherwise. What we do check: that the archive opens, that it has
    the expected shape, and that it is not older than what is already running.
#>
param(
    [ValidateSet('auto', 'local', 'release', 'clone')]
    [string] $Source = 'auto',

    # A branch, a tag or a commit. Giving it forces the `clone` road.
    [string] $Ref,

    # Accept pre-releases. GitHub EXCLUDES pre-releases from /releases/latest: without this switch, a machine will
    # see stable versions only. That is deliberate.
    [switch] $PreVersions,

    # Bring it back even if the version found is no more recent than the one in place.
    [switch] $Force,

    # Empty by default: the address comes from the shared configuration (see further down). They stay overridable
    # as parameters, for a fork or a trial.
    [string] $RemoteUrl,
    [string] $ApiRepo
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
# THE REPOSITORY'S ADDRESS COMES FROM THE CONFIGURATION, never from a literal copied here.
if (-not $RemoteUrl -or -not $ApiRepo) {
    $cfgRepo = Get-Config -Backend $backend
    if (-not $ApiRepo) { $ApiRepo = "$($cfgRepo.Repository)" }
    # The clone's address: the public repository, or the local one on a development workstation (D112).
    if (-not $RemoteUrl)   { $RemoteUrl   = (Get-UpdateRemote -Backend $backend) }
}

function Noter {
    param([string]$T, [string]$N = 'INFO')
    try { Write-Log -Backend $backend -Name 'update' -Level $N -Message $T } catch { }
}
# THE EXIT CODE DECIDES THE COLOUR, not the caller. A colour chosen by hand always ends up lying: that is how a
# failure once came out in green (28/08).
# 0 and 3 are not failures -- 3 means there was nothing to do.
function Sortir {
    param([int]$Code, [string]$Message)
    if ($Code -eq 0 -or $Code -eq 3) { Write-Ok $Message } else { Write-Fail $Message }
    Noter $Message $(if ($Code -eq 0 -or $Code -eq 3) { 'INFO' } else { 'ERROR' })
    exit $Code
}

# --- Comparing two versions ---------------------------------------------------
#
# A version with its "v", without it, and with a "+N" suffix must all compare with each other. The "+N" suffix
# counts the commits since the tag: it makes the version MORE recent, not less.
function ConvertTo-Reperage {
    param([string]$Brut)
    if (-not $Brut) { return $null }
    $t = "$Brut".Trim().TrimStart('v', 'V')
    $suite = 0
    if ($t -match '^(.*)\+(\d+)$') { $t = $Matches[1]; $suite = [int]$Matches[2] }
    $parts = @($t -split '[.\-]' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    if (-not $parts.Count) { return $null }
    while ($parts.Count -lt 3) { $parts += 0 }
    [pscustomobject]@{
        Cle   = ($parts[0] * 1000000 + $parts[1] * 1000 + $parts[2])
        Suite = $suite
        Texte = $Brut
    }
}
function Test-PlusRecente {
    param($Candidate, $Actuelle)
    # A doubt does not block: better to offer one update too many than to miss one.
    if (-not $Candidate) { return $true }
    if (-not $Actuelle)  { return $true }
    if ($Candidate.Cle -ne $Actuelle.Cle) { return ($Candidate.Cle -gt $Actuelle.Cle) }
    return ($Candidate.Suite -gt $Actuelle.Suite)
}

# --- What is running here -----------------------------------------------------
$marque = $null
try { $marque = Get-BuildStamp -Root $repoRoot } catch { }
$enPlace = $null
if ($marque -and $marque.version) { $enPlace = ConvertTo-Reperage -Brut $marque.version }
Write-Info (Get-Label 'vigie-fetch.version-en-place' $(if ($marque -and $marque.version) { $marque.version } else { 'inconnue' }))
# --- Quelle voie ? -------------------------------------------------------------------
$isRepository = $false
try {
    $isRepository = (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) -and
                [bool](Get-Command git -ErrorAction SilentlyContinue)
} catch { }

$route = $Source
if ($route -eq 'auto') {
    if ($Ref)          { $route = 'clone' }
    elseif ($isRepository) { $route = 'local' }
    else               { $route = 'release' }
}
if ($Ref -and $route -ne 'clone') {
    Sortir 1 ("-Ref impose la voie « clone » : « " + $route + " » ne sait pas viser une reference precise.")
}
if ($route -eq 'local' -and -not $isRepository) {
    Sortir 1 "Voie « local » demandee, mais ce dossier n'est pas un depot git utilisable. La voie -Source release reste possible."
}
Write-Info (Get-Label 'vigie-fetch.voie-retenue' $route)
# --- A working folder of our own ----------------------------------------------
$travail = $null
try {
    $travail = Join-Path (Get-VarRoot -Backend $backend) 'update'
    if (-not (Test-Path -LiteralPath $travail)) {
        New-Item -ItemType Directory -Path $travail -Force | Out-Null
    }
} catch {
    Sortir 1 ("Impossible de preparer le dossier de travail : " + $_.Exception.Message)
}

# --- Checking an archive BEFORE using it --------------------------------------
#
# A download that was cut leaves a file of normal appearance but unreadable. We open it for real, and look at
# whether it has the shape of a Vigie.
function Test-Archive {
    param([string]$ArchivePath)
    if (-not $ArchivePath -or -not (Test-Path -LiteralPath $ArchivePath)) { return "l'archive n'existe pas" }
    $size = (Get-Item -LiteralPath $ArchivePath).Length
    if ($size -lt 100KB) { return ("l'archive ne fait que " + [int]($size / 1KB) + " Ko : elle est tronquee") }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
        try {
            $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
            if (-not ($entryNames | Where-Object { $_ -match '(^|/)setup\.cmd$' })) {
                return "l'archive ne contient pas setup.cmd : ce n'est pas une archive de Vigie"
            }
            if (-not ($entryNames | Where-Object { $_ -match '(^|/)apps/backend-pode/server\.ps1$' })) {
                return "l'archive ne contient pas le serveur : elle est incomplete"
            }
        } finally { $zip.Dispose() }
    } catch {
        return ("l'archive ne s'ouvre pas : " + $_.Exception.Message)
    }
    return $null
}

function Get-DerniereArchive {
    param([string]$Folder)
    $zip = @(Get-ChildItem -Path $Folder -Filter 'vigie-*.zip' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($zip.Count) { return $zip[0].FullName }
    return $null
}

# --- ROAD 1: the local repository ---------------------------------------------
function Get-DepuisLocal {
    $build = Join-Path $PSScriptRoot 'build-release.ps1'
    if (-not (Test-Path -LiteralPath $build)) {
        Sortir 1 "build-release.ps1 introuvable : impossible de fabriquer depuis ce depot."
    }
    Write-Info (Get-Label 'vigie-fetch.fabrication-de-archive-depuis')
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $build | Write-Host
    if ($LASTEXITCODE -ne 0) { Sortir 1 ("La fabrication a echoue (code " + $LASTEXITCODE + ").") }
    $zip = Get-DerniereArchive -Folder (Join-Path $repoRoot 'dist')
    if (-not $zip) { Sortir 1 "La fabrication n'a laisse aucune archive dans dist/." }
    return $zip
}

# --- ROAD 2: the latest published version -------------------------------------
function Get-DepuisRelease {
    $entetes = @{ 'User-Agent' = 'Vigie'; 'Accept' = 'application/vnd.github+json' }
    $base    = 'https://api.github.com/repos/' + $ApiRepo + '/releases'
    $url     = if ($PreVersions) { $base + '?per_page=10' } else { $base + '/latest' }

    $rep = $null
    try {
        $rep = Invoke-RestMethod -Uri $url -Headers $entetes -TimeoutSec 20 -ErrorAction Stop
    } catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if ($code -eq 404) {
            if ($PreVersions) { Sortir 4 "Aucune version n'est publiee sur GitHub, meme en pre-version." }
            Sortir 4 "Aucune version STABLE n'est publiee. S'il n'existe que des pre-versions, relancez avec -PreVersions."
        }
        if ($code -eq 403 -or $code -eq 429) {
            Sortir 2 "GitHub refuse de repondre : quota d'appels atteint, ou acces bloque. Nouvel essai possible dans une heure."
        }
        Sortir 2 ("GitHub n'a pas repondu : " + $_.Exception.Message)
    }

    $liste = @($rep)
    if ($PreVersions) {
        $liste = @($liste | Where-Object { -not $_.draft } | Select-Object -First 1)
        if (-not $liste.Count) { Sortir 4 "Aucune version publiee (hors brouillons)." }
    }
    $v = $liste[0]
    if (-not $v) { Sortir 4 "GitHub a repondu, mais sans aucune version exploitable." }
    $etiquette = "$($v.tag_name)"
    Write-Info (Get-Label 'vigie-fetch.derniere-version-publiee' $etiquette $(if ($v.prerelease) { "  (pre-version)" } else { "" }))
    if (-not $Force -and -not (Test-PlusRecente -Candidate (ConvertTo-Reperage -Brut $etiquette) -Actuelle $enPlace)) {
        Sortir 3 ("Deja a jour : la version publiee (" + $etiquette + ") n'est pas plus recente que celle en place. Rien n'a ete touche.")
    }

    $actifs = @($v.assets | Where-Object { "$($_.name)" -like '*.zip' })
    if (-not $actifs.Count) {
        Sortir 4 ("La version " + $etiquette + " ne contient aucune archive .zip : rien a telecharger.")
    }
    $actif = $actifs[0]
    $target = Join-Path $travail ("$($actif.name)")
    $tmp   = $target + '.partiel'
    Write-Info (Get-Label 'vigie-fetch.telechargement-de-ko' $actif.name [int]($actif.size / 1KB))
    try {
        # A temporary file then a rename: a cut does not leave a half-written archive carrying the right name.
        $previousProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'   # sinon PowerShell passe son temps a redessiner
        try {
            Invoke-WebRequest -Uri $actif.browser_download_url -OutFile $tmp `
                              -Headers @{ 'User-Agent' = 'Vigie' } -TimeoutSec 300 -ErrorAction Stop
        } finally { $ProgressPreference = $previousProgress }
        Move-Item -LiteralPath $tmp -Destination $target -Force
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Sortir 2 ("Le telechargement a echoue : " + $_.Exception.Message)
    }
    return $target
}

# --- ROAD 3: a clone of our own -----------------------------------------------
function Get-DepuisClone {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Sortir 1 "git est introuvable : la voie « clone » en a besoin. Il s'installe par winget install --id Git.Git --scope machine ; la voie -Source release reste possible."
    }
    # The clone's path and the address it synchronises from live in common.ps1: the server needs them TOO, in
    # order to compare the installation with what the button would build (D112). Two definitions, and the card
    # compares with something else.
    $clone  = Get-ServiceClonePath -Backend $backend
    # THE CLONE IS NEVER BLOCKED: forced, then recloned if git still refuses (Update-ServiceClone, common.ps1).
    Write-Info (Get-Label 'vigie-fetch.mise-jour-du-clone')
    $update = Update-ServiceClone -Backend $backend -RemoteUrl $RemoteUrl
    if ($update.recloned) { Write-Info (Get-Label 'vigie-fetch.clone-recree') }
    # git's own words, never a guessed cause: "unreachable repository" hid a refused tag on 13/09.
    if (-not $update.ok) { Sortir 2 ("La recuperation a echoue : " + $update.error) }
    # Without a forced reference, we take tags ONLY: a branch moves at every commit, a tag designates a version
    # somebody decided to publish (D99).
    #
    # EXCEPT FROM A LOCAL REPOSITORY. There, that is precisely what one wants: in dev, one wants to test the dev
    # work locally -- and there is no tag at every fix. So we follow the remote's default branch. Work in progress
    # is deployable only on the workstation that writes it, which is exactly what development mode means.
    $localRemote = $false
    try { $localRemote = (Test-Path -LiteralPath (Join-Path $RemoteUrl '.git')) } catch { }
    $target = $Ref
    if (-not $target -and $localRemote) {
        $target = (& git -C $clone rev-parse --abbrev-ref origin/HEAD 2>$null | Select-Object -First 1)
        if (-not $target) { $target = 'origin/main' }
        Write-Info (Get-Label 'vigie-fetch.branche-du-depot-local' $target)
    }
    if (-not $target) {
        $target = (& git -C $clone describe --tags --abbrev=0 2>$null | Select-Object -First 1)
        if (-not $target) { Sortir 4 "Aucun tag dans ce depot : rien a deployer. -Ref vise une branche." }
        $target = "$target".Trim()
        Write-Info (Get-Label 'vigie-fetch.dernier-tag' $target)
        if (-not $Force -and -not (Test-PlusRecente -Candidate (ConvertTo-Reperage -Brut $target) -Actuelle $enPlace)) {
            Sortir 3 ("Deja a jour : le dernier tag (" + $target + ") n'est pas plus recent que la version en place. Rien n'a ete touche.")
        }
    }

    & git -C $clone rev-parse --verify --quiet ($target + '^{commit}') 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Perhaps a remote branch that was never brought out locally.
        & git -C $clone rev-parse --verify --quiet ('origin/' + $target + '^{commit}') 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Sortir 4 ("Reference introuvable dans le depot : " + $target) }
        $target = 'origin/' + $target
    }
    & git -C $clone -c advice.detachedHead=false checkout --quiet --force $target 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { Sortir 4 ("Impossible de se placer sur " + $target + ".") }
    Write-Info (Get-Label 'vigie-fetch.place-sur' $target (& git -C $clone rev-parse --short HEAD))
    $build = Join-Path (Join-Path $clone 'scripts') 'build-release.ps1'
    if (-not (Test-Path -LiteralPath $build)) {
        Sortir 5 "Ce depot ne contient pas scripts/build-release.ps1 : rien a fabriquer."
    }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $build | Write-Host
    if ($LASTEXITCODE -ne 0) { Sortir 5 ("La fabrication depuis le clone a echoue (code " + $LASTEXITCODE + ").") }
    $zip = Get-DerniereArchive -Folder (Join-Path $clone 'dist')
    if (-not $zip) { Sortir 5 "La fabrication depuis le clone n'a laisse aucune archive." }
    return $zip
}

# --- Execution -----------------------------------------------------------------------
$archive = switch ($route) {
    'local'   { Get-DepuisLocal }
    'release' { Get-DepuisRelease }
    'clone'   { Get-DepuisClone }
    default   { Sortir 1 ("Voie inconnue : " + $route) }
}

$souci = Test-Archive -ArchivePath $archive
if ($souci) { Sortir 5 ("Archive inexploitable : " + $souci + ". Rien n'a ete deploye.") }

Write-Ok (Get-Label 'vigie-fetch.archive-prete' $archive)
Noter ("archive prete (" + $route + ") : " + $archive)
# THE LAST LINE = the path. The caller reads only that one.
Write-Output $archive
exit 0
