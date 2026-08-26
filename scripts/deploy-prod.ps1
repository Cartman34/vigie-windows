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
      pwsh -File .\scripts\deploy-prod.ps1 -Zip .\distigie-0.1.zip
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
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

# --- 1. La version a deployer -------------------------------------------------
if (-not $Zip) {
    $build = Join-Path $PSScriptRoot 'build-release.ps1'
    if (-not (Test-Path -LiteralPath $build)) {
        Write-Host "Aucune archive fournie et build-release.ps1 est absent : precisez -Zip." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Fabrication de l'archive de distribution..."
    & pwsh -NoProfile -File $build | Write-Host
    $dist = Join-Path $repoRoot 'dist'
    $Zip = @(Get-ChildItem -Path $dist -Filter 'vigie-*.zip' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $Zip -or -not (Test-Path -LiteralPath $Zip)) {
    Write-Host "Archive introuvable : $Zip" -ForegroundColor Yellow
    exit 1
}
$Zip = (Resolve-Path -LiteralPath $Zip).Path
Write-Host ("Version a deployer : " + (Split-Path $Zip -Leaf))

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

    Write-Host ("Copie vers " + $Destination + " ...")
    Copy-Item -Path (Join-Path $source '*') -Destination $Destination -Recurse -Force

    if (Test-Path -LiteralPath $garde) {
        New-Item -ItemType Directory -Path $cfgDest -Force | Out-Null
        Get-ChildItem -Path $garde -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $cfgDest -Force
        }
        Write-Host "Reglages de la machine conserves."
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ("Vigie deploye : " + $Destination) -ForegroundColor Green

# --- 4. Les comptes : proposes ici, modifiables a tout moment -----------------
$outilComptes = Join-Path $Destination 'scriptsigie-comptes.ps1'
if (-not (Test-Path -LiteralPath $outilComptes)) { $outilComptes = Join-Path $PSScriptRoot 'vigie-comptes.ps1' }

# QUI a Vigie est un autre geste, volontairement : deployer installe l'application a un
# endroit connu d'avance, pour tout le monde. Les comptes se choisissent apres, et se
# changent a tout moment.
Write-Host ""
& pwsh -NoProfile -File $outilComptes | Write-Host
Write-Host "Pour changer a tout moment :"
Write-Host ("  pwsh -File " + $outilComptes + " -Activer <compte>")
Write-Host ("  pwsh -File " + $outilComptes + " -Retirer <compte>")
Write-Host "Ou dans l'application : Parametres > Utilisateurs."
exit 0
