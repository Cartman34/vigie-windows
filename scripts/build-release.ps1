<#
.SYNOPSIS
    Fabrique l'archive de distribution de Vigie, celle qui est attachee a une Release GitHub.

.DESCRIPTION
    Produit dist/vigie-<version>.zip. La version vient du fichier VERSION a la racine et
    de NULLE PART ailleurs (D15) ; le fichier ne porte que le numero nu, le prefixe « v »
    reste un detail d'affichage et n'entre pas dans le nom de l'archive.

    LA LISTE DES FICHIERS VIENT DE GIT, PAS DU DISQUE.
    C'est le choix de conception central de ce script. Parcourir le systeme de fichiers
    obligerait a re-deviner tout ce que .gitignore sait deja, et le moindre oubli ferait
    partir un secret dans une archive publique. `git ls-files` ne connait que les fichiers
    SUIVIS : le jeton d'API (apps/*/var/secrets/), le cache, les journaux, les
    config.local.psd1 et les *.bak-* sont ignores par git, donc structurellement absents
    de la liste. On ne peut pas oublier d'exclure ce qui n'a jamais ete propose.

    Par-dessus, une liste d'exclusions retire ce qui EST versionne mais n'a rien a faire
    chez un utilisateur (voir $EXCLUSIONS : chaque regle porte sa raison).

    Enfin, un GARDE-FOU verifie deux fois qu'aucun chemin interdit ne passe : une fois sur
    la liste retenue, une fois sur le contenu reel de l'archive produite. Le script refuse
    d'ecrire, ou supprime ce qu'il vient d'ecrire, plutot que de livrer un doute.

    IDEMPOTENT : relance sans effet de bord, l'archive precedente est remplacee.

.PARAMETER OutDir
    Dossier de sortie. Defaut : dist/ a la racine du depot (ignore par git).

.PARAMETER KeepStaging
    Conserve le dossier de preparation pour inspecter l'arborescence a l'oeil.

.PARAMETER ListOnly
    N'ecrit rien : affiche seulement ce qui serait inclus. Utile pour trancher une exclusion.

.EXAMPLE
    pwsh -File .\scripts\build-release.ps1

.EXAMPLE
    pwsh -File .\scripts\build-release.ps1 -ListOnly

.NOTES
    Codes de retour :
      0 = archive produite (ou liste affichee avec -ListOnly)
      1 = prerequis manquant (git absent, fichier VERSION absent ou vide, hors depot git)
      2 = GARDE-FOU : un chemin interdit a ete detecte, aucune archive n'est laissee
      3 = echec de fabrication (copie, compression, ou decompte incoherent)
#>
[CmdletBinding()]
param(
    [string] $OutDir,
    # Numero a graver dans l'archive. Absent : celui du fichier VERSION. Le deploiement,
    # lui, passe le TAG qu'il vient de poser (v0.1.3) : l'archive et le tag disent alors
    # exactement la meme chose.
    [string] $Version,
    [switch] $KeepStaging,
    [switch] $ListOnly
)

$ErrorActionPreference = 'Stop'

# Les scripts de gestion vivent dans scripts/ : la racine du depot est le dossier parent.
$repoRoot = Split-Path $PSScriptRoot -Parent
# La marque de version (numero + commit) a UNE seule definition, dans common.ps1 : la
# fabrication et la lecture doivent s'accorder, sinon l'archive dit une chose et
# l'installation en comprend une autre.
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

