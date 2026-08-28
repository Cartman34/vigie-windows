<#
    deploy-prod.ps1 - Deploie une version STABLE de Vigie pour TOUS les comptes. IDEMPOTENT.

    Modele valide par l'utilisateur (D65) : on choisit une version, on la copie en prod, et
    c'est CETTE copie que les autres comptes utilisent. Chez l'utilisateur final il n'y a
    qu'un seul depot, celui de prod -- la livraison par archive suffit.

    Concretement :
      - la version deployee vient d'une ARCHIVE (build-release.ps1 la fabrique depuis git,
        avec ses garde-fous) : ce qui part en prod est une version CHOISIE, jamais l'etat de
        travail du moment ;
      - la destination par defaut est C:\Program Files\Sowapps\Vigie (Editeur\Produit) : lisible par tous les comptes,
        modifiable seulement par un administrateur. L'espace de travail personnel du
        developpeur n'est pas ouvert aux autres comptes ;
      - les REGLAGES de la machine deja presents a destination (config/*.local.*,
        actions.policy.json) sont CONSERVES : deployer ne remet pas les choix a zero ;
      - a la fin, les comptes sont proposes -- et restent modifiables a tout moment
        (scripts/vigie-comptes.ps1, ou Parametres > Utilisateurs dans l'application).

    Usage :
      pwsh -File .\scripts\deploy-prod.ps1
      pwsh -File .\scripts\deploy-prod.ps1 -Zip .\dist\vigie-0.1.zip
      pwsh -File .\scripts\deploy-prod.ps1 -Comptes fhaza,Famille
      pwsh -File .\scripts\deploy-prod.ps1 -Destination 'D:\Vigie'

    Codes de retour : 0 = deploye ; 1 = prerequis manquant ; 3 = refuse ou droits insuffisants.
#>
param(
    [string]   $Zip,
    [string]   $Destination = 'C:\Program Files\Sowapps\Vigie',
    [switch]   $Yes
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

# --- 0. LE TAG DE CE DEPLOIEMENT ---------------------------------------------
#
# Regle posee par l'utilisateur : on cree des versions v0.X et v0.X.Y, marquees par un
# TAG, et **uniquement au moment d'un deploiement**, avec un increment fixe. Un tag pose
# a chaque commit ne voudrait rien dire ; pose au deploiement, il repond exactement a la
# question « qu'est-ce qui tourne sur cette machine ? ».
#
# L'increment est le dernier nombre, +1. Le premier deploiement d'une version part de ce
# que dit le fichier VERSION (0.1 -> v0.1.1).
function Get-ProchainTag {
    param([string]$Racine)
    # La base vient du DERNIER TAG : c'est le seul numero que le projet maintient (D96).
    # « 0.1 » n'est que la graine du tout premier tag, quand aucun n'existe encore.
    $base = '0.1'
    try {
        $dernier = (& git -C $Racine describe --tags --abbrev=0 2>$null | Select-Object -First 1)
        if ($dernier -match '^v?(\d+\.\d+)\.\d+$') { $base = $Matches[1] }
    } catch { }
    $existants = @()
    try { $existants = @(& git -C $Racine tag --list ("v" + $base + ".*") 2>$null) } catch { }
    $max = 0
    foreach ($t in $existants) {
        if ("$t" -match ('^v' + [regex]::Escape($base) + '\.(\d+)$')) {
            $x = [int]$Matches[1]
            if ($x -gt $max) { $max = $x }
        }
    }
    return ('v' + $base + '.' + ($max + 1))
}

if (-not $Zip) {
    $tag = Get-ProchainTag -Racine $repoRoot
    $commit = (Get-GitCommit -Path $repoRoot -Court)
    try {
        # -f absent VOLONTAIREMENT : un tag ne se reecrit pas. S'il existe deja, c'est
        # que ce deploiement a deja eu lieu -- on le dit et on continue.
        & git -C $repoRoot tag -a $tag -m ("Deploiement du " + (Get-Date -Format 'dd/MM/yyyy HH:mm')) 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Info ("Tag pose : " + $tag + " sur " + $commit)
            # Le tag ne vaut que s'il est partage. L'echec de pousse n'est PAS fatal :
            # un deploiement doit aboutir meme sans reseau.
            & git -C $repoRoot push origin $tag 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "Tag pousse." } else { Write-Detail "Tag local (pousse impossible)." }
        } else {
            Write-Detail ("Tag " + $tag + " deja present : rien a poser.")
        }
    } catch {
        Write-Detail ("Tag non pose : " + $_.Exception.Message)
    }
}

# --- 1. La version a deployer -------------------------------------------------
if (-not $Zip) {
    $build = Join-Path $PSScriptRoot 'build-release.ps1'
    if (-not (Test-Path -LiteralPath $build)) {
        Write-Warn "Aucune archive fournie et build-release.ps1 est absent : precisez -Zip."
        exit 1
    }
    Write-Info "Fabrication de l'archive de distribution..."
    # L'archive porte le numero du tag qu'on vient de poser : le tag, l'archive et
    # l'installation racontent alors la meme histoire.
    if ($tag) { & pwsh -NoProfile -File $build -Version $tag | Write-Host }
    else      { & pwsh -NoProfile -File $build | Write-Host }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "La fabrication de l'archive a echoue : deploiement abandonne."
        exit 1
    }
    $dist = Join-Path $repoRoot 'dist'
    $Zip = @(Get-ChildItem -Path $dist -Filter 'vigie-*.zip' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $Zip -or -not (Test-Path -LiteralPath $Zip)) {
    Write-Warn "Archive introuvable : $Zip"
    exit 1
}
$Zip = (Resolve-Path -LiteralPath $Zip).Path
Write-Info ("Version a deployer : " + (Split-Path $Zip -Leaf))
# --- 2. Elevation : ecrire hors du profil et poser des taches -----------------
if (-not (Test-IsElevated)) {
    $ok = Show-ElevationRationale -AssumeYes:$Yes -Title "Deployer Vigie pour tous les comptes" -Summary "Vigie va etre installe dans un emplacement lisible par tous les comptes de cet ordinateur. Chaque compte gardera ses propres reglages." -Changes @(
            ("Copie de " + (Split-Path $Zip -Leaf) + " vers " + $Destination),
            "Les reglages deja presents a destination sont conserves",
            "Aucun compte n'est active sans votre choix explicite",
            "Rien n'est supprime ailleurs sur la machine"
        )
    if (-not $ok) { Write-Host "Deploiement annule. Rien n'a ete modifie."; exit 3 }
    $passe = @('-Zip', $Zip, '-Destination', $Destination, '-Yes')
    exit (Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments $passe -LogDir (Get-LogDir))
}

# --- 3. Extraction puis copie -------------------------------------------------
$temp = Join-Path $env:TEMP ('vigie-deploy-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    Expand-Archive -LiteralPath $Zip -DestinationPath $temp -Force
    # L'archive porte un dossier racine « vigie-<version> » : on deploie SON contenu.
    $racines = @(Get-ChildItem -Path $temp -Directory)
    $source  = if ($racines.Count -eq 1) { $racines[0].FullName } else { $temp }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    # Les REGLAGES de la machine survivent au deploiement : mis de cote, puis remis.
    # Les ecraser a chaque livraison serait une regression a chaque mise a jour.
    $garde   = Join-Path $temp '_config-machine'
    $cfgDest = Join-Path $Destination 'config'
    if (Test-Path -LiteralPath $cfgDest) {
        New-Item -ItemType Directory -Path $garde -Force | Out-Null
        foreach ($motif in @('*.local.*', 'actions.policy.json')) {
            Get-ChildItem -Path $cfgDest -File -Filter $motif -ErrorAction SilentlyContinue |
                ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $garde -Force }
        }
    }

    Write-Info ("Copie vers " + $Destination + " ...")
    Copy-Item -Path (Join-Path $source '*') -Destination $Destination -Recurse -Force

    if (Test-Path -LiteralPath $garde) {
        New-Item -ItemType Directory -Path $cfgDest -Force | Out-Null
        Get-ChildItem -Path $garde -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $cfgDest -Force
        }
        Write-Info "Reglages de la machine conserves."
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Ok ("Vigie deploye : " + $Destination)

# --- 4. Les comptes : proposes ici, modifiables a tout moment -----------------
# Deux Join-Path imbriques : l'antislash de 'scripts\vigie-comptes.ps1' avait ete
# mange a l'ecriture (il en restait un caractere de controle), et le chemin ne
# designait rien.
$outilComptes = Join-Path (Join-Path $Destination 'scripts') 'vigie-comptes.ps1'
if (-not (Test-Path -LiteralPath $outilComptes)) { $outilComptes = Join-Path $PSScriptRoot 'vigie-comptes.ps1' }

# QUI a Vigie est un autre geste, volontairement : deployer installe l'application a un
# endroit connu d'avance, pour tout le monde. Les comptes se choisissent apres, et se
# changent a tout moment.
# DEPENDANCE : sans un PowerShell 7 installe pour la machine, activer un autre compte
# poserait une tache qui ne lance rien. Le deploiement est justement le moment ou on
# prepare les AUTRES comptes : on le dit ici, fort, plutot qu'apres coup.
if (-not (Get-SharedPwshPath)) {
    Write-Warn "ATTENTION : PowerShell 7 n'est installe que pour le compte courant."
    Write-Warn "Les autres comptes ne pourront pas demarrer Vigie. A faire une fois, en administrateur :"
    Write-Info "  winget install --id Microsoft.PowerShell --scope machine"
}

& pwsh -NoProfile -File $outilComptes | Write-Host
Write-Info "Pour changer a tout moment :"
Write-Info ("  pwsh -File " + $outilComptes + " -Activer <compte>")
Write-Info ("  pwsh -File " + $outilComptes + " -Retirer <compte>")
Write-Info "Ou dans l'application : Parametres > Utilisateurs."
exit 0
