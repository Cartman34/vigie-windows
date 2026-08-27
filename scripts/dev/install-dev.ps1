<#
    install-dev.ps1 - Installe les DEPENDANCES DE DEVELOPPEMENT. IDEMPOTENT.

    Pourquoi ce script existe (D100) : « si tu as besoin de quelque chose, c'est que c'est
    une dependance ». Installer un outil a la main, une fois, sur une machine, c'est un
    savoir qui ne survit pas a la session ou il a ete acquis : le poste suivant retombe sur
    la meme absence, sans savoir quoi installer ni pourquoi. Une dependance se DECLARE et
    s'installe par un script -- exactement ce que `scripts/install.ps1` fait pour
    l'application. Celui-ci fait la meme chose pour l'outillage du developpeur.

    Ce sont des dependances de DEVELOPPEMENT : elles ne servent qu'a qui travaille sur le
    depot. Rien ici n'est necessaire pour se servir de Vigie, et rien ici ne part dans
    l'archive de distribution.

    IL DEMANDE L'ELEVATION LUI-MEME. Une fenetre explique ce qui va etre installe et
    pourquoi, AVANT que Windows ne demande son accord (D66 : on n'envoie personne taper une
    commande a notre place). Portee MACHINE, jamais compte, comme pour PowerShell 7 (D79).

    CE QU'IL NE FAIT PAS : s'authentifier a votre place. `gh auth login` engage VOS
    identifiants -- il propose de lancer la procedure, dans une vraie fenetre, et vous
    laisse la conduire.

    Usage :
      pwsh -File .\scripts\dev\install-dev.ps1 -Lister    # etat des lieux, ne change rien
      pwsh -File .\scripts\dev\install-dev.ps1            # installe ce qui manque
      pwsh -File .\scripts\dev\install-dev.ps1 -Nom gh    # une seule dependance

    Codes de retour : 0 = tout est en place ; 1 = prerequis manquant (winget, elevation
                      refusee) ; 2 = au moins une installation a echoue ; 3 = elevation
                      refusee par l'utilisateur, rien n'a ete touche.
