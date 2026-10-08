# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
# @libelle: Verrouiller maintenant | immediate | fix   -- affiche quand un champ cite cette action (D66)
<# The update-mode-off action: it LOCKS AGAIN (it switches automatic updates off and lays the ACL lock down).

   Intent: be a NATIVE ability of the product -- no dependency on tooling outside the repository. All the writing
   goes through Set-UpdateLock (lib/common.ps1), the single entry point (D15), which reads the real state back
   after acting.
   Usage: it is called from the Windows Update card. Idempotent: laying down a lock that is already there returns
   a quiet success. The lock has in fact to be LAID AGAIN regularly -- Windows undoes it by itself after certain
   updates. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$inv = @('lock.probe.ps1','pending.probe.ps1')

if (-not (Test-Elevated)) {
    return @{
        message = "Le serveur de Vigie n'est pas administrateur : le verrou ne peut pas être posé. Vigie doit être relancée en administrateur (l'invite UAC s'affichera)."
        result  = @{ ok = $false }
    }
}

$before = Get-UpdateLockState
if ($before.locked) {
    return @{
        message = 'Le verrouillage complet est déjà en place : mises à jour automatiques coupées et verrou ACL posé.'
        result  = @{ ok = $true; invalidate = $inv }
    }
}

# Set-UpdateLock's return value carries only the ACL half of the lock; the count
# rendu ci-dessous s'appuie sur l'etat COMPLET relu juste apres.
$null = Set-UpdateLock -State 'pose' -Backend $backend
$after = Get-UpdateLockState

# We report the OBSERVED state (D43). The two halves of the lock are told apart: switching automatic updates off
# without laying the ACL lock down is a partial result, not a success.
if ($after.locked) {
    @{
        message = 'Verrou complet appliqué : mises à jour automatiques coupées ET verrou ACL posé.'
        result  = @{ ok = $true; invalidate = $inv }
    }
} elseif ($after.autoUpdatesOff) {
    @{
        message = "Mises à jour automatiques coupées, mais le verrou ACL n'a PAS pu être posé (dossiers protégés par Windows). Détails dans apps/backend-pode/var/log/updatelock_*.log."
        result  = @{ ok = $false; invalidate = $inv }
    }
} else {
    @{
        message = "Échec du verrouillage : ni verrou ACL, ni coupure des mises à jour automatiques (NoAutoUpdate=$($after.noAutoUpdate)). Détails dans apps/backend-pode/var/log/updatelock_*.log."
        result  = @{ ok = $false; invalidate = $inv }
    }
}
