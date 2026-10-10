# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    client.ps1 -- the Vigie client app, in the notification area (apps/client).

    Intent: give each account its own presence on its own desktop -- an icon that says whether Vigie is running, a
    menu to show it, restart it or stop it, and the notifications of the modules it has turned on. It is an app IN
    ITS OWN RIGHT, distinct from the server app: it has its own WinForms interface, its own icons (assets/) and its
    own life cycle. It DRIVES the server app -- starts it, stops it, probes its health -- without being part of it.

    Usage: Windows starts it at logon, one instance per account (a mutex named after the account). Started by hand
    it does the same thing; a second one steps aside. What it does, in brief:
      - the server app runs IN THE BACKGROUND (hidden). The ICON IS THE STATE OF THE APP, not of the components,
        read from /health: green = running, orange = starting, red = error or stopped. A light poll every 8 s.
      - the menu entry that shows the application opens a DEDICATED window (Edge or Chrome in --app mode); the
        one that opens it in the browser opens a tab.
      - the entry that restarts the application reloads the client app itself. A dark menu. Children are started with no window
        (CreateNoWindow).
      - it logs into logs/client_*.log. The interface lives in an STA runspace.
#>
$ErrorActionPreference = 'Stop'
# The repository URL: a deliberate CONSTANT, not a setting -- it must not be easy to change.
# Its counterpart on the front end: REPO_URL in frontend/index.html.
$RepoUrl = 'https://github.com/Cartman34/vigie-windows'
# The server app is a SISTER app (apps/backend-pode), not the current folder.
$appsRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $appsRoot 'backend-pode'   # BOOTSTRAP : nom en clair, cf. common.ps1
$repoRoot = Split-Path $appsRoot -Parent
# Every app manages its own local files under ITS OWN var/ (D33) -- BUT NEVER beside the program when the program
# lives in Program Files (D97).
#
# THIS is where Vigie failed to start on a standard account. The path was computed by hand: "$PSScriptRoot/var/log".
# On the administrator's account the task runs elevated, the folder is created inside Program Files and everything
# works. On "Famille", a Limited account, Windows refuses the write: New-Item throws, $ErrorActionPreference is
# 'Stop', and the script dies BEFORE TLog exists. Exit code 1, no log anywhere, no trace at all -- exactly what was
# observed on 28/08.
#
# Get-VarPath applies the rule once and for all: in place when that is possible, in the account's profile
# otherwise. So it is loaded BEFORE anything is written.

$appsRootTmp = Split-Path $PSScriptRoot -Parent
. (Join-Path (Join-Path $appsRootTmp 'backend-pode') 'lib/common.ps1')
$clientLog = Get-VarPath -Backend $PSScriptRoot -Kind 'log' -File ('client_' + (Get-Date -Format 'yyyyMMdd') + '.log')
function TLog($m) { try { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Out-File -FilePath $clientLog -Append -Encoding UTF8 } catch { } }
TLog "demarrage (PS $($PSVersionTable.PSVersion), $([System.Threading.Thread]::CurrentThread.GetApartmentState()))"
# Its own logs are kept 30 days, like everyone else's (Invoke-LogPurge).
try { $null = Invoke-LogPurge -Backend $PSScriptRoot } catch { }

# ONE LOCK PER ACCOUNT, not per desktop session. Without an explicit namespace a mutex lives in "Local\", that is,
# inside the Windows session -- and two accounts can share a session: that is what happens when one starts another
# account's client app with runas, exactly what we do to debug. Famille's client app started, saw fhaza's lock, and
# stepped aside (28/08 22:09). The lock is therefore named after the account now: each has its own, whatever
# session hosts it.
<#
    IT IS THE SUCCESSOR THAT WAITS, NOT THE ONE ASKING.

    Four seconds were not enough: during a restart the old instance closes its icon, hands control back to Windows
    and releases its lock -- which sometimes takes longer than that. The new one then exited on "already running",
    the process number never changed, and the installation counted two failures on a client app that was running
    (observed on 30/08).

    So we wait HERE, in the process that is starting: nobody upstream is blocked, and the normal case -- no
    predecessor -- goes through with no delay. Twenty seconds amply cover the closing of an icon; beyond that, an
    instance really is running.
#>

#>
$mutex = New-Object System.Threading.Mutex($false, ('VigieClient-' + (Get-ProcessAccount)))
if (-not $mutex.WaitOne(20000)) { TLog "deja lance (mutex) - sortie"; return }

$uiScript = {
    param($backend, $clientLog, $repoUrl, $clientRoot)
    $ErrorActionPreference = 'Continue'
    function TLog($m) { try { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Out-File -FilePath $clientLog -Append -Encoding UTF8 } catch { } }
    try {
        . (Join-Path $backend 'lib/common.ps1')
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        Add-Type -Namespace VigieNative -Name Ico -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr handle);'

        # S5 -- A CHANGE OF NETWORK ADDRESS, at once.
        #
        # Without this, unplugging the cable or changing Wi-Fi left the Network card showing the old address until
        # its probe expired. Windows can say the instant of the change: we subscribe to it.
        #
        # The subscription is made IN C#, not by a PowerShell block: Windows warns on a pool thread, where running
        # PowerShell demands a runspace that is not necessarily available. The native handler does one thing only,
        # set a flag; it is the interface loop (every second) that acts.


        Add-Type -Namespace VigieNative -Name Net -MemberDefinition @'
public static volatile bool Changed = false;
public static void Watch() {
    System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged += delegate { Changed = true; };
    System.Net.NetworkInformation.NetworkChange.NetworkAvailabilityChanged += delegate { Changed = true; };
}
'@

        <#
            IS ANYBODY LOOKING AT THIS SESSION?

            Every account's client app watches the SAME server, so every account sees every
            state change -- including the accounts nobody is sitting in front of. Windows
            does not throw those toasts away: it QUEUES them and hands the whole pile over
            the moment the session comes back. Measured on 06/09: fhaza's log and Famille's
            log carry the same ten notifications at the same seconds, and switching accounts
            delivered the lot at once.

            WE ASK FOR A STATE, NOT AN EVENT. A SessionSwitch subscription only says what
            CHANGED: a client app started while its session was already in the background
            would never learn it, and a missed event would be missed for ever. The console
            session id is the truth at any instant, and it can be read again at every pass.

            WHEN WINDOWS DOES NOT KNOW, WE DO NOT CONCLUDE: 0xFFFFFFFF means no session is
            attached to the console, and an unreadable answer is not a reason to go silent.
        #>
        Add-Type -Namespace VigieNative -Name Wts -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint WTSGetActiveConsoleSessionId();

public static bool SomeoneIsWatching(int mySession) {
    uint console = WTSGetActiveConsoleSessionId();
    if (console == 0xFFFFFFFF) { return true; }
    return console == (uint)mySession;
}
'@

        # Wearing the declared identity. See "the bubbles must say Vigie", further down.
        Add-Type -Namespace VigieNative -Name Aumid -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);
'@

        # Find a window by its title, and bring it to the front.
        # Without this, every double click opened one MORE window: the application ended up twice over in the task
        # bar.
        Add-Type -Namespace VigieNative -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.IntPtr lParam);
