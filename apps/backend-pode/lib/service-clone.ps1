# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, git, paths, var, version
<#
    Intent: THE CLONE THE SERVICE PULLS FROM: where it lives, which remote it follows, and bringing it in step without ever touching the working copy a human is using. Whether a deployment MAY happen is decided elsewhere (deployment.ps1); here the clone is simply kept current.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
