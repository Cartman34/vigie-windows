# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
<# The update-mode-on action: it switches to UPDATE MODE (it lifts the lock).

   Intent: be a NATIVE ability of the product -- no dependency on tooling outside the repository. All the writing
   goes through Set-UpdateLock (lib/common.ps1), the single entry point (D15), which reads the real state back
   after acting.
   Usage: it is called from the Windows Update card. Idempotent: lifting a lock that is already lifted returns a
   success, not an error -- the state asked for IS the machine's state, and that is all that counts. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent          # actions/ -> backend/
. (Join-Path $backend 'lib/common.ps1')

$inv = @('lock.probe.ps1','pending.probe.ps1')

# The elevation is stated BEFORE acting: without it, icacls and takeown fail in silence and
# l'utilisateur croirait avoir deverrouille.
if (-not (Test-Elevated)) {
    return @{
        message = "Le serveur de Vigie n'est pas administrateur : le verrou ne peut pas être levé. Vigie doit être relancée en administrateur (l'invite UAC s'affichera)."
        result  = @{ ok = $false }
    }
}

$before = Get-UpdateLockState
if (-not $before.aclLock -and -not $before.autoUpdatesOff) {
    return @{
        message = 'Le mode mise à jour est déjà actif : Windows Update est déverrouillé.'
        result  = @{ ok = $true; invalidate = $inv }
    }
}

$ok = Set-UpdateLock -State 'leve' -Backend $backend
$after = Get-UpdateLockState

# What is reported is what was OBSERVED afterwards (D43), never "the command did not raise an error".
if ($ok -and -not $after.autoUpdatesOff) {
    @{
        message = 'Mode mise à jour ACTIVÉ : Windows Update est déverrouillé. Les mises à jour peuvent s''installer ; redémarrer au moment voulu, puis re-verrouiller.'
        result  = @{ ok = $true; invalidate = $inv }
    }
} elseif ($ok) {
    @{
        message = "Verrou des tâches levé, mais les mises à jour automatiques sont restées coupées (NoAutoUpdate=$($after.noAutoUpdate)). Windows Update reste utilisable manuellement."
        result  = @{ ok = $true; invalidate = $inv }
    }
} else {
    @{
        message = "Le verrou n'a PAS pu être levé (verrou ACL toujours posé). Détails dans apps/backend-pode/var/log/updatelock_*.log."
        result  = @{ ok = $false; invalidate = $inv }
    }
}
