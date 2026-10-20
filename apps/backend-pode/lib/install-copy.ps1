# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, config, paths, var, version
<#
    Intent: COPYING AN INSTALLATION WITHOUT LOSING THE ONE IN PLACE: the lock that keeps two installations from running at once, the backup taken first, the archive expanded, the files copied, the surplus removed, and the restore that puts back what was there. The gestures only; WHETHER to deploy is decided by deployment.ps1.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    RESTARTING THE SERVER APP -- ONE SINGLE IMPLEMENTATION.

    It lived inside the "server-restart" action. The update needed it too, and copying it
    would have made two paths for one gesture: the day one is fixed, the other lies. So it
    lives here, and both call the same one.

    ONE CANNOT KILL AND RESTART ONESELF: a dying process runs nothing more. A DETACHED
    RELAUNCHER does it -- it stops the server, waits for the port to be released, then starts
    the next one. It waits for the PORT and not for a delay: with two servers on the same
    port, it is the second that dies.

    -Wait: wait until no operation holds the machine any more. Deliberately with no time
    limit -- an operation that lasts has a reason to last, and interrupting it is precisely
    what we want to avoid. That is how the update restarts itself: it asks for the restart as
    it begins, and the relauncher waits until it has finished.

    THE PID COMES FROM THE PORT, not from $PID: the caller is not always the server. The
    start script, on the other hand, is SAID by the caller -- it is the one of the running
    installation, not necessarily the one of the repository being spoken from.
#>
<#
    STOPPING THE SERVER APP, AND OBSERVING THAT IT IS STOPPED.

    Its files were modified while it was running, and it was only stopped afterwards, when
    putting the task back into service. So code was overwritten under a living process -- it
    carried on with the old one in memory, and the slightest file re-read along the way mixed
    two versions.

    A STOP IS OBSERVED. The port being released is a fact: we wait for it, unlike a start,
    which is never watched for. And the TASK is stopped first -- otherwise Windows considers
    it running and restarts it under our feet.

    Returns $true when nothing listens any more at the end.
#>
<#
    THE INSTALLATION LOCK -- ONE AT A TIME.

    Two simultaneous installations tread on each other: one stops what the other has just
    started, one copies while the other backs up. Preventing it is imperative.

    THE LOCK SAYS WHO HOLDS IT -- a process id and a time -- and a lock whose process no
    longer exists is IGNORED. Without that, an installation interrupted brutally would
    condemn the workstation until someone deleted a file by hand, which we forbid ourselves:
    what is missing is missing from the installation, never from a command to type.

    It lives with the computer's declaration, outside the shared installation: it must
    survive a copy and stay readable by both entry points.
#>
function Get-InstallLockPath {
    Join-Path (Split-Path (Get-ComputerConfigPath) -Parent) 'install.lock'
}

function Get-InstallLockHolder {
    $path = Get-InstallLockPath
    if (-not (Test-PathSafe $path)) { return $null }
    $held = $null
    try { $held = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $held -or -not $held.pid) { return $null }
    # DOES THE PROCESS STILL EXIST? It is the only question that matters: an orphan lock
    # protects nothing, it blocks.
    $alive = $false
    try { $alive = [bool](Get-Process -Id ([int]$held.pid) -ErrorAction Stop) } catch { }
    if (-not $alive) { return $null }
    return $held
}

