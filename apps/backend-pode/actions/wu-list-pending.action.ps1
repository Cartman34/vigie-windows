# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : liste les mises a jour Windows detectees et NON installees.

   LECTURE SEULE. Sert a remplir la fenetre de choix de l'interface : on ne peut pas
   demander a l'utilisateur QUOI installer sans lui montrer la liste avec un identifiant
   stable par ligne.

   ELLE NE CONSTRUIT PLUS LA LISTE ELLE-MEME. Get-PendingUpdateList la fabrique une fois
   pour la carte ET pour cette fenetre : les deux ont compte chacun de leur cote jusqu'au
   11/09, la carte annoncait 49 et la fenetre en proposait 48.
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

# Le verrouillage des taches (Mode MAJ) empeche l'installation : on le DIT ici plutot que
# de laisser l'installation echouer sans explication.
$verrou = $false
try { $verrou = Test-UpdateTasksAclLock } catch { }

$aside = if ($pending.setAsideOlder -gt 0) {
    " $($pending.setAsideOlder) version(s) plus ancienne(s) du même pilote ne sont pas proposées."
} else { '' }

@{
    message = "$(@($pending.offered).Count) mise(s) à jour à installer.$aside"
    result  = @{
        ok       = $true
        choose   = $true          # l'interface doit ouvrir une fenetre de choix
        action   = 'wu-install'   # action a appeler avec les identifiants retenus
        verrou   = $verrou
        updates  = @($pending.offered)
    }
}
