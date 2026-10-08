# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    install-service.ps1 -- Vigie's server becomes a MACHINE SERVICE. IDEMPOTENT.

    Intent: give the machine ONE server instead of one per session. Today each account starts its own at the
    moment of its session. A STANDARD account cannot: the server demands elevation, and Windows would ask it for
    an administrator's password it does not have. And two sessions open at the same time fight over the same port.
    Hence a SINGLE server, started when the machine boots, under a DEDICATED administrator account -- not SYSTEM,
    whose full powers are not justified. The whole design: doc/progress/targeting/multi-account-server.md.

    Usage: THIS IS NOT AN ENTRY POINT. Installing Vigie has only ONE -- setup.cmd, which calls install.ps1 -- and
    it is that one which calls this step. A user has no business knowing it exists, nor in what order to run what:
    idempotence is what makes the difference between a first installation and an update. It stays runnable by hand
    for the gestures that are NOT the installation:

      pwsh -File .\scripts\lib\install-service.ps1 -Lister    # a survey, changes nothing
      pwsh -File .\scripts\lib\install-service.ps1 -Enable    # switch over to the service
      pwsh -File .\scripts\lib\install-service.ps1 -Remove    # go back

    THE PASSWORD IS NOT A SECRET TO BE KEPT ALIVE. It is generated here, passed once to Register-ScheduledTask,
    and it is WINDOWS that keeps it in its vault in order to start the task. This script writes it nowhere and
    does not return it.

    DELIBERATE CAUTION: the task is created DISABLED. As long as it is not enabled, nothing changes when the
    machine boots, and the present road goes on working. The two must NEVER run together: they would fight over
    the port.

    Exit codes: 0 = done; 1 = a missing prerequisite; 2 = a step failed; 3 = refused by the user.
#>






param(
    [switch] $Lister,
    [switch] $Enable,
    [switch] $Remove,
    # Repairs the account and the task from the running server, without stopping it (service-account-repair).
    [switch] $Repair
)
$ErrorActionPreference = 'Stop'

# The script has gone down one level (scripts/lib/): the root is two levels above.
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # the same display as every other script
. (Join-Path $repoRoot 'scripts/lib/i18n.ps1')

$SERVICE_ACCOUNT = Get-ServiceAccountName   # one single definition, in common.ps1
$SERVICE_TASK    = Get-ServiceTaskName   # one single definition, in common.ps1


function Get-ServiceAccount {
    try { return (Get-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop) } catch { return $null }
}
function Get-ServiceTask {
    try { return (Get-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop) } catch { return $null }
}

# --- The survey ---------------------------------------------------------------
<#
    THE SURVEY. It serves twice: before the work, to say where we start from, and afterwards, to show what has
    changed. So the same title came up TWICE on the same screen, which looked like a duplicate rather than a
    before and after (reported on 29/08).

    -NoTitle leaves the caller holding the thread: inside an installation the step's title is already above, and
    the survey is only its conclusion.
#>

function Show-State {
    param([switch]$NoTitle)
    $account = Get-ServiceAccount
    $task    = Get-ServiceTask
    if (-not $NoTitle) { Write-Title (Get-Label 'install-service.service-de-machine') }
    Write-Info (Get-Label 'install-service.compte-dedie' $(if ($account) { $SERVICE_ACCOUNT + " (actif=" + $account.Enabled + ")" } else { "absent" }))
    Write-Info (Get-Label 'install-service.tache-machine' $(if ($task) { $SERVICE_TASK + " (" + $task.State + ")" } else { "absente" }))
    # PROD IS THE DEFAULT, we do not announce it: only the development stage teaches anything.
    if ((Get-DeclaredStage -Backend $backend) -eq 'dev') { Write-Info (Get-Label 'install-service.stage-dev') }
    $listening = Get-PortListener -Port ([int](Get-Config -Backend $backend).Port)
    Write-Info (Get-Label 'install-service.serveur-en-ligne' $(if ($listening) { "oui (PID " + $listening.OwningProcess + ")" } else { "non" }))
}

# --- The dedicated account ----------------------------------------------------
#
# A long random password, generated here, passed once to Windows. We do not keep it: if the task has to be
# re-registered, we generate a new one and reset the account -- an administrator's gesture, like the rest.

