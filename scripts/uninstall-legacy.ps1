# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    uninstall-legacy.ps1 -- removes the remains of installations made BEFORE the rename to Vigie (2026-08-22).
    IDEMPOTENT.

    Intent: let a workstation installed under the old names come back to a clean state, and let the current
    uninstaller know nothing of those names.
    Usage:
      pwsh -ExecutionPolicy Bypass -File .\uninstall-legacy.ps1 -WhatIf
      pwsh -ExecutionPolicy Bypass -File .\uninstall-legacy.ps1 -LegacyWorkspace 'C:/path/to/old-folder'
    Exit codes: 0 = finished without an error; 2 = at least one step failed; 3 = refused by the user.

    Scope: any workstation installed BEFORE the rename, when the scheduled task, the desktop shortcut and the
    working folder still carried the name of the author's machine. See doc/progress/decisions.md (D05, D07, D11).

    This script is DATED and DISPOSABLE. It is deliberately SEPARATE from uninstall-autostart.ps1, which must
    know only the current names: the old names live here and will disappear with this file once every workstation
    has been migrated.

    This script never DELETES a folder: the old working folder is merely set aside (with a .old suffix).

    It needs administrator rights (the scheduled task is at RunLevel Highest). Before any UAC prompt, a window
    explains what is about to be removed and why (D22). The elevated session writes a log, handed back here:
    nothing is lost.
#>


