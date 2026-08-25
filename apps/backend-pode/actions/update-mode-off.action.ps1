# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
# @libelle: Verrouiller maintenant | immediate | fix   -- affiche quand un champ cite cette action (D66)
<# Action update-mode-off : RE-VERROUILLE (coupe les MAJ auto + pose le verrou ACL).

   Capacite NATIVE du produit : aucune dependance a un outillage hors depot. Toute
   l'ecriture passe par Set-UpdateLock (lib/common.ps1), unique porte d'entree (D15),
   qui relit l'etat reel apres avoir agi.

   Idempotent : re-poser un verrou deja pose rend un succes tranquille. Le verrou est
   d'ailleurs a REPOSER regulierement -- Windows le defait de lui-meme apres certaines
   mises a jour. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$inv = @('lock.probe.ps1','pending.probe.ps1')

if (-not (Test-Elevated)) {
    return @{
        message = "Le serveur de Vigie n'est pas administrateur : le verrou ne peut pas être posé. Relancez Vigie en administrateur (l'invite UAC s'affichera)."
        result  = @{ ok = $false }
    }
}

$avant = Get-UpdateLockState
if ($avant.locked) {
    return @{
        message = 'Le verrouillage complet est déjà en place : mises à jour automatiques coupées et verrou ACL posé.'
        result  = @{ ok = $true; invalidate = $inv }
    }
}

# La valeur de retour de Set-UpdateLock ne porte que la moitie ACL du verrou ; le compte
# rendu ci-dessous s'appuie sur l'etat COMPLET relu juste apres.
$null = Set-UpdateLock -Etat 'pose' -Backend $backend
$apres = Get-UpdateLockState

# On rapporte l'etat CONSTATE (D43). Les deux moities du verrou sont distinguees : couper
# les MAJ auto sans poser le verrou ACL est un resultat partiel, pas un succes.
if ($apres.locked) {
    @{
        message = 'Verrou complet appliqué : mises à jour automatiques coupées ET verrou ACL posé.'
        result  = @{ ok = $true; invalidate = $inv }
    }
} elseif ($apres.autoUpdatesOff) {
    @{
        message = "Mises à jour automatiques coupées, mais le verrou ACL n'a PAS pu être posé (dossiers protégés par Windows). Détails dans apps/backend-pode/var/log/updatelock_*.log."
        result  = @{ ok = $false; invalidate = $inv }
    }
} else {
    @{
        message = "Échec du verrouillage : ni verrou ACL, ni coupure des mises à jour automatiques (NoAutoUpdate=$($apres.noAutoUpdate)). Détails dans apps/backend-pode/var/log/updatelock_*.log."
        result  = @{ ok = $false; invalidate = $inv }
    }
}
