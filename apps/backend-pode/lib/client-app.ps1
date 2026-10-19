# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, format, games, log, measures, paths, rights, sessions, tasks, var
<#
    Intent: THE CLIENT APP SEEN FROM THE SERVER: its heartbeat, the accounts whose app has gone quiet, and the orders it is given -- stop, start, restart everywhere. The app answers, it is never commanded blind.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# =============================================================================
#  WHO IS SPEAKING TO THE SERVER? -- account secret, opening ticket, session cookie
# =============================================================================
#
# THE PROBLEM. One elevated server answers the whole machine. With no way of knowing WHICH
# account is behind a request, it can neither refuse an action to a standard account, nor
# serve each one their own settings: everybody inherits those of the account running the
# server.
#
# THREE OBJECTS, AND THEY ARE NOT CONFUSED (design, section Q1):
#
#   account secret    lasting    in THEIR profile, explicit ACL, they alone read it
#   opening ticket    30 s       passed in the URL by the client app, consumed once
#   session cookie    browser    identifies the page afterwards; HttpOnly, so out of reach
#                                of the page's own JavaScript
#
# WHY THAT DETOUR rather than putting the secret in the URL. A URL ends up in the browser's
# history, in the logs, in a copy-paste. A ticket that dies in 30 seconds and serves once is
# worth nothing a minute later.
#
# WHAT THE SERVER DOES NOT STORE: the secret. It keeps none of it -- it RE-READS the
# account's file at the moment of checking. Being elevated, it has the right; and so there is
# no copy to protect, to synchronise, or to revoke.

<#
    RESTARTING THE CLIENT APPS OF EVERY ACCOUNT.

    After an update, only the client app that launched it came back. The others went on
    running the code from BEFORE, loaded in memory from an installation that had just been
    replaced under their feet -- until the next logon.

    So a "restart" order is dropped in each account's folder: their client app reads it within
    the second and restarts itself. No particular right is required of them, and one that is
    not running has nothing to do -- it will start with the new code.

    The server is elevated: it can write into other people's profiles. A client app that has
    never run has no order folder, and none is created for it: there is nothing to restart.
#>
<#
    STOPPING AND STARTING THE CLIENT APPS -- THROUGH THEIR TASK, ALWAYS.

    The task is what knows which identity to launch under, and for ANOTHER account's client
    app it is the only way: starting it directly would ask for their credentials.

    A CLIENT APP'S TASK IS INTERACTIVE: Windows refuses to start it for an account with no
    session. "Open" does not mean "active" -- an account left by "Switch user" keeps a
    DISCONNECTED session, and its task starts there perfectly well (checked on 30/08, two
    sessions coexisting). An account with no session is therefore not an error: its client app
    will come back at its next logon, with the new code.
#>
# ASKS EVERY CLIENT APP TO QUIT ON ITS OWN, through the order it reads each second in its run folder: it logs its
# own stop, acknowledges, and leaves. Until 19/09 an update ended the tasks and killed what was
# left: the client apps of Famille vanished seven times on 18/09 without one line saying why. Returns the accounts
# whose app acknowledged; the forced stop that follows is left for the ones that did not answer. Never throws.
<#
    THE CLIENT APP THAT VANISHES WITHOUT A WORD -- SEEN, AND KEPT.

    On 28/09 the client app of an account started at 19:50, reported itself well, and was gone around 20:22 without one
    line: it did not leave through its own loop, which always logs its exit, and Windows kept nothing either, no
    error, no report, no dump. From then on Vigie measured NOTHING until the next logon, in the middle of a game, and
    said nothing about it afterwards. What is not watched is not known.

    WHAT PROVES IT. The client app writes its heartbeat every eight seconds (var/run/client.alive: process id, time,
    state). A heartbeat that has stopped while the account's registry hive is still loaded -- which only happens during
    its session -- is a client app that should be there and is not. No session, no expectation: that is not a fault.

    WHAT IS KEPT. One line per disappearance in var/history/client-vanished.jsonl, with the account, the last heartbeat,
    the process id that stopped, and THE CONTEXT of the moment -- the game being played, if any. Recorded once per
    disappearance, not once per reading. Vigie restarts nothing on its own: the card names it, the user decides.
