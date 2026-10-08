# @author Florent HAZARD <f.hazard@sowapps.com>
<# A probe: THE DEPLOYMENT of Vigie on this machine. READ ONLY.

   Intent: say what the OTHER accounts start -- the shared location, the version in place, the interpreter, the
   start-up tasks, the fate of the last deployment -- and whether that version matches its source.
   Usage: it is run by the scheduler like any probe; nothing here acts, everything here reads.

   WHY IT LIVES ALONE, IN ITS OWN MODULE. It used to be returned by the accounts probe, which is declared PER
   ACCOUNT (it writes a "you" beside a name). Yet a per-account probe is NEVER deferred to the background refresh:
   it is computed INSIDE the request, because the background refresh runs without a session and would not know
   whom to keep its result for.

   This card speaks of nobody in particular: it compares an installation with its source. Leaving it inside the
   per-account probe made it compulsory in every request, with what it costs -- reading the accounts, the state of
   the tasks, synchronising the clone. On 31/08, /api/v1/state took up to 52 seconds. Separated, it becomes
   deferrable again: the answer leaves with the known value, and the recomputation happens behind.

   The group does not change: the two cards are read together, under Accounts. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$elevated   = [bool](Test-IsElevated)
$accounts = @(Get-UserAccounts)
# =============================================================================
# THE SECOND CARD: THE DEPLOYMENT
#
# This probe returned ONE card that spoke of two things: who has Vigie on this machine, and how Vigie is installed
# there. The owner saw it (27/08) -- the card showed the list of accounts, the deployed version, the interpreter,
# and the fate of the last deployment. Two subjects, two cards.
#
#   Accounts   : who has Vigie, and with what rights.
#   Deployment : what the OTHER accounts start -- the shared location, the interpreter, the start-up tasks, the
#                last deployment.
#
# Both stay in the same group: they are read together.

$depl = @()

