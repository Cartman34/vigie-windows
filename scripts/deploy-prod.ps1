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
    # Le numero de version a graver, quand le TAG a deja ete pose ailleurs -- par l'action
    # « tag-version », dans la session du proprietaire du depot (D112). Sans lui, et sans
    # -Zip, on pose le tag ici : on tourne alors sous le compte de la personne.
    [string]   $Version,
    [switch]   $Yes
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

# --- 0. LE TAG DE CE DEPLOIEMENT ---------------------------------------------
#
# LE TAG SE POSE AILLEURS (D112) : Get-NextDeploymentTag et New-DeploymentTag vivent dans
# common.ps1, et c'est l'action « tag-version » qui les appelle DANS LA SESSION du
# proprietaire du depot. Ici, on ne fait que s'en servir quand on nous le passe.
#
# En ligne de commande, sans -Zip et sans -Version, on pose le tag nous-memes : on tourne
# alors sous le compte de la personne, c'est le meme cas de figure.
if (-not $Zip -and -not $Version) {
    $pose = New-DeploymentTag -RepoPath $repoRoot -Push
    if ($pose.posed) {
        $tag = $pose.tag
        Write-Info (Get-Label 'deploy-prod.tag-pose-sur' $tag (Get-GitCommit -Path $repoRoot -Court))
        if ($pose.pushed) { Write-Host (Get-Label 'deploy-prod.tag-pousse') }
        else              { Write-Detail (Get-Label 'deploy-prod.tag-local-pousse-impossible') }
    } else {
        Write-Detail (Get-Label 'deploy-prod.tag-non-pose' "$($pose.error)")
    }
} elseif ($Version) {
    # Le tag a ete pose par le demandeur, dans sa session : l'archive portera son numero.
    $tag = $Version
}

# --- 1. La version a deployer -------------------------------------------------
if (-not $Zip) {
    $build = Join-Path $PSScriptRoot 'build-release.ps1'
    if (-not (Test-Path -LiteralPath $build)) {
        Write-Warn (Get-Label 'deploy-prod.aucune-archive-fournie-et')
        exit 1
    }
    Write-Info (Get-Label 'deploy-prod.fabrication-de-archive-de')
    # L'archive porte le numero du tag qu'on vient de poser : le tag, l'archive et
    # l'installation racontent alors la meme histoire.
    if ($tag) { & pwsh -NoProfile -File $build -Version $tag | Write-Host }
    else      { & pwsh -NoProfile -File $build | Write-Host }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail (Get-Label 'deploy-prod.la-fabrication-de-archive')
        exit 1
    }
    $dist = Join-Path $repoRoot 'dist'
    $Zip = @(Get-ChildItem -Path $dist -Filter 'vigie-*.zip' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $Zip -or -not (Test-Path -LiteralPath $Zip)) {
    Write-Warn (Get-Label 'deploy-prod.archive-introuvable' $Zip)
    exit 1
}
$Zip = (Resolve-Path -LiteralPath $Zip).Path
Write-Info (Get-Label 'deploy-prod.version-deployer' (Split-Path $Zip -Leaf))
# --- 2. Elevation : ecrire hors du profil et poser des taches -----------------
if (-not (Test-IsElevated)) {
    $ok = Show-ElevationRationale -AssumeYes:$Yes -Title "Deployer Vigie pour tous les comptes" -Summary "Vigie va etre installe dans un emplacement lisible par tous les comptes de cet ordinateur. Chaque compte gardera ses propres reglages." -Changes @(
            ("Copie de " + (Split-Path $Zip -Leaf) + " vers " + $Destination),
            "Les reglages deja presents a destination sont conserves",
            "Aucun compte n'est active sans votre choix explicite",
            "Rien n'est supprime ailleurs sur la machine"
        )
    if (-not $ok) { Write-Host (Get-Label 'deploy-prod.deploiement-annule-rien-ete'); exit 3 }
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

    Write-Info (Get-Label 'deploy-prod.copie-vers' $Destination)
    Copy-Item -Path (Join-Path $source '*') -Destination $Destination -Recurse -Force

    if (Test-Path -LiteralPath $garde) {
        New-Item -ItemType Directory -Path $cfgDest -Force | Out-Null
        Get-ChildItem -Path $garde -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $cfgDest -Force
        }
        Write-Info (Get-Label 'deploy-prod.reglages-de-la-machine')
    }
    <#
        CETTE MACHINE EST UN POSTE DE DEVELOPPEMENT, ET ELLE LE DIT UNE FOIS.

        On deploie DEPUIS UN DEPOT : c'est un fait, pas une intention. La machine porte
        donc sa declaration a un seul endroit, hors de toute copie -- sinon le depot dit
        « dev », l'installation partagee (qui n'a pas de config locale) dit « prod », et
        la carte annonce « Production » sur la machine ou tout est developpe.

        On note aussi OU est ce depot : c'est ce qui permet a l'installation, plus tard,
        de fabriquer une version a partir de lui au lieu d'aller chercher sur Internet.
    #>
    if (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) {
        try {
            $declaredAt = Set-ComputerConfigValue -Values @{ Environment = 'dev'; SourcePath = $repoRoot }
            Write-Detail (Get-Label 'deploy-prod.machine-declaree' $declaredAt)
            # ET GIT DOIT POUVOIR LE LIRE. Le service tourne sous un autre compte : sans
            # cette declaration, il ne peut meme pas cloner la source (mesure le 30/08).
            if (Set-GitSafeDirectory -RepoPath $repoRoot) {
                Write-Detail (Get-Label 'deploy-prod.depot-de-confiance' $repoRoot)
            }
        } catch {
            Write-Warn (Get-Label 'deploy-prod.machine-non-declaree' $_.Exception.Message)
        }
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Ok (Get-Label 'deploy-prod.vigie-deploye' $Destination)

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
    Write-Warn (Get-Label 'deploy-prod.attention-powershell-est-installe')
    Write-Warn (Get-Label 'deploy-prod.les-autres-comptes-ne')
    Write-Info (Get-Label 'deploy-prod.winget-install-id-microsoft')
}

& pwsh -NoProfile -File $outilComptes | Write-Host
Write-Info (Get-Label 'deploy-prod.pour-changer-tout-moment')
Write-Info (Get-Label 'deploy-prod.pwsh-file-activer-compte' $outilComptes)
Write-Info (Get-Label 'deploy-prod.pwsh-file-retirer-compte' $outilComptes)
Write-Info (Get-Label 'deploy-prod.ou-dans-application-parametres')
exit 0