function New-ServicePassword {
    $bytes = [byte[]]::new(24)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    # Base64 can hold characters some APIs digest badly: we keep a safe alphabet, and a length that amply makes up
    # for it.
    $safe = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
    return ($safe + 'aA1!')
}

function Set-ServiceAccountReady {
    $account = Get-ServiceAccount
    $password = New-ServicePassword
    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    if (-not $account) {
        Write-Step (Get-Label 'install-service.creation-du-compte' $SERVICE_ACCOUNT)
        # 48 CHARACTERS, NOT ONE MORE: that is the limit Windows imposes on a local account's description. A
        # sentence of 66 signs made the first installation fail (28/08) -- and the failure, at least, was properly
        # reported.
        New-LocalUser -Name $SERVICE_ACCOUNT -Password $secure -FullName 'Vigie - service local' `
                      -Description 'Service local de Vigie (pas de session)' `
                      -PasswordNeverExpires -UserMayNotChangePassword -ErrorAction Stop | Out-Null
    } else {
        Write-Detail (Get-Label 'install-service.le-compte-existe-mot' $SERVICE_ACCOUNT)
        Set-LocalUser -Name $SERVICE_ACCOUNT -Password $secure -ErrorAction Stop
    }

    # An administrator: the server holds the Windows Update lock and writes into HKLM.
    try {
        $admins = (Get-LocalGroup -SID 'S-1-5-32-544').Name
        $member = @(Get-LocalGroupMember -Group $admins -ErrorAction SilentlyContinue |
                    Where-Object { "$($_.Name)" -like ('*\' + $SERVICE_ACCOUNT) })
        if (-not $member.Count) {
            Add-LocalGroupMember -Group $admins -Member $SERVICE_ACCOUNT -ErrorAction Stop
            Write-Detail (Get-Label 'install-service.ajoute-aux-administrateurs')
        }
    } catch { Write-Warn (Get-Label 'install-service.groupe-administrateurs' $_.Exception.Message) }

    # HIDDEN FROM THE SIGN-IN SCREEN. This account is not a person: it has no business in the list of users. It is
    # the same key Vigie already reads to recognise a technical account -- the circle is closed.
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name $SERVICE_ACCOUNT -Value 0 -PropertyType DWord -Force | Out-Null
        Write-Detail (Get-Label 'install-service.masque-de-ecran-de')
    } catch { Write-Warn (Get-Label 'install-service.masquage-impossible' $_.Exception.Message) }

    return $password
}

# THE "LOG ON AS A BATCH JOB" RIGHT (SeBatchLogonRight).
#
# A task registered with a password (LogonType Password) starts only if its account holds that right. The Task
# Scheduler's graphical interface grants it by itself; Register-ScheduledTask does not -- hence a registration
# refused with nothing to explain what was missing (code 2 at the installation of 28/08).
#
# We grant it through secedit, which demands elevation -- the script already has it. Idempotent: an account that
# already holds it is not touched.

function Grant-BatchLogonRight {
    param([Parameter(Mandatory)][string]$Sid)
    # THE secedit WORK LIVES IN common.ps1 (Set-BatchLogonRight): the uninstall revokes what this grants, with one code.
    $result = Set-BatchLogonRight -Sid $Sid
    if (-not $result.ok) { Write-Warn (Get-Label 'install-service.droits-de-session' $result.error); return $false }
    if ($result.changed) { Write-Detail (Get-Label 'install-service.droit-ouvrir-une-session-2') }
    else { Write-Detail (Get-Label 'install-service.droit-ouvrir-une-session') }
    return $true
}
# --- The machine task ---------------------------------------------------------
function Register-ServiceTask {
    param([Parameter(Mandatory)][string]$Password)

    $pwsh = Get-SharedPwshPath
    if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $pwsh) { Write-Fail (Get-Label 'install-service.powershell-introuvable-pour-la'); return $false }

    # THE SERVER ALWAYS LIVES IN THE SHARED INSTALLATION, whatever the environment.
    #
    # "Dev or prod, it is just the SOURCE that changes, but the server is in Program Files." That is the only
    # tenable position for a machine service: a server living inside a user's working space would be unreadable to
    # the other accounts -- exactly the trap one account fell into -- and would disappear the day that folder
    # moves.
    #
    # So the declared environment does not say WHERE the server runs, but WHERE what is deployed there comes from:
    # the local repository in dev, a published version in prod.

    $appRoot = Get-SharedInstallPath
    if (-not $appRoot) {
        Write-Fail (Get-Label 'install-service.aucune-installation-partagee-deployez')
        Write-Detail (Get-Label 'install-service.le-service-de-machine')
        return $false
    }
    $start = Join-Path (Join-Path $appRoot 'apps/backend-pode') 'start.ps1'
    if (-not (Test-Path -LiteralPath $start)) { Write-Fail (Get-Label 'install-service.serveur-introuvable' $start); return $false }

    $action  = New-ScheduledTaskAction -Execute $pwsh `
                   -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $start + '"')
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId ("$env:COMPUTERNAME\$SERVICE_ACCOUNT") `
                     -LogonType Password -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    # THE RIGHT BEFORE THE REGISTRATION: without it Windows refuses a task started by password -- and its message
    # does not say which one is missing.
    $sid = $null
    try { $sid = (Get-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop).SID.Value } catch { }
    if ($sid) { $null = Grant-BatchLogonRight -Sid $sid }

    # TWO CALLS, NOT ONE. `Register-ScheduledTask` has exclusive PARAMETER SETS: -Principal belongs to one,
    # -Password to the other. Giving them together does not produce an error naming the culprit, but "Parameter set
    # cannot be resolved" -- which cost a whole installation on 28/08. So we build the task first (the principal
    # goes into it, RunLevel Highest included), then register it with the password: that set accepts -InputObject
    # and -Password.

    try {
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        Register-ScheduledTask -TaskName $SERVICE_TASK -InputObject $task `
            -User ("$env:COMPUTERNAME\$SERVICE_ACCOUNT") -Password $Password -Force -ErrorAction Stop | Out-Null
    } catch {
        # THE TRACE OUTLIVES THE CONSOLE. This message went into a terminal that was closed on 28/08, and what it
        # said had to be guessed: from now on it goes into Vigie's log as well, which can be read back.
        $why = $_.Exception.Message
        Write-Fail (Get-Label 'install-service.windows-refuse-enregistrer-la' $why)
        try { Write-Log -Backend $backend -Name 'install' -Level 'ERROR' `
                        -Message (Get-Label 'install-service.service-de-machine-windows' $why) } catch { }
        return $false
    }

    # DISABLED WHEN CREATED. Two servers on the same port would tread on each other: the switch-over is a separate
    # gesture, and a deliberate one (-Enable).
    try { Disable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop | Out-Null } catch { }
    Write-Ok (Get-Label 'install-service.tache-enregistree-desactivee' $SERVICE_TASK)
    return $true
}

