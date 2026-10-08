# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    uninstall-autostart.ps1 -- removes the permanent access. IDEMPOTENT.

    Intent: take back exactly what install-autostart.ps1 laid down, and nothing else -- the application and its
    data stay in place.
    Usage:  pwsh -ExecutionPolicy Bypass -File .\uninstall-autostart.ps1
            pwsh -ExecutionPolicy Bypass -File .\uninstall-autostart.ps1 -Yes   (no window)
    Exit codes: 0 = removed; 3 = refused by the user.

    It needs administrator rights. Before any UAC prompt, a window explains what is about to be removed and why
    (D22).

    It knows the current names ONLY. The remains of an installation made before the rename to Vigie are handled
    by uninstall-legacy.ps1 (D11).
#>
param(
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
# The management scripts live in scripts/: the apps are in apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # the same display as everywhere
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, see common.ps1
. (Join-Path $backend 'lib/common.ps1')
$taskName = 'Vigie'
$lnk      = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Vigie.url'

if (-not (Test-IsElevated)) {
    $ok = Show-ElevationRationale -AssumeYes:$Yes `
        -Title   "Retirer le démarrage automatique de Vigie" `
        -Summary "Vigie ne se lancera plus à l'ouverture de session. L'application et ses données restent en place : seul l'accès permanent est retiré." `
        -Changes @(
            "Suppression de la tâche planifiée '$taskName'",
            "Suppression du raccourci bureau : $lnk",
            "Aucun fichier de l'application n'est supprimé",
            "Réinstallable à tout moment avec install-autostart.ps1"
        )
    if (-not $ok) { Write-Host (Get-Label 'uninstall-autostart.desinstallation-annulee-rien-ete'); exit 3 }

    $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments @('-Yes') -LogDir (Get-LogDir -Backend $backend)
    exit $code
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Info (Get-Label 'uninstall-autostart.tache-retiree' $taskName)
} else {
    Write-Info (Get-Label 'uninstall-autostart.tache-absente-rien-faire' $taskName)
}

if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force
    Write-Info (Get-Label 'uninstall-autostart.raccourci-retire' $lnk)
} else {
    Write-Info (Get-Label 'uninstall-autostart.raccourci-bureau-absent-rien')
}

Write-Info (Get-Label 'uninstall-autostart.acces-permanent-retire')
exit 0