#>
function Get-ClientHeartbeat {
    param([Parameter(Mandatory)][string]$Account)
    try {
        $runDir = Get-AccountRunDir -Account $Account
        if (-not $runDir) { return $null }
        $file = Join-Path $runDir 'client.alive'
        if (-not (Test-PathSafe $file)) { return $null }
        $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop
        $parts = "$raw".Trim() -split ';'
        if ($parts.Count -lt 2) { return $null }
        $at = ConvertTo-UtcDate $parts[1]
        if (-not $at) { return $null }
        return [pscustomobject]@{
            ProcessId = [int]$parts[0]
            At        = $at
            State     = $(if ($parts.Count -ge 3) { "$($parts[2])" } else { '' })
        }
    } catch { return $null }
}

<#
    WHAT THE CARD READS -- and it only reads: a probe never acts (D14).

    Rows: one per account whose session is open and that has already had a client app here. Silent tells how many
    minutes its heartbeat has been quiet, -1 when it never wrote one.
#>
function Get-ClientWatchRows {
    # HOW LONG BEFORE CONCLUDING: the heartbeat is every eight seconds, and a loaded machine can miss a few of them.
    # Three minutes without a single beat is no longer lateness.
    param([string]$Backend = (Get-BackendRoot), [int]$SilentMinutes = 3)
    $rows = @()
    $nowUtc = [datetime]::UtcNow
    <#
        NOT FROM THE LIST OF ACCOUNTS: establishing it costs two seconds (measured on 29/09), and this card is
        recomputed often. From the OPEN SESSIONS instead -- a registry hive is only mounted during its owner's session
        -- and then only the accounts that HAVE ALREADY had a client app here, the ones whose heartbeat file exists. An
        account that never started Vigie has lost nothing, and neither has the service account.
    #>
    foreach ($hive in @(Get-UserRegistryRoots)) {
        $name = ''
        try {
            $sid = $hive.Split([char]92)[-1]
            $name = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate(
                        [System.Security.Principal.NTAccount]).Value.Split([char]92)[-1]
        } catch { continue }
        if (-not $name) { continue }
        $beat = Get-ClientHeartbeat -Account $name
        if (-not $beat) { continue }
        $silentMin = [int][Math]::Floor(($nowUtc - $beat.At).TotalMinutes)
        $gone = $silentMin -ge $SilentMinutes
        $said = if ($gone) {
                    "Disparue, muette depuis " + $(if ($silentMin -ge 60) { "$([int][Math]::Floor($silentMin / 60)) h $($silentMin % 60) min" } else { "$silentMin min" })
                } else {
                    # The beat's own state is not repeated when it says what we already say: "En marche (En marche)".
                    "En marche" + $(if ($beat.State -and $beat.State -ne 'En marche') { " ($($beat.State))" } else { '' })
                }
        $rows += [pscustomobject]@{
            Account   = $name
            Session   = $true
            Said      = $said
            Status    = $(if ($gone) { 'warn' } else { 'ok' })
            Silent    = $silentMin
            ProcessId = $beat.ProcessId
            At        = $beat.At
            Beat      = $beat
        }
    }
    return $rows
}

<#
    THE PASS OF THE PERMANENT WATCH: it records a disappearance, and brings the client app back.

    WHY IT ACTS. Until 29/09 nobody brought it back. A client app that dies leaves its task reading "Running" with no
    process behind it, and Windows then REFUSES every start with 0x800710E0 -- the last result of the Famille task, read
    on 29/09. So the account stayed without Vigie until its next logon: no icon, no notification, and nothing asking for
    a recomputation, which is why nothing at all was measured between 20:22 and 21:41 on 28/09, during a game.

    WHAT IT NEVER DOES. It stops no process, and it cannot: what it ends is a task whose process is already gone --
    Start-ClientTasks returns untouched as soon as the process is alive. Nothing is killed, here or anywhere below.

    HOW IT IS BOUNDED. A disappearance must be seen TWICE IN A ROW, one minute apart, on the same stopped heartbeat.
    Then at most two attempts for that heartbeat, each one logged with its outcome. A client app that will not come back
    is said on the card, not retried forever.
