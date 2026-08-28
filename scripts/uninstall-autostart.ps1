<#
    uninstall-autostart.ps1 - Retire l'acces permanent. IDEMPOTENT.

    Necessite les droits admin. Avant toute invite UAC, une fenetre explique ce
    qui va etre retire et pourquoi (D22).

    Ne connait QUE les noms courants. Les vestiges d'une installation anterieure
    au renommage Vigie sont traites par uninstall-legacy.ps1 (D11).

    Usage :  pwsh -ExecutionPolicy Bypass -File .\uninstall-autostart.ps1
             pwsh -ExecutionPolicy Bypass -File .\uninstall-autostart.ps1 -Yes   (sans fenetre)

    Codes de retour : 0 = retire ; 3 = refuse par l'utilisateur.
#>
param(
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
# Les scripts de gestion vivent dans scripts/ : les apps sont dans apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')
$taskName = 'Vigie'
$lnk      = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Vigie.url'

if (-not (Test-IsElevated)) {
    $ok = Show-ElevationRationale -AssumeYes:$Yes `
        -Title   "Retirer le démarrage automatique de Vigie" `
        -Summary "Vigie ne se lancera plus à l'ouverture de session. L'application et tes données restent en place : seul l'accès permanent est retiré." `
        -Changes @(
            "Suppression de la tâche planifiée '$taskName'",
            "Suppression du raccourci bureau : $lnk",
            "Aucun fichier de l'application n'est supprimé",
            "Réinstallable à tout moment avec install-autostart.ps1"
        )
    if (-not $ok) { Write-Host "Désinstallation annulée. Rien n'a été modifié."; exit 3 }

    $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments @('-Yes') -LogDir (Get-LogDir -Backend $backend)
    exit $code
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Info ("Tache '" + $taskName + "' retiree.")
} else {
    Write-Info ("Tache '" + $taskName + "' absente (rien a faire).")
}

if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force
    Write-Info ("Raccourci retire : " + $lnk)
} else {
    Write-Info "Raccourci bureau absent (rien a faire)."
}

Write-Info "Accès permanent retire."
exit 0
