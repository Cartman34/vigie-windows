# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, paths, var
<#
    Intent: WHICH VERSION RUNS HERE, and which commit it really is. One number (D96): the installation stamp when there is one, otherwise what git says of the repository -- and git's refusals are kept rather than crushed.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- The application's version (it changes when the panel's files change) ---
# The product's VERSION number: the installation's, or the repository's.
#
# ONE single number (D96), and it is no longer kept by hand: an archive carries its build
# stamp, a repository answers with its last TAG. A VERSION file beside the tags gave two
# possible answers to "which version runs here?".
#
# One attempt was discarded before this one: the file date's TICKS ("version
# 639231069781032063"), a change token disguised as a version, unreadable and incomparable.
# That token's role belongs to Get-AppBuildId, below.
function Get-AppVersion {
    param([string]$Backend = (Get-BackendRoot))
    # ONE definition only: the installation's stamp when it has one (a deployed archive),
    # otherwise what git says of the repository. No more VERSION file (D96).
    $m = Get-BuildStamp -Root (Get-RepoRoot)
    if ($m -and $m.version -and $m.version -ne 'sans version') { return "$($m.version)" }
    return 'inconnue'
}

# A CHANGE token, never displayed. The front end compares it with its own and reloads the
# page as soon as it differs. It must therefore move at every modification of the file
# served -- which a commit hash does not do, since it ignores uncommitted changes.
function Get-AppBuildId {
    param([string]$Backend = (Get-BackendRoot))
    # THE WHOLE PANEL, NOT ONE FILE. This watched index.html alone, which was the panel entire. Since the style
    # and the script moved to their own files (D132, UI-ASSETS), watching the page alone would have left the
    # browser on an old script for as long as nobody touched the page: the most recent write of the view AND of
    # the files it loads is what "the panel changed" means.
    $front = Get-AppPath -Role 'frontend'
    $watched = @()
    foreach ($sub in @('views', 'assets')) {
        $dir = Join-Path $front $sub
        if (Test-Path -LiteralPath $dir) { $watched += @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue) }
    }
    if (-not $watched.Count) { return '0' }
    "$((($watched | Sort-Object LastWriteTimeUtc -Descending)[0]).LastWriteTimeUtc.Ticks)"
}

# --- THE PRECISE IDENTITY OF A VERSION: the number AND the commit -----------
#
# "Technically I advise taking the version AND the commit." The number says what was meant
# to be delivered; the commit says what REALLY was. Two deployments of the same v0.1 can be
# twenty commits apart -- and that is exactly the case on a development workstation.
#
# The stamp is LAID INSIDE THE ARCHIVE at build time (a BUILD file, one line reading
# "version commit date"), because a deployed installation has no git repository: it cannot
# describe itself any other way.
# A REPOSITORY'S VERSION: the last TAG, and what has been committed since.
#
# There is only ONE number left (D96). A VERSION file kept by hand beside the tags meant two
# numbers to maintain -- and they drifted: the debug card showed "v0.1" while the deployed
# installation showed "v0.1.6".
#
# `git describe` says it all: "v0.1.6" when sitting exactly on the tag, "v0.1.6+6" when six
# commits have followed. That is the PRECISE version, and it maintains itself.
<#
    CALLING GIT AND KEEPING ITS REFUSAL.

    Get-GitVersion and Get-GitCommit crushed the error ("2>$null") and returned $null. On
    30/08 the card therefore announced "this workstation's repository: no version" -- without
    saying whether the folder was unreadable, whether git was missing, or whether it refused
    to work in a repository belonging to someone else. Three causes, three different
    gestures, and no trace to tell them apart.

    So the refusal is kept. It interrupts nothing -- an unknown version is not a breakdown --
    but it becomes READABLE: Get-BuildStamp reports it, and the card says it.
#>
$script:GitLastError = $null
function Invoke-Git {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)
    $script:GitLastError = $null
    $git = (Get-Command git -ErrorAction SilentlyContinue)
    if (-not $git) {
        $script:GitLastError = 'git est introuvable pour ce compte.'
        return $null
    }
    try {
        $err = @()
        $out = & $git.Source -C $Path @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $err += "$_"; } else { $_ }
        }
        <#
            THE EXIT CODE JUDGES, NOT THE ERROR STREAM.

            git speaks on stderr when everything is fine: "Everything up-to-date",
            "To https://...", "* [new tag] v0.1.67 -> v0.1.67", and every progress line of a
            fetch or a clone. Taking that for a failure made EVERY successful push report
            itself as failed -- so a deployment announced "tag posed, local only" while the
            tag had just been published, and nobody could tell a real refusal from a normal
            one. Measured on 03/09: five versions believed unpublished.

            The stderr text is kept, because a real failure explains itself there; it just
            no longer decides.
        #>
        if ($LASTEXITCODE -ne 0) {
            $script:GitLastError = if ($err.Count) { ($err | Select-Object -First 2) -join ' ' }
                                   else { "git a rendu le code $LASTEXITCODE" }
        }
        return @($out | Where-Object { "$_".Trim() })
    } catch {
        $script:GitLastError = $_.Exception.Message
        return $null
    }
}

