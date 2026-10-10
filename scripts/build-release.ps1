# @author Florent HAZARD <f.hazard@sowapps.com>
<#
.SYNOPSIS
    Builds Vigie's distribution archive, the one attached to a GitHub Release.

.DESCRIPTION
    Intent: make an archive one can publish without rereading it. What leaves must be exactly what is tracked and
    meant for a user -- never a secret, never a working file -- and the script proves it rather than promising it.

    It produces dist/vigie-<version>.zip. The version comes from the last git TAG (or from -Version) and from
    NOWHERE else (D15); the file carries the bare number only, the "v" prefix staying a display detail that does
    not enter the archive's name.

    THE LIST OF FILES COMES FROM GIT, NOT FROM THE DISC.
    That is this script's central design choice. Walking the file system would mean guessing again everything
    .gitignore already knows, and the slightest oversight would send a secret into a public archive. `git
    ls-files` knows only TRACKED files: the API token (apps/*/var/secrets/), the cache, the logs, the
    config.local.psd1 files and the *.bak-* ones are ignored by git, so they are structurally absent from the
    list. One cannot forget to exclude what was never offered.

    On top of that, a list of exclusions takes out what IS versioned but has no business on a user's machine (see
    $EXCLUSIONS: every rule carries its reason).

    Finally, a GUARD checks twice that no forbidden path gets through: once on the list that was kept, once on the
    real contents of the archive produced. The script refuses to write, or deletes what it has just written,
    rather than delivering a doubt.

    IDEMPOTENT: running it again has no side effect, the previous archive is replaced.

.PARAMETER OutDir
    The output folder. Default: dist/ at the root of the repository (ignored by git).

.PARAMETER KeepStaging
    Keeps the staging folder so the tree can be inspected by eye.

.PARAMETER ListOnly
    Writes nothing: only displays what would be included. Useful for settling an exclusion.

.EXAMPLE
    pwsh -File .\scripts\build-release.ps1

.EXAMPLE
    pwsh -File .\scripts\build-release.ps1 -ListOnly

.NOTES
    Exit codes:
      0 = the archive was produced (or the list displayed with -ListOnly)
      1 = a missing prerequisite (git absent, outside a git repository)
      2 = THE GUARD: a forbidden path was detected, no archive is left behind
      3 = the build failed (a copy, the compression, or an inconsistent count)
#>
[CmdletBinding()]
param(
    [string] $OutDir,
    # The number to engrave into the archive. Absent: the one of the last TAG. The deployment, for its part,
    # passes the TAG it has just laid down: the archive and the tag then say exactly the same thing.
    [string] $Version,
    [switch] $KeepStaging,
    [switch] $ListOnly
)

$ErrorActionPreference = 'Stop'

# The management scripts live in scripts/: the root of the repository is the parent folder.
$repoRoot = Split-Path $PSScriptRoot -Parent
# The version stamp (number plus commit) has ONE single definition, in common.ps1: the building and the reading
# must agree, otherwise the archive says one thing and the installation understands another.
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

# ---------------------------------------------------------------------------------------
# What IS VERSIONED but does NOT go to the user.
#
# The patterns apply to the path RELATIVE to the root of the repository, with forward slashes (the form git
# returns). Every rule carries its reason: an exclusion with no written reason always ends up being removed
# "because nobody knows why it is there any more".
# ---------------------------------------------------------------------------------------
$EXCLUSIONS = @(
    @{ Motif = '^\.github/'
       Raison = "Chaîne de publication. Elle fabrique l'archive, elle n'a rien à y faire." }

    @{ Motif = '^\.claude/'
       Raison = "Réglages de l'agent de développement (D40). Sans objet hors du dépôt." }

    @{ Motif = '^\.gitignore$'
       Raison = "Règles de versionnement. Une archive n'est pas un dépôt git." }

    @{ Motif = '^apps/atelier/'
       Raison = "Outil de DÉVELOPPEMENT (PHP, port 47610, D28). Jamais livré à un utilisateur : inutile sans les sources, et ce serait un serveur de plus sur sa machine." }

    @{ Motif = '^apps/client/assets/generate-icons\.py$'
       Raison = "Générateur des icônes : outil de développement, exige Python. Les .ico qu'il produit sont livrés, lui non." }

    @{ Motif = '^scripts/hooks/'
       Raison = "Hooks git. Sans .git/, ils n'ont aucun point d'accroche." }

    @{ Motif = '^scripts/install-hooks\.ps1$'
       Raison = "Installe les hooks git ci-dessus. Même raison." }

    @{ Motif = '^scripts/build-release\.ps1$'
       Raison = "Ce script. Il exige git et le dépôt complet : inutilisable depuis l'archive qu'il produit." }

    @{ Motif = '^scripts/uninstall-legacy\.ps1$'
       Raison = "Nettoyage DATÉ et JETABLE des postes antérieurs au renommage Vigie (D11). Il ne concerne que des machines déjà installées, jamais une installation neuve." }

    @{ Motif = '^scripts/dev/'
       Raison = "Outillage du developpeur : controle de la documentation, installation des dependances de dev, page de charge GPU. Sans objet pour qui utilise Vigie, et ces scripts s'appuient sur des documents internes qui ne partent pas non plus." }

    @{ Motif = '^doc/progress/'
       Raison = "Suivi du projet : ce qu'on vise, ce qui est fait, les décisions prises. Utile à qui code, pas à qui utilise." }

    @{ Motif = '^doc/archives/'
       Raison = "Ce qui est révolu, gardé pour la trace : historiques de conception, migration terminée, maquettes validées." }

    @{ Motif = '^doc/en/agent-working/'
       Raison = "Briefing et disciplines de l'agent qui travaille sur le dépôt. Sans objet pour qui utilise Vigie." }

    @{ Motif = '^doc/en/developing/security-review\.md$'
       Raison = "Revue de sécurité INTERNE, à relire à chaque ajout d'action. La page publique équivalente est doc/*/security.md." }

    @{ Motif = '^doc/en/developing/debugging\.md$'
       Raison = "Démarche de débogage : elle s'exécute avec scripts/dev/, qui ne part pas. Livrée seule, elle ne renvoie qu'à des fichiers absents." }

    @{ Motif = '^doc/README\.md$'
       Raison = "Aiguillage du dépôt : il ne pointe QUE vers les documents internes ci-dessus. Dans l'archive, README.md mène directement à doc/en/ et doc/fr/." }
)

