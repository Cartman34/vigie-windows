# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- lit dans le profil des autres comptes : Windows exige l'elevation (D65)
# @libelle: Details des comptes | immediate | info   -- affiche quand un champ cite cette action (D66)
<# An action: the detail of the machine's accounts.

   Intent: answer the questions that follow the card. The card says the essentials at a glance (who, Vigie or
   not, what kind); this detail says when each one last signed in, which are dormant, and what weight their Vigie
   data has.
   Usage: it is called from the Accounts card. READ ONLY. Reserved to an administrator, like any reading inside
   somebody else's profile. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

# The "dormant account" threshold: a constant, not a setting -- nobody asked to set it, and 90 days without a
# session is a universal landmark.
$dormant = 90

$lines = @()
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

    $data = 'aucune donnée Vigie'
    try {
        $var = Join-Path (Join-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $c.name) 'AppData\Local\Sowapps\Vigie') 'var'
        if (Test-Path -LiteralPath $var) {
            $f = @(Get-ChildItem -LiteralPath $var -File -Recurse -ErrorAction SilentlyContinue)
            $size = ($f | Measure-Object Length -Sum).Sum
            $recent = ($f | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            $data = "{0} de données Vigie, dernière activité {1}" -f (Format-ByteSize ([long]$size)),
                       $(if ($recent) { $recent.ToString('dd/MM/yyyy HH:mm') } else { 'inconnue' })
        }
    } catch { $data = 'données illisibles' }

    $qualites = @()
    $qualites += $(if ($c.admin) { 'administrateur' } else { 'standard' })
    $qualites += $(if ($c.enabled) { 'Vigie activée' } else { 'Vigie inactive' })
    if ($c.technical) { $qualites += 'compte technique (pas de profil humain)' }
    if ($c.current)   { $qualites += 'compte en cours' }

    # WHAT THE TASK STARTS, AND WHAT IT RETURNED. Without that, "enabled but nothing starts" stays a riddle: the
    # command line and the exit code are the only two things that answer, and only an elevated server can read
    # them (D67).
    $task = @()
    if ($c.task) {
        try {
            $t = Get-ScheduledTask -TaskName $c.task -ErrorAction Stop
            $i = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            $act = @($t.Actions)[0]
            $cmd = ("$($act.Execute)" + ' ' + "$($act.Arguments)").Trim()
            if ($cmd.Length -gt 150) { $cmd = $cmd.Substring(0, 147) + '...' }
            # The STATE is the first thing to know, and that is precisely what was missing: a DISABLED task reads
            # as "enabled" everywhere else, and never starts. A session that is not elevated does not see that
            # state -- so the diagnosis must carry it, otherwise it sends one looking elsewhere (the owner's rule
            # of 28/08).
            $task += ("tâche « " + $c.task + " » : " + "$($t.State)" +
                       ", niveau " + "$($t.Principal.RunLevel)" +
                       ", compte " + "$($t.Principal.UserId)")
            $task += ("lance : " + $cmd)
            if ($i) {
                $quand = if ($i.LastRunTime -and $i.LastRunTime.Year -gt 2000) { $i.LastRunTime.ToString('dd/MM/yyyy HH:mm') } else { 'jamais' }
                # UNSIGNED, AND THAT IS THE WHOLE PROBLEM -- the same trap as in Get-VigieTaskHistoryAilment, fixed
                # there and left here: Windows returns a 32-bit UNSIGNED HRESULT, and 0x800710E0 is 2 147 946 720,
                # past Int32. The cast threw, the catch swallowed the whole block, and the account's line read "tâche
                # illisible" instead of the state, the level, the command and the code -- exactly what was being
                # looked for. Read on the Famille account on 29/09, whose last result WAS 0x800710E0.
                $task += ("dernière exécution : " + $quand +
                           " — code 0x" + ([uint32][long]$i.LastTaskResult).ToString('X8'))
            }
            if ($c.taskAilment) { $task += ("PROBLÈME : " + $c.taskAilment) }
        } catch { $task += ("tâche illisible : " + $_.Exception.Message) }
    }

    $bloc = @($c.name, ('   ' + ($qualites -join ' · ')), ('   ' + $depuis), ('   ' + $data))
    foreach ($l in $task) { $bloc += ('   ' + $l) }
    $lines += ($bloc -join "`n")
}

$entete = "Comptes de cet ordinateur"
if ($dormants -gt 0) { $entete += " ($dormants dormant(s) depuis plus de $dormant jours)" }

$detail = ($entete, '') + $lines + ('',
    "Pour relire les journaux de l'un d'eux : scripts/vigie-diag-account.ps1 -Account <nom>",
    "Pour choisir qui a Vigie : Paramètres > Utilisateurs.")

@{
    message = ("Détail de " + (@(Get-ComputerAccounts).Count) + " compte(s).")
    result  = @{ ok = $true; detail = ($detail -join [Environment]::NewLine) }
}