public delegate bool EnumWindowsProc(System.IntPtr hWnd, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsIconic(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool PostMessage(System.IntPtr hWnd, uint msg, System.IntPtr w, System.IntPtr l);

// Titre EXACT attendu : le front pose « <machine> - Vigie » (document.title).
public static System.IntPtr FindBySuffix(string suffix) {
    System.IntPtr found = System.IntPtr.Zero;
    EnumWindows(delegate(System.IntPtr h, System.IntPtr p) {
        if (!IsWindowVisible(h)) return true;
        System.Text.StringBuilder sb = new System.Text.StringBuilder(512);
        if (GetWindowText(h, sb, sb.Capacity) == 0) return true;
        if (sb.ToString().EndsWith(suffix, System.StringComparison.Ordinal)) { found = h; return false; }
        return true;
    }, System.IntPtr.Zero);
    return found;
}

// SW_RESTORE = 9 : deminiaturise si besoin, puis met au premier plan.
public static bool Focus(System.IntPtr h) {
    if (h == System.IntPtr.Zero) return false;
    if (IsIconic(h)) ShowWindow(h, 9);
    return SetForegroundWindow(h);
}

// IS IT WATCHED? The foreground window is the only one actually being looked at.
public static bool IsWatched(System.IntPtr h) {
    return h != System.IntPtr.Zero && GetForegroundWindow() == h;
}

// WM_CLOSE = 0x10: the close is ASKED for, nothing is killed. A window that refuses stays open.
public static bool Close(System.IntPtr h) {
    if (h == System.IntPtr.Zero) return false;
    return PostMessage(h, 0x0010, System.IntPtr.Zero, System.IntPtr.Zero);
}
'@

        $cfg       = Get-Config -Backend $backend
        $url       = Get-AppUrl -Config $cfg
        $healthUrl = (Get-ApiUrl -Config $cfg) + '/health'
        $pwsh      = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        $clientPath  = Join-Path $clientRoot 'client.ps1'      # cette app, pas le backend

        <#
            THE PROTOCOL VIGIE:// -- DECLARED HERE, FOR THIS ACCOUNT ONLY.

            Windows opens nothing when a notification is clicked unless the notification names a target it knows how
            to reach, and a script cannot be that target: a protocol can. The declaration lives under HKCU, so it
            belongs to the account and needs no privilege; it is rewritten whenever the installation moves, because a
            protocol pointing at a path that no longer exists is worse than none.
        #>
        try {
            $protocolScript = Join-Path $clientRoot 'protocol.ps1'
            $protocolCommand = '"{0}" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" "%1"' -f $pwsh, $protocolScript
            $protocolKey = 'HKCU:\Software\Classes\vigie'
            $alreadySet = $null
            try { $alreadySet = (Get-ItemProperty -Path (Join-Path $protocolKey 'shell\open\command') -ErrorAction Stop).'(default)' } catch { }
            if ($pwsh -and (Test-Path -LiteralPath $protocolScript) -and "$alreadySet" -ne $protocolCommand) {
                New-Item -Path (Join-Path $protocolKey 'shell\open\command') -Force | Out-Null
                Set-ItemProperty -Path $protocolKey -Name '(default)' -Value 'URL:Vigie'
                Set-ItemProperty -Path $protocolKey -Name 'URL Protocol' -Value ''
                Set-ItemProperty -Path (Join-Path $protocolKey 'shell\open\command') -Name '(default)' -Value $protocolCommand
                TLog 'protocole vigie:// declare pour ce compte'
            }
        } catch { TLog ('protocole vigie:// non declare : ' + $_.Exception.Message) }

        # Starting: a start has been asked for and the server has not answered yet.
        $state     = [hashtable]::Synchronized(@{ Proc = $null; Drawn = ''; EverUp = $false; Starting = $true; StartTicks = [datetime]::UtcNow.Ticks; Mods = @{}; ModsInit = $false; HealthKo = 0; MachineTask = $null; ElevationAsked = $false; SaidDead = $false; Bulles = @{}; DerniereBulle = $null; NotifTicks = 0; ApiSession = $null; Present = $true; NotifPar = @{} })
        # OUR Windows session, read once: it does not change for the life of the process.
        # The console session is compared against it at every pass.
        $mySession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
        # The server app's state cache: read (never written) by the module watcher (D54).
        # (the state is asked of the API: this file is no longer read -- see the notifications block)
        <#
            HOW LONG BEFORE DECLARING A FAILED START?

            25 seconds, until 28/08. But the server takes about SIXTY-FIVE seconds to answer: the client app's log
            shows the same sequence at every launch -- orange for 22 s, then RED, then green some forty seconds
            later. So the user saw a breakdown at every start while everything was going well. A signal that cries
            wrongly ends up ignored, and the day the server really fails nobody is looking at it any more.

            WE NO LONGER GUESS, WE WATCH THE PROCESS. As long as the one we started is ALIVE, the start is under
            way: that is a proof, not an estimate. If it has gone, that is a failure -- and we say so at once,
            without waiting for a delay to run out. The ceiling now serves only as a guard against a server that
            would stay alive without ever answering.

            The case of a client app that ADOPTS a server already in place ($state.Proc empty) keeps a delay, for
            want of a process to watch: a wide one, because we know nothing.
        #>



        $startupGrace   = 120   # the ceiling when we are watching the process we started
        $startupBlind   = 90    # the delay when we have no process to watch

        # --- Self-repair of the start-up task ---------------------------------------
        # The client app runs ELEVATED: it is the only one that can fix its own scheduled task without asking the
        # user for an elevation again. The task failed intermittently at logon (0xC0070154: pwsh comes from the
        # Store and its MSIX package is not always ready the second the session opens). Idempotent: it touches the
        # delay and the retries only, and only if they are missing.

        # ITS OWN TASK, NOT SOMEBODY ELSE'S. It is called "Vigie - <account>" (D117); plain
        # "Vigie" is the old name, kept as a fallback while machines still carry it. Looking
        # for another account's name is never repairing anything -- which is what the Famille
        # log repeated at every start (04/09).
        try {
            $ownTaskName = Get-VigieAccountTaskName -Name (Get-ProcessAccount)
            $ownTask = $null
            try { $ownTask = Get-ScheduledTask -TaskName $ownTaskName -ErrorAction Stop } catch { }
            if (-not $ownTask) { $ownTask = Get-ScheduledTask -TaskName 'Vigie' -ErrorAction Stop }
            $toFix = $false
            if (-not $ownTask.Triggers[0].Delay) { $ownTask.Triggers[0].Delay = 'PT45S'; $toFix = $true }
            if (-not $ownTask.Settings.RestartCount) {
                $ownTask.Settings.RestartCount = 3
                $ownTask.Settings.RestartInterval = 'PT1M'
                $toFix = $true
            }
            if ($toFix) {
                Set-ScheduledTask -InputObject $ownTask | Out-Null
                TLog "tache planifiee reparee : delai PT45S + 3 reprises (echec MSIX au logon)"
            }
        } catch { TLog ("tache planifiee non reparable ici : " + $_.Exception.Message) }
        $iconHandle = [System.IntPtr]::Zero

        # --- Driven by orders dropped in var/run -------------------------------------
        # The client app runs ELEVATED: from an ordinary session one can neither read its command line nor signal a
        # kernel object it created. A folder of orders avoids both obstacles, stays inspectable by eye, is
        # scriptable from anything, and accepts new orders without touching the mechanism.
        # See scripts/client.ps1 for the sending side.

        $runDir    = Get-VarPath -Backend $clientRoot -Kind 'run'
        $heartbeat = Join-Path $runDir 'client.alive'
        # A brutal stop leaves orders unconsumed: they must not apply at the next start.
        #
        # EXCEPT the acknowledgements: the one the previous client app has just laid down is precisely what the
        # sender is waiting for, and we are starting within the second that follows. Erasing them on the way in was
        # racing against it -- and making it conclude "order not read" on a restart that worked. A stale
        # acknowledgement bothers nobody: the sender erases its own BEFORE sending its order.


        Get-ChildItem -LiteralPath $runDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ne '.ack' } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $launchHidden = {
            param($file, $argv)
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $file; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            foreach ($x in $argv) { [void]$psi.ArgumentList.Add([string]$x) }
            return [System.Diagnostics.Process]::Start($psi)
        }
        <#
            IS THE MACHINE'S SERVER TASK ALREADY HOLDING THE MACHINE?

            That is THE question of the migration. As long as there is one server per session, each account's
            client app starts its own -- the historical behaviour. As soon as the "Vigie - Serveur" task is
            enabled, a single server answers for the whole machine: if the client apps went on starting one, they
            would fight over port 47600, and the loser would die without anybody knowing which one answers.

            THE ANSWER IS CACHED. The state of a scheduled task does not change during a session, and asking for
            it every eight seconds costs for nothing.

            IF WE CANNOT READ THE TASK, we answer "no". An account Windows refuses the read to must not end up
            with no server at all: we keep the historical behaviour, which works.
        #>


        $machineServerActive = {
            if ($null -ne $state.MachineTask) { return $state.MachineTask }
            $actif = $false
            try {
                $t = Get-ScheduledTask -TaskName 'Vigie - Serveur' -ErrorAction Stop
                $actif = ("$($t.State)" -ne 'Disabled')
            } catch { $actif = $false }
            $state.MachineTask = $actif
            if ($actif) { TLog "tache serveur active : l'app cliente ne lancera pas de serveur" }
            return $actif
        }

        <#
            ASKING THE SERVER TO RESTART ITSELF.

            It is already elevated: it starts its successor with ITS OWN rights, and nobody has anything to
            authorise -- not even a standard account. This is the normal road.

            Returns: 'ok' if it accepted, 'busy:<operation>' if it refuses because an operation is running, 'ko' if
            it does not answer -- and only in that last case will we speak of elevation, since there is no longer
            anybody there to restart itself.
        #>

        # THE QUESTION WINDOW, once for the whole client app. Returns 0 (the main button), 4 (a third way out) or 3
        # (refusal).
        $askWindow = {
            param($Subject, $Body, $okText, $tiersText, $nonText)
            try {
                $script = Join-Path (Split-Path (Split-Path $backend -Parent) -Parent) 'scripts/lib/show-confirm.ps1'
                if (-not (Test-Path -LiteralPath $script)) { return 3 }
                $payload = Join-Path ([IO.Path]::GetTempPath()) ('vigie-client-' + [guid]::NewGuid().ToString('N') + '.json')
                # The text travels through a FILE: as an argument, its accents would be damaged by the code page of
                # the process called.
                [IO.File]::WriteAllText($payload,
                    (@{ title = "$Subject"; summary = "$Body" } | ConvertTo-Json -Compress),
                    (New-Object Text.UTF8Encoding($false)))
                # RAW VALUES: the call operator quotes each argument itself, and a value
                # wrapped by hand would arrive WITH its quotes (D116).
                $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script,
                          '-Caption', 'Vigie', '-PayloadFile', $payload,
                          '-OkText', $okText, '-CancelText', $nonText, '-Note', '')
                if ($tiersText) { $argv += @('-ThirdText', $tiersText) }
                & $pwsh @argv | Out-Null
                $code = $LASTEXITCODE
                try { Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue } catch { }
                return $code
            } catch { TLog ("fenetre KO : " + $_.Exception.Message); return 3 }
        }

        $askServerRestart = {
            param([bool]$Force, [bool]$Wait)
            try {
                $token = Get-ApiToken -Backend $backend
                $body  = if ($Force)   { '{"type":"server-restart","params":{"force":true}}' }
                         elseif ($Wait) { '{"type":"server-restart","params":{"wait":true}}' }
                         else           { '{"type":"server-restart"}' }
                $rep = Invoke-RestMethod -Method Post -Uri ($url.TrimEnd('/') + '/api/v1/actions') `
                            -ContentType 'application/json' -Body $body -TimeoutSec 6 `
                            -Headers @{ Authorization = ('Bearer ' + $token); Origin = $url.TrimEnd('/') }
                if ($rep.result -and $rep.result.busy) { return ('busy:' + $rep.result.operation) }
                if ($rep.result -and $rep.result.ok)   { return 'ok' }
                return 'ko'
            } catch { return 'ko' }
        }

        $startServer = {
            if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) { return }
            # THE MACHINE TAKES CARE OF IT: we have nothing to start, and above all nothing to fight over.
            if (& $machineServerActive) { return }

            <#
                WITHOUT THE RIGHTS, WE ASK FOR THEM -- BUT ONCE ONLY.

                start.ps1 demands elevation and restarts itself with "RunAs": on a standard account Windows opens a
                UAC window asking for an administrator's credentials. That is the wanted behaviour -- somebody can
                come and type them -- and the client app must keep that ability.

                What was wrong is the REPETITION: the poll comes back every eight seconds, so the window came back
                every eight seconds. A refused request does not present itself again on its own; it presents itself
                when asked for, through the menu entry that restarts the server.
            #>


            if (-not (Test-IsElevated)) {
                if ($state.ElevationAsked) { return }
                $state.ElevationAsked = $true
                TLog "serveur arrete : demande d'elevation (une fois)"
            }
            # A start that was WANTED reopens the window of tolerance: for $startupGrace seconds, "unreachable"
            # means "starting" (orange) and not "broken down" (red).
            $state.StartTicks = [datetime]::UtcNow.Ticks
            $state.Starting   = $true
            if ($pwsh) { $state.Proc = & $launchHidden $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $backend 'start.ps1')) }
        }
        # STOPPING THE SERVER, even when it is not OUR child.
        #
        # A restarted client app ADOPTS the server already in place: $state.Proc is then empty, and the old
        # $stopServer killed nothing. The consequence, measured on 26/08: "Relancer l'application" (and so the
        # restart after a deployment) left the OLD server running -- the new client app saw "server ok" and went on
        # with stale code. Fallback: the process LISTENING on the port, and only if it is a PowerShell interpreter
        # -- we kill nothing but what we could have started ourselves.
        # STOPPING THE SERVER IS A RARE, ASKED-FOR GESTURE. This function is no longer called except on somebody's
        # explicit decision, when the server no longer answers. Neither "Quitter", nor "Relancer l'application",
        # nor the detection of a stuck server touches it: they come after it, and it serves everybody.


        $stopServer = {
            try { if ($state.Proc -and -not $state.Proc.HasExited) { $state.Proc.Kill(); return } } catch { }
            try {
                $c = Get-PortListener -Port $cfg.Port
                if ($c -and $c.OwningProcess) {
                    $p = Get-Process -Id ([int]$c.OwningProcess) -ErrorAction Stop
                    if (@('pwsh','powershell') -contains $p.ProcessName) {
                        TLog ("arret du serveur adopte (PID " + $p.Id + ")")
                        $p.Kill()
                    }
                }
            } catch { }
        }

        # A CLEAN exit, the only end-of-life road. It releases the icon: a process that is killed leaves its icon
        # behind as a ghost in the notification area, answering nothing and showing the last known state for ever.
        <#
            QUITTING THE CLIENT APP QUITS THE CLIENT APP -- NOT THE SERVER.

            "Quitter" used to stop the server. That was defensible when each session had its own; with a server
            shared by the machine, quitting from one account cuts it off for ALL THE OTHERS. Observed on 29/08:
            Famille's client app exits, the server is killed, fhaza's client app restarts it, and an elevation is
            asked for on the way -- for somebody who only wanted to close an icon.

            The server is a service: it lives its own life. To stop it or restart it there is the menu entry that
            restarts the server, which says so.
        #>


        $quitApp = {
            param($origine)
            TLog ("arret de l'app cliente (" + $origine + ") -- le serveur reste en marche")
            try { $icon.Visible = $false; $icon.Dispose() } catch { }
            try { Remove-Item -LiteralPath $heartbeat -Force -ErrorAction SilentlyContinue } catch { }
            [System.Windows.Forms.Application]::Exit()
        }
        <#
            RESTARTING THE APPLICATION RESTARTS THE APPLICATION.

            This function used to kill the server too, "so that it comes back with the new code". But the server
            PRECEDES the client app: with the machine task it starts before a session is even open. A program
            started afterwards does not close the one that was waiting for it -- and cutting it off from one
            account cuts it off for all the others.

            The server restarts ITSELF, with its own rights, through the menu entry that says so. Two distinct
            gestures for two distinct things.
        #>

        $relaunch = {
            # .NET's ArgumentList quotes each value itself: it gets the bare path (D116).
            try { [void](& $launchHidden $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File', $clientPath)) } catch { }
            try { $icon.Visible = $false; $icon.Dispose() } catch { }
            [System.Windows.Forms.Application]::Exit()
        }
        # The path to the DEFAULT browser's executable, read from the user's http association. It is the only
        # browser we know works on this machine -- so it is tried first.
        $defaultBrowser = {
            try {
                $key = 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
                $progId = (Get-ItemProperty -Path $key -ErrorAction Stop).ProgId
                if (-not $progId) { return $null }
                $cmd = (Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command" -ErrorAction Stop).'(default)'
                if ($cmd -match '"([^"]+\.exe)"') { return $Matches[1] }
                if ($cmd -match '^\s*(\S+\.exe)')  { return $Matches[1] }
            } catch { }
            return $null
        }

        # Opens the dedicated window (a browser in --app mode).
        #
        # WHY WE CHECK INSTEAD OF TRUSTING Start-Process
        # The old version took the FIRST browser found on disk, Edge then Chrome. On this machine Edge is present
        # but DOES NOT START: the process exits in under a second, with no window and no error. Start-Process
        # therefore handed control back without throwing and the log wrote "openApp ok" -- a lie, for four reports
        # running. A double click did nothing.
        #
        # Two corrections: we try the DEFAULT browser first (the one that works, by definition, since opening
        # Vigie in the browser did work), and above all we OBSERVE the result before declaring it. A candidate that dies
        # moves on to the next; if none holds, we open an ordinary tab rather than nothing.


        $openApp = {
            # -Sur: what the panel must show on opening ('recap' for the last session's recap). Without it, it opens
            # as usual: the parameter adds nothing for those who do not pass it.
            param([string]$On)
            TLog ("openApp demande" + $(if ($On) { " (sur $On)" } else { '' }))


            # ALREADY OPEN? We bring it to the front instead of opening a second one.
            # The suffix is the one the front end lays down (document.title = "<machine> - Vigie").
            $existante = [VigieNative.Win]::FindBySuffix(' — Vigie')
            if ($existante -ne [System.IntPtr]::Zero) {
                if ([VigieNative.Win]::Focus($existante)) {
                    TLog "openApp : fenetre deja ouverte, ramenee au premier plan"
                    return
                }
                TLog "openApp : fenetre trouvee mais impossible a activer - on en ouvre une"
            }

            <#
                THE DEDICATED WINDOW GOES THROUGH THE SAME DOOR AS THE BROWSER.

                Two roads opened the panel: the menu entry that opens it in the browser, which asked for an
                opening address, and the DOUBLE CLICK, which opened the bare address. So the second did not
                identify itself: on one session, on 01/09, the window opened on the page saying it is tied to no account, the
                panel now refusing a window without a session.

                It is here and not further up: a window already open is brought to the front, and the opening
                address serves ONCE only -- asking for it in order not to use it wastes it.
            #>


            $signInUrl = $null
            foreach ($attempt in 1..2) {
                try { $signInUrl = Get-OpenUrl -BaseUrl $url -TimeoutSec (5 * $attempt) -Backend $backend } catch { }
                if ($signInUrl) { break }
                Start-Sleep -Milliseconds 700
            }
            if (-not $signInUrl) {
                TLog "openApp : pas d'adresse d'ouverture, on n'ouvre pas"
                & $dire -Subject (Get-Label 'client.bulle-identite-titre') `
                        -Body (Get-Label 'client.bulle-identite-texte') -Icon 'Warning' -Duration 8000
                return
            }
            $url = $signInUrl
            # THE PANEL OPENS ON WHAT IT IS ASKED FOR: the page reads this parameter and opens the right window.
            if ($On) { $url += $(if ($url -like '*`?*') { '&' } else { '?' }) + 'show=' + [uri]::EscapeDataString($On) }

            # The --app mode exists on Chromium browsers only.
            $chromium = @('chrome', 'msedge', 'brave', 'vivaldi', 'opera')
            $candidats = New-Object System.Collections.Generic.List[string]
            $parDefaut = & $defaultBrowser
            if ($parDefaut -and (Test-Path -LiteralPath $parDefaut) -and
                ($chromium -contains [IO.Path]::GetFileNameWithoutExtension($parDefaut).ToLower())) {
                $candidats.Add($parDefaut)
            }
            $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ }
            $rel   = @('Google\Chrome\Application\chrome.exe','Microsoft\Edge\Application\msedge.exe')
            foreach ($base in $bases) {
                foreach ($rp in $rel) {
                    $c = Join-Path $base $rp
                    if ((Test-Path -LiteralPath $c) -and -not $candidats.Contains($c)) { $candidats.Add($c) }
                }
            }

            foreach ($exe in $candidats) {
                $procName = [IO.Path]::GetFileNameWithoutExtension($exe)
                $before = @(Get-Process -Name $procName -ErrorAction SilentlyContinue).Count
                try {
                    $p = Start-ChildProcess -FilePath $exe -Arguments @("--app=$url", '--window-size=1240,840') `
                                            -Options @{ PassThru = $true }
                } catch {
                    TLog ("openApp : " + $exe + " refuse (" + $_.Exception.Message + ")")
                    continue
                }
                Start-Sleep -Milliseconds 1500
                # Two ways of succeeding: our process holds, OR it handed over to an instance already running -- in
                # which case it exits quickly but the browser has gained processes. Testing HasExited alone would
                # open two windows.
                $after = @(Get-Process -Name $procName -ErrorAction SilentlyContinue).Count
                if ((-not $p.HasExited) -or ($after -gt $before)) {
                    TLog ("openApp OK (fenetre dediee) : " + $exe)
                    return
                }
                TLog ("openApp : " + $exe + " sort aussitot sans fenetre - candidat suivant")
            }

            TLog "openApp : aucun navigateur Chromium exploitable - repli onglet normal"
            try { Start-Process $url; TLog "openApp OK (onglet normal)" }
            catch { TLog ("openApp ECHEC : " + $_.Exception.Message) }
        }
        $openUrl     = { param($u) try { Start-Process $u } catch { TLog ("ouverture KO (" + $u + ") : " + $_.Exception.Message) } }

        <#
            OPENING THE PANEL WHILE SAYING WHO WE ARE.

            The client app is the only program able to read ITS OWN account's secret. It presents it to the server,
            receives a single-use ticket, and opens the page with that ticket. The server exchanges it for a session
            cookie: the page then knows which account it comes from, without any secret having travelled through
            the URL or staying readable in the JavaScript.

            IF ANYTHING AT ALL FAILS, WE OPEN THE PAGE ANYWAY, without a ticket. Vigie stays usable as before; what
            is missing is the identification of the account, not the application. Refusing to open the panel
            because the identification failed would be a regression for no gain.
        #>


        $openBrowser = {
            <#
                WITHOUT IDENTIFICATION, WE DO NOT OPEN A PAGE THAT REFUSES.

                The panel served to a window without a session is now a refusal page. Opening the bare address when
                the identification had failed therefore amounted to walking the user into a wall: on 31/08 on the
                Famille account, the icon was green and the page said "aucun compte".

                We ask once more, with a wider timeout -- the server may be busy recomputing -- and if we still get
                nothing, we SAY SO instead of opening. One single implementation of the request: Get-OpenUrl.
            #>


            $target = $null
            foreach ($essai in 1..2) {
                try { $target = Get-OpenUrl -BaseUrl $url -TimeoutSec (5 * $essai) -Backend $backend } catch { }
                if ($target) { break }
                Start-Sleep -Milliseconds 700
            }
            if (-not $target) {
                TLog "adresse d'ouverture refusee : on n'ouvre pas"
                & $dire -Subject (Get-Label 'client.bulle-identite-titre') `
                        -Body (Get-Label 'client.bulle-identite-texte') -Icon 'Warning' -Duration 8000
                return
            }
            TLog "adresse d'ouverture obtenue"
            & $openUrl $target
        }
        $openRepo    = { & $openUrl $repoUrl }

        # THE ACCOUNT IS IN THE TOOLTIP. There is one icon per account that is open, and they all said "Vigie -
        # <state>": there was no way of knowing which one belongs to whom. On a family machine that is the first
        # question one asks, and it is indispensable for debugging one account from another's session.

        $clientAccount = (Get-ProcessAccount)
        <#
            THE BUBBLES MUST SAY "VIGIE", NOT "POWERSHELL".

            On Windows 10 and later, a NotifyIcon balloon is turned into a real toast, and
            the name on it is NOT the balloon's title: it is the identity of the process
            that raised it. Ours is pwsh.exe, so the user reads "PowerShell" and learns
            nothing (reported on 07/09).

            An identity is DECLARED, then WORN. Declared once for the whole machine by the
            installation (HKLM\SOFTWARE\Classes\AppUserModelId\Sowapps.Vigie, carrying the
            display name and the delivered icon), and worn here by the process -- before
            the icon exists, because the identity of a notification is fixed when its
            source is created, not when it is sent.

            MEASURED: SetCurrentProcessExplicitAppUserModelID returns 0 and the identity
            reads back. What the toast then DISPLAYS is only verifiable by looking at one,
            and that is the user's eyes -- see subject S11.
        #>
        try {
            $null = [VigieNative.Aumid]::SetCurrentProcessExplicitAppUserModelID((Get-VigieToastIdentity))
        } catch { TLog ("identite des notifications non posee : " + $_.Exception.Message) }
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Text = (Get-Label 'client.infobulle' $clientAccount)

        $setIcon = {
            param($status)
            # The icon is ALWAYS the delivered .ico file (assets/), generated by assets/generate-icons.ps1. It is
            # the ONLY rendering of the brand.
            $name = switch ($status) { 'ok' { 'ok' } 'warn' { 'warn' } 'error' { 'error' } default { 'error' } }
            $icoPath = Join-Path $clientRoot ('assets\' + $name + '.ico')
            if (Test-Path $icoPath) {
                try {
                    $newIco = New-Object System.Drawing.Icon($icoPath)
                    $icon.Icon = $newIco
                    if ($script:iconObj) { try { $script:iconObj.Dispose() } catch { } }
                    $script:iconObj = $newIco
                    return
                } catch {
                    # Never silent: an icon that changes for no reason cannot be diagnosed if the failure is not
                    # traced.
                    TLog ("icone : lecture KO (" + $icoPath + ") : " + $_.Exception.Message)
                }
            } else {
                TLog ("icone : fichier absent : " + $icoPath)
            }

            # --- Degraded mode ------------------------------------------------------
            # Deliberately a plain DISC, not an imitation of the brand.
            # The old fallback redrew the gauge in GDI+: two drawings of the same brand, which HAD ENDED UP
            # DIVERGING (a needle starting from the centre, no graduations, different thicknesses and track colour).
            # As the read failure was swallowed, the client app could show ANOTHER brand without anybody seeing it.
            # A plain disc fools nobody: it signals that the assets are missing, while keeping the state
            # information (the colour).

            $c = switch ($status) {
                'ok'    { [System.Drawing.Color]::FromArgb(63,185,80) }
                'warn'  { [System.Drawing.Color]::FromArgb(210,153,34) }
                'error' { [System.Drawing.Color]::FromArgb(248,81,73) }
                default { [System.Drawing.Color]::FromArgb(248,81,73) }
            }
            $s = 32.0
            $bmp = New-Object System.Drawing.Bitmap ([int]$s), ([int]$s)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            $pad = $s * 0.12
            $brush = New-Object System.Drawing.SolidBrush $c
            $g.FillEllipse($brush, [single]$pad, [single]$pad, [single]($s - 2*$pad), [single]($s - 2*$pad))
            $brush.Dispose()
            $g.Dispose()
            $h = $bmp.GetHicon(); $bmp.Dispose()
            $icon.Icon = [System.Drawing.Icon]::FromHandle($h)
            if ($iconHandle -ne [System.IntPtr]::Zero) { [void][VigieNative.Ico]::DestroyIcon($iconHandle) }
            $script:iconHandle = $h
        }
        & $setIcon 'warn'
        $icon.Visible = $true
        TLog "icone visible"

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $menu.ShowImageMargin = $false
        try { $menu.Font = New-Object System.Drawing.Font('Segoe UI', 9.5) } catch { }
        # --- Win11 style: native rounded corners (DWM), a rounded inset hover ----
        # Any failure falls back silently on the default rendering: the menu stays usable even if the style does
        # not apply.
        try {
            $csrc = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

// Palette du menu. Une seule definition des couleurs, partagee par la table et le rendu.
// La reference demandee est le menu de WINDOWS 11 : gris NEUTRE, pas le bleute de la
// palette Vigie. Le bleu #2b3038 livre jusqu'ici venait de mes valeurs par defaut, qui
// avaient pris le pas sur la reference.
public static class VigieMenuPalette {
  public static readonly Color Surface   = Color.FromArgb(44, 44, 44);   // #2c2c2c
  public static readonly Color Hover     = Color.FromArgb(61, 61, 61);   // #3d3d3d
  public static readonly Color Border    = Color.FromArgb(69, 69, 69);   // #454545
  public static readonly Color Separator = Color.FromArgb(64, 64, 64);   // #404040
  // Survol PLEINE LARGEUR : bande edge-to-edge, sans marge ni arrondi. C'est le rendu
  // demande. Les valeurs restent nommees pour qu'un survol encarte redevienne un simple
  // changement de constantes, sans toucher au trace.
  public const int CornerRadius = 0;   // arrondi du RECTANGLE DE SURVOL
  public const int MenuRadius   = 8;   // arrondi des COINS DU MENU (decoupe de region)
  public const int InsetX       = 0;   // marge laterale du rectangle de survol
  public const int InsetY       = 0;
  // Retrait du TEXTE dans l'item. Doit etre superieur a InsetX, sinon le texte touche
  // le bord du rectangle de survol. Win11 laisse respirer autour du libelle.
  public const int TextPadX     = 14;
  public const int TextPadY     = 7;   // ne sert QUE a fixer la hauteur de ligne
  // Libelles non cliquables (ligne d'etat) : gris attenue, lisible sur fond sombre.
  public static readonly Color TextDisabled = Color.FromArgb(154, 160, 166);
  // Couleur du LIBELLE actif. Definie ICI et nulle part ailleurs (D15) : elle etait
  // ecrite en dur a deux endroits du script, ce qui obligeait a la recopier dans
  // l Atelier -- qui la relit desormais (palette.php).
  public static readonly Color Text = Color.FromArgb(230, 237, 243);
}

public class VigieDarkColors : ProfessionalColorTable {
  public override Color ToolStripDropDownBackground { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientBegin    { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientMiddle   { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientEnd      { get { return VigieMenuPalette.Surface; } }
  public override Color MenuBorder                  { get { return VigieMenuPalette.Border; } }
  public override Color MenuItemBorder              { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelected            { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelectedGradientBegin { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelectedGradientEnd   { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemPressedGradientBegin  { get { return VigieMenuPalette.Surface; } }
  public override Color MenuItemPressedGradientEnd    { get { return VigieMenuPalette.Surface; } }
  public override Color SeparatorDark               { get { return VigieMenuPalette.Separator; } }
  public override Color SeparatorLight              { get { return VigieMenuPalette.Separator; } }
}

public class VigieMenuRenderer : ToolStripProfessionalRenderer {
  public VigieMenuRenderer() : base(new VigieDarkColors()) { this.RoundedEdges = false; }

  static GraphicsPath RoundedRect(Rectangle r, int radius) {
    int d = radius * 2;
    GraphicsPath p = new GraphicsPath();
    if (d <= 0 || r.Width <= d || r.Height <= d) { p.AddRectangle(r); return p; }
    p.AddArc(r.X, r.Y, d, d, 180, 90);
    p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
    p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
    p.CloseFigure();
    return p;
  }

  // Survol : rectangle ENCARTE et arrondi (Win11), et non une bande pleine largeur.
  protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
    if (!e.Item.Selected || !e.Item.Enabled) return;

    // L'item peut etre plus LARGE que la zone visible du menu : ses derniers pixels
    // passent sous la bordure. Un rectangle calcule sur e.Item.Size sortait donc a
    // droite et s'y faisait rogner a angle droit -- arrondi a gauche, coupe net a
    // droite. On borne la largeur a ce qui est reellement visible.
    int visible = e.ToolStrip.ClientSize.Width - e.Item.Bounds.Left;
    int largeur = Math.Min(e.Item.Size.Width, visible);

    Rectangle r = new Rectangle(
      VigieMenuPalette.InsetX,
      VigieMenuPalette.InsetY,
      largeur - VigieMenuPalette.InsetX * 2,
      e.Item.Size.Height - VigieMenuPalette.InsetY * 2);
    if (r.Width <= 0 || r.Height <= 0) return;
    SmoothingMode old = e.Graphics.SmoothingMode;
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    using (GraphicsPath path = RoundedRect(r, VigieMenuPalette.CornerRadius))
    using (SolidBrush brush = new SolidBrush(VigieMenuPalette.Hover))
      e.Graphics.FillPath(brush, path);
    e.Graphics.SmoothingMode = old;
  }

  // Placement du TEXTE, explicite.
  //
  // Le moteur de disposition des menus deroulants calcule lui-meme la boite des items :
  // regler Padding y produit un ContentRectangle incoherent (mesure : {X=-12, Y=-5,
  // Height=44} pour un item de 34 px). S'appuyer dessus revenait a se battre contre le
  // moteur -- le texte n'etait jamais centre verticalement, quatre tentatives durant.
  //
  // On ne subit plus la mise en page : on donne le rectangle de texte et on demande un
  // centrage vertical. Meme resultat pour TOUS les types d'items, y compris ceux que le
  // moteur decale (un ToolStripLabel est pose 8 px plus a droite qu'un ToolStripMenuItem).
  protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
    Size s = e.Item.Size;
    e.TextRectangle = new Rectangle(
        VigieMenuPalette.TextPadX, 0,
        Math.Max(0, s.Width - VigieMenuPalette.TextPadX * 2), s.Height);
    e.TextFormat = TextFormatFlags.Left | TextFormatFlags.VerticalCenter
                 | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix;
    // Un item desactive sert de libelle (ligne d'etat) : le gris systeme serait
    // illisible sur fond sombre.
    if (!e.Item.Enabled) e.TextColor = VigieMenuPalette.TextDisabled;
    base.OnRenderItemText(e);
  }

  // Separateur : trait fin encarte, aligne sur les marges du survol.
  protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
    Rectangle b = new Rectangle(Point.Empty, e.Item.Size);
    int y = b.Top + b.Height / 2;
    // Le separateur s'aligne sur le TEXTE, pas sur le survol : avec un survol pleine
    // largeur, un trait pleine largeur decouperait le menu en tranches.
    using (Pen pen = new Pen(VigieMenuPalette.Separator))
      e.Graphics.DrawLine(pen, b.Left + VigieMenuPalette.TextPadX, y, b.Right - VigieMenuPalette.TextPadX, y);
  }

  // Fond uni : pas de degrade, pas de bande de marge d'icone.
  protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
    using (SolidBrush brush = new SolidBrush(VigieMenuPalette.Surface))
      e.Graphics.FillRectangle(brush, e.AffectedBounds);
  }

  // Bordure geree par DWM (coins arrondis natifs) : ne rien dessiner ici.
  protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) { }
}
'@
            # System.Drawing is split: Color comes from System.Drawing.Primitives, GraphicsPath and Graphics from
            # System.Drawing.Common. BOTH are needed.
            $refs = @(
                [System.Windows.Forms.ToolStrip].Assembly.Location,
                [System.Drawing.Color].Assembly.Location,
                [System.Drawing.Drawing2D.GraphicsPath].Assembly.Location
            ) | Sort-Object -Unique
            Add-Type -TypeDefinition $csrc -ReferencedAssemblies $refs -ErrorAction Stop
            $menu.Renderer  = New-Object VigieMenuRenderer
            $menu.BackColor = [VigieMenuPalette]::Surface
            $menu.ForeColor = [VigieMenuPalette]::Text
            $menu.Padding   = New-Object System.Windows.Forms.Padding(0, 5, 0, 5)
            TLog "style menu Win11 applique"
        } catch { TLog ("style menu KO (fallback): " + $_.Exception.Message) }

        # NATIVE rounded corners through DWM (Windows 11). Applied at every opening: idempotent, and the menu's
        # window may recreate its handle between two displays.
        # Set-WindowChrome comes from lib/common.ps1: the P/Invoke signature is declared in one place only, shared
        # with the consent window.
        # DWM first (a native shadow and antialiasing when it agrees to apply), then a region cut which, for its
        # part, ALWAYS rounds: without it the menu keeps square corners, DWM not rounding windows that have no
        # standard frame.
        $roundCorners = {
            try {
                Set-WindowChrome  -Handle $menu.Handle -RoundedCorners -BorderColor 0x00564C44
                Set-RoundedRegion -Control $menu -Radius ([VigieMenuPalette]::MenuRadius)
                # We trace the RESULT, not the intention: "region applied" proves nothing, only the fact that a
                # corner falls outside the region proves the rounding took.
                $horsCoin = if ($menu.Region) {
                    -not $menu.Region.IsVisible((New-Object System.Drawing.Point(0,0)))
                } else { $false }
                TLog ("menu ouvert : {0}x{1}, region={2}, coin decoupe={3}" -f `
                      $menu.Width, $menu.Height, [bool]$menu.Region, $horsCoin)
            } catch {
                TLog ("arrondi du menu KO : " + $_.Exception.Message)
            }
        }
        $menu.add_Opened({ & $roundCorners })

        $lite = [VigieMenuPalette]::Text
        $miShow = $menu.Items.Add('Afficher l''application', $null, [System.EventHandler]{ & $openApp })
        try { $miShow.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold) } catch { }
        [void]$menu.Items.Add('Ouvrir dans le navigateur', $null, [System.EventHandler]{ & $openBrowser })
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        # The state line: a DISABLED ToolStripMenuItem, not a ToolStripLabel. The layout engine places a Label 8 px
        # further right than an item, hence a visible offset. The same kind of item means the same geometry, with
        # no correction to maintain.
        # Its dimmed colour is applied by the renderer (TextDisabled), the system grey being unreadable on a dark
        # background.
        $miInfo = New-Object System.Windows.Forms.ToolStripMenuItem('État : démarrage…')
        $miInfo.Enabled = $false
        [void]$menu.Items.Add($miInfo)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add('Relancer l''application', $null, [System.EventHandler]$relaunch)
        <#
            THREE WAYS OUT WHEN AN OPERATION IS RUNNING.

            Cutting a deployment in two leaves an installation half done. We do not decide in the person's place:
            we tell them what is running, and leave them the choice -- do nothing, wait for the end, or force it.

            "Attendre" does not watch for ever: after ten minutes we give up and say so. A silent, endless wait is
            a deadlock in disguise.
        #>

        $restartServer = {
            $r = & $askServerRestart $false $false

            if ("$r".StartsWith('busy:')) {
                $operation = "$r".Substring(5)
                $choix = & $askWindow (Get-Label 'client.relance-operation-titre') `
                                      (Get-Label 'client.relance-operation-texte' $operation) `
                                      (Get-Label 'client.relance-forcer') `
                                      (Get-Label 'client.relance-attendre') `
                                      (Get-Label 'client.relance-rien')
                if ($choix -eq 0) { $r = & $askServerRestart $true $false }        # force it
                elseif ($choix -eq 4) {
                    # IT IS THE SERVER THAT WAITS. It knows what is running, and its relauncher is detached: making
                    # it hold the question saves the client app a polling loop and an arbitrary delay.
                    TLog "relance : le serveur attendra la fin de l'operation"
                    $r = & $askServerRestart $false $true
                }
                else { return }                                            # do nothing
            }

            if ($r -eq 'ok') {
                TLog "relance demandee au serveur (il s'en charge)"
                $state.StartTicks = [datetime]::UtcNow.Ticks
                $state.Starting   = $true
                & $setIcon 'warn'; $state.Drawn = 'warn'
                $icon.Text = (Get-Label 'client.infobulle-etat' $clientAccount 'Démarrage…')
                $miInfo.Text = 'État : Démarrage…'
                return
            }

            # THE SERVER DOES NOT ANSWER: there is nobody left to restart itself. This is the only case where we
            # speak of elevation, and we SAY SO before asking for it.
            $suite = & $askWindow (Get-Label 'client.relance-mort-titre') `
                                  (Get-Label 'client.relance-mort-texte') `
                                  (Get-Label 'client.relance-mort-ok') '' `
                                  (Get-Label 'client.relance-rien')
            if ($suite -ne 0) { return }

            # THE ONLY PLACE WHERE THE CLIENT APP TOUCHES THE SERVER, and it is not the client app that decides:
            # somebody clicked, read that the server no longer answers, and granted the elevation. The process
            # aimed at is either dead -- there is nothing to stop -- or stuck, and stopping it is then the only
            # cure.
            #
            # Everywhere else the rule has no exception: the client app never closes the server. The server
            # PRECEDES it -- with the machine task it starts before a session exists -- and it is shared by every
            # account.
            $state.ElevationAsked = $false
            & $stopServer
            Start-Sleep -Milliseconds 600
            & $startServer
        }

        [void]$menu.Items.Add('Redémarrer le serveur', $null, [System.EventHandler]{
            & $restartServer
            # Immediate visual feedback: without it the icon keeps its state until the next poll (8 s) and the user
            # sees a red that has no reason to be there.
            & $setIcon 'warn'; $state.Drawn = 'warn'
            $icon.Text = (Get-Label 'client.infobulle-etat' $clientAccount 'Démarrage…'); $miInfo.Text = 'État : Démarrage…'
        })
        # The SERVER's logs: that is what one wants to see in order to diagnose.
        [void]$menu.Items.Add('Ouvrir les journaux', $null, [System.EventHandler]{ Start-Process (Get-LogDir -Backend $backend) })
        <#
            WINDOWS NOTIFICATIONS, FROM HERE.

            When a notification runs wild, the first reflex is to switch them off in Windows -- which is what had to
            be done on the Famille account on 31/08. Switching them back on then means finding "Parametres >
            Systeme > Notifications" again in THAT account's SESSION: one searches, and then forgets about it.

            So the shortcut is there, beside the state it governs. It opens Windows's own page, it changes nothing
            itself: that setting belongs to the person, and Vigie has no business deciding whether they want to be
            disturbed.
        #>

        [void]$menu.Items.Add((Get-Label 'client.menu-notifications-windows'), $null, [System.EventHandler]{
            try { Start-Process 'ms-settings:notifications' }
            catch { TLog ("ouverture des notifications Windows impossible : " + $_.Exception.Message) }
        })
        <#
            "A PROPOS" SHOWS, IT DOES NOT LEAVE.

            This menu used to open the GitHub repository directly: one left Vigie for a browser without having
            learned anything about it. Yet that is exactly where one goes to look for what one does not know --
            which version is running, under which account, from which folder. The repository link has its place
            there, but as ONE of the pieces of information, not as the destination.

            The window answers the questions one asks in front of an incident: which version, which account, which
            location, which server. The link opens from the window, if one wants it.
        #>


        $showAbout = {
            try {
                $version = try { Get-AppVersion -Backend $backend } catch { 'inconnue' }
                $srv = if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
                           (Get-Label 'client.apropos-serveur-en-ligne' $cfg.Port)
                       } else { (Get-Label 'client.apropos-serveur-hors-ligne') }
                $lines = @(
                    (Get-Label 'client.apropos-version'     $version),
                    (Get-Label 'client.apropos-compte'      $clientAccount),
                    (Get-Label 'client.apropos-application' (Split-Path $backend -Parent)),
                    $srv,
                    '',
                    (Get-Label 'client.apropos-depot'       $repoUrl),
                    '',
                    (Get-Label 'client.apropos-ouvrir-depot')
                )
                $response = [System.Windows.Forms.MessageBox]::Show(
                    ($lines -join [Environment]::NewLine),
                    (Get-Label 'client.apropos-titre'),
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($response -eq [System.Windows.Forms.DialogResult]::Yes) { & $openRepo }
            } catch { TLog ("a propos KO : " + $_.Exception.Message) }
        }
        $miAbout = $menu.Items.Add('À propos de Vigie', $null, [System.EventHandler]$showAbout)
        $miAbout.ToolTipText = $repoUrl
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add('Quitter', $null, [System.EventHandler]{ & $quitApp 'menu' })

        # The colour and the LINE HEIGHT, in one place for every item.
        # The vertical padding serves only to fix the height: the POSITION of the text is imposed by the renderer
        # (OnRenderItemText), because the layout engine of drop-down menus makes Padding useless for placing the
        # content.
        # No horizontal padding here: it would duplicate the renderer's TextPadX.
        $itemPad = New-Object System.Windows.Forms.Padding(0, [VigieMenuPalette]::TextPadY, 0, [VigieMenuPalette]::TextPadY)
        foreach ($it in $menu.Items) {
            if ($it -is [System.Windows.Forms.ToolStripMenuItem]) {
                $it.ForeColor = $lite
                $it.Padding   = $itemPad
            }
        }
        $icon.ContextMenuStrip = $menu
        # The double click is traced BEFORE acting: if nothing happens, the log says whether the click even reached
        # the application. Without that, there is no telling a handler that was never called from an opening that
        # fails.
        $icon.add_MouseDoubleClick({ TLog "double-clic sur l'icone"; & $openApp })

        & $startServer
        TLog "serveur ok"

        <#
            EVERY BALLOON GOES THROUGH HERE, AND THEY HAVE A BRAKE.

            On the Famille account, on 31/08: a notification that reopened as soon as it was closed, endlessly,
            until it hid the icons of the notification area. Vigie had to be switched off for that account and
            PowerShell's notifications forbidden in Windows.

            The cause is not the balloon, it is what it announces: when the server alternates between unreachable
            and starting, the cards flip at every round of surveillance -- every eight seconds -- and every flip
            asked for its balloon. A notification that repeats itself no longer informs, it blocks.

            Three rules, here and nowhere else:
              - NEVER THE SAME MESSAGE TWICE within the quarter hour;
              - at least a minute between two balloons, whatever their subject;
              - if the display fails, we do not insist -- we note it and move on.
        #>


        $dire = {
            # -Launch: what a click on the notification must open (a vigie:// address). Without it, the notification
            # informs without offering anything -- which most of them still do.
            param([string]$Subject, [string]$Body, [string]$Icon = 'Info', [int]$Duration = 6000, [string]$Key = '', [string]$Launch = '')
            $maintenant = [datetime]::UtcNow
            $cle = "$Subject|$Body"
            if (-not $state.Bulles) { $state.Bulles = @{} }
            $vue = $state.Bulles[$cle]
            if ($vue -and ($maintenant - [datetime]$vue).TotalMinutes -lt 15) { return }
            if ($state.DerniereBulle -and ($maintenant - [datetime]$state.DerniereBulle).TotalSeconds -lt 60) { return }
            # WHICH TOOL SHOWS IT IS NOT DECIDED HERE (targeting/notifications.md).
            # We describe the event; the door picks -- and its last rank, the balloon,
            # is always available.
            $level = switch ($Icon) { 'Error' { 'error' } 'Warning' { 'warn' } default { 'ok' } }
            try {
                $outil = Show-VigieNotification `
                    -Notification @{ Subject = $Subject; Body = $Body; State = $level; Duration = $Duration; Key = $Key; Launch = $Launch } `
                    -Context @{ ClientRoot = $clientRoot; Aumid = (Get-VigieToastIdentity); Icon = $icon }
                if ($outil) { TLog ("notification montree par " + $outil) }
                else { TLog "aucun outil n'a su montrer la notification" }
                $state.Bulles[$cle] = $maintenant
                $state.DerniereBulle = $maintenant
            } catch {
                # WE DO NOT INSIST. A balloon we do not know how to show is noted and forgotten: retrying at every
                # round is exactly what blocked Famille's screen.
                $state.Bulles[$cle] = $maintenant
                $state.DerniereBulle = $maintenant
                TLog ("bulle refusee par Windows : " + $_.Exception.Message)
            }
        }

        $poll = {
            <#
                AN INSTALLATION UNDER WAY IS NOT A BREAKDOWN.

                During an update the server stops, the cards fall into error then come back: the client app saw
                STATE CHANGES there and put out a Windows balloon for each one, plus a "the server is dead", plus a
                restart attempt competing with the installation. Yet that is the NORMAL course of the gesture the
                user has just asked for.

                The installation lock lives in %ProgramData%, readable by every account: that is the signal, and no
                other is needed.
            #>

            $installEnCours = $false
            try { $installEnCours = [bool](Get-InstallLockHolder) } catch { }
            <#
                THE SILENCE LASTS LONGER THAN THE LOCK.

                The lock falls as soon as the installation has finished laying down the files -- but the server
                restarts AFTERWARDS, through its task, and takes a good minute to answer. In between, the port
                opens before the requests go through: exactly the signature of a "stuck server", which therefore
                put out its balloon at the end of every update (observed on 31/08).

                So we keep silent for two minutes after the last time we saw the lock. This is not a timeout: the
                client app goes on watching and displaying, it simply does not DISTURB.
            #>


            if ($installEnCours) { $state.QuietTicks = [datetime]::UtcNow.AddMinutes(2).Ticks }
            $silence = $installEnCours
            try { if ($state.QuietTicks -and [datetime]::UtcNow.Ticks -lt [long]$state.QuietTicks) { $silence = $true } } catch { }
            <#
                AND NOBODY IN FRONT OF THE SCREEN IS THE SAME SILENCE.

                A notification interrupts a person. No person, no interruption: the
                reference is updated as usual, the balloon does not come out -- so coming
                back to the session announces NOTHING of what moved while nobody was there.
                This is exactly the treatment an installation already gets.

                READ AT EVERY PASS, never once and for all: the active account changes
                without warning, and a flag set at startup would lie from the very first
                user switch.
            #>
            $state.Present = $true
            try { $state.Present = [VigieNative.Wts]::SomeoneIsWatching($mySession) } catch { }
            if (-not $state.Present) { $silence = $true }

            # THE MEASURED REASONS, appended to the bubble that says the server does not answer (CORE-CLIENT): memory, ports,
            # what Windows logged, Vigie's own processes. Read only when the bubble goes out, never at every pass.
            function Format-TroubleReasons {
                $found = @()
                try { $found = @(Get-ServerTroubleReasons -Port ([int]$cfg.Port) -Backend $backend) } catch { }
                if (-not $found.Count) { return '' }
                TLog ("raisons mesurees : " + ($found -join ' | '))
                return ([Environment]::NewLine + (Get-Label 'client.raison-titre') + [Environment]::NewLine + ($found -join [Environment]::NewLine))
            }
            try {
                [void](Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5 -ErrorAction Stop)
                $state.EverUp   = $true
                $state.Starting = $false
                $state.HealthKo = 0
                $state.SaidDead = $false
                $app = 'ok'; $lbl = 'En marche'
            } catch {
                # A STUCK server: the port answers (TCP) but no request goes through any more (observed on 24/08: a
                # bug in the Pode listener, everything ended in 408). In that case restarting is the only cure --
                # and nobody but the client app can do it, since the open port hides the breakdown. Three
                # consecutive failures (~24 s) outside a start => we kill the listener and set off again.
                if (-not $state.Starting -and (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port)) {
                    $state.HealthKo = [int]$state.HealthKo + 1
                    # A STUCK SERVER: the port answers, the requests do not. The client app OBSERVES it and says so
                    # -- it no longer kills it. Killing the shared server from a client app means cutting it off
                    # for every account, and the client app comes after it. The cure belongs to the server task,
                    # which restarts it, or to somebody clicking the menu entry that restarts the server.
                    if ($state.HealthKo -eq 3 -and -not $silence) {
                        TLog "serveur coince (port ouvert, health muet x3) : signale, pas tue"
                        try {
                            & $dire -Subject (Get-Label 'client.bulle-coince-titre') `
                                    -Body ((Get-Label 'client.bulle-coince-texte') + (Format-TroubleReasons)) `
                                    -Icon 'Warning' -Duration 8000
                        } catch { }
                    }
                }
                $elapsed = ([datetime]::UtcNow.Ticks - $state.StartTicks) / 1e7
                if ($state.Starting) {
                    # IS THE PROCESS STILL THERE? That is the only proof worth having: as long as it lives the
                    # start carries on, however long it takes. We know that process only if WE are the ones who
                    # started it -- a client app that adopts a server already in place has nothing to watch, and
                    # falls back on a delay, deliberately a wide one.
                    $known = $false
                    $alive = $false
                    try {
                        if ($state.Proc) { $known = $true; $alive = (-not $state.Proc.HasExited) }
                    } catch { $known = $false }

                    if ($known -and $alive -and $elapsed -le $startupGrace) {
                        $app = 'warn';  $lbl = 'Démarrage…'
                    } elseif ($known -and -not $alive) {
                        # It has stopped: no need to wait for a delay to run out before saying so. That is even
                        # FASTER than the old behaviour.
                        $app = 'error'; $lbl = 'Le serveur s''est arrêté au démarrage'
                    } elseif (-not $known -and $elapsed -le $startupBlind) {
                        $app = 'warn';  $lbl = 'Démarrage…'
                    } else {
                        $app = 'error'; $lbl = 'Échec de démarrage'
                    }
                } elseif (-not (Test-IsElevated) -and $state.ElevationAsked) {
                    # The elevation was asked for and refused -- or not granted yet. Neither a breakdown nor a wait:
                    # we say so, and the menu entry that restarts the server asks again.
                    $app = 'warn'; $lbl = 'Serveur arrêté : relance à autoriser'
                } elseif ($silence) {
                    # The server is off BECAUSE WE ARE UPDATING IT. No balloon, no restart -- the installation will
                    # restart it itself, and two restarts crossing each other is exactly what we are avoiding.
                    $app = 'warn'; $lbl = 'Mise à jour en cours…'
                } else {
                    $app = 'error'; $lbl = 'Arrêtée / injoignable'
                    # A DEAD server (a closed port): the client app restarts it on its own. This is the counterpart
                    # of the "stuck" case above -- observed on 25/08 in the morning: the server killed, the client
                    # app alive, and nobody to start it again. startServer lays the window of tolerance down again,
                    # which naturally spaces the attempts out if the start fails in a loop.
                    if ($state.EverUp -and -not (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port)) {
                        # DEAD: there is nobody left to restart itself. We warn through a balloon -- it disappears
                        # on its own, demanding nothing -- and we attempt the restart. If the rights are missing,
                        # the icon stays orange and the menu entry that restarts the server stays there, on demand.
                        if (-not $state.SaidDead) {
                            $state.SaidDead = $true
                            TLog "serveur mort (port ferme)"
                            try {
                                & $dire -Subject (Get-Label 'client.bulle-mort-titre') `
                                        -Body ((Get-Label 'client.bulle-mort-texte') + (Format-TroubleReasons)) `
                                        -Icon 'Warning' -Duration 8000
                            } catch { }
                        }
                        & $startServer
                        $app = 'warn'; $lbl = 'Redémarrage…'
                    }
                }
            }
            $miInfo.Text = "État : $lbl"
            if ($app -ne $state.Drawn) { & $setIcon $app; $state.Drawn = $app; $icon.Text = (Get-Label 'client.infobulle-etat' $clientAccount $lbl); TLog "app=$app" }
            # The heartbeat: it is what lets a script know whether the client app is alive, without having to
            # inspect an elevated process.
            try {
                # UTF8 and not ASCII: the state carries accents, which ASCII replaces with question marks.
                Set-Content -LiteralPath $heartbeat -Encoding UTF8 -NoNewline `
                    -Value ("{0};{1};{2}" -f $PID, (Get-Date -Format 'o'), $lbl)
            } catch { }

            # --- Notifications when a MODULE flips (D54) -----------------------------
            # The icon stays the state of the APP; here we report the probe RESULTS.
            # We notify ONLY on a change (never a repeated reminder), and never on the first pass: at startup we
            # take the state as the reference, otherwise every launch would shower the user with everything that is
            # already known.


            try {
                <#
                    WE ASK THE SERVER APP FOR THE STATE, WE NO LONGER READ ITS FILE.

                    This block used to open "the server app's" state-cache.json -- that is, since the server runs
                    under a service account, a file sitting IN THAT ACCOUNT'S PROFILE. So the client app was
                    looking at a file nobody writes on its side: not one notification since 28/08, and nothing to
                    say so.

                    It goes through the API now, with its own session: it sees what the server sees, with its own
                    account's rights, without reading in somebody else's home. The answer is SERVED FROM THE CACHE
                    -- no recomputation is provoked.

                    Once a minute is enough: the icon, for its part, goes on following the server's health every
                    eight seconds.
                #>

                $mustRead = $false
                if (-not $state.NotifTicks) { $mustRead = $true }
                elseif (([datetime]::UtcNow.Ticks - [long]$state.NotifTicks) / 1e7 -ge 60) { $mustRead = $true }
                if ($mustRead) {
                    $state.NotifTicks = [datetime]::UtcNow.Ticks
                    if (-not $state.ApiSession) {
                        $state.ApiSession = Open-VigieSession -BaseUrl $url -Backend $backend
                    }
                    $received = $null
                    if ($state.ApiSession) {
                        try {
                            $received = Invoke-RestMethod -Uri ($url.TrimEnd('/') + '/api/v1/state') `
                                            -WebSession $state.ApiSession -TimeoutSec 30
                        } catch {
                            # The session is lost (the server restarted): we will open another at the next pass
                            # rather than insisting now.
                            $state.ApiSession = $null
                        }
                    }
                    $j = $null
                    if ($received) {
                        # The same shape as the cache file: one property per probe, carrying its module or modules.
                        $j = [pscustomobject]@{}
                        foreach ($m in @($received.modules)) {
                            if ($m -and $m.id) {
                                Add-Member -InputObject $j -NotePropertyName "$($m.id)" `
                                           -NotePropertyValue ([pscustomobject]@{ module = $m }) -Force
                            }
                        }
                    }
                }
                if ($j) {
                    # We watch the state of the FIELDS, not only of the cards: a notification is a NAMED event,
                    # declared by the module. A card title said nothing to anybody -- reported by the owner on
                    # 26/08.
                    $seen = @{}
                    foreach ($pr in $j.PSObject.Properties) {
                        foreach ($m in @($pr.Value.module)) {
                            if (-not $m -or -not $m.id) { continue }
                            $seen["$($m.id)"] = @{ status = "$($m.status)"; label = "$($m.label)" }
                            foreach ($c in @($m.fields)) {
                                if ($c -and $c.key) { $seen["$($m.id)/$($c.key)"] = @{ status = "$($c.status)"; label = "$($c.label)"; value = "$($c.value)"; reason = "$($c.reason)"; identity = "$($c.identity)" } }
                            }
                        }
                    }
                    <#
                        THE END OF A SESSION OPENS ITS RECAP.

                        The server app cannot open a window: it runs under the service account, with no screen.
                        The client app IS the session, so it opens it, and nothing else does.

                        The setting decides (Settings > Modules > Games, on by default): open it, or merely
                        offer it through a notification that opens it on a click. That notification goes through
                        the same door as the others, so it obeys the notification settings -- switched off, it
                        stays quiet.

                        IT BELONGS HERE, IN THE LOOP, and not in the branch of the first pass, where it was written
                        on 28/09. There, its condition -- a recap seen BEFORE, different from the one now -- could
                        never hold, since nothing has been seen yet on a first pass; and that branch is never
                        visited again. The code was delivered, read twice, and could not run once.
                    #>
                    <#
                        WHAT IS COMPARED IS THE IDENTITY OF THE SESSION, never the line that states it.

                        The line carries a wording that drifts: it names the end time one way on the day it happened
                        and another way afterwards. Comparing the lines, the first computation past midnight reads a
                        change where nothing happened -- on 05/10 the recap of a session ended the day before at 18:28
                        opened at 06:45, half a day late, at the next sign-in. The field now carries `identity` (the
                        end of the session); the value remains the fallback for a field that declares none.
                    #>
                    $recapNow = $null
                    try {
                        $f = $seen['gaming/last-session']
                        $recapNow = if ($f.identity) { "$($f.identity)" } else { "$($f.value)" }
                    } catch { }
                    $inGame = $false
                    try { $inGame = ($seen['gaming/game'] -and "$($seen['gaming/game'].value)" -notin @('Aucun', 'Surveillance indisponible')) } catch { }
                    if ($recapNow -and $state.RecapSeen -and $recapNow -ne $state.RecapSeen -and -not $silence -and $state.Present) {
                        $auto = $true
                        try { $auto = [bool](Get-ModuleSetting -Unit 'gaming' -Key 'OpenRecapAtEnd' -Backend $backend) } catch { }
                        if ($auto) {
                            TLog "fin de partie : ouverture du recapitulatif"
                            & $openApp 'recap'
                            Start-Sleep -Milliseconds 2500
                            $state.RecapWindow = [VigieNative.Win]::FindBySuffix(' — Vigie')
                            $state.RecapSeenAt = [datetime]::UtcNow.Ticks
                        } else {
                            $allowed = $true
                            try { $allowed = Test-NotificationAllowed -ModuleId 'gaming' -Key 'game-recap' -Settings (Get-NotificationSettings -Backend $backend) } catch { }
                            if ($allowed) { & $dire -Subject (Get-Label 'client.bulle-partie-titre') -Body (Get-Label 'client.bulle-partie-texte') -Icon 'Info' -Duration 8000 -Key 'gaming.recap' -Launch 'vigie://session-recap' }
                        }
                    }
                    if ($recapNow) { $state.RecapSeen = $recapNow }
                    <#
                        AND IT CLOSES ON ITS OWN.

                        Two reasons, and two only: a new session starts -- the previous recap has no object any
                        more -- or ten minutes have passed without the window coming to the foreground once.
                        Watched, it stays: the count restarts at every glance. Vigie closes ONLY the window it
                        opened itself.
                    #>
                    if ($state.RecapWindow -and $state.RecapWindow -ne [System.IntPtr]::Zero) {
                        $mustClose = $false
                        if ($inGame) { TLog 'recapitulatif : nouvelle partie, fermeture'; $mustClose = $true }
                        elseif ([VigieNative.Win]::IsWatched($state.RecapWindow)) { $state.RecapSeenAt = [datetime]::UtcNow.Ticks }
                        elseif ($state.RecapSeenAt -and ([datetime]::UtcNow - [datetime]$state.RecapSeenAt).TotalMinutes -ge 10) {
                            TLog 'recapitulatif : dix minutes sans etre regarde, fermeture'; $mustClose = $true
                        }
                        if ($mustClose) {
                            try { [void][VigieNative.Win]::Close($state.RecapWindow) } catch { }
                            $state.RecapWindow = $null
                        }
                    }
                    if (-not $state.ModsInit) {
                        $state.Mods = $seen; $state.ModsInit = $true
                    } elseif ($silence) {
                        # DURING AN INSTALLATION a change of state is not an event: it is the gesture in the course
                        # of being made. We update the reference silently, so as not to announce at the end
                        # everything that moved in the meantime.
                        $state.Mods = $seen
                    } else {
                        $settings = $null
                        $bascules = @()
                        # The catalogue says WHAT to notify and under what name. It is read again at every pass: a
                        # module switched back on must be taken into account.
                        $catalogue = @()
                        try { $catalogue = @(Get-NotificationCatalog -Backend $backend) } catch { }
                        foreach ($u in $catalogue) {
                            foreach ($nn in @($u.notifications)) {
                                $ref = if ($nn.card -and $nn.field) { "$($nn.card)/$($nn.field)" } else { $null }
                                if (-not $ref) { continue }
                                $before = $state.Mods[$ref]
                                $after = $seen[$ref]
                                if (-not $before -or -not $after) { continue }
                                if ($before.status -eq $after.status) { continue }
                                # We disturb only for a DEGRADATION or a RECOVERY.
                                $interessant = ($after.status -in @('warn','error')) -or
                                               ($after.status -eq 'ok' -and $before.status -in @('warn','error'))
                                if (-not $interessant) { continue }
                                if ($null -eq $settings) { $settings = Get-NotificationSettings -Backend $backend }
                                if (-not (Test-NotificationAllowed -ModuleId $u.unit -Key $nn.key -Settings $settings)) { continue }
                                # Warned WITHOUT being able to act: we say so, instead of leaving the user in front
                                # of a problem that is beyond them.
                                <#
                                    THE SAME FIELD DOES NOT SPEAK TWICE WITHIN TEN MINUTES.

                                    Crossing a threshold is not an event by itself. During a
                                    game, applications sit right on the CPU/GPU limit and cross
                                    it back and forth: gaming.hogs flipped ok<->warn TEN times
                                    in forty minutes on 06/09, so ten bubbles described one
                                    single situation. There was already a floor of one bubble
                                    per minute for the whole machine, but nothing stopping one
                                    field from ringing for ever.

                                    The delay is PER NOTIFICATION, not global: something else
                                    going wrong during those ten minutes is still announced --
                                    it is a different subject, and it deserves the interruption.

                                    The reference still follows (further down, unconditionally),
                                    so what is silenced is the bubble, never the state.
                                #>
                                $refNotif = "$($u.unit).$($nn.key)"
                                $dernier = $null
                                try { $dernier = $state.NotifPar[$refNotif] } catch { }
                                if ($dernier -and ([datetime]::UtcNow - [datetime]$dernier).TotalMinutes -lt 10) {
                                    # LOGGED ANYWAY: without this line, a deliberate silence
                                    # and a broken watcher look exactly the same in the log.
                                    TLog ("notification retenue (moins de 10 min) : " + $refNotif + " " + $before.status + "->" + $after.status)
                                    continue
                                }
                                $state.NotifPar[$refNotif] = [datetime]::UtcNow
                                $aPrevenir = ("$($nn.rights)" -eq 'admin' -and -not (Test-IsElevated))
                                $bascules += [pscustomobject]@{ id = $refNotif; label = "$($nn.label)"; value = "$($after.value)"; de = $before.status; vers = $after.status; prevenir = $aPrevenir; reason = "$($after.reason)" }
                            }
                        }
                        $state.Mods = $seen
                        if ($bascules.Count -gt 0) {
                            # ONE BUBBLE, even for several changes at once:
                            # three notifications in a row are noise.
                            $pire  = if (@($bascules | Where-Object { $_.vers -eq 'error' }).Count) { 'error' }
                                     elseif (@($bascules | Where-Object { $_.vers -eq 'warn' }).Count) { 'warn' } else { 'ok' }
                            $tipIc = switch ($pire) { 'error' { 'Error' } 'warn' { 'Warning' } default { 'Info' } }
                            <#
                                THE TITLE NAMES THE SUBJECT, THE BODY SAYS THE STATE.

                                Seen on screen on 09/09: "A module changed state" as the title,
                                and the name of what changed pushed into the body. A toast is
                                read title first, and that title was the same for every subject
                                -- it told nobody anything. They are swapped.

                                The bubble no longer opens with "Vigie" either: the header above
                                it already carries the name and the icon since S11. Repeating it
                                cost a third of the only line the reader is sure to see.

                                And it says the MEASUREMENT. "To watch" alone sends the reader
                                to the panel to learn what the bubble already had in hand.
                            #>
                            $word   = @{ ok = (Get-Label 'client.etat-retabli'); warn = (Get-Label 'client.etat-a-surveiller')
                                        error = (Get-Label 'client.etat-en-erreur'); neutral = (Get-Label 'client.etat-sans-objet') }
                            if ($bascules.Count -eq 1) {
                                $single = $bascules[0]
                                $title = "$($single.label)"
                                # THE MEASUREMENT LEADS when there is one -- "2 detected" says more
                                # than "to watch" -- and the state alone gets a word to lean on, so
                                # no line ever starts with a lowercase fragment.
                                $body = $(if ("$($single.value)".Trim()) { (Get-Label 'client.bulle-bascule-texte' "$($single.value)" $word[$single.vers]) }
                                           else { (Get-Label 'client.bulle-bascule-etat' $word[$single.vers]) })
                                # THE REASON FOLLOWS THE STATE (CORE-ERRORS): "RAM 93 %" alone sent the reader to the panel on
                                # 18/09 to learn what the probe already knew -- which applications held the memory.
                                if ($single.reason -and $single.vers -ne 'ok') { $body += [Environment]::NewLine + $single.reason }
                                if ($single.prevenir -and $single.vers -ne 'ok') { $body += [Environment]::NewLine + (Get-Label 'client.bulle-bascule-admin') }
                            } else {
                                $title = (Get-Label 'client.bulle-bascules-titre' $bascules.Count)
                                $body = (@($bascules | ForEach-Object {
                                    (Get-Label 'client.bulle-bascule-ligne' $_.label $word[$_.vers]) +
                                    $(if ($_.prevenir -and $_.vers -ne 'ok') { [Environment]::NewLine + (Get-Label 'client.bulle-bascule-admin') } else { '' })
                                }) -join [Environment]::NewLine)
                            }
                            TLog ("notification : " + (@($bascules | ForEach-Object { "$($_.id) $($_.de)->$($_.vers)" }) -join ', '))
                            # THE FIELD'S REFERENCE TRAVELS WITH IT: that is what makes a
                            # recovery replace its own alert instead of sitting next to it.
                            # Several changes at once have no single field, so they share
                            # one label.
                            $fieldKey = $(if ($bascules.Count -eq 1) { "$($bascules[0].id)" } else { 'vigie.modules' })
                            & $dire -Subject $title -Body $body -Icon $tipIc -Duration 6000 -Key $fieldKey
                        }
                    }
                }
            } catch { TLog ("guetteur de modules : " + $_.Exception.Message) }
        }
        $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 8000; $timer.add_Tick($poll); $timer.Start()
        $first = New-Object System.Windows.Forms.Timer; $first.Interval = 2000; $first.add_Tick({ $first.Stop(); & $poll }); $first.Start()

        # Reading the orders. A plain poll of an almost empty folder: negligible, and far simpler to maintain than
        # a FileSystemWatcher, whose events arrive on another thread and would have to be put back on the interface
        # thread.
        $commandes = {
            try {
                $stop = Join-Path $runDir 'stop'
                if (Test-Path -LiteralPath $stop) {
                    Remove-Item -LiteralPath $stop -Force -ErrorAction SilentlyContinue
                    try { Set-Content -LiteralPath (Join-Path $runDir 'stop.ack') -Value "$PID" -Encoding ASCII -NoNewline } catch { }
                    & $quitApp 'ordre stop'
                    return
                }
                # THE OPEN ORDERS come from the protocol: a notification is clicked, Windows calls protocol.ps1,
                # which drops the file read here. The app that owns the screen stays the only one that opens.
                foreach ($order in @(@{ nom = 'open-recap'; sur = 'recap' }, @{ nom = 'open'; sur = '' })) {
                    $orderFile = Join-Path $runDir $order.nom
                    if (Test-Path -LiteralPath $orderFile) {
                        Remove-Item -LiteralPath $orderFile -Force -ErrorAction SilentlyContinue
                        TLog ("ordre recu : " + $order.nom)
                        if ($order.sur) { & $openApp $order.sur } else { & $openApp }
                    }
                }
                $restart = Join-Path $runDir 'restart'
                if (Test-Path -LiteralPath $restart) {
                    Remove-Item -LiteralPath $restart -Force -ErrorAction SilentlyContinue
                    # AN ACKNOWLEDGEMENT, before leaving. The sender could only judge on the return of a NEW client
                    # app (ten seconds or so): "order not taken into account" therefore mixed up "nothing read the
                    # order" and "the restart is slower than expected". That is not the same troubleshooting.


                    try { Set-Content -LiteralPath (Join-Path $runDir 'restart.ack') -Value "$PID" -Encoding ASCII -NoNewline } catch { }
                    TLog "arret demande (ordre restart)"
                    & $relaunch
                    return
                }

                <#
                    THE ACTIONS THAT NEED A SCREEN.

                    The server has none -- and the day it becomes the machine task, it will run in session 0, where
                    "Start-Process explorer.exe" succeeds without anybody ever seeing the window. So it drops the
                    order here, and it is the client app that runs it: in ITS OWN session, with ITS OWN rights, on
                    the desktop of whoever asked.

                    We report back in a ".done.json" file the server is waiting for. EVEN ON FAILURE: without a
                    report it waits until the expiry then wrongly concludes the client app is absent.
                #>


                foreach ($order in @(Get-ChildItem -LiteralPath $runDir -Filter 'client-task-*.json' -File -ErrorAction SilentlyContinue |
                                     Where-Object { $_.Name -notlike '*.done.json' })) {
                    $response = Join-Path $runDir ($order.BaseName + '.done.json')
                    $outcome = @{ message = ''; result = @{ ok = $false } }
                    try {
                        $charge = Get-Content -LiteralPath $order.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                        Remove-Item -LiteralPath $order.FullName -Force -ErrorAction SilentlyContinue
                        $type = "$($charge.type)"
                        # The same check as on the server side: a simple identifier, and nothing resembling a path.
                        # A folder of orders is an attack surface, even inside one's own profile.
                        if ($type -notmatch '^[a-z][a-z0-9-]{1,40}$') { throw "type d'action invalide" }
                        $script = Join-Path (Join-Path $backend 'actions') ($type + '.action.ps1')
                        if (-not (Test-Path -LiteralPath $script)) { throw "action inconnue : $type" }
                        $p = @{}
                        if ($charge.params) {
                            foreach ($prop in $charge.params.PSObject.Properties) { $p[$prop.Name] = $prop.Value }
                        }
                        TLog "tache cliente : $type"
                        $r = & $script -Module "$($charge.module)" -Params $p
                        $outcome = @{ message = "$($r.message)"; result = $r.result }
                    } catch {
                        TLog ("tache cliente KO : " + $_.Exception.Message)
                        $outcome = @{ message = $_.Exception.Message; result = @{ ok = $false } }
                    }
                    try { ($outcome | ConvertTo-Json -Compress -Depth 6) | Out-File -FilePath $response -Encoding UTF8 } catch { }
                }
            } catch { TLog ("lecture des ordres KO : " + $_.Exception.Message) }
        }
        $cmdTimer = New-Object System.Windows.Forms.Timer
        $cmdTimer.Interval = 1000; $cmdTimer.add_Tick($commandes); $cmdTimer.Start()

        # S5: we subscribe, then look at the flag every second. A failure here breaks nothing -- the network probe
        # expires on its own anyway.
        try {
            [VigieNative.Net]::Watch()
            $netTimer = New-Object System.Windows.Forms.Timer
            $netTimer.Interval = 1000
            $netTimer.add_Tick({
                try {
                    if ([VigieNative.Net]::Changed) {
                        [VigieNative.Net]::Changed = $false
                        Remove-ProbeCache -Names @('net.probe.ps1') -Backend $backend
                        TLog "adresse reseau changee : sonde reseau perimee"
                    }
                } catch { }
            })
            $netTimer.Start()
            TLog "guetteur d'adresse reseau arme"
        } catch { TLog ("guetteur d'adresse reseau indisponible : " + $_.Exception.Message) }

        <#
            WINDOWS CLOSING THE SESSION IS WRITTEN DOWN.

            Twice -- 28/09 and 05/10, both in the middle of a game -- the client app's log stopped dead with no
            closing line, and the conclusion drawn was that the app had vanished on its own. It had not: the Windows
            event log holds a restart asked from the Start menu each time (User32 1074), followed by an unclean stop
            (Kernel-Power 41, EventLog 6008). The app was closed WITH the computer, which is normal; what was missing
            was the line saying so, and its absence cost two investigations into a defect that does not exist.

            SystemEvents.SessionEnding fires before Windows tears the session down, and it says WHY -- a sign-out or
            a shutdown. Nothing here tries to delay it: the line is written, and that is all it is for.
        #>
        try {
            [Microsoft.Win32.SystemEvents]::add_SessionEnding({
                param($sender, $e)
                try { TLog ("Windows ferme la session (" + $e.Reason + ") : arret avec l'ordinateur") } catch { }
            })
            TLog "fin de session Windows surveillee"
        } catch { TLog ("fin de session Windows non surveillee : " + $_.Exception.Message) }

        # A BUBBLE THAT IGNORES A CLICK IS A DOOR PAINTED ON A WALL. Clicking it did nothing -- it just vanished
        # (reported 28/09). It now opens the panel, which is what anyone expects.
        try { $icon.add_BalloonTipClicked({ TLog "clic sur la bulle : ouverture du panneau"; & $openApp }) } catch { }
        try { $icon.ShowBalloonTip(3000, 'Vigie', "Panneau lance en fond. Un clic sur cette bulle l'ouvre.", [System.Windows.Forms.ToolTipIcon]::Info) } catch { }

        TLog "Application.Run"
        [System.Windows.Forms.Application]::Run()
        if ($iconHandle -ne [System.IntPtr]::Zero) { [void][VigieNative.Ico]::DestroyIcon($iconHandle) }
        TLog "sortie boucle"
    } catch { TLog ("ERREUR UI: " + $_.Exception.ToString()) }
}

$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
$ps = [PowerShell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript($uiScript).AddArgument($backend).AddArgument($clientLog).AddArgument($RepoUrl).AddArgument($PSScriptRoot)
try { $ps.Invoke() } catch { TLog ("ERREUR Invoke: " + $_.Exception.ToString()) }
foreach ($er in $ps.Streams.Error) { TLog ("STREAM ERROR: " + $er.ToString()) }
try { $rs.Close() } catch { }
try { $mutex.ReleaseMutex() } catch { }
TLog "termine"