# --- The right to restart it, for ordinary accounts ---------------------------
#
# The client app is not elevated: without this right it could neither stop nor restart the server. Windows grants
# it through the task's security descriptor.
function Grant-TaskControl {
    try {
        # NO "schtasks /change /RU" HERE. There was one, and it BLOCKED the installation: without /RP, schtasks asks
        # for the account's password and waits on standard input. The installation stayed frozen until somebody
        # pressed Enter -- 28 seconds measured in the log of 29/08, between two consecutive lines -- and that Enter
        # supplied an EMPTY password.
        #
        # Its error was swallowed by a "$null = $out": a deadlock with no message, on a call whose result nobody
        # checked. It was useless into the bargain, the principal being already laid down when the task was
        # registered.
        $sddl = 'D:(A;;GA;;;BA)(A;;GA;;;SY)(A;;GRGX;;;BU)'   # admins+system full, users read+execute
        $folder = New-Object -ComObject 'Schedule.Service'
        $folder.Connect()
        $task = $folder.GetFolder('\').GetTask($SERVICE_TASK)
        $task.SetSecurityDescriptor($sddl, 0)
        Write-Detail (Get-Label 'install-service.les-comptes-de-la')
        return $true
    } catch {
        Write-Warn (Get-Label 'install-service.droits-sur-la-tache' $_.Exception.Message)
        Write-Detail (Get-Label 'install-service.le-client-un-compte')
        return $false
    }
}

# --- Retrait --------------------------------------------------------------------------
function Remove-Service {
    $done = $true
    if (Get-ServiceTask) {
        try { Unregister-ScheduledTask -TaskName $SERVICE_TASK -Confirm:$false -ErrorAction Stop; Write-Ok (Get-Label 'install-service.tache-retiree') }
        catch { Write-Fail (Get-Label 'install-service.tache-non-retiree' $_.Exception.Message); $done = $false }
    }
    if (Get-ServiceAccount) {
        try { Remove-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop; Write-Ok (Get-Label 'install-service.compte-retire') }
        catch { Write-Fail (Get-Label 'install-service.compte-non-retire' $_.Exception.Message); $done = $false }
    }
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if (Test-Path -LiteralPath $key) { Remove-ItemProperty -Path $key -Name $SERVICE_ACCOUNT -ErrorAction SilentlyContinue }
    } catch { }
    return $done
}