# ---------------------------------------------------------------------------------------
# Ce qui est VERSIONNE mais ne part PAS chez l'utilisateur.
#
# Motifs appliques au chemin RELATIF a la racine du depot, en slashs avants (forme rendue
# par git). Chaque regle porte sa raison : une exclusion sans motif ecrit finit toujours
# par etre retiree « parce qu'on ne sait plus pourquoi elle est la ».
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

    @{ Motif = '^apps/tray/assets/generate-icons\.py$'
       Raison = "Générateur des icônes : outil de développement, exige Python. Les .ico qu'il produit sont livrés, lui non." }

    @{ Motif = '^scripts/hooks/'
       Raison = "Hooks git. Sans .git/, ils n'ont aucun point d'accroche." }

    @{ Motif = '^scripts/install-hooks\.ps1$'
       Raison = "Installe les hooks git ci-dessus. Même raison." }

    @{ Motif = '^scripts/build-release\.ps1$'
       Raison = "Ce script. Il exige git et le dépôt complet : inutilisable depuis l'archive qu'il produit." }

    @{ Motif = '^scripts/uninstall-legacy\.ps1$'
       Raison = "Nettoyage DATÉ et JETABLE des postes antérieurs au renommage Vigie (D11). Il ne concerne que des machines déjà installées, jamais une installation neuve." }

    @{ Motif = '^(SUIVI|PRISE-EN-MAIN)\.md$'
       Raison = "Documents de travail : journal courant et fiche d'amorçage pour un agent qui reprend le projet." }

    @{ Motif = '^doc/progress/'
       Raison = "Suivi du projet : ce qu'on vise, ce qui est fait, les décisions prises. Utile à qui code, pas à qui utilise." }

    @{ Motif = '^doc/archives/'
       Raison = "Ce qui est révolu, gardé pour la trace : historiques de conception, migration terminée, maquettes validées." }

    @{ Motif = '^doc/en/agent-working/'
       Raison = "Briefing et disciplines de l'agent qui travaille sur le dépôt. Sans objet pour qui utilise Vigie." }

    @{ Motif = '^doc/en/developing/security-review\.md$'
       Raison = "Revue de sécurité INTERNE, à relire à chaque ajout d'action. La page publique équivalente est doc/*/security.md." }

    @{ Motif = '^doc/README\.md$'
       Raison = "Aiguillage du dépôt : il ne pointe QUE vers les documents internes ci-dessus. Dans l'archive, README.md mène directement à doc/en/ et doc/fr/." }
)

# ---------------------------------------------------------------------------------------
# GARDE-FOU. Ce qui ne doit JAMAIS se retrouver dans une archive publique, quoi qu'il
# arrive en amont. C'est une seconde barriere, redondante avec .gitignore : elle existe
# precisement pour le jour ou quelqu'un versionnera par erreur un de ces fichiers.
# Toute correspondance arrete le script (code 2) au lieu de produire une archive douteuse.
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

function Format-Taille {
    param([long] $Octets)
    if ($Octets -ge 1MB) { return ('{0:N1} Mo' -f ($Octets / 1MB)) }
    if ($Octets -ge 1KB) { return ('{0:N0} Ko' -f ($Octets / 1KB)) }
    "$Octets o"
}

# Liens relatifs des .md retenus qui ne resolvent plus UNE FOIS DANS L'ARCHIVE.
#
# Exclure un fichier casse tous les liens qui le visaient : la documentation livree se
# retrouve avec des liens morts, sans que rien ne le signale. Le remede est d'ecrire ces
# liens en URL GitHub absolue (ils marchent alors des deux cotes) ; ce controle est la
# pour que l'oubli se voie au moment de la fabrication, pas chez l'utilisateur.
function Find-LienMort {
    param([Parameter(Mandatory)][string] $Racine)
    $morts = @()
    foreach ($md in (Get-ChildItem -LiteralPath $Racine -Recurse -Filter *.md -File)) {
        $texte = Get-Content -LiteralPath $md.FullName -Raw
        foreach ($m in [regex]::Matches($texte, '\]\(([^)]+)\)')) {
            $lien = $m.Groups[1].Value
            if ($lien -match '^(https?:|mailto:|#)') { continue }
            $chemin = ($lien -split '#')[0]
            if (-not $chemin) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $md.DirectoryName $chemin))) {
                $morts += [pscustomobject]@{
                    Fichier = $md.FullName.Substring($Racine.Length).TrimStart('\', '/')
                    Lien    = $lien
                }
            }
        }
    }
    $morts
}

