# @author Florent HAZARD <f.hazard@sowapps.com>
<#
.SYNOPSIS
    Installs the repository's git hooks (the scripts/hooks folder) into .git/hooks.

.DESCRIPTION
    Intent: make the project's hooks something a clone receives, instead of something one has to remember. Git
    does not version .git/hooks: a hook dropped there survives neither a clone nor a new workstation. So the
    project's hooks live in scripts/hooks/ -- versioned, readable, diffable -- and this script installs them.

    IDEMPOTENT: running it again has no effect if the hooks are already up to date.

    The worktrees share the main repository's hooks: one single installation is enough.

.PARAMETER Verifier
    Installs nothing; only says whether the installed hooks are up to date.
    Exit code 1 if at least one hook is missing or differs.

.EXAMPLE
    pwsh -File .\scripts\install-hooks.ps1

.EXAMPLE
    pwsh -File .\scripts\install-hooks.ps1 -Verifier

.NOTES
    Exit codes: 0 = up to date or installed; 1 = a discrepancy was detected (with -Verifier);
                2 = no git repository found.
#>
[CmdletBinding()]
param([switch] $Verifier)

$ErrorActionPreference = 'Stop'
# This file is isolated: it loads the common display itself, which also brings the labels (console-ui.ps1 and
# i18n.ps1 are its neighbours).
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'console-ui.ps1')

$repoRoot = Split-Path $PSScriptRoot -Parent
$source   = Join-Path $PSScriptRoot 'hooks'

# git rev-parse --git-common-dir: it gives the .git of the MAIN repository even from a worktree, where .git is a
# plain redirection file.
Push-Location $repoRoot
try { $gitDir = (& git rev-parse --git-common-dir 2>$null) } catch { $gitDir = $null }
Pop-Location
if (-not $gitDir) { Write-Fail (Get-Label 'install-hooks.depot-git-introuvable-depuis' $repoRoot); exit 2 }
if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $repoRoot $gitDir }
$target = Join-Path $gitDir 'hooks'

if (-not (Test-Path -LiteralPath $source)) { Write-Host (Get-Label 'install-hooks.aucun-hook-installer' $source); exit 0 }
if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }

$ecarts = 0
foreach ($h in Get-ChildItem -LiteralPath $source -File) {
    $dst = Join-Path $target $h.Name
    $identique = (Test-Path -LiteralPath $dst) -and
                 ((Get-FileHash $h.FullName).Hash -eq (Get-FileHash $dst).Hash)
    if ($identique) { Write-Host (Get-Label 'install-hooks.jour' $h.Name); continue }
    $ecarts++
    if ($Verifier) { Write-Warn (Get-Label 'install-hooks.installer' $h.Name); continue }
    Copy-Item -LiteralPath $h.FullName -Destination $dst -Force
    Write-Ok (Get-Label 'install-hooks.installe' $h.Name)
}

if ($Verifier -and $ecarts -gt 0) {
    Write-Info (Get-Label 'install-hooks.hook-manquant-ou-differents' $ecarts)
    exit 1
}
Write-Info (Get-Label 'install-hooks.hooks' $source $target)
exit 0