# ---------------------------------------------------------------------------------------
# THE GUARD. What must NEVER end up in a public archive, whatever happens upstream. It is a second barrier,
# redundant with .gitignore: it exists precisely for the day somebody versions one of those files by mistake.
# Any match stops the script (code 2) instead of producing a doubtful archive.
# ---------------------------------------------------------------------------------------
$INTERDITS = @(
    @{ Motif = '(^|/)var/';              Quoi = "données d'exécution (cache, journaux, secrets)" }
    @{ Motif = '(^|/)secrets?/';         Quoi = "dossier de secrets" }
    @{ Motif = 'config\.local\.psd1$';   Quoi = "configuration propre à une machine" }
    @{ Motif = '\.token$';               Quoi = "jeton" }
    @{ Motif = '(^|/)\.git/';            Quoi = "métadonnées git" }
    @{ Motif = '(^|/)\.bak-';            Quoi = "sauvegarde d'édition" }
    @{ Motif = '\.log$';                 Quoi = "journal" }
)

function Format-Size {
    param([long] $Octets)
    if ($Octets -ge 1MB) { return ('{0:N1} Mo' -f ($Octets / 1MB)) }
    if ($Octets -ge 1KB) { return ('{0:N0} Ko' -f ($Octets / 1KB)) }
    "$Octets o"
}

# The relative links of the .md files we keep that no longer resolve ONCE INSIDE THE ARCHIVE.
#
# Excluding a file breaks every link that aimed at it: the documentation delivered ends up with dead links, with
# nothing to report it. The remedy is to write those links as absolute GitHub URLs (they then work on both sides);
# this check is here so that the oversight shows up when the archive is built, not on the user's machine.
function Find-LienMort {
    param([Parameter(Mandatory)][string] $Root)
    $morts = @()
    foreach ($md in (Get-ChildItem -LiteralPath $Root -Recurse -Filter *.md -File)) {
        # AN EMPTY FILE RETURNS $null, NOT AN EMPTY STRING. Matches then throws "Value cannot be null", and the
        # whole build stops on a document without a single line (observed on 01/09: v0.1.44 was never built).
        $text = Get-Content -LiteralPath $md.FullName -Raw
        if (-not $text) { continue }
        foreach ($m in [regex]::Matches($text, '\]\(([^)]+)\)')) {
            $lien = $m.Groups[1].Value
            if ($lien -match '^(https?:|mailto:|#)') { continue }
            $path = ($lien -split '#')[0]
            if (-not $path) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $md.DirectoryName $path))) {
                $morts += [pscustomobject]@{
                    Fichier = $md.FullName.Substring($Root.Length).TrimStart('\', '/')
                    Lien    = $lien
                }
            }
        }
    }
    $morts
}

# Returns the list of forbidden matches found in the paths given.
function Find-ForbiddenPath {
    param([string[]] $Paths)
    $trouves = @()
    foreach ($c in $Paths) {
        foreach ($i in $INTERDITS) {
            if ($c -match $i.Motif) { $trouves += [pscustomobject]@{ Chemin = $c; Quoi = $i.Quoi } }
        }
    }
    $trouves
}

