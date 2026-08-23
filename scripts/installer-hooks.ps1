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
$repoRoot = Split-Path $PSScriptRoot -Parent
$source   = Join-Path $PSScriptRoot 'hooks'

# git rev-parse --git-common-dir : donne le .git du depot PRINCIPAL meme depuis un
# worktree, ou .git est un simple fichier de renvoi.
Push-Location $repoRoot
try { $gitDir = (& git rev-parse --git-common-dir 2>$null) } catch { $gitDir = $null }
Pop-Location
if (-not $gitDir) { Write-Host "Depot git introuvable depuis $repoRoot" -ForegroundColor Red; exit 2 }
if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $repoRoot $gitDir }
$cible = Join-Path $gitDir 'hooks'

if (-not (Test-Path -LiteralPath $source)) { Write-Host "Aucun hook a installer ($source)"; exit 0 }
if (-not (Test-Path -LiteralPath $cible)) { New-Item -ItemType Directory -Path $cible -Force | Out-Null }

$ecarts = 0
foreach ($h in Get-ChildItem -LiteralPath $source -File) {
    $dst = Join-Path $cible $h.Name
    $identique = (Test-Path -LiteralPath $dst) -and
                 ((Get-FileHash $h.FullName).Hash -eq (Get-FileHash $dst).Hash)
    if ($identique) { Write-Host ("  a jour    {0}" -f $h.Name); continue }
    $ecarts++
    if ($Verifier) { Write-Host ("  A INSTALLER {0}" -f $h.Name) -ForegroundColor Yellow; continue }
    Copy-Item -LiteralPath $h.FullName -Destination $dst -Force
    Write-Host ("  installe  {0}" -f $h.Name) -ForegroundColor Green
}

if ($Verifier -and $ecarts -gt 0) {
    Write-Host "$ecarts hook(s) manquant(s) ou differents. Lance ce script sans -Verifier."
    exit 1
}
Write-Host ("Hooks : {0} -> {1}" -f $source, $cible)
exit 0
