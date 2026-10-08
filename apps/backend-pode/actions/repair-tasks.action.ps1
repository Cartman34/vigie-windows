# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- reecrire une tache planifiee exige l'elevation (D65)
# @libelle: Vérifier le démarrage de Vigie | immediate | fix   -- affiche quand un champ cite cette action (D66)
#
# Saying "repair" when nothing is broken rings false, and yet that is the normal state: the button stays on the
# card even when all is well (D59, D66). It CHECKS first, and repairs only what has to be -- so its label says
# what it does for certain, not what it does
# parfois.
<# An action: it puts VIGIE'S start-up tasks back in order, and nothing else.

   Intent: repair what Vigie itself laid down, and only that. Explicitly authorised by the owner: "the app may
   self-correct the system as long as it is pure Vigie". So we touch only the tasks named after Vigie, never
   anything else.
   Usage: it is called from the Deployment card's button. The case that motivated this: the tasks pointed at a
   pwsh installed inside one account's profile, which had gone after a change in the PowerShell installation.
   Windows said nothing -- the task existed, started, and died at once. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$done = @(Repair-VigieTasks -Backend $backend)
if (-not $done.Count) {
    return @{ message = "Vérification faite : les tâches de démarrage de Vigie sont saines."
              result  = @{ ok = $true; invalidate = @('accounts.probe.ps1', 'deployment.probe.ps1') } }
}
# THREE FATES, not two. A task can be rewritten without the defect disappearing: a failure already written into
# its history is only erased at its next run, that is, at the account's next logon. We say so, rather than
# announcing "repaired" while the screen shows "out of service" right beside it.
$ok      = @($done | Where-Object { $_.repare })
$waitMs = @($done | Where-Object { $_.attente })
$restant = @($done | Where-Object { -not $_.repare -and -not $_.attente -and $_.reste })
$ko      = @($done | Where-Object { -not $_.repare -and -not $_.attente -and -not $_.reste })

$detail = (($done | ForEach-Object {
    if ($_.attente) {
        # Nothing was touched: the task is sound, it is its last run that was not. We say so as it stands, without
        # repeating the same sentence twice.
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
    result  = @{ ok = ($ko.Count -eq 0); detail = $detail; invalidate = @('accounts.probe.ps1', 'deployment.probe.ps1') }
}
