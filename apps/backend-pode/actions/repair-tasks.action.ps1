# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- reecrire une tache planifiee exige l'elevation (D65)
# @libelle: Vérifier le démarrage de Vigie | immediate | fix   -- affiche quand un champ cite cette action (D66)
#
# « Réparer » quand rien n'est cassé sonne faux, et c'est pourtant l'état normal : le bouton
# reste sur la carte même quand tout va bien (D59, D66). Il VÉRIFIE d'abord, et ne répare
# que ce qui doit l'être -- son libellé dit donc ce qu'il fait à coup sûr, pas ce qu'il fait
# parfois.
<# Action : remet d'aplomb les taches de demarrage DE VIGIE, et rien d'autre.

   Autorise explicitement par l'utilisateur : « l'app peut auto-corriger le systeme tant
   que c'est du pur Vigie ». On ne touche donc qu'aux taches nommees « Vigie » ou
   « Vigie - <compte> », jamais a autre chose.

   Le cas qui a motive ceci : les taches pointaient vers un pwsh installe dans le profil
   d'un compte, disparu apres un changement d'installation de PowerShell. Windows n'a
   rien dit -- la tache existait, se lancait, et mourait aussitot. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$done = @(Repair-VigieTasks -Backend $backend)
if (-not $done.Count) {
    return @{ message = "Vérification faite : les tâches de démarrage de Vigie sont saines."
              result  = @{ ok = $true; invalidate = @('comptes.probe.ps1', 'deployment.probe.ps1') } }
}
# TROIS SORTS, pas deux. Une tache peut etre reecrite sans que le defaut disparaisse :
# un echec deja inscrit dans son historique ne s'efface qu'a sa prochaine execution,
# c'est-a-dire a la prochaine ouverture de session du compte. Le dire, plutot que
# d'annoncer « réparée » pendant que l'ecran affiche « hors service » juste a cote.
$ok      = @($done | Where-Object { $_.repare })
$waitMs = @($done | Where-Object { $_.attente })
$restant = @($done | Where-Object { -not $_.repare -and -not $_.attente -and $_.reste })
$ko      = @($done | Where-Object { -not $_.repare -and -not $_.attente -and -not $_.reste })

$detail = (($done | ForEach-Object {
    if ($_.attente) {
        # Rien n'a ete touche : la tache est saine, c'est son dernier passage qui ne
        # l'etait pas. On le dit tel quel, sans repeter la meme phrase deux fois.
        "{0} : structure saine. {1} — se confirmera à la prochaine ouverture de session." -f $_.tache, $_.mal
    } else {
        $sort = if ($_.repare)   { 'réparée' }
                elseif ($_.reste) { "réécrite, mais : " + $_.reste }
                else             { 'ÉCHEC : ' + $_.erreur }
        "{0} : {1} -> {2}" -f $_.tache, $_.mal, $sort
    }
}) -join [Environment]::NewLine)

$parts = @()
if ($ok.Count)      { $parts += ("{0} tâche(s) réparée(s)" -f $ok.Count) }
if ($waitMs.Count) { $parts += ("{0} saine(s), en attente de leur prochain démarrage" -f $waitMs.Count) }
if ($restant.Count) { $parts += ("{0} réécrite(s), à confirmer à la prochaine ouverture de session" -f $restant.Count) }
if ($ko.Count)      { $parts += ("{0} en échec" -f $ko.Count) }
if (-not $parts.Count) { $parts += "rien à signaler" }

@{
    message = (($parts -join ', ') + '.')
    result  = @{ ok = ($ko.Count -eq 0); detail = $detail; invalidate = @('comptes.probe.ps1', 'deployment.probe.ps1') }
}