#>
function Update-ClientWatch {
    param([string]$Backend = (Get-BackendRoot), [int]$SilentMinutes = 3, [int]$MaxTries = 2)
    $rows = @(Get-ClientWatchRows -Backend $Backend -SilentMinutes $SilentMinutes)
    $stateFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'client-watch.json'
    $known = @{}
    try {
        if (Test-PathSafe $stateFile) {
            $raw = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 -ErrorAction Stop
            foreach ($pr in @((ConvertFrom-Json $raw).PSObject.Properties)) {
                $known["$($pr.Name)"] = @{ key = "$($pr.Value.key)"; seen = [int]$pr.Value.seen; tries = [int]$pr.Value.tries }
            }
        }
    } catch { }
    $nowUtc = [datetime]::UtcNow
    $toRelaunch = @()
    foreach ($row in $rows) {
        $name = "$($row.Account)"
        if ($row.Status -eq 'ok') { if ($known.ContainsKey($name)) { $known.Remove($name) }; continue }
        <#
            ONCE PER DISAPPEARANCE, not once per reading: the key is the heartbeat that stopped.

            That key is in TICKS, not in ISO 8601, and it matters: ConvertFrom-Json turns an ISO date into a
            [datetime] (D44). Read back, it no longer compared to the string that had been written -- the comparison
            always failed, and three readings in a row wrote the same disappearance three times (measured on 29/09).
            A number reads back as a number.
        #>
        $key = "$($row.Beat.At.Ticks)"
        $entry = $known[$name]
        if (-not $entry -or "$($entry.key)" -ne $key) {
            $known[$name] = @{ key = $key; seen = 1; tries = 0 }
            # THE CONTEXT OF THE MOMENT, or the line does not answer "why did it go?". The game being played first:
            # that is when a disappearance costs the most, and that is when it happened.
            $game = $null
            try { $game = Get-GameModeName -Backend $Backend } catch { }
            $record = [ordered]@{
                at      = $nowUtc.ToString('o')
                account = $name
                lastAt  = $row.Beat.At.ToString('o')
                pid     = $row.Beat.ProcessId
                state   = $row.Beat.State
                silent  = [int]$row.Silent
                game    = $game
            }
            try {
                $file = Get-VarPath -Backend $Backend -Kind 'history' -File 'client-vanished.jsonl'
                Add-HistoryLine -Path $file -Line ($record | ConvertTo-Json -Depth 4 -Compress) | Out-Null
                # GROWTH IS BOUNDED: a disappearance is rare, two hundred of them tell months.
                $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue)
                if ($lines.Count -gt 200) { Set-Content -LiteralPath $file -Value ($lines | Select-Object -Last 200) -Encoding UTF8 }
                Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                    "app cliente disparue : $name, PID $($row.Beat.ProcessId), dernier battement " +
                    $row.Beat.At.ToLocalTime().ToString('dd/MM HH:mm:ss') +
                    $(if ($game) { ", jeu en cours : $game" } else { '' }))
            } catch { }
            continue
        }
        $entry.seen = [int]$entry.seen + 1
        if ($entry.seen -ge 2 -and [int]$entry.tries -lt $MaxTries) {
            $entry.tries = [int]$entry.tries + 1
            $toRelaunch += [pscustomobject]@{ Account = $name; Try = [int]$entry.tries }
        }
        $known[$name] = $entry
    }
    foreach ($r in $toRelaunch) {
        # THE TASK KNOWS WHICH IDENTITY TO START UNDER, and for another account's client app it is the only way. The
        # list of accounts costs two seconds: it is read HERE only, a relaunch being rare.
        $account = $null
        try { $account = @(Get-EnabledAccounts -Backend $Backend | Where-Object { "$($_.name)" -eq "$($r.Account)" })[0] } catch { }
        if (-not $account -or -not $account.task) {
            try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message ("relance impossible : aucune tache pour $($r.Account)") } catch { }
            continue
        }
        <#
            A CLIENT APP THAT STILL HAS ITS PROCESS IS NOT GONE, IT IS STUCK -- and a stuck process is not ours to end
            (18/09). Nothing is relaunched then: the card says it is alive and silent, and the decision stays the
            user's. Only a client app whose process has really gone is brought back.
        #>
        <#
            THE PROCESS ID THAT WROTE THE HEARTBEAT decides, and it decides FIRST.

            Measured on 29/09, and it cost a client app: Test-VigieTaskProcessAlive compares COMMAND LINES, which
            Windows hides for an elevated process from a session that is not. It answered "no process" about a client
            app that was running, and Start-ClientTasks then ended the task -- that is, the live process -- before
            starting it again. A test that can be wrong must never be the last word before an act.

            A process id is readable by everyone, for every process. If the one that wrote the last heartbeat still
            exists and is still a PowerShell, the client app is alive and silent: nothing is relaunched, nothing is
            ended, and the card says so. An id could have been reused by another PowerShell, and the consequence of
            believing it is exactly the right one: we do nothing.
        #>
        $alive = $false
        try {
            $held = Get-Process -Id ([int]$row.Beat.ProcessId) -ErrorAction Stop
            if ($held -and $held.ProcessName -in @('pwsh', 'powershell')) { $alive = $true }
        } catch { }
        if (-not $alive) {
            try { $alive = Test-VigieTaskProcessAlive -Task (Get-ScheduledTask -TaskName "$($account.task)" -ErrorAction Stop) } catch { }
        }
        if ($alive) {
            foreach ($row in $rows) {
                if ("$($row.Account)" -ne "$($r.Account)") { continue }
                $row.Said = $row.Said + ' — vivante mais muette'
            }
            try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                    "app cliente de $($r.Account) vivante mais muette : aucune relance, on n'arrete pas un processus") } catch { }
            continue
        }
        $started = @()
        try { $started = @(Start-ClientTasks -Accounts @($account)) } catch { }
        try {
            Write-Log -Backend $Backend -Name 'state' -Level $(if ($started.Count) { 'INFO' } else { 'WARN' }) -Message (
                "relance de l'app cliente de $($r.Account), tentative $($r.Try) : " +
                $(if ($started.Count) { 'demandee' } else { 'refusee par Windows' }))
        } catch { }
        foreach ($row in $rows) {
            if ("$($row.Account)" -ne "$($r.Account)") { continue }
            $row.Said = $row.Said + $(if ($started.Count) { " — relance demandée" } else { " — relance refusée" })
        }
    }
    try { Set-Content -LiteralPath $stateFile -Value (ConvertTo-Json $known -Depth 4 -Compress) -Encoding UTF8 } catch { }
    return $rows
}

