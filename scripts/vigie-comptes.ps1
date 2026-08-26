<#
    vigie-comptes.ps1 - QUELS COMPTES Windows ont Vigie. IDEMPOTENT.

    Le meme outil sert pendant l'installation et n'importe quand apres : « un outil doit
    toujours permettre de changer quel compte a acces » (exigence utilisateur, D65).

    Usage :
      pwsh -File .\scripts\vigie-comptes.ps1                     # liste
      pwsh -File .\scripts\vigie-comptes.ps1 -Activer Famille    # Vigie demarre pour ce compte
      pwsh -File .\scripts\vigie-comptes.ps1 -Retirer Famille    # ne demarre plus

    Activer = poser SA tache de demarrage, au niveau que Windows accorde a ce compte
    (administrateur -> eleve, standard -> limite). Vigie ne donne rien de plus que Windows.

    Codes de retour : 0 = fait ; 1 = compte inconnu ; 3 = droits insuffisants.
#>
param(
    [string]$Activer,
    [string]$Retirer
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

function Show-Comptes {
    # Uniquement les comptes utilisateurs : un profil qui n'a jamais servi est un
    # compte d'outil.
    $lignes = @(Get-VigieAccounts | Where-Object { -not $_.technical } | ForEach-Object {
        '{0} {1,-24} {2,-14} {3}' -f `
            $(if ($_.enabled) { '[x]' } else { '[ ]' }),
            $_.name,
            $(if ($_.admin) { 'administrateur' } else { 'standard' }),
            $(if ($_.current) { '(compte en cours)' } else { '' })
    })
    Write-Host ""
    Write-Host "Comptes de cette machine ([x] = Vigie demarre avec ce compte) :"
    $lignes | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

if (-not $Activer -and -not $Retirer) { Show-Comptes; exit 0 }

$cible = if ($Activer) { $Activer } else { $Retirer }
$connu = @(Get-VigieAccounts | Where-Object { $_.name -eq $cible })
if (-not $connu) {
    Write-Host "Compte inconnu sur cette machine : $cible" -ForegroundColor Yellow
    Show-Comptes
    exit 1
}
if (-not (Test-IsElevated)) {
    Write-Host "Cette operation demande un PowerShell administrateur (creer ou retirer une tache planifiee)." -ForegroundColor Yellow
    exit 3
}
try {
    Set-VigieAccountEnabled -Name $cible -Enabled ([bool]$Activer) | Out-Null
    Write-Host $(if ($Activer) { "Vigie demarrera avec le compte $cible." } else { "Vigie ne demarrera plus avec le compte $cible." })
    Show-Comptes
    exit 0
} catch {
    Write-Host "Echec : $($_.Exception.Message)" -ForegroundColor Red
    exit 3
}