# --- Deroulement ----------------------------------------------------------------------
if ($Lister) { Show-State; exit 0 }

if (-not (Test-IsElevated)) {
    Write-Fail (Get-Label 'install-service.cette-operation-cree-un')
    Write-Detail (Get-Label 'install-service.rien-ete-touche')
    exit 1
}

<#
    THE SWITCH-OVER. -Enable was declared in the parameters and described in the help, but NO code handled it: the
    command displayed the state and exited, doing nothing and saying nothing. A documented switch that does
    nothing is worse than an absent one -- that one, at least, raises an error.

    WHAT IT DOES, in this order, and why:

      1. The task must EXIST. Otherwise there is nothing to enable, and it is the installation that lays it down.
      2. THE PORT MUST BE FREE. Two servers on 47600 means the second one dies -- and one no longer knows which
         answers the orders. So the previous one stops and the next takes its place -- this is an installation, not
         a negotiation.
      3. We ENABLE, then START ON DEMAND. Windows refuses to start a disabled task, even by hand: both gestures
         are necessary, in that order. The "at startup" trigger remains for later; it is not awaited here.
      4. WE CHECK THAT IT LISTENS. A task that has "started" proves nothing: the process can die the next second.
         We wait for the port, not for the exit code.
      5. IF IT DOES NOT LISTEN, WE DISABLE IT. Leaving an enabled task that serves no purpose means that at the
         machine's next boot it will take over without anybody having decided so.

    THE RIGHTS ARE THE TASK'S, NOT THE REQUESTER'S. That is the very principle of the arrangement: the task
    declares its principal (the service account, RunLevel Highest), and Grant-TaskControl grants the built-in
    users the right to RUN it. So a standard account starts it, and it runs elevated -- with the rights it defines
    itself.
#>




<#
    PUTTING THE SERVER TASK INTO SERVICE. Returns $true if the server answers at the end.

    EXTRACTED SO AS TO BE CALLABLE TWICE: by the installation, which must install everything, and by -Enable,
    which puts back into service a task that had been taken out of play. The body used to end with an "exit" --
    usable only at the end of a script, so not as a step.

    It checks before switching on: the installation deals with the server task BEFORE starting the client app, so
    the client app will not start a competing server -- it observes that an enabled task is taking care of it.
#>


