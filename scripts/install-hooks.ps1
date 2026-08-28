<#
.SYNOPSIS
    Installe les hooks git du depot (dossier scripts/hooks) dans .git/hooks.

.DESCRIPTION
    Git ne versionne pas .git/hooks : un hook depose la ne survit ni a un clone, ni a un
    nouveau poste. Les hooks du projet vivent donc dans scripts/hooks/ -- versionnes,
    relisibles, diffables -- et ce script les installe.

    IDEMPOTENT : relance sans effet si les hooks sont deja a jour.

    Les worktrees partagent les hooks du depot principal : une seule installation suffit.

.PARAMETER Verifier
    N'installe rien ; indique seulement si les hooks installes sont a jour.
    Code de retour 1 si au moins un hook manque ou differe.

.EXAMPLE
    pwsh -File .\scripts\installer-hooks.ps1

.EXAMPLE
    pwsh -File .\scripts\installer-hooks.ps1 -Verifier

.NOTES
    Codes de retour : 0 = a jour ou installe ; 1 = ecart detecte (avec -Verifier) ;
                      2 = depot git introuvable.
#>
[CmdletBinding()]
param([switch] $Verifier)

$ErrorActionPreference = 'Stop'
# Ce fichier est isole : il charge lui-meme l'affichage commun, qui apporte aussi
# les libelles (console-ui.ps1 et i18n.ps1 sont voisins).
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'console-ui.ps1')

$repoRoot = Split-Path $PSScriptRoot -Parent
$source   = Join-Path $PSScriptRoot 'hooks'

# git rev-parse --git-common-dir : donne le .git du depot PRINCIPAL meme depuis un
# worktree, ou .git est un simple fichier de renvoi.
Push-Location $repoRoot
try { $gitDir = (& git rev-parse --git-common-dir 2>$null) } catch { $gitDir = $null }
Pop-Location
if (-not $gitDir) { Write-Fail (Get-Label 'install-hooks.depot-git-introuvable-depuis' $repoRoot); exit 2 }
if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $repoRoot $gitDir }
$cible = Join-Path $gitDir 'hooks'

if (-not (Test-Path -LiteralPath $source)) { Write-Host (Get-Label 'install-hooks.aucun-hook-installer' $source); exit 0 }
if (-not (Test-Path -LiteralPath $cible)) { New-Item -ItemType Directory -Path $cible -Force | Out-Null }

$ecarts = 0
foreach ($h in Get-ChildItem -LiteralPath $source -File) {
    $dst = Join-Path $cible $h.Name
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
Write-Info (Get-Label 'install-hooks.hooks' $source $cible)
exit 0