# --- Prerequis -------------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn (Get-Label 'build-release.git-est-introuvable-ce')
    exit 1
}

# The "v" prefix is display dressing: it does not go into a file name, otherwise it would have to be stripped
# everywhere else. The number comes from the TAG (through Get-BuildStamp), or from -Version when the deployment
# has just laid one down. No more VERSION file to keep up to date (D96).
$number = if ($Version) { $Version -replace '^v', '' } else { (Get-BuildStamp -Root $repoRoot).version -replace '^v', '' }
if (-not $number -or $number -eq 'sans version') { $number = '0.1' }
# A "+" in a file name is legal but awkward: v0.1.6+6 becomes 0.1.6-dev6 in the ARCHIVE NAME, and there only. The
# stamp keeps "+": written "-dev1" into BUILD on 15/09, one version read two ways -- the installation "v1.1.6-dev1",
# the repository "v1.1.6+1" -- and deploy-status announced a repository ahead of an installation on the same commit.
$fileNumber = $number -replace '\+', '-dev'

# --- The inventory: what git tracks -------------------------------------------
Push-Location $repoRoot
try {
    # -z plus a NUL separator: robust against exotic file names, and it avoids the quoting git applies to
    # non-ASCII characters when its output is line-based.
    $brut = (& git ls-files -z) -join ''
    if ($LASTEXITCODE -ne 0) {
        Write-Warn (Get-Label 'build-release.git-ls-files-echoue')
        exit 1
    }
} finally {
    Pop-Location
}

$suivis = @($brut -split "`0" | Where-Object { $_ })
if ($suivis.Count -eq 0) {
    Write-Warn (Get-Label 'build-release.git-ne-suit-aucun')
    exit 1
}

# --- Tri : retenus / ecartes -----------------------------------------------------------
$retenus = @()
$excluded = @{}   # motif -> nombre de fichiers ecartes
foreach ($f in $suivis) {
    $regle = $EXCLUSIONS | Where-Object { $f -match $_.Motif } | Select-Object -First 1
    if ($regle) {
        if (-not $excluded.ContainsKey($regle.Motif)) { $excluded[$regle.Motif] = 0 }
        $excluded[$regle.Motif]++
        continue
    }
    # A file that is tracked but deleted from the disc (a deletion not committed yet) must not make the build
    # fail: we report it and carry on.
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $f))) {
        Write-Warn (Get-Label 'build-release.absent-du-disque-ignore' $f)
        continue
    }
    $retenus += $f
}

# --- THE GUARD, before anything is written ------------------------------------
$interdits = Find-ForbiddenPath -Paths $retenus
if ($interdits.Count -gt 0) {
    Write-Fail (Get-Label 'build-release.arret-des-fichiers-interdits')
    foreach ($i in $interdits) { Write-Fail ("  " + $i.Chemin + "   <- " + $i.Quoi) }
    Write-Fail (Get-Label 'build-release.rien-ete-ecrit-corrige')
    exit 2
}

# --- A report of what is leaving ----------------------------------------------
$totalSize = 0
$byRoot = @{}
foreach ($f in $retenus) {
    $size = (Get-Item -LiteralPath (Join-Path $repoRoot $f)).Length
    $totalSize += $size
    $Root = if ($f -match '/') { ($f -split '/')[0] + '/' } else { '(racine)' }
    if (-not $byRoot.ContainsKey($Root)) { $byRoot[$Root] = @{ N = 0; Taille = 0 } }
    $byRoot[$Root].N++
    $byRoot[$Root].Taille += $size
}

Write-Step (Get-Label 'build-release.vigie-contenu-de-archive' $number)
Write-Info (Get-Label 'build-release.fichier-avant-compression' $retenus.Count (Format-Size $totalSize))
foreach ($k in ($byRoot.Keys | Sort-Object)) {
    Write-Info (Get-Label 'build-release.18-fichier' $k $byRoot[$k].N (Format-Size $byRoot[$k].Taille))
}

$excludedCount = ($excluded.Values | Measure-Object -Sum).Sum
Write-Detail (Get-Label 'build-release.ecarte-volontairement-fichier-suivi' ([int]$excludedCount))
foreach ($regle in $EXCLUSIONS) {
    if ($excluded.ContainsKey($regle.Motif)) {
        Write-Detail (Get-Label 'build-release.texte' $excluded[$regle.Motif] $regle.Raison)
    }
}
Write-Detail (Get-Label 'build-release.jamais-propose-tout-ce')

if ($ListOnly) {
    foreach ($f in ($retenus | Sort-Object)) { Write-Host ("  " + $f) }
    Write-Step (Get-Label 'build-release.listonly-rien-ete-ecrit')
    exit 0
}

