# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, git, install-copy, paths, service-clone, version
<#
    Intent: DEPLOYING AND PUTTING BACK: the clone the service reads, the archive expanded over the shared installation, the lock that keeps two deployments apart, the backup taken before and the restore that uses it.
    Usage: dot-sourced by common.ps1, never run on its own.
#>








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
