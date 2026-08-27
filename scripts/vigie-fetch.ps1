<#
    vigie-fetch.ps1 - Rapporte une archive de Vigie, prete a etre deployee. NE DEPLOIE RIEN.

    Ce script ne fait qu'une chose : obtenir un `.zip` verifie et en ecrire le chemin sur la derniere ligne de sa
    sortie. C'est `vigie-update.ps1` qui le deploie ensuite. Separer les deux evite le pire des cas : une
    recuperation a moitie faite qui ecrase une installation qui marchait.

    TROIS VOIES, et une regle pour choisir quand on ne le dit pas (-Source auto) :
      - `local`   : le depot est la (poste de developpement) -> on fabrique depuis lui.
      - `release` : sinon -> on telecharge la derniere version publiee sur GitHub.
      - `clone`   : des qu'on force une reference (-Ref), parce qu'une branche ou un commit precis n'existe pas
                    sous forme de release.

    RESEAU. C'est le seul endroit ou Vigie va chercher du CODE a l'exterieur, et jamais de sa propre initiative :
    il faut qu'on le lui demande. Ce qui est telecharge vient du depot officiel en HTTPS ; il n'y a pas de
    signature a verifier, et on ne pretend pas le contraire. Ce qu'on verifie, en revanche : que l'archive
    s'ouvre, qu'elle a la forme attendue, et qu'elle n'est pas plus ancienne que ce qui tourne deja.

    Codes de retour, tous distincts pour que l'appelant sache QUOI dire :
      0 = archive prete (son chemin est la derniere ligne)
      1 = prerequis manquant (git absent, dossier illisible...)
      2 = le reseau ou GitHub n'a pas repondu
      3 = deja a jour : rien a faire, et ce n'est pas une erreur (D77)
      4 = la reference demandee n'existe pas
      5 = ce qui a ete rapporte n'est pas exploitable (archive illisible ou tronquee)
