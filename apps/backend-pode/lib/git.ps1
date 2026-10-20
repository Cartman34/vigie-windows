# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: TALKING TO GIT, AND WHAT THIS MACHINE MUST DECLARE FOR GIT TO ANSWER: running a command in a repository while keeping its refusal readable, and the folders declared trusted system-wide. What git SAYS of a version is another subject (version.ps1), and what is deployed from it yet another (deployment.ps1).
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
