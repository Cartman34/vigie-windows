# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: WHAT A CARD AND AN APP ARE CALLED on screen, and the tooltip that goes with them: read from the declarations, never spelled out twice.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- The contract's object factories ----------------------------------------
# A process name -> the READABLE name, the one Windows itself displays.
#
# "csrss" means nothing to anybody (pointed out by the owner on 25/08). The real name is in
# the executable's version information (FileDescription): "Client Server Runtime Process",
# "Windows Explorer", "Google Chrome". It is read from the FILE and not from the process:
# protected processes (csrss, lsass) refuse access to their main module, while their file
# reads without trouble.
#
# The technical name is not thrown away: it is kept in brackets, because that is the one
# found again in the Task Manager.
$script:AppNameCache = @{}
function Get-AppDisplayName {
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [string]$Path,
        # Without -Complet, only the readable name is returned (for a short field value).
        [switch]$Complet
    )
    $cle = $ProcessName.ToLower()
    if (-not $script:AppNameCache.ContainsKey($cle)) {
        $desc = $null
        $exe = $Path
        if (-not $exe) {
            # A protected process: its path is refused, but a system binary of the same name
            # reads perfectly well. We do not GUESS: we check the file exists.
            $candidat = Join-Path $env:SystemRoot ("System32\" + $ProcessName + ".exe")
            if (Test-Path -LiteralPath $candidat) { $exe = $candidat }
        }
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            try {
                $d = "$([System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileDescription)".Trim()
                if ($d -and $d -ne $ProcessName) { $desc = $d }
            } catch { }
        }
        $script:AppNameCache[$cle] = $desc
    }
    $lisible = $script:AppNameCache[$cle]
    if (-not $lisible) {
        # For want of better, the process name is displayed -- but with a CAPITAL: on screen
        # it is a proper noun ("Claude", not "claude"), and a card's value always begins
        # with a capital.
        if ($ProcessName.Length -gt 1) { return $ProcessName.Substring(0,1).ToUpper() + $ProcessName.Substring(1) }
        return $ProcessName.ToUpper()
    }
    if ($Complet) { return "$lisible ($ProcessName)" }
    return $lisible
}

# What is said of an application when its name is hovered: the ABSOLUTE path first, as the
# owner asked, then publisher and version, then the real processes behind the name.
#
# HOMONYMS: two processes of the same name may come from TWO different binaries -- two
# installations of chrome, a fake "svchost" laid somewhere other than System32. We do not
# choose in the user's place: every distinct location is named, and the fact that there is
# more than one is announced.
function Get-AppInfoTip {
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [string[]]$Paths = @(),
        [int[]]$Ids = @()
    )
    $lines = @()
    $cleanPaths = @($Paths | Where-Object { $_ } | Sort-Object -Unique)
    if ($cleanPaths.Count -eq 0) {
        # A protected process (csrss, lsass...): Windows refuses its path. If a system binary
        # of the same name EXISTS, it is named -- while saying it is the expected binary and
        # not the path read; the nuance matters to whoever is hunting an impostor.
        $sys = Join-Path $env:SystemRoot ("System32\" + $ProcessName + ".exe")
        if (Test-Path -LiteralPath $sys) {
            $lines += "Chemin non communiqué (processus protégé par Windows)."
            $lines += "Binaire système attendu : $sys"
            $cleanPaths = @($sys)
        } else {
            $lines += "Chemin : non communiqué (processus protégé par Windows)."
        }
    } elseif ($cleanPaths.Count -eq 1) {
        $lines += "$($cleanPaths[0])"
    } else {
        $lines += "$($cleanPaths.Count) emplacements différents pour ce nom :"
        foreach ($c in ($cleanPaths | Select-Object -First 4)) { $lines += "- $c" }
    }
    $ref = @($cleanPaths | Select-Object -First 1)[0]
    if ($ref -and (Test-Path -LiteralPath $ref)) {
        try {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ref)
            $editeur = "$($vi.CompanyName)".Trim()
            $version = "$($vi.FileVersion)".Trim()
            $detail = @($editeur, $version | Where-Object { $_ }) -join ' · '
            if ($detail) { $lines += $detail }
        } catch { }
    }
    $pids = @($Ids | Where-Object { $_ -gt 0 })
    if ($pids.Count -eq 1) { $lines += "1 processus (PID $($pids[0]))" }
    elseif ($pids.Count -gt 1) {
        $seen = @($pids | Select-Object -First 6) -join ', '
        $nextArgs = if ($pids.Count -gt 6) { '…' } else { '' }
        $lines += "$($pids.Count) processus (PID $seen$nextArgs)"
    }
    $lines -join "`n"
}