function Lock-Install {
    $held = Get-InstallLockHolder
    if ($held) { return $null }
    $path = Get-InstallLockPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $mine = [ordered]@{ pid = $PID; account = (Get-ProcessAccount); at = (Get-Date).ToUniversalTime().ToString('o') }
    ($mine | ConvertTo-Json -Compress) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Unlock-Install {
    # WE ONLY REMOVE OUR OWN. Removing someone else's would allow exactly what we have just
    # forbidden.
    $path = Get-InstallLockPath
    if (-not (Test-PathSafe $path)) { return }
    try {
        $held = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($held -and [int]$held.pid -ne $PID) { return }
    } catch { }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

<#
    BACK UP, CHECK, RESTORE.

    The copy overwrites the installation in place: if it fails halfway, the old version is
    already destroyed and we would start an incomplete installation.

    The backup lives OUTSIDE the shared installation -- otherwise it would double the volume
    and the next backup would back it up -- and carries the version it holds, so one knows
    what is being restored. It is removed as soon as the copy is checked: it exists only for
    the length of the risk.
#>
function Get-InstallBackupRoot {
    <#
        OUTSIDE THE INSTALLATION, ALWAYS.

        The backup used to live under the server app's var/, that is, INSIDE the folder it
        serves to restore: the safety net was tied to the trapeze. Three ways to lose it: a
        copy overwriting the folder takes the backup with it, an uninstall does the same, and
        the setup.cmd of the installed folder cannot restore what that same folder held.

        So it lives at MACHINE scale, where machine.psd1 already lives: the source folder may
        disappear, the installation may be replaced, the previous version stays.
    #>
    Join-Path (Get-ComputerDataRoot) 'backup'
}

function Backup-Install {
    param([Parameter(Mandatory)][string]$Source, [string]$Backend = (Get-BackendRoot))
    if (-not (Test-PathSafe $Source)) { return $null }
    # THE OLD LOCATION DOES NOT SURVIVE AN INSTALLATION. It was under the server app's var/;
    # leaving it there means keeping a whole copy of Vigie that nothing reads any more and
    # nobody thinks to erase. The installation cleans it up, being idempotent -- no command
    # to type by hand.
    $ancien = Join-Path (Get-VarRoot -Backend $Backend) 'backup'
    if (Test-Path -LiteralPath $ancien) {
        Remove-Item -LiteralPath $ancien -Recurse -Force -ErrorAction SilentlyContinue
    }
    $stamp = Get-BuildStamp -Root $Source
    $name = 'installation-' + $(if ($stamp.version) { "$($stamp.version)" -replace '[^\w\.\+-]', '_' } else { 'inconnue' })
    $root = Get-InstallBackupRoot -Backend $Backend
    $dest = Join-Path $root $name
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $dest -Recurse -Force -ErrorAction Stop
    return $dest
}

<#
    IS THE COPY VALID? We do not ask whether it "seems" done: we read the version stamp we
    were expecting, and the files without which Vigie does not start.
#>
function Test-InstallCopy {
    param([Parameter(Mandatory)][string]$Destination, [string]$ExpectedVersion)
    foreach ($needed in @('apps/backend-pode/start.ps1', 'apps/client/client.ps1', 'apps/backend-pode/lib/common.ps1')) {
        if (-not (Test-PathSafe (Join-Path $Destination $needed))) { return ("fichier manquant : " + $needed) }
    }
    if ($ExpectedVersion) {
        $stamp = Get-BuildStamp -Root $Destination
        if (-not (Test-SameVersion -A "$($stamp.version)" -B $ExpectedVersion)) {
            return ("version posée « " + "$($stamp.version)" + " » au lieu de « " + $ExpectedVersion + " »")
        }
    }
    return $null
}

<#
    EXTRACT AN ARCHIVE, AND RETURN THE FOLDER THAT WILL BE DEPLOYED.

    The archive carries a root folder "vigie-<version>": it is ITS contents that are
    installed, not one more folder inside Program Files.
#>
function Expand-InstallArchive {
    param([Parameter(Mandatory)][string]$Zip)
    if (-not (Test-PathSafe $Zip)) { throw ("archive introuvable : " + $Zip) }
    $temp = Join-Path $env:TEMP ('vigie-deploy-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $temp -Force
    $roots = @(Get-ChildItem -Path $temp -Directory)
    if ($roots.Count -eq 1) { return $roots[0].FullName }
    return $temp
}

<#
    COPY TO THE SHARED INSTALLATION, WITHOUT LOSING THE COMPUTER'S SETTINGS.

    The settings laid on this machine survive the deployment: set aside, then put back.
    Overwriting them at every delivery would be a regression at every update.

    var/ does not exist in the installation -- the data live in the profiles (D97) -- but it
    is not deleted if someone has created one: we only destroy what we know how to replace.
#>
<#
    WHAT THE SOURCE NO LONGER HAS, REMOVED WHEREVER IT IS.

    Walks the installation and the source side by side. A folder the source does not have goes whole; inside a folder
    both have, each file the source lacks goes. `var/` is never entered: it is the data.

    It is a function of its own so the rule can be read -- and tested -- without running an installation.
#>
function Remove-InstallSurplus {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Destination) -or -not (Test-PathSafe $Source)) { return }
    foreach ($entry in @(Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue)) {
        if ($entry.Name -eq 'var') { continue }
        $mirror = Join-Path $Source $entry.Name
        if (-not (Test-Path -LiteralPath $mirror)) {
            Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }
        # BOTH SIDES HAVE IT: a folder is walked, a file is left to be overwritten by the copy that follows.
        if ($entry.PSIsContainer) { Remove-InstallSurplus -Source $mirror -Destination $entry.FullName }
    }
}

function Copy-InstallFrom {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Source)) { throw ("source introuvable : " + $Source) }

    $kept = $null
    $configDir = Join-Path $Destination 'config'
    if (Test-PathSafe $configDir) {
        $kept = Join-Path $env:TEMP ('vigie-cfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $kept -Force | Out-Null
        foreach ($pattern in @('*.local.*', 'actions.policy.json')) {
            Get-ChildItem -Path $configDir -File -Filter $pattern -ErrorAction SilentlyContinue |
                ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $kept -Force }
        }
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    <#
        WHAT THE SOURCE NO LONGER HAS, THE INSTALLATION NO LONGER KEEPS.

        Copy-Item only adds and overwrites: a file dropped upstream stayed on disk for ever. On 30/09 the client app's
        folder was renamed, the old one survived in the installation, the account's scheduled task went on naming the
        old script -- it still existed, so nothing was declared broken -- and TWO client apps ran at once on the same
        account, each with its icon and its heartbeat.

        AT EVERY DEPTH, and that took a second lesson. The first version dropped only at the top level and inside
        apps/, which left everything below untouched: on 06/10 an action deleted from the source and pushed stayed
        installed and ANSWERING after a successful deployment. An action is a door with rights of its own, and
        removing it from the source is the gesture that deletes it; the same goes for a probe, which would keep
        producing a card, and for a worker, which would stay launchable. The requirement that the shared
        installation carry exactly the source's commit (targeting/install-update.md) was therefore false below two levels.

        var/ is the one thing kept: it is the data, not the code. The settings of this machine are set aside before
        and put back after, so they survive this. Nothing outside the destination is ever touched.
    #>
    Remove-InstallSurplus -Source $Source -Destination $Destination
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force -ErrorAction Stop

    if ($kept) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Get-ChildItem -Path $kept -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $configDir -Force
        }
        Remove-Item -LiteralPath $kept -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Restore-Install {
    param([Parameter(Mandatory)][string]$Backup, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Backup)) { throw "aucune sauvegarde à restaurer" }
    Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'var' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item -Path (Join-Path $Backup '*') -Destination $Destination -Recurse -Force -ErrorAction Stop
}