# Renvoie la liste des correspondances interdites trouvees dans $Chemins.
function Find-CheminInterdit {
    param([string[]] $Chemins)
    $trouves = @()
    foreach ($c in $Chemins) {
        foreach ($i in $INTERDITS) {
            if ($c -match $i.Motif) { $trouves += [pscustomobject]@{ Chemin = $c; Quoi = $i.Quoi } }
        }
    }
    $trouves
}

# --- Prerequis -------------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "git est introuvable. Ce script en a besoin : c'est git qui dit quels fichiers sont suivis, donc lesquels peuvent partir dans l'archive." -ForegroundColor Yellow
    exit 1
}

$versionFile = Join-Path $repoRoot 'VERSION'
if ($false) {
    Write-Host "Fichier VERSION introuvable à la racine du dépôt : $versionFile" -ForegroundColor Yellow
    exit 1
}
# Le numero ne vit qu'ici (D15). Le prefixe « v » est un habillage d'affichage : il ne
# rentre pas dans un nom de fichier, sinon il faudrait le retirer partout ailleurs.
# Le numero vient du TAG (via Get-BuildStamp), ou de -Version quand le deploiement
# vient d'en poser un. Plus de fichier VERSION a tenir a jour (D96).
$version = if ($Version) { $Version -replace '^v', '' } else { (Get-BuildStamp -Root $repoRoot).version -replace '^v', '' }
if (-not $version -or $version -eq 'sans version') { $version = '0.1' }
# Un « + » dans un nom de fichier est legal mais desagreable : v0.1.6+6 devient
# 0.1.6-dev6 dans le nom de l'archive.
$version = $version -replace '\+', '-dev'
if (-not $version) {
    Write-Host "Le fichier VERSION est vide. Le nom de l'archive en dépend." -ForegroundColor Yellow
    exit 1
}

# --- Inventaire : ce que git suit ------------------------------------------------------
Push-Location $repoRoot
try {
    # -z + separateur NUL : robuste aux noms de fichiers exotiques, et evite le quoting
    # que git applique aux caracteres non-ASCII avec la sortie par lignes.
    $brut = (& git ls-files -z) -join ''
    if ($LASTEXITCODE -ne 0) {
        Write-Host "git ls-files a échoué : ce dossier n'est pas un dépôt git utilisable." -ForegroundColor Yellow
        exit 1
    }
} finally {
    Pop-Location
}

$suivis = @($brut -split "`0" | Where-Object { $_ })
if ($suivis.Count -eq 0) {
    Write-Host "git ne suit aucun fichier ici. Rien à empaqueter." -ForegroundColor Yellow
    exit 1
}

# --- Tri : retenus / ecartes -----------------------------------------------------------
$retenus = @()
$ecartes = @{}   # motif -> nombre de fichiers ecartes
foreach ($f in $suivis) {
    $regle = $EXCLUSIONS | Where-Object { $f -match $_.Motif } | Select-Object -First 1
    if ($regle) {
        if (-not $ecartes.ContainsKey($regle.Motif)) { $ecartes[$regle.Motif] = 0 }
        $ecartes[$regle.Motif]++
        continue
    }
    # Un fichier suivi mais supprime du disque (suppression non encore committee) ne doit
    # pas faire echouer la fabrication : on le signale et on continue.
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $f))) {
        Write-Host ("ABSENT du disque, ignoré : " + $f) -ForegroundColor Yellow
        continue
    }
    $retenus += $f
}

# --- GARDE-FOU, avant toute ecriture ---------------------------------------------------
$interdits = Find-CheminInterdit -Chemins $retenus
if ($interdits.Count -gt 0) {
    Write-Host ""
    Write-Host "ARRÊT : des fichiers interdits sont sur le point d'être empaquetés." -ForegroundColor Red
    foreach ($i in $interdits) { Write-Host ("  " + $i.Chemin + "   <- " + $i.Quoi) -ForegroundColor Red }
    Write-Host "Rien n'a été écrit. Corrige le versionnement (.gitignore) avant de recommencer." -ForegroundColor Red
    exit 2
}

