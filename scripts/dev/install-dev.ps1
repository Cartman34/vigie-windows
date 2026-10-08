# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    install-dev.ps1 -- installs the DEVELOPMENT DEPENDENCIES. IDEMPOTENT.

    Intent: make the developer's tooling a thing one installs by running a script, not a thing one remembers.
    "If you need something, then it is a dependency" (D100): installing a tool by hand, once, on one machine is
    knowledge that does not outlive the session in which it was acquired -- the next workstation falls back on
    the same absence, with no idea what to install nor why. A dependency is DECLARED and installed by a script --
    exactly what `scripts/install.ps1` does for the application. This one does the same for the developer's
    tooling.

    Usage:
      pwsh -File .\scripts\dev\install-dev.ps1 -Lister    # a survey, changes nothing
      pwsh -File .\scripts\dev\install-dev.ps1            # installs what is missing
      pwsh -File .\scripts\dev\install-dev.ps1 -Nom gh    # one single dependency
    Exit codes: 0 = everything is in place; 1 = a missing prerequisite (winget, elevation refused); 2 = at least
    one installation failed; 3 = elevation refused by the user, nothing was touched.

    These are DEVELOPMENT dependencies: they serve only whoever works on the repository. Nothing here is needed
    in order to use Vigie, and nothing here goes into the distribution archive.

    IT ASKS FOR THE ELEVATION ITSELF. A window explains what is about to be installed and why, BEFORE Windows
    asks for its agreement (D66: we send nobody off to type a command in our stead). MACHINE scope, never an
    account's, as for PowerShell 7 (D79).

    WHAT IT DOES NOT DO: authenticate in your place. `gh auth login` commits YOUR credentials -- it offers to
    start the procedure, in a real window, and leaves you to drive it.
#>




param(
    # Install nothing: say what is there and what is missing.
    [switch] $Lister,

    # Act on this dependency only (its short name, for instance gh).
    [string] $Name,

    # Do not offer to open the GitHub session at the end.
    [switch] $SansSession,

    # Already elevated and already consented: do not ask again (used internally by the restart).
    [switch] $Yes
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # the same display as everywhere
$commun   = Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1'
$withWindow = $false
if (Test-Path -LiteralPath $commun) {
    . $commun
    $withWindow = $true
}

# --- THE DEPENDENCIES, DECLARED -----------------------------------------------
#
# Each one says what it is, how it is recognised, and ABOVE ALL what it is for here: a dependency with no written
# reason ends up being installed "just in case".
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

# A question, in a real window when that is possible. On the console otherwise: this script also runs in a
# terminal with no desktop (a remote session, a scheduled task).
function Get-Accord {
    param([string]$Title, [string]$Question, [string]$Detail = '')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $text = $Question + $(if ($Detail) { [Environment]::NewLine + [Environment]::NewLine + $Detail } else { '' })

        # WE WARN BEFORE OPENING. A modal can open behind the terminal: the script then seems blocked "for no
        # reason", while it is in fact waiting for an answer nobody can see (observed on 27/08, several minutes
        # lost).
        Write-Step (Get-Label 'install-dev.une-fenetre-vient-de' $Title)
        Write-Detail (Get-Label 'install-dev.si-vous-ne-la')

        # An invisible OWNER plus TopMost forces the box to the front. Without it, MessageBox has no parent window
        # and Windows puts it where it likes.
        $holder = New-Object System.Windows.Forms.Form
        $holder.TopMost        = $true
        $holder.ShowInTaskbar  = $false
        $holder.FormBorderStyle = 'None'
        $holder.Size           = New-Object System.Drawing.Size(1, 1)
        $holder.StartPosition  = 'CenterScreen'
        $holder.Opacity        = 0
        try {
            $holder.Show()
            $holder.Activate()
            $r = [System.Windows.Forms.MessageBox]::Show($holder, $text, $Title,
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question)
        } finally {
            $holder.Close()
            $holder.Dispose()
        }
        return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        Write-Warn (Get-Label 'install-dev.texte' $Question)
        $rep = Read-Host
        return ("$rep".Trim().ToLower() -in @('o', 'oui', 'y', 'yes'))
    }
}

