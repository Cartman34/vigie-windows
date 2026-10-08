# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    deploy-status.ps1 -- WHERE DOES THE DEPLOYMENT STAND? READ ONLY.

    Intent: make a recurring question a script rather than an improvisation. After every installation I ask the
    same things -- has the server come back, which version is laid down, is the repository ahead, did the last
    installation miss anything -- and I used to ask them through makeshift command lines, unreadable and never
    twice the same.

    Usage:
      pwsh -File .\scripts\dev\deploy-status.ps1
      pwsh -File .\scripts\dev\deploy-status.ps1 -Attendre 120   # waits for the server to come back
    Exit codes: 0 = the installation and the repository are at the same level, the server is up; 1 = the server
                does not answer; 2 = a gap or a failure to report.

    IT WRITES NOTHING and triggers no recomputation: it reads the state, the versions and the report.
#>


#>
[CmdletBinding()]
param(
    # Seconds to wait for the server to come back. 0 = we observe, we do not wait.
    [int] $Attendre = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

Write-Title (Get-Label 'deploy-status.titre')

# --- 1. Does the server answer? -----------------------------------------------
Write-Step (Get-Label 'deploy-status.etape-serveur')
$port = [int](Get-Config -Backend $backend).Port
$serverUp = $false
$deadline = (Get-Date).AddSeconds([Math]::Max($Attendre, 0))
do {
    $serverUp = [bool](Get-PortListener -Port $port)
    if ($serverUp) {
        try {
            $null = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/health") -TimeoutSec 5
        } catch { $serverUp = $false }
    }
    if (-not $serverUp -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
} while (-not $serverUp -and (Get-Date) -lt $deadline)

if ($serverUp) { Write-Ok (Get-Label 'deploy-status.serveur-repond' $port) }
else         { Write-Fail (Get-Label 'deploy-status.serveur-muet' $port) }

# --- 2. The versions ----------------------------------------------------------
Write-Step (Get-Label 'deploy-status.etape-versions')
$installed = $null
$here = $null
try { $installed = (Get-BuildStamp -Root (Get-SharedInstallPath)).version } catch { }
try { $here = (Get-BuildStamp -Root $repoRoot).version } catch { }
Write-Info (Get-Label 'deploy-status.version-installee' $(if ($installed) { $installed } else { 'inconnue' }))
Write-Info (Get-Label 'deploy-status.version-depot'     $(if ($here) { $here } else { 'inconnue' }))
$gap = -not (Test-SameVersion -A "$installed" -B "$here")
if ($gap) { Write-Warn (Get-Label 'deploy-status.versions-differentes') }
else        { Write-Ok (Get-Label 'deploy-status.versions-identiques') }

<#
    ARE THE MARKED VERSIONS PUBLISHED?

    A tag posed and never pushed designates nothing for anyone: the public repository does
    not know that version, and an installation looking for "the latest published version"
    cannot see it. Nine had stayed that way, some for weeks, with nothing to say so -- the
    tag is posed by an action meant to run in the requester's session, and the server takes
    it over when the client app does not answer; under the service account the push has no
    credentials and fails.

    The finding lives HERE, in the tool one questions before delivering, rather than in my
    memory. The repair itself is one line: git push origin <tag>.
#>
$localTags = @(Invoke-Git -Path $repoRoot -Arguments @('tag', '--list', 'v*'))
$remoteRefs = @(Invoke-Git -Path $repoRoot -Arguments @('ls-remote', '--tags', 'origin'))
if (Get-GitLastError) {
    Write-Warn (Get-Label 'deploy-status.tags-illisibles' (Get-GitLastError))
} else {
    $publishedTags = @()
    foreach ($line in $remoteRefs) {
        if ("$line" -match 'refs/tags/(v[^\s^]+)') { $publishedTags += $Matches[1] }
    }
    $missingTags = @($localTags | Where-Object { $publishedTags -notcontains "$_" })
    if ($missingTags.Count) {
        Write-Warn (Get-Label 'deploy-status.tags-non-publies' $missingTags.Count ($missingTags -join ', '))
        Write-Detail (Get-Label 'deploy-status.tags-comment-publier' ($missingTags[-1]))
    } else {
        Write-Ok (Get-Label 'deploy-status.tags-publies' $localTags.Count)
    }
}

# --- 3. The last operation ----------------------------------------------------
#
# WE ASK VIGIE RATHER THAN LOOK FOR A FILE. The log of an installation started from the card lives in the service
# account's profile; this repository's own dates from the last time setup.cmd was run from here. Looking for "the
# last log" beside oneself means reading the wrong one (observed on 01/09: a log from 26/08 presented as the
# latest). The server, for its part, knows what really happened.
Write-Step (Get-Label 'deploy-status.etape-journal')
$session = $null
if ($serverUp) {
    try { $session = Open-VigieSession -BaseUrl ("http://127.0.0.1:$port") -Backend $backend } catch { }
}
if (-not $session) {
    Write-Info (Get-Label 'deploy-status.operations-sans-serveur')
} else {
    $operations = $null
    try { $operations = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/operations") -WebSession $session -TimeoutSec 20 } catch { }
    $recent = @()
    if ($operations) { $recent = @($operations.results) }
    if (-not $recent.Count) {
        Write-Info (Get-Label 'deploy-status.aucune-operation')
    } else {
        foreach ($o in ($recent | Select-Object -First 3)) {
            $when = "$($o.at)"
            try { $when = (ConvertTo-UtcDate $o.at).ToLocalTime().ToString('dd/MM HH:mm') } catch { }
            if ([int]$o.code -eq 0) {
                Write-Ok (Get-Label 'deploy-status.operation-reussie' "$($o.label)" $when ([int]$o.seconds))
            } else {
                Write-Fail (Get-Label 'deploy-status.operation-echouee' "$($o.label)" $when `
                                      $(if ($o.error) { "$($o.error)" } else { "code " + [int]$o.code }))
            }
        }
    }
}

# --- 4. The sentinels ---------------------------------------------------------
#
# WE ASK VIGIE, WE DO NOT READ ITS FILE. The memory of the watch lives in the service account's var: an ordinary
# session cannot even read it, and this script announced "never measured" while it did not know (observed on
# 01/09). The Debugging card carries the information, and Vigie serves it with the rights of whoever asks.
Write-Step (Get-Label 'deploy-status.etape-sentinelles')
if (-not $serverUp) {
    Write-Info (Get-Label 'deploy-status.sentinelles-sans-serveur')
} else {
    $card = $null
    try {
        if (-not $session) { $session = Open-VigieSession -BaseUrl ("http://127.0.0.1:$port") -Backend $backend }
        if ($session) {
            $card = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/modules/vigie-debug") `
                                       -WebSession $session -TimeoutSec 30
        }
    } catch { }
    $field = $null
    if ($card) { $field = @($card.fields | Where-Object { $_.key -eq 'veille' }) | Select-Object -First 1 }
    if (-not $field) {
        Write-Info (Get-Label 'deploy-status.sentinelles-sans-reponse')
    } else {
        Write-Info (Get-Label 'deploy-status.sentinelles-etat' "$($field.value)")
        foreach ($l in @("$($field.guide)" -split "`r?`n")) { if ("$l".Trim()) { Write-Detail "$l" } }
        if ("$($field.status)" -eq 'warn') { Write-Warn (Get-Label 'deploy-status.veille-arretee') }
    }
}

Write-Outcome -What (Get-Label 'deploy-status.verdict')
if (-not $serverUp) { exit 1 }
if ($gap) { exit 2 }
exit 0
