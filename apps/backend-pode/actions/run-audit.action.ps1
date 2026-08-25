# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action run-audit : audit complet de la machinerie Windows Update. LECTURE SEULE.

   Capacite NATIVE du produit (Invoke-UpdateAudit, lib/common.ps1) : un outil de
   diagnostic qui exige un outillage hors depot ne sert plus au moment ou l'on en a
   besoin. Le rapport est ecrit sous var/log/ (texte + JSON), comme tout ce que
   l'application genere. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$audit = Invoke-UpdateAudit -Backend $backend

# D43 : on annonce le rapport parce que le FICHIER existe, pas parce que l'appel est passe.
if (-not $audit.ok) {
    return @{
        message = "L'audit s'est exécuté mais le rapport n'a pas pu être écrit dans apps/backend-pode/var/log/."
        result  = @{ ok = $false }
    }
}

$e = $audit.state
$resume = if ($e.locked) { 'verrou complet en place' }
          elseif ($e.autoUpdatesOff) { 'MAJ automatiques coupées, verrou ACL absent' }
          elseif ($e.aclLock) { 'verrou ACL posé, MAJ automatiques actives' }
          else { 'aucun verrouillage' }
$reserve = if ($audit.elevated) { '' } else { " Serveur non administrateur : une partie de l'état n'a pas pu être lue." }

@{
    message = "Audit terminé : $resume ; $($e.tasksDisabled) tâche(s) désactivée(s), $($e.tasksReady) active(s). Rapport : $($audit.txt)$reserve"
    result  = @{ ok = $true; invalidate = @('lock.probe.ps1') }
}
