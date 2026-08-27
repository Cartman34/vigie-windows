<#
    install-dev.ps1 - Installe les DEPENDANCES DE DEVELOPPEMENT. IDEMPOTENT.

    Pourquoi ce script existe : « si tu as besoin de quelque chose, c'est que c'est une
    dependance ». Installer un outil a la main, une fois, sur une machine, c'est un savoir
    qui ne survit pas a la session ou il a ete acquis : le poste suivant retombe sur la
    meme absence, sans savoir quoi installer ni pourquoi. Une dependance se DECLARE et
    s'installe par un script -- exactement ce que `scripts/install.ps1` fait deja pour
    l'application. Celui-ci fait la meme chose pour l'outillage du developpeur.

    Ce sont des dependances de DEVELOPPEMENT : elles ne servent qu'a qui travaille sur le
    depot. Rien ici n'est necessaire pour se servir de Vigie, et rien ici ne part dans
    l'archive de distribution.

    PORTEE MACHINE, jamais compte. Comme pour PowerShell 7 (D79) : un outil installe dans
    le profil d'un compte est invisible des autres, et des taches planifiees.

    CE QUE CE SCRIPT NE FAIT PAS : s'authentifier a votre place. `gh auth login` ouvre une
    session GitHub avec VOS identifiants -- c'est votre geste, pas celui d'un script. Le
    script le rappelle a la fin si la session manque.

    Usage :
      pwsh -File .\scripts\dev\install-dev.ps1 -Lister    # etat des lieux, ne change rien
      pwsh -File .\scripts\dev\install-dev.ps1            # installe ce qui manque
      pwsh -File .\scripts\dev\install-dev.ps1 -Nom gh    # une seule dependance

    Codes de retour : 0 = tout est en place ; 1 = prerequis manquant (winget, droits) ;
                      2 = au moins une installation a echoue.
#>
param(
    # Ne rien installer : dire ce qui est la et ce qui manque.
    [switch] $Lister,

    # N'agir que sur cette dependance (son nom court, ex. « gh »).
    [string] $Nom
)
$ErrorActionPreference = 'Stop'

# --- LES DEPENDANCES, DECLAREES ------------------------------------------------------
#
# Chacune dit ce qu'elle est, comment on la reconnait, et SURTOUT a quoi elle sert ici :
# une dependance sans raison ecrite finit par etre installee « au cas ou ».
$DEPENDANCES = @(
    @{ Nom      = 'git'
       Titre    = 'Git'
       Winget   = 'Git.Git'
       Commande = 'git'
       Pourquoi = "Fabriquer l'archive de distribution : build-release.ps1 lit la liste des fichiers avec « git ls-files », ce qui garantit qu'aucun fichier ignore -- jeton, cache, journal -- ne parte chez l'utilisateur. Sert aussi a la voie « clone » de la mise a jour." }

    @{ Nom      = 'gh'
       Titre    = 'GitHub CLI'
       Winget   = 'GitHub.cli'
       Commande = 'gh'
       Pourquoi = "Publier une version : creer la release GitHub et y attacher l'archive. Sans lui, la publication se fait a la main dans le navigateur, a refaire integralement a chaque version." }

    @{ Nom      = 'php'
       Titre    = 'PHP'
       Winget   = 'PHP.PHP.8.4'
       Commande = 'php'
       Pourquoi = "Servir l'Atelier (apps/atelier), l'outil de validation visuelle : il tourne sur le serveur integre de PHP. Volontairement cantonne a l'outillage -- PHP n'entre jamais dans l'application. N'importe quel PHP 8.x recent convient : l'identifiant winget ci-dessus ne sert qu'a l'installation automatique." }
)

