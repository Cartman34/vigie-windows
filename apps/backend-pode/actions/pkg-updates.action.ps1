# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @execution: session   -- un gestionnaire de paquets appartient a la session qui l'a installe (D128)
<#
    Action: ask ONE package manager what it has to update, or update it, in the session of whoever asks.

    WHY IT EXISTS. The server app runs under a service account. It has no winget at all -- measured on 06/10, an MSIX
    package refuses to launch for an account it is not registered for, "Acces refuse", whatever its privilege -- and
    the packages a manager installed in a profile belong to that profile. Asked from the server, the question has no
    answer, or the wrong one: that of a account nobody uses.

    WHAT IT DOES. `check` lists what is pending; `upgrade` updates everything, or only the packages named. Both run
    the manager the way the person would themselves, with their PATH and their rights. winget asks for elevation
    when a package needs it, which the owner authorised on 06/10 for these updates.

    WHAT IT DOES NOT DO: decide, keep, or report. The worker that asked holds the operation, writes the result and
    invalidates the card. This action measures, nothing more.

    Parameters: mgr = the manager; op = 'check' (default) or 'upgrade'; pkgs = the packages kept (empty = all).
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$mgr = if ($Params -and $Params.mgr) { "$($Params.mgr)" } elseif ($Module) { $Module -replace '^pkg-', '' } else { $null }
if (-not $mgr) { return @{ message = "Gestionnaire non précisé."; result = @{ ok = $false } } }
$known = Get-PackageManagerCatalog | Where-Object { $_.id -eq $mgr } | Select-Object -First 1
if (-not $known) { return @{ message = "Gestionnaire inconnu : $mgr"; result = @{ ok = $false } } }

$op = if ($Params -and $Params.op) { "$($Params.op)" } else { 'check' }
if ($op -notin @('check', 'upgrade')) { return @{ message = "Opération inconnue : $op"; result = @{ ok = $false } } }
$pkgs = @()
if ($Params -and $Params.pkgs) { $pkgs = @($Params.pkgs | ForEach-Object { "$_" } | Where-Object { $_ -match '\S' }) }

# HERE, OR NOWHERE. The manager must exist IN THIS SESSION: that is the whole point of this action.
if (-not (Get-Command $mgr -ErrorAction SilentlyContinue)) {
    return @{ message = "$($known.label) n'est pas installé sur ce compte."; result = @{ ok = $false; absent = $true } }
}

$upgrade = $null
if ($op -eq 'upgrade') {
    try { $upgrade = Invoke-PkgUpgrade -Id $mgr -Pkgs $pkgs } catch {
        return @{ message = "Mise à jour impossible : $($_.Exception.Message)"; result = @{ ok = $false } }
    }
    # LET THE MANAGER CATCH ITS BREATH: the check that follows used to run within the second, and winget listed
    # again the package it had just installed (seen on 27/08). The pause lives here, with the installing.
    Start-Sleep -Seconds 12
}

$updates = $null
try { $updates = Get-PkgUpdates -Id $mgr } catch {
    return @{ message = "Lecture des mises à jour impossible : $($_.Exception.Message)"; result = @{ ok = $false } }
}

@{
    message = $(if ($op -eq 'upgrade') { "Mise à jour de $($known.label) terminée." }
                else { "$([int]$updates.count) mise(s) à jour pour $($known.label)." })
    result  = @{ ok = $true; mgr = $mgr; op = $op
                 updates = $updates
                 upgrade = $upgrade
                 at = (Get-Date).ToUniversalTime().ToString('o') }
}
