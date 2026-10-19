# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, config, format, paths, var, version
<#
    Intent: DEPLOYING AND PUTTING BACK: the clone the service reads, the archive expanded over the shared installation, the lock that keeps two deployments apart, the backup taken before and the restore that uses it.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    DECLARING THE TRUSTED REPOSITORY TO GIT, AT THE SCALE OF THE COMPUTER.

    Since git 2.35, git refuses to open a repository belonging to someone else: "detected
    dubious ownership". The server app runs under a service account and the repository belongs
    to a person -- measured on 30/08, even READING is refused, so the service clone could not
    be created at all.

    The refusal is lifted for THAT path, and nothing else. It is not a write permission: the
    ACLs do not move, and the service never writes in that repository -- the tag is laid in
    the owner's session (D112).

    Laid at machine scale, where the computer already declares where its code comes from: the
    declaration and the trust are the same gesture.
#>
function Set-GitSafeDirectory {
    param([Parameter(Mandatory)][string]$RepoPath)
    <#
        TWO PATHS, NOT ONE.

        Declaring the working folder is not enough: on a LOCAL CLONE, git opens
        "<repo>/.git" and that is the path it checks -- its refusal names it word for word.
        With the single "<repo>" entry, the service clone stayed refused after being
        declared (seen on 30/08, three deployments in a row).
    #>
    $rootPath = "$RepoPath".Replace([char]92, [char]47).TrimEnd([char]47)
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory')) |
              ForEach-Object { "$_".Replace([char]92, [char]47).TrimEnd([char]47) }
    $added = $false
    foreach ($wanted in @($rootPath, ($rootPath + '/.git'))) {
        if ($declared -contains $wanted) { continue }
        $null = Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--add', 'safe.directory', $wanted)
        if (Get-GitLastError) { throw (Get-GitLastError) }
        $added = $true
    }
    return $added
}

<#
    THE RIGHT "LOG ON AS A BATCH JOB" (SeBatchLogonRight), granted or revoked through secedit. A task registered with
    a password starts only if its account holds it; the uninstall takes it back, so that no right outlives the
    account. No display here: the caller says what was done. Returns ok, changed and error.