#>
param(
    # Ne rien installer : dire ce qui est la et ce qui manque.
    [switch] $Lister,

    # N'agir que sur cette dependance (son nom court, ex. « gh »).
    [string] $Nom,

    # Ne pas proposer d'ouvrir la session GitHub a la fin.
    [switch] $SansSession,

    # Deja eleve et deja consenti : ne pas redemander (usage interne a la relance).
    [switch] $Yes
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$commun   = Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1'
$avecFenetre = $false
if (Test-Path -LiteralPath $commun) {
    . $commun
    $avecFenetre = $true
}

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

function Test-Admin {
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

function Test-SessionGitHub {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $false }
    & gh auth status 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Une question, dans une vraie fenetre quand c'est possible. En console sinon : ce script
# tourne aussi dans un terminal sans bureau (session distante, tache planifiee).
function Get-Accord {
    param([string]$Titre, [string]$Question, [string]$Detail = '')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $texte = $Question + $(if ($Detail) { [Environment]::NewLine + [Environment]::NewLine + $Detail } else { '' })
        $r = [System.Windows.Forms.MessageBox]::Show($texte, $Titre,
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question)
        return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        Dire ""
        Dire ($Question + " [o/N]") 'Yellow'
        $rep = Read-Host
        return ("$rep".Trim().ToLower() -in @('o', 'oui', 'y', 'yes'))
    }
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

# --- La session GitHub, proposee a la fin -----------------------------------------------
#
# gh peut etre installe SANS session ouverte : c'est le cas le plus trompeur, la commande
# existe et toute publication echoue quand meme.
function Invoke-SessionGitHub {
    if ($SansSession) { return }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return }
    if (Test-SessionGitHub) {
        Dire "Session GitHub : ouverte." 'Green'
        return
    }
    Dire ""
    Dire "GitHub CLI est installe, mais aucune session n'est ouverte." 'Yellow'
    $ok = Get-Accord -Titre 'Vigie - session GitHub' `
                     -Question "Ouvrir la session GitHub maintenant ?" `
                     -Detail ("Une fenetre va s'ouvrir avec un code a huit caracteres, puis votre navigateur." +
                              [Environment]::NewLine +
                              "Vous collez le code sur github.com et vous validez : c'est vous qui vous authentifiez, " +
                              "ce script ne voit ni votre mot de passe ni votre jeton.")
    if (-not $ok) {
        Dire "A faire quand vous voudrez :  gh auth login --web" 'DarkGray'
        return
    }
    # Fenetre VISIBLE et interactive : la procedure affiche un code a recopier, il faut
    # pouvoir le lire. -Wait pour constater le resultat plutot que de le supposer (D43).
    try {
        $p = Start-Process -FilePath 'gh.exe' `
                           -ArgumentList @('auth', 'login', '--web', '--git-protocol', 'https', '--hostname', 'github.com') `
                           -Wait -PassThru
        if (Test-SessionGitHub) {
            Dire "Session GitHub ouverte." 'Green'
        } else {
            Dire ("La session n'a pas ete ouverte (gh a rendu " + $p.ExitCode + "). Reessayez :  gh auth login --web") 'Yellow'
        }
    } catch {
        Dire ("Impossible de lancer gh : " + $_.Exception.Message) 'Red'
        Dire "A faire a la main :  gh auth login --web" 'Yellow'
    }
}

if (-not $manquantes.Count) {
    Dire "Tout est en place." 'Green'
    Invoke-SessionGitHub
    exit 0
}

if ($Lister) {
    Dire ("" + $manquantes.Count + " dependance(s) manquante(s). Pour les installer :") 'Yellow'
    Dire "  pwsh -File .\scripts\dev\install-dev.ps1"
    exit 0
}

# --- Elevation : demandee ICI, expliquee AVANT ------------------------------------------
if (-not (Test-Admin)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Dire "winget est introuvable : impossible d'installer automatiquement." 'Red'
        Dire "Installez « App Installer » depuis le Microsoft Store, puis relancez." 'Yellow'
        exit 1
    }
    $quoi = @($manquantes | ForEach-Object { $_.Titre + " (" + $_.Winget + ")" })
    $ok = $true
    if ($avecFenetre) {
        $ok = Show-ElevationRationale -AssumeYes:$Yes `
                -Title "Installer les dependances de developpement" `
                -Summary ("Ces outils s'installent POUR TOUTE LA MACHINE, jamais pour votre seul compte : " +
                          "un outil pose dans un profil est invisible des autres comptes et des taches planifiees. " +
                          "Windows va demander votre accord.") `
                -Changes (@($quoi | ForEach-Object { "Installation de " + $_ }) +
                          @("Aucune version deja installee n'est remplacee",
                            "Aucune session GitHub n'est ouverte sans votre geste",
                            "Rien n'est supprime ailleurs sur la machine"))
    } else {
        $ok = Get-Accord -Titre 'Vigie - dependances de developpement' `
                         -Question "Installer ces outils pour toute la machine ?" `
                         -Detail ($quoi -join [Environment]::NewLine)
    }
    if (-not $ok) {
        Dire "Installation annulee. Rien n'a ete touche." 'Yellow'
        exit 3
    }

    $argv = @('-Yes')
    if ($Nom)         { $argv += @('-Nom', $Nom) }
    if ($SansSession) { $argv += '-SansSession' }

    if ($avecFenetre) {
        # La relance eleve, attend, et RAPPORTE : son journal est relu ici, sinon
        # l'utilisateur ne verrait qu'une fenetre disparaitre.
        $journal = Join-Path $env:TEMP 'vigie-dev'
        $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments $argv -LogDir $journal
        $dernier = @(Get-ChildItem -Path $journal -Filter 'elevated_install-dev_*.log' -File -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($dernier.Count) {
            Dire ""
            Get-Content -LiteralPath $dernier[0].FullName -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        }
        # La session GitHub se propose depuis la session NON elevee : c'est le compte de
        # l'utilisateur qui doit porter le jeton, pas l'administrateur.
        if ($code -eq 0) { Invoke-SessionGitHub }
        exit $code
    }

    Dire "Relancez ce script depuis un terminal administrateur." 'Yellow'
    exit 1
}

# --- Installation ------------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Dire "winget est introuvable : impossible d'installer automatiquement." 'Red'
    Dire "Installez « App Installer » depuis le Microsoft Store, puis relancez." 'Yellow'
    exit 1
}

$echecs = 0
foreach ($d in $manquantes) {
    Dire ("Installation de " + $d.Titre + " (" + $d.Winget + ") pour la machine...") 'Cyan'
    $code = -1
    try {
        # --scope machine : jamais dans le profil d'un compte (D79).
        & winget install --id $d.Winget --scope machine --silent `
                  --accept-package-agreements --accept-source-agreements | Write-Host
        $code = $LASTEXITCODE
    } catch {
        Dire ("  winget a leve une erreur : " + $_.Exception.Message) 'Red'
    }

    # LE RESULTAT SE CONSTATE (D43) : winget rend parfois 0 sans avoir rien pose, et
    # parfois un code non nul pour un paquet deja present. Seule la commande fait foi.
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
# Sous elevation, on ne propose PAS la session : elle appartiendrait a l'administrateur.
if (-not $Yes) { Invoke-SessionGitHub }
exit 0
