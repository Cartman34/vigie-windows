# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    uninstall-legacy.ps1 - Retire les vestiges des installations ANTERIEURES au
    renommage Vigie (2026-08-22). IDEMPOTENT.

    Perimetre : tout poste installe AVANT le renommage, quand la tache planifiee,
    le raccourci bureau et l'espace de travail portaient encore le nom de la machine
    de l'auteur. Voir doc/progress/decisions.md (D05, D07, D11).

    Ce script est DATE et JETABLE. Il est volontairement SEPARE de
    uninstall-autostart.ps1, qui ne doit connaitre que les noms courants : les
    anciens noms vivent ici et disparaitront avec ce fichier une fois tous les
    postes migres.

    Ce script ne SUPPRIME jamais de dossier : l'ancien espace de travail est
    seulement mis de cote (suffixe .old).

    Necessite les droits admin (la tache planifiee est en RunLevel Highest). Avant
    toute invite UAC, une fenetre explique ce qui va etre retire et pourquoi (D22).
    La session elevee ecrit un journal, restitue ici : rien n'est perdu.

    Usage :
      pwsh -ExecutionPolicy Bypass -File .\uninstall-legacy.ps1 -WhatIf
      pwsh -ExecutionPolicy Bypass -File .\uninstall-legacy.ps1 -LegacyWorkspace 'C:\chemin\vers\ancien-dossier'

    Codes de retour : 0 = termine sans erreur ; 2 = au moins une etape en echec ;
                      3 = refuse par l'utilisateur.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Ancien espace de travail a mettre de cote. Machine-specifique : aucune valeur
    # par defaut, sinon le script porterait un chemin d'une machine particuliere.
    [string] $LegacyWorkspace,
    # Passe l'explication graphique : execution volontairement automatisee.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
# Les scripts de gestion vivent dans scripts/ : la bibliotheque est dans apps/backend.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

# --- Noms herites, confines a ce fichier ---------------------------------------
$LegacyTaskNames     = @('HyperionControlPanel')
$LegacyShortcutNames = @('HYPERION Control Panel.url')

# --- Consentement puis elevation (D22) ------------------------------------------
if (-not (Test-IsElevated)) {
    $changes = @(
        "Suppression de la tâche planifiée héritée : " + ($LegacyTaskNames -join ', '),
        "Suppression du raccourci bureau hérité : " + ($LegacyShortcutNames -join ', ')
    )
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

# Trace d'entree : un script de migration doit dire ce qu'il a recu, sinon un compte
# rendu vide est indistinguable d'un "rien a faire".
$ws = if ($LegacyWorkspace) { $LegacyWorkspace } else { '(aucun)' }
Write-Info (Get-Label 'uninstall-legacy.nettoyage-des-vestiges-taches' $LegacyTaskNames -join ', ' $LegacyShortcutNames -join ', ' $ws $WhatIfPreference)
$done = 0
$skipped = 0
$planned = 0
$failed = 0

# -WhatIf : les messages "What if:" de ShouldProcess sont ecrits DIRECTEMENT sur l'hote
# et non dans un flux redirigeable. En session elevee cachee, la sortie est capturee par
# redirection : ces messages sont donc perdus et le compte rendu arrive vide. On emet
# notre propre ligne, qui passe par le journal comme tout le reste.
# Renvoie $true s'il faut REELLEMENT appliquer le changement.
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

# --- Ancien espace de travail (mise de cote, jamais de suppression) --------------
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