# --- Compte rendu de ce qui part --------------------------------------------------------
$tailleTotale = 0
$parRacine = @{}
foreach ($f in $retenus) {
    $taille = (Get-Item -LiteralPath (Join-Path $repoRoot $f)).Length
    $tailleTotale += $taille
    $racine = if ($f -match '/') { ($f -split '/')[0] + '/' } else { '(racine)' }
    if (-not $parRacine.ContainsKey($racine)) { $parRacine[$racine] = @{ N = 0; Taille = 0 } }
    $parRacine[$racine].N++
    $parRacine[$racine].Taille += $taille
}

Write-Host ""
Write-Host ("Vigie " + $version + " — contenu de l'archive") -ForegroundColor Cyan
Write-Host ("  " + $retenus.Count + " fichier(s), " + (Format-Taille $tailleTotale) + " avant compression")
foreach ($k in ($parRacine.Keys | Sort-Object)) {
    Write-Host ("    {0,-18} {1,4} fichier(s)  {2}" -f $k, $parRacine[$k].N, (Format-Taille $parRacine[$k].Taille))
}

$nbEcartes = ($ecartes.Values | Measure-Object -Sum).Sum
Write-Host ""
Write-Host ("Écarté volontairement : " + [int]$nbEcartes + " fichier(s) suivi(s) par git") -ForegroundColor DarkGray
foreach ($regle in $EXCLUSIONS) {
    if ($ecartes.ContainsKey($regle.Motif)) {
        Write-Host ("    {0,4} x  {1}" -f $ecartes[$regle.Motif], $regle.Raison) -ForegroundColor DarkGray
    }
}
Write-Host ""
Write-Host "Jamais proposé : tout ce que .gitignore ignore — jeton d'API, cache, journaux, config.local.psd1, sauvegardes .bak-*." -ForegroundColor DarkGray

if ($ListOnly) {
    Write-Host ""
    foreach ($f in ($retenus | Sort-Object)) { Write-Host ("  " + $f) }
    Write-Host ""
    Write-Host "-ListOnly : rien n'a été écrit." -ForegroundColor Cyan
    exit 0
}

# --- Preparation et compression ---------------------------------------------------------
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'dist' }
$nom     = 'vigie-' + $version
# Fichiers AJOUTES par la fabrication (donc absents de git) : le controle final les
# attend en plus de la liste retenue.
$genereParLaFabrication = @()

$staging = Join-Path $OutDir $nom
$zip     = Join-Path $OutDir ($nom + '.zip')

