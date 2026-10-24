# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, deployment, elevation, paths, var
<#
    Intent: WHAT VIGIE TAKES UP ON THE MACHINE: the program, the data of each account, and the repository on a development workstation. An application that watches other people's disk space owes it to say what it takes itself. The data of other accounts are only readable when elevated: without that we return what is visible and SAY so, rather than announcing a false total.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- WHAT VIGIE TAKES UP ON THE MACHINE --------------------------------------
#
# Asked for on 27/08: "it would be good to show Vigie's storage, for all the users, and so
# follow what our app consumes". An application that watches other people's disk space owes
# it to say what it takes itself.
#
# Three items, and they are not alike:
#   - the PROGRAM : the shared installation (Program Files), the same for everyone;
#   - the DATA    : cache, history, logs -- ONE SET PER ACCOUNT;
#   - the REPOSITORY : on a development workstation, the sources and dist/.
#
# The data of OTHER accounts are only readable when elevated: without elevation we return
# what we can see, and we SAY so rather than announcing a false total.
function Get-VigieFootprint {
    param([string]$Backend = (Get-BackendRoot))

    function Poids {
        param([string]$Path)
        if (-not (Test-PathSafe $Path)) { return 0 }
        try {
            return [long]((Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                           Measure-Object -Property Length -Sum).Sum)
        } catch { return 0 }
    }

    $partagee = Get-SharedInstallPath
    $programme = Poids $partagee

    # Each account's data: %LOCALAPPDATA%\Sowapps\Vigie, and the old location without the
    # publisher's name, for installations from before D72.
    $perAccount = @()
    $inaccessibles = 0
    $currentAccountVar = $null
    foreach ($c in @(Get-UserAccounts -Backend $Backend)) {
        $local = Join-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $c.name) 'AppData\Local'
        $total = 0
        $vu = $false
        foreach ($d in @((Join-Path (Join-Path $local 'Sowapps') 'Vigie'), (Join-Path $local 'Vigie'))) {
            if (Test-PathSafe $d) { $vu = $true; $total += (Poids $d) }
        }
        # A folder present but unreadable gives 0: without elevation it cannot be told from an
        # empty one. So the uncertainty is counted separately.
        if ($vu -and $total -eq 0 -and -not $c.current) { $inaccessibles++ }
        # THE CURRENT ACCOUNT knows where ITS data are: Get-VarRoot is authoritative. On a
        # development workstation they live in the repository (var/), not in %LOCALAPPDATA% --
        # without that we announced 320 bytes for an account taking up megabytes.
        if ($c.current) {
            $sien = Get-VarRoot -Backend $Backend
            if ($sien -and (Test-Path -LiteralPath $sien)) {
                $total = Poids $sien
                $vu = $true
                $currentAccountVar = $sien
            }
        }
        if ($vu) { $perAccount += [pscustomobject]@{ name = $c.name; bytes = $total; current = $c.current } }
    }

    # The development repository, when it is distinct from the shared installation.
    $repositoryRoot = Get-RepoRoot
    $sources = 0
    if ($repositoryRoot -and (-not $partagee -or $repositoryRoot -ne $partagee)) {
        $sources = Poids $repositoryRoot
        # The current account's var/ is ALREADY counted in the data: it is taken out of the
        # repository, or the total counts it twice.
        if ($currentAccountVar -and $currentAccountVar.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $sources = [Math]::Max(0, $sources - (Poids $currentAccountVar))
        }
    }

    $dataBytes = 0
    foreach ($x in $perAccount) { $dataBytes += $x.bytes }

    [pscustomobject][ordered]@{
        programme     = $programme          # installation partagee
        programmePath = $partagee
        data       = $dataBytes            # somme des donnees par compte
        perAccount     = $perAccount
        sources       = $sources            # depot de developpement (0 en usage normal)
        sourcesPath   = $(if ($sources) { $repositoryRoot } else { $null })
        total         = ($programme + $dataBytes + $sources)
        complet       = (Test-IsElevated) -and ($inaccessibles -eq 0)
        inaccessibles = $inaccessibles
    }
}