# Is the installation readable by the other accounts? If not, no other account can start Vigie -- and that is the
# case on a development workstation. We SAY SO on the card, with the button that fixes it (D66: an alert always
# carries its resolution).
$partagee = [bool](Get-SharedInstallPath)
if ($partagee) {
    # UP TO DATE? The version number is not enough: two "v0.1" can differ by twenty commits. So we compare the
    # COMMIT, and we state the gap (D84).
    $cmp = Compare-SharedInstall -Backend $backend
    $state = 'accessible à tous les comptes'
    $niveau = 'ok'
    $detail = "Installation partagée : " + (Get-SharedInstallPath)
    if ($cmp) {
        # THE VALUE SAYS WHAT IT IS, the COLOUR says something is wrong, the DETAIL explains (the owner's rule of
        # 27/08: the version in orange is enough to know there is a problem). A card's line is read at a glance;
        # the whole sentence fits in the tooltip.
        $state = $cmp.there.version
        $detail += [Environment]::NewLine + "Déployée : " + $cmp.there.version +
                   $(if ($cmp.there.commit) { " (" + $cmp.there.commit.Substring(0, [Math]::Min(8, $cmp.there.commit.Length)) + ")" } else { " (commit inconnu)" })

        <#
            WHAT DO WE COMPARE WITH? The question has a different answer on each machine, and the old version asked
            none: it compared with "here", which IS the installation when the server app runs inside it. So it
            declared itself to match itself, whatever happened.

            We now STATE the reference, and when there is none we say that too -- rather than reassuring while
            knowing nothing.
        #>

        if ($cmp.reference -eq 'clone') {
            $detail += [Environment]::NewLine + "Source : " + $cmp.here.version +
                       $(if ($cmp.here.commit) { " (" + $cmp.here.commit.Substring(0, [Math]::Min(8, $cmp.here.commit.Length)) + ")" } else { "" })
            $detail += [Environment]::NewLine + "Synchronisé depuis : " + $cmp.remote
            # THE REPOSITORY IS DECLARED, BUT IS IT READABLE? The account that runs Vigie is not the one that
            # develops: it may have no rights at all on the working folder, or git may refuse a repository
            # belonging to somebody else. We SAY SO, in git's own words: "it differs from the repository" suggested
            # a gap in the code when in fact nothing could be read at all.
            if ($cmp.here.error) {
                $niveau = 'warn'
                $why = "La source n'a pas pu être lue : " + $cmp.here.error +
                            " Tant qu'elle est illisible, impossible de dire si l'installation est à jour."
            } elseif ($cmp.same) {
                $why = "Elle correspond exactement à la source : les autres comptes lancent la même version que ce compte."
            } elseif ($null -ne $cmp.behind -and $cmp.behind -gt 0) {
                $niveau = 'warn'
                $why = "Elle est en retard de $($cmp.behind) commit(s) sur la source : les autres comptes n'ont pas les dernières corrections."
            } elseif (-not $cmp.there.commit) {
                $niveau = 'warn'
                $why = "Elle a été déployée avant que Vigie ne marque ses archives : impossible de dire à quel commit elle correspond."
            } else {
                $niveau = 'warn'
                $why = "Elle diffère de la source."
            }
        } elseif ($cmp.reference -eq 'publiee') {
            $detail += [Environment]::NewLine + "Dernière version publiée : " + $cmp.here.version
            if ($cmp.same) {
                $why = "C'est la dernière version publiée : il n'y a rien à mettre à jour."
            } else {
                $niveau = 'warn'
                $why = "Une version plus récente est publiée ($($cmp.here.version))."
            }
        } else {
            # NEITHER A REPOSITORY NOR A NETWORK. We do not know, and we say so: a default verdict of "conforms" is
            # the worst of all, it reassures while knowing nothing.
            $niveau = 'neutral'
            $why = "Impossible de dire si elle est à jour : aucun dépôt sur ce poste, et la liste des versions publiées n'a pas pu être consultée."
        }
        $detail = $why + [Environment]::NewLine + [Environment]::NewLine + $detail
    }
    # ALREADY DEPLOYED: what we offer is an UPDATE, not a deployment -- "deploy for every account" no longer means
    # anything once it is done.
    $depl += New-Field -Key 'partage' -Label 'Installation partagée' -Value $state -Kind 'text' -Status $niveau `
        -FixAction $(if ($niveau -eq 'warn') { 'vigie-update' } else { '' }) `
        -Help "Emplacement lisible par tous les comptes de la machine : leurs tâches de démarrage pointent dessus. Les autres comptes lancent CETTE version, pas celle du dépôt." `
        -Guide $detail
} else {
    # NEVER DEPLOYED: here it really is a FIRST deployment, and the button says so.
    $depl += New-Field -Key 'partage' -Label 'Installation partagée' -Value 'Lisible par ce seul compte' -Kind 'text' -Status 'warn' `
        -FixAction 'vigie-update' `
        -Help "Les autres comptes ne peuvent pas lire cette installation : Vigie ne demarrerait pas chez eux." `
        -Guide ("Emplacement actuel : " + (Get-RepoRoot) + [Environment]::NewLine +
                "Le bouton installe cette version dans C:\Program Files\Sowapps\Vigie, lisible par tous les comptes, et conserve les reglages deja en place.")
}

