# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    vigie-accounts.ps1 - QUELS COMPTES Windows ont Vigie. IDEMPOTENT.

    Le meme outil sert pendant l'installation et n'importe quand apres : « un outil doit
    toujours permettre de changer quel compte a acces » (exigence utilisateur, D65).

    Usage :
      pwsh -File .\scripts\vigie-accounts.ps1                     # liste
      pwsh -File .\scripts\vigie-accounts.ps1 -Activer Famille    # Vigie demarre pour ce compte
      pwsh -File .\scripts\vigie-accounts.ps1 -Retirer Famille    # ne demarre plus

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
    $lines = @(Get-UserAccounts | ForEach-Object {
        '{0} {1,-24} {2,-14} {3}' -f `
            $(if ($_.enabled) { '[x]' } else { '[ ]' }),
            $_.name,
            $(if ($_.admin) { 'administrateur' } else { 'standard' }),
            $(if ($_.current) { '(compte en cours)' } else { '' })
    })
    Write-Info (Get-Label 'vigie-accounts.comptes-de-cette-machine')
    $lines | ForEach-Object { Write-Host "  $_" }
}

if (-not $Activer -and -not $Retirer) { Show-Comptes; exit 0 }

$target = if ($Activer) { $Activer } else { $Retirer }
$connu = @(Get-AccountByName -Name $target)
if (-not $connu) {
    Write-Warn (Get-Label 'vigie-accounts.compte-inconnu-sur-cette' $target)
    Show-Comptes
    exit 1
}
if (-not (Test-IsElevated)) {
    Write-Warn (Get-Label 'vigie-accounts.cette-operation-demande-un')
    exit 3
}
try {
    Set-VigieAccountEnabled -Name $target -Enabled ([bool]$Activer) | Out-Null
    Write-Host $(if ($Activer) { "Vigie demarrera avec le compte $target." } else { "Vigie ne demarrera plus avec le compte $target." })
    Show-Comptes
    exit 0
} catch {
    Write-Fail (Get-Label 'vigie-accounts.echec' $($_.Exception.Message))
    exit 3
}
