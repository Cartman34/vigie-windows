# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses: paths
<#
    Intent: WHERE WHAT THE APP GENERATES MAY BE WRITTEN -- cache, logs, state, generated secrets, all under
    var/. The hard part is not the path, it is the RIGHT to write it: a development repository writes in place,
    a shared installation in Program Files does not, and a standard account then writes in its own profile. We
    do not guess from the path: we try to write, once, and remember (D65).
    Usage: dot-sourced by common.ps1, never run on its own. It asks `paths` where the app is and nothing more.
#>

# --- Runtime data: apps/<app>/var/ (the Symfony convention) --------------------
# Everything the app GENERATES or manages locally lives under var/: cache, logs, state,
# generated secrets. None of it is versioned.
# These paths are written HERE and nowhere else: they used to be recomposed by hand in eight
# files -- actions, probes, workers.
# Is the installation WRITABLE by the account running? (D65)
#
# Two situations, and a single rule to tell them apart: writing for real.
#   - a DEV repository, or an installation in a personal space: var/ is written in place, as
#     it always has been -- nothing changes;
#   - a SHARED installation (Program Files): a standard account does not write there. Its
#     runtime data then go to its profile, where it is at home.
# We do not GUESS from the path: we try to write, once, and remember.
$script:VarRootCache = $null
function Get-VarRoot {
    param([string]$Backend = (Get-BackendRoot))
    # THE CACHE IS PER APPLICATION, not global.
    #
    # It took no account whatever of its argument: the first call froze THE root, and every
    # one after it got that root back whatever -Backend was asked for. The client app
    # therefore wrote its heartbeat into the server's var/, where the order sender did not
    # look for it -- "restart impossible, client app already stopped" while it was running
    # (seen on 28/08). Each app keeps its files under ITS var/ (D33), so the cache has to be
    # indexed by application.
    if ($null -eq $script:VarRootCache) { $script:VarRootCache = @{} }
    $cle = "$Backend".TrimEnd([char]92, [char]47).ToLowerInvariant()
    if ($script:VarRootCache.ContainsKey($cle)) { return $script:VarRootCache[$cle] }

    # INSTALLED IN PROGRAM FILES: the data go into the account's profile, NEVER beside the
    # program. The server runs elevated, so it COULD write there -- and that is precisely the
    # trap: every account would then share the same token, the same cache and the same
    # settings, when each must have its own (D65). The write test below would see nothing,
    # since it would succeed.
    $programmes = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($p in $programmes) {
        if ("$Backend".StartsWith("$p", [StringComparison]::OrdinalIgnoreCase)) {
            $script:VarRootCache[$cle] = Join-Path (Get-UserConfigDir) 'var'
            return $script:VarRootCache[$cle]
        }
    }

    # Elsewhere -- a development repository, a personal folder: in place when it can be
    # written to, otherwise in the profile.
    $surPlace = Join-Path $Backend 'var'
    $ok = $false
    try {
        if (-not (Test-Path -LiteralPath $surPlace)) {
            New-Item -ItemType Directory -Path $surPlace -Force -WhatIf:$false | Out-Null
        }
        $temoin = Join-Path $surPlace ('.ecriture-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        [IO.File]::WriteAllText($temoin, 'x')
        Remove-Item -LiteralPath $temoin -Force -ErrorAction SilentlyContinue
        $ok = $true
    } catch { $ok = $false }
    $script:VarRootCache[$cle] = if ($ok) { $surPlace } else { Join-Path (Get-UserConfigDir) 'var' }
    return $script:VarRootCache[$cle]
}

function Get-VarPath {
    param(
        [string]$Backend = (Get-BackendRoot),
        <#
            ANOTHER ACCOUNT'S ROOT, when one must write somewhere other than at home.

            The var of an installation inside Program Files lives in the profile of the
            account that RUNS (D65): the service's, for the server app. The installation, on
            the other hand, runs under the person who clicked -- so it cleaned THEIR cache
            while the card went on reading the service's. Get-AccountVarRoot gives the right
            root, and it goes through here rather than being recomposed by hand.
        #>
        [string]$VarRoot,
        # 'history': series of measurements. Distinct from 'cache': a lost cache recomputes
        # itself, a lost history does not.
        # 'run': LIVE state, valid for the length of a process (background-task marks). It is
        # not backed up and not read back after a restart.
        [Parameter(Mandatory)][ValidateSet('cache','log','secrets','history','run')][string]$Kind,
        [string]$File
    )
    $dir = Join-Path $(if ($VarRoot) { $VarRoot } else { Get-VarRoot -Backend $Backend }) $Kind
    # TEST-PATHSAFE, AND A CREATION THAT DOES NOT SHOUT. On ANOTHER account's var, Test-Path
    # THROWS instead of answering "no", and New-Item writes four red blocks -- when all we
    # were doing was reading a path to erase a file inside it. A caller without the right
    # will notice by finding nothing there, without polluting the log.
    if (-not (Test-PathSafe $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false -ErrorAction SilentlyContinue | Out-Null
    }
    if ($File) { return (Join-Path $dir $File) }
    return $dir
}

function Get-UserConfigDir {
    # Vigie is an application of SOWAPPS: its data live under the publisher's name, like those
    # of any installed software (Publisher\Product).
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    $d = Join-Path (Join-Path $base 'Sowapps') 'Vigie'
    if (-not (Test-Path -LiteralPath $d)) {
        try { New-Item -ItemType Directory -Path $d -Force -WhatIf:$false | Out-Null } catch { }
        # Taking over the previous location, without the publisher: nobody is to lose their
        # settings because the filing changed.
        $ancien = Join-Path $base 'Vigie'
        if ((Test-Path -LiteralPath $ancien) -and (Test-Path -LiteralPath $d)) {
            try {
                foreach ($x in (Get-ChildItem -LiteralPath $ancien -Force -ErrorAction SilentlyContinue)) {
                    $targetPath = Join-Path $d $x.Name
                    if (-not (Test-Path -LiteralPath $targetPath)) { Move-Item -LiteralPath $x.FullName -Destination $targetPath -Force }
                }
            } catch { }
        }
    }
    $d
}