# Git's last refusal, or $null. Read just after a call.
function Get-GitLastError { return $script:GitLastError }

function Get-GitVersion {
    param([string]$Path = (Get-RepoRoot))
    try {
        $d = @(Invoke-Git -Path $Path -Arguments @('describe', '--tags') | Select-Object -First 1)[0]
        if (-not $d) { return $null }
        $d = "$d".Trim()
        # git returns "v0.1.6-6-g813205f": we keep "v0.1.6+6", shorter to read, and the
        # commit is already displayed beside it.
        if ($d -match '^(.*)-(\d+)-g[0-9a-f]+$') { return ($Matches[1] + '+' + $Matches[2]) }
        return $d
    } catch { return $null }
}

function Get-GitCommit {
    param([string]$Path = (Get-RepoRoot), [switch]$Court)
    try {
        $forme = if ($Court) { '%h' } else { '%H' }
        $c = @(Invoke-Git -Path $Path -Arguments @('log', '-1', "--format=$forme") | Select-Object -First 1)[0]
        if ($c) { return "$c".Trim() }
    } catch { }
    return $null
}

# An installation's stamp: version, commit, date. Read from the BUILD file when there is one
# (a deployed installation), otherwise computed from git (a development workstation).
function Get-BuildStamp {
    param([string]$Root = (Get-RepoRoot))
    $f = Join-Path $Root 'BUILD'
    if (Test-Path -LiteralPath $f) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            if ($j -and $j.version) { return $j }
        } catch { }
    }
    # Outside an archive, the version is the one git knows: the last tag, plus commits.
    # IF GIT REFUSES, ITS WORD IS KEPT: "no version" does not say whether the folder is
    # unreadable, whether git is missing, or whether it refuses a repository owned by another.
    $v = Get-GitVersion -Path $Root
    $c = Get-GitCommit -Path $Root
    return [pscustomobject][ordered]@{
        version = $(if ($v) { $v } else { 'sans version' })
        commit  = $c
        at      = $null
        source  = 'depot'
        error   = $(if ($v -and $c) { $null } else { Get-GitLastError })
    }
}

<#
    THIS MACHINE'S SOURCE REPOSITORY, or $null.

    Three cases, one result:
      - we are running INSIDE a repository -> that is the one;
      - we are running from an installation that knows where it came from, and that
        repository is still there -> that is the one;
      - an ordinary machine -> $null, and the reference becomes the published version. That
        is the right question there: nobody has a repository on such a machine.
#>
function Get-LocalRepoPath {
    param([string]$Backend = (Get-BackendRoot))
    <#
        THIS COMPUTER'S REPOSITORY, or $null. WITH NO JUDGEMENT AT ALL.

        I had put a guard here: "no repository outside dev mode". It was wrong -- a
        PRODUCTION workstation may perfectly well have a local repository and deploy from it,
        or prefer the published versions. "dev" and "prod" do not answer that question.

        What does answer it already exists: UpdateSource. So this function merely says WHERE
        the repository is, if there is one; the choice belongs to Get-UpdateRoute.
    #>
    $here = Get-RepoRoot
    if (Test-PathSafe (Join-Path $here '.git')) { return $here }
    # THE PATH COMES FROM THE COMPUTER, not from the copy's BUILD: a deployment rewrites the
    # BUILD, while the computer's own declaration does not move.
    $declared = "$((Get-Config -Backend $Backend).SourcePath)"
    if (-not $declared) { return $null }
    # The repository may have been moved or deleted since: we check it is still one.
    if (-not (Test-PathSafe (Join-Path $declared '.git'))) { return $null }
    return $declared
}

<#
    WHERE WOULD THE NEXT VERSION COME FROM?

    ONE RESOLUTION, FOR EVERYONE: the "Update" button borrows it to know what to do, and the
    card borrows it to know what to compare itself WITH. It is the only way the card answers
    the real question -- "would this button change anything?" -- instead of comparing itself
    with whatever comes to hand.

    The setting already exists: UpdateSource, in the configuration.
      local   : this computer's repository (we build, and we lay the tag)
      release : the latest version published on GitHub
      clone   : a precise branch or tag, fetched from GitHub
      auto    : the repository when there is one, otherwise the published version -- the default

    IT IS NOT THE SAME QUESTION AS "dev or prod": a production workstation may have a local
    repository and deploy from it. I had confused the two.
#>
<#
    THE SERVICE CLONE -- its folder, and where it synchronises from.

    A service NEVER works inside a person's repository (D112): it has its own clone, which it
    owns, and builds from that. The path is defined here and nowhere else -- vigie-fetch used
    it under the name "$travail\depot", recomposing it.
