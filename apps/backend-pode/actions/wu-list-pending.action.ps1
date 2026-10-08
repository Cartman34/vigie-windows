# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# An action: it lists the Windows updates that were detected and NOT installed.

   Intent: let somebody be asked WHAT to install, which is impossible without showing them the list with a
   stable identifier per line. READ ONLY.
   Usage: it fills the interface's window of choice. IT NO LONGER BUILDS THE LIST ITSELF.
   Get-PendingUpdateList builds it once for the card AND for this window: the two counted on their own side
   until 11/09, the card announcing 49 while the window offered 48. #>
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$pending = Get-PendingUpdateList -Backend $backend
if (-not $pending.ok) {
    return @{
        message = "Impossible de lire la liste des mises à jour."
        result  = @{ ok = $false }
    }
}

# Locking the tasks (Update Mode) prevents the installation: we SAY SO here rather than let the installation fail
# with no explanation.
$lock = $false
try { $lock = Test-UpdateTasksAclLock } catch { }

$aside = if ($pending.setAsideOlder -gt 0) {
    " $($pending.setAsideOlder) version(s) plus ancienne(s) du même pilote ne sont pas proposées."
} else { '' }

@{
    message = "$(@($pending.offered).Count) mise(s) à jour à installer.$aside"
    result  = @{
        ok       = $true
        choose   = $true          # l'interface doit ouvrir une fenetre de choix
        action   = 'wu-install'   # action a appeler avec les identifiants retenus
        verrou   = $lock
        updates  = @($pending.offered)
    }
}