# The same obstacle, another cause: the application is indeed shared, but the INTERPRETER that starts it is not.
# Say it here, otherwise enabling an account creates a task that fails silently at every logon (observed on 26/08
# with one of the accounts).
$pwshPartage = Get-SharedPwshPath
$pwshAccount  = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshPartage -and -not $pwshAccount) {
    # ABSENT is not the same as "installed for you alone": the card must say which of the two, otherwise it tells a
    # story that does not exist. Lived through on 26/08: an installation in machine scope uninstalled the account's
    # package then failed, and the machine found itself WITHOUT PowerShell 7 -- while the card still announced it
    # was installed for this account alone.
    $depl += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'Absent de la machine' -Kind 'text' -Status 'error' `
        -FixAction 'pwsh-install-machine' `
        -Help "PowerShell 7 n'est installé nulle part : Vigie ne redémarrera pas, ni pour ce compte ni pour les autres. Les processus en cours survivent, mais le prochain démarrage échouera." `
        -Guide ("À faire tout de suite, dans un terminal ADMINISTRATEUR :" + [Environment]::NewLine +
                "  winget install --id Microsoft.PowerShell -e --scope machine" + [Environment]::NewLine +
                "À défaut, le paquet MSI : https://github.com/PowerShell/PowerShell/releases")
} elseif (-not $pwshPartage) {
    $depl += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'Installé pour ce seul compte' -Kind 'text' -Status 'warn' `
        -FixAction 'pwsh-install-machine' `
        -Help "Les tâches des autres comptes ont besoin d'un PowerShell 7 installé pour la MACHINE. Celui-ci vient du Store et n'existe que dans le profil de ce compte : leur tâche ne lancerait rien." `
        -Guide ("Interpréteur actuel : " + $pwshAccount + [Environment]::NewLine +
                "À faire une fois, en administrateur :" + [Environment]::NewLine +
                "  winget install --id Microsoft.PowerShell --scope machine" + [Environment]::NewLine +
                "Puis réactivez les comptes concernés.")
} else {
    $depl += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'Installé' -Kind 'text' -Status 'ok' `
        -Help "Tous les comptes peuvent lancer l'interpréteur : leurs tâches de démarrage fonctionnent." `
        -Guide ("Interpréteur des tâches : " + $pwshPartage)
}

if (-not $elevated) {
    $fields += New-Field -Key 'scope' -Label 'Détail des autres comptes' -Value 'Réservé à un administrateur' -Kind 'text' -Status 'neutral' `
        -Help "Windows protège le profil de chaque compte : leur détail n'est lisible que par un Vigie lancé en administrateur. Vigie ne montre rien de plus que ce que Windows laisse voir."
}

# AILING TASKS: a task aiming at an interpreter or an application that has gone starts and dies in silence. The
# probe repairs NOTHING (read only): it observes, and carries the button that repairs (D66).
# --- WHICH ENVIRONMENT ANSWERS ------------------------------------------------
#
# VIGIE ALWAYS RUNS FROM THE SHARED INSTALLATION, development included. Only the SOURCE of what is deployed there
# changes: a published version in production, a branch of the repository in development -- and the gap is then read
# in the version number itself ("v0.1.27+3"), not in a location.
#
# So I was reporting a permanent and pointless gap on a development workstation: "the machine declares itself
# Development but Vigie runs from Production". There was nothing to repair, and the card went orange for normal
# behaviour.
#
# WHAT REMAINS A GAP: a task that starts THE REPOSITORY. The working folder may be unreadable to the other
# accounts -- neither an ordinary account nor the service account has any rights on it -- and it can move. A task
# pointing at it will fail to start something, one day or another.

$declared = Get-DeclaredStage -Backend $backend
$running  = Get-RunningStage -Backend $backend
$envIssues = @()
foreach ($c in $accounts) {
    if (-not $c.task) { continue }
    try {
        $t = Get-ScheduledTask -TaskName $c.task -ErrorAction Stop
        $args = "$(@($t.Actions)[0].Arguments)"
        if ($args -match '-File\s+"([^"]+)"') {
            if ((Get-PathStage -Path $Matches[1]) -ne 'prod') {
                $envIssues += ($c.name + " démarre depuis le dépôt de travail, pas depuis l'installation partagée")
            }
        }
    } catch { }
}

# THE FIELD IS CALLED "STAGE": "environment" did not say what was being spoken of -- this setting, the server, or
# the whole computer? And the value is what the computer DECLARES, not where the running code sits: the latter is
# always the same, so it carries no information, and it was misleading as soon as it was compared with the
# declaration.
$aide = "Le stage déclaré par cet ordinateur : développement ou production. " +
        "Il conditionne le marquage des versions, pas la provenance du code — celle-ci est un réglage à part. Vigie tourne toujours depuis l'installation partagée : " +
        "une tâche qui lance le dépôt de travail ne démarrera pas chez un compte qui n'y a pas accès."
if ($envIssues.Count) {
    $depl += New-Field -Key 'env' -Label 'Stage' `
        -Value ((Get-StageLabel -Stage $declared) + " — " + $envIssues.Count.ToString() + " écart(s)") `
        -Kind 'text' -Status 'warn' -FixAction 'repair-tasks' `
        -Help $aide `
        -Guide ($envIssues -join [Environment]::NewLine)
} else {
    $depl += New-Field -Key 'env' -Label 'Stage' `
        -Value (Get-StageLabel -Stage $declared) -Kind 'text' -Status 'ok' `
        -Help $aide `
        -Guide ("Toutes les tâches de démarrage lancent l'installation partagée." + [Environment]::NewLine +
                "Vigie répond depuis : " + (Get-StageLabel -Stage $running))
}