function Enable-ServiceTask {
    $task = Get-ServiceTask
    if (-not $task) {
        Write-Fail (Get-Label 'install-service.activer-tache-absente')
        Write-Detail (Get-Label 'install-service.activer-lancez-installation')
        return $false
    }

    # --- The port ---
    $port = [int](Get-Config -Backend $backend).Port
    $held = Get-PortListener -Port $port
    # THE PREVIOUS ONE STOPS, THE NEXT ONE STARTS. This is an installation: we do not ask permission to replace a
    # server with its own new version.
    if ($held) {
        # ONE SINGLE IMPLEMENTATION OF THE STOP (Stop-ServerApp): it stops the task BEFORE the process -- otherwise
        # Windows restarts it under our feet -- and waits for the port to be released, which is an observable fact.
        Write-Step (Get-Label 'install-service.activer-arret-du-serveur' $held.OwningProcess)
        if (-not (Stop-ServerApp -Backend $backend -Port $port)) {
            Write-Fail (Get-Label 'install-service.activer-arret-impossible' ("le port " + $port + " est toujours occupe"))
            return $false
        }
    }

    # --- Activer, puis demarrer ---
    Write-Step (Get-Label 'install-service.activer-bascule')
    try {
        Enable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop
    } catch {
        Write-Fail (Get-Label 'install-service.activer-windows-refuse' $_.Exception.Message)
        try { Disable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction SilentlyContinue | Out-Null } catch { }
        return $false
    }

    <#
        THE PROOF IS THAT THE TASK STARTS -- NOT THAT THE SERVER ANSWERS.

        I was waiting for the port. The wrong question: what the installation installs is a task that starts under
        the right account. How long the application then takes to open its port is no longer its business -- a
        minute, two, depending on the disc and the rest. Waiting for that result means waiting for an undetermined
        delay, and on 29/08 it ended with a DISABLED task while the server answered just afterwards.

        What can go wrong HERE goes wrong AT ONCE: a refused password, a missing batch logon right, a path that
        cannot be found. Windows then stops the task immediately and gives its code. So: if the task RUNS, it is
        installed; if it has stopped, we read why. A few seconds are enough to tell the difference.
    #>


    $state = 'Unknown'
    $result = $null
    foreach ($n in 1..12) {
        Start-Sleep -Milliseconds 750
        try {
            $state = "$((Get-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop).State)"
            $result = (Get-ScheduledTaskInfo -TaskName $SERVICE_TASK -ErrorAction Stop).LastTaskResult
        } catch { }
        if ($state -eq 'Running') { break }
    }
    if ($state -ne 'Running') {
        Write-Fail (Get-Label 'install-service.activer-tache-arretee' $state ("0x{0:X}" -f [int]$result))
        Write-Detail (Get-Label 'install-service.activer-desactivee-de-nouveau')
        try { Disable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction SilentlyContinue | Out-Null } catch { }
        try { Write-Log -Backend $backend -Name 'install' -Level 'ERROR' `
                        -Message ("Service : active puis desactive, la tache ne tourne pas (etat " + $state + ").") } catch { }
        Show-State
        return $false
    }

    Write-Ok (Get-Label 'install-service.activer-en-ligne')
    Write-Detail (Get-Label 'install-service.activer-ouverture-differee' $port)
    Write-Detail (Get-Label 'install-service.activer-au-prochain-demarrage')
    try { Write-Log -Backend $backend -Name 'install' `
                    -Message (Get-Label 'install-service.journal-tache-tourne') } catch { }
    return $true
}

if ($Enable) {
    Show-State
    if (-not (Enable-ServiceTask)) { Show-State -NoTitle; exit 2 }
    Show-State -NoTitle
    exit 0
}

if ($Remove) {
    Show-State
    if (Remove-Service) { Show-State; exit 0 }
    exit 2
}

<#
    REPAIRING FROM THE RUNNING SERVER (action service-account-repair). The account gets a new password, its right and
    the line that hides it again; the task is re-registered with that password, then enabled again. Nothing is
    stopped: the running server keeps its token, and the next start uses the new password. If the registration fails
    once the password has changed, the next start fails too: the failure is displayed with its reason, and
    setup.cmd repairs it.
#>
if ($Repair) {
    Write-Step (Get-Label 'install-service.reparation')
    try {
        $password = Set-ServiceAccountReady
    } catch {
        Write-Fail (Get-Label 'install-service.le-compte-de-service' $_.Exception.Message)
        exit 2
    }
    $registered = Register-ServiceTask -Password $password
    $password = $null
    [System.GC]::Collect()
    if (-not $registered) { exit 2 }
    $null = Grant-TaskControl
    try {
        Enable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop | Out-Null
    } catch {
        Write-Fail (Get-Label 'install-service.reactivation-impossible' $_.Exception.Message)
        exit 2
    }
    Write-Ok (Get-Label 'install-service.reparation-faite')
    exit 0
}

Write-Step (Get-Label 'install-service.etape')
Show-State -NoTitle

# A STEP THAT FAILS SAYS SO, it does not crash. Without this net the error came back raw and the script returned 1
# without explaining what was wrong.
try {
    $password = Set-ServiceAccountReady
} catch {
    Write-Fail (Get-Label 'install-service.le-compte-de-service' $_.Exception.Message)
    exit 2
}
if (-not (Register-ServiceTask -Password $password)) { exit 2 }
$null = Grant-TaskControl
# The password is of no further use: Windows holds it. We erase it from memory.
$password = $null
[System.GC]::Collect()

# AN INSTALLATION INSTALLS: at the end, the application works. The task used to be left disabled, waiting for a
# second gesture that nothing made obvious -- running the installation ten times changed nothing.
if (-not (Enable-ServiceTask)) { Show-State -NoTitle; exit 2 }
Show-State -NoTitle
exit 0
