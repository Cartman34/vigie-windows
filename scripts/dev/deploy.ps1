# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    deploy.ps1 -- THE DEPLOYMENT, IN ONE COMMAND, AND IT CHECKS WHAT IT DEPLOYED.

    Intent: a procedure one redoes from memory is a procedure one redoes badly. This one was written in the
    briefing -- "merge --ff-only into main FROM THE MAIN CHECKOUT, push, then ask the server for the update" --
    and on 15/10 I did not follow it: I pushed the worktree's branch straight onto the remote main. The remote ref
    moved, the LOCAL main stayed where it was, and the update chain reads the local repository: it therefore
    reinstalled the commit already in place and reported a success. Nothing in the chain said that the deployment
    had changed nothing. Hence this script, and its last step, which is the one that matters.

    Usage:
      pwsh -File scripts/dev/deploy.ps1                 # the whole chain, from this worktree or from the repository
      pwsh -File scripts/dev/deploy.ps1 -NoWait   # does not wait for the server to come back
    Exit codes: 0 = the installation carries the commit that was pushed; 2 = a step refused, nothing further was
                attempted; 3 = the update ran and the installation does NOT carry the expected commit.

    WHAT IT DOES, in order, and it stops at the first refusal:
      1. the work tree is clean, and so is the main checkout's;
      2. the fifteen checkers are green (check-all) -- a deployment is a delivery;
      3. the branch is an AVANCE DIRECTE over main, which is what makes the merge safe;
      4. in the MAIN CHECKOUT: merge --ff-only, then push origin main;
      5. the server app is asked to update itself (vigie-update);
      6. IT WAITS AND IT VERIFIES: the installed BUILD must carry the pushed commit, and the server must answer.

    WHAT IT DOES NOT DO: it never rewrites history, never forces anything, and it does not lay the version tag --
    that one is laid inside the requester's session by the Deployment card (D123), under their account.
#>
[CmdletBinding()]
param(
    # Do not wait for the server to come back: the update is asked for, and the verification is left out. To be
    # used only when the wait is unwanted, never to "go faster" -- a deployment nobody verified is a rumour.
    [switch] $NoWait,
    # How long to wait for the installation to carry the pushed commit. The measured chain takes 70 to 225 s.
    [int] $Seconds = 300
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

Write-Title 'Déploiement'

$backend = Join-Path $repoRoot 'apps/backend-pode'

function Stop-Deployment {
    param([Parameter(Mandatory)][string]$Why, [string]$What)
    Write-Fail $Why
    if ($What) { Write-Info $What }
    exit 2
}

# --- 1. Nothing in progress, on either side -----------------------------------------------------------------
#
# THE MAIN CHECKOUT IS LOOKED AT TOO, and it belongs to somebody: we READ its state, we never put work of ours
# into it. A merge into a dirty checkout is how one loses somebody else's work.
Write-Step 'Ce qui est en cours'
$branch = "$(Invoke-Git -Path $repoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD'))".Trim()
$dirty = @(Invoke-Git -Path $repoRoot -Arguments @('status', '--short') | Where-Object { "$_".Trim() })
if ($dirty.Count) {
    foreach ($l in $dirty) { Write-Detail "$l" }
    Stop-Deployment "L'arbre de travail porte $($dirty.Count) modification(s) non commitée(s)." `
                    'Commitez ou mettez de côté avant de déployer : on ne déploie que ce que git connaît.'
}
Write-Detail "Branche : $branch"

$mainRepo = Get-LocalRepoPath -Backend $backend
if (-not $mainRepo) { Stop-Deployment "Aucun dépôt local sur cette machine : il n'y a rien à fusionner." }
$mainRepo = (Resolve-Path -LiteralPath $mainRepo).Path
Write-Detail "Dépôt principal : $mainRepo"
if ($mainRepo -eq (Resolve-Path -LiteralPath $repoRoot).Path) {
    Write-Detail "Nous y sommes déjà : la fusion se fera sur place."
} else {
    $mainDirty = @(Invoke-Git -Path $mainRepo -Arguments @('status', '--short') | Where-Object { "$_".Trim() })
    if ($mainDirty.Count) {
        foreach ($l in $mainDirty) { Write-Detail "$l" }
        Stop-Deployment "Le dépôt principal porte $($mainDirty.Count) modification(s) en cours." `
                        "Ce dossier appartient à quelqu'un : rien n'y est fusionné tant qu'il n'est pas propre."
    }
}