function Request-ClientStop {
    param([string]$Backend = (Get-BackendRoot), [int]$TimeoutSec = 10)
    $asked = @()
    foreach ($c in @(Get-EnabledAccounts -Backend $Backend)) {
        try {
            $runDir = Get-AccountRunDir -Account "$($c.name)"
            if (-not $runDir -or -not (Test-PathSafe $runDir)) { continue }
            Remove-Item -LiteralPath (Join-Path $runDir 'stop.ack') -Force -ErrorAction SilentlyContinue
            Set-Content -LiteralPath (Join-Path $runDir 'stop') -Value 'install' -Encoding ASCII -NoNewline -ErrorAction Stop
            $asked += [pscustomobject]@{ name = "$($c.name)"; runDir = $runDir }
        } catch { }
    }
    $acknowledged = @()
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($asked.Count -and (Get-Date) -lt $deadline) {
        foreach ($a in @($asked)) {
            if (Test-Path -LiteralPath (Join-Path $a.runDir 'stop.ack')) { $acknowledged += $a.name; $asked = @($asked | Where-Object { $_.name -ne $a.name }) }
        }
        if ($asked.Count) { Start-Sleep -Milliseconds 250 }
    }
    # AN ORDER NOBODY READ IS WITHDRAWN: a client app started later must not quit on reading it.
    foreach ($a in @($asked)) { Remove-Item -LiteralPath (Join-Path $a.runDir 'stop') -Force -ErrorAction SilentlyContinue }
    # The acknowledgement precedes the exit by a moment: leave it that moment before anything is forced.
    if ($acknowledged.Count) { Start-Sleep -Seconds 2 }
    return $acknowledged
}

function Stop-ClientTasks {
    param([string]$Backend = (Get-BackendRoot))
    $stopped = @()
    foreach ($c in @(Get-EnabledAccounts -Backend $Backend)) {
        if (-not $c.task) { continue }
        try { Stop-ScheduledTask -TaskName "$($c.task)" -ErrorAction Stop } catch { }
        $stopped += [pscustomobject]@{ name = "$($c.name)"; task = "$($c.task)" }
    }
    return $stopped
}