#>
<#
    LAYING THE VERSION TAG -- AND IT IS NOT THE SERVICE'S JOB.

    The original rule: a version is marked by a TAG, only at the moment of a deployment, with
    a fixed increment. It does not change -- "I mark nothing, the current deployment in dev
    marks a version and pushes it".

    What changes is WHO runs it. A tag laid by a service account has no author, its push has
    no credentials, and git refuses to write inside a person's repository (D112). So the
    "tag-version" action calls this function IN THE REQUESTER'S SESSION, under their account,
    in their repository.

    Computing the next number lives here, in the library: both paths -- the button and the
    command line -- must give the same one.
#>
function Get-NextDeploymentTag {
    param([Parameter(Mandatory)][string]$RepoPath)
    # The base comes from the LAST TAG: the only number the project maintains (D96).
    $base = '0.1'
    $last = @(Invoke-Git -Path $RepoPath -Arguments @('describe', '--tags', '--abbrev=0') | Select-Object -First 1)[0]
    if ("$last" -match '^v?(\d+\.\d+)\.\d+$') { $base = $Matches[1] }
    $max = 0
    foreach ($t in @(Invoke-Git -Path $RepoPath -Arguments @('tag', '--list', ("v" + $base + ".*")))) {
        if ("$t" -match ('^v' + [regex]::Escape($base) + '\.(\d+)$')) {
            $x = [int]$Matches[1]
            if ($x -gt $max) { $max = $x }
        }
    }
    return ('v' + $base + '.' + ($max + 1))
}

function New-DeploymentTag {
    param([Parameter(Mandatory)][string]$RepoPath, [switch]$Push)
    $tag = Get-NextDeploymentTag -RepoPath $RepoPath
    # -f is absent ON PURPOSE: a tag is not rewritten. If it already exists, this deployment
    # has already happened -- we say so and carry on.
    $null = Invoke-Git -Path $RepoPath -Arguments @('tag', '-a', $tag, '-m', ("Deploiement du " + (Get-Date -Format 'dd/MM/yyyy HH:mm')))
    $failure = Get-GitLastError
    $pushed = $false
    if (-not $failure -and $Push) {
        # A tag is only worth anything once shared. A failed push is NOT fatal: a deployment
        # must succeed even with no network.
        $null = Invoke-Git -Path $RepoPath -Arguments @('push', 'origin', $tag)
        $pushed = -not (Get-GitLastError)
    }
    return [pscustomobject][ordered]@{ tag = $tag; posed = (-not $failure); pushed = $pushed; error = $failure }
}

# Writes the stamp: called by the building of the archive, once.
function Write-BuildStamp {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Version, [string]$Commit)
    $o = [ordered]@{ version = $Version; commit = $Commit
                     at = (Get-Date).ToUniversalTime().ToString('o'); source = 'archive' }
    ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $Root 'BUILD') -Encoding UTF8
}

# Do two numbers name the same version? "v0.1.26" and "0.1.26": yes.
# "v1.1.6-dev1" and "v1.1.6+1" too: archives built before 15/09 wrote the commits count as "-devN" into their stamp.
function Test-SameVersion {
    param([string]$A, [string]$B)
    $left  = ("$A".TrimStart('v', 'V').Trim()) -replace '-dev(\d+)$', '+$1'
    $right = ("$B".TrimStart('v', 'V').Trim()) -replace '-dev(\d+)$', '+$1'
    return ($left -eq $right)
}

<#
    THE LATEST PUBLISHED VERSION, or $null.

    Asked for at most once per half-day: the answer rarely changes, and a card must not
    depend on the network to display. Offline, GitHub quota reached, private repository: it
    returns $null, and the card says "not checked yet" rather than inventing a verdict.

    THE FAILURE IS RECORDED TOO: without that, an offline machine would call GitHub again at
    every display.
#>
function Get-LatestPublishedVersion {
    param([string]$Backend = (Get-BackendRoot))
    $f = Get-VarPath -Backend $Backend -Kind 'cache' -File 'published-version.json'
    if (Test-Path -LiteralPath $f) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalHours
            if ($age -lt 12) { return $(if ($j.version) { "$($j.version)" } else { $null }) }
        } catch { }
    }
    $version = $null
    try {
        $repo = "$((Get-Config -Backend $Backend).Repository)"
        if (-not $repo) { $repo = 'Cartman34/vigie-windows' }
        $rep = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/releases/latest') `
                                 -Headers @{ 'User-Agent' = 'Vigie'; 'Accept' = 'application/vnd.github+json' } `
                                 -TimeoutSec 8 -ErrorAction Stop
        if ($rep -and $rep.tag_name) { $version = "$($rep.tag_name)" }
    } catch { }
    try {
        (@{ at = (Get-Date).ToUniversalTime().ToString('o'); version = $version } | ConvertTo-Json) |
            Set-Content -LiteralPath $f -Encoding UTF8
    } catch { }
    return $version
}
