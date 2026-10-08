# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    debug.ps1 -- DEBUG ONE PART OF VIGIE, ALWAYS THE SAME WAY.

    Intent: make the way of examining something a script rather than a memory. WHY IT EXISTS: every time
    something did not work, I reinvented the way of looking at it -- a different command line, a log looked for
    by hand, sometimes a second log created for nothing on top of the one the program already writes. The next
    day, I had forgotten yesterday's way. A procedure that comes back is a script, not a memory.

    Usage:

        pwsh -File scripts/dev/debug.ps1                      # the available targets
        pwsh -File scripts/dev/debug.ps1 probe gaming         # a probe, run for real
        pwsh -File scripts/dev/debug.ps1 sentinel internet    # a sentinel plus its history
        pwsh -File scripts/dev/debug.ps1 server               # the server app and its log
        pwsh -File scripts/dev/debug.ps1 client               # the client app and its log
        pwsh -File scripts/dev/debug.ps1 install              # the last installation
        pwsh -File scripts/dev/debug.ps1 card gaming          # the card as Vigie returns it

    Exit codes: 0 = the target answered; 2 = it returned nothing.

    WHAT IT DOES, for each target: it says WHAT IT IS STARTING, it starts it the standard way, then it shows
    WHERE THAT THING'S LOG IS and its last lines.

    WHAT IT DOES NOT DO:
      - it writes NO log of its own: the program's log is enough, doubling one gives two truths and duplicate
        lines;
      - it runs neither an action nor a worker: running those for real is an integration test, which IS ASKED
        FOR by the user (D62, D63);
      - it does not elevate: what is unreadable from an ordinary session is asked of the server app
        (ask-vigie.ps1), which does see everything.

    A RULE THAT HOLDS FOR EVERY SCRIPT IN THIS REPOSITORY, and that this file applies: one runs it in a REAL
    console, without redirecting its output. A redirected output loses its colours and appears one round late --
    which gives the illusion of a deadlock (observed on 01/09 on the installation).
#>



[CmdletBinding()]
param(
    # The family of what we are examining: probe, sentinel, server, client, install, card.
    [string] $Target,
    # The name of the probe, of the sentinel or of the card, depending on the target.
    [string] $Name,
    # How many lines of log to show.
    [int] $Lines = 15
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

Write-Title (Get-Label 'debug.titre')

# The last lines of a log, with its path: that is what one wants to see first when something went wrong, and one
# never looks for it twice.
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

# The most recent log carrying that prefix, in the logs folder.
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

    # --- A PROBE: we run it for real, through the probe checker ---------------
    'probe' {
        Write-Step (Get-Label 'debug.etape-sonde' $Name)
        if (-not $Name) { Write-Fail (Get-Label 'debug.nom-manquant' 'probe'); break }
        Write-Info (Get-Label 'debug.lance' ("scripts/check-probes.ps1 -Only " + $Name))
        & (Join-Path $repoRoot 'scripts/check-probes.ps1') -Only $Name
        $rendu = $true
        Write-Info (Get-Label 'debug.branches-rares')
    }

    # --- A SENTINEL: its value, then its history as Vigie returns it ----------
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
        $value = "$(& $d.Script 2>$null | Select-Object -Last 1)".Trim()
        Write-Ok (Get-Label 'debug.sentinelle-valeur' $Name $value)
        # THE HISTORY IS ASKED OF VIGIE, not of the disc: it lives at the service account's, unreadable from an
        # ordinary session.
        $id = Get-SentinelMeasureId -Key $Name
        try {
            $session = Open-VigieSession
            $port = [int](Get-Config -Backend $backend).Port
            $h = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/history/$id" + '?window=7d') -WebSession $session -TimeoutSec 20
            Write-Ok (Get-Label 'debug.sentinelle-historique' $id @($h.points).Count)
            foreach ($p in @($h.points | Select-Object -Last $Lines)) {
                # IN LOCAL TIME. The history keeps UTC (D44); printed raw, it read two hours early and sent the
                # investigation of 28/09 looking for a game session that had never happened at that hour.
                $when = "$($p.at)"
                try { $when = (ConvertTo-UtcDate $p.at).ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss') } catch { }
                Write-Detail (Get-Label 'debug.sentinelle-point' $when $p.from $p.v (@($p.cards) -join ', '))
            }
            $rendu = $true
        } catch {
            Write-Warn (Get-Label 'debug.historique-muet' $_.Exception.Message)
        }
    }

    # --- THE SERVER APP: up or not, and its log -------------------------------
    'server' {
        Write-Step (Get-Label 'debug.etape-serveur')
        $port = [int](Get-Config -Backend $backend).Port
        $listener = Get-PortListener -Port $port
        if ($listener) { Write-Ok (Get-Label 'debug.serveur-debout' $port) ; $rendu = $true }
        else { Write-Fail (Get-Label 'debug.serveur-muet' $port) }
        Show-Journal -Path (Get-LatestJournal -Prefix 'state') -Tail $Lines
        Write-Info (Get-Label 'debug.serveur-ailleurs')
    }

    # --- THE CLIENT APP: its process and its log ------------------------------
    'client' {
        Write-Step (Get-Label 'debug.etape-client')
        $seen = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
                 Where-Object { "$($_.CommandLine)" -match 'client\.ps1' })
        if ($seen.Count) { Write-Ok (Get-Label 'debug.client-vivant' $seen.Count) ; $rendu = $true }
        else { Write-Warn (Get-Label 'debug.client-absent') }
        Show-Journal -Path (Get-LatestJournal -Prefix 'client') -Tail $Lines
    }

    # --- THE LAST INSTALLATION: its state, then its own log -------------------
    'install' {
        Write-Step (Get-Label 'debug.etape-install')
        & (Join-Path $PSScriptRoot 'deploy-status.ps1')
        Show-Journal -Path (Get-LatestJournal -Prefix 'install_') -Tail $Lines
        $rendu = $true
    }

    # --- A CARD, as Vigie returns it to whoever asks --------------------------
    'card' {
        Write-Step (Get-Label 'debug.etape-carte' $Name)
        if (-not $Name) { Write-Fail (Get-Label 'debug.nom-manquant' 'card'); break }
        & (Join-Path $PSScriptRoot 'ask-vigie.ps1') -Modules -Module $Name
        $rendu = $true
    }

    default {
        # With no target, we say what we know how to do -- and that is a success, not a failure: whoever runs the
        # script with no argument has obtained exactly what they asked for.
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