try {
    # Idempotence : on repart d'une preparation vide, sinon un fichier retire de la liste
    # survivrait d'une execution a l'autre.
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    foreach ($f in $retenus) {
        $cible = Join-Path $staging ($f -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dossier = Split-Path $cible -Parent
        if (-not (Test-Path -LiteralPath $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $repoRoot $f) -Destination $cible -Force
    }

    # Controle de la documentation livree, sur la preparation : c'est le seul moment ou
    # l'arborescence de l'archive existe reellement sur le disque.
    $liensMorts = Find-LienMort -Racine $staging
    if ($liensMorts.Count -gt 0) {
        Write-Host ""
        Write-Host ("ATTENTION : " + $liensMorts.Count + " lien(s) de la documentation ne résolvent pas dans l'archive.") -ForegroundColor Yellow
        foreach ($l in $liensMorts) { Write-Host ("    " + $l.Fichier + " -> " + $l.Lien) -ForegroundColor Yellow }
        Write-Host "    Ces cibles sont exclues de l'archive : écris ces liens en URL GitHub absolue." -ForegroundColor Yellow
    }

    # LA MARQUE DE CETTE VERSION, posee dans l'archive : numero ET commit (D84).
    # Une installation deployee n'a pas de depot git ; sans ce fichier, elle ne peut pas
    # dire ce qu'elle contient, et on ne peut pas savoir si elle est a jour. Le numero
    # seul ne suffit pas : deux archives « v0.1 » peuvent differer de vingt commits.
    $commit = Get-GitCommit -Path $repoRoot
    Write-BuildStamp -Root $staging -Version $(if ($version.StartsWith('v')) { $version } else { "v$version" }) -Commit $commit
    # CE FICHIER N'EST PAS SUIVI PAR GIT : il est fabrique ici. Le controle final compte
    # les fichiers de l'archive et les compare a la liste retenue -- il faut donc lui
    # dire. Sans cette ligne, la fabrication s'arretait sur « 146 fichiers pour 145
    # attendus » et le deploiement etait abandonne (constate le 27/08 : le garde-fou
    # avait raison, c'est le decompte qui avait tort).
    $genereParLaFabrication += 'BUILD'
    Write-Host ("Marque posée : v" + ($version -replace '^v', '') + " / " + $(if ($commit) { $commit.Substring(0, 8) } else { 'commit inconnu' }))

    # Le dossier lui-meme est compresse, pas son contenu : l'archive porte donc une racine
    # « vigie-<version>/ ». Sans elle, une decompression deverse tout dans le dossier courant.
    if (Test-Path -LiteralPath $zip) {
        Remove-Item -LiteralPath $zip -Force
        Write-Host ("Archive précédente remplacée : " + $zip) -ForegroundColor DarkGray
    }
    Compress-Archive -Path $staging -DestinationPath $zip -CompressionLevel Optimal
} catch {
    Write-Host ("Échec de la fabrication : " + $_.Exception.Message) -ForegroundColor Red
    exit 3
}

# --- Verification du contenu REEL de l'archive -------------------------------------------
# On ne se fie pas a la liste d'entree : on relit ce qui a effectivement ete ecrit (D43).
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entrees = @($archive.Entries | ForEach-Object { $_.FullName })
} finally {
    $archive.Dispose()
}

$interditsZip = Find-CheminInterdit -Chemins $entrees
if ($interditsZip.Count -gt 0) {
    Write-Host ""
    Write-Host "ARRÊT : l'archive produite contient des fichiers interdits." -ForegroundColor Red
    foreach ($i in $interditsZip) { Write-Host ("  " + $i.Chemin + "   <- " + $i.Quoi) -ForegroundColor Red }
    Remove-Item -LiteralPath $zip -Force
    Write-Host "Archive supprimée : rien de douteux n'est laissé derrière." -ForegroundColor Red
    exit 2
}

# Les entrees de dossier n'ont pas de nom de fichier : on ne compte que les vrais fichiers.
$nbFichiersZip = @($entrees | Where-Object { -not $_.EndsWith('/') }).Count
# Attendu = ce que git suit ET ce que la fabrication a ajoute (la marque de version).
$attendu = $retenus.Count + $genereParLaFabrication.Count
if ($nbFichiersZip -ne $attendu) {
    Write-Host ("ARRÊT : " + $nbFichiersZip + " fichier(s) dans l'archive pour " + $attendu + " attendu(s)" +
                $(if ($genereParLaFabrication.Count) { " (" + $retenus.Count + " suivis par git + " + ($genereParLaFabrication -join ', ') + ")" }) + ".") -ForegroundColor Red
    exit 3
}

if (-not $KeepStaging) { Remove-Item -LiteralPath $staging -Recurse -Force }

$tailleZip = (Get-Item -LiteralPath $zip).Length
Write-Host ""
Write-Host ("Archive prête : " + $zip) -ForegroundColor Green
Write-Host ("  " + $nbFichiersZip + " fichier(s), " + (Format-Taille $tailleZip) + " compressés, racine « " + $nom + "/ »")
Write-Host "  Vérifié dans l'archive elle-même : aucun var/, aucun secret, aucun config.local.psd1, aucun journal." -ForegroundColor Green
if ($KeepStaging) { Write-Host ("  Préparation conservée : " + $staging) -ForegroundColor DarkGray }
exit 0