function Dire { param([string]$T, [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }

function Test-Elevation {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-Etat {
    param([hashtable]$D)
    $c = Get-Command $D.Commande -ErrorAction SilentlyContinue
    if (-not $c) { return @{ Present = $false; Ou = $null; Version = $null } }
    $v = $null
    try { $v = (& $D.Commande --version 2>$null | Select-Object -First 1) } catch { }
    return @{ Present = $true; Ou = $c.Source; Version = "$v".Trim() }
}

# --- Le tri ---------------------------------------------------------------------------
$aTraiter = $DEPENDANCES
if ($Nom) {
    $aTraiter = @($DEPENDANCES | Where-Object { $_.Nom -eq $Nom })
    if (-not $aTraiter.Count) {
        Dire ("Dependance inconnue : " + $Nom + ". Connues : " + (($DEPENDANCES | ForEach-Object { $_.Nom }) -join ', ')) 'Red'
        exit 1
    }
}

Dire ""
Dire "=== Dependances de developpement ===" 'Cyan'
Dire ""
$manquantes = @()
foreach ($d in $aTraiter) {
    $e = Get-Etat -D $d
    if ($e.Present) {
        Dire ("  [OK]      " + $d.Titre + "  -  " + $(if ($e.Version) { $e.Version } else { $e.Ou })) 'Green'
    } else {
        Dire ("  [ABSENT]  " + $d.Titre) 'Yellow'
        Dire ("            " + $d.Pourquoi) 'DarkGray'
        $manquantes += $d
    }
}
Dire ""

if (-not $manquantes.Count) {
    Dire "Tout est en place." 'Green'
    # gh peut etre installe SANS session ouverte : c'est le cas le plus trompeur, la
    # commande existe mais toute publication echouera.
    $gh = $aTraiter | Where-Object { $_.Nom -eq 'gh' }
    if ($gh -and (Get-Command gh -ErrorAction SilentlyContinue)) {
        & gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Dire ""
            Dire "GitHub CLI est installe, mais aucune session n'est ouverte." 'Yellow'
            Dire "A faire vous-meme, une fois (un script n'a pas a manipuler vos identifiants) :" 'Yellow'
            Dire "  gh auth login"
        }
    }
    exit 0
}

if ($Lister) {
    Dire ("" + $manquantes.Count + " dependance(s) manquante(s). Pour les installer :") 'Yellow'
    Dire "  pwsh -File .\scripts\dev\install-dev.ps1        (terminal administrateur)"
    exit 0
}

# --- Installation ----------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Dire "winget est introuvable : impossible d'installer quoi que ce soit automatiquement." 'Red'
    Dire "Installez « App Installer » depuis le Microsoft Store, puis relancez." 'Yellow'
    exit 1
}
if (-not (Test-Elevation)) {
    # On le dit AVANT d'essayer : winget en portee machine sans droits echoue sur un
    # 0x80070005 illisible, apres avoir parfois deja desinstalle l'existant (vecu le 26/08).
    Dire "Ces installations se font pour TOUTE LA MACHINE : il faut un terminal administrateur." 'Yellow'
    Dire "Rien n'a ete touche. Relancez ainsi :" 'Yellow'
    Dire "  pwsh -File .\scripts\dev\install-dev.ps1"
    exit 1
}

$echecs = 0
foreach ($d in $manquantes) {
    Dire ("Installation de " + $d.Titre + " (" + $d.Winget + ") pour la machine...") 'Cyan'
    try {
        # --scope machine : jamais dans le profil d'un compte (D79).
        # Les accords de licence sont acceptes ici parce que c'est une installation
        # d'outillage demandee explicitement ; rien n'est installe sans ce script.
        & winget install --id $d.Winget --scope machine --silent --accept-package-agreements --accept-source-agreements | Write-Host
        $code = $LASTEXITCODE
    } catch {
        Dire ("  winget a leve une erreur : " + $_.Exception.Message) 'Red'
        $code = -1
    }

    # LE RESULTAT SE CONSTATE (D43) : winget rend parfois 0 sans avoir rien pose, et
    # parfois un code non nul pour un paquet deja installe. Seule la commande fait foi.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    $e = Get-Etat -D $d
    if ($e.Present) {
        Dire ("  " + $d.Titre + " est en place : " + $(if ($e.Version) { $e.Version } else { $e.Ou })) 'Green'
    } else {
        $echecs++
        Dire ("  " + $d.Titre + " n'est TOUJOURS pas la (winget a rendu " + $code + ").") 'Red'
        Dire ("  A faire a la main : winget install --id " + $d.Winget + " --scope machine") 'Yellow'
        Dire "  Un terminal deja ouvert peut aussi ne pas voir le nouveau PATH : rouvrez-le avant de conclure." 'DarkGray'
    }
}

Dire ""
if ($echecs) {
    Dire ("" + $echecs + " installation(s) en echec.") 'Red'
    exit 2
}
Dire "Toutes les dependances de developpement sont en place." 'Green'
if (Get-Command gh -ErrorAction SilentlyContinue) {
    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Dire ""
        Dire "Derniere etape, la votre : ouvrir une session GitHub." 'Yellow'
        Dire "  gh auth login"
        Dire "Un script ne manipule pas vos identifiants." 'DarkGray'
    }
}
exit 0