function Start-ClientTasks {
    param([Parameter(Mandatory)]$Accounts)
    $started = @()
    foreach ($a in @($Accounts)) {
        if (-not $a.task) { continue }
        try {
            # A CLIENT APP ALREADY RUNNING IS NOT STARTED AGAIN: under IgnoreNew Windows refuses, and the refusal becomes
            # the task's last result (13/09). The process decides, not the task's state: re-registered a few seconds
            # earlier, the task no longer reads Running while its instance still runs (22:39 the same day).
            $current = Get-ScheduledTask -TaskName "$($a.task)" -ErrorAction Stop
            if (Test-VigieTaskProcessAlive -Task $current) { continue }
            # A TASK THAT READS « Running » WITH NOBODY BEHIND IT REFUSES TO START. Windows keeps the state after the
            # process is gone, and the start comes back 0x800710E0, « request refused » -- the account is then left
            # without its client app until the next logon. Seen on 28/09, on the very account that asked for the
            # update. Ending the ghost costs nothing when there is none.
            if ("$($current.State)" -eq 'Running') {
                try { Stop-ScheduledTask -TaskName "$($a.task)" -ErrorAction Stop; Start-Sleep -Milliseconds 700 } catch { }
            }
            Start-ScheduledTask -TaskName "$($a.task)" -ErrorAction Stop
            $started += "$($a.name)"
        } catch { }
    }
    return $started
}

<#
    THE CLIENT APPS STARTED OUTSIDE THEIR TASK.

    Stopping the task does not kill what it did not start: a client app launched by hand -- a
    development try -- would go on running on files being replaced. So whatever is left is
    swept, aiming at what RUNS the client app's script, whatever the account: the installation
    is elevated and sees them all.

    Returns the number of processes stopped.
#>
function Stop-StandaloneClients {
    $killed = 0
    $leaf = 'client.ps1'
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
        $line = "$($p.CommandLine)"
        if (-not $line -or $line -notmatch [regex]::Escape($leaf)) { continue }
        if ([int]$p.ProcessId -eq $PID) { continue }
        try { Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction Stop; $killed++ } catch { }
    }
    return $killed
}

function Send-ClientRestartToAll {
    # "Except me" means "except WHOEVER ASKS": their client app has just carried out the
    # update and restarts itself. The service account has no client app at all.
    # Nobody identified: EVERYONE is told. That is the right default -- a client app
    # restarted for nothing is back in two seconds; one keeping the old code lies until the
    # next logon.
    param([string]$Except = (Get-RequesterAccount))
    $touches = @()
    # The accounts that have a client app: those whose startup task exists.
    $avecAppCliente = @()
    try { $avecAppCliente = @(Get-EnabledAccounts | ForEach-Object { "$($_.name)" }) } catch { }
    $users = Join-Path $env:SystemDrive 'Users'
    if (-not (Test-Path -LiteralPath $users)) { return $touches }
    foreach ($profil in @(Get-ChildItem -LiteralPath $users -Directory -ErrorAction SilentlyContinue)) {
        if ($Except -and $profil.Name -ieq $Except) { continue }
        # A PROFILE WE CANNOT READ IS NOT AN ERROR. From a session without rights, the mere
        # existence test on another account's folder THROWS -- and under
        # "ErrorActionPreference = Stop" it takes the whole function with it. The server is
        # elevated and has no such trouble, but a function must not depend on who calls it:
        # we move on to the next, in silence.
        # HAVING AN ORDER FOLDER DOES NOT MEAN HAVING A CLIENT APP. The service account has
        # one -- the SERVER app drops its busy marks there -- and it therefore received a
        # "restart" order nobody will ever read: "Relance demandee aux autres comptes :
        # Famille, fhaza, VigieService" (seen on 30/08).
        #
        # What proves an account has a client app is ITS STARTUP TASK.
        if ($avecAppCliente -notcontains $profil.Name) { continue }
        $run = $null
        try { $run = Get-AccountRunDir -Account $profil.Name } catch { continue }
        if (-not $run) { continue }
        if (-not (Test-PathSafe $run)) { continue }
        # WE DO NOT HAVE TO KNOW WHETHER THE CLIENT APP IS RUNNING. A client app erases the
        # pending orders when it starts: an order left for an absent client app does not
        # survive its return, and that return happens with the new code anyway. Checking its
        # heartbeat added a disk access and a condition for nothing.
        try {
            Set-Content -LiteralPath (Join-Path $run 'restart') -Value 'update' -Encoding ASCII -NoNewline
            $touches += $profil.Name
        } catch { }
    }
    return $touches
}