#>
param(
    [ValidateSet('auto', 'local', 'release', 'clone')]
    [string] $Source = 'auto',

    # Branche, tag ou commit. Le preciser force la voie `clone`.
    [string] $Ref,

    # Accepter les pre-versions. GitHub EXCLUT les pre-versions de /releases/latest : sans
    # ce commutateur, une machine ne verra que les versions stables. C'est voulu.
    [switch] $PreVersions,

    # Rapporter meme si la version trouvee n'est pas plus recente que celle en place.
    [switch] $Force,

    [string] $Depot   = 'https://github.com/Cartman34/vigie-windows.git',
    [string] $ApiRepo = 'Cartman34/vigie-windows'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'

function Dire  { param([string]$T, [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }
function Noter {
    param([string]$T, [string]$N = 'INFO')
    try { Write-Log -Backend $backend -Name 'update' -Level $N -Message $T } catch { }
}
function Sortir {
    param([int]$Code, [string]$Message, [string]$Couleur = 'Red')
    Dire $Message $Couleur
    Noter $Message $(if ($Code -eq 0 -or $Code -eq 3) { 'INFO' } else { 'ERROR' })
    exit $Code
}

# --- Comparer deux versions ---------------------------------------------------------
#
# « v0.1.9 », « 0.1.9 » et « v0.1.9+3 » doivent se comparer entre eux. Le suffixe « +N »
# compte les commits depuis le tag : il rend la version PLUS recente, pas moins.
function ConvertTo-Reperage {
    param([string]$Brut)
    if (-not $Brut) { return $null }
    $t = "$Brut".Trim().TrimStart('v', 'V')
    $suite = 0
    if ($t -match '^(.*)\+(\d+)$') { $t = $Matches[1]; $suite = [int]$Matches[2] }
    $morceaux = @($t -split '[.\-]' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    if (-not $morceaux.Count) { return $null }
    while ($morceaux.Count -lt 3) { $morceaux += 0 }
    [pscustomobject]@{
        Cle   = ($morceaux[0] * 1000000 + $morceaux[1] * 1000 + $morceaux[2])
        Suite = $suite
        Texte = $Brut
    }
}
function Test-PlusRecente {
    param($Candidate, $Actuelle)
    # Un doute ne bloque pas : mieux vaut proposer une mise a jour de trop qu'en rater une.
    if (-not $Candidate) { return $true }
    if (-not $Actuelle)  { return $true }
    if ($Candidate.Cle -ne $Actuelle.Cle) { return ($Candidate.Cle -gt $Actuelle.Cle) }
    return ($Candidate.Suite -gt $Actuelle.Suite)
}

# --- Ce qui tourne ici ---------------------------------------------------------------
$marque = $null
try { $marque = Get-BuildStamp -Root $repoRoot } catch { }
$enPlace = $null
if ($marque -and $marque.version) { $enPlace = ConvertTo-Reperage -Brut $marque.version }
Dire ("Version en place : " + $(if ($marque -and $marque.version) { $marque.version } else { 'inconnue' }))

# --- Quelle voie ? -------------------------------------------------------------------
$estDepot = $false
try {
    $estDepot = (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) -and
                [bool](Get-Command git -ErrorAction SilentlyContinue)
} catch { }

$voie = $Source
if ($voie -eq 'auto') {
    if ($Ref)          { $voie = 'clone' }
    elseif ($estDepot) { $voie = 'local' }
    else               { $voie = 'release' }
}
if ($Ref -and $voie -ne 'clone') {
    Sortir 1 ("-Ref impose la voie « clone » : « " + $voie + " » ne sait pas viser une reference precise.")
}
if ($voie -eq 'local' -and -not $estDepot) {
    Sortir 1 "Voie « local » demandee, mais ce dossier n'est pas un depot git utilisable. Essayez -Source release."
}
Dire ("Voie retenue : " + $voie)

# --- Un dossier de travail a nous ----------------------------------------------------
$travail = $null
try {
    $travail = Join-Path (Get-VarRoot -Backend $backend) 'update'
    if (-not (Test-Path -LiteralPath $travail)) {
        New-Item -ItemType Directory -Path $travail -Force | Out-Null
    }
} catch {
    Sortir 1 ("Impossible de preparer le dossier de travail : " + $_.Exception.Message)
}

# --- Verifier une archive AVANT de s'en servir ---------------------------------------
#
# Un telechargement coupe laisse un fichier d'allure normale mais illisible. On l'ouvre
# pour de vrai, et on regarde s'il a la forme d'une Vigie.
function Test-Archive {
    param([string]$Chemin)
    if (-not $Chemin -or -not (Test-Path -LiteralPath $Chemin)) { return "l'archive n'existe pas" }
    $taille = (Get-Item -LiteralPath $Chemin).Length
    if ($taille -lt 100KB) { return ("l'archive ne fait que " + [int]($taille / 1KB) + " Ko : elle est tronquee") }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [IO.Compression.ZipFile]::OpenRead($Chemin)
        try {
            $noms = @($zip.Entries | ForEach-Object { $_.FullName })
            if (-not ($noms | Where-Object { $_ -match '(^|/)setup\.cmd$' })) {
                return "l'archive ne contient pas setup.cmd : ce n'est pas une archive de Vigie"
            }
            if (-not ($noms | Where-Object { $_ -match '(^|/)apps/backend-pode/server\.ps1$' })) {
                return "l'archive ne contient pas le serveur : elle est incomplete"
            }
        } finally { $zip.Dispose() }
    } catch {
        return ("l'archive ne s'ouvre pas : " + $_.Exception.Message)
    }
    return $null
}

function Get-DerniereArchive {
    param([string]$Dossier)
    $zip = @(Get-ChildItem -Path $Dossier -Filter 'vigie-*.zip' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($zip.Count) { return $zip[0].FullName }
    return $null
}

# --- VOIE 1 : le depot local ---------------------------------------------------------
function Get-DepuisLocal {
    $build = Join-Path $PSScriptRoot 'build-release.ps1'
    if (-not (Test-Path -LiteralPath $build)) {
        Sortir 1 "build-release.ps1 introuvable : impossible de fabriquer depuis ce depot."
    }
    Dire "Fabrication de l'archive depuis le depot local..."
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $build | Write-Host
    if ($LASTEXITCODE -ne 0) { Sortir 1 ("La fabrication a echoue (code " + $LASTEXITCODE + ").") }
    $zip = Get-DerniereArchive -Dossier (Join-Path $repoRoot 'dist')
    if (-not $zip) { Sortir 1 "La fabrication n'a laisse aucune archive dans dist/." }
    return $zip
}

# --- VOIE 2 : la derniere version publiee --------------------------------------------
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
            Sortir 2 "GitHub refuse de repondre : quota d'appels atteint, ou acces bloque. Reessayez dans une heure."
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
    Dire ("Derniere version publiee : " + $etiquette + $(if ($v.prerelease) { "  (pre-version)" } else { "" }))

    if (-not $Force -and -not (Test-PlusRecente -Candidate (ConvertTo-Reperage -Brut $etiquette) -Actuelle $enPlace)) {
        Sortir 3 ("Deja a jour : la version publiee (" + $etiquette + ") n'est pas plus recente que celle en place. Rien n'a ete touche.") 'Green'
    }

    $actifs = @($v.assets | Where-Object { "$($_.name)" -like '*.zip' })
    if (-not $actifs.Count) {
        Sortir 4 ("La version " + $etiquette + " ne contient aucune archive .zip : rien a telecharger.")
    }
    $actif = $actifs[0]
    $cible = Join-Path $travail ("$($actif.name)")
    $tmp   = $cible + '.partiel'
    Dire ("Telechargement de " + $actif.name + " (" + [int]($actif.size / 1KB) + " Ko)...")
    try {
        # Fichier temporaire puis renommage : une coupure ne laisse pas une archive a
        # moitie ecrite portant le nom de la bonne.
        $avantProgression = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'   # sinon PowerShell passe son temps a redessiner
        try {
            Invoke-WebRequest -Uri $actif.browser_download_url -OutFile $tmp `
                              -Headers @{ 'User-Agent' = 'Vigie' } -TimeoutSec 300 -ErrorAction Stop
        } finally { $ProgressPreference = $avantProgression }
        Move-Item -LiteralPath $tmp -Destination $cible -Force
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Sortir 2 ("Le telechargement a echoue : " + $_.Exception.Message)
    }
    return $cible
}

# --- VOIE 3 : un clone a nous --------------------------------------------------------
function Get-DepuisClone {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Sortir 1 "git est introuvable : la voie « clone » en a besoin. Installez-le (winget install --id Git.Git --scope machine), ou passez par -Source release."
    }
    $clone  = Join-Path $travail 'depot'
    $valide = $false
    if (Test-Path -LiteralPath (Join-Path $clone '.git')) {
        & git -C $clone rev-parse --git-dir 2>$null | Out-Null
        $valide = ($LASTEXITCODE -eq 0)
        if (-not $valide) {
            Dire "Le clone existant est abime : il est refait de zero." 'Yellow'
            Remove-Item -LiteralPath $clone -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if ($valide) {
        Dire "Mise a jour du clone..."
        & git -C $clone fetch --quiet --tags --prune origin 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) { Sortir 2 "La recuperation a echoue : depot injoignable, ou reseau absent." }
    } else {
        Dire ("Clonage de " + $Depot + " ...")
        & git clone --quiet $Depot $clone 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) { Sortir 2 "Le clonage a echoue : depot injoignable, ou reseau absent." }
    }

    # Sans reference imposee, on ne prend QUE des tags : une branche bouge a chaque
    # commit, un tag designe une version qu'on a decide de publier.
    $cible = $Ref
    if (-not $cible) {
        $cible = (& git -C $clone describe --tags --abbrev=0 2>$null | Select-Object -First 1)
        if (-not $cible) { Sortir 4 "Aucun tag dans ce depot : rien a deployer. Precisez -Ref pour viser une branche." }
        $cible = "$cible".Trim()
        Dire ("Dernier tag : " + $cible)
        if (-not $Force -and -not (Test-PlusRecente -Candidate (ConvertTo-Reperage -Brut $cible) -Actuelle $enPlace)) {
            Sortir 3 ("Deja a jour : le dernier tag (" + $cible + ") n'est pas plus recent que la version en place. Rien n'a ete touche.") 'Green'
        }
    }

    & git -C $clone rev-parse --verify --quiet ($cible + '^{commit}') 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Peut-etre une branche distante jamais sortie en local.
        & git -C $clone rev-parse --verify --quiet ('origin/' + $cible + '^{commit}') 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Sortir 4 ("Reference introuvable dans le depot : " + $cible) }
        $cible = 'origin/' + $cible
    }
    & git -C $clone -c advice.detachedHead=false checkout --quiet --force $cible 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { Sortir 4 ("Impossible de se placer sur " + $cible + ".") }
    Dire ("Place sur " + $cible + " (" + (& git -C $clone rev-parse --short HEAD) + ")")

    $build = Join-Path (Join-Path $clone 'scripts') 'build-release.ps1'
    if (-not (Test-Path -LiteralPath $build)) {
        Sortir 5 "Ce depot ne contient pas scripts/build-release.ps1 : rien a fabriquer."
    }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $build | Write-Host
    if ($LASTEXITCODE -ne 0) { Sortir 5 ("La fabrication depuis le clone a echoue (code " + $LASTEXITCODE + ").") }
    $zip = Get-DerniereArchive -Dossier (Join-Path $clone 'dist')
    if (-not $zip) { Sortir 5 "La fabrication depuis le clone n'a laisse aucune archive." }
    return $zip
}

# --- Execution -----------------------------------------------------------------------
$archive = switch ($voie) {
    'local'   { Get-DepuisLocal }
    'release' { Get-DepuisRelease }
    'clone'   { Get-DepuisClone }
    default   { Sortir 1 ("Voie inconnue : " + $voie) }
}

$souci = Test-Archive -Chemin $archive
if ($souci) { Sortir 5 ("Archive inexploitable : " + $souci + ". Rien n'a ete deploye.") }

Dire ("Archive prete : " + $archive) 'Green'
Noter ("archive prete (" + $voie + ") : " + $archive)
# DERNIERE LIGNE = le chemin. L'appelant ne lit que celle-la.
Write-Output $archive
exit 0