[CmdletBinding(SupportsShouldProcess)]
param(
    # The old working folder to set aside. Machine-specific: no default value, otherwise the script would carry
    # the path of one particular machine.
    [string] $LegacyWorkspace,
    # Skip the graphical explanation: a deliberately automated run.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
# The management scripts live in scripts/: the library is in apps/backend-pode.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

# --- The inherited names, confined to this file -------------------------------
$LegacyTaskNames     = @('HyperionControlPanel')
$LegacyShortcutNames = @('HYPERION Control Panel.url')

# --- Consentement puis elevation (D22) ------------------------------------------
if (-not (Test-IsElevated)) {
    # THE COMMA BINDS TIGHTER THAN THE PLUS: written inside the array, these two
    # concatenations became ONE, and the consent window showed a single mangled line
    # instead of the two changes it announced.
    $taskLine     = "Suppression de la tâche planifiée héritée : " + ($LegacyTaskNames -join ', ')
    $shortcutLine = "Suppression du raccourci bureau hérité : " + ($LegacyShortcutNames -join ', ')
    $changes = @($taskLine, $shortcutLine)
    if ($LegacyWorkspace) {
        $changes += "Ancien espace de travail MIS DE CÔTÉ (renommé en .old, jamais supprimé) : $LegacyWorkspace"
    } else {
        $changes += "Aucun ancien espace de travail indiqué : rien ne sera renommé"
    }
    $changes += "Aucun dossier n'est supprimé, aucune donnée n'est perdue"
    if ($WhatIfPreference) { $changes += "MODE SIMULATION (-WhatIf) : rien ne sera réellement modifié" }

    $ok = Show-ElevationRationale -AssumeYes:$Yes `
        -Title   "Nettoyer les vestiges de l'ancienne installation" `
        -Summary "Une installation antérieure au renommage Vigie a laissé une tâche planifiée et un raccourci orphelins. Ce nettoyage les retire." `
        -Changes $changes
    if (-not $ok) { Write-Host (Get-Label 'uninstall-legacy.nettoyage-annule-rien-ete'); exit 3 }

    $argv = @()
    if ($LegacyWorkspace) { $argv += @('-LegacyWorkspace', $LegacyWorkspace) }
    if ($WhatIfPreference) { $argv += '-WhatIf' }
    $argv += '-Yes'
    $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments $argv -LogDir (Get-LogDir -Backend $backend)
    exit $code
}

# A trace on entry: a migration script must say what it received, otherwise an empty report cannot be told from a
# "nothing to do".
$ws = if ($LegacyWorkspace) { $LegacyWorkspace } else { '(aucun)' }
Write-Info (Get-Label 'uninstall-legacy.nettoyage-des-vestiges-taches' $LegacyTaskNames -join ', ' $LegacyShortcutNames -join ', ' $ws $WhatIfPreference)
$done = 0
$skipped = 0
$planned = 0
$failed = 0

# -WhatIf: the "What if:" messages of ShouldProcess are written DIRECTLY to the host and not into a redirectable
# stream. In a hidden elevated session the output is captured by redirection: so those messages are lost and the
# report arrives empty. We emit our own line, which goes through the log like everything else.
# Returns $true when the change must REALLY be applied.
function Test-ShouldApply {
    param([Parameter(Mandatory)][string] $Operation, [Parameter(Mandatory)][string] $Target)
    if ($WhatIfPreference) {
        Write-Step (Get-Label 'uninstall-legacy.simulation' $Operation $Target)
        $script:planned++
        return $false
    }
    return $true
}

function Invoke-Step {
    param([string] $Label, [scriptblock] $Action)
    try {
        & $Action
    } catch {
        Write-Fail (Get-Label 'uninstall-legacy.echec' $Label $_.Exception.Message)
        $script:failed++
    }
}

# --- Taches planifiees heritees -------------------------------------------------
foreach ($name in $LegacyTaskNames) {
    Invoke-Step ("tache '" + $name + "'") {
        $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Info (Get-Label 'uninstall-legacy.absent-tache-rien-faire' $name)
            $script:skipped++
            return
        }
        if (Test-ShouldApply -Operation "Supprimer la tache planifiee" -Target $name) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Ok (Get-Label 'uninstall-legacy.retire-tache' $name)
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
            Write-Info (Get-Label 'uninstall-legacy.absent-raccourci-rien-faire' $shortcut)
            $script:skipped++
            return
        }
        if (Test-ShouldApply -Operation "Supprimer le raccourci" -Target $path) {
            Remove-Item -LiteralPath $path -Force
            Write-Ok (Get-Label 'uninstall-legacy.retire-raccourci' $path)
            $script:done++
        }
    }
}

# --- The old working folder (set aside, never deleted) ------------------------
if ($LegacyWorkspace) {
    Invoke-Step ("espace de travail '" + $LegacyWorkspace + "'") {
        if (-not (Test-Path -LiteralPath $LegacyWorkspace)) {
            Write-Info (Get-Label 'uninstall-legacy.absent-espace-de-travail' $LegacyWorkspace)
            $script:skipped++
            return
        }
        $target = $LegacyWorkspace.TrimEnd('\') + '.old'
        if (Test-Path -LiteralPath $target) {
            Write-Warn (Get-Label 'uninstall-legacy.ignore-existe-deja-mise' $target)
            $script:skipped++
            return
        }
        if (Test-ShouldApply -Operation ("Renommer en " + (Split-Path $target -Leaf)) -Target $LegacyWorkspace) {
            Rename-Item -LiteralPath $LegacyWorkspace -NewName (Split-Path $target -Leaf)
            Write-Ok (Get-Label 'uninstall-legacy.mis-de-cote' $LegacyWorkspace $target)
            Write-Info (Get-Label 'uninstall-legacy.dossier-conserve-supprime-le')
            $script:done++
        }
    }
} else {
    Write-Info (Get-Label 'uninstall-legacy.ignore-espace-de-travail')
    $skipped++
}

# --- Compte rendu ---------------------------------------------------------------
if ($WhatIfPreference) {
    Write-Info (Get-Label 'uninstall-legacy.simulation-terminee-changement-prevu' $planned $skipped $failed)
    Write-Info (Get-Label 'uninstall-legacy.relance-la-meme-commande')
} else {
    Write-Info (Get-Label 'uninstall-legacy.termine-action-ignoree-echec' $done $skipped $failed)
}
if ($failed -gt 0) { exit 2 }
exit 0