<#
    HOW A CLIENT APP IS STARTED -- written ONCE, used by everyone who builds that task.

    It was written in three places: the installer, the repair of the legacy task, and the enabling of an account. On
    29/09 I changed one of them and the two others kept the old line, so the fault stayed exactly where it had been
    reported. Three copies of a launch line is three launch lines.

    conhost --headless creates the console WITHOUT a window. "-WindowStyle Hidden" only hides one that Windows has
    already made: unnoticed on an administrator account, an empty terminal at every logon on a standard one, and a
    flash that steals the focus whenever a deployment restarts a client app.
#>
function Get-HeadlessConsolePath {
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    if (Test-PathSafe $conhost) { return $conhost }
    return $null
}

function New-VigieClientAction {
    param([Parameter(Mandatory)][string]$Pwsh, [Parameter(Mandatory)][string]$Client)
    $arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Client + '"'
    $conhost = Get-HeadlessConsolePath
    if ($conhost) { return (New-ScheduledTaskAction -Execute $conhost -Argument ('--headless "' + $Pwsh + '" ' + $arg)) }
    return (New-ScheduledTaskAction -Execute $Pwsh -Argument $arg)
}

<#
    HAVING AN ACTION RUN BY AN ACCOUNT'S CLIENT APP.

    An order is dropped in its folder, and we wait for its report. The client app runs in ITS
    session, with ITS rights and ITS desktop: the window opens where the requester sees it,
    and the action obtains nothing Windows would refuse it.

    THE ORDER CHANNEL IS AN ATTACK SURFACE (design, C8). It lives in the account's profile,
    where only that account and the administrators write. A folder anybody could drop into
    would be a way of having anything run by anyone.

    NOTHING IS GUARANTEED ON THE OTHER SIDE: the client app may be stopped, the session
    closed, the account signed out. We then return $null, and the caller decides -- here, it
    runs the action itself, as before. An action that does not open on the right desktop beats
    an action that does not open at all.
#>
function Invoke-ClientTask {
    param(
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][string]$Type,
        [hashtable]$Params,
        [string]$Module,
        [int]$TimeoutSec = 12,
        [string]$Backend = (Get-BackendRoot)
    )
    $runDir = Get-AccountRunDir -Account $Account
    if (-not $runDir) { return $null }
    if (-not (Test-Path -LiteralPath $runDir)) {
        try { New-Item -ItemType Directory -Path $runDir -Force | Out-Null } catch { return $null }
    }
    $id    = New-RandomId
    # THE FILE NAME SAYS WHAT THE TASK IS (S17, D129): a client task, named after the app that runs it. The former
    # name carried a notion nobody had validated. No reading of both names: an installation stops and restarts every
    # client app, so a task written in the seconds before it would be lost either way -- and the caller says so,
    # since every client task reports back even when it fails.
    $order = Join-Path $runDir ('client-task-' + $id + '.json')
    $done  = Join-Path $runDir ('client-task-' + $id + '.done.json')
    $charge = @{ type = $Type; module = $Module; params = $Params; at = (Get-EpochSeconds) }
    try { ($charge | ConvertTo-Json -Compress -Depth 6) | Out-File -FilePath $order -Encoding UTF8 }
    catch { return $null }

    $deadline = (Get-EpochSeconds) + $TimeoutSec
    while ((Get-EpochSeconds) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (Test-Path -LiteralPath $done) {
            $data = $null
            try { $data = Get-Content -LiteralPath $done -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
            Remove-Item -LiteralPath $done -Force -ErrorAction SilentlyContinue
            return $data
        }
    }
    # NO ANSWER: our order is withdrawn. Without that, a client app coming back in an hour
    # would open a window nobody is waiting for any more.
    Remove-Item -LiteralPath $order -Force -ErrorAction SilentlyContinue
    return $null
}