#>
function Set-BatchLogonRight {
    param([Parameter(Mandatory)][string]$Sid, [switch]$Revoke)
    $stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $exportFile = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '.inf')
    $importFile = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '-import.inf')
    $database   = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '.sdb')
    try {
        $out = & secedit.exe /export /areas USER_RIGHTS /cfg $exportFile 2>&1
        if (-not (Test-Path -LiteralPath $exportFile)) {
            return [pscustomobject]@{ ok = $false; changed = $false; error = (@($out) -join ' ') }
        }
        $line = Get-Content -LiteralPath $exportFile | Where-Object { $_ -match '^SeBatchLogonRight' } | Select-Object -First 1
        $holders = @()
        if ($line) { $holders = @((($line -split '=', 2)[1]).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $mine = '*' + $Sid
        $has = $holders -contains $mine
        if ($Revoke) {
            if (-not $has) { return [pscustomobject]@{ ok = $true; changed = $false; error = $null } }
            $holders = @($holders | Where-Object { $_ -ne $mine })
        } else {
            if ($has) { return [pscustomobject]@{ ok = $true; changed = $false; error = $null } }
            $holders += $mine
        }
        # A MINIMAL POLICY FILE: only the line we are about.
        $content = @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1',
                     '[Privilege Rights]', ('SeBatchLogonRight = ' + ($holders -join ','))) -join [Environment]::NewLine
        [IO.File]::WriteAllText($importFile, $content, [Text.Encoding]::Unicode)
        $out = & secedit.exe /configure /db $database /cfg $importFile /areas USER_RIGHTS 2>&1
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ ok = $false; changed = $false; error = (@($out) -join ' ') } }
        return [pscustomobject]@{ ok = $true; changed = $true; error = $null }
    } catch {
        return [pscustomobject]@{ ok = $false; changed = $false; error = $_.Exception.Message }
    } finally {
        foreach ($f in @($exportFile, $importFile, $database)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

<#
    THE TRUST GIVEN TO A SOURCE IS TAKEN BACK WHEN THE SOURCE CHANGES. Set-GitSafeDirectory adds two entries per
    repository; they piled up, one pair per source ever used (seen on 13/09). This removes exactly those two.
#>
function Remove-GitSafeDirectory {
    param([Parameter(Mandatory)][string]$RepoPath)
    $rootPath = "$RepoPath".Replace([char]92, [char]47).TrimEnd([char]47)
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory')) |
                ForEach-Object { "$_".Replace([char]92, [char]47).TrimEnd([char]47) }
    $removed = $false
    foreach ($unwanted in @($rootPath, ($rootPath + '/.git'))) {
        if ($declared -notcontains $unwanted) { continue }
        $null = Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--unset-all', 'safe.directory', ('^' + [regex]::Escape($unwanted) + '$'))
        if (-not (Get-GitLastError)) { $removed = $true }
    }
    return $removed
}

<#
    THE ONLY TRUST VIGIE KEEPS IS THE DECLARED SOURCE'S. Every other pair Set-GitSafeDirectory wrote -- "<folder>" and
    "<folder>/.git", on a local path -- is taken back: a folder gone, a worktree left, a copy that is not a repository
    (answered by the owner on 14/09). A single entry belongs to another tool, and a path that is not of this computer
    cannot be judged from here. Without -KeepPath, only the pairs of folders that are gone are removed. Returns the
    folders taken back.
#>
function Remove-StaleGitSafeDirectory {
    param([string]$KeepPath = '')
    $keep = "$KeepPath".Replace([char]92, [char]47).TrimEnd([char]47)
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory') |
                  ForEach-Object { "$_".Replace([char]92, [char]47).TrimEnd([char]47) } | Where-Object { $_ })
    $removed = @()
    foreach ($entry in $declared) {
        if ($entry.EndsWith('/.git') -or $declared -notcontains ($entry + '/.git')) { continue }
        if ($entry -notmatch '^[A-Za-z]:/') { continue }
        if ($keep) { if ($entry -ieq $keep) { continue } }
        elseif (Test-Path -LiteralPath $entry) { continue }
        if (Remove-GitSafeDirectory -RepoPath $entry) { $removed += $entry }
    }
    return $removed
}

function Get-ServiceClonePath {
    param([string]$Backend = (Get-BackendRoot))
    Join-Path (Join-Path (Get-VarRoot -Backend $Backend) 'update') 'depot'
}

<#
    THE ADDRESS THE CLONE SYNCHRONISES FROM.

    In production: the public repository. On a development workstation: the local repository,
    so that what has just been written can be built without pushing it first. The same
    mechanism, only the address changes -- it is a setting, not a second design.
#>
function Get-UpdateRemote {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = Get-Config -Backend $Backend
    $remoteUrl = "$($cfg.UpdateRemote)".Trim()
    if ($remoteUrl) { return $remoteUrl }
    $repo = Get-LocalRepoPath -Backend $Backend
    if ($repo) { return $repo }
    return "$($cfg.RepositoryUrl)"
}

<#
    THE SERVICE CLONE IS NEVER BLOCKED. The required behaviour: doc/progress/targeting/install-update.md, in the
    section bearing that name. It is a copy the service owns alone: it mirrors the declared source, it never
    resists it.

    On 13/09 it refused the version tags a history rewrite had moved, and deployment stopped for good. Fetching is
    therefore FORCED; if git still refuses while the source answers, the clone is rebuilt beside the old one, which
    is replaced only once the new one exists. A source that does not answer leaves the clone in place, with git's
    own words.

    Returns ok, error and recloned.
#>
function Update-ServiceClone {
    param([string]$Backend = (Get-BackendRoot), [string]$RemoteUrl = '', [switch]$Reset)
    $cloneDir = Get-ServiceClonePath -Backend $Backend
    if (-not $RemoteUrl) { $RemoteUrl = Get-UpdateRemote -Backend $Backend }
    $parentDir = Split-Path $cloneDir -Parent
    if (-not (Test-Path -LiteralPath $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

    if (-not $Reset -and (Test-PathSafe (Join-Path $cloneDir '.git'))) {
        $null = Invoke-Git -Path $cloneDir -Arguments @('rev-parse', '--git-dir')
        if (-not (Get-GitLastError)) {
            # The address may have changed -- dev and prod, another folder: it is set before fetching.
            $null = Invoke-Git -Path $cloneDir -Arguments @('remote', 'set-url', 'origin', $RemoteUrl)
            $null = Invoke-Git -Path $cloneDir -Arguments @('fetch', '--quiet', '--force', '--prune', '--prune-tags', '--tags', 'origin')
            $refused = Get-GitLastError
            if (-not $refused) {
                return [pscustomobject][ordered]@{ ok = $true; error = $null; recloned = $false }
            }
            # UNREACHABLE, OR REFUSED? Only a source that answers justifies rebuilding the clone.
            $null = Invoke-Git -Path $cloneDir -Arguments @('ls-remote', '--quiet', $RemoteUrl, 'HEAD')
            if (Get-GitLastError) {
                return [pscustomobject][ordered]@{ ok = $false; error = $refused; recloned = $false }
            }
        }
    }

    # A FRESH CLONE BESIDE THE OLD ONE: the old one goes only once the new one exists.
    $fresh = $cloneDir + '.new'
    if (Test-Path -LiteralPath $fresh) { Remove-Item -LiteralPath $fresh -Recurse -Force -ErrorAction SilentlyContinue }
    $null = Invoke-Git -Path $parentDir -Arguments @('clone', '--quiet', $RemoteUrl, $fresh)
    $cloneError = Get-GitLastError
    if ($cloneError) {
        Remove-Item -LiteralPath $fresh -Recurse -Force -ErrorAction SilentlyContinue
        return [pscustomobject][ordered]@{ ok = $false; error = $cloneError; recloned = $false }
    }
    try {
        if (Test-Path -LiteralPath $cloneDir) { Remove-Item -LiteralPath $cloneDir -Recurse -Force -ErrorAction Stop }
        Move-Item -LiteralPath $fresh -Destination $cloneDir -ErrorAction Stop
    } catch {
        return [pscustomobject][ordered]@{ ok = $false; error = $_.Exception.Message; recloned = $false }
    }
    return [pscustomobject][ordered]@{ ok = $true; error = $null; recloned = $true }
}
<#
    SYNCHRONISING THE CLONE, AND SAYING WHAT IT HOLDS.

    "If it does not update the service's repository first, it is no use: it has to see the
    commits of the dev repository." Exactly -- comparing against a stale clone compares
    nothing. So it is refreshed BEFORE being read, with a short respite: from a local
    repository a fetch costs a few hundred milliseconds, but a card must not pay that at every
    display. The "Refresh" button (-Force) forces it.

    Returns the stamp (version, commit) of the reference aimed at, or $null with git's error.
#>
function Sync-ServiceClone {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force, [int]$TtlSeconds = 300)
    $cloneDir  = Get-ServiceClonePath -Backend $Backend
    $remoteUrl = Get-UpdateRemote -Backend $Backend
    $wantedRef    = "$((Get-Config -Backend $Backend).UpdateRef)".Trim()
    $stampFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'clone-sync.json'

    <#
        THE RESPITE FOLLOWS THE DISTANCE, NOT A CONSTANT.

        Five minutes are justified for a remote repository: a fetch goes over the network.
        From a LOCAL REPOSITORY -- a development workstation -- it costs a few hundred
        milliseconds, and five minutes mostly mean the card goes on showing "up to date" long
        after a commit. Added to the probe's own respite, the gap could reach ten minutes.
    #>
    #>
    if ($remoteUrl -and $remoteUrl -notmatch '^[a-z]+://' -and (Test-PathSafe $remoteUrl)) { $TtlSeconds = 30 }

    if (-not $Force -and (Test-Path -LiteralPath $stampFile)) {
        try {
            $j = Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalSeconds
            if ($age -lt $TtlSeconds -and "$($j.remote)" -eq $remoteUrl) {
                return [pscustomobject][ordered]@{ path = $cloneDir; remote = $remoteUrl; ref = "$($j.ref)"
                                                   version = "$($j.version)"; commit = "$($j.commit)"
                                                   error = $(if ($j.error) { "$($j.error)" } else { $null }) }
            }
        } catch { }
    }

    $failure = $null
    # THE CLONE IS NEVER BLOCKED: forced, then recloned if git still refuses (Update-ServiceClone).
    $update = Update-ServiceClone -Backend $Backend -RemoteUrl $remoteUrl
    if (-not $update.ok) { $failure = $update.error }
    $tagVersion = $null; $headCommit = $null
    if (Test-PathSafe (Join-Path $cloneDir '.git')) {
        # With no reference imposed, we follow the remote's default branch.
        $target = $(if ($wantedRef) { $wantedRef } else { 'origin/HEAD' })
        $headCommit = @(Invoke-Git -Path $cloneDir -Arguments @('rev-parse', $target) | Select-Object -First 1)[0]
        if (-not $headCommit -and -not $wantedRef) {
            $headCommit = @(Invoke-Git -Path $cloneDir -Arguments @('rev-parse', 'origin/main') | Select-Object -First 1)[0]
        }
        if ($headCommit) {
            $tagVersion = @(Invoke-Git -Path $cloneDir -Arguments @('describe', '--tags', "$headCommit") | Select-Object -First 1)[0]
            if ($tagVersion -and $tagVersion -match '^(.*)-(\d+)-g[0-9a-f]+$') { $tagVersion = ($Matches[1] + '+' + $Matches[2]) }
        } else {
            $failure = Get-GitLastError
        }
    }

    <#
        A FAILURE IS NOT RECORDED FOR FIVE MINUTES.

        The respite exists so a successful fetch is not redone at every display. A FAILURE,
        on the other hand, is often repaired by one gesture -- declaring the repository
        trusted to git, for instance: freezing it would make the card lie for five more
        minutes when everything is already back in order. It is returned, not frozen.
    #>
    if (-not $failure) {
        try {
            (@{ at = (Get-Date).ToUniversalTime().ToString('o'); remote = $remoteUrl; ref = $wantedRef
                version = $tagVersion; commit = $headCommit; error = $null } | ConvertTo-Json) |
                Set-Content -LiteralPath $stampFile -Encoding UTF8
        } catch { }
    }

    return [pscustomobject][ordered]@{ path = $cloneDir; remote = $remoteUrl; ref = $wantedRef
                                       version = $tagVersion; commit = $headCommit; error = $failure }
}

function Get-UpdateRoute {
    param([string]$Backend = (Get-BackendRoot))
    $choice = 'auto'
    try {
        $c = "$((Get-Config -Backend $Backend).UpdateSource)".Trim().ToLowerInvariant()
        if ($c -in @('auto', 'local', 'release', 'clone')) { $choice = $c }
    } catch { }
    $repo = Get-LocalRepoPath -Backend $Backend
    # "LOCAL" IS NO LONGER A ROUTE FOR THE SERVICE (D112): building inside a person's
    # repository means writing tags there under a service identity, and being refused by git.
    # A declared repository therefore becomes the clone's ADDRESS, not the place of work.
    if ($choice -eq 'local') { $choice = 'clone' }
    if ($choice -eq 'auto')  { $choice = $(if ($repo) { 'clone' } else { 'release' }) }
    return [pscustomobject][ordered]@{ route = $choice; repo = $repo }
}

# Is the shared installation up to date against this repository? It returns a readable
# observation, never a bare boolean: "the same", "12 commits behind", "unknown".
<#
    IS THE SHARED INSTALLATION UP TO DATE -- AND AGAINST WHAT?

    The reference is not the same everywhere, and that was the whole defect: the comparison
    was always against "Get-RepoRoot", which IS the installation when the server app runs
    inside it.

      - a repository exists on the workstation -> reference "repository": commits compared;
      - otherwise -> reference "published": on an ordinary machine the only thing that makes
        sense is the latest published version.

    Nothing is guessed: when it cannot be settled, `same` is $null and the caller SAYS so.
    "Up to date" by default is the worst of verdicts -- it reassures while knowing nothing.
#>
function Compare-SharedInstall {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force)
    $installed = Get-SharedInstallPath
    if (-not $installed) { return $null }
    $there   = Get-BuildStamp -Root $installed
    $route   = Get-UpdateRoute -Backend $Backend
    $behind  = $null
    $here    = $null
    $same    = $null
    $reference = 'aucune'
    $remote  = $null

    # WE COMPARE AGAINST WHAT THE BUTTON WOULD FETCH, never against anything else.
    if ($route.route -eq 'clone') {
        # AND WE REFRESH BEFORE READING: comparing against a stale clone compares nothing.
        $sync = Sync-ServiceClone -Backend $Backend -Force:$Force
        $reference = 'clone'
        $remote = $sync.remote
        # WHAT ARRIVES, as it will read on the installation: "v1.1.5+3" in dev, since a deployment tags nothing (D123).
        $here = [pscustomobject][ordered]@{ version = $(if ($sync.version) { "$($sync.version)" } else { 'sans version' })
                                            commit = $sync.commit; at = $null; source = 'clone'
                                            error = $sync.error }
        if ($sync.commit -and $there.commit) {
            if ($sync.commit -eq $there.commit) { $behind = 0; $same = $true }
            else {
                $same = $false
                # The counting happens IN THE CLONE: it is the one holding both commits.
                $c = @(Invoke-Git -Path $sync.path -Arguments @('rev-list', '--count', ($there.commit + '..' + $sync.commit)) |
                       Select-Object -First 1)[0]
                if ("$c" -match '^\d+$') { $behind = [int]$c }
            }
        }
    } else {
        $published = Get-LatestPublishedVersion -Backend $Backend
        if ($published) {
            $reference = 'publiee'
            $here = [pscustomobject][ordered]@{ version = $published; commit = $null; at = $null
                                                source = 'release'; error = $null }
            $same = (Test-SameVersion -A $published -B "$($there.version)")
        }
    }

    [pscustomobject][ordered]@{
        path = $installed; here = $here; there = $there; behind = $behind
        reference = $reference; repo = $route.repo; remote = $remote; same = $same
    }
}

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
    IS THE DEPLOYMENT POSSIBLE? -- quick checks, before stopping anything at all.

    Vigie was stopped, and only then did we discover that the copy would not go through: a
    locked folder, a full disk. Those two questions are answered in a few milliseconds, and
    save stopping for nothing.

    We do not try to foresee EVERY failure -- only those that cost less to check than to
    suffer. Returns $null when all is well, the reason otherwise.
#>
function Test-DeploymentPossible {
    param([Parameter(Mandatory)][string]$Destination, [long]$NeededBytes = 0)
    $parent = Split-Path $Destination -Parent
    if (-not (Test-PathSafe $parent)) { return ("dossier d'accueil introuvable : " + $parent) }

    # WRITING: we try, which is the only proof. A rights test would lie -- inheritance,
    # redirections, an antivirus that blocks at the real write.
    $probe = Join-Path $parent ('.vigie-write-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Set-Content -LiteralPath $probe -Value 'x' -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch { return ("écriture refusée dans " + $parent + " : " + $_.Exception.Message) }

    <#
        ROOM: TWO PLACES, AND NO LONGER NECESSARILY THE SAME DISK.

        The new version is laid at the destination, and the previous one is kept as a backup
        -- which now lives at machine scale, not under the installation. Counting "twice over,
        on the destination disk" was right as long as both were in the same place; with a
        destination on another disk it reserved twice the room where only one is needed, and
        nothing where the backup is actually going to be written.
    #>
    if ($NeededBytes -gt 0) {
        foreach ($lieu in @($parent, (Get-InstallBackupRoot))) {
            try {
                $rootPath = $lieu
                while ($rootPath -and -not (Test-Path -LiteralPath $rootPath)) { $rootPath = Split-Path $rootPath -Parent }
                if (-not $rootPath) { continue }
                $drive = (Get-Item -LiteralPath $rootPath).PSDrive
                if ($drive -and $null -ne $drive.Free -and $drive.Free -lt $NeededBytes) {
                    return ("espace disque insuffisant sur " + $drive.Name + " : " +
                            (Format-ByteSize -Bytes $drive.Free) + " libres, " +
                            (Format-ByteSize -Bytes $NeededBytes) + " nécessaires")
                }
            } catch { }
        }
    }
    return $null
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

# IS THE INSTALLATION SHARED? In other words: can another account of the machine so much as
# READ the application?
#
# The question is not theoretical: on a development workstation, or a clone of the
# repository, Vigie lives in somebody's personal space, and offering to enable it for another
# account would mean offering a task that fails silently at every logon (raised by the
# owner). So the REAL rights are looked at, and nothing is assumed.
#
# The groups whose read access makes the installation reachable by everyone:
#   S-1-5-32-545 Users | S-1-1-0 Everyone | S-1-5-11 Authenticated Users
function Test-InstallationPartagee {
    param([string]$Path = (Get-RepoRoot))
    $sids = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        foreach ($ace in $acl.Access) {
            if ("$($ace.AccessControlType)" -ne 'Allow') { continue }
            $sid = $null
            try { $sid = "$($ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value)" } catch { }
            if (-not $sid -or $sids -notcontains $sid) { continue }
            if (("$($ace.FileSystemRights)" -match 'Read|ReadAndExecute|Modify|FullControl')) { return $true }
        }
    } catch { }
    return $false
}

# WHERE is the SHARED installation, the one every account can read?
#
# On a development workstation Vigie runs from the repository, which the others cannot read;
# a deployed copy may exist beside it. An account's startup task must point at THAT ONE, or
# it fails silently at every logon -- which is exactly the trap that was raised: the
# deployment had been done, but the task would have aimed at the personal repository.
<#
    WHERE THE SHARED INSTALLATION LIVES.

    THE CHOSEN FOLDER IS DECLARED, because nothing else could find it. Program Files is
    guessable; "D:\Outils\Vigie" is not -- and an installation nobody can locate cannot be
    updated, diagnosed, nor uninstalled. So the setup writes the path it used under
    HKLM\SOFTWARE\Sowapps\Vigie, and this function reads it FIRST.

    The declaration is never believed on its word: the marker file must be there. A folder
    moved or deleted by hand would otherwise be announced as an installation forever.
#>
function Get-InstallPathDeclarationKey { 'HKLM:\SOFTWARE\Sowapps\Vigie' }

function Get-SharedInstallPath {
    $declared = $null
    try {
        $key = Get-InstallPathDeclarationKey
        if (Test-Path -LiteralPath $key) {
            $declared = "$((Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).InstallPath)"
        }
    } catch { }
    if ($declared) {
        $marqueurDeclare = Join-Path (Join-Path (Join-Path $declared 'apps') 'client') 'client.ps1'
        if (Test-Path -LiteralPath $marqueurDeclare -ErrorAction SilentlyContinue) { return $declared }
    }
    # Program Files is readable by every account BY CONSTRUCTION: an installation sitting
    # there is shared, with no need to question the ACLs. Reading the rights is kept for
    # locations outside Program Files, which the user chose.
    # The previous version relied on Get-Acl alone and answered "not shared" from the server
    # while the deployment had been done -- a hard thing to diagnose.
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($b in $bases) {
        foreach ($name in @((Join-Path 'Sowapps' 'Vigie'), 'Vigie')) {
            $c = Join-Path $b $name
            # A path built by Join-Path: a literal backslash has already been eaten by my
            # writing tools and turned into tabs (seen on this very file).
            $marqueur = Join-Path (Join-Path (Join-Path $c 'apps') 'client') 'client.ps1'
            if (Test-Path -LiteralPath $marqueur) { return $c }
        }
    }
    # An installation outside Program Files: the ACL decides.
    if (Test-InstallationPartagee) { return (Get-RepoRoot) }
    return $null
}

<#
    WHAT THE PRODUCT OWNS AT THE ROOT OF ITS FOLDER.

    Installed in Program Files, Vigie is alone and the folder is hers: it goes whole. Chosen
    elsewhere -- "D:\Outils\Vigie", or worse "D:\Outils" passed as an argument -- the folder
    may hold someone else's things, and deleting it whole would carry them away.

    So this list says what is OURS. It is the top level of the published archive, plus what
    running produces: var/ (data), dist/ and logs/ (working files). Anything else in that
    folder belongs to somebody, and stays.
#>
function Get-InstallOwnEntries {
    @('apps', 'config', 'doc', 'lang', 'notes', 'scripts', 'var', 'dist', 'logs',
      'setup.cmd', 'uninstall.cmd', 'CHANGELOG.md', 'CLAUDE.md', 'LICENSE', 'README.md', 'README.fr.md')
}

<#
    DECLARING THE INSTALL FOLDER, at the scale of the computer.

    Written by the setup, read by everyone, removed by the uninstall. One value, and it
    answers one question -- "where is Vigie?". Nothing else lives there.
#>
function Set-InstallPathDeclaration {
    param([Parameter(Mandatory)][string]$Path)
    $key = Get-InstallPathDeclarationKey
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name 'InstallPath' -Value $Path -PropertyType String -Force | Out-Null
}
