# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- lit dans le profil des autres comptes : Windows exige l'elevation (D65)
# @libelle: Details des comptes | immediate | info   -- affiche quand un champ cite cette action (D66)
<# Action : le detail des comptes de la machine.

   La carte dit l'essentiel d'un coup d'oeil (qui, Vigie ou non, quel type) ; ce detail
   repond aux questions suivantes : quand chacun s'est-il connecte pour la derniere fois,
   lesquels dorment, et quel poids font leurs donnees Vigie.

   LECTURE SEULE. Reserve a un administrateur, comme toute lecture dans le profil d'autrui. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

# Seuil de « compte dormant » : une constante, pas un reglage -- personne n'a demande
# a le regler, et 90 jours sans session est un repere universel.
$dormant = 90

$lignes = @()
$dormants = 0
foreach ($c in (Get-ComputerAccounts | Sort-Object name)) {
    $depuis = 'jamais connecté'
    if ($c.lastLogon) {
        try {
            $j = [int]((Get-Date) - [datetime]$c.lastLogon).TotalDays
            $depuis = if ($j -le 0) { "connecté aujourd'hui" } else { "dernière session il y a $j jour(s)" }
            if ($j -ge $dormant) { $dormants++; $depuis += " — dormant" }
        } catch { }
    }

    $donnees = 'aucune donnée Vigie'
    try {
        $var = Join-Path (Join-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $c.name) 'AppData\Local\Sowapps\Vigie') 'var'
        if (Test-Path -LiteralPath $var) {
            $f = @(Get-ChildItem -LiteralPath $var -File -Recurse -ErrorAction SilentlyContinue)
            $taille = ($f | Measure-Object Length -Sum).Sum
            $recent = ($f | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            $donnees = "{0} de données Vigie, dernière activité {1}" -f (Format-ByteSize ([long]$taille)),
                       $(if ($recent) { $recent.ToString('dd/MM/yyyy HH:mm') } else { 'inconnue' })
        }
    } catch { $donnees = 'données illisibles' }

    $qualites = @()
    $qualites += $(if ($c.admin) { 'administrateur' } else { 'standard' })
    $qualites += $(if ($c.enabled) { 'Vigie activée' } else { 'Vigie inactive' })
    if ($c.technical) { $qualites += 'compte technique (pas de profil humain)' }
    if ($c.current)   { $qualites += 'compte en cours' }

    # CE QUE LA TACHE LANCE, ET CE QU'ELLE A RENDU. Sans ca, « activee mais rien ne
    # demarre » reste une enigme : la ligne de commande et le code de retour sont les
    # deux seules choses qui repondent, et seul un serveur eleve peut les lire (D67).
    $tache = @()
    if ($c.task) {
        try {
            $t = Get-ScheduledTask -TaskName $c.task -ErrorAction Stop
            $i = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            $act = @($t.Actions)[0]
            $cmd = ("$($act.Execute)" + ' ' + "$($act.Arguments)").Trim()
            if ($cmd.Length -gt 150) { $cmd = $cmd.Substring(0, 147) + '...' }
            # L'ETAT est la premiere chose a savoir, et c'est justement ce qui manquait :
            # une tache DESACTIVEE se lit « activee » partout ailleurs, et ne demarre
            # jamais. Une session non elevee ne voit pas cet etat -- le diagnostic doit
            # donc le porter, sinon il envoie chercher ailleurs (règle du 28/08).
            $tache += ("tâche « " + $c.task + " » : " + "$($t.State)" +
                       ", niveau " + "$($t.Principal.RunLevel)" +
                       ", compte " + "$($t.Principal.UserId)")
            $tache += ("lance : " + $cmd)
            if ($i) {
                $quand = if ($i.LastRunTime -and $i.LastRunTime.Year -gt 2000) { $i.LastRunTime.ToString('dd/MM/yyyy HH:mm') } else { 'jamais' }
                $tache += ("dernière exécution : " + $quand +
                           " — code 0x" + ([int]$i.LastTaskResult).ToString('X8'))
            }
            if ($c.taskAilment) { $tache += ("PROBLÈME : " + $c.taskAilment) }
        } catch { $tache += ("tâche illisible : " + $_.Exception.Message) }
    }

    $bloc = @($c.name, ('   ' + ($qualites -join ' · ')), ('   ' + $depuis), ('   ' + $donnees))
    foreach ($l in $tache) { $bloc += ('   ' + $l) }
    $lignes += ($bloc -join "`n")
}

$entete = "Comptes de cet ordinateur"
if ($dormants -gt 0) { $entete += " ($dormants dormant(s) depuis plus de $dormant jours)" }

$detail = ($entete, '') + $lignes + ('',
    "Pour relire les journaux de l'un d'eux : scripts/vigie-diag-compte.ps1 -Compte <nom>",
    "Pour choisir qui a Vigie : Paramètres > Utilisateurs.")

@{
    message = ("Détail de " + (@(Get-ComputerAccounts).Count) + " compte(s).")
    result  = @{ ok = $true; detail = ($detail -join [Environment]::NewLine) }
}