# --- The sorting -------------------------------------------------------------
$aTraiter = $DEPENDANCES
if ($Name) {
    $aTraiter = @($DEPENDANCES | Where-Object { $_.Nom -eq $Name })
    if (-not $aTraiter.Count) {
        Write-Fail (Get-Label 'install-dev.dependance-inconnue-connues' $Name ($DEPENDANCES | ForEach-Object { $_.Nom }) -join ', ')
        exit 1
    }
}

Write-Step (Get-Label 'install-dev.dependances-de-developpement')
$missing = @()
foreach ($d in $aTraiter) {
    $e = Get-Etat -D $d
    if ($e.Present) {
        Write-Ok (Get-Label 'install-dev.ok' $d.Titre $(if ($e.Version) { $e.Version } else { $e.Ou }))
    } else {
        Write-Warn (Get-Label 'install-dev.absent' $d.Titre)
        Write-Detail ("            " + $d.Pourquoi)
        $missing += $d
    }
}
# --- The GitHub session, offered at the end -----------------------------------
#
# gh can be installed WITHOUT an open session: that is the most misleading case, the command exists and every
# publication fails all the same.
function Invoke-SessionGitHub {
    if ($SansSession) { return }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return }
    if (Test-SessionGitHub) {
        Write-Ok (Get-Label 'install-dev.session-github-ouverte')
        return
    }
    Write-Warn (Get-Label 'install-dev.github-cli-est-installe')
    $ok = Get-Accord -Title 'Vigie - session GitHub' `
                     -Question "Ouvrir la session GitHub maintenant ?" `
                     -Detail ("Une fenêtre va s'ouvrir avec un code à huit caractères, puis votre navigateur." +
                              [Environment]::NewLine +
                              "Vous collez le code sur github.com et vous validez : c'est vous qui vous authentifiez, " +
                              "ce script ne voit ni votre mot de passe ni votre jeton.")
    if (-not $ok) {
        Write-Detail (Get-Label 'install-dev.faire-quand-vous-voudrez')
        return
    }
    # A VISIBLE and interactive window: the procedure displays a code to copy, and it must be readable. -Wait so
    # as to observe the result rather than assume it (D43).
    try {
        $p = Start-ChildProcess -FilePath 'gh.exe' `
                                -Arguments @('auth', 'login', '--web', '--git-protocol', 'https', '--hostname', 'github.com') `
                                -Options @{ Wait = $true; PassThru = $true }
        if (Test-SessionGitHub) {
            Write-Ok (Get-Label 'install-dev.session-github-ouverte-2')
        } else {
            Write-Warn (Get-Label 'install-dev.la-session-pas-ete' $p.ExitCode)
        }
    } catch {
        Write-Fail (Get-Label 'install-dev.impossible-de-lancer-gh' $_.Exception.Message)
        Write-Warn (Get-Label 'install-dev.faire-la-main-gh')
    }
}

if (-not $missing.Count) {
    Write-Ok (Get-Label 'install-dev.tout-est-en-place')
    Invoke-SessionGitHub
    exit 0
}

if ($Lister) {
    Write-Warn (Get-Label 'install-dev.dependance-manquante-pour-les' $missing.Count)
    Write-Info (Get-Label 'install-dev.pwsh-file-scripts-dev')
    exit 0
}

