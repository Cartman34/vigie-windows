# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    debug.ps1 - DEBOGUER UN ELEMENT DE VIGIE, TOUJOURS DE LA MEME FACON.

    POURQUOI CE SCRIPT EXISTE. Chaque fois qu'une chose ne marche pas, je reinventais la
    facon de l'examiner : une ligne de commande differente, un journal cherche a la main,
    parfois un second journal cree pour rien par-dessus celui que le programme ecrit deja.
    Le lendemain, j'avais oublie la maniere de la veille. Une demarche qui revient est un
    script, pas un souvenir.

    CE QU'IL FAIT, pour chaque cible : il dit CE QU'IL LANCE, il le lance de la maniere
    standard, puis il montre OU SE TROUVE LE JOURNAL de la chose et ses dernieres lignes.

    CE QU'IL NE FAIT PAS :
      - il n'ecrit AUCUN journal a lui : celui du programme suffit, en doubler un donne
        deux verites et des lignes en double ;
      - il ne lance ni action ni worker : les executer pour de vrai est un test
        d'integration, qui SE DEMANDE a l'utilisateur (D62, D63) ;
      - il ne s'eleve pas : ce qui est illisible depuis une session ordinaire se demande a
        l'app serveur (ask-vigie.ps1), qui, elle, voit tout.

    USAGE

        pwsh -File scripts/dev/debug.ps1                      # les cibles disponibles
        pwsh -File scripts/dev/debug.ps1 probe gaming         # une sonde, executee
        pwsh -File scripts/dev/debug.ps1 sentinel internet    # une sentinelle + son historique
        pwsh -File scripts/dev/debug.ps1 server               # l'app serveur et son journal
        pwsh -File scripts/dev/debug.ps1 client               # l'app cliente et son journal
        pwsh -File scripts/dev/debug.ps1 install              # la derniere installation
        pwsh -File scripts/dev/debug.ps1 card gaming          # la carte telle que Vigie la rend

    UNE REGLE QUI VAUT POUR TOUT SCRIPT DE CE DEPOT, et que ce fichier applique : on le
    lance dans une VRAIE console, sans rediriger sa sortie. Une sortie redirigee perd ses
    couleurs et s'affiche avec un tour de retard -- ce qui donne l'illusion d'un blocage
    (constate le 01/09 sur l'installation).

    Codes de retour : 0 = la cible a repondu ; 2 = elle n'a rien rendu.
#>
[CmdletBinding()]
param(
    # La famille de ce qu'on examine : probe, sentinel, server, client, install, card.
    [string] $Target,
    # Le nom de la sonde, de la sentinelle ou de la carte, selon la cible.
    [string] $Name,
    # Nombre de lignes de journal a montrer.
    [int] $Lines = 15
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

Write-Title (Get-Label 'debug.titre')

# Les dernieres lignes d'un journal, avec son chemin : c'est ce qu'on veut voir en
# premier quand quelque chose s'est mal passe, et on ne le cherche jamais deux fois.
function Show-Journal {
    param([string]$Path, [int]$Tail = 15)
    if (-not $Path -or -not (Test-PathSafe $Path)) {
        Write-Warn (Get-Label 'debug.journal-absent' $Path)
        return
    }
    Write-Info (Get-Label 'debug.journal' $Path)
    foreach ($l in @(Get-Content -LiteralPath $Path -Tail $Tail -ErrorAction SilentlyContinue)) {
        Write-Detail "$l"
    }
}

# Le journal le plus recent portant ce prefixe, dans le dossier des journaux.
function Get-LatestJournal {
    param([Parameter(Mandatory)][string]$Prefix)
    $dir = Get-LogDir -Backend $backend
    if (-not (Test-PathSafe $dir)) { return $null }
    $f = @(Get-ChildItem -LiteralPath $dir -File -Filter ($Prefix + '*') -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending)[0]
    if ($f) { return $f.FullName }
    return $null
}

$rendu = $false

switch ("$Target".ToLower()) {

    # --- UNE SONDE : on l'execute pour de vrai, par le controleur des sondes ---------
    'probe' {
        Write-Step (Get-Label 'debug.etape-sonde' $Name)
        if (-not $Name) { Write-Fail (Get-Label 'debug.nom-manquant' 'probe'); break }
        Write-Info (Get-Label 'debug.lance' ("scripts/check-probes.ps1 -Only " + $Name))
        & (Join-Path $repoRoot 'scripts/check-probes.ps1') -Only $Name
        $rendu = $true
        Write-Info (Get-Label 'debug.branches-rares')
    }

    # --- UNE SENTINELLE : sa valeur, puis son historique tel que Vigie le rend -------
    'sentinel' {
        Write-Step $(if ($Name) { Get-Label 'debug.etape-sentinelle' $Name } else { Get-Label 'debug.etape-sentinelles' })
        $decls = @(Get-WatchDeclarations -Backend $backend)
        if (-not $Name) {
            foreach ($d in $decls) { Write-Info (Get-Label 'debug.sentinelle-ligne' $d.Key $d.Label $d.Seconds ($d.Cards -join ', ')) }
            $rendu = [bool]$decls.Count
            break
        }
        $d = @($decls | Where-Object { "$($_.Key)" -eq $Name })[0]
        if (-not $d) { Write-Fail (Get-Label 'debug.sentinelle-inconnue' $Name); break }
        Write-Info (Get-Label 'debug.lance' $d.Script)
        $valeur = "$(& $d.Script 2>$null | Select-Object -Last 1)".Trim()
        Write-Ok (Get-Label 'debug.sentinelle-valeur' $Name $valeur)
        # L'HISTORIQUE SE DEMANDE A VIGIE, pas au disque : il vit chez le compte de
        # service, illisible depuis une session ordinaire.
        $id = Get-SentinelMeasureId -Key $Name
        try {
            $session = Open-VigieSession
            $port = [int](Get-Config -Backend $backend).Port
            $h = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/history/$id" + '?window=7d') -WebSession $session -TimeoutSec 20
            Write-Ok (Get-Label 'debug.sentinelle-historique' $id @($h.points).Count)
            foreach ($p in @($h.points | Select-Object -Last $Lines)) {
                Write-Detail (Get-Label 'debug.sentinelle-point' $p.at $p.from $p.v (@($p.cards) -join ', '))
            }
            $rendu = $true
        } catch {
            Write-Warn (Get-Label 'debug.historique-muet' $_.Exception.Message)
        }
    }

    # --- L'APP SERVEUR : debout ou non, et son journal -------------------------------
    'server' {
        Write-Step (Get-Label 'debug.etape-serveur')
        $port = [int](Get-Config -Backend $backend).Port
        $listener = Get-PortListener -Port $port
        if ($listener) { Write-Ok (Get-Label 'debug.serveur-debout' $port) ; $rendu = $true }
        else { Write-Fail (Get-Label 'debug.serveur-muet' $port) }
        Show-Journal -Path (Get-LatestJournal -Prefix 'state') -Tail $Lines
        Write-Info (Get-Label 'debug.serveur-ailleurs')
    }

    # --- L'APP CLIENTE : son processus et son journal --------------------------------
    'client' {
        Write-Step (Get-Label 'debug.etape-client')
        $vus = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
                 Where-Object { "$($_.CommandLine)" -match 'tray\.ps1' })
        if ($vus.Count) { Write-Ok (Get-Label 'debug.client-vivant' $vus.Count) ; $rendu = $true }
        else { Write-Warn (Get-Label 'debug.client-absent') }
        Show-Journal -Path (Get-LatestJournal -Prefix 'tray') -Tail $Lines
    }

    # --- LA DERNIERE INSTALLATION : son etat, puis son propre journal -----------------
    'install' {
        Write-Step (Get-Label 'debug.etape-install')
        & (Join-Path $PSScriptRoot 'deploy-status.ps1')
        Show-Journal -Path (Get-LatestJournal -Prefix 'install_') -Tail $Lines
        $rendu = $true
    }

    # --- UNE CARTE, telle que Vigie la rend a celui qui demande ----------------------
    'card' {
        Write-Step (Get-Label 'debug.etape-carte' $Name)
        if (-not $Name) { Write-Fail (Get-Label 'debug.nom-manquant' 'card'); break }
        & (Join-Path $PSScriptRoot 'ask-vigie.ps1') -Modules -Module $Name
        $rendu = $true
    }

    default {
        # Sans cible, on dit ce qu'on sait faire -- et c'est un succes, pas un echec :
        # celui qui lance le script sans argument a obtenu exactement ce qu'il demandait.
        Write-Step (Get-Label 'debug.etape-cibles')
        $rendu = $true
        foreach ($c in @('probe <id>', 'sentinel [cle]', 'server', 'client', 'install', 'card <id>')) {
            Write-Info (Get-Label 'debug.cible-ligne' $c)
        }
        Write-Info (Get-Label 'debug.console-vraie')
    }
}

if ($rendu) { Write-Outcome -What (Get-Label 'debug.verdict') ; exit 0 }
Write-Outcome -What (Get-Label 'debug.verdict') -Failures 1
exit 2