# --- 2. The checkers ----------------------------------------------------------------------------------------
Write-Step 'Les vérificateurs'
$checkAll = Join-Path $repoRoot 'scripts/dev/check-all.ps1'
& pwsh -NoProfile -File $checkAll | Out-Null
if ($LASTEXITCODE -ne 0) {
    Stop-Deployment "Les vérificateurs refusent (code $LASTEXITCODE) : rien n'est poussé." `
                    'Relancez scripts/dev/check-all.ps1 pour voir lequel, et corrigez avant de déployer.'
}
Write-Ok 'Les quinze vérificateurs sont verts.'

# --- 3. An avance directe, never a merge commit ---------------------------------------------------------------
Write-Step 'La fusion est-elle une avance directe ?'
$target = "$(Invoke-Git -Path $repoRoot -Arguments @('rev-parse', 'HEAD'))".Trim()
$null = Invoke-Git -Path $repoRoot -Arguments @('merge-base', '--is-ancestor', 'main', 'HEAD')
if ($LASTEXITCODE -ne 0) {
    Stop-Deployment "main n'est pas un ancêtre de cette branche : la fusion ne serait pas une avance directe." `
                    'Rebasez la branche sur main, ou dites ce que vous voulez faire de la divergence.'
}
$ahead = @(Invoke-Git -Path $repoRoot -Arguments @('log', '--oneline', 'main..HEAD') | Where-Object { "$_".Trim() })
if (-not $ahead.Count) {
    Write-Warn "Rien de nouveau : main porte déjà ce commit. Aucun déploiement n'est nécessaire."
    exit 0
}
Write-Detail "$($ahead.Count) commit(s) à déployer, jusqu'à $($target.Substring(0, 7))"

# --- 4. The merge, then the push, both from the main checkout -------------------------------------------------
#
# THIS IS THE STEP THAT WAS SKIPPED. Pushing `HEAD:main` from a worktree moves the REMOTE ref and leaves the
# local main behind -- and it is the local repository that the update chain reads.
Write-Step 'Fusion dans main, puis poussée'
if ($mainRepo -ne (Resolve-Path -LiteralPath $repoRoot).Path) {
    foreach ($line in @(Invoke-Git -Path $mainRepo -Arguments @('merge', '--ff-only', $branch))) {
        if ("$line".Trim()) { Write-Detail "$line" }
    }
    if ($LASTEXITCODE -ne 0) { Stop-Deployment "La fusion a échoué (code $LASTEXITCODE) : rien n'est poussé." }
} else {
    Write-Detail 'Déjà sur le dépôt principal : rien à fusionner depuis ailleurs.'
}
$localMain = "$(Invoke-Git -Path $mainRepo -Arguments @('rev-parse', 'main'))".Trim()
if ($localMain -ne $target) {
    Stop-Deployment "Le main local est à $($localMain.Substring(0, 7)) alors que l'on déploie $($target.Substring(0, 7))." `
                    "C'est exactement le défaut du 15/10 : la chaîne lit le dépôt local, elle installerait l'ancien code."
}
foreach ($line in @(Invoke-Git -Path $mainRepo -Arguments @('push', 'origin', 'main'))) {
    if ("$line".Trim()) { Write-Detail "$line" }
}
if ($LASTEXITCODE -ne 0) { Stop-Deployment "La poussée a échoué (code $LASTEXITCODE)." }
Write-Ok "main est à $($target.Substring(0, 7)), localement et à distance."

# --- 5. The server app updates itself -------------------------------------------------------------------------
Write-Step "Demande de mise à jour à l'app serveur"
$before = 'inconnue'
try { $before = (Get-BuildStamp -Root (Get-SharedInstallPath)).version } catch { }
Write-Detail "Version installée avant : $before"
& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/dev/ask-vigie.ps1') -Type 'vigie-update' -Module 'vigie' | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-Deployment "L'app serveur n'a pas pris la demande (code $LASTEXITCODE)." }
Write-Ok 'Mise à jour lancée : elle récupère, construit, installe et relance.'

if ($NoWait) {
    Write-Warn "Demandé sans attendre : le déploiement n'est PAS vérifié."
    exit 0
}

# --- 6. And we verify, because a successful update can install the wrong thing ---------------------------------
Write-Step "Ce qui est réellement installé"
$port = 47600
try { $port = [int](Get-Config -Backend $backend).Port } catch { }
$deadline = (Get-Date).AddSeconds([Math]::Max($Seconds, 30))
$installed = $null
$online = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    try { $installed = Get-BuildStamp -Root (Get-SharedInstallPath) } catch { $installed = $null }
    $online = [bool](Get-PortListener -Port $port)
    $says = $(if ($installed) { "$($installed.version)" } else { 'illisible' })
    Write-Detail ("{0} — installée : {1}, serveur {2}" -f (Get-Date -Format 'HH:mm:ss'), $says,
                                                        $(if ($online) { 'en ligne' } else { 'en redémarrage' }))
    if ($installed -and "$($installed.commit)" -eq $target -and $online) { break }
}

if ($installed -and "$($installed.commit)" -eq $target -and $online) {
    Write-Ok "Installée : $($installed.version), commit $($target.Substring(0, 7)). Serveur en ligne sur $port."
    Write-Outcome -What 'Le déploiement est posé et vérifié'
    exit 0
}

# A DEPLOYMENT THAT CHANGED NOTHING IS A FAILURE, AND IT IS SAID. On 15/10 the same commit was reinstalled and
# announced as a success, which is how two hours went by on a correction nobody could see.
Write-Fail "L'installation ne porte pas le commit déployé."
Write-Info ("Attendu : {0} — installé : {1}" -f $target.Substring(0, 7),
            $(if ($installed -and $installed.commit) { "$($installed.commit)".Substring(0, 7) } else { 'illisible' }))
if (-not $online) { Write-Info "Et le serveur ne répond pas sur $port : la relance n'a pas abouti." }
Write-Info 'Lisez scripts/dev/deploy-status.ps1, puis le journal de la dernière installation.'
exit 3