# --- Elevation: asked for HERE, explained BEFORE ------------------------------
if (-not (Test-Admin)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail (Get-Label 'install-dev.winget-est-introuvable-impossible')
        Write-Warn (Get-Label 'install-dev.installez-app-installer-depuis')
        exit 1
    }
    $quoi = @($missing | ForEach-Object { $_.Titre + " (" + $_.Winget + ")" })
    $ok = $true
    if ($withWindow) {
        $ok = Show-ElevationRationale -AssumeYes:$Yes `
                -Title "Installer les dépendances de développement" `
                -Summary ("Ces outils s'installent pour TOUTE LA MACHINE, jamais pour votre seul compte : un outil posé " +
                          "dans un profil est invisible des autres comptes et des tâches planifiées.") `
                -Changes (@($quoi | ForEach-Object { "Installation de " + $_ }) +
                          @("Aucune version déjà installée n'est remplacée",
                            "Aucune session GitHub n'est ouverte sans votre geste",
                            "Rien n'est supprimé ailleurs sur la machine"))
    } else {
        $ok = Get-Accord -Title 'Vigie - dependances de developpement' `
                         -Question "Installer ces outils pour toute la machine ?" `
                         -Detail ($quoi -join [Environment]::NewLine)
    }
    if (-not $ok) {
        Write-Warn (Get-Label 'install-dev.installation-annulee-rien-ete')
        exit 3
    }

    $argv = @('-Yes')
    if ($Name)         { $argv += @('-Nom', $Name) }
    if ($SansSession) { $argv += '-SansSession' }

    if ($withWindow) {
        # The restart elevates, waits, and REPORTS: its log is read back here, otherwise the user would see only a
        # window disappear.
        $journal = Join-Path $env:TEMP 'vigie-dev'
        $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments $argv -LogDir $journal
        $dernier = @(Get-ChildItem -Path $journal -Filter 'elevated_install-dev_*.log' -File -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($dernier.Count) {
            Get-Content -LiteralPath $dernier[0].FullName -Encoding UTF8 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host $_ }
        }
        # THE PATH IS READ AGAIN BEFORE LOOKING FOR gh. The elevated pass has just installed it, but THIS session
        # has kept the old PATH: without that refresh, Get-Command gh fails, the session offer is skipped without
        # a word, and the user sees the installation end in silence (observed on 27/08).
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')
        # The GitHub session is offered from the session that is NOT elevated: it is the user's account that must
        # carry the token, not the administrator's.
        if ($code -eq 0) { Invoke-SessionGitHub }
        exit $code
    }

    Write-Warn (Get-Label 'install-dev.relancez-ce-script-depuis')
    exit 1
}

# --- Installation ------------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail (Get-Label 'install-dev.winget-est-introuvable-impossible')
    Write-Warn (Get-Label 'install-dev.installez-app-installer-depuis')
    exit 1
}

$failures = 0
foreach ($d in $missing) {
    Write-Step (Get-Label 'install-dev.installation-de-pour-la' $d.Titre $d.Winget)
    $code = -1
    try {
        # --scope machine: never inside an account's profile (D79).
        & winget install --id $d.Winget --scope machine --silent `
                  --accept-package-agreements --accept-source-agreements | Write-Host
        $code = $LASTEXITCODE
    } catch {
        Write-Fail (Get-Label 'install-dev.winget-leve-une-erreur' $_.Exception.Message)
    }

    # THE RESULT IS OBSERVED (D43): winget sometimes returns 0 without having laid anything down, and sometimes a
    # non-zero code for a package that is already there. Only the command itself is authoritative.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    $e = Get-Etat -D $d
    if ($e.Present) {
        Write-Ok (Get-Label 'install-dev.est-en-place' $d.Titre $(if ($e.Version) { $e.Version } else { $e.Ou }))
    } else {
        $failures++
        Write-Fail (Get-Label 'install-dev.est-toujours-pas-la' $d.Titre $code)
        Write-Warn (Get-Label 'install-dev.faire-la-main-winget' $d.Winget)
        Write-Detail (Get-Label 'install-dev.un-terminal-deja-ouvert')
    }
}

if ($failures) {
    Write-Fail (Get-Label 'install-dev.installation-en-echec' $failures)
    exit 2
}
Write-Ok (Get-Label 'install-dev.toutes-les-dependances-de')
# Under elevation we do NOT offer the session: it would belong to the administrator.
if (-not $Yes) { Invoke-SessionGitHub }
exit 0
