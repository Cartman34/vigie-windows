# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
<# Action update-mode-on : passe en MODE MISE A JOUR (leve le verrou).

   Capacite NATIVE du produit : aucune dependance a un outillage hors depot. Toute
   l'ecriture passe par Set-UpdateLock (lib/common.ps1), unique porte d'entree (D15),
   qui relit l'etat reel apres avoir agi.

   Idempotent : lever un verrou deja leve rend un succes, pas une erreur -- l'etat
   demande EST celui de la machine, c'est tout ce qui compte. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent          # actions/ -> backend/
. (Join-Path $backend 'lib/common.ps1')

$inv = @('lock.probe.ps1','pending.probe.ps1')

# L'elevation se dit AVANT d'agir : sans elle, icacls et takeown echouent en silence et
# l'utilisateur croirait avoir deverrouille.
if (-not (Test-Elevated)) {
    return @{
        message = "Le serveur de Vigie n'est pas administrateur : le verrou ne peut pas être levé. Relancez Vigie en administrateur (l'invite UAC s'affichera)."
        result  = @{ ok = $false }
    }
}

$avant = Get-UpdateLockState
if (-not $avant.aclLock -and -not $avant.autoUpdatesOff) {
    return @{
        message = 'Le mode mise à jour est déjà actif : Windows Update est déverrouillé.'
        result  = @{ ok = $true; invalidate = $inv }
    }
}

$ok = Set-UpdateLock -Etat 'leve' -Backend $backend
$apres = Get-UpdateLockState

# Ce qui est rapporte est ce qui a ete OBSERVE apres coup (D43), jamais « la commande
# n'a pas leve d'erreur ».
if ($ok -and -not $apres.autoUpdatesOff) {
    @{
        message = 'Mode mise à jour ACTIVÉ : Windows Update est déverrouillé. Installez vos mises à jour, redémarrez quand vous le souhaitez, puis re-verrouillez.'
        result  = @{ ok = $true; invalidate = $inv }
    }
} elseif ($ok) {
    @{
        message = "Verrou des tâches levé, mais les mises à jour automatiques sont restées coupées (NoAutoUpdate=$($apres.noAutoUpdate)). Windows Update reste utilisable manuellement."
        result  = @{ ok = $true; invalidate = $inv }
    }
} else {
    @{
        message = "Le verrou n'a PAS pu être levé (verrou ACL toujours posé). Détails dans apps/backend-pode/var/log/updatelock_*.log."
        result  = @{ ok = $false; invalidate = $inv }
    }
}