# --- Staging and compression --------------------------------------------------
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'dist' }
$name     = 'vigie-' + $fileNumber
# Files ADDED by the build (so absent from git): the final check expects them on top of the list that was kept.
$genereParLaFabrication = @()

$staging = Join-Path $OutDir $name
$zip     = Join-Path $OutDir ($name + '.zip')

try {
    # Idempotence: we start again from an empty staging folder, otherwise a file taken out of the list would
    # survive from one run to the next.
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    foreach ($f in $retenus) {
        $target = Join-Path $staging ($f -replace '/', [IO.Path]::DirectorySeparatorChar)
        $folder = Split-Path $target -Parent
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $repoRoot $f) -Destination $target -Force
    }

    # Checking the documentation that is delivered, on the staging folder: that is the only moment where the
    # archive's tree really exists on the disc.
    $liensMorts = Find-LienMort -Root $staging
    if ($liensMorts.Count -gt 0) {
        Write-Warn (Get-Label 'build-release.attention-lien-de-la' $liensMorts.Count)
        foreach ($l in $liensMorts) { Write-Warn ("    " + $l.Fichier + " -> " + $l.Lien) }
        Write-Warn (Get-Label 'build-release.ces-cibles-sont-exclues')
    }

    # THE STAMP OF THIS VERSION, laid inside the archive: the number AND the commit (D84).
    # A deployed installation has no git repository; without this file it cannot say what it holds, and there is
    # no way of knowing whether it is up to date. The number alone is not enough: two archives both called
    # "v0.1" can differ by twenty commits.
    $commit = Get-GitCommit -Path $repoRoot
    Write-BuildStamp -Root $staging -Version $(if ($number.StartsWith('v')) { $number } else { "v$number" }) -Commit $commit
    # THIS FILE IS NOT TRACKED BY GIT: it is built here. The final check counts the files in the archive and
    # compares them with the list that was kept -- so it must be told. Without this line, the build stopped on
    # "146 files for 145 expected" and the deployment was abandoned (observed on 27/08: the guard was right, it
    # was the count that was wrong).
    $genereParLaFabrication += 'BUILD'
    Write-Info (Get-Label 'build-release.marque-posee' $number -replace '^v', '' $(if ($commit) { $commit.Substring(0, 8) } else { 'commit inconnu' }))
    # The folder itself is compressed, not its contents: so the archive carries a "vigie-<version>/" root.
    # Without it, unpacking spills everything into the current folder.
    if (Test-Path -LiteralPath $zip) {
        Remove-Item -LiteralPath $zip -Force
        Write-Detail (Get-Label 'build-release.archive-precedente-remplacee' $zip)
    }
    Compress-Archive -Path $staging -DestinationPath $zip -CompressionLevel Optimal
} catch {
    Write-Fail (Get-Label 'build-release.echec-de-la-fabrication' $_.Exception.Message)
    exit 3
}

# --- Checking the REAL contents of the archive --------------------------------
# We do not trust the input list: we read back what was actually written (D43).
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName })
} finally {
    $archive.Dispose()
}

$interditsZip = Find-ForbiddenPath -Paths $entries
if ($interditsZip.Count -gt 0) {
    Write-Fail (Get-Label 'build-release.arret-archive-produite-contient')
    foreach ($i in $interditsZip) { Write-Fail ("  " + $i.Chemin + "   <- " + $i.Quoi) }
    Remove-Item -LiteralPath $zip -Force
    Write-Fail (Get-Label 'build-release.archive-supprimee-rien-de')
    exit 2
}

# Folder entries have no file name: we count only the real files.
$zipFileCount = @($entries | Where-Object { -not $_.EndsWith('/') }).Count
# Expected = what git tracks AND what the build added (the version stamp).
$attendu = $retenus.Count + $genereParLaFabrication.Count
if ($zipFileCount -ne $attendu) {
    Write-Fail (Get-Label 'build-release.arret-fichier-dans-archive' $zipFileCount $attendu $(if ($genereParLaFabrication.Count) { " (" + $retenus.Count + " suivis par git + " + ($genereParLaFabrication -join ', ') + ")" }))
    exit 3
}

if (-not $KeepStaging) { Remove-Item -LiteralPath $staging -Recurse -Force }

$zipSize = (Get-Item -LiteralPath $zip).Length
Write-Ok (Get-Label 'build-release.archive-prete' $zip)
Write-Info (Get-Label 'build-release.fichier-compresses-racine' $zipFileCount (Format-Size $zipSize) $name)
Write-Ok (Get-Label 'build-release.verifie-dans-archive-elle')
if ($KeepStaging) { Write-Detail (Get-Label 'build-release.preparation-conservee' $staging) }
exit 0
