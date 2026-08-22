<#
    uninstall-legacy.ps1 - Retire les vestiges des installations ANTERIEURES au
    renommage Vigie (2026-08-22). IDEMPOTENT.

    Perimetre : tout poste installe AVANT le renommage, quand la tache planifiee,
    le raccourci bureau et l'espace de travail portaient encore le nom de la machine
    de l'auteur. Voir docs/DECISIONS-VALIDEES.md (D05, D07, D11).

    Ce script est DATE et JETABLE. Il est volontairement SEPARE de
    uninstall-autostart.ps1, qui ne doit connaitre que les noms courants : les
    anciens noms vivent ici et disparaitront avec ce fichier une fois tous les
    postes migres.

    Ce script ne SUPPRIME jamais de dossier : l'ancien espace de travail est
    seulement mis de cote (suffixe .old).

    Prerequis : session ELEVEE (la tache planifiee est enregistree en RunLevel
    Highest). Le script ne s'auto-eleve pas, pour que son compte rendu reste lisible.

    Usage :
      pwsh -ExecutionPolicy Bypass -File .\uninstall-legacy.ps1
      pwsh -ExecutionPolicy Bypass -File .\uninstall-legacy.ps1 -LegacyWorkspace 'C:\chemin\vers\ancien-dossier'
      pwsh -ExecutionPolicy Bypass -File .\uninstall-legacy.ps1 -WhatIf

    Codes de retour : 0 = termine sans erreur ; 1 = prerequis manquant ; 2 = au moins une etape en echec.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Ancien espace de travail a mettre de cote. Machine-specifique : aucune valeur
    # par defaut, sinon le script porterait un chemin d'une machine particuliere.
    [string] $LegacyWorkspace
)

$ErrorActionPreference = 'Stop'

# --- Noms herites, confines a ce fichier ---------------------------------------
$LegacyTaskNames     = @('HyperionControlPanel')
$LegacyShortcutNames = @('HYPERION Control Panel.url')

# --- Prerequis -----------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Session non elevee. Relance ce script depuis un PowerShell administrateur." -ForegroundColor Yellow
    exit 1
}

$done = 0
$skipped = 0
$failed = 0

function Invoke-Step {
    param([string] $Label, [scriptblock] $Action)
    try {
        & $Action
    } catch {
        Write-Host ("ECHEC  " + $Label + " : " + $_.Exception.Message) -ForegroundColor Red
        $script:failed++
    }
}

# --- Taches planifiees heritees -------------------------------------------------
foreach ($name in $LegacyTaskNames) {
    Invoke-Step ("tache '" + $name + "'") {
        $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host ("ABSENT tache '" + $name + "' (rien a faire)")
            $script:skipped++
            return
        }
        if ($PSCmdlet.ShouldProcess($name, 'Unregister-ScheduledTask')) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Host ("RETIRE tache '" + $name + "'") -ForegroundColor Green
            $script:done++
        }
    }
}

# --- Raccourcis bureau herites --------------------------------------------------
$desktop = [Environment]::GetFolderPath('Desktop')
foreach ($shortcut in $LegacyShortcutNames) {
    Invoke-Step ("raccourci '" + $shortcut + "'") {
        $path = Join-Path $desktop $shortcut
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host ("ABSENT raccourci '" + $shortcut + "' (rien a faire)")
            $script:skipped++
            return
        }
        if ($PSCmdlet.ShouldProcess($path, 'Remove-Item')) {
            Remove-Item -LiteralPath $path -Force
            Write-Host ("RETIRE raccourci " + $path) -ForegroundColor Green
            $script:done++
        }
    }
}

# --- Ancien espace de travail (mise de cote, jamais de suppression) --------------
if ($LegacyWorkspace) {
    Invoke-Step ("espace de travail '" + $LegacyWorkspace + "'") {
        if (-not (Test-Path -LiteralPath $LegacyWorkspace)) {
            Write-Host ("ABSENT espace de travail " + $LegacyWorkspace + " (rien a faire)")
            $script:skipped++
            return
        }
        $target = $LegacyWorkspace.TrimEnd('\') + '.old'
        if (Test-Path -LiteralPath $target) {
            Write-Host ("IGNORE " + $target + " existe deja - mise de cote non refaite") -ForegroundColor Yellow
            $script:skipped++
            return
        }
        if ($PSCmdlet.ShouldProcess($LegacyWorkspace, ('Rename-Item -> ' + (Split-Path $target -Leaf)))) {
            Rename-Item -LiteralPath $LegacyWorkspace -NewName (Split-Path $target -Leaf)
            Write-Host ("MIS DE COTE " + $LegacyWorkspace + " -> " + $target) -ForegroundColor Green
            Write-Host "  (dossier conserve : supprime-le toi-meme une fois la migration confirmee)"
            $script:done++
        }
    }
} else {
    Write-Host "IGNORE espace de travail : aucun -LegacyWorkspace fourni."
    $skipped++
}

# --- Compte rendu ---------------------------------------------------------------
Write-Host ""
Write-Host ("Termine : " + $done + " action(s), " + $skipped + " ignoree(s), " + $failed + " echec(s).")
if ($failed -gt 0) { exit 2 }
exit 0