# THE DECLARED SOURCE MAY HAVE GONE -- a working copy deleted, a repository moved. The update then takes the latest
# published version (Get-UpdateRoute), and the card says why: arbitrated by the owner on 13/09.
$declaredSource = ''
try { $declaredSource = "$((Get-Config -Backend $backend).SourcePath)" } catch { }
if ($declaredSource -and -not (Test-PathSafe (Join-Path $declaredSource '.git'))) {
    $depl += New-Field -Key 'source' -Label 'Source déclarée' -Value 'Introuvable' -Kind 'text' -Status 'warn' `
        -Help "Le dépôt déclaré comme source n'existe plus : les mises à jour viennent de la dernière version publiée." `
        -Guide ("Source déclarée : " + $declaredSource)
}

# THE SERVICE ACCOUNT'S PROFILE MAY BE BROKEN -- opened as temporary, corrupted: the service then runs without its clone,
# its cache or its secrets. Surfaced since 14/09; restarting the server logs the account on again, which reloads it.
$serviceProfileIssue = $null
try { $serviceProfileIssue = Get-ServiceProfileAilment } catch { $serviceProfileIssue = "lecture impossible : " + $_.Exception.Message }
if ($serviceProfileIssue) {
    $depl += New-Field -Key 'profil-service' -Label 'Profil du compte de service' -Value 'Abîmé' -Kind 'text' -Status 'error' `
        -FixAction 'server-restart' `
        -Help "Le profil Windows du compte de service ne se charge pas normalement : le service tourne sans son clone, son cache ni ses secrets." `
        -Guide ("Constat : " + $serviceProfileIssue + [Environment]::NewLine +
                "Relancer le serveur ouvre à nouveau la session du compte de service, ce qui recharge son profil." + [Environment]::NewLine +
                "Si le défaut revient après un redémarrage de l'ordinateur, un administrateur retire la clé « .bak » de ce compte sous HKLM, ProfileList, puis redémarre.")
}

# OUT OF SERVICE and WAITING are not said the same way. A task whose structure is sound but whose last launch
# failed is not broken: it will confirm itself at the account's next logon. Announcing it in red was excessive, and
# pushed towards repairing what had nothing to repair.
$malades  = @($accounts | Where-Object { $_.taskAilment })
$pending = @($accounts | Where-Object { -not $_.taskAilment -and $_.taskPending })
if ($malades.Count) {
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value ($(if ($malades.Count -eq 1) { "Ne démarre pas — " + $malades[0].name }
                  else { "Ne démarre pas — " + $malades.Count.ToString() + " comptes" })) -Kind 'text' -Status 'error' `
        -FixAction 'repair-tasks' `
        -Help "Une tâche de démarrage de Vigie ne peut plus lancer l'application : elle démarre et meurt aussitôt, sans message. Vigie ne se lancera pas à l'ouverture de session." `
        -Guide (($malades | ForEach-Object { $_.name + " : " + $_.taskAilment }) -join [Environment]::NewLine)
} elseif ($pending.Count) {
    # No button: there is nothing to repair. Only the account's next logon will say whether the problem is behind
    # us.
    <#
        "1 task(s) to confirm" says nothing to anybody: confirmed by whom, what, how? A card's value is understood
        WITHOUT opening the help. So we say what is true: Vigie has not started yet on that account.

        NEUTRAL, NOT "TO WATCH": there is nothing to do and nothing to repair. A warning calls for an action (D66);
        this one had none to offer, and pushed towards repairing what is fine.

        THE COMMENT LIVES ABOVE THE STATEMENT. Slipped between a backtick of continuation and the next parameter, it
        CUTS the call: the probe threw "missing mandatory parameters: Value Kind" and no longer returned any card.
    #>



    # A launch that never happened and a launch that failed are two facts: the value names the one that holds.
    $neverRun = Get-VigieTaskNeverRunText
    $pendingState = if (@($pending | Where-Object { $_.taskPending -ne $neverRun }).Count) { 'Dernier démarrage en échec' } else { 'Jamais démarrée' }
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value ($(if ($pending.Count -eq 1) { $pendingState + " — " + $pending[0].name }
                  else { $pendingState + " — " + $pending.Count.ToString() + " comptes" })) -Kind 'text' -Status 'neutral' `
        -Help "Vigie est bien installée pour ce compte, mais elle ne s'y est pas encore lancée — soit il n'a pas ouvert de session depuis, soit son dernier démarrage s'est mal passé. Il n'y a rien à réparer : la prochaine ouverture de session de ce compte le dira." `
        -Guide (($pending | ForEach-Object { $_.name + " : " + $_.taskPending }) -join [Environment]::NewLine)
} else {
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value 'Opérationnel' -Kind 'text' -Status 'ok' `
        -Help "Chaque compte qui a Vigie porte une tâche de démarrage saine."
}

<#
    THE TWO VERSIONS IN THE CONFIRMATION: where we come from, where we are going.

    "Deploys the current version to the shared installation" does not say which one to which: one clicked without
    knowing whether one was moving forward by two commits or overwriting a more recent version. So the window shows
    two badges, old -> new.

    THIS BLOCK HAD DISAPPEARED when the Deployment card moved into its own probe: it stayed in the accounts one,
    the action went on quoting EMPTY variables, and the two badges no longer displayed. Nothing had reported it --
    a missing variable raises no error in PowerShell.

    THE COMMIT IS SHOWN IN DEVELOPMENT ONLY: in production two versions are told apart by their number, which is
    what it is for. In development the number does not move between two commits, and the same number twice would
    say nothing.
#>

$court = { param($c) if ($c) { $c.Substring(0, [Math]::Min(8, $c.Length)) } else { '' } }
$estDev = ((Get-DeclaredStage -Backend $backend) -eq 'dev')
$deVersion = ''; $versVersion = ''; $deNote = ''; $versNote = ''
if ($cmp) {
    $deVersion   = "$($cmp.there.version)"
    $versVersion = "$($cmp.here.version)"
    if ($estDev) {
        $deNote   = & $court $cmp.there.commit
        $versNote = & $court $cmp.here.commit
    }
} else {
    $deVersion   = 'rien'
    $versVersion = 'première installation'
}

# THE FATE OF THE LAST OPERATION started from this card (D82). A green line when it got there, RED with its log
# when it failed -- never nothing.
$dernier = New-LastRunField -Module 'deployment'
if ($dernier) { $depl += $dernier }

# WHAT VIGIE OCCUPIES, every account together (asked for on 27/08). An application that watches the others' disc
# space must say what it takes itself.
$emp = Get-VigieFootprint -Backend $backend
$detailEmp = @()
if ($emp.programme) { $detailEmp += "Programme (partagé) : " + (Format-ByteSize -Bytes $emp.programme) + "  —  " + $emp.programmePath }
foreach ($x in @($emp.parCompte)) {
    $detailEmp += "Données de " + $x.name + $(if ($x.current) { " (vous)" } else { "" }) + " : " + (Format-ByteSize -Bytes $x.bytes)
}
if ($emp.sources) { $detailEmp += "Dépôt de développement : " + (Format-ByteSize -Bytes $emp.sources) + "  —  " + $emp.sourcesPath }
if (-not $emp.complet) { $detailEmp += "" ; $detailEmp += "Relevé partiel : les données des autres comptes ne sont lisibles que par un Vigie lancé en administrateur." }
$depl += New-Field -Key 'empreinte' -Label 'Stockage occupé' `
    -Value ((Format-ByteSize -Bytes $emp.total) + $(if (-not $emp.complet) { ' (au moins)' } else { '' })) `
    -Kind 'text' -Status 'neutral' `
    -Help "Tout ce que Vigie occupe sur cette machine : le programme partagé, les données de chaque compte, et le dépôt sur un poste de développement." `
    -Guide ($detailEmp -join [Environment]::NewLine)

# --- Card 2: the DEPLOYMENT ---------------------------------------------------
# A background task started from this card (a deployment, an installation of PowerShell) keeps it marked as having
# an operation under way until the process ends.
$travail = Get-ModuleBusyMark -Module 'deployment'
# SCOPE: the computer's installation, a single one for every account.
$deployCard = New-ModuleObject -Id 'deployment' -Theme 'accounts' -Label 'Déploiement' -Scope 'machine' `
    -Status $(if (@($depl | Where-Object { "$($_.status)" -eq 'error' }).Count) { 'error' }
              elseif (@($depl | Where-Object { "$($_.status)" -eq 'warn' }).Count) { 'warn' }
              else { 'ok' }) `
    -Fields $depl `
    -Busy:([bool]$travail) -BusyAction $(if ($travail) { "$($travail.action)" } else { '' }) `
    -Actions @(
        # THE CONFIRMATION TEXTS. "What this changes" says what CHANGES, not what happens -- the sequence is shown
        # just above by -Steps. And without our internal vocabulary: a version tag, a client app, a repository mean
        # nothing to somebody using Vigie. "Going back" answers YES first, then how.
        #
        # BEWARE: these comments are HERE and not in the middle of the call. A comment placed after a backtick of
        # continuation CUTS it: the next line becomes a command of its own, and PowerShell answers that the term
        # '-Impact' is not recognised. Observed on 29/08, the probe broken in production.
        New-Action -Id 'vigie-update' -Label 'Mettre à jour l''installation' -Kind 'confirm' -Severity 'fix' -Confirm `
            -BusyLabel 'Mise à jour…' `
            -Help "Déploie la version actuelle vers l'installation partagée, puis relance Vigie avec." `
            -From $deVersion -To $versVersion -FromNote $deNote -ToNote $versNote `
            -Steps @('Copie vers Program Files', 'Redémarrage du serveur', 'Vigie à jour') `
            -Impact ("Tous les comptes de la machine passeront à cette version, celui-ci compris. " +
                     "Réglages, historique et journaux ne bougent pas : ils vivent dans le " +
                     "profil de chaque compte, pas dans l'installation. Vigie se coupe quelques secondes et revient seule.") `
            -Usage ("Quand les autres comptes utilisent encore une version plus ancienne que celle de ce compte. " +
                    "C'est aussi ce qui installe Vigie pour tout le monde, la première fois.") `
            -Reversible ("Oui : en déployant une version plus ancienne. Et si la copie échoue, rien n'est " +
                         "relancé — la version en place continue de tourner.")
        New-Action -Id 'repair-tasks' -Label 'Réparer le démarrage de Vigie' -Kind 'immediate' -Severity 'fix' `
            -BusyLabel 'Réparation…' `
            -Help "Réécrit les tâches de démarrage de Vigie qui ne fonctionnent plus (interpréteur ou application déplacés). Ne touche à rien d'autre sur la machine."
    )

@($deployCard)
