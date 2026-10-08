# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    Intent: the one place where everything the back end shares lives, so that no mechanism
    exists twice -- the card contract, the configuration, the token, the aggregation of the
    probes, the running of the actions, the data paths. It depends on nothing of Pode, so a
    script, a probe or a worker can load it without a server.
    Usage: dot-source it (`. (Join-Path $backend 'lib/common.ps1')`) before anything else,
    and look here FIRST for a function that already does what you are about to write; add
    one here rather than beside it, and never a second way to do the same thing.
#>

<#
    "DOES THIS PATH EXIST?" MUST NEVER BRING A CALLER DOWN.

    Test-Path THROWS on a path whose rights are refused -- another account's profile,
    typically. Under "ErrorActionPreference = Stop" the question then takes the whole script
    with it. Seen twice on 29/08: an entire probe in error, and a restart of client apps cut
    short, both times because something asked whether a folder existed.

    A refusal of access IS NOT an answer to the question asked: we do not know whether the
    path exists, and "I do not know" is treated as "no" here -- there is nothing to be done
    with it either way.

    The repository's rule: a system call that repeats becomes a function of ours.
#>
function Test-PathSafe {
    param([string]$Path)
    if (-not $Path) { return $false }
    try { return [bool](Test-Path -LiteralPath $Path -ErrorAction Stop) } catch { return $false }
}

function Get-BackendRoot { Split-Path $PSScriptRoot -Parent }

# THE LABELS ARE AVAILABLE WHEREVER common.ps1 IS -- that is, in the server, the probes, the
# actions and the workers. Without loading them here, every file would have to remember to
# load i18n.ps1, and whoever forgot would only break at run time, on the line that displays:
# the worst possible place to learn it.
# console-ui.ps1 brings the display vocabulary AND, through it, the labels: the two files are
# neighbours and one loads the other. Loading common.ps1 is therefore enough to have it all.
# Without this, a back-end file converted to Write-Ok died on "term not recognised" -- at run
# time, on its display line.
$script:_uiLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/console-ui.ps1'
if (Test-Path -LiteralPath $script:_uiLib) { . $script:_uiLib }

# The account secret: laying it down, its rights, reading it back suspiciously. This file had
# existed since 28/08 without being loaded anywhere -- code no test could see.
$script:_secretLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/account-secret.ps1'
if (Test-Path -LiteralPath $script:_secretLib) { . $script:_secretLib }

# Who listens on a port, asked of Windows directly: Get-PortListener, Get-UdpEndpointOwner (26 s through WMI on 14/09).
$script:_portLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/tcp-ports.ps1'
if (Test-Path -LiteralPath $script:_portLib) { . $script:_portLib }

# Memory and processor load, asked of Windows directly: Get-MemoryStatus, Get-ProcessorLoad (1.7 s through WMI on 18/09).
$script:_metricsLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/system-metrics.ps1'
if (Test-Path -LiteralPath $script:_metricsLib) { . $script:_metricsLib }

# Who holds a file, asked of Windows directly: Get-FileHolders, through the Restart Manager. Names what blocks (D127).
$script:_lockLib = Join-Path (Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent) 'scripts/lib/file-locks.ps1'
if (Test-Path -LiteralPath $script:_lockLib) { . $script:_lockLib }

# --- Landmarks of the tree ---------------------------------------------------
# The repository holds SEVERAL apps (apps/backend, apps/frontend, apps/client,
# apps/atelier) plus scripts/ and doc/. These landmarks are computed HERE and nowhere
# else: no script may recompose a cross-app path by hand.
function Get-RepoRoot { Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent }
function Get-AppsRoot { Split-Path (Get-BackendRoot) -Parent }
# App folder names carry their TECHNOLOGY: they are replaceable implementations
# (principle no. 1). They are written ONLY HERE; all the code goes through Get-AppPath.
# Only the bootstrap is an exception -- see the note further down.
function Get-AppPath {
    param([Parameter(Mandatory)][ValidateSet('backend','frontend','client','atelier')][string]$Role)
    $folder = switch ($Role) {
        'backend'  { 'backend-pode' }    # PowerShell + Pode
        'frontend' { 'frontend-web' }    # HTML/CSS/JS, sans framework ni build
        'client'   { 'client' }          # pas de suffixe : n'implemente aucun contrat
        'atelier'  { 'atelier' }         # idem
    }
    Join-Path (Get-AppsRoot) $folder
}

# A NOTE ON THE BOOTSTRAP: a script that must LOAD this library cannot call Get-AppPath
# yet. The backend folder's name is therefore spelled out there (client.ps1,
# scripts/*.ps1). It is unavoidable: one has to know where the library is before being
# able to use it. Those lines are marked with a comment of their own.

# --- Shared helpers (the rule: one feature, one piece of code) ---------------

# Is the current process elevated (administrator)?
function Test-Elevated {
    try {
        return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

<#
    ONE VALUE, ONE ARGUMENT -- whatever that value contains.

    A Windows command line is a SINGLE STRING; the child splits it again with the rules of
    CommandLineToArgvW. Start-Process joins -ArgumentList with spaces and quotes NOTHING, so
    each value handed to it must already be a valid token.

    Wrapping it by hand -- ('"' + $path + '"') -- is the trap that looks like the fix: it
    holds for "C:\Program Files\Sowapps\Vigie" and breaks on a path that ends with a
    backslash, because "C:\dir\" escapes its own closing quote and swallows the argument
    that follows.

    Three rules, and no others:
      - an empty value is not nothing, it is a pair of quotes;
      - a backslash only matters in front of a quote (the end of the value counts, since the
        closing quote comes next): there, it doubles;
      - a value carrying a space, a tab or a quote is wrapped -- anything else is passed as
        it stands, because wrapping what needs nothing hides what does.

    The sibling of ConvertTo-PSLiteral, which answers the same question for the OTHER world:
    a value inserted into PowerShell source. Neither escaping fits the other's world.
#>
function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Value)
    if ($null -eq $Value -or $Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $out = [Text.StringBuilder]::new('"')
    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') { $backslashes++; continue }
        if ($ch -eq '"') { [void]$out.Append('\' * (2 * $backslashes + 1)); [void]$out.Append('"'); $backslashes = 0; continue }
        if ($backslashes -gt 0) { [void]$out.Append('\' * $backslashes); $backslashes = 0 }
        [void]$out.Append($ch)
    }
    # Trailing backslashes sit just before the closing quote: they double, or they escape it.
    if ($backslashes -gt 0) { [void]$out.Append('\' * (2 * $backslashes)) }
    [void]$out.Append('"')
    $out.ToString()
}

<#
    STARTING A PROCESS WITH ARGUMENTS GOES THROUGH HERE, ALWAYS (D116).

    Arguments are given RAW, as values; the quoting happens here, once, for everyone. That is
    the whole point: the fault it prevents cannot be seen when rereading the line, and says
    nothing at run time -- on 02/09 the game resident died at every arming on "C:\Program is
    not a script", and only its health field ever revealed it. A rule nobody can check is a
    rule nobody keeps, so check-probes refuses a bare Start-Process everywhere but here.

    Everything else Start-Process accepts -- Wait, PassThru, Verb, WindowStyle,
    WorkingDirectory, redirections -- travels untouched through -Options.

    THE CALL OPERATOR IS ANOTHER WORLD: "& $exe @arguments" quotes each value ITSELF, so a
    value wrapped by hand arrives WITH its quotes. Invoke-Native, which uses it, therefore
    takes raw values too -- the same discipline, the opposite mechanism.
#>
function Start-ChildProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [hashtable]$Options = @{}
    )
    $splat = @{}
    foreach ($k in $Options.Keys) { $splat[$k] = $Options[$k] }
    $splat['FilePath'] = $FilePath
    if ($Arguments.Count -gt 0) {
        $splat['ArgumentList'] = @($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) })
    }
    Start-Process @splat
}

# Runs a native command handling its output AND its exit code (the rule: errors, output and
# exit codes are always handled). Returns one uniform object.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @())
    # winget, like other modern tools, emits UTF-8; PowerShell decoded it with the OEM code
    # page (850) and every accent became a pair of symbols -- including in the error messages
    # shown to the user. UTF-8 is forced for the length of the capture.
    $before = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
    try {
        $out = & $File @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        try { [Console]::OutputEncoding = $before } catch { }
    }
    # winget decorates its output with ANSI sequences for highlighting: unreadable once
    # captured, so they are stripped. [...letter is the standard CSI form.
    $text = (($out | Out-String).TrimEnd()) -replace "\[[0-9;]*[A-Za-z]", ''
    [pscustomobject]@{ Ok = ($code -eq 0); ExitCode = $code; Output = $text }
}

# Merges keys into a JSON state file (an ATOMIC read-merge-write), serialised by a named
# mutex derived from the file, so several writers -- actions, detached workers -- do not
# overwrite one another. The rule: one single piece of code writes the files of var/cache
# (netmeasure.json, pkgupdates.json, ...).
function Update-StateJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Set,
        # Serialisation depth. 8 is enough for flat states; a TREE -- the disk analysis --
        # goes past it, and ConvertTo-Json then truncates IN SILENCE.
        [int]$Depth = 8
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $leaf = (Split-Path $Path -Leaf) -replace '[^A-Za-z0-9]', '_'
    $mx = $null; $held = $false
    try {
        $mx = New-Object System.Threading.Mutex($false, "Local\VigieState_$leaf")
        try { $held = $mx.WaitOne(5000) }
        catch [System.Threading.AbandonedMutexException] { $held = $true }
        catch { $held = $false }
        $data = @{}
        if (Test-Path $Path) {
            try { $j = Get-Content $Path -Raw | ConvertFrom-Json; foreach ($pp in $j.PSObject.Properties) { $data[$pp.Name] = $pp.Value } } catch { }
        }
        foreach ($k in $Set.Keys) { $data[$k] = $Set[$k] }
        $tmp = "$Path.tmp"
        ($data | ConvertTo-Json -Depth $Depth) | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $Path -Force
        return $data
    } finally {
        if ($held -and $mx) { try { $mx.ReleaseMutex() } catch { } }
        if ($mx) { try { $mx.Dispose() } catch { } }
    }
}

# Invalidates -- removes -- entries of the state cache: the probes named will be recomputed
# at the next /state. One single piece of code, reused by Invoke-ActionById AND by the
# detached workers. Best effort, written atomically.
function Remove-ProbeCache {
    param([Parameter(Mandatory)][string[]]$Names, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    $cacheFile = Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'cache' -File 'state-cache.json'
    # TEST-PATHSAFE: on another account's var, Test-Path THROWS instead of saying "no".
    if (-not (Test-PathSafe $cacheFile)) { return }
    try {
        $obj = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $ht = @{}
        foreach ($pp in $obj.PSObject.Properties) { $ht[$pp.Name] = $pp.Value }
        $changed = $false
        <#
            THE PER-ACCOUNT ENTRIES GO TOO.

            An action names the PROBE ("accounts.probe.ps1"); since personal cards have one key
            per account, the real entries are called "accounts.probe.ps1@fhaza",
            "accounts.probe.ps1@Famille"... so the invalidation removed nothing at all, and the
            card kept the rendering it had before the update.
        #>
        <#
            INVALIDATING IS NOT FORGETTING.

            The entry used to be deleted. Since a display no longer computes anything, a probe
            with no entry has no card at all: after an installation, Accounts and Deployment had
            purely VANISHED from the page. An empty card, loading, is no trouble at all -- which
            is what had been agreed.

            So the known rendering is kept and marked TO BE RECOMPUTED: the card shows, with its
            title and its place, and says it is waiting for its measurement.
        #>
        foreach ($k in $Names) {
            foreach ($present in @($ht.Keys)) {
                if ($present -eq $k -or $present -like ($k + '@*')) {
                    $entry = $ht[$present]
                    if ($entry -and $entry.module) {
                        # "at" at epoch zero: stale whatever the delay.
                        try { $entry.at = '0001-01-01T00:00:00.0000000Z' } catch { }
                        try { Add-Member -InputObject $entry -NotePropertyName 'pending' -NotePropertyValue $true -Force } catch { }
                        <#
                            AND THE OCCUPANCY DOES NOT SURVIVE IN A KEPT RENDERING (D130).

                            A card computed WHILE an operation ran carries `busy` in its rendering. We keep that
                            rendering so the card does not vanish -- but `busy` is not a value, it is a state, and it
                            was over by the time this ran: this function is called at the END of the operation.
                            Served again, the stale flag greyed the card out of its buttons until the probe
                            recomputed, which for the packages card can be a day. Seen on 06/10: the owner had to
                            press F5. A kept rendering keeps what was measured, never what was happening.
                        #>
                        foreach ($mod in @($entry.module)) {
                            if (-not $mod) { continue }
                            foreach ($champ in @('busy', 'busyAction', 'busyResources')) {
                                try { if ($mod.PSObject.Properties[$champ]) { $mod.PSObject.Properties.Remove($champ) } } catch { }
                            }
                        }
                        $ht[$present] = $entry
                    } else {
                        $ht.Remove($present)
                    }
                    $changed = $true
                }
            }
        }
        if ($changed) {
            $tmp = "$cacheFile.tmp"
            ($ht | ConvertTo-Json -Depth 25) | Out-File -FilePath $tmp -Encoding UTF8
            Move-Item -Path $tmp -Destination $cacheFile -Force
            # AND THE SCHEDULER LEARNS IT: without this an invalidated card would wait out its whole interval.
            try { Reset-RefreshDue -Backend $Backend -Probes $Names } catch { }
        }
    } catch { }
}

# --- The Windows Update machinery: THE catalogue ------------------------------------
# Paths, accounts and tasks of the locking, defined ONCE AND ONLY ONCE (D15). The probe, the
# state reading, the laying of the lock and the audit all draw on them: these lists used to
# be copied into the probe, into the reading helper and into a script OUTSIDE the repository
# -- three copies that could only drift apart.
function Get-UpdateTaskCatalog {
    [ordered]@{
        # The policy: NoAutoUpdate=1 turns automatic updates off.
        RegAu    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
        RegWu    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        RegUx    = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        # The accounts aimed at, by SID: never by name, which Windows translates per language.
        SidSystem = 'S-1-5-18'
        SidAdmins = 'S-1-5-32-544'
        # Task folders ON DISK: that is where the permission lock is laid.
        Dirs = @(
            "$env:windir\System32\Tasks\Microsoft\Windows\UpdateOrchestrator"
            "$env:windir\System32\Tasks\Microsoft\Windows\WindowsUpdate"
            "$env:windir\System32\Tasks\Microsoft\Windows\InstallService"
            "$env:windir\System32\Tasks\Microsoft\Windows\WaaSMedic"
        )
        # The same folders as the SCHEDULER sees them (reading the state).
        TaskPaths = @(
            '\Microsoft\Windows\UpdateOrchestrator\'
            '\Microsoft\Windows\WindowsUpdate\'
            '\Microsoft\Windows\InstallService\'
            '\Microsoft\Windows\WaaSMedic\'
        )
        # The ONLY tasks Windows lets one disable. The others are protected: trying to switch
        # them fails, which is normal and is not a breakdown.
        Managed = @(
            [pscustomobject]@{ Path = '\Microsoft\Windows\WindowsUpdate\';  Name = 'Scheduled Start' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'RestoreDevice' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'ScanForUpdates' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'ScanForUpdatesAsUser' }
            [pscustomobject]@{ Path = '\Microsoft\Windows\InstallService\'; Name = 'SmartRetry' }
        )
        # Services of the update machinery (WaaSMedicSvc is the "repairer" that undoes the
        # settings: its state explains a good many unexplained reversals).
        Services = @('wuauserv','UsoSvc','WaaSMedicSvc','BITS','DoSvc','InstallService')
    }
}

# Is the ACL lock -- writing refused to SYSTEM -- laid on the task folder?
# Compared by SID (S-1-5-18), independent of the language and of the account's translation.
function Test-UpdateTasksAclLock {
    param([string]$Path = (Get-UpdateTaskCatalog).Dirs[0])
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    # icacls is the authoritative source (it is also what update-mode.ps1 lays down). The only
    # refusal applied is SYSTEM's: one (DENY) entry means the lock is on. "(DENY)" is NOT
    # localised by icacls, so the test holds whatever the language of Windows.
    try {
        $r = Invoke-Native -File 'icacls.exe' -Arguments @($Path)
        if ($r.Output -match '\(DENY\)') { return $true }
    } catch { }
    # A .NET fallback, by SID, when icacls is unavailable.
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $sysSid = New-Object System.Security.Principal.SecurityIdentifier(
            [System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        foreach ($ace in $acl.Access) {
            if ($ace.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Deny) { continue }
            try { if (($ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])) -eq $sysSid) { return $true } } catch { }
        }
    } catch { }
    return $false
}

# The REAL and complete state of the Windows Update locking. READ ONLY.
#
# It is the single state reading of this subject: the probe displays it, the actions use it to
# say what was OBSERVED after acting (D43), and the audit takes it as it stands.
#
# `locked` means the lock is COMPLETE: automatic updates off AND the permission lock laid.
# The two halves answer different questions and are never conflated.
<#
    THE TASKS OF ONE FOLDER, IN FORTY MILLISECONDS INSTEAD OF SIX SECONDS AND A HALF.

    Get-ScheduledTask -TaskPath walks the whole tree on each call: four folders cost 6 682 ms, measured on 29/09, and
    that alone was almost all of the Windows Update lock card. The Task Scheduler's own interface opens a folder and
    lists it: 43 ms for the same six tasks, the same names, the same states.

    The state is given as a number by that interface; it is translated to the words the rest of the code already uses.
    A folder we may not read answers nothing, which is exactly what the cmdlet did -- and here it IS the information:
    the lock is on.
#>
$script:TaskStateNames = @{ 0 = 'Unknown'; 1 = 'Disabled'; 2 = 'Queued'; 3 = 'Ready'; 4 = 'Running' }

function Get-TasksInFolder {
    param([Parameter(Mandatory)][string]$Path)
    $out = @()
    # THE SERVICE, ONCE. Only ITS failure is a reason to fall back: a FOLDER that refuses is an answer, not a breakdown.
    if (-not $script:TaskService) {
        try {
            $svc = New-Object -ComObject Schedule.Service
            $svc.Connect()
            $script:TaskService = $svc
        } catch { $script:TaskService = $null }
    }
    if ($script:TaskService) {
        try {
            $folder = $script:TaskService.GetFolder($Path.TrimEnd([char]92))
            foreach ($task in $folder.GetTasks(1)) {
                $state = $script:TaskStateNames[[int]$task.State]
                if (-not $state) { $state = "$($task.State)" }
                $out += [pscustomobject]@{ path = $Path; name = "$($task.Name)"; state = $state }
            }
        } catch {
            <#
                A FOLDER WE CANNOT OPEN HAS NOTHING TO SAY, and that silence IS the information: it is what the ACL
                lock does to UpdateOrchestrator. Falling back to the cmdlet here cost 3 400 ms per pass to be told
                the same nothing (measured 29/09) -- the whole gain of this function, spent on a refusal.
            #>
        }
        return $out
    }
    # NO SERVICE AT ALL: the cmdlet, slow but present.
    try {
        foreach ($t in (Get-ScheduledTask -TaskPath $Path -ErrorAction Ignore)) {
            $out += [pscustomobject]@{ path = "$($t.TaskPath)"; name = "$($t.TaskName)"; state = "$($t.State)" }
        }
    } catch { }
    return $out
}

function Get-UpdateLockState {
    $cat = Get-UpdateTaskCatalog
    $noAuto = $null
    try { $noAuto = (Get-ItemProperty -Path $cat.RegAu -Name NoAutoUpdate -ErrorAction SilentlyContinue).NoAutoUpdate } catch { }
    $tasks = @()
    foreach ($p in $cat.TaskPaths) {
        # -ErrorAction Ignore rather than SilentlyContinue: a folder that is empty or whose
        # access is refused -- which is precisely what the lock does -- raises an error that
        # SilentlyContinue hides on screen while still stacking it in $Error. Absence here is
        # expected information, reported further down, not an incident to collect.
        $tasks += @(Get-TasksInFolder -Path $p)
    }
    $acl = Test-UpdateTasksAclLock
    $autoOff = ($noAuto -eq 1)
    [ordered]@{
        elevated       = (Test-Elevated)
        noAutoUpdate   = $noAuto
        autoUpdatesOff = $autoOff
        aclLock        = $acl
        locked         = ($autoOff -and $acl)
        tasks          = @($tasks)
        tasksDisabled  = @($tasks | Where-Object { $_.state -eq 'Disabled' }).Count
        tasksReady     = @($tasks | Where-Object { $_.state -ne 'Disabled' }).Count
    }
}

# NATIVE writing of the lock: no external script, no dependency outside the repository.
# Internal -- the only entry point stays Set-UpdateLock, which observes the result.
#
# Idempotence: every gesture is already written to withstand being replayed. Laying a refusal
# already laid, disabling a task already disabled or writing NoAutoUpdate to the same value
# changes nothing and must report NOTHING abnormal.
function Invoke-UpdateLockNative {
    param(
        [Parameter(Mandatory)][ValidateSet('pose','leve')][string]$State,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = Get-UpdateTaskCatalog
    $sys = '*' + $cat.SidSystem
    $adm = '*' + $cat.SidAdmins
    $trace = New-Object System.Collections.Generic.List[string]
    $noter = { param($m) $trace.Add([string]$m) }

    # 1) The policy: turn automatic updates off, or give them back.
    # The policy key does NOT exist on a fresh machine, and writing to it failed silently.
    # It is created -- that is the difference between "it works on my machine" and "it works
    # on a clean installation".
    $value = if ($State -eq 'pose') { 1 } else { 0 }
    try {
        if (-not (Test-Path -LiteralPath $cat.RegAu)) { New-Item -Path $cat.RegAu -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $cat.RegAu -Name 'NoAutoUpdate' -Value $value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        & $noter "NoAutoUpdate = $value"
    } catch {
        & $noter "NoAutoUpdate : ECHEC -- $($_.Exception.Message)"
    }

    # 2) Make the folders writable BEFORE anything else, even to LAY the lock: one cannot
    # disable a task inside a folder whose access is refused. Removing a refusal that is not
    # there has no effect, so this replays.
    foreach ($d in $cat.Dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $r1 = Invoke-Native -File 'icacls.exe' -Arguments @($d, '/remove:d', $sys, '/t', '/c', '/q')
        $r2 = Invoke-Native -File 'icacls.exe' -Arguments @($d, '/grant', ($sys + ':(OI)(CI)F'), '/t', '/c', '/q')
        & $noter ("deverrouillage " + (Split-Path $d -Leaf) + " : remove:d=" + $r1.ExitCode + " grant=" + $r2.ExitCode)
    }

    # 3) Managed tasks: disabled when laying, re-enabled when lifting. The folder's other
    # tasks are protected by Windows and do not switch -- that is not a failure.
    foreach ($m in $cat.Managed) {
        try {
            if ($State -eq 'pose') { Disable-ScheduledTask -TaskName $m.Name -TaskPath $m.Path -ErrorAction Stop | Out-Null }
            else                  { Enable-ScheduledTask  -TaskName $m.Name -TaskPath $m.Path -ErrorAction Stop | Out-Null }
            & $noter ("tache " + $m.Name + " -> " + $(if ($State -eq 'pose') { 'desactivee' } else { 'activee' }))
        } catch {
            # Task absent in this edition of Windows, or protected: noted, and we carry on.
            & $noter ("tache " + $m.Name + " : ignoree -- " + $_.Exception.Message)
        }
    }

    if ($State -eq 'pose') {
        # 4) The permission lock: take ownership of the folders, keep access for the
        # administrators, then REFUSE creation and modification to SYSTEM. It is that refusal
        # which stops Windows recreating its tasks and forcing a restart.
        foreach ($d in $cat.Dirs) {
            if (-not (Test-Path -LiteralPath $d)) { continue }
            $name = Split-Path $d -Leaf
            $rt = Invoke-Native -File 'takeown.exe' -Arguments @('/f', $d, '/r', '/a', '/d', 'O')
            $rg = Invoke-Native -File 'icacls.exe'  -Arguments @($d, '/grant', ($adm + ':(OI)(CI)F'), '/t', '/c')
            $rd = Invoke-Native -File 'icacls.exe'  -Arguments @($d, '/deny',  ($sys + ':(OI)(CI)(WD,AD,DC)'), '/t', '/c')
            & $noter ("verrouillage $name : takeown=" + $rt.ExitCode + " grant=" + $rg.ExitCode + " deny=" + $rd.ExitCode)
            if (-not $rd.Ok) { & $noter ("  detail deny $name : " + (($rd.Output -split "`r?`n" | Select-Object -Last 3) -join ' | ')) }
        }
    } else {
        # 4b) Lifting: tell Windows the policy has changed, or the Windows Update interface
        # goes on showing the old setting until its own cycle comes round.
        $uso = Join-Path $env:windir 'System32\UsoClient.exe'
        if (Test-Path -LiteralPath $uso) {
            $ru = Invoke-Native -File $uso -Arguments @('RefreshSettings')
            & $noter ("UsoClient RefreshSettings : exit=" + $ru.ExitCode)
        }
    }
    return @($trace)
}

# Lays or lifts the update lock. The ONLY entry point for WRITING (D15): the update-mode-on
# and update-mode-off actions, the installation and the update scan all come through here.
# Without it, every caller would copy the manoeuvre.
#
# A NATIVE implementation: locking is a capability of the product, not a service rendered by
# a script outside the repository. A supplied `ToolsPath` carrying `update-mode.ps1` is still
# PREFERRED where it exists, for historical installations, but its absence no longer stops
# anything.
#
# Returns $true when the state asked for is REALLY obtained, read back AFTERWARDS and never
# inferred from the fact that no command raised an error (D43).
function Set-UpdateLock {
    param(
        [Parameter(Mandatory)][ValidateSet('pose','leve')][string]$State,
        [string]$Backend = (Get-BackendRoot)
    )
    # Without elevation, icacls and takeown fail silently and one would believe the lock laid.
    # We refuse BEFORE acting: the caller has a false state to announce, not a half measure.
    if (-not (Test-Elevated)) {
        try { Write-Log -Backend $Backend -Name 'updatelock' -Level 'WARN' -Message (Get-Label 'common.refuse-le-serveur-est' $State) } catch { }
        return $false
    }
    $route = 'native'
    $trace = @()
    $script = $null
    $tools = Get-ToolsPath -Backend $Backend
    if ($tools) {
        $candidat = Join-Path $tools 'update-mode.ps1'
        if (Test-Path -LiteralPath $candidat) { $script = $candidat; $route = 'outillage' }
    }
    try {
        if ($script) {
            if ($State -eq 'pose') { & $script -Off *> $null } else { & $script -On *> $null }
        } else {
            $trace = Invoke-UpdateLockNative -State $State -Backend $Backend
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'updatelock' -Level 'ERROR' -Message "$State ($route) : $($_.Exception.Message)" } catch { }
    }
    # THE OBSERVATION: the real state is read back, and it is what counts.
    $actualState = Get-UpdateLockState
    $obtenu = if ($State -eq 'pose') { $actualState.aclLock } else { -not $actualState.aclLock }
    try {
        foreach ($t in $trace) { Write-Log -Backend $Backend -Name 'updatelock' -Message "  $t" }
        Write-Log -Backend $Backend -Name 'updatelock' -Message (Get-Label 'common.obtenu-verrouacl-noautoupdate-tachesdesactivees' $State $route $obtenu $($actualState.aclLock) $($actualState.noAutoUpdate) $($actualState.tasksDisabled))
    } catch { }
    return [bool]$obtenu
}

# --- Virtualisation security (VBS / HVCI) ---------------------------------------
# THE catalogue of this subject, defined once (D15): registry keys, value names and labels.
# The probe, the state reading and the switch all draw on them.
#
# What sets this subject apart from the Windows Update lock: a value written here only takes
# effect at the next RESTART. So there are TWO states never to be confused --
#   `configured`: what the registry asks for (what is written, verifiable at once);
#   `running`   : what Windows actually runs (it will not move before a restart).
function Get-DeviceGuardCatalog {
    $rootPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    [ordered]@{
        Root      = $rootPath
        RootReg   = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard'   # forme attendue par reg.exe
        Features  = [ordered]@{
            vbs  = [pscustomobject]@{
                Key = $rootPath; Name = 'EnableVirtualizationBasedSecurity'
                Label = 'Sécurité par virtualisation (VBS)'; Court = 'VBS'
            }
            hvci = [pscustomobject]@{
                Key = "$rootPath\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = 'Enabled'
                Label = 'Intégrité mémoire (HVCI)'; Court = 'intégrité mémoire'
            }
        }
    }
}

# The marker of switches ASKED FOR and not yet effective (var/cache). It serves two purposes:
# knowing what to display ("demandé, effectif au redémarrage") and knowing which value to
# switch to when one clicks again before having restarted.
function Get-DeviceGuardMarkerPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'deviceguard.json'
}

# The REAL and complete state of VBS / HVCI. READ ONLY.
#
# For each feature:
#   configured : the registry value (0/1), $null when the value does not exist
#   running    : what Windows runs right now (Win32_DeviceGuard)
#   requested  : what Vigie asked for and which is waiting for a restart ($null otherwise)
#   pending    : a request of Vigie's is not yet effective
#   effective  : the state to DISPLAY and the one a switch works from -- the pending request
#                if there is one, otherwise what is running. Switching from `running` while a
#                request waits would go backwards without saying so.
function Get-DeviceGuardState {
    param([string]$Backend = (Get-BackendRoot))
    $cat = Get-DeviceGuardCatalog
    $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $running = @{
        vbs  = [bool]($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2)
        hvci = [bool]($dg -and ($dg.SecurityServicesRunning -contains 2))
    }
    $marque = @{}
    try {
        $f = Get-DeviceGuardMarkerPath -Backend $Backend
        if (Test-Path -LiteralPath $f) {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $marque[$p.Name] = $p.Value }
        }
    } catch { }

    $State = [ordered]@{ elevated = (Test-Elevated); vbsStatus = $(if ($dg) { [int]$dg.VirtualizationBasedSecurityStatus } else { $null }) }
    foreach ($id in $cat.Features.Keys) {
        $f = $cat.Features[$id]
        $cfg = $null
        try {
            $v = (Get-ItemProperty -LiteralPath $f.Key -Name $f.Name -ErrorAction SilentlyContinue).$($f.Name)
            if ($null -ne $v) { $cfg = [int]$v }
        } catch { }
        $dem = $null
        try { if ($marque[$id] -and $null -ne $marque[$id].requested) { $dem = [int]$marque[$id].requested } } catch { }
        # A request that already matches what is running is no longer pending: the marker
        # goes stale on its own at the restart, with no arbitrary delay to tune.
        $pending = ($null -ne $dem -and [bool]$dem -ne $running[$id])
        $State[$id] = [ordered]@{
            label      = $f.Label
            court      = $f.Court
            configured = $cfg
            running    = $running[$id]
            requested  = $(if ($pending) { $dem } else { $null })
            pending    = $pending
            effective  = $(if ($pending) { [bool]$dem } else { $running[$id] })
        }
    }
    $State['pending'] = ($State.vbs.pending -or $State.hvci.pending)
    $State
}

# Backs up the DeviceGuard key BEFORE any writing, into var/log.
# A startup setting is hard to undo by hand: we keep what it takes to go back.
function Backup-DeviceGuardKey {
    param([string]$Backend = (Get-BackendRoot))
    $cat = Get-DeviceGuardCatalog
    $f = Join-Path (Get-LogDir -Backend $Backend) ('deviceguard_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.reg')
    try {
        $r = Invoke-Native -File 'reg.exe' -Arguments @('export', $cat.RootReg, $f, '/y')
        # D43: the backup exists when the FILE is there, not when the call has returned.
        if ((Test-Path -LiteralPath $f) -and $r.Ok) { return $f }
    } catch { }
    return $null
}

# Writes the value of ONE feature. The ONLY entry point for WRITING (D15).
#
# It returns an object, where Set-UpdateLock returns a boolean, because there is nothing to
# preserve here: no existing caller, and "written" does not tell the story -- one has to tell
# "already at that value", "written, waiting for the restart" and "written but still running"
# apart, the last being a value imposed by the UEFI or by a policy. The result is READ BACK
# from the registry, never assumed (D43).
function Set-DeviceGuardFeature {
    param(
        [Parameter(Mandatory)][ValidateSet('vbs','hvci')][string]$Feature,
        [Parameter(Mandatory)][bool]$Enable,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = Get-DeviceGuardCatalog
    if (-not (Test-Elevated)) {
        try { Write-Log -Backend $Backend -Name 'deviceguard' -Level 'WARN' -Message (Get-Label 'common.refuse-le-serveur-est' $Feature) } catch { }
        return @{ ok = $false; elevated = $false }
    }
    $targetValue = [int][bool]$Enable
    $before = Get-DeviceGuardState -Backend $Backend
    $sauvegarde = Backup-DeviceGuardKey -Backend $Backend

    # The values to lay down. HVCI CANNOT run without VBS: disabling VBS while leaving memory
    # integrity asked for leaves an inconsistent configuration, which Windows sometimes
    # resolves by switching VBS back on. So both are turned off -- and it is SAID.
    # The converse is not true: enabling VBS does not enable memory integrity behind the
    # user's back; that is a separate decision with its own trade-offs.
    $toWrite = @( [pscustomobject]@{ Id = $Feature; Valeur = $targetValue } )
    $hvciCoupeAussi = $false
    if ($Feature -eq 'vbs' -and $targetValue -eq 0) {
        $toWrite += [pscustomobject]@{ Id = 'hvci'; Valeur = 0 }
        $hvciCoupeAussi = $true
    }

    $erreurs = @()
    foreach ($e in $toWrite) {
        $f = $cat.Features[$e.Id]
        try {
            # Idempotent: New-Item -Force on an existing key does not erase it, and writing
            # the same value again has no effect. Replaying the switch breaks nothing.
            if (-not (Test-Path -LiteralPath $f.Key)) { New-Item -Path $f.Key -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -Path $f.Key -Name $f.Name -Value $e.Valeur -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        } catch {
            $erreurs += "$($e.Id) : $($_.Exception.Message)"
        }
    }

    # The marker: what Vigie asked for. It is used to offer the restart, and to know which
    # value to switch back to if the user clicks again before restarting.
    try {
        $set = @{}
        foreach ($e in $toWrite) { $set[$e.Id] = @{ requested = $e.Valeur; at = (Get-Date).ToUniversalTime().ToString('o') } }
        Update-StateJson -Path (Get-DeviceGuardMarkerPath -Backend $Backend) -Set $set | Out-Null
    } catch { }

    # THE OBSERVATION: the REGISTRY is read back, the only state that can have changed now.
    # Reading `running` to judge would be a guaranteed false failure -- it will not move
    # before the restart. That is the difference not to miss with the Windows Update lock.
    $after = Get-DeviceGuardState -Backend $Backend
    $ecrit = ($after[$Feature].configured -eq $targetValue)
    try {
        Write-Log -Backend $Backend -Name 'deviceguard' -Message (Get-Label 'common.ecrit-configavant-configapres-actif' $Feature $targetValue $ecrit $($before[$Feature].configured) $($after[$Feature].configured) $($after[$Feature].running) $hvciCoupeAussi $sauvegarde $(if ($erreurs.Count) { ' erreurs=' + ($erreurs -join ' | ') } else { '' }))
    } catch { }

    @{
        ok             = $ecrit
        elevated       = $true
        feature        = $Feature
        value          = $targetValue
        already        = ($before[$Feature].configured -eq $targetValue)
        running        = $after[$Feature].running
        rebootNeeded   = ($after[$Feature].running -ne [bool]$targetValue)
        hvciCoupeAussi = $hvciCoupeAussi
        backup         = $sauvegarde
        errors         = @($erreurs)
        state          = $after
    }
}

# Switches ONE feature, from the user's point of view: what the card DISPLAYS (`effective`)
# is inverted, not what is running. Clicking again before restarting therefore returns to the
# starting state, instead of writing the same value twice.
#
# It returns @{ message; result } directly: the two actions differ only by the feature's
# name, and there is no reason to write that report twice (D15).
function Invoke-DeviceGuardToggle {
    param(
        [Parameter(Mandatory)][ValidateSet('vbs','hvci')][string]$Feature,
        [string]$Backend = (Get-BackendRoot)
    )
    $inv = @('vbs.probe.ps1')
    $State = Get-DeviceGuardState -Backend $Backend
    $name  = $State[$Feature].court

    if (-not $State.elevated) {
        return @{
            message = "Le serveur de Vigie n'est pas administrateur : la bascule $name est impossible. Vigie doit être relancée en administrateur (l'invite UAC s'affichera)."
            result  = @{ ok = $false }
        }
    }

    $targetValue = -not $State[$Feature].effective
    $r = Set-DeviceGuardFeature -Feature $Feature -Enable $targetValue -Backend $Backend
    $verbe = if ($targetValue) { 'activée' } else { 'désactivée' }

    if (-not $r.ok) {
        $det = if (@($r.errors).Count) { ' ' + (@($r.errors) -join ' ; ') } else { '' }
        return @{
            message = "La valeur de $name n'a pas pu être écrite dans le registre.$det"
            result  = @{ ok = $false; invalidate = $inv }
        }
    }

    $bonus = if ($r.hvciCoupeAussi) { " L'intégrité mémoire est coupée avec elle : elle ne peut pas fonctionner sans VBS." } else { '' }
    $garde = if ($r.backup) { " Sauvegarde du registre : $($r.backup)." } else { " Attention : la sauvegarde du registre n'a pas pu être écrite." }

    if (-not $r.rebootNeeded) {
        # Value written AND already matching what runs: nothing to wait for.
        return @{
            message = "$name déjà $verbe : la configuration et l'état actif concordent, aucun redémarrage nécessaire.$bonus"
            result  = @{ ok = $true; invalidate = $inv }
        }
    }
    $rappel = if ($r.already) { " Cette valeur était déjà demandée : si elle ne s'applique toujours pas après un redémarrage, elle est imposée par l'UEFI ou par une stratégie d'entreprise." } else { '' }
    @{
        message = "$name sera $verbe au prochain redémarrage de Windows — la demande est écrite, elle ne prend effet qu'au démarrage.$bonus$rappel$garde"
        result  = @{ ok = $true; invalidate = $inv }
    }
}

# Is a deferred restart under way, and therefore still cancellable?
# Bounded in TIME: an expired countdown is no longer cancellable -- either the machine has
# restarted, or it was cancelled elsewhere. The flag alone would stay true for ever.
# Shared by the cards that offer a restart (Windows Update, virtualisation): this
# computation lived in one probe and was about to be copied into a second (D15).
function Test-RestartCountdown {
    param([string]$Backend = (Get-BackendRoot))
    $f = Get-VarPath -Backend $Backend -Kind 'cache' -File 'restart.json'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    try {
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        if (-not ($j.pending -and $j.at)) { return $false }
        $delaiPrevu = if ($j.delay) { [int]$j.delay } else { 60 }
        $ecoule = ([datetime]::UtcNow - (ConvertTo-UtcDate $j.at)).TotalSeconds
        return ($ecoule -ge 0 -and $ecoule -lt ($delaiPrevu + 15))
    } catch { return $false }
}

# A complete audit of the Windows Update machinery. READ ONLY, it changes nothing.
#
# Reimplemented inside the repository: the audit served to understand why a lock does not
# hold -- a repairing service, a policy overwritten, a task recreated. A diagnostic function
# that requires an absent toolkit is precisely no use when one needs it.
#
# The report goes to var/log/ (the project's convention: everything the app generates lives
# under var/), in text to be read and in JSON to be reused.
#
# ITS LINES ARE SHOWN IN THE PANEL (S04, 30/09): the action hands them back and the page lays them out preformatted.
# They are therefore INTERFACE, and carry their accents -- the report used to be written for a file, read by nobody.
function Invoke-UpdateAudit {
    param([string]$Backend = (Get-BackendRoot))
    $cat    = Get-UpdateTaskCatalog
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir    = Get-LogDir -Backend $Backend
    $txt    = Join-Path $dir "update-audit_$stamp.txt"
    $json   = Join-Path $dir "update-audit_$stamp.json"
    $lines = New-Object System.Collections.Generic.List[string]
    $rap    = [ordered]@{}
    $L   = { param($s = '') $lines.Add([string]$s) }
    $Sec = { param($t) & $L ''; & $L ('===== ' + $t + ' =====') }

    $State = Get-UpdateLockState
    $rap.at       = (Get-Date).ToString('o')
    $rap.elevated = $State.elevated
    & $L ("Audit Windows Update du " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "  (administrateur = " + $State.elevated + ")")
    if (-not $State.elevated) { & $L "ATTENTION : serveur non administrateur — une partie de l'état n'est pas lisible." }

    & $Sec 'Verrouillage'
    & $L ("   Mises à jour automatiques coupées : " + $State.autoUpdatesOff + "   (NoAutoUpdate=" + $State.noAutoUpdate + ")")
    & $L ("   Verrou de permissions (ACL)       : " + $State.aclLock)
    & $L ("   Verrou complet                    : " + $State.locked)
    $rap.lock = @{ autoUpdatesOff = $State.autoUpdatesOff; noAutoUpdate = $State.noAutoUpdate
                   aclLock = $State.aclLock; locked = $State.locked }

    & $Sec 'Édition et licence'
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        & $L ("   " + $cv.ProductName + "  (EditionID=" + $cv.EditionID + ")  build " + $cv.CurrentBuild + "." + $cv.UBR)
        $rap.edition = @{ product = "$($cv.ProductName)"; editionId = "$($cv.EditionID)"; build = "$($cv.CurrentBuild).$($cv.UBR)" }
    } catch { & $L "   (illisible)" }

    # Policies explain most of the "the lock did not hold": a value written elsewhere, by a
    # GPO or another tool, overwrites ours without a word.
    $vider = {
        param($exePath, $title)
        & $Sec $title
        $o = [ordered]@{}
        if (-not (Test-Path -LiteralPath $exePath)) { & $L '   (absente)'; return $o }
        $p = Get-ItemProperty -LiteralPath $exePath -ErrorAction SilentlyContinue
        # A key that EXISTS can return $null -- no value at all, or a reading refused without
        # elevation. And $null.PSObject.Properties.Name returns one $null element, which gets
        # through the filter and is then used as an index: seen as "the array index evaluated
        # to null". So emptiness is ruled out explicitly, rather than a list of names assumed.
        if ($null -eq $p) { & $L '   (illisible ou vide)'; return $o }
        $names = @($p.PSObject.Properties.Name | Where-Object { $_ -and ("$_" -notlike 'PS*') })
        foreach ($n in $names) { & $L ("   {0,-40} = {1}" -f $n, $p.$n); $o[$n] = $p.$n }
        if (-not $names.Count) { & $L '   (vide)' }
        return $o
    }
    $rap.policyWindowsUpdate = & $vider $cat.RegWu 'Stratégie WindowsUpdate'
    $rap.policyAu            = & $vider $cat.RegAu 'Stratégie WindowsUpdate\AU'
    $rap.ux                  = & $vider $cat.RegUx 'Réglages UX (heures actives, notifications)'

    & $Sec 'Redémarrage en attente'
    $pending = [ordered]@{}
    $pending.CBS_RebootPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $pending.WU_RebootRequired = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pending.PendingFileRename = [bool]((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
    foreach ($k in $pending.Keys) { & $L ("   {0,-22} = {1}" -f $k, $pending[$k]) }
    $rap.pendingReboot = $pending

    & $Sec 'Tâches planifiées de mise à jour'
    if (-not @($State.tasks).Count) { & $L '   (aucune lisible — accès refusé ?)' }
    foreach ($p in $cat.TaskPaths) {
        $lot = @($State.tasks | Where-Object { $_.path -eq $p })
        & $L ''
        & $L ("[" + $p + "]")
        if (-not $lot.Count) { & $L '   (aucune / accès refusé)'; continue }
        foreach ($t in $lot) { & $L ("   {0,-34} {1}" -f $t.name, $t.state) }
    }
    $rap.tasks = @($State.tasks)
    $rap.tasksDisabled = $State.tasksDisabled
    $rap.tasksReady    = $State.tasksReady

    & $Sec 'Services de mise à jour'
    $svc = @()
    foreach ($n in $cat.Services) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $s) { & $L ("   {0,-16} (absent)" -f $n); continue }
        $dem = ''
        try { $dem = "$((Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue).StartMode)" } catch { }
        & $L ("   {0,-16} statut={1,-10} démarrage={2}" -f $n, $s.Status, $dem)
        $svc += @{ name = $n; status = "$($s.Status)"; start = $dem }
    }
    # WaaSMedicSvc happily puts the machinery back to work: its start mode read from the
    # registry is more reliable than the one the service manager reports.
    try {
        $wm = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -ErrorAction SilentlyContinue).Start
        if ($null -ne $wm) { & $L ("   WaaSMedicSvc Start (registre) = " + $wm + "  (2=automatique, 3=manuel, 4=désactivé)"); $rap.waasMedicStart = $wm }
    } catch { }
    $rap.services = $svc

    & $Sec 'Contexte'
    try {
        $bootLocal = (Get-BootTime).ToLocalTime()
        & $L ("   Dernier démarrage : " + $bootLocal)
        $rap.lastBoot = "$bootLocal"
    } catch { }
    $hf = @()
    try {
        foreach ($h in (Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5)) {
            & $L ("   {0,-12} {1}" -f $h.HotFixID, $h.InstalledOn)
            $hf += @{ id = "$($h.HotFixID)"; installedOn = "$($h.InstalledOn)" }
        }
    } catch { }
    $rap.hotfixes = $hf

    $ecrit = $false
    try {
        ($lines -join "`r`n") | Out-File -FilePath $txt  -Encoding UTF8
        ($rap | ConvertTo-Json -Depth 8) | Out-File -FilePath $json -Encoding UTF8
        # D43: the report is "written" when the FILE EXISTS, not when the call has returned.
        $ecrit = (Test-Path -LiteralPath $txt) -and (Test-Path -LiteralPath $json)
    } catch {
        try { Write-Log -Backend $Backend -Name 'updateaudit' -Level 'ERROR' -Message $_.Exception.Message } catch { }
    }
    return @{ ok = $ecrit; txt = $txt; json = $json; elevated = $State.elevated; state = $State; lines = @($lines) }
}

# --- Background tasks (the rule: a slow action never blocks the request) ----
# Starts a worker script in a DETACHED pwsh, window hidden -- no console appears and no
# Terminal tab is restored. The pwsh executable is the current process's own, so no
# installation path is hard-coded anywhere. Parameters travel as base64 JSON, which is
# robust to quoting. Returns the process id.
# RESERVED FOR THE INTERNAL RECOMPUTE OF A STALE PROBE, whose place in the protocol is not settled (S14). An
# action never calls it: an asynchronous operation goes through Start-Operation, and check-operations refuses the rest.
function Start-DetachedAction {
    param(
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$ArgsMap = @{},
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-Path -LiteralPath $Script)) { throw "Worker introuvable : $Script" }
    <#
        THE HARD CEILING ON WHAT VIGIE MAY START -- and it is a REFUSAL, not a warning.

        On 29/09 a bad guard let each background task start another one: 150 elevated processes in two minutes, the
        machine down to 0,3 GB of free memory, and the server unable to listen on its own port. No count anywhere
        said stop. A product that watches a computer must never be what brings it down.

        Every process Vigie starts is written down here, with its id; the dead ones are dropped at each pass. Past
        MaxChildren live ones, the launch is REFUSED -- it returns nothing, it says so in the log, and the caller
        carries on without its background task. Nothing is ever stopped by this: refusing to start is enough.
    #>
    $childFile = $null
    try {
        $childFile = Get-VarPath -Backend $Backend -Kind 'run' -File 'children.json'
        $live = @()
        if (Test-PathSafe $childFile) {
            $raw = Get-Content -LiteralPath $childFile -Raw -Encoding UTF8 -ErrorAction Stop
            foreach ($id in @((ConvertFrom-Json $raw).ids)) {
                try { if (Get-Process -Id ([int]$id) -ErrorAction Stop) { $live += [int]$id } } catch { }
            }
        }
        $max = 8
        try { $max = [int](Get-RefreshConfig -Backend $Backend).MaxChildren } catch { }
        if ($max -le 0) { $max = 8 }
        if ($live.Count -ge $max) {
            Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (
                "lancement REFUSE : $($live.Count) taches de fond vivantes, plafond $max -- " + (Split-Path $Script -Leaf))
            return $null
        }
        $script:PendingChildren = $live
    } catch { $script:PendingChildren = @() }
    $exe = $null
    try { $exe = (Get-Process -Id $PID).Path } catch { }
    if (-not $exe) { try { $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { } }
    if (-not $exe) { $exe = 'pwsh.exe' }
    $json = ($ArgsMap | ConvertTo-Json -Compress -Depth 6)
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe
    # NB: no -WindowStyle argument -- it is not implemented outside Windows. The absence of a
    # window is guaranteed by CreateNoWindow + UseShellExecute=$false below.
    # ArgumentList, NOT Arguments: .NET quotes each value itself, while a command line built
    # by hand carries the trap a path ending with a backslash sets (D116).
    foreach ($piece in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                         '-File', $Script, '-Backend', $Backend, '-ArgsB64', $b64)) {
        [void]$psi.ArgumentList.Add([string]$piece)
    }
    # THE CHILD IS A BACKGROUND TASK, AND IT SAYS SO: Get-State reads this and never hands off in turn (29/09).
    $psi.UseShellExecute = $false
    [void]$psi.EnvironmentVariables.Remove('VIGIE_NO_BACKGROUND')
    [void]$psi.EnvironmentVariables.Add('VIGIE_NO_BACKGROUND', '1')
    $psi.CreateNoWindow  = $true
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = $Backend
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p) { return $null }
    # WRITTEN DOWN THE MOMENT IT EXISTS, or the ceiling above counts nothing.
    try {
        $ids = @($script:PendingChildren) + @([int]$p.Id)
        Set-Content -LiteralPath $childFile -Value (@{ ids = @($ids) } | ConvertTo-Json -Compress) -Encoding UTF8
    } catch { }
    return $p.Id
}

# --- Package managers (one source for the probe, the update check AND the upgrade) --
# One catalogue: id, label, version arguments, update arguments and mode, upgrade arguments.
# An empty upgArgs means no automatic update is offered for that manager.
#
# upgOne holds the arguments to update ONE package, `{pkg}` being replaced by its
# identifier. That is what makes CHOICE possible: without upgOne a manager only knows how to
# "update everything", and the interface says so rather than suggesting otherwise.
#
# gui* describes the manager's graphical interface, when it exists AND is installed.
#   guiKind 'uri' -> a protocol checked in HKEY_CLASSES_ROOT (the Store is not an .exe)
#   guiKind 'exe' -> an executable looked for in the PATH, then in guiPaths
# A button that opens an absent program is worse than no button: presence is checked at
# every pass of the probe, never assumed.
function Get-PackageManagerCatalog {
    @(
        [pscustomobject]@{ id='winget'; label='winget';       verArgs=@('--version'); updArgs=@('upgrade','--include-unknown','--disable-interactivity','--accept-source-agreements'); updMode='winget';   upgArgs=@('upgrade','--all','--silent','--include-unknown','--disable-interactivity','--accept-source-agreements','--accept-package-agreements')
                           upgOne=@('upgrade','--id','{pkg}','--silent','--disable-interactivity','--accept-source-agreements','--accept-package-agreements')
                           guiKind='uri'; guiTarget='ms-windows-store://downloadsandupdates'; guiProbe='ms-windows-store'; guiLabel='Ouvrir le Microsoft Store'
                           guiHelp="Ouvre la page « Téléchargements et mises à jour » du Microsoft Store, qui partage le catalogue de winget." }
        [pscustomobject]@{ id='choco';  label='Chocolatey';   verArgs=@('--version'); updArgs=@('outdated','-r','--nocolor');   updMode='chocor';   upgArgs=@('upgrade','all','-y')
                           upgOne=@('upgrade','{pkg}','-y')
                           guiKind='exe'; guiTarget='ChocolateyGUI.exe'; guiProbe='ChocolateyGUI'; guiLabel='Ouvrir Chocolatey GUI'
                           guiHelp="Ouvre Chocolatey GUI, l'interface graphique de Chocolatey (paquet « chocolateygui »)." }
        [pscustomobject]@{ id='scoop';  label='Scoop';        verArgs=@('--version'); updArgs=@('status');                      updMode='lines';    upgArgs=@('update','*');  upgOne=@() }
        [pscustomobject]@{ id='npm';    label='npm';          verArgs=@('-v');        updArgs=@('outdated','-g','--json');      updMode='jsonkeys'; upgArgs=@('update','-g'); upgOne=@() }
        [pscustomobject]@{ id='pnpm';   label='pnpm';         verArgs=@('-v');        updArgs=@('outdated','-g');               updMode='lines';    upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='yarn';   label='Yarn';         verArgs=@('-v');        updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='pip';    label='pip (Python)'; verArgs=@('--version'); updArgs=@('list','--outdated','--format=json'); updMode='jsonlist'; upgArgs=@();        upgOne=@('install','-U','{pkg}') }
        [pscustomobject]@{ id='pipx';   label='pipx';         verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='cargo';  label='Cargo (Rust)'; verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='gem';    label='RubyGems';     verArgs=@('--version'); updArgs=@('outdated');                    updMode='lines';    upgArgs=@('update');      upgOne=@() }
        [pscustomobject]@{ id='dotnet'; label='.NET SDK';     verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
    )
}

# The graphical interface REALLY present for a manager, or $null.
# Returns @{ target; label; help }: enough to build the button and the action.
function Get-PkgGui {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg -or -not $mg.guiKind) { return $null }
    $targetPath = $null
    switch ($mg.guiKind) {
        'uri' {
            # An unregistered protocol would open an "application not found" dialog.
            if (Test-Path -LiteralPath ("Registry::HKEY_CLASSES_ROOT\" + $mg.guiProbe)) { $targetPath = $mg.guiTarget }
        }
        'exe' {
            $c = Get-Command $mg.guiProbe -ErrorAction SilentlyContinue
            if ($c -and $c.Source) { $targetPath = $c.Source }
            else {
                $rootPath = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { 'C:\ProgramData\chocolatey' }
                foreach ($p in @((Join-Path $rootPath ('bin\' + $mg.guiTarget)), (Join-Path $rootPath ('lib\chocolateygui\tools\' + $mg.guiTarget)))) {
                    if (Test-Path -LiteralPath $p) { $targetPath = $p; break }
                }
            }
        }
    }
    if (-not $targetPath) { return $null }
    return @{ target = $targetPath; label = $mg.guiLabel; help = $mg.guiHelp }
}

# Checks the updates available from ONE manager (a slow call, over the network). Handles the
# output AND the exit code through Invoke-Native.
# Returns @{ count; items; pkgs; supported; selectable }.
#   items = DISPLAY strings, cut at 25, which fill the card's detail
#   pkgs  = the COMPLETE list @{ id; titre; detail }, `id` being the identifier to hand the
#           manager to update THAT package only. Without it no choice is possible: one
#           cannot ask "which ones?" holding nothing but display labels.
function Get-PkgUpdates {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $false } }
    $selectable = ($null -ne $mg.upgOne -and @($mg.upgOne).Count -gt 0)
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $selectable } }
    if ($mg.updMode -eq 'none' -or $mg.updArgs.Count -eq 0) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $selectable } }
    $count = 0; $items = @(); $pkgs = @()
    try {
        $r = Invoke-Native -File $cmd.Source -Arguments $mg.updArgs
        $out = "$($r.Output)"
        switch ($mg.updMode) {
            'jsonlist' {
                if ($out.Trim()) {
                    $j = $out | ConvertFrom-Json
                    foreach ($e in @($j)) {
                        $items += ("{0}  {1} -> {2}" -f $e.name, $e.version, $e.latest_version)
                        $pkgs  += [ordered]@{ id = "$($e.name)"; titre = "$($e.name)"; detail = ("{0} -> {1}" -f $e.version, $e.latest_version) }
                    }
                    $count = $items.Count
                }
            }
            'jsonkeys' {
                if ($out.Trim() -and $out.Trim() -ne '{}') {
                    $j = $out | ConvertFrom-Json
                    foreach ($e in @($j.PSObject.Properties)) {
                        $items += ("{0} -> {1}" -f $e.Name, $e.Value.latest)
                        $pkgs  += [ordered]@{ id = "$($e.Name)"; titre = "$($e.Name)"; detail = "$($e.Value.latest)" }
                    }
                    $count = $items.Count
                }
            }
            'chocor' {
                foreach ($l in (($out -split "`r?`n") | Where-Object { $_ -match '\|' })) {
                    $p = $l.Split('|')
                    $items += ("{0}  {1} -> {2}" -f $p[0], $p[1], $p[2])
                    $pkgs  += [ordered]@{ id = "$($p[0])"; titre = "$($p[0])"; detail = ("{0} -> {1}" -f $p[1], $p[2]) }
                }
                $count = $items.Count
            }
            'winget' {
                $lines = @($out -split "`r?`n"); $idx = -1
                for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{3,}') { $idx = $i; break } }
                if ($idx -ge 0 -and $idx -lt ($lines.Count - 1)) {
                    # winget's columns: Name | Id | Version | Available | Source. The Id is
                    # the ONLY column one can target a package with -- the name is not unique.
                    #
                    # Cut at FIXED POSITIONS, not on "two spaces or more": winget fills each
                    # column to the width of its longest element, so a long name leaves just
                    # ONE space before the Id, and a wide version number leaves one before the
                    # next. Seen for real: splitting on spaces returned "12.0.40664.0" as the
                    # identifier of the Visual C++ Redistributable -- an update would have
                    # aimed at a package that does not exist. The column starts are read from
                    # the header line.
                    $hdr = if ($idx -ge 1) { "$($lines[$idx-1])" } else { '' }
                    $debuts = @()
                    if ($hdr.Length) {
                        if ($hdr[0] -ne ' ') { $debuts += 0 }
                        for ($k = 2; $k -lt $hdr.Length; $k++) {
                            if ($hdr[$k] -ne ' ' -and $hdr[$k-1] -eq ' ' -and $hdr[$k-2] -eq ' ') { $debuts += $k }
                        }
                    }
                    $rest = @($lines[($idx+1)..($lines.Count-1)] | Where-Object { $_.Trim() -and $_ -notmatch 'niveau|upgrade|mise' })
                    foreach ($l in $rest) {
                        $cols = @()
                        if ($debuts.Count -ge 2) {
                            for ($c = 0; $c -lt $debuts.Count; $c++) {
                                $s = $debuts[$c]
                                if ($s -ge $l.Length) { $cols += ''; continue }
                                $e = if ($c + 1 -lt $debuts.Count) { [Math]::Min($debuts[$c+1], $l.Length) } else { $l.Length }
                                $cols += $l.Substring($s, $e - $s).Trim()
                            }
                        } else {
                            # A fallback when the header is missing, on unexpected output:
                            # an approximate list beats nothing at all.
                            $cols = @(($l -split '\s{2,}') | Where-Object { $_ } | ForEach-Object { "$_".Trim() })
                        }
                        if (-not $cols.Count) { continue }
                        $name = "$($cols[0])"
                        if (-not $name) { continue }
                        $items += $name
                        # NO variable named $pid: it is a read-only automatic variable, the
                        # process id. Assigning to it raised an exception the catch swallowed,
                        # and the list came back EMPTY.
                        $ident = if ($cols.Count -ge 2) { "$($cols[1])" } else { '' }
                        if ($ident) {
                            $det = if ($cols.Count -ge 4 -and $cols[3]) { ("{0} -> {1}" -f "$($cols[2])", "$($cols[3])") } else { $ident }
                            $pkgs += [ordered]@{ id = $ident; titre = $name; detail = $det }
                        }
                    }
                    $count = $items.Count
                }
            }
            'lines' {
                $items = @(($out -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch '^Name|^-{3,}|is up to date|Everything' })
                $count = $items.Count
            }
        }
    } catch { }
    # The selectable list is NOT truncated: one cannot tick what one cannot see. Only the
    # card's condensed display is.
    if ($items.Count -gt 25) { $items = @($items[0..24] + "... (+$($items.Count - 25))") }
    return @{ count = $count; items = @($items); pkgs = @($pkgs); supported = $true; selectable = $selectable }
}

# The LOCAL DNS PROXY, if there is one: the Windows service whose process listens on port
# 53. Detected by BEHAVIOUR rather than by name -- Acrylic today, anything else tomorrow,
# and null when there is none.
function Get-LocalDnsProxyService {
    try {
        $owner = Get-UdpEndpointOwner -Port 53
        if (-not $owner) { return $null }
        $svc = Get-ServiceByProcessId -ProcessId $owner
        if ($svc) { return [pscustomobject]@{ Name = $svc.Name; DisplayName = $svc.DisplayName; Pid = $owner } }
    } catch { }
    return $null
}

# Puts a package manager's failure message IN PLAIN WORDS: what it means, and what to do.
# The tool's raw message is jargon -- "a different installation technology" evokes nothing --
# and the card must carry the explanation.
function Get-PkgFailureAdvice {
    param([string]$Reason)
    if (-not $Reason) { return $null }

    if ($Reason -match 'technologie d.installation est diff|install technology is different') {
        return ("En clair : cette application a été installée à l'origine par un autre canal " +
                "que winget (préinstallée avec Windows, installateur classique, Store...) ; winget refuse de mettre à jour par-dessus. " +
                "Que faire : réinstaller l'application depuis son installateur officiel — l'installation est " +
                "remplacée proprement, les données et profils sont conservés.")
    }
    # "Already done" is NOT a failure: winget refuses because the installed version is
    # already at least as recent. Seen with Edge, which had updated itself through its own
    # channel between the check and the click -- so Vigie offered an update already carried
    # out, then displayed it as a FAILURE. Recognising that pattern lets the line be removed
    # instead of blamed.
    if ($Reason -match 'Aucune version de package plus|No newer package versions are available|No applicable (update|upgrade) found|No available upgrade found') {
        return "En clair : c'est déjà fait — la version installée est au moins aussi récente que celle proposée. La liste datait d'avant. Rien à faire."
    }
    if ($Reason -match '0x80070005|acc.s refus|access is denied') {
        return "En clair : Windows a refusé l'accès. Que faire : réessayer ; si ça persiste, un antivirus ou un verrou de fichier bloque l'écriture."
    }
    if ($Reason -match '1603|0x80070643') {
        return "En clair : l'installateur du paquet a échoué (erreur générique MSI). Que faire : redémarrer Windows puis réessayer — c'est la cause la plus fréquente."
    }
    return $null
}

# Does the failure merely say THE WORK IS ALREADY DONE? Then the line has no business in a
# list of updates to offer.
function Test-PkgFailureIsDone {
    param([string]$Reason)
    if (-not $Reason) { return $false }
    return [bool]($Reason -match 'Aucune version de package plus|No newer package versions are available|No applicable (update|upgrade) found|No available upgrade found')
}

# Updates the packages of ONE manager (a slow, system-wide call). It inherits the server's
# elevation. Handles output and exit code. Returns @{ ok; supported; exit; output }.
#
# -Pkgs empty  -> the historical behaviour: the WHOLE manager, in one command.
# -Pkgs filled -> one command PER package (upgOne), so those only. When the manager cannot
#   target a package, the selection is ignored and the global update happens instead: which
#   is what the choice window told the user.
function Invoke-PkgUpgrade {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string[]]$Pkgs,
        # THE WHOLE MANAGER, AND IT HAS TO BE SAID (D131). This is where "upgrade --all" leaves from: an empty
        # list meant all of it, and that installed sixteen programs instead of one on 06/10. The gate sits here, as
        # close to the gesture as possible, because a mistyped parameter name upstream must never be able to open it.
        [switch]$All
    )
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg) { return @{ ok = $false; supported = $false; output = '' } }
    $liste = @($Pkgs | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" })
    $unParUn = ($liste.Count -gt 0 -and $null -ne $mg.upgOne -and @($mg.upgOne).Count -gt 0)
    # NOTHING DESIGNATED IS NOT EVERYTHING (D131): with no package and no -All, nothing runs, and it says so.
    if (-not $liste.Count -and -not $All) {
        return @{ ok = $false; supported = $true; output = ''; count = 0; failed = @()
                  reason = "aucun paquet désigné : précisez les paquets, ou demandez explicitement tout le gestionnaire" }
    }
    if (-not $unParUn -and (-not $mg.upgArgs -or @($mg.upgArgs).Count -eq 0)) { return @{ ok = $false; supported = $false; output = '' } }
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ ok = $false; supported = $false; output = '' } }

    # 3010 = ERROR_SUCCESS_REBOOT_REQUIRED: the installation SUCCEEDED and asks for a
    # restart. Treating it as a failure ("ok=False") was wrong and showed an error on an
    # operation that had worked -- seen with Chocolatey.
    # 1641 = restart ALREADY triggered, the same family.
    if (-not $unParUn) {
        $r = Invoke-Native -File $cmd.Source -Arguments $mg.upgArgs
        $rebootRequired = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
        return @{ ok = ($r.Ok -or $rebootRequired); supported = $true; exit = $r.ExitCode
                  reboot = $rebootRequired; output = $r.Output; count = 0; failed = @() }
    }

    $outputs = @(); $failures = @(); $raisons = @{}; $rebootRequired = $false; $dernier = 0
    foreach ($p in $liste) {
        # .Replace rather than -replace: a package identifier ('Microsoft.VC++', 'a.b')
        # contains characters the regular-expression engine would interpret.
        $argv = @($mg.upgOne | ForEach-Object { "$_".Replace('{pkg}', $p) })
        $r = Invoke-Native -File $cmd.Source -Arguments $argv
        $rb = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
        if ($rb) { $rebootRequired = $true }
        if (-not ($r.Ok -or $rb)) {
            # The REASON for the failure: the last meaningful line of winget's output --
            # it is the one that says what to do ("a different installation technology...").
            $usefulLine = @(("$($r.Output)" -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
            $motif = if ($usefulLine) { "$usefulLine".Trim() } else { '' }
            # "Nothing newer to install" is not a failure: the package is already up to date,
            # having updated itself through its own channel since the check. Counting it as a
            # failure turned the whole operation red and showed an error on work that had
            # nothing to do -- seen with Edge.
            if (Test-PkgFailureIsDone -Reason $motif) {
                $outputs += ("=== $p (code $($r.ExitCode)) === deja a jour, ignore")
                continue
            }
            $failures += $p
            if ($motif) { $raisons[$p] = $motif }
        }
        $dernier = $r.ExitCode
        $outputs += ("=== $p (code $($r.ExitCode)) ===" + [Environment]::NewLine + "$($r.Output)")
    }
    return @{ ok = ($failures.Count -eq 0); supported = $true; exit = $dernier; reboot = $rebootRequired
              output = ($outputs -join ([Environment]::NewLine + [Environment]::NewLine))
              count = $liste.Count; failed = @($failures); reasons = $raisons }
}

# The GENERIC, non-blocking launcher of a package operation: 'check' or 'upgrade'.
# It marks the card as busy, naming the operation, starts the detached worker and hands back
# at once. One piece of code shared by both actions, so nothing is duplicated.
function Start-PkgJob {
    param(
        [Parameter(Mandatory)][string]$Mgr,
        [ValidateSet('check','upgrade')][string]$Op = 'check',
        # THE PACKAGES KEPT. An empty list no longer means "all": that takes -All (D131). See Invoke-PkgUpgrade.
        [string[]]$Pkgs,
        <#
            -All: THE WHOLE MANAGER, AND IT HAS TO BE SAID (D131).

            An empty list used to mean "all of it". On 06/10 a call passed the list under a parameter name that did
            not exist, it arrived empty, and winget received `upgrade --all`: SIXTEEN programs installed instead of
            one, among them the owner's terminal, closed with the work running inside it, and WSL, which he had kept
            for himself.

            None of it threw: every link did what it was asked. The DEFECT is the design -- an absence read as the
            widest permission. From now on, "all" is asked for.
        #>
        [switch]$All,
        # POUR QUEL COMPTE (D128). A manager installed in a profile answers only in that profile's session, and the
        # service account has no winget at all. Without an account there is nobody to ask, and the job is refused
        # rather than answering for the wrong person.
        [string]$Account,
        [string]$Backend = (Get-BackendRoot)
    )
    $known = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Mgr } | Select-Object -First 1
    if (-not $known) { return @{ message = "Gestionnaire inconnu : $Mgr"; result = @{ ok = $false } } }
    $choisis = @($Pkgs | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" })
    # NOTHING NAMED IS NOT EVERYTHING (D131): with no package AND no -All, nothing starts.
    if ($Op -eq 'upgrade' -and -not $choisis.Count -and -not $All) {
        return @{ message = "Aucun paquet désigné : précisez les paquets, ou demandez explicitement tout le gestionnaire."
                  result = @{ ok = $false } }
    }
    $unParUn = ($choisis.Count -gt 0 -and $null -ne $known.upgOne -and @($known.upgOne).Count -gt 0)
    if ($Op -eq 'check'   -and ($known.updMode -eq 'none' -or @($known.updArgs).Count -eq 0)) {
        return @{ message = "Verification non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    if ($Op -eq 'upgrade' -and -not $unParUn -and (-not $known.upgArgs -or @($known.upgArgs).Count -eq 0)) {
        return @{ message = "Mise a jour automatique non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    if (-not $Account) { $Account = Get-StateAccount }
    if (-not $Account) {
        return @{ message = "Aucun compte identifié : une vérification de paquets se fait dans une session."
                  result = @{ ok = $false } }
    }
    $stateDir = Get-VarPath -Backend $Backend -Kind 'cache'
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    # ONE STORE PER ACCOUNT (D128): two accounts do not have the same packages, and a single file had each one
    # overwriting the other.
    $outFile = Join-Path $stateDir ('pkgupdates-' + $Account + '.json')
    # WHAT IS RUNNING IS SAID BY THE BUSY MARK (doc/progress/targeting/operations.md). This file keeps the
    # detail only: the last known result, and the packages retained, so the card says "1 package of 3".
    $entry = @{ op = $Op; startedAt = (Get-Date).ToString('s') }
    if ($Op -eq 'upgrade' -and $choisis.Count -gt 0) { $entry.sel = @($choisis) }
    if (Test-Path $outFile) {
        try {
            $j = Get-Content $outFile -Raw | ConvertFrom-Json; $e = $j.$Mgr
            if ($e -and $null -ne $e.count) {
                $entry.count = [int]$e.count; $entry.items = @($e.items)
                if ($e.pkgs) { $entry.pkgs = @($e.pkgs) }
            }
            if ($e -and $e.at) { $entry.at = "$($e.at)" }
            if ($e -and $e.last) { $entry.last = $e.last }
        } catch { }
    }
    Update-StateJson -Path $outFile -Set @{ $Mgr = $entry } | Out-Null
    $verb = if ($Op -eq 'upgrade') { 'Mise à jour' } else { 'Vérification' }
    $started = $false
    try {
        $started = [bool](Start-Operation -Module ("pkg-" + $Mgr) `
                              -Action $(if ($Op -eq 'upgrade') { 'pkg-upgrade' } else { 'pkg-check-updates' }) `
                              -Label ("$verb de " + $known.label) -Probes @('packages.probe.ps1') `
                              -Worker 'pkg-job.worker.ps1' -ArgsMap @{ mgr = $Mgr; op = $Op; pkgs = $choisis; account = $Account; all = [bool]$All } `
                              -Button $(if ($Op -eq 'upgrade') { 'pkg-list-updates' } else { '' }) -Backend $Backend)
    } catch { }
    if (-not $started) { return @{ message = "Impossible de lancer l'opération sur $($known.label)."; result = @{ ok = $false } } }
    $portee = if ($Op -eq 'upgrade' -and $unParUn) { " ($($choisis.Count) paquet(s) sélectionné(s))" } else { "" }
    @{
        message = "$verb de $($known.label) lancée en tâche de fond$portee."
        result  = @{ ok = $true; async = $true; module = ("pkg-" + $Mgr); invalidate = @('packages.probe.ps1') }
    }
}


# config.psd1, which is versioned, carries THE definition of every value.
# config.local.psd1, ignored by git and optional, overrides ONLY the values that cannot be
# generic: paths belonging to one machine. See config.local.sample.psd1.
<#
    WHAT DESCRIBES THE MACHINE IS STORED ON THE MACHINE.

    config.local.psd1 announces itself as "the settings belonging to THIS MACHINE"... and
    lives IN EVERY COPY. On a development workstation the repository had one, saying "dev",
    and the shared installation had none, so it said "prod". One machine, two contradictory
    answers to "is this a development workstation?", and the installation answering NO on the
    very machine where everything is developed.

    What describes the MACHINE now lives in one place, outside every copy:
    %ProgramData%\Sowapps\Vigie\machine.psd1. All the copies read it, none of them owns it,
    and a deployment can no longer erase it.

    config.local.psd1 keeps its role -- what belongs to THIS COPY, a test port or a path to a
    toolkit -- and remains the most specific layer.
#>
# THE SERVER TASK'S NAME, once and only once. It lived in install-service.ps1, which the
# server does not load: the restart therefore could not know who owns the process it stops.
function Get-ServiceTaskName { return 'Vigie - Serveur' }

function Get-ComputerDataRoot {
    <#
        THIS COMPUTER'S FOLDER: %ProgramData%\Sowapps\Vigie.

        It depends on NO installation, and that is what matters: whatever must survive the
        replacement -- or the disappearance -- of the installed folder is stored here, never
        under the installation itself.
    #>
    $base = $env:ProgramData
    if (-not $base) { $base = Join-Path $env:SystemDrive 'ProgramData' }
    return (Join-Path (Join-Path $base 'Sowapps') 'Vigie')
}

function Get-ComputerConfigPath {
    <#
        NOT TO BE CONFUSED with Get-MachineConfigPath, which already exists further down and
        names the settings DELIVERED in the repository (config/<file>). I had reused its
        name: my definition was silently overwritten by its own, and the call failed on a
        mandatory parameter that was not mine. Two notions, two names.
    #>
    return (Join-Path (Get-ComputerDataRoot) 'machine.psd1')
}

function Get-Config {
    param([string]$Backend = (Get-BackendRoot))
    # Merged in FOUR layers (D33), from the most general to the most specific:
    #   config/common.psd1  ->  apps/<app>/config/config.psd1  ->  machine.psd1  ->  config.local.psd1
    $cfg = @{}
    $commonPath = Join-Path (Get-RepoRoot) 'config/common.psd1'
    if (Test-Path -LiteralPath $commonPath) {
        try { (Import-PowerShellDataFile -Path $commonPath).GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value } }
        catch { throw ("config/common.psd1 illisible : " + $_.Exception.Message) }
    }
    $appCfg = Import-PowerShellDataFile -Path (Join-Path $Backend 'config/config.psd1')
    foreach ($k in $appCfg.Keys) { $cfg[$k] = $appCfg[$k] }
    # THE MACHINE, before the copy: what it declares holds for all its installations.
    $computerPath = Get-ComputerConfigPath
    if (Test-Path -LiteralPath $computerPath) {
        try {
            $computerCfg = Import-PowerShellDataFile -Path $computerPath
            foreach ($k in $computerCfg.Keys) { $cfg[$k] = $computerCfg[$k] }
        } catch { throw ("machine.psd1 illisible (" + $computerPath + ") : " + $_.Exception.Message) }
    }
    $localPath = Join-Path $Backend 'config/config.local.psd1'
    if (Test-Path -LiteralPath $localPath) {
        try { $local = Import-PowerShellDataFile -Path $localPath }
        catch { throw ("config.local.psd1 illisible (" + $localPath + ") : " + $_.Exception.Message) }
        foreach ($k in $local.Keys) { $cfg[$k] = $local[$k] }
    }
    $cfg
}

<#
    DECLARING WHAT THIS MACHINE IS.

    Written by the installation and by the deployment, when they start from a REPOSITORY: it
    is a fact observed at the moment of acting, not a setting to type in. Only the keys being
    brought are overwritten -- the rest of the file belongs to whoever wrote it.
#>
function Set-ComputerConfigValue {
    param([Parameter(Mandatory)][hashtable]$Values)
    $path = Get-ComputerConfigPath
    $dir  = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cfg = [ordered]@{}
    if (Test-Path -LiteralPath $path) {
        try {
            $previous = Import-PowerShellDataFile -Path $path
            foreach ($k in $previous.Keys) { $cfg[$k] = $previous[$k] }
        } catch { }
    }
    foreach ($k in $Values.Keys) { $cfg[$k] = $Values[$k] }

    $lines = @('@{')
    $lines += "    # Ce que cette MACHINE est, pour TOUTES ses installations de Vigie."
    $lines += "    # Ecrit par Vigie au deploiement ; modifiable a la main."
    foreach ($k in $cfg.Keys) {
        $v = $cfg[$k]
        $rendered = if ($v -is [bool]) { if ($v) { '$true' } else { '$false' } }
                 elseif ($v -is [int] -or $v -is [long]) { "$v" }
                 else { "'" + ("$v" -replace "'", "''") + "'" }
        $lines += ("    {0} = {1}" -f $k, $rendered)
    }
    $lines += '}'
    [System.IO.File]::WriteAllText($path, ($lines -join [Environment]::NewLine),
                                   (New-Object System.Text.UTF8Encoding($true)))
    return $path
}

# --- Values derived from the config: defined HERE and nowhere else -----------
# The address and the port exist once (config.psd1); every URL derives from them.
function Get-AppUrl {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    'http://{0}:{1}/' -f $Config.BindAddress, $Config.Port
}
function Get-ApiUrl {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    'http://{0}:{1}{2}' -f $Config.BindAddress, $Config.Port, $Config.ApiBase
}

# --- Optional external toolkit (administration scripts outside the repository) -------
# An empty or missing ToolsPath gives $null, and the actions concerned return a clear
# message instead of failing obscurely.
function Get-ToolsPath {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    $p = [string]$Config.ToolsPath
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    (Resolve-Path -LiteralPath $p).Path
}
function Get-AdminRoot {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    $tools = Get-ToolsPath -Backend $Backend -Config $Config
    if (-not $tools) { return $null }
    Split-Path $tools -Parent
}
# The common answer when the external toolkit is not configured (written once).
# The common answer of the actions that STILL depend on a configured toolkit path.
# Since the Windows Update locking and the VBS / HVCI switches became native, the only one
# left is "open the folder" -- and its probe no longer even offers the button when the path
# is missing. This guard covers the case where the folder disappears between the card being
# displayed and the click.
function New-ToolsMissingResult {
    @{
        message = "Aucun dossier d'outillage n'est configuré. Renseignez ToolsPath dans apps/backend-pode/config/config.local.psd1 (modèle : config.local.sample.psd1)."
        result  = @{ ok = $false }
    }
}

function Get-ApiToken {
    <#
        THE SERVER'S TOKEN LIVES AT THE SERVER'S.

        Without "-VarRoot", this function returns the token of WHOEVER RUNS IT: launched by
        the installation, under the person's account, it returned fhaza's token and the
        server answered 401. The two cards the installation asked to recompute therefore
        never were (seen on 01/09).
    #>
    param([string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    $dir  = Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'secrets'
    $file = Join-Path $dir 'api.token'
    # ITS OWN TOKEN IS HELD UNDER TARGET C7: rights set, checked at each read, reissued if a third party reached it.
    # Another account's token (-VarRoot) is only read: its rights belong to its owner.
    if (-not $VarRoot) {
        $owner = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        $token = Get-ProtectedSecretFile -Path $file -OwnerSid $owner -NewValue { [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') }
        if ($script:SecretIncident) {
            try { Write-Log -Backend $Backend -Level 'ERROR' -Name 'session' -Message ("Jeton de l'API compromis (" + $script:SecretIncident + ") : révoqué et réémis.") } catch { }
        }
        return $token
    }
    if (-not (Test-Path $file)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
        Set-Content -Path $file -Value $token -NoNewline -Encoding ASCII
    }
    (Get-Content -Path $file -Raw).Trim()
}

# --- The application's version (it changes when index.html changes) ---------
# The product's VERSION number: the installation's, or the repository's.
#
# ONE single number (D96), and it is no longer kept by hand: an archive carries its build
# stamp, a repository answers with its last TAG. A VERSION file beside the tags gave two
# possible answers to "which version runs here?".
#
# One attempt was discarded before this one: the file date's TICKS ("version
# 639231069781032063"), a change token disguised as a version, unreadable and incomparable.
# That token's role belongs to Get-AppBuildId, below.
function Get-AppVersion {
    param([string]$Backend = (Get-BackendRoot))
    # ONE definition only: the installation's stamp when it has one (a deployed archive),
    # otherwise what git says of the repository. No more VERSION file (D96).
    $m = Get-BuildStamp -Root (Get-RepoRoot)
    if ($m -and $m.version -and $m.version -ne 'sans version') { return "$($m.version)" }
    return 'inconnue'
}

# A CHANGE token, never displayed. The front end compares it with its own and reloads the
# page as soon as it differs. It must therefore move at every modification of the file
# served -- which a commit hash does not do, since it ignores uncommitted changes.
function Get-AppBuildId {
    param([string]$Backend = (Get-BackendRoot))
    $idx = Join-Path (Get-AppPath -Role 'frontend') 'index.html'
    if (Test-Path $idx) { "$((Get-Item $idx).LastWriteTimeUtc.Ticks)" } else { '0' }
}

# --- THE PRECISE IDENTITY OF A VERSION: the number AND the commit -----------
#
# "Technically I advise taking the version AND the commit." The number says what was meant
# to be delivered; the commit says what REALLY was. Two deployments of the same v0.1 can be
# twenty commits apart -- and that is exactly the case on a development workstation.
#
# The stamp is LAID INSIDE THE ARCHIVE at build time (a BUILD file, one line reading
# "version commit date"), because a deployed installation has no git repository: it cannot
# describe itself any other way.
# A REPOSITORY'S VERSION: the last TAG, and what has been committed since.
#
# There is only ONE number left (D96). A VERSION file kept by hand beside the tags meant two
# numbers to maintain -- and they drifted: the debug card showed "v0.1" while the deployed
# installation showed "v0.1.6".
#
# `git describe` says it all: "v0.1.6" when sitting exactly on the tag, "v0.1.6+6" when six
# commits have followed. That is the PRECISE version, and it maintains itself.
<#
    CALLING GIT AND KEEPING ITS REFUSAL.

    Get-GitVersion and Get-GitCommit crushed the error ("2>$null") and returned $null. On
    30/08 the card therefore announced "this workstation's repository: no version" -- without
    saying whether the folder was unreadable, whether git was missing, or whether it refused
    to work in a repository belonging to someone else. Three causes, three different
    gestures, and no trace to tell them apart.

    So the refusal is kept. It interrupts nothing -- an unknown version is not a breakdown --
    but it becomes READABLE: Get-BuildStamp reports it, and the card says it.
#>
$script:GitLastError = $null
function Invoke-Git {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)
    $script:GitLastError = $null
    $git = (Get-Command git -ErrorAction SilentlyContinue)
    if (-not $git) {
        $script:GitLastError = 'git est introuvable pour ce compte.'
        return $null
    }
    try {
        $err = @()
        $out = & $git.Source -C $Path @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $err += "$_"; } else { $_ }
        }
        <#
            THE EXIT CODE JUDGES, NOT THE ERROR STREAM.

            git speaks on stderr when everything is fine: "Everything up-to-date",
            "To https://...", "* [new tag] v0.1.67 -> v0.1.67", and every progress line of a
            fetch or a clone. Taking that for a failure made EVERY successful push report
            itself as failed -- so a deployment announced "tag posed, local only" while the
            tag had just been published, and nobody could tell a real refusal from a normal
            one. Measured on 03/09: five versions believed unpublished.

            The stderr text is kept, because a real failure explains itself there; it just
            no longer decides.
        #>
        if ($LASTEXITCODE -ne 0) {
            $script:GitLastError = if ($err.Count) { ($err | Select-Object -First 2) -join ' ' }
                                   else { "git a rendu le code $LASTEXITCODE" }
        }
        return @($out | Where-Object { "$_".Trim() })
    } catch {
        $script:GitLastError = $_.Exception.Message
        return $null
    }
}

# Git's last refusal, or $null. Read just after a call.
function Get-GitLastError { return $script:GitLastError }

function Get-GitVersion {
    param([string]$Path = (Get-RepoRoot))
    try {
        $d = @(Invoke-Git -Path $Path -Arguments @('describe', '--tags') | Select-Object -First 1)[0]
        if (-not $d) { return $null }
        $d = "$d".Trim()
        # git returns "v0.1.6-6-g813205f": we keep "v0.1.6+6", shorter to read, and the
        # commit is already displayed beside it.
        if ($d -match '^(.*)-(\d+)-g[0-9a-f]+$') { return ($Matches[1] + '+' + $Matches[2]) }
        return $d
    } catch { return $null }
}

function Get-GitCommit {
    param([string]$Path = (Get-RepoRoot), [switch]$Court)
    try {
        $forme = if ($Court) { '%h' } else { '%H' }
        $c = @(Invoke-Git -Path $Path -Arguments @('log', '-1', "--format=$forme") | Select-Object -First 1)[0]
        if ($c) { return "$c".Trim() }
    } catch { }
    return $null
}

# An installation's stamp: version, commit, date. Read from the BUILD file when there is one
# (a deployed installation), otherwise computed from git (a development workstation).
function Get-BuildStamp {
    param([string]$Root = (Get-RepoRoot))
    $f = Join-Path $Root 'BUILD'
    if (Test-Path -LiteralPath $f) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            if ($j -and $j.version) { return $j }
        } catch { }
    }
    # Outside an archive, the version is the one git knows: the last tag, plus commits.
    # IF GIT REFUSES, ITS WORD IS KEPT: "no version" does not say whether the folder is
    # unreadable, whether git is missing, or whether it refuses a repository owned by another.
    $v = Get-GitVersion -Path $Root
    $c = Get-GitCommit -Path $Root
    return [pscustomobject][ordered]@{
        version = $(if ($v) { $v } else { 'sans version' })
        commit  = $c
        at      = $null
        source  = 'depot'
        error   = $(if ($v -and $c) { $null } else { Get-GitLastError })
    }
}

<#
    THIS MACHINE'S SOURCE REPOSITORY, or $null.

    Three cases, one result:
      - we are running INSIDE a repository -> that is the one;
      - we are running from an installation that knows where it came from, and that
        repository is still there -> that is the one;
      - an ordinary machine -> $null, and the reference becomes the published version. That
        is the right question there: nobody has a repository on such a machine.
#>
function Get-LocalRepoPath {
    param([string]$Backend = (Get-BackendRoot))
    <#
        THIS COMPUTER'S REPOSITORY, or $null. WITH NO JUDGEMENT AT ALL.

        I had put a guard here: "no repository outside dev mode". It was wrong -- a
        PRODUCTION workstation may perfectly well have a local repository and deploy from it,
        or prefer the published versions. "dev" and "prod" do not answer that question.

        What does answer it already exists: UpdateSource. So this function merely says WHERE
        the repository is, if there is one; the choice belongs to Get-UpdateRoute.
    #>
    $here = Get-RepoRoot
    if (Test-PathSafe (Join-Path $here '.git')) { return $here }
    # THE PATH COMES FROM THE COMPUTER, not from the copy's BUILD: a deployment rewrites the
    # BUILD, while the computer's own declaration does not move.
    $declared = "$((Get-Config -Backend $Backend).SourcePath)"
    if (-not $declared) { return $null }
    # The repository may have been moved or deleted since: we check it is still one.
    if (-not (Test-PathSafe (Join-Path $declared '.git'))) { return $null }
    return $declared
}

<#
    D'OU VIENDRAIT LA PROCHAINE VERSION ?
<#
    WHERE WOULD THE NEXT VERSION COME FROM?

    ONE RESOLUTION, FOR EVERYONE: the "Update" button borrows it to know what to do, and the
    card borrows it to know what to compare itself WITH. It is the only way the card answers
    the real question -- "would this button change anything?" -- instead of comparing itself
    with whatever comes to hand.

    The setting already exists: UpdateSource, in the configuration.
      local   : this computer's repository (we build, and we lay the tag)
      release : the latest version published on GitHub
      clone   : a precise branch or tag, fetched from GitHub
      auto    : the repository when there is one, otherwise the published version -- the default

    IT IS NOT THE SAME QUESTION AS "dev or prod": a production workstation may have a local
    repository and deploy from it. I had confused the two.
#>
<#
    THE SERVICE CLONE -- its folder, and where it synchronises from.

    A service NEVER works inside a person's repository (D112): it has its own clone, which it
    owns, and builds from that. The path is defined here and nowhere else -- vigie-fetch used
    it under the name "$travail\depot", recomposing it.
#>
<#
    LAYING THE VERSION TAG -- AND IT IS NOT THE SERVICE'S JOB.

    The original rule: a version is marked by a TAG, only at the moment of a deployment, with
    a fixed increment. It does not change -- "I mark nothing, the current deployment in dev
    marks a version and pushes it".

    What changes is WHO runs it. A tag laid by a service account has no author, its push has
    no credentials, and git refuses to write inside a person's repository (D112). So the
    "tag-version" action calls this function IN THE REQUESTER'S SESSION, under their account,
    in their repository.

    Computing the next number lives here, in the library: both paths -- the button and the
    command line -- must give the same one.
#>
function Get-NextDeploymentTag {
    param([Parameter(Mandatory)][string]$RepoPath)
    # The base comes from the LAST TAG: the only number the project maintains (D96).
    $base = '0.1'
    $last = @(Invoke-Git -Path $RepoPath -Arguments @('describe', '--tags', '--abbrev=0') | Select-Object -First 1)[0]
    if ("$last" -match '^v?(\d+\.\d+)\.\d+$') { $base = $Matches[1] }
    $max = 0
    foreach ($t in @(Invoke-Git -Path $RepoPath -Arguments @('tag', '--list', ("v" + $base + ".*")))) {
        if ("$t" -match ('^v' + [regex]::Escape($base) + '\.(\d+)$')) {
            $x = [int]$Matches[1]
            if ($x -gt $max) { $max = $x }
        }
    }
    return ('v' + $base + '.' + ($max + 1))
}

<#
    DECLARING THE TRUSTED REPOSITORY TO GIT, AT THE SCALE OF THE COMPUTER.

    Since git 2.35, git refuses to open a repository belonging to someone else: "detected
    dubious ownership". The server app runs under a service account and the repository belongs
    to a person -- measured on 30/08, even READING is refused, so the service clone could not
    be created at all.

    The refusal is lifted for THAT path, and nothing else. It is not a write permission: the
    ACLs do not move, and the service never writes in that repository -- the tag is laid in
    the owner's session (D112).

    Laid at machine scale, where the computer already declares where its code comes from: the
    declaration and the trust are the same gesture.
#>
function Set-GitSafeDirectory {
    param([Parameter(Mandatory)][string]$RepoPath)
    <#
        TWO PATHS, NOT ONE.

        Declaring the working folder is not enough: on a LOCAL CLONE, git opens
        "<repo>/.git" and that is the path it checks -- its refusal names it word for word.
        With the single "<repo>" entry, the service clone stayed refused after being
        declared (seen on 30/08, three deployments in a row).
    #>
    $rootPath = "$RepoPath".Replace([char]92, [char]47).TrimEnd([char]47)
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory')) |
              ForEach-Object { "$_".Replace([char]92, [char]47).TrimEnd([char]47) }
    $added = $false
    foreach ($wanted in @($rootPath, ($rootPath + '/.git'))) {
        if ($declared -contains $wanted) { continue }
        $null = Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--add', 'safe.directory', $wanted)
        if (Get-GitLastError) { throw (Get-GitLastError) }
        $added = $true
    }
    return $added
}

<#
    THE RIGHT "LOG ON AS A BATCH JOB" (SeBatchLogonRight), granted or revoked through secedit. A task registered with
    a password starts only if its account holds it; the uninstall takes it back, so that no right outlives the
    account. No display here: the caller says what was done. Returns ok, changed and error.
#>
function Set-BatchLogonRight {
    param([Parameter(Mandatory)][string]$Sid, [switch]$Revoke)
    $stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $exportFile = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '.inf')
    $importFile = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '-import.inf')
    $database   = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '.sdb')
    try {
        $out = & secedit.exe /export /areas USER_RIGHTS /cfg $exportFile 2>&1
        if (-not (Test-Path -LiteralPath $exportFile)) {
            return [pscustomobject]@{ ok = $false; changed = $false; error = (@($out) -join ' ') }
        }
        $line = Get-Content -LiteralPath $exportFile | Where-Object { $_ -match '^SeBatchLogonRight' } | Select-Object -First 1
        $holders = @()
        if ($line) { $holders = @((($line -split '=', 2)[1]).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $mine = '*' + $Sid
        $has = $holders -contains $mine
        if ($Revoke) {
            if (-not $has) { return [pscustomobject]@{ ok = $true; changed = $false; error = $null } }
            $holders = @($holders | Where-Object { $_ -ne $mine })
        } else {
            if ($has) { return [pscustomobject]@{ ok = $true; changed = $false; error = $null } }
            $holders += $mine
        }
        # A MINIMAL POLICY FILE: only the line we are about.
        $content = @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1',
                     '[Privilege Rights]', ('SeBatchLogonRight = ' + ($holders -join ','))) -join [Environment]::NewLine
        [IO.File]::WriteAllText($importFile, $content, [Text.Encoding]::Unicode)
        $out = & secedit.exe /configure /db $database /cfg $importFile /areas USER_RIGHTS 2>&1
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ ok = $false; changed = $false; error = (@($out) -join ' ') } }
        return [pscustomobject]@{ ok = $true; changed = $true; error = $null }
    } catch {
        return [pscustomobject]@{ ok = $false; changed = $false; error = $_.Exception.Message }
    } finally {
        foreach ($f in @($exportFile, $importFile, $database)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

<#
    THE TRUST GIVEN TO A SOURCE IS TAKEN BACK WHEN THE SOURCE CHANGES. Set-GitSafeDirectory adds two entries per
    repository; they piled up, one pair per source ever used (seen on 13/09). This removes exactly those two.
#>
function Remove-GitSafeDirectory {
    param([Parameter(Mandatory)][string]$RepoPath)
    $rootPath = "$RepoPath".Replace([char]92, [char]47).TrimEnd([char]47)
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory')) |
                ForEach-Object { "$_".Replace([char]92, [char]47).TrimEnd([char]47) }
    $removed = $false
    foreach ($unwanted in @($rootPath, ($rootPath + '/.git'))) {
        if ($declared -notcontains $unwanted) { continue }
        $null = Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--unset-all', 'safe.directory', ('^' + [regex]::Escape($unwanted) + '$'))
        if (-not (Get-GitLastError)) { $removed = $true }
    }
    return $removed
}

<#
    THE ONLY TRUST VIGIE KEEPS IS THE DECLARED SOURCE'S. Every other pair Set-GitSafeDirectory wrote -- "<folder>" and
    "<folder>/.git", on a local path -- is taken back: a folder gone, a worktree left, a copy that is not a repository
    (answered by the owner on 14/09). A single entry belongs to another tool, and a path that is not of this computer
    cannot be judged from here. Without -KeepPath, only the pairs of folders that are gone are removed. Returns the
    folders taken back.
#>
function Remove-StaleGitSafeDirectory {
    param([string]$KeepPath = '')
    $keep = "$KeepPath".Replace([char]92, [char]47).TrimEnd([char]47)
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory') |
                  ForEach-Object { "$_".Replace([char]92, [char]47).TrimEnd([char]47) } | Where-Object { $_ })
    $removed = @()
    foreach ($entry in $declared) {
        if ($entry.EndsWith('/.git') -or $declared -notcontains ($entry + '/.git')) { continue }
        if ($entry -notmatch '^[A-Za-z]:/') { continue }
        if ($keep) { if ($entry -ieq $keep) { continue } }
        elseif (Test-Path -LiteralPath $entry) { continue }
        if (Remove-GitSafeDirectory -RepoPath $entry) { $removed += $entry }
    }
    return $removed
}

function New-DeploymentTag {
    param([Parameter(Mandatory)][string]$RepoPath, [switch]$Push)
    $tag = Get-NextDeploymentTag -RepoPath $RepoPath
    # -f is absent ON PURPOSE: a tag is not rewritten. If it already exists, this deployment
    # has already happened -- we say so and carry on.
    $null = Invoke-Git -Path $RepoPath -Arguments @('tag', '-a', $tag, '-m', ("Deploiement du " + (Get-Date -Format 'dd/MM/yyyy HH:mm')))
    $failure = Get-GitLastError
    $pushed = $false
    if (-not $failure -and $Push) {
        # A tag is only worth anything once shared. A failed push is NOT fatal: a deployment
        # must succeed even with no network.
        $null = Invoke-Git -Path $RepoPath -Arguments @('push', 'origin', $tag)
        $pushed = -not (Get-GitLastError)
    }
    return [pscustomobject][ordered]@{ tag = $tag; posed = (-not $failure); pushed = $pushed; error = $failure }
}

function Get-ServiceClonePath {
    param([string]$Backend = (Get-BackendRoot))
    Join-Path (Join-Path (Get-VarRoot -Backend $Backend) 'update') 'depot'
}

<#
    THE ADDRESS THE CLONE SYNCHRONISES FROM.

    In production: the public repository. On a development workstation: the local repository,
    so that what has just been written can be built without pushing it first. The same
    mechanism, only the address changes -- it is a setting, not a second design.
#>
function Get-UpdateRemote {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = Get-Config -Backend $Backend
    $remoteUrl = "$($cfg.UpdateRemote)".Trim()
    if ($remoteUrl) { return $remoteUrl }
    $repo = Get-LocalRepoPath -Backend $Backend
    if ($repo) { return $repo }
    return "$($cfg.RepositoryUrl)"
}

<#
    THE SERVICE CLONE IS NEVER BLOCKED. The required behaviour: doc/progress/targeting/install-update.md, section
    "Le clone du service ne se bloque jamais". It is a copy the service owns alone: it mirrors the declared source,
    it never resists it.

    On 13/09 it refused the version tags a history rewrite had moved, and deployment stopped for good. Fetching is
    therefore FORCED; if git still refuses while the source answers, the clone is rebuilt beside the old one, which
    is replaced only once the new one exists. A source that does not answer leaves the clone in place, with git's
    own words.

    Returns ok, error and recloned.
#>
function Update-ServiceClone {
    param([string]$Backend = (Get-BackendRoot), [string]$RemoteUrl = '', [switch]$Reset)
    $cloneDir = Get-ServiceClonePath -Backend $Backend
    if (-not $RemoteUrl) { $RemoteUrl = Get-UpdateRemote -Backend $Backend }
    $parentDir = Split-Path $cloneDir -Parent
    if (-not (Test-Path -LiteralPath $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

    if (-not $Reset -and (Test-PathSafe (Join-Path $cloneDir '.git'))) {
        $null = Invoke-Git -Path $cloneDir -Arguments @('rev-parse', '--git-dir')
        if (-not (Get-GitLastError)) {
            # The address may have changed -- dev and prod, another folder: it is set before fetching.
            $null = Invoke-Git -Path $cloneDir -Arguments @('remote', 'set-url', 'origin', $RemoteUrl)
            $null = Invoke-Git -Path $cloneDir -Arguments @('fetch', '--quiet', '--force', '--prune', '--prune-tags', '--tags', 'origin')
            $refused = Get-GitLastError
            if (-not $refused) {
                return [pscustomobject][ordered]@{ ok = $true; error = $null; recloned = $false }
            }
            # UNREACHABLE, OR REFUSED? Only a source that answers justifies rebuilding the clone.
            $null = Invoke-Git -Path $cloneDir -Arguments @('ls-remote', '--quiet', $RemoteUrl, 'HEAD')
            if (Get-GitLastError) {
                return [pscustomobject][ordered]@{ ok = $false; error = $refused; recloned = $false }
            }
        }
    }

    # A FRESH CLONE BESIDE THE OLD ONE: the old one goes only once the new one exists.
    $fresh = $cloneDir + '.new'
    if (Test-Path -LiteralPath $fresh) { Remove-Item -LiteralPath $fresh -Recurse -Force -ErrorAction SilentlyContinue }
    $null = Invoke-Git -Path $parentDir -Arguments @('clone', '--quiet', $RemoteUrl, $fresh)
    $cloneError = Get-GitLastError
    if ($cloneError) {
        Remove-Item -LiteralPath $fresh -Recurse -Force -ErrorAction SilentlyContinue
        return [pscustomobject][ordered]@{ ok = $false; error = $cloneError; recloned = $false }
    }
    try {
        if (Test-Path -LiteralPath $cloneDir) { Remove-Item -LiteralPath $cloneDir -Recurse -Force -ErrorAction Stop }
        Move-Item -LiteralPath $fresh -Destination $cloneDir -ErrorAction Stop
    } catch {
        return [pscustomobject][ordered]@{ ok = $false; error = $_.Exception.Message; recloned = $false }
    }
    return [pscustomobject][ordered]@{ ok = $true; error = $null; recloned = $true }
}
<#
    SYNCHRONISING THE CLONE, AND SAYING WHAT IT HOLDS.

    "If it does not update the service's repository first, it is no use: it has to see the
    commits of the dev repository." Exactly -- comparing against a stale clone compares
    nothing. So it is refreshed BEFORE being read, with a short respite: from a local
    repository a fetch costs a few hundred milliseconds, but a card must not pay that at every
    display. The "Refresh" button (-Force) forces it.

    Returns the stamp (version, commit) of the reference aimed at, or $null with git's error.
#>
function Sync-ServiceClone {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force, [int]$TtlSeconds = 300)
    $cloneDir  = Get-ServiceClonePath -Backend $Backend
    $remoteUrl = Get-UpdateRemote -Backend $Backend
    $wantedRef    = "$((Get-Config -Backend $Backend).UpdateRef)".Trim()
    $stampFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'clone-sync.json'

    <#
        THE RESPITE FOLLOWS THE DISTANCE, NOT A CONSTANT.

        Five minutes are justified for a remote repository: a fetch goes over the network.
        From a LOCAL REPOSITORY -- a development workstation -- it costs a few hundred
        milliseconds, and five minutes mostly mean the card goes on showing "up to date" long
        after a commit. Added to the probe's own respite, the gap could reach ten minutes.
    #>
    #>
    if ($remoteUrl -and $remoteUrl -notmatch '^[a-z]+://' -and (Test-PathSafe $remoteUrl)) { $TtlSeconds = 30 }

    if (-not $Force -and (Test-Path -LiteralPath $stampFile)) {
        try {
            $j = Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalSeconds
            if ($age -lt $TtlSeconds -and "$($j.remote)" -eq $remoteUrl) {
                return [pscustomobject][ordered]@{ path = $cloneDir; remote = $remoteUrl; ref = "$($j.ref)"
                                                   version = "$($j.version)"; commit = "$($j.commit)"
                                                   error = $(if ($j.error) { "$($j.error)" } else { $null }) }
            }
        } catch { }
    }

    $failure = $null
    # THE CLONE IS NEVER BLOCKED: forced, then recloned if git still refuses (Update-ServiceClone).
    $update = Update-ServiceClone -Backend $Backend -RemoteUrl $remoteUrl
    if (-not $update.ok) { $failure = $update.error }
    $tagVersion = $null; $headCommit = $null
    if (Test-PathSafe (Join-Path $cloneDir '.git')) {
        # With no reference imposed, we follow the remote's default branch.
        $target = $(if ($wantedRef) { $wantedRef } else { 'origin/HEAD' })
        $headCommit = @(Invoke-Git -Path $cloneDir -Arguments @('rev-parse', $target) | Select-Object -First 1)[0]
        if (-not $headCommit -and -not $wantedRef) {
            $headCommit = @(Invoke-Git -Path $cloneDir -Arguments @('rev-parse', 'origin/main') | Select-Object -First 1)[0]
        }
        if ($headCommit) {
            $tagVersion = @(Invoke-Git -Path $cloneDir -Arguments @('describe', '--tags', "$headCommit") | Select-Object -First 1)[0]
            if ($tagVersion -and $tagVersion -match '^(.*)-(\d+)-g[0-9a-f]+$') { $tagVersion = ($Matches[1] + '+' + $Matches[2]) }
        } else {
            $failure = Get-GitLastError
        }
    }

    <#
        A FAILURE IS NOT RECORDED FOR FIVE MINUTES.

        The respite exists so a successful fetch is not redone at every display. A FAILURE,
        on the other hand, is often repaired by one gesture -- declaring the repository
        trusted to git, for instance: freezing it would make the card lie for five more
        minutes when everything is already back in order. It is returned, not frozen.
    #>
    if (-not $failure) {
        try {
            (@{ at = (Get-Date).ToUniversalTime().ToString('o'); remote = $remoteUrl; ref = $wantedRef
                version = $tagVersion; commit = $headCommit; error = $null } | ConvertTo-Json) |
                Set-Content -LiteralPath $stampFile -Encoding UTF8
        } catch { }
    }

    return [pscustomobject][ordered]@{ path = $cloneDir; remote = $remoteUrl; ref = $wantedRef
                                       version = $tagVersion; commit = $headCommit; error = $failure }
}

function Get-UpdateRoute {
    param([string]$Backend = (Get-BackendRoot))
    $choice = 'auto'
    try {
        $c = "$((Get-Config -Backend $Backend).UpdateSource)".Trim().ToLowerInvariant()
        if ($c -in @('auto', 'local', 'release', 'clone')) { $choice = $c }
    } catch { }
    $repo = Get-LocalRepoPath -Backend $Backend
    # "LOCAL" IS NO LONGER A ROUTE FOR THE SERVICE (D112): building inside a person's
    # repository means writing tags there under a service identity, and being refused by git.
    # A declared repository therefore becomes the clone's ADDRESS, not the place of work.
    if ($choice -eq 'local') { $choice = 'clone' }
    if ($choice -eq 'auto')  { $choice = $(if ($repo) { 'clone' } else { 'release' }) }
    return [pscustomobject][ordered]@{ route = $choice; repo = $repo }
}

# Writes the stamp: called by the building of the archive, once.
function Write-BuildStamp {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Version, [string]$Commit)
    $o = [ordered]@{ version = $Version; commit = $Commit
                     at = (Get-Date).ToUniversalTime().ToString('o'); source = 'archive' }
    ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $Root 'BUILD') -Encoding UTF8
}

# Is the shared installation up to date against this repository? It returns a readable
# observation, never a bare boolean: "the same", "12 commits behind", "unknown".
<#
    IS THE SHARED INSTALLATION UP TO DATE -- AND AGAINST WHAT?

    The reference is not the same everywhere, and that was the whole defect: the comparison
    was always against "Get-RepoRoot", which IS the installation when the server app runs
    inside it.

      - a repository exists on the workstation -> reference "repository": commits compared;
      - otherwise -> reference "published": on an ordinary machine the only thing that makes
        sense is the latest published version.

    Nothing is guessed: when it cannot be settled, `same` is $null and the caller SAYS so.
    "Up to date" by default is the worst of verdicts -- it reassures while knowing nothing.
#>
function Compare-SharedInstall {
    param([string]$Backend = (Get-BackendRoot), [switch]$Force)
    $installed = Get-SharedInstallPath
    if (-not $installed) { return $null }
    $there   = Get-BuildStamp -Root $installed
    $route   = Get-UpdateRoute -Backend $Backend
    $behind  = $null
    $here    = $null
    $same    = $null
    $reference = 'aucune'
    $remote  = $null

    # WE COMPARE AGAINST WHAT THE BUTTON WOULD FETCH, never against anything else.
    if ($route.route -eq 'clone') {
        # AND WE REFRESH BEFORE READING: comparing against a stale clone compares nothing.
        $sync = Sync-ServiceClone -Backend $Backend -Force:$Force
        $reference = 'clone'
        $remote = $sync.remote
        # WHAT ARRIVES, as it will read on the installation: "v1.1.5+3" in dev, since a deployment tags nothing (D123).
        $here = [pscustomobject][ordered]@{ version = $(if ($sync.version) { "$($sync.version)" } else { 'sans version' })
                                            commit = $sync.commit; at = $null; source = 'clone'
                                            error = $sync.error }
        if ($sync.commit -and $there.commit) {
            if ($sync.commit -eq $there.commit) { $behind = 0; $same = $true }
            else {
                $same = $false
                # The counting happens IN THE CLONE: it is the one holding both commits.
                $c = @(Invoke-Git -Path $sync.path -Arguments @('rev-list', '--count', ($there.commit + '..' + $sync.commit)) |
                       Select-Object -First 1)[0]
                if ("$c" -match '^\d+$') { $behind = [int]$c }
            }
        }
    } else {
        $published = Get-LatestPublishedVersion -Backend $Backend
        if ($published) {
            $reference = 'publiee'
            $here = [pscustomobject][ordered]@{ version = $published; commit = $null; at = $null
                                                source = 'release'; error = $null }
            $same = (Test-SameVersion -A $published -B "$($there.version)")
        }
    }

    [pscustomobject][ordered]@{
        path = $installed; here = $here; there = $there; behind = $behind
        reference = $reference; repo = $route.repo; remote = $remote; same = $same
    }
}

# Do two numbers name the same version? "v0.1.26" and "0.1.26": yes.
# "v1.1.6-dev1" and "v1.1.6+1" too: archives built before 15/09 wrote the commits count as "-devN" into their stamp.
function Test-SameVersion {
    param([string]$A, [string]$B)
    $left  = ("$A".TrimStart('v', 'V').Trim()) -replace '-dev(\d+)$', '+$1'
    $right = ("$B".TrimStart('v', 'V').Trim()) -replace '-dev(\d+)$', '+$1'
    return ($left -eq $right)
}

<#
    THE LATEST PUBLISHED VERSION, or $null.

    Asked for at most once per half-day: the answer rarely changes, and a card must not
    depend on the network to display. Offline, GitHub quota reached, private repository: it
    returns $null, and the card says "not checked yet" rather than inventing a verdict.

    THE FAILURE IS RECORDED TOO: without that, an offline machine would call GitHub again at
    every display.
#>
function Get-LatestPublishedVersion {
    param([string]$Backend = (Get-BackendRoot))
    $f = Get-VarPath -Backend $Backend -Kind 'cache' -File 'published-version.json'
    if (Test-Path -LiteralPath $f) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalHours
            if ($age -lt 12) { return $(if ($j.version) { "$($j.version)" } else { $null }) }
        } catch { }
    }
    $version = $null
    try {
        $repo = "$((Get-Config -Backend $Backend).Repository)"
        if (-not $repo) { $repo = 'Cartman34/vigie-windows' }
        $rep = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/releases/latest') `
                                 -Headers @{ 'User-Agent' = 'Vigie'; 'Accept' = 'application/vnd.github+json' } `
                                 -TimeoutSec 8 -ErrorAction Stop
        if ($rep -and $rep.tag_name) { $version = "$($rep.tag_name)" }
    } catch { }
    try {
        (@{ at = (Get-Date).ToUniversalTime().ToString('o'); version = $version } | ConvertTo-Json) |
            Set-Content -LiteralPath $f -Encoding UTF8
    } catch { }
    return $version
}

<#
    RESTARTING THE SERVER APP -- ONE SINGLE IMPLEMENTATION.

    It lived inside the "server-restart" action. The update needed it too, and copying it
    would have made two paths for one gesture: the day one is fixed, the other lies. So it
    lives here, and both call the same one.

    ONE CANNOT KILL AND RESTART ONESELF: a dying process runs nothing more. A DETACHED
    RELAUNCHER does it -- it stops the server, waits for the port to be released, then starts
    the next one. It waits for the PORT and not for a delay: with two servers on the same
    port, it is the second that dies.

    -Wait: wait until no operation holds the machine any more. Deliberately with no time
    limit -- an operation that lasts has a reason to last, and interrupting it is precisely
    what we want to avoid. That is how the update restarts itself: it asks for the restart as
    it begins, and the relauncher waits until it has finished.

    THE PID COMES FROM THE PORT, not from $PID: the caller is not always the server. The
    start script, on the other hand, is SAID by the caller -- it is the one of the running
    installation, not necessarily the one of the repository being spoken from.
#>
<#
    STOPPING THE SERVER APP, AND OBSERVING THAT IT IS STOPPED.

    Its files were modified while it was running, and it was only stopped afterwards, when
    putting the task back into service. So code was overwritten under a living process -- it
    carried on with the old one in memory, and the slightest file re-read along the way mixed
    two versions.

    A STOP IS OBSERVED. The port being released is a fact: we wait for it, unlike a start,
    which is never watched for. And the TASK is stopped first -- otherwise Windows considers
    it running and restarts it under our feet.

    Returns $true when nothing listens any more at the end.
#>
<#
    THE INSTALLATION LOCK -- ONE AT A TIME.

    Two simultaneous installations tread on each other: one stops what the other has just
    started, one copies while the other backs up. Preventing it is imperative.

    THE LOCK SAYS WHO HOLDS IT -- a process id and a time -- and a lock whose process no
    longer exists is IGNORED. Without that, an installation interrupted brutally would
    condemn the workstation until someone deleted a file by hand, which we forbid ourselves:
    what is missing is missing from the installation, never from a command to type.

    It lives with the computer's declaration, outside the shared installation: it must
    survive a copy and stay readable by both entry points.
#>
function Get-InstallLockPath {
    Join-Path (Split-Path (Get-ComputerConfigPath) -Parent) 'install.lock'
}

function Get-InstallLockHolder {
    $path = Get-InstallLockPath
    if (-not (Test-PathSafe $path)) { return $null }
    $held = $null
    try { $held = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $held -or -not $held.pid) { return $null }
    # DOES THE PROCESS STILL EXIST? It is the only question that matters: an orphan lock
    # protects nothing, it blocks.
    $alive = $false
    try { $alive = [bool](Get-Process -Id ([int]$held.pid) -ErrorAction Stop) } catch { }
    if (-not $alive) { return $null }
    return $held
}

function Lock-Install {
    $held = Get-InstallLockHolder
    if ($held) { return $null }
    $path = Get-InstallLockPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $mine = [ordered]@{ pid = $PID; account = (Get-ProcessAccount); at = (Get-Date).ToUniversalTime().ToString('o') }
    ($mine | ConvertTo-Json -Compress) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Unlock-Install {
    # WE ONLY REMOVE OUR OWN. Removing someone else's would allow exactly what we have just
    # forbidden.
    $path = Get-InstallLockPath
    if (-not (Test-PathSafe $path)) { return }
    try {
        $held = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($held -and [int]$held.pid -ne $PID) { return }
    } catch { }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

<#
    IS THE DEPLOYMENT POSSIBLE? -- quick checks, before stopping anything at all.

    Vigie was stopped, and only then did we discover that the copy would not go through: a
    locked folder, a full disk. Those two questions are answered in a few milliseconds, and
    save stopping for nothing.

    We do not try to foresee EVERY failure -- only those that cost less to check than to
    suffer. Returns $null when all is well, the reason otherwise.
#>
function Test-DeploymentPossible {
    param([Parameter(Mandatory)][string]$Destination, [long]$NeededBytes = 0)
    $parent = Split-Path $Destination -Parent
    if (-not (Test-PathSafe $parent)) { return ("dossier d'accueil introuvable : " + $parent) }

    # WRITING: we try, which is the only proof. A rights test would lie -- inheritance,
    # redirections, an antivirus that blocks at the real write.
    $probe = Join-Path $parent ('.vigie-write-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Set-Content -LiteralPath $probe -Value 'x' -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch { return ("écriture refusée dans " + $parent + " : " + $_.Exception.Message) }

    <#
        ROOM: TWO PLACES, AND NO LONGER NECESSARILY THE SAME DISK.

        The new version is laid at the destination, and the previous one is kept as a backup
        -- which now lives at machine scale, not under the installation. Counting "twice over,
        on the destination disk" was right as long as both were in the same place; with a
        destination on another disk it reserved twice the room where only one is needed, and
        nothing where the backup is actually going to be written.
    #>
    if ($NeededBytes -gt 0) {
        foreach ($lieu in @($parent, (Get-InstallBackupRoot))) {
            try {
                $rootPath = $lieu
                while ($rootPath -and -not (Test-Path -LiteralPath $rootPath)) { $rootPath = Split-Path $rootPath -Parent }
                if (-not $rootPath) { continue }
                $drive = (Get-Item -LiteralPath $rootPath).PSDrive
                if ($drive -and $null -ne $drive.Free -and $drive.Free -lt $NeededBytes) {
                    return ("espace disque insuffisant sur " + $drive.Name + " : " +
                            (Format-ByteSize -Bytes $drive.Free) + " libres, " +
                            (Format-ByteSize -Bytes $NeededBytes) + " nécessaires")
                }
            } catch { }
        }
    }
    return $null
}

<#
    BACK UP, CHECK, RESTORE.

    The copy overwrites the installation in place: if it fails halfway, the old version is
    already destroyed and we would start an incomplete installation.

    The backup lives OUTSIDE the shared installation -- otherwise it would double the volume
    and the next backup would back it up -- and carries the version it holds, so one knows
    what is being restored. It is removed as soon as the copy is checked: it exists only for
    the length of the risk.
#>
function Get-InstallBackupRoot {
    <#
        OUTSIDE THE INSTALLATION, ALWAYS.

        The backup used to live under the server app's var/, that is, INSIDE the folder it
        serves to restore: the safety net was tied to the trapeze. Three ways to lose it: a
        copy overwriting the folder takes the backup with it, an uninstall does the same, and
        the setup.cmd of the installed folder cannot restore what that same folder held.

        So it lives at MACHINE scale, where machine.psd1 already lives: the source folder may
        disappear, the installation may be replaced, the previous version stays.
    #>
    Join-Path (Get-ComputerDataRoot) 'backup'
}

function Backup-Install {
    param([Parameter(Mandatory)][string]$Source, [string]$Backend = (Get-BackendRoot))
    if (-not (Test-PathSafe $Source)) { return $null }
    # THE OLD LOCATION DOES NOT SURVIVE AN INSTALLATION. It was under the server app's var/;
    # leaving it there means keeping a whole copy of Vigie that nothing reads any more and
    # nobody thinks to erase. The installation cleans it up, being idempotent -- no command
    # to type by hand.
    $ancien = Join-Path (Get-VarRoot -Backend $Backend) 'backup'
    if (Test-Path -LiteralPath $ancien) {
        Remove-Item -LiteralPath $ancien -Recurse -Force -ErrorAction SilentlyContinue
    }
    $stamp = Get-BuildStamp -Root $Source
    $name = 'installation-' + $(if ($stamp.version) { "$($stamp.version)" -replace '[^\w\.\+-]', '_' } else { 'inconnue' })
    $root = Get-InstallBackupRoot -Backend $Backend
    $dest = Join-Path $root $name
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $dest -Recurse -Force -ErrorAction Stop
    return $dest
}

<#
    IS THE COPY VALID? We do not ask whether it "seems" done: we read the version stamp we
    were expecting, and the files without which Vigie does not start.
#>
function Test-InstallCopy {
    param([Parameter(Mandatory)][string]$Destination, [string]$ExpectedVersion)
    foreach ($needed in @('apps/backend-pode/start.ps1', 'apps/client/client.ps1', 'apps/backend-pode/lib/common.ps1')) {
        if (-not (Test-PathSafe (Join-Path $Destination $needed))) { return ("fichier manquant : " + $needed) }
    }
    if ($ExpectedVersion) {
        $stamp = Get-BuildStamp -Root $Destination
        if (-not (Test-SameVersion -A "$($stamp.version)" -B $ExpectedVersion)) {
            return ("version posée « " + "$($stamp.version)" + " » au lieu de « " + $ExpectedVersion + " »")
        }
    }
    return $null
}

<#
    EXTRACT AN ARCHIVE, AND RETURN THE FOLDER THAT WILL BE DEPLOYED.

    The archive carries a root folder "vigie-<version>": it is ITS contents that are
    installed, not one more folder inside Program Files.
#>
function Expand-InstallArchive {
    param([Parameter(Mandatory)][string]$Zip)
    if (-not (Test-PathSafe $Zip)) { throw ("archive introuvable : " + $Zip) }
    $temp = Join-Path $env:TEMP ('vigie-deploy-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $temp -Force
    $roots = @(Get-ChildItem -Path $temp -Directory)
    if ($roots.Count -eq 1) { return $roots[0].FullName }
    return $temp
}

<#
    COPY TO THE SHARED INSTALLATION, WITHOUT LOSING THE COMPUTER'S SETTINGS.

    The settings laid on this machine survive the deployment: set aside, then put back.
    Overwriting them at every delivery would be a regression at every update.

    var/ does not exist in the installation -- the data live in the profiles (D97) -- but it
    is not deleted if someone has created one: we only destroy what we know how to replace.
#>
<#
    WHAT THE SOURCE NO LONGER HAS, REMOVED WHEREVER IT IS.

    Walks the installation and the source side by side. A folder the source does not have goes whole; inside a folder
    both have, each file the source lacks goes. `var/` is never entered: it is the data.

    It is a function of its own so the rule can be read -- and tested -- without running an installation.
#>
function Remove-InstallSurplus {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Destination) -or -not (Test-PathSafe $Source)) { return }
    foreach ($entry in @(Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue)) {
        if ($entry.Name -eq 'var') { continue }
        $mirror = Join-Path $Source $entry.Name
        if (-not (Test-Path -LiteralPath $mirror)) {
            Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }
        # BOTH SIDES HAVE IT: a folder is walked, a file is left to be overwritten by the copy that follows.
        if ($entry.PSIsContainer) { Remove-InstallSurplus -Source $mirror -Destination $entry.FullName }
    }
}

function Copy-InstallFrom {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Source)) { throw ("source introuvable : " + $Source) }

    $kept = $null
    $configDir = Join-Path $Destination 'config'
    if (Test-PathSafe $configDir) {
        $kept = Join-Path $env:TEMP ('vigie-cfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $kept -Force | Out-Null
        foreach ($pattern in @('*.local.*', 'actions.policy.json')) {
            Get-ChildItem -Path $configDir -File -Filter $pattern -ErrorAction SilentlyContinue |
                ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $kept -Force }
        }
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    <#
        WHAT THE SOURCE NO LONGER HAS, THE INSTALLATION NO LONGER KEEPS.

        Copy-Item only adds and overwrites: a file dropped upstream stayed on disk for ever. On 30/09 the client app's
        folder was renamed, the old one survived in the installation, the account's scheduled task went on naming the
        old script -- it still existed, so nothing was declared broken -- and TWO client apps ran at once on the same
        account, each with its icon and its heartbeat.

        AT EVERY DEPTH, and that took a second lesson. The first version dropped only at the top level and inside
        apps/, which left everything below untouched: on 06/10 an action deleted from the source and pushed stayed
        installed and ANSWERING after a successful deployment. An action is a door with rights of its own, and
        removing it from the source is the gesture that deletes it; the same goes for a probe, which would keep
        producing a card, and for a worker, which would stay launchable. "L'installation partagee porte exactement
        le commit de la source" (targeting/install-update.md) was therefore false below two levels.

        var/ is the one thing kept: it is the data, not the code. The settings of this machine are set aside before
        and put back after, so they survive this. Nothing outside the destination is ever touched.
    #>
    Remove-InstallSurplus -Source $Source -Destination $Destination
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force -ErrorAction Stop

    if ($kept) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Get-ChildItem -Path $kept -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $configDir -Force
        }
        Remove-Item -LiteralPath $kept -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Restore-Install {
    param([Parameter(Mandatory)][string]$Backup, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-PathSafe $Backup)) { throw "aucune sauvegarde à restaurer" }
    Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'var' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item -Path (Join-Path $Backup '*') -Destination $Destination -Recurse -Force -ErrorAction Stop
}

# Get-PortListener lives in scripts/lib/tcp-ports.ps1, loaded at the top of this file.

# WHY THE SERVER DOES NOT ANSWER, as far as a client app can measure it alone (CORE-CLIENT): short lines, the likeliest
# first, empty when nothing measurable explains it. On 17/09 the client app said only "server unreachable" while the memory,
# the network ports and the desktop heap of the computer were exhausted -- all of it readable from any account.
# Each reading is a direct call to Windows (a few milliseconds each, the log filtered by the log service); the netsh
# range reading (0.2 s) is paid only when the ports are counted. Never throws.
function Get-ServerTroubleReasons {
    param([int]$Port = 0, [string]$Backend = (Get-BackendRoot))
    $reasons = @()
    try {
        $memory = Get-MemoryStatus
        if ($memory -and $memory.CommitLimit -gt 0) {
            $pct = [math]::Round(100 * $memory.CommitUsed / $memory.CommitLimit)
            if ($pct -ge 90) { $reasons += (Get-Label 'client.raison-memoire' $pct) }
        }
    } catch { }
    try {
        foreach ($proto in 'tcp', 'udp') {
            $range = Get-EphemeralPortRange -Protocol $proto
            if (-not $range) { continue }
            $usage = Get-EphemeralPortUsage -Protocol $proto -Start $range.Start -Count $range.Count
            if ($usage -and $usage.Used -ge 0.8 * $usage.Limit) { $reasons += (Get-Label 'client.raison-ports' $proto.ToUpper() $usage.Used $usage.Limit) }
        }
    } catch { }
    try {
        # What Windows logged in the last 30 minutes that stops a server from answering.
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Tcpip', 'Win32k', 'Microsoft-Windows-Resource-Exhaustion-Detector'
                                                     Id = 4231, 4266, 704, 2004; StartTime = (Get-Date).AddMinutes(-30) } -ErrorAction Stop)
        foreach ($provider in @($events | Group-Object ProviderName)) {
            $at = @($provider.Group | Sort-Object TimeCreated -Descending)[0].TimeCreated.ToString('HH:mm')
            switch ($provider.Name) {
                'Tcpip'  { $reasons += (Get-Label 'client.raison-journal-ports' $at) }
                'Win32k' { $reasons += (Get-Label 'client.raison-journal-bureau' $at) }
                default  { $reasons += (Get-Label 'client.raison-journal-memoire' $at) }
            }
        }
    } catch { }
    try {
        if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }
        $listener = Get-PortListener -Port $Port
        if ($listener) {
            $count = 1 + @(Get-ProcessDescendants -ProcessId ([int]$listener.OwningProcess)).Count
            $limit = 20
            try { $limit = [int](Get-ModuleSetting -Unit 'debug' -Key 'SelfMaxProcesses' -Backend $Backend) } catch { }
            if ($count -gt $limit) { $reasons += (Get-Label 'client.raison-processus' $count) }
        }
    } catch { }
    return $reasons
}

<#
    IS THIS PROCESS OURS? Asked before anything is ever stopped.

    Stopping was decided on ONE clue: whoever holds port 47600. Nothing said it was Vigie. A port is taken by the
    first comer, so a program that grabbed 47600 before Vigie -- or after it died -- would have been killed by an
    update, in silence. The owner's rule is absolute: nothing is stopped without his word, and the exception he
    granted on 29/09 covers VIGIE'S OWN processes, so we must be able to prove it is one.

    The proof is the command line: a PowerShell running a script that lives under our installation. An unreadable
    command line proves nothing, so it answers NO -- and nothing is stopped.
#>
function Test-VigieProcess {
    param([Parameter(Mandatory)][int]$ProcessId, [string]$Backend = (Get-BackendRoot))
    if ($ProcessId -le 0) { return $false }
    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        if (-not $p) { return $false }
        if ("$($p.Name)" -notin @('pwsh.exe', 'powershell.exe')) { return $false }
        $line = "$($p.CommandLine)"
        if (-not $line) { return $false }
        # BOTH AT ONCE: our installation AND one of our scripts. The path alone is not enough -- it travels as an
        # argument in command lines that are not ours at all, and a check that says yes too easily is worse than none.
        $roots = @("$Backend".TrimEnd([char]92, [char]47))
        try { $roots += (Split-Path $roots[0] -Parent) } catch { }
        $under = $false
        foreach ($root in @($roots | Where-Object { $_ })) {
            if ($line -like ('*' + $root + '*')) { $under = $true; break }
        }
        if (-not $under) { return $false }
        foreach ($ours in @('server.ps1', 'start.ps1', 'client.ps1', 'protocol.ps1', '.worker.ps1', '.resident.ps1')) {
            if ($line -like ('*' + $ours + '*')) { return $true }
        }
        return $false
    } catch { return $false }
}

function Stop-ServerApp {
    param([string]$Backend = (Get-BackendRoot), [int]$Port = 0, [int]$TimeoutSec = 30)
    if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }

    try { Stop-ScheduledTask -TaskName (Get-ServiceTaskName) -ErrorAction SilentlyContinue } catch { }
    $held = Get-PortListener -Port $Port
    if ($held) {
        $owner = [int]$held.OwningProcess
        if (Test-VigieProcess -ProcessId $owner -Backend $Backend) {
            try { Stop-Process -Id $owner -Force -ErrorAction Stop } catch { }
        } else {
            # NOT OURS, NOT OUR CALL. The port is taken by something else: we say it and we leave it alone.
            try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                    "port $Port tenu par le PID $owner, qui n'est pas un processus de Vigie : rien n'est arrete") } catch { }
        }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-PortListener -Port $Port)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Start-ServerRelauncher {
    param(
        [Parameter(Mandatory)][string]$StartScript,
        [int]$Port = 0,
        [switch]$Wait,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-PathSafe $StartScript)) { throw ("start.ps1 introuvable : " + $StartScript) }
    if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }

    $target = $null
    $c = Get-PortListener -Port $Port
    if ($c) { $target = [int]$c.OwningProcess }
    if (-not $target) { throw ("Aucune app serveur n'ecoute sur le port " + $Port + ".") }
    # THE RELAUNCHER CARRIES THIS ID AND STOPS IT: it must be ours, or there is nothing to relaunch here.
    if (-not (Test-VigieProcess -ProcessId $target -Backend $Backend)) {
        throw ("Le port " + $Port + " est tenu par le PID " + $target + ", qui n'est pas un processus de Vigie : rien n'est arrete.")
    }

    $pwsh = $null
    try { $pwsh = (Get-Process -Id $PID).Path } catch { }
    if (-not $pwsh) { $pwsh = 'pwsh.exe' }

    # The folder of the busy marks comes from Get-VarPath, never from a recomposed path:
    # one definition, and it lives here.
    $runDir = Get-VarPath -Backend $Backend -Kind 'run'
    $waitBlock = if ($Wait) { @"
`$run = '$runDir'
while (`$true) {
    `$marques = @(Get-ChildItem -LiteralPath `$run -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)
    if (-not `$marques.Count) { break }
    Start-Sleep -Seconds 3
}
"@ } else { '' }

    <#
        THE SERVER BELONGS TO ITS TASK: WE RESTART THE TASK.

        I used to launch start.ps1 myself. The result, on 30/08: the update killed the server
        and the successor never held -- launched from an elevated session, it ran under THE
        WRONG ACCOUNT and died with it. Vigie stayed dead, the task "Ready", the port silent.

        The task, on the other hand, knows what it launches: the right account, with no open
        session, with its own rights. We stop it and start it again. start.ps1 run directly
        remains only for the case where there is no task -- a server started by hand, in
        development.
    #>
    $taskName = Get-ServiceTaskName
    $byTask = $false
    try { $byTask = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction Stop) } catch { }

    $stopSnippet = if ($byTask) { @"
try { Stop-ScheduledTask -TaskName '$taskName' -ErrorAction SilentlyContinue } catch { }
try { Stop-Process -Id $target -Force -ErrorAction SilentlyContinue } catch { }
"@ } else { @"
try { Stop-Process -Id $target -Force -ErrorAction SilentlyContinue } catch { }
"@ }

    $startSnippet = if ($byTask) { @"
Start-ScheduledTask -TaskName '$taskName'
"@ } else { @"
Start-Process -FilePath $(ConvertTo-PSLiteral $pwsh) -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$(ConvertTo-PSLiteral (ConvertTo-ProcessArgument $StartScript)) -WindowStyle Hidden
"@ }

    $portLib = ConvertTo-PSLiteral (Join-Path (Join-Path (Get-RepoRoot) 'scripts') (Join-Path 'lib' 'tcp-ports.ps1'))
    $script = @"
Start-Sleep -Milliseconds 400
. $portLib
$waitBlock
$stopSnippet
`$fin = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt `$fin) {
    `$occupe = Get-PortListener -Port $Port
    if (-not `$occupe) { break }
    Start-Sleep -Milliseconds 300
}
$startSnippet
"@

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pwsh
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $script)) {
        [void]$psi.ArgumentList.Add($a)
    }
    [void][System.Diagnostics.Process]::Start($psi)
    return $target
}

# --- Logging ----------------------------------------------------------------
# --- Runtime data: apps/<app>/var/ (the Symfony convention) --------------------
# Everything the app GENERATES or manages locally lives under var/: cache, logs, state,
# generated secrets. None of it is versioned.
# These paths are written HERE and nowhere else: they used to be recomposed by hand in eight
# files -- actions, probes, workers.
# Is the installation WRITABLE by the account running? (D65)
#
# Two situations, and a single rule to tell them apart: writing for real.
#   - a DEV repository, or an installation in a personal space: var/ is written in place, as
#     it always has been -- nothing changes;
#   - a SHARED installation (Program Files): a standard account does not write there. Its
#     runtime data then go to its profile, where it is at home.
# We do not GUESS from the path: we try to write, once, and remember.
$script:VarRootCache = $null
function Get-VarRoot {
    param([string]$Backend = (Get-BackendRoot))
    # THE CACHE IS PER APPLICATION, not global.
    #
    # It took no account whatever of its argument: the first call froze THE root, and every
    # one after it got that root back whatever -Backend was asked for. The client app
    # therefore wrote its heartbeat into the server's var/, where the order sender did not
    # look for it -- "restart impossible, client app already stopped" while it was running
    # (seen on 28/08). Each app keeps its files under ITS var/ (D33), so the cache has to be
    # indexed by application.
    if ($null -eq $script:VarRootCache) { $script:VarRootCache = @{} }
    $cle = "$Backend".TrimEnd([char]92, [char]47).ToLowerInvariant()
    if ($script:VarRootCache.ContainsKey($cle)) { return $script:VarRootCache[$cle] }

    # INSTALLED IN PROGRAM FILES: the data go into the account's profile, NEVER beside the
    # program. The server runs elevated, so it COULD write there -- and that is precisely the
    # trap: every account would then share the same token, the same cache and the same
    # settings, when each must have its own (D65). The write test below would see nothing,
    # since it would succeed.
    $programmes = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($p in $programmes) {
        if ("$Backend".StartsWith("$p", [StringComparison]::OrdinalIgnoreCase)) {
            $script:VarRootCache[$cle] = Join-Path (Get-UserConfigDir) 'var'
            return $script:VarRootCache[$cle]
        }
    }

    # Elsewhere -- a development repository, a personal folder: in place when it can be
    # written to, otherwise in the profile.
    $surPlace = Join-Path $Backend 'var'
    $ok = $false
    try {
        if (-not (Test-Path -LiteralPath $surPlace)) {
            New-Item -ItemType Directory -Path $surPlace -Force -WhatIf:$false | Out-Null
        }
        $temoin = Join-Path $surPlace ('.ecriture-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        [IO.File]::WriteAllText($temoin, 'x')
        Remove-Item -LiteralPath $temoin -Force -ErrorAction SilentlyContinue
        $ok = $true
    } catch { $ok = $false }
    $script:VarRootCache[$cle] = if ($ok) { $surPlace } else { Join-Path (Get-UserConfigDir) 'var' }
    return $script:VarRootCache[$cle]
}

<#
    IS A CARD THE SAME FOR EVERYONE?

    Most are: disk space, updates and the firewall do not depend on who is looking. But the
    accounts card writes "(vous)" beside one name -- and that rendering goes into
    state-cache.json, which is SHARED. So the first person to open Vigie left their "vous"
    there, and it was served to everyone else.

    A probe declares it in its module.psd1:  PerAccount = $true.

    Declaring beats guessing: one cannot read inside a rendering to tell whether it depends on
    the person, and assuming it for all of them would cost one recomputation per account for
    nothing. check-probes verifies that the ones speaking of the requester have declared it.
#>
$script:ProbePerAccount = @{}
function Test-ProbeIsPerAccount {
    param([Parameter(Mandatory)][string]$ProbeFile)
    $folder = Split-Path $ProbeFile -Parent
    if ($script:ProbePerAccount.ContainsKey($folder)) { return $script:ProbePerAccount[$folder] }
    $answer = $false
    try {
        $decl = Join-Path $folder 'module.psd1'
        if (Test-Path -LiteralPath $decl) {
            $d = Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop
            $answer = [bool]$d.PerAccount
        }
    } catch { }
    $script:ProbePerAccount[$folder] = $answer
    return $answer
}

<#
    THE CACHE KEY: the probe's name, and the account when the rendering depends on it.

    "accounts.probe.ps1@Famille" and "accounts.probe.ps1@fhaza" live side by side in the same
    file without treading on each other. With no requester identified the key is "@?": an
    anonymous session has an entry of its own, where nobody is "vous".
#>
function Get-ProbeCacheKey {
    param([Parameter(Mandatory)][string]$ProbeFile, [string]$Account)
    $leaf = Split-Path $ProbeFile -Leaf
    if (-not (Test-ProbeIsPerAccount -ProbeFile $ProbeFile)) { return $leaf }
    return ($leaf + '@' + $(if ($Account) { $Account } else { '?' }))
}

function Get-VarPath {
    param(
        [string]$Backend = (Get-BackendRoot),
        <#
            ANOTHER ACCOUNT'S ROOT, when one must write somewhere other than at home.

            The var of an installation inside Program Files lives in the profile of the
            account that RUNS (D65): the service's, for the server app. The installation, on
            the other hand, runs under the person who clicked -- so it cleaned THEIR cache
            while the card went on reading the service's. Get-AccountVarRoot gives the right
            root, and it goes through here rather than being recomposed by hand.
        #>
        [string]$VarRoot,
        # 'history': series of measurements. Distinct from 'cache': a lost cache recomputes
        # itself, a lost history does not.
        # 'run': LIVE state, valid for the length of a process (background-task marks). It is
        # not backed up and not read back after a restart.
        [Parameter(Mandatory)][ValidateSet('cache','log','secrets','history','run')][string]$Kind,
        [string]$File
    )
    $dir = Join-Path $(if ($VarRoot) { $VarRoot } else { Get-VarRoot -Backend $Backend }) $Kind
    # TEST-PATHSAFE, AND A CREATION THAT DOES NOT SHOUT. On ANOTHER account's var, Test-Path
    # THROWS instead of answering "no", and New-Item writes four red blocks -- when all we
    # were doing was reading a path to erase a file inside it. A caller without the right
    # will notice by finding nothing there, without polluting the log.
    if (-not (Test-PathSafe $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false -ErrorAction SilentlyContinue | Out-Null
    }
    if ($File) { return (Join-Path $dir $File) }
    return $dir
}

function Get-LogDir {
    param([string]$Backend = (Get-BackendRoot))
    $d = Get-VarPath -Backend $Backend -Kind 'log'
    # -WhatIf:$false: creating the log folder is plumbing, not an operation the user
    # simulates. Without it, -WhatIf prevents any logging at all.
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force -WhatIf:$false | Out-Null }
    $d
}
function Write-Log {
    param(
        # AN EMPTY LINE IS A LINE. The installation log relays what each sub-script displays,
        # blank layout lines included: without this permission, every breath produced a
        # "Cannot bind argument to parameter Message" in the transcript -- red noise on an
        # installation that was going perfectly well.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [string]$Level = 'INFO',
        [string]$Name  = 'app',
        [string]$Backend = (Get-BackendRoot),
        # Write WITHOUT displaying again: the line is already on screen, we only want to keep it.
        [switch]$NoEcho
    )
    $dir  = Get-LogDir -Backend $Backend
    $file = Join-Path $dir ($Name + '_' + (Get-Date -Format 'yyyyMMdd') + '.log')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $file -Value $line -Encoding UTF8 } catch { }

    # THE SCREEN AND THE FILE DO NOT SAY THE SAME THING, and that is deliberate. The file
    # keeps the timestamp and the level: it is the one read back weeks later. The screen
    # speaks the language of every other script (scripts/lib/console-ui.ps1).
    #
    # WHY: on 28/08 an installation step failed; its ERROR came out grey among twenty grey
    # lines, and the user could not see it. A log level that does not stand out on screen is
    # no use at all.
    #
    # The fallback exists because common.ps1 is loaded by scripts that have no need of the
    # display -- the server, the probes: the dependency is not imposed on them.
    if ($NoEcho) { return }
    $hasUi = [bool](Get-Command Write-Fail -ErrorAction SilentlyContinue)
    switch ($Level) {
        'ERROR' { if ($hasUi) { Write-Fail $Message } else { Write-Host $line -ForegroundColor Red } }
        'WARN'  { if ($hasUi) { Write-Warn $Message } else { Write-Host $line -ForegroundColor Yellow } }
        default { if ($hasUi) { Write-Info $Message } else { Write-Host $line } }
    }
}


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
# ASKS EVERY CLIENT APP TO QUIT ON ITS OWN, through the order it reads each second in its run folder: it logs
# "arret de l'app cliente (ordre stop)", acknowledges, and leaves. Until 19/09 an update ended the tasks and killed what was
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

# The data root of ANOTHER account. The path was copied by hand into the diagnosis; one
# definition beats an agreement between two copies.
<#
    THE ACCOUNT THE SERVER APP RUNS UNDER.

    It was written in install-service.ps1, which is not the library: everything that must
    write or read AT ITS HOME -- the installation cleaning the card's cache, for instance --
    would have copied the name. One definition, as for the task's name.
#>
function Get-ServiceAccountName { 'VigieService' }

<#
    WHAT IS WRONG WITH THE SERVICE ACCOUNT'S PROFILE, or $null. Every error is handled and surfaced
    (doc/progress/targeting/components.md, situation "broken state"): a profile Windows opened as temporary, declared
    corrupted, or whose registration left a ".bak" copy behind runs the service on data that are not its own -- no
    clone, no cache, no secrets -- and nothing said so until 14/09.
#>
function Get-ServiceProfileAilment {
    param([string]$Account = (Get-ServiceAccountName))
    $sid = $null
    try { $sid = Get-AccountSid -Account $Account } catch { }
    if (-not $sid) { return $null }
    $userProfile = $null
    try { $userProfile = Get-CimInstance Win32_UserProfile -Filter ("SID='" + $sid + "'") -ErrorAction Stop }
    catch { return ("son profil ne se lit pas : " + $_.Exception.Message) }
    # No profile yet: the server task has never started; the deployment card says so through its task.
    if (-not $userProfile) { return $null }
    # Win32_UserProfile.Status: 1 temporary, 8 corrupted.
    $status = [int]$userProfile.Status
    if ($status -band 1) { return "Windows l'a ouvert en profil temporaire : le service ne travaille pas sur ses propres données" }
    if ($status -band 8) { return "Windows déclare son profil corrompu" }
    if ((Split-Path "$($userProfile.LocalPath)" -Leaf) -like 'TEMP*') { return ("son profil pointe vers un dossier temporaire : " + $userProfile.LocalPath) }
    $backupKey = 'HKLM:' + [char]92 + (@('SOFTWARE', 'Microsoft', 'Windows NT', 'CurrentVersion', 'ProfileList', ($sid + '.bak')) -join [char]92)
    if (Test-Path -LiteralPath $backupKey) { return "l'inscription de son profil a une copie « .bak » : un chargement a échoué" }
    return $null
}

function Get-AccountVarRoot {
    param([Parameter(Mandatory)][string]$Account)
    $profil = Join-Path $env:SystemDrive (Join-Path 'Users' $Account)
    if (-not (Test-PathSafe $profil)) { return $null }
    return (Join-Path (Join-Path (Join-Path (Join-Path $profil 'AppData') 'Local') 'Sowapps') 'Vigie/var')
}

<#
    THE ACCOUNT RUNNING THIS PROCESS. Not "the person".

    The distinction did not matter while the server app ran under somebody's account:
    $env:USERNAME happened to be right BY ACCIDENT. Since it runs as a service under
    "VigieService", every place that said $env:USERNAME meaning "the person in front of the
    screen" names the service -- and on 29/08 the Accounts card therefore showed "VOUS" on
    VigieService, and took it out of the list of technical accounts.

    Two notions, two functions, never mixed again:
      - Get-ProcessAccount   : WHO RUNS. True for the client app, which IS the person, and
                               for scripts launched by hand.
      - Get-ActionRequester  : WHO ASKS, read from the session cookie. That is the person, on
                               the server app's side, and it is what is almost always needed.

    check-probes now refuses $env:USERNAME anywhere else: whoever next writes that shortcut
    will be told before delivering, not three weeks later.
#>
function Get-ProcessAccount {
    return "$env:USERNAME"
}

# A local account's SID, by its name. Returns $null when the account does not exist.
function Get-AccountSid {
    param([Parameter(Mandatory)][string]$Account)
    try { return (New-Object System.Security.Principal.NTAccount($Account)).Translate(
                    [System.Security.Principal.SecurityIdentifier]).Value } catch { return $null }
}

<#
    Is the secret presented really this account's?

    The account's file is RE-READ, with its ACL check: if its rights have moved since it was
    laid, Get-AccountSecret throws and we refuse. A secret a third party may have read is
    worth nothing, and refusing it loudly beats accepting it in silence.
#>
function Test-AccountSecret {
    param(
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][string]$Secret
    )
    if (-not $Secret) { return $false }
    $varRoot = Get-AccountVarRoot -Account $Account
    if (-not $varRoot) { return $false }
    $sid = Get-AccountSid -Account $Account
    if (-not $sid) { return $false }
    $known = $null
    try { $known = Get-AccountSecret -VarRoot $varRoot -OwnerSid $sid } catch {
        try { Write-Log -Level 'ERROR' -Name 'session' -Message ("Secret du compte " + $Account + " refuse : " + $_.Exception.Message) } catch { }
        return $false
    }
    if (-not $known) { return $false }
    return ($known -ceq $Secret)
}

# --- Where tickets and sessions live ----------------------------------------------------
#
# In the SERVER's var, under a closed ACL: a session identifier is authentication information
# just as a secret is. The folder is laid with the same function as the secrets, and
# therefore with the same rigour.
function Get-SessionStorePath {
    param([string]$Kind = 'sessions', [string]$Backend = (Get-BackendRoot))
    $dir = Join-Path (Join-Path (Get-VarRoot -Backend $Backend) 'auth') $Kind
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
            Set-SecretFolderAcl -Path (Split-Path $dir -Parent) -OwnerSid $me
        } catch { }
    }
    return $dir
}

# AGE IS COUNTED IN SECONDS, NOT IN DATES. A date written to JSON comes back as a DateTime
# object, already converted into the local culture: "08/28/2026 20:43:31". Re-parsing it
# failed, the exception went unnoticed, and the age stayed empty -- which is to say a ticket
# NEVER expired. A number has neither culture nor surprise type.
function Get-EpochSeconds {
    return [double]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0)
}

function New-RandomId {
    $bytes = [byte[]]::new(24)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
}

# An opening ticket, valid once and for thirty seconds.
function New-OpenTicket {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $id = New-RandomId
    $file = Join-Path (Get-SessionStorePath -Kind 'tickets' -Backend $Backend) ($id + '.json')
    (@{ account = $Account; at = (Get-EpochSeconds) } | ConvertTo-Json -Compress) |
        Out-File -FilePath $file -Encoding UTF8
    return $id
}

# Consumes a ticket: returns the account, or $null. The file is DELETED in every case -- a
# ticket presented once, valid or stale, must not be able to serve again.
function Use-OpenTicket {
    param([Parameter(Mandatory)][string]$Ticket, [string]$Backend = (Get-BackendRoot))
    if ($Ticket -notmatch '^[A-Za-z0-9]{8,64}$') { return $null }
    $file = Join-Path (Get-SessionStorePath -Kind 'tickets' -Backend $Backend) ($Ticket + '.json')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $data = $null
    try { $data = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { }
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    if (-not $data) { return $null }
    if (((Get-EpochSeconds) - [double]$data.at) -gt 30) { return $null }
    return "$($data.account)"
}

# Opens a session and returns its identifier, the one the cookie will carry.
<#
    THE OPENING URL: THE ONLY WAY TO ASK FOR ONE.

    The gesture is always the same -- read THEIR account's secret, present it to the server,
    receive a single-use address -- and it was written in two places: in the client app and in
    the question tool. Two copies, so two behaviours to keep in step: they already did not
    have the same timeout.

    ONE CAN ONLY ASK FOR ONESELF. The secret lives in the account's profile, with an explicit
    ACL: nobody else reads it, and that is precisely what makes it prove an identity. To open
    a session in another account's name, one has to be inside THEIR session.

    Returns $null if anything at all fails -- the caller then opens the page without
    identification rather than refusing to open it.
#>
function Get-OpenUrl {
    param(
        [string]$Account = (Get-ProcessAccount),
        [string]$BaseUrl,
        [int]$TimeoutSec = 10,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not $BaseUrl) { $BaseUrl = Get-AppUrl -Backend $Backend }
    $BaseUrl = $BaseUrl.TrimEnd('/')
    $secret = $null
    try {
        $secret = Get-AccountSecret -VarRoot (Get-AccountVarRoot -Account $Account) `
                                    -OwnerSid (Get-AccountSid -Account $Account) -Create
    } catch { return $null }
    if (-not $secret) { return $null }
    $body = @{ account = $Account; secret = $secret } | ConvertTo-Json -Compress
    $reply = $null
    try {
        $reply = Invoke-RestMethod -Method Post -Uri ($BaseUrl + '/api/v1/session/ticket') `
                                   -ContentType 'application/json' -Body $body `
                                   -Headers @{ Origin = $BaseUrl } -TimeoutSec $TimeoutSec
    } catch { return $null }
    if (-not ($reply -and $reply.ok -and $reply.ticket)) { return $null }
    return ($BaseUrl + '/?t=' + $reply.ticket)
}

<#
    OPENING A SESSION WITH THE SERVER APP, AND RETURNING WHAT IT TAKES TO QUESTION IT.

    The whole path, the client app's own: the account's secret -> the opening address -> the
    cookie. It was written in the question tool; the client app needs it too, to READ THE
    STATE.

    WHY IT NEEDS IT. It used to read the cache file directly -- and since the server runs
    under a service account, that file lives in THAT account's profile: the client app was
    looking at a file nobody writes, and had not raised a single notification since 28/08.
    Going through the API solves both: it sees what the server sees, with its own account's
    rights, without reading in someone else's home.

    Returns a session object usable with Invoke-RestMethod, or $null.
#>
function Open-VigieSession {
    param(
        [string]$Account = (Get-ProcessAccount),
        [string]$BaseUrl,
        [int]$TimeoutSec = 10,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not $BaseUrl) { $BaseUrl = Get-AppUrl -Backend $Backend }
    $BaseUrl = $BaseUrl.TrimEnd('/')
    $url = Get-OpenUrl -Account $Account -BaseUrl $BaseUrl -TimeoutSec $TimeoutSec -Backend $Backend
    if (-not $url) { return $null }

    $handler = $null; $client = $null
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        # WE DO NOT FOLLOW THE REDIRECTION, and we do not let .NET manage the cookies: the
        # cookie arrives on the 302 response, and the next one no longer carries it.
        $handler.UseCookies = $false
        $handler.AllowAutoRedirect = $false
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $url)
        $req.Headers.Add('Origin', $BaseUrl)
        $req.Headers.ConnectionClose = $true
        $rep = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $value = $null
        if ($rep.Headers.Contains('Set-Cookie')) {
            foreach ($c in @($rep.Headers.GetValues('Set-Cookie'))) {
                if ("$c" -match 'vigie_session=([^;]+)') { $value = $Matches[1] }
            }
        }
        if (-not $value) { return $null }
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $session.Cookies.Add((New-Object System.Net.Cookie('vigie_session', $value, '/', '127.0.0.1')))
        return $session
    } catch { return $null }
    finally {
        if ($client)  { try { $client.Dispose() } catch { } }
        if ($handler) { try { $handler.Dispose() } catch { } }
    }
}

function New-AccountSession {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $id = New-RandomId
    $file = Join-Path (Get-SessionStorePath -Kind 'sessions' -Backend $Backend) ($id + '.json')
    (@{ account = $Account; at = (Get-EpochSeconds) } | ConvertTo-Json -Compress) |
        Out-File -FilePath $file -Encoding UTF8
    return $id
}

<#
    THE ACCOUNT BEHIND A SESSION, or $null.

    A SESSION DOES NOT EXPIRE. It used to, after 24 hours: past that delay the window stayed
    open but belonged to nobody -- "vous" disappeared from the accounts card and the actions
    no longer knew who was asking, with nothing announcing it. What is disposable is the
    OPENING URL: 30 seconds, one single presentation. What it leaves behind, the identity,
    must last, or one has to ask for another every time on a workstation where the person has
    not changed.

    A session ends otherwise: the file is deleted, or the account stops being enabled.
#>
function Get-SessionAccount {
    param([Parameter(Mandatory)][string]$SessionId, [string]$Backend = (Get-BackendRoot))
    if ($SessionId -notmatch '^[A-Za-z0-9]{8,64}$') { return $null }
    $file = Join-Path (Get-SessionStorePath -Kind 'sessions' -Backend $Backend) ($SessionId + '.json')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $data = $null
    try { $data = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { return $null }
    return "$($data.account)"
}

# --- The contract's object factories ----------------------------------------
# A process name -> the READABLE name, the one Windows itself displays.
#
# "csrss" means nothing to anybody (pointed out by the owner on 25/08). The real name is in
# the executable's version information (FileDescription): "Client Server Runtime Process",
# "Windows Explorer", "Google Chrome". It is read from the FILE and not from the process:
# protected processes (csrss, lsass) refuse access to their main module, while their file
# reads without trouble.
#
# The technical name is not thrown away: it is kept in brackets, because that is the one
# found again in the Task Manager.
$script:AppNameCache = @{}
function Get-AppDisplayName {
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [string]$Path,
        # Without -Complet, only the readable name is returned (for a short field value).
        [switch]$Complet
    )
    $cle = $ProcessName.ToLower()
    if (-not $script:AppNameCache.ContainsKey($cle)) {
        $desc = $null
        $exe = $Path
        if (-not $exe) {
            # A protected process: its path is refused, but a system binary of the same name
            # reads perfectly well. We do not GUESS: we check the file exists.
            $candidat = Join-Path $env:SystemRoot ("System32\" + $ProcessName + ".exe")
            if (Test-Path -LiteralPath $candidat) { $exe = $candidat }
        }
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            try {
                $d = "$([System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileDescription)".Trim()
                if ($d -and $d -ne $ProcessName) { $desc = $d }
            } catch { }
        }
        $script:AppNameCache[$cle] = $desc
    }
    $lisible = $script:AppNameCache[$cle]
    if (-not $lisible) {
        # For want of better, the process name is displayed -- but with a CAPITAL: on screen
        # it is a proper noun ("Claude", not "claude"), and a card's value always begins
        # with a capital.
        if ($ProcessName.Length -gt 1) { return $ProcessName.Substring(0,1).ToUpper() + $ProcessName.Substring(1) }
        return $ProcessName.ToUpper()
    }
    if ($Complet) { return "$lisible ($ProcessName)" }
    return $lisible
}

# What is said of an application when its name is hovered: the ABSOLUTE path first, as the
# owner asked, then publisher and version, then the real processes behind the name.
#
# HOMONYMS: two processes of the same name may come from TWO different binaries -- two
# installations of chrome, a fake "svchost" laid somewhere other than System32. We do not
# choose in the user's place: every distinct location is named, and the fact that there is
# more than one is announced.
function Get-AppInfoTip {
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [string[]]$Paths = @(),
        [int[]]$Ids = @()
    )
    $lines = @()
    $cleanPaths = @($Paths | Where-Object { $_ } | Sort-Object -Unique)
    if ($cleanPaths.Count -eq 0) {
        # A protected process (csrss, lsass...): Windows refuses its path. If a system binary
        # of the same name EXISTS, it is named -- while saying it is the expected binary and
        # not the path read; the nuance matters to whoever is hunting an impostor.
        $sys = Join-Path $env:SystemRoot ("System32\" + $ProcessName + ".exe")
        if (Test-Path -LiteralPath $sys) {
            $lines += "Chemin non communiqué (processus protégé par Windows)."
            $lines += "Binaire système attendu : $sys"
            $cleanPaths = @($sys)
        } else {
            $lines += "Chemin : non communiqué (processus protégé par Windows)."
        }
    } elseif ($cleanPaths.Count -eq 1) {
        $lines += "$($cleanPaths[0])"
    } else {
        $lines += "$($cleanPaths.Count) emplacements différents pour ce nom :"
        foreach ($c in ($cleanPaths | Select-Object -First 4)) { $lines += "- $c" }
    }
    $ref = @($cleanPaths | Select-Object -First 1)[0]
    if ($ref -and (Test-Path -LiteralPath $ref)) {
        try {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ref)
            $editeur = "$($vi.CompanyName)".Trim()
            $version = "$($vi.FileVersion)".Trim()
            $detail = @($editeur, $version | Where-Object { $_ }) -join ' · '
            if ($detail) { $lines += $detail }
        } catch { }
    }
    $pids = @($Ids | Where-Object { $_ -gt 0 })
    if ($pids.Count -eq 1) { $lines += "1 processus (PID $($pids[0]))" }
    elseif ($pids.Count -gt 1) {
        $seen = @($pids | Select-Object -First 6) -join ', '
        $nextArgs = if ($pids.Count -gt 6) { '…' } else { '' }
        $lines += "$($pids.Count) processus (PID $seen$nextArgs)"
    }
    $lines -join "`n"
}

# --- THE DISK TREE, LEVEL BY LEVEL (D60, revised on 26/08) --------------------
# The interface NEVER receives the whole tree: it asks for ONE level, and asks again when the
# user unfolds. The owner's requirement -- a complete tree is a JSON that grows without
# limit, and a card carrying what nobody will look at.
#
# Two sources, in this order:
#   1. the CACHE of the last analysis (var/cache/diskscan.json): already computed, free;
#   2. a PARTIAL COMPUTATION on demand, when the level asked for lies beyond what the
#      analysis kept. Only the sub-tree asked for is then walked.
# What is computed on demand is remembered (diskscan-levels.json): unfolding the same folder
# twice does not walk it twice.
$script:SEP = [string][char]92

# The total size of a folder, in one .NET pass. Bounded in time: past that, what we have is
# returned while SAYING so (partial), rather than keeping the interface waiting.
function Measure-FolderQuick {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutMs = 8000
    )
    $opts = [System.IO.EnumerationOptions]::new()
    $opts.IgnoreInaccessible    = $true
    $opts.RecurseSubdirectories = $true
    $opts.AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
    $size = [long]0; $nb = 0; $partial = $false
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    try {
        $di = [System.IO.DirectoryInfo]::new($Path)
        foreach ($f in $di.EnumerateFiles('*', $opts)) {
            $size += [long]$f.Length
            $nb++
            if (($nb % 4096) -eq 0 -and $chrono.ElapsedMilliseconds -gt $TimeoutMs) { $partial = $true; break }
        }
    } catch { }
    [pscustomobject]@{ Size = $size; Files = $nb; Partial = $partial }
}

# The DIRECT children of $Path, from the largest to the smallest.
function Get-DiskTreeLevel {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Backend = (Get-BackendRoot),
        [int]$Top = 0
    )
    $stateFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan.json'
    $State = $null
    if (Test-Path -LiteralPath $stateFile) {
        try { $State = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { }
    }
    if (-not $State -or -not $State.tree) { throw "Aucune analyse disponible : lancez d'abord l'analyse de l'espace." }

    $rootPath = if ($State.result -and $State.result.root) { "$($State.result.root)" } else { "$($State.scan.root)" }
    $total  = [long]$State.tree.s
    if ($Top -le 0) {
        $Top = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanTop' -Backend $Backend)
        if ($Top -le 0) { $Top = 10 }
    }

    # The path asked for must belong to the analysis: we do not explore the disk on a
    # client's request, we explore the tree already analysed.
    $plein = $Path
    try { $plein = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { }
    if (-not $plein.ToLower().StartsWith($rootPath.ToLower())) { throw "Hors de l'analyse en cours : $Path" }

    $pct = { param($o) if ($total -gt 0) { ('{0:N1}' -f ([double]$o / $total * 100)) } else { '0,0' } }

    # 1) Does the analysis cache already hold this level?
    $noeud = $State.tree
    $coupe = $rootPath.TrimEnd([char]92).Length
    $reste = $plein.Substring([Math]::Min($coupe, $plein.Length)).Trim([char]92)
    $trouve = $true
    if ($reste) {
        foreach ($pas in ($reste.Split([char]92))) {
            if (-not $pas) { continue }
            $suivant = @($noeud.k | Where-Object { "$($_.n)" -eq $pas })[0]
            if (-not $suivant) { $trouve = $false; break }
            $noeud = $suivant
        }
    }
    if ($trouve -and $noeud -and $noeud.k -and @($noeud.k).Count) {
        $enfants = @($noeud.k | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | ForEach-Object {
            [ordered]@{
                n = "$($_.n)"; path = (Join-Path $plein "$($_.n)")
                s = [long]$_.s; size = (Format-ByteSize ([long]$_.s))
                pct = (& $pct ([long]$_.s)); f = [int]$_.f; more = $true
            }
        })
        $files = @($noeud.t | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | ForEach-Object {
            [ordered]@{ n = "$($_.n)"; size = (Format-ByteSize ([long]$_.s)) }
        })
        $autres = $null
        if ($noeud.o) { $autres = [ordered]@{ c = [int]$noeud.o.c; size = (Format-ByteSize ([long]$noeud.o.s)) } }
        return [pscustomobject]@{ path = $plein; source = 'analyse'; children = $enfants; files = $files; others = $autres }
    }

    # 2) A level the analysis did not keep: a PARTIAL COMPUTATION, bounded to this folder.
    $memo = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan-levels.json'
    $cle  = $plein.ToLower()
    try {
        if (Test-Path -LiteralPath $memo) {
            $m = Get-Content -LiteralPath $memo -Raw | ConvertFrom-Json
            $e = $m.PSObject.Properties | Where-Object { $_.Name -eq $cle } | Select-Object -First 1
            if ($e -and $e.Value) {
                return [pscustomobject]@{ path = $plein; source = 'memoire'; children = @($e.Value.children); files = @($e.Value.files); others = $null }
            }
        }
    } catch { }

    $opts = [System.IO.EnumerationOptions]::new()
    $opts.IgnoreInaccessible    = $true
    $opts.RecurseSubdirectories = $false
    $opts.AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
    $di = $null
    try { $di = [System.IO.DirectoryInfo]::new($plein) } catch { }
    if (-not $di -or -not $di.Exists) { throw "Dossier introuvable : $plein" }

    $sous = @()
    try { $sous = @($di.EnumerateDirectories('*', $opts)) } catch { }
    $calcules = @(foreach ($d in $sous) {
        $mes = Measure-FolderQuick -Path $d.FullName
        [ordered]@{
            n = $d.Name; path = $d.FullName; s = [long]$mes.Size
            size = (Format-ByteSize ([long]$mes.Size)); pct = (& $pct ([long]$mes.Size))
            f = [int]$mes.Files; more = $true; partial = [bool]$mes.Partial
        }
    })
    $calcules = @($calcules | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $Top)

    $fic = @()
    try {
        $fic = @($di.EnumerateFiles('*', $opts) | Sort-Object Length -Descending | Select-Object -First $Top | ForEach-Object {
            [ordered]@{ n = $_.Name; size = (Format-ByteSize ([long]$_.Length)) }
        })
    } catch { }

    try {
        Update-StateJson -Path $memo -Depth 12 -Set @{ $cle = @{ children = $calcules; files = $fic; at = (Get-Date).ToUniversalTime().ToString('s') } } | Out-Null
    } catch { }
    return [pscustomobject]@{ path = $plein; source = 'calcul'; children = $calcules; files = $fic; others = $null }
}

# A size in bytes -> readable text (one decimal: "12,4 Go"). The single point where sizes are
# formatted: a card showing raw bytes teaches nothing.
function Format-ByteSize {
    param([Parameter(Mandatory)][long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} To' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} Go' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} Mo' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} Ko' -f ($Bytes / 1KB)) }
    return ("$Bytes o")
}

function New-Field {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][ValidateSet('bool','number','text','date')][string]$Kind,
        [string]$Unit,
        [ValidateSet('ok','warn','error','neutral')][string]$Status,
        [string]$Help,
        [string]$FixAction,
        [string]$Guide,
        # A STRUCTURED detail: @{ columns = @('...'); rows = @(@('...'), ...) }.
        # A list of several dozen lines formatted into a string stays unreadable wherever it
        # is displayed. A table is taken in at a glance; text is not.
        [hashtable]$Table,
        # A foldable TREE (S13b/D60): @{ n; path; size; pct; k = @(...) }. A table flattens
        # what is hierarchical; a tree is walked branch by branch, which is exactly the
        # question being asked ("where is the room going?").
        $Tree,
        # THE PROGRESS OF AN OPERATION IN PROGRESS, in a block of its own under the field, only while it runs:
        # @{ phase; percent; index; total; title; itemPercent; bytesDone; bytesTotal; since } (contract Field.progress).
        [hashtable]$Progress,
        # THE REASON OF AN ALERT, one short line, carried as is into the desktop notification (CORE-ERRORS).
        [string]$Reason,
        <#
            -Scope: WHOSE INFORMATION THIS FIELD CARRIES, when it is not its card's (D128).

            'machine' or 'user'. A 'mixed' card requires one on EVERY field; on a 'machine' or
            'user' card it is written only for the exception.
        #>
        [ValidateSet('machine','user')][string]$Scope,
        # THE IDENTITY OF THE FACT STATED, when the displayed value is a rendering of it and not the fact itself.
        # Never displayed. It exists for whoever WATCHES the field: a watcher that compares values alone cannot tell
        # "the same fact, worded differently" from "a new fact". Measured on 05/10: the last session's line reads
        # the last session's line names its end time one way on the day and another way afterwards, so at the first
        # computation past midnight the client app took a twelve-hour-old session for a session that had just ended,
        # and opened its recap at 06:45. Every field whose value carries a date, a duration or any wording that
        # drifts with time owes an identity.
        [string]$Identity
    )
    $f = [ordered]@{ key = $Key; label = $Label; value = $Value; kind = $Kind }
    if ($Reason) { $f['reason'] = $Reason }
    if ($Identity) { $f['identity'] = $Identity }
    if ($Scope) { $f['scope'] = $Scope }
    if ($Unit)      { $f['unit']      = $Unit }
    if ($Status)    { $f['status']    = $Status }
    if ($Help)      { $f['help']      = $Help }
    if ($FixAction) { $f['fixAction'] = $FixAction }
    if ($Guide)     { $f['guide']     = $Guide }
    if ($Table -and $Table.rows -and @($Table.rows).Count) { $f['table'] = $Table }
    if ($Tree) { $f['tree'] = $Tree }
    if ($Progress -and $Progress.phase) { $f['progress'] = $Progress }
    [pscustomobject]$f
}
function New-Action {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        # THE CARD THAT CARRIES THIS ACTION, when the resource it takes depends on it: "pkg-choco" turns "paquets"
        # into "paquets-choco", so checking pip during an upgrade of Chocolatey stays possible. Optional: an action
        # whose resource does not depend on its card has nothing to say here.
        [string]$Module,
        [switch]$Confirm,
        [string]$Help,
        # 'dialog': opens a CHOICE window inside the application (a list to tick).
        # Distinct from 'manual', which opens EXTERNAL SOFTWARE, and from 'confirm', which
        # only asks a yes or no. The three did not look different enough on screen.
        [ValidateSet('immediate','confirm','manual','dialog')][string]$Kind,
        # SEVERITY: what the action represents, independently of the FORM it takes.
        # `kind` chooses the ICON -- how it happens: yes/no, a choice window, external
        # software; `severity` chooses the COLOUR, what it is worth:
        #   neutral = nothing at stake (grey) | info = consulting, opening (blue)
        #   fix     = it corrects something (green)
        # The two were conflated: the colour followed the form, which teaches nothing.
        [ValidateSet('neutral','info','fix')][string]$Severity,
        # The label displayed WHILE it runs. It must say what is happening -- "Mise à jour…",
        # not "En cours…". The ellipsis is RESERVED for an action under way: a label at rest
        # never carries one.
        [string]$BusyLabel,
        # TWO distinct confirmations before running. Reserved for gestures that close the
        # user's work in progress or touch the whole machine: one click too many must not be
        # enough.
        [switch]$ConfirmTwice,
        # --- WHAT A CONFIRMATION MUST SAY (D91) ---------------------------------
        # "This action modifies your system" informs nobody. Before saying yes, one wants
        # to know WHAT CHANGES on the machine, WHY one would do it, and WHETHER one can go
        # back. Surface technical details are welcome: a service name, a registry key, a
        # restart required.
        #
        #   -Impact     : what concretely changes, here and now.
        #   -Usage      : in which case one uses it (the intention).
        #   -Reversible : how to go back -- or why one cannot.
        [string]$Impact,
        [string]$Usage,
        [string]$Reversible,

        <#
            -From / -To: THE ACTION MOVES FROM ONE STATE TO ANOTHER, and it is SHOWN.

            "From v0.1.25 to v0.1.25+1" stuck at the end of a sentence reads badly and gets
            lost. Two values and an arrow are taken in at a glance -- and that is what one
            wants to know before clicking.

            -FromNote / -ToNote carry the detail under each value: a commit, a date. Both
            optional: in production the version number says enough.
        #>
        [string]$From,
        [string]$To,
        [string]$FromNote,
        [string]$ToNote,

        <#
            -Steps: WHAT IS GOING TO HAPPEN, IN ORDER.

            An asynchronous action chains several phases -- deploy, restart, check. Listing
            them in a sentence drowns them; showing them aligned says at a glance how many
            there are, and which one finishes the job.

            The last is the STATE ARRIVED AT, not a phase: it stands apart.
        #>
        [string[]]$Steps = @()
    )
    $a = [ordered]@{ id = $Id; label = $Label }
    if ($Confirm -or $ConfirmTwice) { $a['confirm'] = $true }
    if ($ConfirmTwice) { $a['confirmTwice'] = $true }
    if ($Help)    { $a['help']    = $Help }
    if ($Impact)     { $a['impact']     = $Impact }
    if ($Usage)      { $a['usage']      = $Usage }
    if ($Steps -and $Steps.Count) { $a['steps'] = @($Steps) }
    if ($From -or $To) {
        $a['transition'] = @{ from = "$From"; to = "$To"; fromNote = "$FromNote"; toNote = "$ToNote" }
    }
    if ($Reversible) { $a['reversible'] = $Reversible }
    $a['kind'] = if ($Kind) { $Kind } elseif ($Confirm) { 'confirm' } else { 'immediate' }
    # A reasonable default: opening something informs, the rest is neutral. A corrective
    # action must declare itself -- one does not guess that it repairs.
    # Default: 'info'. A button IS an action: it does something, and its icon deserves a
    # colour. Grey used to be the default, so every ordinary action looked inert; it is now
    # DECLARED, for the rare case where nothing is at stake.
    # 'fix' is declared too: one does not guess that an action repairs.
    $a['severity'] = if ($Severity) { $Severity } else { 'info' }
    # Default: the label followed by an ellipsis. Grammatically right in most cases; one
    # spells it out when the noun form reads better.
    $a['busyLabel'] = if ($BusyLabel) { $BusyLabel } else { "$Label…" }
    # WHAT THE ACTION TAKES UP (D93). The interface uses it to grey out just what it must;
    # the server is the one that really arbitrates.
    $res = @(Get-ActionResources -Type $Id -Module $Module)
    if ($res.Count) { $a['resources'] = @($res) }
    [pscustomobject]$a
}
function New-ModuleObject {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Theme,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][ValidateSet('ok','warn','error','neutral')][string]$Status,
        <#
            -Scope: WHOSE INFORMATION THIS CARD CARRIES, and it is mandatory (D128).

              'machine' -- facts about the computer, true with nobody signed in.
              'user'    -- facts about the account looking, which are read IN ITS OWN SESSION.
              'mixed'   -- both on one card; every field then declares its own.

            WHAT IT IS FOR. Information carried by a user account is fetched from that account,
            never from the service account: the server app has no winget, no WSL, no Game Bar
            and nobody's settings. Measured on 05/10: the winget card was missing from the
            panel entirely, and its first fix then showed one account's winget to another
            account's session. A per-account measurement borrowed from another account is
            wrong even when it is exact.

            WHY DECLARE IT RATHER THAN KNOW IT. Because forgetting does not show: the card
            appears, the value reads plausibly, and it belongs to someone else. Declared, the
            gap becomes mechanical -- `check-scope.ps1` refuses a card without a scope, and a
            'mixed' card one of whose fields does not declare one.
        #>
        [Parameter(Mandatory)][ValidateSet('machine','user','mixed')][string]$Scope,
        [object[]]$Fields = @(),
        [object[]]$Actions = @(),
        <#
            -Mode: A LASTING STATE OF THE CARD, which the interface shows.

            Neither an alert nor an occupancy: a CONTEXT. The Gaming card enters 'game' mode
            for as long as a game lasts, and the interface shows it -- one must see at a
            glance that a game is on, without reading a field.
        #>
        [string]$Mode,

        [switch]$Busy,
        # The identifier of the action REALLY under way. Without it the interface animates
        # every button on the card: one no longer knows which is working.
        [string]$BusyAction,
        # What the running operation takes up: without it, the interface can only block
        # everything or nothing.
        [string[]]$BusyResources = @()
    )
    # INVARIANT: a card is never MORE SERIOUS than the worst of its fields. A card reading
    # "Problème" in red with no red line in it is a contradiction the user sees at once, and
    # there is nowhere for them to go to resolve it.
    # The bound is set HERE, once, for every probe, so none can forget it any more.
    # "neutral" fields bound NOTHING: they carry no judgement, and a green card made of
    # neutral lines is perfectly legitimate.
    $rank = @{ neutral = 0; ok = 1; warn = 2; error = 3 }
    $cap = 0
    foreach ($f in @($Fields)) {
        $s = "$($f.status)"
        if ($s -and $rank.ContainsKey($s) -and $rank[$s] -gt $cap) { $cap = $rank[$s] }
    }
    $effective = $Status
    if ($cap -gt 0 -and $rank["$Status"] -gt $cap) {
        $effective = ($rank.GetEnumerator() | Where-Object { $_.Value -eq $cap }).Name
    }
    $o = [ordered]@{
        id = $Id; theme = $Theme; label = $Label; status = $effective; scope = $Scope
        fields = @($Fields); actions = @($Actions)
    }
    if ($Busy) { $o['busy'] = $true }
    if ($Busy -and $BusyAction) { $o['busyAction'] = $BusyAction }
    if ($Mode) { $o['mode'] = $Mode }
    if ($Busy) {
        $br = if ($BusyResources.Count) { @($BusyResources) } elseif ($BusyAction) { @(Get-ActionResources -Type $BusyAction -Module $Id) } else { @() }
        if ($br.Count) { $o['busyResources'] = @($br) }
    }
    [pscustomobject]$o
}

$script:ThemeCatalog = @(
    [pscustomobject]@{ id = 'windows-update'; label = 'Windows Update' }
    [pscustomobject]@{ id = 'system';         label = 'Système' }
    [pscustomobject]@{ id = 'accounts';       label = 'Comptes' }
    [pscustomobject]@{ id = 'wsl';            label = 'WSL' }
    [pscustomobject]@{ id = 'security';       label = 'Sécurité' }
    [pscustomobject]@{ id = 'network';        label = 'Réseau' }
    [pscustomobject]@{ id = 'tools';          label = 'Outils & paquets' }
    [pscustomobject]@{ id = 'gaming';         label = 'Gaming' }
    # Last in the list: it is a troubleshooting tool, off by default (D85).
    [pscustomobject]@{ id = 'debug';          label = 'Débogage' }
)

<#
    SENTINELS: CHEAP READINGS, AND AN EVENT WHEN THE VALUE CHANGES.

    This is NOT recomputing cards in a loop. A card is expensive -- thirteen seconds for the
    deployment one -- and most of what it holds does not move within the minute. So a few
    precise, cheap FACTS are read instead, declared by each module; when a reading changes it
    raises an event, and it is the event that recomputes the cards the module named.

    A module declares:
      - a "<key>.watch.ps1" file in its folder: ONE reading, ONE comparable value -- a
        boolean, a number, a short string. Nothing else.
      - a "Sentinels" entry in its module.psd1: the cadence, and the cards to recompute.

    The detail: doc/progress/targeting/surveillance.md.
#>
<#
    THE MACHINE'S GAME LIBRARIES, read once and kept.

    Steam declares its libraries in its configuration; other stores register the folder of
    each installed game. All of it lives PER USER for Steam and in the machine store for the
    others: we therefore read hive by hive, never the service account's HKCU (D113).

    This is one identification method, and the most limited: it only knows the big stores.
    An indie game launched without a platform will never be there.
#>
$script:GameLibraries = $null
$script:GameLibrariesAt = [datetime]::MinValue
function Get-GameLibraryPaths {
    param([int]$TtlMinutes = 10)
    if ($script:GameLibraries -and (([datetime]::UtcNow - $script:GameLibrariesAt).TotalMinutes -lt $TtlMinutes)) {
        return $script:GameLibraries
    }
    $found = @()
    # --- Steam: the libraries declared, in each user's own configuration -----------
    foreach ($hive in @(Get-UserRegistryRoots)) {
        try {
            $steamPath = (Get-ItemProperty (Join-Path $hive 'Software\Valve\Steam') -Name 'SteamPath' -ErrorAction Stop).SteamPath
            if (-not $steamPath) { continue }
            $root = ($steamPath -replace '/', '\')
            $found += @{ Label = 'une bibliotheque Steam'; Path = (Join-Path $root 'steamapps\common') }
            $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    $lib = ($m.Groups[1].Value -replace '\\\\', '\')
                    $found += @{ Label = 'une bibliotheque Steam'; Path = (Join-Path $lib 'steamapps\common') }
                }
            }
        } catch { }
    }
    # --- Ubisoft Connect: the folder of each installed game ------------------------
    foreach ($base in @('HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs',
                        'HKLM:\SOFTWARE\Ubisoft\Launcher\Installs')) {
        try {
            foreach ($key in (Get-ChildItem $base -ErrorAction Stop)) {
                $dir = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallDir
                if ($dir) { $found += @{ Label = 'la bibliotheque Ubisoft Connect'; Path = ($dir -replace '/', '\') } }
            }
        } catch { }
    }
    # --- GOG Galaxy ----------------------------------------------------------------
    foreach ($base in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games')) {
        try {
            foreach ($key in (Get-ChildItem $base -ErrorAction Stop)) {
                $dir = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).path
                if ($dir) { $found += @{ Label = 'la bibliotheque GOG'; Path = $dir } }
            }
        } catch { }
    }
    # --- Epic Games: one manifest per game, in the machine's data ------------------
    try {
        $manifests = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
        foreach ($file in @(Get-ChildItem -LiteralPath $manifests -Filter '*.item' -File -ErrorAction Stop)) {
            $item = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($item.InstallLocation) { $found += @{ Label = 'la bibliotheque Epic Games'; Path = "$($item.InstallLocation)" } }
        }
    } catch { }

    $script:GameLibraries = @($found | Where-Object { $_.Path })
    $script:GameLibrariesAt = [datetime]::UtcNow
    return $script:GameLibraries
}

<#
    IS IT A GAME? Several METHODS, and one that speaks is enough.

    They live in probes/gaming/identify/, one file each, ordered by COST: the file name
    carries its rank, and we stop at the first that answers. None is complete -- their union
    is -- and adding one tomorrow costs a file, nothing else.

    WE NEVER JUDGE ON AN EXECUTABLE'S NAME (D64). What is ruled out upfront is ruled out on
    its LOCATION: what lives in the Windows folder is not a game.

    BOTH VERDICTS ARE REMEMBERED -- game AND not-game. An executable that starts a hundred
    times is examined once. The memory carries the CRITERIA FINGERPRINT: change a criterion,
    add a method, and everything is examined again, once.
#>
<#
    A STORE'S OWN FOLDER HOLDS THE STORE, NOT A GAME.

    Ubisoft Connect keeps nine UplayWebCore processes alive next to upc.exe, and each one
    answered two methods at once: started by a store (20) and game markers around the
    executable (50) -- the launcher's folder does hold uplay_r1_loader64.dll. Each new one
    took the session over, so on 03/09 the card announced "UplayWebCore" while Odyssey was
    the process actually consuming the machine.

    The rule judges the LOCATION, like the Windows one: a process sitting DIRECTLY in the
    store's program folder is the store's machinery. A game never sits there -- Steam puts
    them under steamapps\common, Ubisoft in its own game folder -- so nothing real is lost.
#>
function Test-PathInGameStoreFolder {
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Path)
    if (-not $Path) { return $false }
    $folder = ''
    try { $folder = Split-Path $Path -Parent } catch { }
    if (-not $folder) { return $false }
    $separator = [string][char]92
    $folder = "$folder".ToLower().TrimEnd([char]92)
    # THE CONCATENATION STAYS OUT OF THE ARRAY: inside one, the comma binds tighter than the
    # plus, and @('a' + 'b', 'c' + 'd') quietly builds something else entirely.
    $stores = @('steam', 'ubisoft game launcher', 'ubisoft connect', 'gog galaxy',
                'battle.net', 'eadesktop')
    foreach ($store in $stores) {
        if ($folder.EndsWith($separator + $store)) { return $true }
    }
    return $false
}

function Get-GameCriteriaFingerprint {
    param([string]$Backend = (Get-BackendRoot))
    $dir = Join-Path $Backend 'probes/gaming/identify'
    $parts = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $parts += ($file.Name + '@' + $file.LastWriteTimeUtc.ToString('o'))
    }
    # THIS LIBRARY IS A CRITERION TOO: what rules a process out before any method runs lives
    # here. Leaving it out of the fingerprint left the old verdicts standing while the rule
    # that made them had changed -- and a wrong verdict, once memorised, never comes back up.
    try {
        $self = Get-Item -LiteralPath (Join-Path $Backend 'lib/common.ps1') -ErrorAction Stop
        $parts += ('common.ps1@' + $self.LastWriteTimeUtc.ToString('o'))
    } catch { }
    return ($parts -join '|')
}

function Get-GameVerdictPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'game-verdicts.json'
}

function Test-ProcessIsGame {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)]$Process
    )
    $unknown = [pscustomobject]@{ IsGame = $false; Reason = $null; Method = $null }
    if (-not $Process -or -not $Process.Path) { return $unknown }
    $path = "$($Process.Path)"
    # What lives in Windows is not a game: ruled out on its LOCATION, never on its name.
    if ($path.ToLower().StartsWith("$env:SystemRoot".ToLower())) { return $unknown }
    # Neither is what lives in a store's OWN folder (see below).
    if (Test-PathInGameStoreFolder -Path $path) { return $unknown }

    $key = $path.ToLower()
    $file = Get-GameVerdictPath -Backend $Backend
    $fingerprint = Get-GameCriteriaFingerprint -Backend $Backend
    # THE MEMORY IS READ ONCE PER PASS, not once per process. Parsing this file for every running process cost 45 ms
    # each -- the bulk of the 5.5 s the gaming card took on 28/09, with a hundred processes to judge. It is kept in
    # memory for as long as the file has not changed.
    $memory = $null
    $written = $null
    try { if (Test-PathSafe $file) { $written = (Get-Item -LiteralPath $file).LastWriteTimeUtc } } catch { }
    if ($script:GameVerdictMemory -and $script:GameVerdictWritten -eq $written) {
        $memory = $script:GameVerdictMemory
    } elseif ($written) {
        try { $memory = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } catch { }
        $script:GameVerdictMemory = $memory
        $script:GameVerdictWritten = $written
    }
    if ($memory -and "$($memory.fingerprint)" -ne $fingerprint) { $memory = $null }
    if ($memory -and $memory.verdicts -and $memory.verdicts.PSObject.Properties[$key]) {
        $known = $memory.verdicts.PSObject.Properties[$key].Value
        return [pscustomobject]@{ IsGame = [bool]$known.game; Reason = "$($known.reason)"; Method = "$($known.method)" }
    }

    $verdict = $unknown
    $dir = Join-Path $Backend 'probes/gaming/identify'
    foreach ($method in @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $reason = $null
        try { $reason = & $method.FullName -Process $Process } catch { $reason = $null }
        $reason = "$($reason | Select-Object -Last 1)".Trim()
        if ($reason) {
            $verdict = [pscustomobject]@{ IsGame = $true; Reason = $reason; Method = $method.BaseName }
            break
        }
    }

    # We keep the answer, whatever it is.
    $store = [ordered]@{ fingerprint = $fingerprint; verdicts = [ordered]@{} }
    if ($memory -and $memory.verdicts) {
        foreach ($prop in $memory.verdicts.PSObject.Properties) { $store.verdicts[$prop.Name] = $prop.Value }
    }
    $store.verdicts[$key] = [ordered]@{ game = $verdict.IsGame; reason = $verdict.Reason
                                        method = $verdict.Method; at = ([datetime]::UtcNow).ToString('o') }
    try {
        $tmp = "$file.tmp"
        ($store | ConvertTo-Json -Depth 6) | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $file -Force
        # The memory follows what has just been written: without this, the next process reads the file again.
        $script:GameVerdictMemory = ($store | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
        try { $script:GameVerdictWritten = (Get-Item -LiteralPath $file).LastWriteTimeUtc } catch { $script:GameVerdictWritten = $null }
    } catch { }
    return $verdict
}

<#
    RESIDENTS: WHAT LIVES ALONGSIDE THE SERVER APP (target: targeting/residents.md).

    Everything else in Vigie is triggered -- a request, a timer, a button. A RESIDENT stays
    alive instead: it listens, it consumes, it holds a state. The first need that requires
    one is the subscription to process starts, but the mechanism assumes NOTHING about what
    a resident does.

    A module declares one in its module.psd1:

        Residents = @(
            @{ Key = 'game'; Label = 'Detection des jeux' }
        )

    and drops a "<key>.resident.ps1" script next to it. The server arms it at startup, stops
    it with itself, re-arms it if it dies, and its state is visible.
#>
function Get-ResidentDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    if (-not (Test-PathSafe $probesDir)) { return @() }
    $off = @(Get-InactiveUnits -Backend $Backend)
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if ($off -contains $dir.Name) { continue }
        $decl = $null
        try { $decl = Import-PowerShellDataFile -Path (Join-Path $dir.FullName 'module.psd1') } catch { }
        if (-not $decl -or -not $decl.Residents) { continue }
        foreach ($r in @($decl.Residents)) {
            if (-not $r.Key) { continue }
            $script = Join-Path $dir.FullName ("$($r.Key).resident.ps1")
            if (-not (Test-PathSafe $script)) { continue }
            $out += [pscustomobject]@{
                Unit   = $dir.Name
                Key    = "$($r.Key)"
                Label  = $(if ($r.Label) { "$($r.Label)" } else { "$($r.Key)" })
                Script = $script
            }
        }
    }
    return $out
}

# A RESIDENT'S STATE, written by ITSELF: it says it is alive by rewriting it. The server
# only reads it -- a resident that no longer beats is dead, even if its process still
# exists.
function Get-ResidentStatePath {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key)
    Get-VarPath -Backend $Backend -Kind 'run' -File ('resident-' + $Key + '.json')
}

function Get-ResidentState {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key)
    $path = Get-ResidentStatePath -Backend $Backend -Key $Key
    if (-not (Test-PathSafe $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Set-ResidentState {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][hashtable]$Fields
    )
    $path = Get-ResidentStatePath -Backend $Backend -Key $Key
    $state = [ordered]@{}
    $known = Get-ResidentState -Backend $Backend -Key $Key
    if ($known) { foreach ($prop in $known.PSObject.Properties) { $state[$prop.Name] = $prop.Value } }
    foreach ($name in $Fields.Keys) { $state[$name] = $Fields[$name] }
    $state['at'] = ([datetime]::UtcNow).ToString('o')
    try {
        $tmp = "$path.tmp"
        ($state | ConvertTo-Json -Depth 6) | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $path -Force
    } catch { }
}

<#
    ALIVE? Two conditions, and both count: its process exists, and it has beaten recently.
    A frozen process satisfies the first and not the second -- exactly the case we want to
    see.
#>
function Test-ResidentAlive {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key,
        [int]$BeatSeconds = 180
    )
    $state = Get-ResidentState -Backend $Backend -Key $Key
    if (-not $state -or -not $state.processId) { return $false }
    if (-not (Get-ResidentProcess -State $state)) { return $false }
    if (-not $state.at) { return $false }
    try { return ((([datetime]::UtcNow) - (ConvertTo-UtcDate $state.at)).TotalSeconds -lt $BeatSeconds) }
    catch { return $false }
}

<#
    ARMING. A resident runs in ITS OWN process, not in one of the server's runspaces: Pode
    recycles those, and a subscription placed in one would vanish without a word. A process
    can be seen, watched and killed.

    It inherits the server's rights -- that is what lets the process-start subscription
    exist at all, since an ordinary session is denied (measured on 02/09).

    THE SERVER'S PROCESS NUMBER IS HANDED OVER: the resident stops when the server stops.
    That is the only way to hold "no resident outlives the server app" without leaving an
    orphan nobody can see or kill.
#>
function Start-Resident {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)]$Declaration
    )
    # ARMED ONLY WHEN ITS PROCESS IS GONE (Invoke-ResidentPass), so nothing is stopped here: Vigie stops no process on
    # its own (owner, 18/09). The state is only cleared of the vanished number.
    Set-ResidentState -Backend $Backend -Key $Declaration.Key -Fields @{ processId = $null; state = 'arrete' }
    $pwsh = $null
    try { $pwsh = (Get-Process -Id $PID).Path } catch { }
    if (-not $pwsh) { $pwsh = 'pwsh.exe' }
    try {
        # Raw values: Start-ChildProcess quotes them (D116). Passing them bare to
        # Start-Process is what killed this child at every arming on 02/09 -- the shared
        # install lives under "C:\Program Files\Sowapps\Vigie", and "C:\Program" is not a
        # script.
        $child = Start-ChildProcess -FilePath $pwsh `
                    -Arguments @('-NoProfile', '-File', $Declaration.Script,
                                 '-Backend', $Backend, '-ServerPid', $PID) `
                    -Options @{ PassThru = $true; WindowStyle = 'Hidden' }
        Set-ResidentState -Backend $Backend -Key $Declaration.Key -Fields @{
            processId = $child.Id; serverPid = $PID; state = 'arme'
            armedAt = ([datetime]::UtcNow).ToString('o'); error = $null }
        return $true
    } catch {
        Set-ResidentState -Backend $Backend -Key $Declaration.Key -Fields @{
            processId = $null; state = 'echec'; error = "$($_.Exception.Message)" }
        return $false
    }
}

<#
    THE PASS: arms what is missing, re-arms what is dead. Called by the same one-minute
    loop as the sentinels -- one rhythm, one place.
#>
function Invoke-ResidentPass {
    param([string]$Backend = (Get-BackendRoot))
    $started = @()
    foreach ($declaration in @(Get-ResidentDeclarations -Backend $Backend)) {
        # RE-ARMED WHEN ITS PROCESS IS GONE, NEVER BECAUSE IT BEATS LATE. A slow process is not dead: re-arming it on a
        # late beat started a second one beside it, then a third, 115 on 17/09. A late beat is shown on the card.
        if (Test-ResidentProcessPresent -Backend $Backend -Key $declaration.Key) { continue }
        if (Start-Resident -Backend $Backend -Declaration $declaration) {
            $started += $declaration.Key
            try { Write-Log -Backend $Backend -Name 'state' -NoEcho -Message ("resident arme : " + $declaration.Label) } catch { }
        }
    }
    return $started
}

# WHAT CAN BE SAID OF EACH RESIDENT, for a card or a diagnosis: a watch nobody knows the
# health of is worth nothing.
<#
    ALIVE DOES NOT MEAN OPERATIONAL.

    A resident whose process runs and beats may have placed nothing: its subscription was
    denied, and it says so in its state. Believing it works because it breathes is exactly
    the mistake that would announce "no game" while measuring nothing. What it placed is
    therefore reported ALWAYS, without exception.
#>
function Test-ResidentOperational {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key
    )
    if (-not (Test-ResidentAlive -Backend $Backend -Key $Key)) { return $false }
    $state = Get-ResidentState -Backend $Backend -Key $Key
    return ($state -and "$($state.state)" -eq 'arme')
}

# ITS PROCESS STILL EXISTS, whatever its beat says: the only condition for leaving a resident alone.
# THE PROCESS A RESIDENT'S STATE NAMES, or $null -- and only if it is still that resident. A process id is reused by
# Windows once its process is gone, and the state survives a restart of the computer: an id alone let any program
# pass for the resident, which was then never re-armed. The process must be a PowerShell started after the arming;
# when its start time cannot be read, the name alone decides.
function Get-ResidentProcess {
    param($State)
    if (-not $State -or -not $State.processId) { return $null }
    $process = Get-Process -Id ([int]$State.processId) -ErrorAction SilentlyContinue
    if (-not $process -or $process.ProcessName -notin @('pwsh', 'powershell')) { return $null }
    if ($State.armedAt) {
        $armed = $null; $started = $null
        try { $armed = ConvertTo-UtcDate $State.armedAt } catch { }
        try { $started = $process.StartTime.ToUniversalTime() } catch { }
        if ($armed -and $started -and $started -lt $armed.AddSeconds(-30)) { return $null }
    }
    return $process
}

function Test-ResidentProcessPresent {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key)
    $state = Get-ResidentState -Backend $Backend -Key $Key
    if (-not $state -or -not $state.processId) { return $false }
    return [bool](Get-ResidentProcess -State $state)
}

function Get-ResidentHealth {
    param([string]$Backend = (Get-BackendRoot))
    foreach ($declaration in @(Get-ResidentDeclarations -Backend $Backend)) {
        $state = Get-ResidentState -Backend $Backend -Key $declaration.Key
        # THE REASONS A SLOW OR DOUBLED RESIDENT IS SHOWN WITH: the age of its beat, what its process uses, and every
        # process running its script -- counted, never stopped.
        $beatAge = $null
        try { if ($state -and $state.at) { $beatAge = [int](([datetime]::UtcNow) - (ConvertTo-UtcDate $state.at)).TotalSeconds } } catch { }
        $process = $null
        $process = Get-ResidentProcess -State $state
        $copies = @()
        try {
            $leaf = Split-Path "$($declaration.Script)" -Leaf
            $copies = @(Get-CimInstance Win32_Process -Filter ("Name='pwsh.exe' AND CommandLine LIKE '%" + $leaf + "%'") -ErrorAction Stop |
                        ForEach-Object { [pscustomobject]@{ Id = [int]$_.ProcessId; StartedAt = $_.CreationDate } })
        } catch { }
        [pscustomobject]@{
            Key       = $declaration.Key
            Label     = $declaration.Label
            Present     = [bool]$process
            Alive       = (Test-ResidentAlive -Backend $Backend -Key $declaration.Key)
            Operational = (Test-ResidentOperational -Backend $Backend -Key $declaration.Key)
            State     = $(if ($state) { "$($state.state)" } else { 'jamais arme' })
            ArmedAt   = $(if ($state) { $state.armedAt } else { $null })
            LastBeat  = $(if ($state) { $state.at } else { $null })
            BeatAge   = $beatAge
            CpuSeconds = $(if ($process) { try { [int]$process.TotalProcessorTime.TotalSeconds } catch { $null } } else { $null })
            # IN RAM, not committed (Get-ProcessMemoryUse): the figures say what is really in RAM (18/09).
            MemoryMb  = $(if ($process) { $use = Get-ProcessMemoryUse; if ($use.ContainsKey($process.Id)) { [int]($use[$process.Id].Ram / 1MB) } else { $null } } else { $null })
            Copies    = $copies
            LastEvent = $(if ($state) { $state.lastEventAt } else { $null })
            Conflict  = $(if ($state) { $state.lastConflict } else { $null })
            Error     = $(if ($state) { $state.error } else { $null })
        }
    }
}

function Get-WatchDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    if (-not (Test-PathSafe $probesDir)) { return @() }
    $off = @(Get-InactiveUnits -Backend $Backend)
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if ($off -contains $dir.Name) { continue }
        $decl = $null
        try { $decl = Import-PowerShellDataFile -Path (Join-Path $dir.FullName 'module.psd1') } catch { }
        if (-not $decl -or -not $decl.Sentinels) { continue }
        foreach ($v in @($decl.Sentinels)) {
            if (-not $v.Key) { continue }
            $script = Join-Path $dir.FullName ("$($v.Key).watch.ps1")
            if (-not (Test-PathSafe $script)) { continue }
            $out += [pscustomobject]@{
                Unit     = $dir.Name
                Key      = "$($v.Key)"
                Label    = $(if ($v.Label) { "$($v.Label)" } else { "$($v.Key)" })
                Seconds  = $(if ($v.Seconds) { [int]$v.Seconds } else { 900 })
                Cards    = @($v.Cards)
                Script   = $script
            }
        }
    }
    return $out
}

# WHERE THE LAST READING IS KEPT. A file, beside the state cache: it is neither a
# measurement to expose nor a setting -- it is the loop's own memory.
function Get-WatchMemoryPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'watch.json'
}

<#
    ONE WATCH ROUND. Returns the list of events raised, or an empty array.

    It runs the readings that are DUE, compares them, and on a change has the declared cards
    recomputed THROUGH THE EXISTING PATH (Get-State -Only). No second mechanism.
#>
<#
    THE GAME UNDER WAY: one single fact, written by the Gaming probe, read back by its sentinel.

    The probe knows which game is running -- it has just proved it, with two snapshots of
    every process to back it. The sentinel, on the other hand, must stay cheap: it runs every
    minute, permanently. So it does not redo the work, it reads what the probe noted: the
    name, the process, the start time and THE BATTERY CHARGE AT THE START -- without which
    "the battery is draining during the game" cannot be said, only "the battery is low",
    which is not the same information.

    The session lives in var/run: it does not survive a restart, and rightly so -- neither
    does a game.
#>
<#
    THE STATE OF THE POWER SUPPLY, in one place: on mains or not, and the charge.

    The Gaming probe and its sentinel asked the same question in two places, with two
    pieces of code: two chances to drift apart. And above all, neither was TESTABLE without
    unplugging the machine and starting a game -- which is to say never.

    VIGIE_FAKE_BATTERY=<percentage> simulates a machine on battery at that charge, as
    VIGIE_FAKE_GAME simulates a game (doc/en/developing/modules.md). The two together replay
    the whole scene: a game draining the battery.
#>
<#
    IS IT CHARGING OR DRAINING? That is the fact to watch, not the source.

    Being "on mains" says little: plugged in but discharging means a charger that cannot keep
    up; unplugged, it is normal. What matters, and what must wake a card, is the DIRECTION of
    the current.

    Returns 'charge', 'decharge', 'stable' (nothing coming in or going out: a full battery on
    mains) or 'aucune' (a machine with no battery). A reading, with no wake-up and no
    computation.
#>
function Get-PowerFlow {
    if ($env:VIGIE_FAKE_BATTERY) { return 'decharge' }
    $b = Get-CimInstance -Namespace 'root/wmi' -ClassName 'BatteryStatus' -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if (-not $b) { return 'aucune' }
    if ($b.Discharging) { return 'decharge' }
    if ($b.Charging)    { return 'charge' }
    return 'stable'
}

function Get-BatteryState {
    if ($env:VIGIE_FAKE_BATTERY) {
        return @{ OnBattery = $true; Pct = [int]$env:VIGIE_FAKE_BATTERY; Simulated = $true }
    }
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    # No battery at all (a desktop machine): on mains, and no charge to speak of.
    if (-not $battery) { return @{ OnBattery = $false; Pct = $null; Simulated = $false } }
    # BatteryStatus 1 = discharging; any other value means the mains is supplying it.
    return @{ OnBattery = ($battery.BatteryStatus -eq 1)
              Pct       = [int]$battery.EstimatedChargeRemaining
              Simulated = $false }
}

<#
    WHAT EACH APPLICATION TOOK DURING A GAME, AND FOR HOW LONG.

    A card shows an instant. "Chrome at 12 %" says nothing about a session: it may have been a spike between two
    loading screens, or an hour of theft. On 16/09 the greedy-application alert went out fourteen times, and the
    owner recognised the window compositor -- a process that cannot be the culprit, since it draws the game itself.
    The threshold was one percent of the processor, all cores together, read over nine hundred milliseconds.

    So the session keeps a TALLY, not a stream: one entry per application, updated at each pass -- how many passes it
    was seen, the sum of its shares, its peaks, its first and last sighting. Its weight never grows with the length of
    the game. When the game ends, the tally becomes a summary, and the card can say: "during your session of 1 h 35,
    the window compositor held 10 % of the processor for 1 h 04".

    Nothing here measures anything: the gaming card has already measured, this only accumulates.
#>

<#
    WHAT A BOTTLENECK IS, AND WHAT IT IS NOT.

    A saturated machine is not a bottleneck: a game alone at 95 % of the processor simply uses the computer it was
    given. Dust is not one either -- ten processes at one percent are the ordinary life of Windows. A bottleneck is a
    moment when the machine is at its ceiling AND something OTHER than the game takes a share worth the name, on its
    own (owner, 28/09).

    Memory is the exception: when the committed memory reaches its limit, the computer brakes whoever is at fault, so
    no culprit has to be named for the moment to count.

    A single reading is not a bottleneck either: two consecutive ones are needed, one minute, so that a loading screen
    does not become a verdict.
#>
$script:GameJamCpuTotal = 85     # % de charge processeur totale au-dela duquel la machine est au plafond
$script:GameJamCpuOther = 10     # % qu'une application etrangere doit prendre A ELLE SEULE pour gener
$script:GameJamGpuTotal = 95     # % de la carte graphique : un GPU plein bride le jeu plus vite que le processeur
$script:GameJamGpuOther = 5      # % de GPU vole au jeu : plus bas, parce qu'il coute plus cher
$script:GameJamMemPct   = 90     # % de memoire engagee : au-dela, Windows puise dans le fichier d'echange

function Get-GameTallyPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'run' -File 'game-tally.json'
}

function Get-GameSessionsPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'history' -File 'game-sessions.jsonl'
}

# ADDS ONE PASS TO THE TALLY of the running session. $Apps carries what the card has just measured, grouped by
# application: Name, Label, Cpu, Gpu, VramGb, RamGb, IoMbs. Never throws.
function Add-GameTallyPass {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Apps,
        # THE STATE OF THE MACHINE at this pass, which the card has just measured: total processor load, total
        # graphics load, committed memory. Without them, a bottleneck cannot be told from a busy game.
        [double]$CpuTotal = -1,
        [double]$GpuTotal = -1,
        [double]$MemoryPct = -1,
        # The names that belong to the game (the game, its launcher, its components): they never make a bottleneck.
        [string[]]$GameNames = @(),
        # The time between two passes is counted here, from the tally itself: the caller does not have to know it.
        # Capped at five minutes so that a computer put to sleep in the middle of a game does not count as played.
        [int]$MaxGapSeconds = 300
    )
    try {
        $path = Get-GameTallyPath -Backend $Backend
        $tally = $null
        if (Test-PathSafe $path) { try { $tally = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { } }
        $sessionKey = "$($Session.startedAt)"
        # THE SAME SESSION, COMPARED AS A DATE AND NOT AS TEXT: ConvertFrom-Json turns an ISO date into [datetime]
        # (D44), which prints differently from what was written -- every pass then started a new tally, and the
        # session stayed at one pass for ever (caught on the second test, 28/09).
        $sameSession = $false
        if ($tally -and $tally.session) {
            try { $sameSession = ((ConvertTo-UtcDate $tally.session) -eq (ConvertTo-UtcDate $sessionKey)) } catch { $sameSession = $false }
        }
        if (-not $sameSession) {
            $tally = [pscustomobject]@{ session = $sessionKey; game = "$($Session.name)"; startedAt = $sessionKey
                                        lastAt = $null; passes = 0; seconds = 0; apps = [pscustomobject]@{}
                                        jamCpuSeconds = 0; jamGpuSeconds = 0; jamMemSeconds = 0
                                        jamCpuPasses = 0; jamGpuPasses = 0; jamMemPasses = 0
                                        lostSeconds = 0; breaks = @()
                                        satCpuBefore = $false; satGpuBefore = $false; satMemBefore = $false }
        }
        <#
            WHAT THE CAP DROPS IS WRITTEN DOWN, otherwise the count cannot be questioned.

            On 05/10 a session lasting 2 h 06 was counted as 1 h 41, and nothing in the record could say where the
            twenty-five minutes had gone. The cap is right -- a computer asleep in the middle of a game is not played
            time -- but a count one cannot audit is a count one cannot believe. Each interruption longer than the cap
            is now kept: when it started, how long it lasted. Bounded to the ten longest, so a session stays one line.
        #>
        $SecondsSinceLast = 0
        $gapSeconds = 0
        if ($tally.lastAt) {
            try {
                $gapSeconds = [int][Math]::Max(0, ([datetime]::UtcNow - (ConvertTo-UtcDate $tally.lastAt)).TotalSeconds)
                $SecondsSinceLast = [int][Math]::Min($MaxGapSeconds, $gapSeconds)
            } catch { }
        }
        if ($gapSeconds -gt $MaxGapSeconds) {
            $tally.lostSeconds = [int]$tally.lostSeconds + ($gapSeconds - $MaxGapSeconds)
            $breaks = @($tally.breaks) | Where-Object { $_ }
            $breaks += [pscustomobject]@{ at = "$($tally.lastAt)"; seconds = $gapSeconds }
            $tally.breaks = @($breaks | Sort-Object { [int]$_.seconds } -Descending | Select-Object -First 10)
        }
        $tally.passes = [int]$tally.passes + 1
        $tally.seconds = [int]$tally.seconds + $SecondsSinceLast
        # AT ITS CEILING? Told for this pass, and counted only if the previous one said the same.
        $satCpu = ($CpuTotal -ge 0 -and $CpuTotal -ge $script:GameJamCpuTotal)
        $satGpu = ($GpuTotal -ge 0 -and $GpuTotal -ge $script:GameJamGpuTotal)
        $satMem = ($MemoryPct -ge 0 -and $MemoryPct -ge $script:GameJamMemPct)
        $jamCpu = ($satCpu -and [bool]$tally.satCpuBefore)
        $jamGpu = ($satGpu -and [bool]$tally.satGpuBefore)
        $jamMem = ($satMem -and [bool]$tally.satMemBefore)
        # COUNTED IN PASSES AND IN SECONDS: the seconds say how long it lasted, the passes say that it happened --
        # two readings a second apart would otherwise weigh nothing at all.
        if ($jamCpu) { $tally.jamCpuSeconds = [int]$tally.jamCpuSeconds + $SecondsSinceLast; $tally.jamCpuPasses = [int]$tally.jamCpuPasses + 1 }
        if ($jamGpu) { $tally.jamGpuSeconds = [int]$tally.jamGpuSeconds + $SecondsSinceLast; $tally.jamGpuPasses = [int]$tally.jamGpuPasses + 1 }
        if ($jamMem) { $tally.jamMemSeconds = [int]$tally.jamMemSeconds + $SecondsSinceLast; $tally.jamMemPasses = [int]$tally.jamMemPasses + 1 }
        $tally.satCpuBefore = $satCpu
        $tally.satGpuBefore = $satGpu
        $tally.satMemBefore = $satMem
        # NOT $apps: PowerShell does not distinguish case, and the local list would silently overwrite the -Apps
        # parameter -- the tally then recorded nobody (caught on the first test, 28/09).
        $tallied = @{}
        foreach ($prop in $tally.apps.PSObject.Properties) { $tallied[$prop.Name] = $prop.Value }
        foreach ($app in @($Apps)) {
            if (-not $app -or -not $app.Name) { continue }
            $key = "$($app.Name)"
            $e = $tallied[$key]
            if (-not $e) {
                $e = [pscustomobject]@{ label = "$($app.Label)"; passes = 0; seconds = 0
                                        cpu = 0.0; gpu = 0.0; ram = 0.0; cpuMax = 0.0; gpuMax = 0.0
                                        jamSeconds = 0; jamCpu = 0.0; jamGpu = 0.0; jamPasses = 0 }
            }
            # IN THE WAY? Only while the machine is at its ceiling, only if this application is not the game's, and
            # only if it takes a share on its own -- dust at one percent never blocks anything.
            if (($jamCpu -or $jamGpu) -and ($GameNames -notcontains "$($app.Name)")) {
                $offender = (($jamCpu -and [double]$app.Cpu -ge $script:GameJamCpuOther) -or
                           ($jamGpu -and [double]$app.Gpu -ge $script:GameJamGpuOther))
                if ($offender) {
                    $e.jamPasses = [int]$e.jamPasses + 1
                    $e.jamSeconds = [int]$e.jamSeconds + $SecondsSinceLast
                    $e.jamCpu = [double]$e.jamCpu + [double]$app.Cpu
                    $e.jamGpu = [double]$e.jamGpu + [double]$app.Gpu
                }
            }
            $e.passes = [int]$e.passes + 1
            $e.seconds = [int]$e.seconds + $SecondsSinceLast
            $e.cpu = [double]$e.cpu + [double]$app.Cpu
            $e.gpu = [double]$e.gpu + [double]$app.Gpu
            $e.ram = [double]$e.ram + [double]$app.RamGb
            if ([double]$app.Cpu -gt [double]$e.cpuMax) { $e.cpuMax = [double]$app.Cpu }
            if ([double]$app.Gpu -gt [double]$e.gpuMax) { $e.gpuMax = [double]$app.Gpu }
            $tallied[$key] = $e
        }
        # BOUNDED: the sixty heaviest applications of the session. A game does not need a census of the computer.
        $keep = @($tallied.GetEnumerator() | Sort-Object { [double]$_.Value.cpu + [double]$_.Value.gpu } -Descending |
                    Select-Object -First 60)
        $ordered = [ordered]@{}
        foreach ($entry in $keep) { $ordered[$entry.Key] = $entry.Value }
        $tally.apps = [pscustomobject]$ordered
        Update-StateJson -Path $path -Set @{ session = $tally.session; game = $tally.game; startedAt = $tally.startedAt; lastAt = ([datetime]::UtcNow).ToString('o')
                                             passes = $tally.passes; seconds = $tally.seconds; apps = $tally.apps
                                             jamCpuSeconds = $tally.jamCpuSeconds; jamGpuSeconds = $tally.jamGpuSeconds
                                             jamMemSeconds = $tally.jamMemSeconds; satCpuBefore = $tally.satCpuBefore
                                             jamCpuPasses = $tally.jamCpuPasses; jamGpuPasses = $tally.jamGpuPasses
                                             jamMemPasses = $tally.jamMemPasses
                                             lostSeconds = $tally.lostSeconds; breaks = @($tally.breaks)
                                             satGpuBefore = $tally.satGpuBefore; satMemBefore = $tally.satMemBefore } | Out-Null
        <#
            AND THE PASS SAYS WHAT IS HAPPENING NOW, not only what the recap will say hours later.

            Everything needed is already computed here: whether the machine is at its ceiling on this pass and on the
            previous one, and which applications take a share of their own while it is. Returning it costs nothing,
            and it is what lets the card name the offender DURING the game -- on 29/09 the card said no other
            application was greedy while Steam held 12,9 % throughout the jams.
        #>
        $now = @()
        if ($jamCpu -or $jamGpu -or $jamMem) {
            foreach ($app in @($Apps)) {
                if (-not $app -or -not $app.Name) { continue }
                if ($GameNames -contains "$($app.Name)") { continue }
                if (($jamCpu -and [double]$app.Cpu -ge $script:GameJamCpuOther) -or
                    ($jamGpu -and [double]$app.Gpu -ge $script:GameJamGpuOther)) {
                    $now += [pscustomobject]@{ Name = "$($app.Name)"; Label = "$($app.Label)"
                                               Cpu = [double]$app.Cpu; Gpu = [double]$app.Gpu }
                }
            }
        }
        $kind = $null; $held = 0
        if ($jamCpu) { $kind = 'cpu'; $held = [int]$tally.jamCpuSeconds }
        elseif ($jamGpu) { $kind = 'gpu'; $held = [int]$tally.jamGpuSeconds }
        elseif ($jamMem) { $kind = 'memory'; $held = [int]$tally.jamMemSeconds }
        return [pscustomobject]@{ Jam = $kind; Seconds = $held
                                  Offenders = @($now | Sort-Object { $_.Cpu + $_.Gpu } -Descending) }
    } catch { }
}

# CLOSES THE TALLY and keeps the summary of the session. Returns it, or $null when there was nothing to close.
function Close-GameTally {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-GameTallyPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return $null }
        $tally = $null
        try { $tally = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $tally -or [int]$tally.passes -lt 2) { return $null }
        $apps = @()
        foreach ($prop in $tally.apps.PSObject.Properties) {
            $e = $prop.Value
            $passes = [Math]::Max(1, [int]$e.passes)
            $apps += [pscustomobject]@{
                name = $prop.Name; label = "$($e.label)"
                jamSeconds = [int]$e.jamSeconds
                jamPasses = [int]$e.jamPasses
                jamCpu = $(if ([int]$e.jamPasses -gt 0) { [Math]::Round([double]$e.jamCpu / [int]$e.jamPasses, 1) } else { 0 })
                jamGpu = $(if ([int]$e.jamPasses -gt 0) { [Math]::Round([double]$e.jamGpu / [int]$e.jamPasses, 1) } else { 0 })
                seconds = [int]$e.seconds
                cpu = [Math]::Round([double]$e.cpu / $passes, 1)
                gpu = [Math]::Round([double]$e.gpu / $passes, 1)
                ram = [Math]::Round([double]$e.ram / $passes, 2)
                cpuMax = [Math]::Round([double]$e.cpuMax, 1)
                gpuMax = [Math]::Round([double]$e.gpuMax, 1)
            }
        }
        # THE BOTTLENECKS OF THE SESSION, each with those who were in the way -- and a bottleneck with nobody in the
        # way is dropped, except the memory one, where the machine itself is the brake.
        $jams = @()
        $offenders = @($apps | Where-Object { [int]$_.jamPasses -gt 0 } | Sort-Object { $_.jamCpu + $_.jamGpu } -Descending)
        if ([int]$tally.jamCpuPasses -gt 0 -and @($offenders | Where-Object { $_.jamCpu -gt 0 }).Count) {
            $jams += [pscustomobject]@{ kind = 'cpu'; label = 'Processeur saturé'; seconds = [int]$tally.jamCpuSeconds
                                        who = @($offenders | Where-Object { $_.jamCpu -gt 0 } | Select-Object -First 3 |
                                                ForEach-Object { [pscustomobject]@{ label = $_.label; share = $_.jamCpu } }) }
        }
        if ([int]$tally.jamGpuPasses -gt 0 -and @($offenders | Where-Object { $_.jamGpu -gt 0 }).Count) {
            $jams += [pscustomobject]@{ kind = 'gpu'; label = 'Carte graphique saturée'; seconds = [int]$tally.jamGpuSeconds
                                        who = @($offenders | Where-Object { $_.jamGpu -gt 0 } | Select-Object -First 3 |
                                                ForEach-Object { [pscustomobject]@{ label = $_.label; share = $_.jamGpu } }) }
        }
        if ([int]$tally.jamMemPasses -gt 0) {
            $jams += [pscustomobject]@{ kind = 'memory'; label = 'Mémoire à la limite'; seconds = [int]$tally.jamMemSeconds; who = @() }
        }
        $summary = [ordered]@{
            game = "$($tally.game)"; startedAt = "$($tally.startedAt)"
            endedAt = ([datetime]::UtcNow).ToString('o'); seconds = [int]$tally.seconds; passes = [int]$tally.passes
            lostSeconds = [int]$tally.lostSeconds
            breaks = @(@($tally.breaks) | Where-Object { $_ } | Sort-Object { [int]$_.seconds } -Descending)
            jams = @($jams)
            apps = @($apps | Sort-Object { $_.cpu + $_.gpu } -Descending | Select-Object -First 15)
        }
        Add-HistoryLine -Path (Get-GameSessionsPath -Backend $Backend) -Line ($summary | ConvertTo-Json -Depth 6 -Compress) | Out-Null
        return [pscustomobject]$summary
    } catch { return $null }
}

# THE SESSIONS KEPT, most recent first. Bounded by -Last: the file holds one line per session, and nobody reads
# forty of them at once. A line that does not parse is skipped, never fatal.
function Get-GameSessions {
    param([string]$Backend = (Get-BackendRoot), [int]$Last = 40)
    $out = @()
    try {
        $path = Get-GameSessionsPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return @() }
        foreach ($line in @(Get-Content -LiteralPath $path -Tail $Last -ErrorAction Stop)) {
            if (-not "$line".Trim()) { continue }
            try { $out += ($line | ConvertFrom-Json) } catch { }
        }
    } catch { return @() }
    [array]::Reverse($out)
    return $out
}

# THE LAST SESSION KEPT, or $null. Read backwards: the file holds one line per session, the last one is the last game.
function Get-LastGameSession {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-GameSessionsPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return $null }
        $lines = @(Get-Content -LiteralPath $path -Tail 1 -ErrorAction Stop)
        if (-not $lines.Count) { return $null }
        return ($lines[-1] | ConvertFrom-Json)
    } catch { return $null }
}

function Get-GameSessionPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'run' -File 'game-session.json'
}

function Get-GameSession {
    param([string]$Backend = (Get-BackendRoot))
    $path = Get-GameSessionPath -Backend $Backend
    if (-not (Test-PathSafe $path)) { return $null }
    $session = $null
    try { $session = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $session -or -not $session.processId) { return $null }
    # THE PROCESS IS WHAT COUNTS. A game that stops does not come back through the probe to
    # say so: without this check, a finished game would stay open until the next computation.
    $proc = Get-Process -Id ([int]$session.processId) -ErrorAction SilentlyContinue
    if (-not $proc) { return $null }
    # AND IT MUST BE THE SAME PROCESS. Windows recycles ids: a closed game whose id is taken
    # over by a browser would make the session last for ever -- seen on 02/09 with a
    # simulated session that outlived its simulation.
    if ($session.path) {
        $exePath = $null
        try { $exePath = $proc.Path } catch { }
        if ($exePath -and "$exePath" -ne "$($session.path)") { return $null }
    }
    return $session
}

function Set-GameSession {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$ProcessId,
        [int]$BatteryPct = -1
    )
    $path = Get-GameSessionPath -Backend $Backend
    $known = Get-GameSession -Backend $Backend
    # SAME PROCESS MEANS SAME GAME: the start is never rebased, or the battery's fall would
    # start from zero at each computation and never cross a threshold.
    if ($known -and [int]$known.processId -eq $ProcessId) { return }
    $exePath = $null
    try { $exePath = (Get-Process -Id $ProcessId -ErrorAction Stop).Path } catch { }
    $session = [ordered]@{
        name      = $Name
        processId = $ProcessId
        path      = $exePath
        startedAt = ([datetime]::UtcNow).ToString('o')
        startPct  = $BatteryPct
    }
    try { ($session | ConvertTo-Json -Depth 4) | Out-File -FilePath $path -Encoding UTF8 } catch { }
}

function Clear-GameSession {
    param([string]$Backend = (Get-BackendRoot))
    $path = Get-GameSessionPath -Backend $Backend
    if (Test-PathSafe $path) { try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch { } }
}

# One history line for a sentinel: the state reached, the one it came from, and the cards the
# change had recomputed. Best effort from end to end: the watch OBSERVES, it does not
# arbitrate -- a failed write must never stop a recomputation from starting.
function Write-SentinelSample {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Key,
        [string]$From,
        [Parameter(Mandatory)][string]$To,
        [string[]]$Cards = @()
    )
    try {
        $cfg = Get-Config -Backend $Backend
        if (-not (Get-HistoryConfig -Backend $Backend -Config $cfg).Enabled) { return }
        $id = Get-SentinelMeasureId -Key $Key
        if (-not (Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg).Enabled) { return }
        $obj = [ordered]@{ at = ([datetime]::UtcNow).ToString('o'); v = $To }
        if ($From) { $obj.from = $From }
        if ($Cards.Count) { $obj.cards = @($Cards) }
        # A sentinel already writes ONLY on a change: no heartbeat here, and a flat series of
        # events is not a gap, it is an absence of events.
        $null = Write-HistoryPoint -Backend $Backend -MeasureId $id -Point $obj
    } catch { }
}

<#
    THE SCHEDULER -- WHAT THE SERVER COMPUTES BY ITSELF, AND WHEN (D124).

    The watch loop reacted to a CHANGE and to nothing else. "A game is running" does not change during the game, so no
    card was recomputed and nothing was sampled: of a game of more than two hours on 28/09 the session kept four passes
    and 430 seconds, all taken while a client app happened to be alive, and it closed nine hours late. Regular sampling
    was resting on whoever was looking.

    WHAT IS SCHEDULED IS A COMPUTATION, NOT A CARD. A computation feeds the cards it declares -- several cards from one
    computation, several computations for one card -- and nothing here assumes one of each.

    EVERYTHING IS DECIDED ON ELAPSED TIME. A computation is due when the seconds since its last start exceed its
    interval. The loop's thirty-second beat is a beat, never a unit: a skipped beat shifts nothing.

    THE LIMIT IS A SETTING. RefreshMaxParallel launches run at once, three by default, zero meaning no limit. A
    computation already running is never started again unless it declares Parallel.

    A COMPUTATION THAT FAILS STEPS ASIDE. Its next attempt is pushed back, doubling at each failure up to a cap, so a
    broken computation stops being the oldest one and stops taking the place of the others.

    A COMPUTATION THAT RUNS TOO LONG IS NAMED. Past its MaxSeconds it is logged, written to the history and shown on
    the self-watch card, and it stops counting against the limit. It is never stopped: the owner alone decides that.
#>
function Get-RefreshConfig {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = $null
    try { $cfg = (Get-Config -Backend $Backend).Refresh } catch { }
    $out = @{ MaxParallel = 3; MaxChildren = 8; DefaultMaxSeconds = 300; FailBackoffSeconds = 60; FailBackoffMaxSeconds = 3600 }
    if ($cfg) {
        foreach ($k in @($out.Keys)) {
            try { if ($null -ne $cfg[$k]) { $out[$k] = [int]$cfg[$k] } } catch { }
        }
    }
    $out
}

<#
    ONE DISCOVERY FOR EVERY DECLARATION. Sentinels, modes and computations are all sections of the same module.psd1,
    read the same way, with inactive modules left out the same way. Written three times, it would drift three ways.
#>
function Get-UnitDeclarations {
    param([Parameter(Mandatory)][string]$Section, [string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    if (-not (Test-PathSafe $probesDir)) { return @() }
    $off = @(Get-InactiveUnits -Backend $Backend)
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if ($off -contains $dir.Name) { continue }
        $decl = $null
        try { $decl = Import-PowerShellDataFile -Path (Join-Path $dir.FullName 'module.psd1') } catch { }
        if (-not $decl -or -not $decl[$Section]) { continue }
        foreach ($entry in @($decl[$Section])) {
            if (-not $entry) { continue }
            $out += [pscustomobject]@{ Unit = $dir.Name; Dir = $dir.FullName; Entry = $entry }
        }
    }
    return $out
}

<#
    THE MODES. Today "in a game" and "not in a game"; tomorrow whatever a module declares -- nothing here knows about
    games. Several modes can be active at once.

    A mode reads a SENTINEL by default, and that is the DRY answer: the watch loop already reads them, their last value
    is already in memory, and a mode then costs nothing at all. A module needing its own reading declares Script
    instead, and gets a <key>.mode.ps1 read like a sentinel.
#>
$script:ModeOffValues = @('', 'non', 'no', 'aucun', 'inconnu', 'erreur', '0', 'false')

function Get-ModeDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $out = @()
    foreach ($d in @(Get-UnitDeclarations -Section 'Modes' -Backend $Backend)) {
        $key = "$($d.Entry.Key)"
        if (-not $key) { continue }
        $script = $null
        if ($d.Entry.Script) {
            $script = Join-Path $d.Dir "$($d.Entry.Script)"
            if (-not (Test-PathSafe $script)) { continue }
        }
        $off = @($script:ModeOffValues)
        if ($d.Entry.Off) { $off = @(@($d.Entry.Off) | ForEach-Object { "$_".ToLowerInvariant() }) + @('') }
        $out += [pscustomobject]@{
            Unit     = $d.Unit
            Key      = $key
            Label    = $(if ($d.Entry.Label) { "$($d.Entry.Label)" } else { $key })
            Sentinel = $(if ($d.Entry.Sentinel) { "$($d.Entry.Sentinel)" } else { $null })
            Script   = $script
            Off      = $off
        }
    }
    return $out
}

function Get-ActiveModes {
    param([string]$Backend = (Get-BackendRoot))
    $active = @()
    $memory = $null
    foreach ($m in @(Get-ModeDeclarations -Backend $Backend)) {
        $value = $null
        if ($m.Sentinel) {
            if ($null -eq $memory) {
                $memory = @{}
                try {
                    $path = Get-WatchMemoryPath -Backend $Backend
                    if (Test-PathSafe $path) {
                        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                        foreach ($pr in $j.PSObject.Properties) { $memory[$pr.Name] = "$($pr.Value.value)" }
                    }
                } catch { }
            }
            $value = "$($memory[$m.Sentinel])"
        } elseif ($m.Script) {
            try { $value = "$(& $m.Script 2>$null | Select-Object -Last 1)".Trim() } catch { $value = '' }
        }
        if ($m.Off -notcontains "$value".Trim().ToLowerInvariant()) { $active += $m.Key }
    }
    return $active
}

<#
    THE COMPUTATIONS A MODULE DECLARES.

        Refresh = @(
            @{ Key = 'gaming'; Probe = 'gaming.probe.ps1'; Cards = @('gaming')
               Seconds = @{ default = 600; game = 30 }; MaxSeconds = 60 }
        )

    Seconds holds ONE interval per mode, plus "default"; the first active mode that declares one wins. No interval at
    all means the computation only ever runs when someone asks for it -- which is what every card does today.
#>
<#
    THE ACCOUNTS WHOSE SESSION IS OPEN, by name. Their registry hive is mounted only while they are logged in, which
    is exactly the question -- and it costs nothing, where establishing the list of accounts costs two seconds.
#>
<#
    THE ACCOUNTS WITH AN OPEN SESSION -- AND NEVER THE ONE THE SERVER APP RUNS AS.

    Its hive is loaded like any other, so it was counted among them: the scheduler computed a per-account card FOR
    THE SERVICE ACCOUNT, which owns nothing a person installed and has no screen to look at one. Measured on 06/10,
    `packages.probe.ps1@VigieService` sat in the cache beside `@fhaza` and `@Famille`, holding a reading nobody would
    ever read. The owner put it plainly: the service account has no package manager, therefore no card.

    It is the one entry in this list that cannot be a reader -- the whole client-task mechanism exists because it has
    no session of its own (D113). Leaving it out is the definition, not an optimisation.
#>
function Get-OpenSessionAccounts {
    $names = @()
    $self = $null
    try { $self = [Security.Principal.WindowsIdentity]::GetCurrent().Name.Split([char]92)[-1] } catch { }
    foreach ($hive in @(Get-UserRegistryRoots)) {
        try {
            $sid = "$hive".Split([char]92)[-1]
            $name = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate(
                        [System.Security.Principal.NTAccount]).Value.Split([char]92)[-1]
            if (-not $name) { continue }
            if ($self -and $name -eq $self) { continue }
            if ($names -notcontains $name) { $names += $name }
        } catch { }
    }
    return @($names)
}

function Get-RefreshDeclarations {
    param([string]$Backend = (Get-BackendRoot))
    $out = @()
    $openAccounts = $null
    foreach ($d in @(Get-UnitDeclarations -Section 'Refresh' -Backend $Backend)) {
        $key = "$($d.Entry.Key)"
        $probe = "$($d.Entry.Probe)"
        if (-not $key -or -not $probe) { continue }
        if (-not (Test-PathSafe (Join-Path $d.Dir $probe))) { continue }
        <#
            A MEASURE THAT DEPENDS ON WHO LOOKS IS COMPUTED PER ACCOUNT (D109). The owner settled the scope on
            30/09: every account with an open session.

            The cache of such a probe holds one entry per account. The scheduler computes with no requester, so it
            was writing into its own entry -- one nobody ever reads. Measured on 30/09: the WSL card was recomputed
            every five minutes all day, and what the owner saw was 31 hours old, because his own entry was never
            touched. And since a request computes nothing (D124), it would never have been.

            One declaration per open session, then: their hive is mounted, so they are the ones who may be looking.
            Nobody logged in, nothing to compute -- and nobody to read it either.
        #>
        if (Test-ProbeIsPerAccount -ProbeFile (Join-Path $d.Dir $probe)) {
            if ($null -eq $openAccounts) { $openAccounts = @(Get-OpenSessionAccounts) }
            foreach ($account in $openAccounts) {
                $seconds = @{}
                if ($d.Entry.Seconds -is [hashtable]) {
                    foreach ($k in $d.Entry.Seconds.Keys) { $seconds["$k"] = [int]$d.Entry.Seconds[$k] }
                } elseif ($d.Entry.Seconds) { $seconds['default'] = [int]$d.Entry.Seconds }
                $out += [pscustomobject]@{
                    Unit       = $d.Unit
                    Key        = "$($d.Unit)/$key@$account"
                    Probe      = $probe
                    Account    = $account
                    Cards      = @($d.Entry.Cards)
                    Seconds    = $seconds
                    MaxSeconds = $(if ($d.Entry.MaxSeconds) { [int]$d.Entry.MaxSeconds } else { 0 })
                    Parallel   = [bool]$d.Entry.Parallel
                    OnlyWhen   = "$($d.Entry.OnlyWhen)"
                }
            }
            continue
        }
        $seconds = @{}
        if ($d.Entry.Seconds -is [hashtable]) {
            foreach ($k in $d.Entry.Seconds.Keys) { $seconds["$k"] = [int]$d.Entry.Seconds[$k] }
        } elseif ($d.Entry.Seconds) { $seconds['default'] = [int]$d.Entry.Seconds }
        $out += [pscustomobject]@{
            Unit       = $d.Unit
            Key        = "$($d.Unit)/$key"
            Probe      = $probe
            Cards      = @($d.Entry.Cards)
            Seconds    = $seconds
            MaxSeconds = $(if ($d.Entry.MaxSeconds) { [int]$d.Entry.MaxSeconds } else { 0 })
            Parallel   = [bool]$d.Entry.Parallel
            # ONLYWHEN: a computation only worth its cost in a given state. Listing the packages questions three
            # package managers for 3,7 s: once a day, and never while the machine is busy (owner, 29/09).
            OnlyWhen   = "$($d.Entry.OnlyWhen)"
        }
    }
    return $out
}

# THE INTERVAL THAT APPLIES RIGHT NOW: the first active mode that declares one, else "default", else none.
function Get-RefreshInterval {
    param([Parameter(Mandatory)]$Declaration, [string[]]$Modes = @())
    foreach ($m in @($Modes)) {
        if ($Declaration.Seconds.ContainsKey($m)) { return [int]$Declaration.Seconds[$m] }
    }
    if ($Declaration.Seconds.ContainsKey('default')) { return [int]$Declaration.Seconds['default'] }
    return 0
}

<#
    WHEN WAS THIS COMPUTATION'S RESULT LAST WRITTEN? The scheduler needs it to tell a computation that FAILED from one
    that merely returned a card in error: a card saying "no internet" is a result, an exception is not. Get-State
    swallows a probe's error to keep serving the others, so the proof of a failure is that the cache did not move.
#>
function Get-ProbeCacheStamp {
    # ACCOUNT: the entry of THAT account alone. The scheduler now computes per account for a per-account probe, so
    # the proof that ITS computation wrote something is its own entry, not the newest of all.
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Probe, [string]$Account)
    try {
        $path = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
        if (-not (Test-PathSafe $path)) { return '' }
        <#
            THE MOST RECENT OF THE MATCHING ENTRIES, never the first one met.

            A probe whose rendering depends on who looks has ONE entry PER ACCOUNT (D109): accounts.probe.ps1@fhaza,
            accounts.probe.ps1@Famille. The scheduler computes with no requester, so it writes its own entry -- and
            this function was answering with whichever entry came first in the file. It was therefore comparing the
            stamp of SOMEONE ELSE'S entry before and after, saw it unchanged, and the worker concluded "the
            computation wrote nothing". Measured on 30/09: the accounts card had failed eight times in a row that
            way, while its computation was working perfectly.

            The proof that a computation wrote something is that the NEWEST stamp moved, whoever it belongs to.
        #>
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $newest = $null
        $newestAt = $null
        foreach ($pr in $j.PSObject.Properties) {
            $name = "$($pr.Name)"
            if ($Account) {
                if ($name -ne ($Probe + '@' + $Account)) { continue }
            } elseif (-not ($name -eq $Probe -or $name.StartsWith($Probe + '@'))) { continue }
            $raw = "$($pr.Value.at)"
            if (-not $raw) { continue }
            $when = $null
            try { $when = ConvertTo-UtcDate $raw } catch { }
            if (-not $when) { if (-not $newest) { $newest = $raw }; continue }
            if (-not $newestAt -or $when -gt $newestAt) { $newestAt = $when; $newest = $raw }
        }
        if ($newest) { return $newest }
    } catch { }
    return ''
}

<#
    THE STAMP OF THE STATE CACHE -- how the panel learns that something was computed (D124).

    The server cannot push: it answers requests. But the panel already asks /health every fifteen seconds to see
    whether a new version is being served, and that answer costs nothing. It now carries the moment the state cache
    was last written: when it moves, the panel reads the cache again, instead of waiting for its own minute to pass.
    No new route, no new transport, and the panel still never waits for a computation -- it reads what is written.
#>
function Get-StateStamp {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
        if (-not (Test-PathSafe $path)) { return '' }
        return "$((Get-Item -LiteralPath $path -ErrorAction Stop).LastWriteTimeUtc.Ticks)"
    } catch { return '' }
}

function Get-RefreshStatePath {
    param([string]$Backend = (Get-BackendRoot))
    # 'run': a LIVING state. What is running dies with the server, and a pace starts again from the restart.
    Get-VarPath -Backend $Backend -Kind 'run' -File 'refresh.json'
}

function Get-RefreshState {
    param([string]$Backend = (Get-BackendRoot))
    $state = @{}
    try {
        $path = Get-RefreshStatePath -Backend $Backend
        if (Test-PathSafe $path) {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($pr in $j.PSObject.Properties) {
                $e = $pr.Value
                $state["$($pr.Name)"] = @{
                    pid           = [int]$e.pid
                    startedAt     = [long]$e.startedAt
                    lastStartedAt = [long]$e.lastStartedAt
                    lastEndedAt   = [long]$e.lastEndedAt
                    lastMs        = [int]$e.lastMs
                    fails         = [int]$e.fails
                    nextAt        = [long]$e.nextAt
                    long          = [bool]$e.long
                    lastError     = "$($e.lastError)"
                }
            }
        }
    } catch { }
    return $state
}

# ONE KEY AT A TIME, through the helper that locks the file: the workers write their own outcome while the pass writes
# its launches, and neither may lose the other's line.
function Update-RefreshState {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][hashtable]$Entry)
    try { $null = Update-StateJson -Path (Get-RefreshStatePath -Backend $Backend) -Set @{ $Key = $Entry } -Depth 6 } catch { }
}

<#
    WHEN THE DISK EMPTIES FAST, VIGIE LOOKS BY ITSELF.

    The storage card can say where the space went, but only if someone presses the button. On 28/09 the disk went from
    112 GB free to 28 GB without anyone watching, and the answer -- 49,7 GB of debug traces and a virtual disk that
    never gives anything back -- was found by hand, days later.

    THE TRIGGER IS A FALL, NOT A LEVEL. A disk that has been at 30 GB for a year has nothing to explain; one that has
    just lost ten of them in a day does. The history of disk.free already holds what is needed, sampled every thirty
    minutes, and reading it costs a file.

    WHAT HOLDS IT BACK, and each of these was asked for: at most one automatic analysis a day, none while a mode says
    the machine is busy for its owner -- a game --, and none while anything else is already using the machine. The
    analysis itself is the one the button launches, with its own protection against running twice.
#>
<#
    HOW MANY GIGABYTES THE DISK HAS LOST over a window: the highest point of the window against the latest one, read
    from the history that is already sampled every thirty minutes. Separate from the decision that uses it, so the
    decision can be read -- and the reading tested -- without anything being started.

    $null when the history cannot answer: fewer than two points is not "no fall", it is "we do not know".
#>
function Get-DiskFreeFall {
    param([string]$Backend = (Get-BackendRoot), [int]$Hours = 24)
    $history = $null
    try { $history = Get-MeasureHistory -Backend $Backend -MeasureId 'disk.free' -Window ([TimeSpan]::FromHours($Hours)) } catch { }
    if (-not $history) { return $null }
    $values = @(@($history.points) | ForEach-Object { [double]$_.v })
    if ($values.Count -lt 2) { return $null }
    return (($values | Measure-Object -Maximum).Maximum - $values[-1])
}

<#
    WHAT WSL REALLY HOLDS, ASKED TO A CLIENT APP (SYS-DISK).

    A virtual disk never gives back what is freed inside it: 150,7 GB on C: on 28/09, for far less content. Only a
    reading made INSIDE the distribution can tell the difference, and the server app has none -- it runs under a
    service account, where WSL does not exist.

    So the server asks. It writes an order in the account's run folder and the client app runs it in its session, the
    mechanism that already serves every action needing a session (Invoke-ClientTask). The answer is kept for an
    hour: a virtual disk does not change size in a minute, and nobody is ever made to wait for it -- the card reads
    what is written, or says nothing about it.
#>
function Get-WslUsagePath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'wsl-usage.json'
}

function Get-WslUsage {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $path = Get-WslUsagePath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return $null }
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $j -or -not $j.distributions) { return $null }
        return $j
    } catch { return $null }
}

function Update-WslUsage {
    param([string]$Backend = (Get-BackendRoot), [int]$EveryMinutes = 60)
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    $path = Get-WslUsagePath -Backend $Backend
    <#
        THE GATE IS READ IN TICKS, and it is the third time today that this matters: ConvertFrom-Json turns an ISO
        date back into a [datetime], whose string form is then local and no longer parses (D44). Read as text, the
        gate never held and a client app was asked every thirty seconds instead of every hour -- seen in its log.
    #>
    try {
        if (Test-PathSafe $path) {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $ticks = [long]$j.atTicks
            if ($ticks -and ([datetime]::UtcNow - [datetime]$ticks).TotalMinutes -lt $EveryMinutes) { return $null }
        }
    } catch { }
    # A CLIENT APP THAT BEATS, and nothing else: an account with no session has no WSL to look at either.
    $account = @(Get-ClientWatchRows -Backend $Backend | Where-Object { $_.Status -eq 'ok' } | Select-Object -First 1)
    if (-not $account.Count) { return $null }
    $answer = $null
    try { $answer = Invoke-ClientTask -Account "$($account[0].Account)" -Type 'wsl-usage' -Module 'wsl' -TimeoutSec 20 -Backend $Backend } catch { }
    if (-not $answer -or -not $answer.result -or -not $answer.result.ok) { return $null }
    $entry = [ordered]@{
        at            = ([datetime]::UtcNow).ToString('o')
        atTicks       = ([datetime]::UtcNow).Ticks
        account       = "$($account[0].Account)"
        distributions = @($answer.result.distributions)
    }
    try { Set-Content -LiteralPath $path -Value ($entry | ConvertTo-Json -Depth 6 -Compress) -Encoding UTF8 } catch { }
    return $entry
}

<#
    WHICH PACKAGE MANAGERS EACH ACCOUNT HAS, asked of that account's own session.

    WHY. Measured on 05/10: the server app saw Chocolatey and pip, both installed machine-wide, and NOT winget,
    although this account has it. A manager installed in a profile resolves from that profile's PATH, and the service
    account's PATH never names it -- so the main manager of the machine was missing from the panel (C4 of
    `targeting/multi-account-server.md`).

    HOW. The same door WSL already uses (D113 and the client app's desktop orders): the server asks every account
    whose client app beats, through the `pkg-inventory` action, which runs in that session. One entry per account,
    refreshed at most once an hour -- a manager is not installed twice a day, and the reading costs a process launch
    per manager.
#>
function Get-PkgInventoryPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'pkg-inventory.json'
}

# THE INVENTORY OF ONE ACCOUNT, or the union of every account kept when none is named. The union is what a card
# without a requester can honestly show: "this machine has winget somewhere", with the account that proves it.
function Get-PkgInventory {
    param([string]$Backend = (Get-BackendRoot), [string]$Account)
    try {
        $path = Get-PkgInventoryPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return @() }
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $j) { return @() }
        $rows = @()
        foreach ($prop in $j.PSObject.Properties) {
            if ($Account -and "$($prop.Name)" -ne "$Account") { continue }
            foreach ($m in @($prop.Value.managers)) {
                if (-not $m -or -not $m.id) { continue }
                $rows += [pscustomobject]@{ Id = "$($m.id)"; Source = "$($m.source)"; Version = "$($m.version)"
                                            Account = "$($prop.Name)"; At = "$($prop.Value.at)" }
            }
        }
        # ONE LINE PER MANAGER: the first account that has it answers for it, and the order of accounts is stable.
        $seen = @{}
        $out = @()
        foreach ($row in @($rows | Sort-Object Account, Id)) {
            if ($seen.ContainsKey($row.Id)) { continue }
            $seen[$row.Id] = $true
            $out += $row
        }
        return @($out)
    } catch { return @() }
}

function Update-PkgInventory {
    param([string]$Backend = (Get-BackendRoot), [int]$EveryMinutes = 60)
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    $path = Get-PkgInventoryPath -Backend $Backend
    # ONE ACCOUNT PER PASS, the most overdue of them. Asking three accounts at once would launch eleven processes in
    # three sessions in the same second, and the gate below would hide it.
    $kept = $null
    try { if (Test-PathSafe $path) { $kept = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } } catch { }
    $candidate = $null
    $oldest = $null
    foreach ($row in @(Get-ClientWatchRows -Backend $Backend | Where-Object { $_.Status -eq 'ok' })) {
        $account = "$($row.Account)"
        if (-not $account) { continue }
        # THE GATE IS READ IN TICKS (D44): an ISO date read back from JSON is a [datetime] whose string form is local
        # and no longer parses, so a gate compared as text never holds -- it cost a client app asked every pass.
        $ticks = 0
        try { $ticks = [long]$kept.$account.atTicks } catch { }
        if ($ticks -and ([datetime]::UtcNow - [datetime]$ticks).TotalMinutes -lt $EveryMinutes) { continue }
        if ($null -eq $oldest -or $ticks -lt $oldest) { $oldest = $ticks; $candidate = $account }
    }
    if (-not $candidate) { return $null }
    $answer = $null
    try { $answer = Invoke-ClientTask -Account $candidate -Type 'pkg-inventory' -Module 'tools' -TimeoutSec 60 -Backend $Backend } catch { }
    if (-not $answer -or -not $answer.result -or -not $answer.result.ok) { return $null }
    $entry = [ordered]@{
        at       = ([datetime]::UtcNow).ToString('o')
        atTicks  = ([datetime]::UtcNow).Ticks
        managers = @($answer.result.managers)
    }
    try { Update-StateJson -Path $path -Set @{ $candidate = $entry } | Out-Null } catch { }
    # THE CARDS MUST BE RECOMPUTED: a manager that has just appeared has no card until the probe runs again.
    try { Remove-ProbeCache -Names @('packages.probe.ps1') -Backend $Backend } catch { }
    return [pscustomobject]@{ Account = $candidate; Count = @($answer.result.managers).Count }
}

function Invoke-DiskWatch {
    param([string]$Backend = (Get-BackendRoot))
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    # NOT WHILE HE IS PLAYING: an analysis walks the whole disk, and that is felt.
    if (@(Get-ActiveModes -Backend $Backend).Count) { return $null }

    $dropGb = 10.0
    $minHours = 24
    try { $dropGb = [double](Get-ModuleSetting -Unit 'system' -Key 'AutoScanDropGb' -Backend $Backend) } catch { }
    try { $minHours = [int](Get-ModuleSetting -Unit 'system' -Key 'AutoScanMinHours' -Backend $Backend) } catch { }
    if ($dropGb -le 0) { return $null }

    $statePath = Get-VarPath -Backend $Backend -Kind 'cache' -File 'disk-watch.json'
    $lastTicks = 0
    try {
        if (Test-PathSafe $statePath) {
            $j = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $lastTicks = [long]$j.lastAt
        }
    } catch { }
    $nowUtc = [datetime]::UtcNow
    if ($lastTicks -and ($nowUtc - [datetime]$lastTicks).TotalHours -lt $minHours) { return $null }

    $fall = Get-DiskFreeFall -Backend $Backend -Hours $minHours
    if ($null -eq $fall -or $fall -lt $dropGb) { return $null }

    $fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $depth = 3; $top = 10
    try { $depth = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanDepth' -Backend $Backend) } catch { }
    try { $top = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanTop' -Backend $Backend) } catch { }
    if (-not $depth) { $depth = 3 }
    if (-not $top) { $top = 10 }
    $started = $false
    try {
        $started = [bool](Start-Operation -Module 'storage' -Action 'disk-analyze' -Label 'Analyse automatique du disque' `
                              -Probes @('disk.probe.ps1') -Worker 'disk-scan.worker.ps1' `
                              -ArgsMap @{ root = 'C:\'; depth = $depth; top = $top } -Backend $Backend)
    } catch { }
    # THE DATE IS WRITTEN EVEN IF THE START FAILED: otherwise a refusal would be retried every thirty seconds.
    try { Set-Content -LiteralPath $statePath -Value (@{ lastAt = $nowUtc.Ticks; fall = $fall; started = $started } | ConvertTo-Json -Compress) -Encoding UTF8 } catch { }
    try {
        Write-Log -Backend $Backend -Name 'state' -Level $(if ($started) { 'INFO' } else { 'WARN' }) -Message (
            "chute d'espace : " + $fall.ToString('N1', $fr) + " Go en " + $minHours + " h, seuil " +
            $dropGb.ToString('N1', $fr) + " Go -- analyse " + $(if ($started) { 'lancee' } else { 'non lancee' }))
    } catch { }
    if (-not $started) { return $null }
    return [pscustomobject]@{ FallGb = $fall; At = $nowUtc }
}

<#
    THE VERDICT ON A FACT THAT COMES FROM A LOG (D127) -- written once, for every card that reads one.

    The log says what HAPPENED; a card says what IS. Three things decide, in this order:

      1. THE MEASURE OF THE MOMENT, when the kind can be checked: it confirms, it denies, or nothing can check it.
         What is confirmed weighs whatever its age; what is denied never weighs.
      2. THE AGE, past which the fact is DECLASSED. Declassed does not mean gone (owner, 30/09): the line stays where
         it was, with its state and its figures, and only stops carrying the card's status.
      3. THE RECURRENCE, which is itself a fact of today. "Three times in seven days" is not an accident, and a line
         that says it teaches more than a line that hides it -- so it is said, always, as soon as there is more than
         one.

    Returns Said (what the line reads), Weight ('ok' when it no longer carries the card) and Recurrence.
#>
function Get-JournalFactVerdict {
    param(
        [Parameter(Mandatory)][datetime]$LastAt,
        [int]$Count = 1,
        [int]$WindowDays = 0,
        # 'en cours', 'termine', 'passe' (a past fact by nature) or 'inconnu'.
        [string]$Still = 'inconnu',
        [string]$Level = 'warn',
        [int]$HighlightMinutes = 60
    )
    $minutes = [int][math]::Floor(((Get-Date) - $LastAt).TotalMinutes)
    if ($minutes -lt 0) { $minutes = 0 }
    $recent = ($HighlightMinutes -le 0 -or $minutes -lt $HighlightMinutes)
    $ago = if ($minutes -lt 60) { "il y a $minutes min" }
           elseif ($minutes -lt 2880) { 'il y a ' + [int][math]::Floor($minutes / 60) + ' h' }
           else { 'il y a ' + [int][math]::Floor($minutes / 1440) + ' j' }
    $recurrence = if ($Count -ge 2 -and $WindowDays -gt 0) {
                      "$Count fois en " + $WindowDays + $(if ($WindowDays -gt 1) { ' jours' } else { ' jour' }) + ", la dernière $ago"
                  } elseif ($Count -ge 2) { "$Count fois, la dernière $ago" } else { $ago }
    $said = switch ($Still) {
        'en cours' { 'en cours' }
        'termine'  { "ce n'est plus le cas" }
        'passe'    { 'arrivé' }
        default    { $(if ($recent) { "on ne sait pas si c'est encore le cas" } else { 'arrivé' }) }
    }
    $weight = if ($Still -eq 'en cours') { $Level }
              elseif ($Still -eq 'termine') { 'ok' }
              elseif ($recent) { $Level }
              else { 'ok' }
    return [pscustomobject]@{ Said = $said; Weight = $weight; Recurrence = $recurrence; Recent = $recent; Minutes = $minutes }
}

<#
    THE EPHEMERAL RANGE OF BOTH PROTOCOLS, READ ONCE AN HOUR AND AFTER EACH START OF WINDOWS.

    Get-EphemeralPortRange runs netsh, which is a process to start: 200 ms per protocol, measured, against 3 ms for
    reading the ports in use. Asking it at every pass of the watch would make the range cost a hundred times what it
    guards. It changes at a setting or a restart, so an hour is generous.

    This was written inside net.probe.ps1 and is now shared with the port watch: one reading, one definition (D15).
#>
function Get-EphemeralPortRanges {
    param([string]$Backend = (Get-BackendRoot))
    $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'dynamic-ports.json'
    $nowT = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $bootAt = $nowT - [long]([Environment]::TickCount64 / 1000)
    $ranges = $null
    if (Test-PathSafe $file) { try { $ranges = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    if ($ranges -and $ranges.tcp -and $ranges.udp -and
        [math]::Abs([long]$ranges.bootAt - $bootAt) -le 120 -and ($nowT - [long]$ranges.readAt) -le 3600) {
        return $ranges
    }
    $tcp = Get-EphemeralPortRange -Protocol 'tcp'
    $udp = Get-EphemeralPortRange -Protocol 'udp'
    if (-not $tcp -or -not $udp) { return $ranges }
    try { $null = Update-StateJson -Path $file -Set @{ bootAt = $bootAt; readAt = $nowT; tcp = $tcp; udp = $udp } } catch { }
    return [pscustomobject]@{ bootAt = $bootAt; readAt = $nowT; tcp = [pscustomobject]$tcp; udp = [pscustomobject]$udp }
}

<#
    THE EPHEMERAL PORTS, WATCHED WHERE THEY EMPTY -- and written only when there is something to read.

    Why: Windows logs "all ephemeral ports are in use" (Tcpip 4231/4266) 75 times since 25/07 on this computer, and
    two identical events are never closer than six hours -- it suppresses the repeats, so the count is a floor, not a
    total. By the time anyone reads the card, the reserve is back to 1 % and the table names processes that had
    nothing to do with it. The card's advice -- close the one holding the most -- was therefore unusable.

    What this does: READS at every pass, which costs 2,8 ms measured for TCP and UDP together, and WRITES only when
    the occupancy reaches PortWatchPercent, or during the PortWatchAfterMinutes that follow one of those events.
    While the reserve is idle, not one line is written: a point every thirty seconds saying "1 %" teaches no one
    anything and fills the disk of the machine whose disk we watch.

    The event log is re-read at most every five minutes, and the answer kept: Get-WinEvent costs far more than the
    port reading it guards, so asking it thirty times a minute would cost more than the whole watch.
#>
function Invoke-PortWatch {
    param([string]$Backend = (Get-BackendRoot))
    $percent = 50
    $afterMin = 15
    try { $percent = [int](Get-ModuleSetting -Unit 'network' -Key 'PortWatchPercent' -Backend $Backend) } catch { }
    try { $afterMin = [int](Get-ModuleSetting -Unit 'network' -Key 'PortWatchAfterMinutes' -Backend $Backend) } catch { }

    $ranges = $null
    try { $ranges = Get-EphemeralPortRanges -Backend $Backend } catch { }
    if (-not $ranges -or -not $ranges.tcp -or -not $ranges.udp) { return $null }
    $usage = @{}
    $worst = 0
    foreach ($proto in 'tcp', 'udp') {
        $range = $ranges.$proto
        $u = $null
        try { $u = Get-EphemeralPortUsage -Protocol $proto -Start ([int]$range.Start) -Count ([int]$range.Count) } catch { }
        if (-not $u -or $u.Limit -le 0) { continue }
        $usage[$proto] = $u
        $pct = [int][math]::Round(100.0 * $u.Used / $u.Limit)
        if ($pct -gt $worst) { $worst = $pct }
    }
    if (-not $usage.Count) { return $null }

    # THE LAST COMPLAINT OF WINDOWS, asked at most every five minutes and kept in between.
    $statePath = Get-VarPath -Backend $Backend -Kind 'cache' -File 'port-watch.json'
    $nowUtc = [datetime]::UtcNow
    $askedTicks = 0
    $eventTicks = 0
    try {
        if (Test-PathSafe $statePath) {
            $j = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $askedTicks = [long]$j.askedAt
            $eventTicks = [long]$j.eventAt
        }
    } catch { }
    if ($afterMin -gt 0 -and (-not $askedTicks -or ($nowUtc - [datetime]$askedTicks).TotalMinutes -ge 5)) {
        try {
            $last = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Tcpip'; Id = 4231, 4266
                                                       StartTime = $nowUtc.ToLocalTime().AddMinutes(-($afterMin + 10)) } -ErrorAction Stop |
                      Sort-Object TimeCreated -Descending | Select-Object -First 1)
            if ($last.Count) { $eventTicks = $last[0].TimeCreated.ToUniversalTime().Ticks }
        } catch { }
        $askedTicks = $nowUtc.Ticks
        try { $null = Update-StateJson -Path $statePath -Set @{ askedAt = $askedTicks; eventAt = $eventTicks } } catch { }
    }
    $afterComplaint = ($afterMin -gt 0 -and $eventTicks -and ($nowUtc - [datetime]$eventTicks).TotalMinutes -le $afterMin)

    # NOTHING TO SAY: the reserve is idle and Windows has not complained. We read, we keep nothing.
    if (-not $afterComplaint -and ($percent -ge 100 -or $worst -lt $percent)) { return $null }

    <#
        AND HERE, AND ONLY HERE, THE COMPLETE READING -- the one that costs.

        The cheap gauge above comes from GetExtendedTcpTable, which lists the CONNECTIONS. A socket merely BOUND to a
        port -- bind() called, neither listening nor connected -- holds that port and appears in none of those tables.
        Measured on 30/09: 128 counted against 381 distinct ephemeral ports really held, 335 of them bound. The
        difference is not noise, it is the whole phenomenon: WSL's network host alone held 244 bound ports that Vigie
        could not see, while the card announced 1 %.

        Get-NetTCPConnection does see them, and costs 1,5 s -- fifty times the cheap reading. It is therefore taken
        only when we have decided there is something to write: at the threshold, or in the minutes that follow a
        complaint from Windows. The rest of the time nobody pays for it.
    #>
    $boundTop = @()
    $distinct = 0
    $held = $null
    try { $held = Get-HeldEphemeralPorts -Start ([int]$ranges.tcp.Start) } catch { }
    if ($held) {
        $distinct = [int]$held.Held
        foreach ($o in @($held.ByProcess | Select-Object -First 5)) {
            $pn = "$((Get-Process -Id $o.ProcessId -ErrorAction SilentlyContinue).ProcessName)"
            if (-not $pn) { $pn = "pid $($o.ProcessId)" }
            $boundTop += @{ n = $pn; pid = [int]$o.ProcessId; c = [int]$o.Count; s = "$($o.States)" }
        }
    }

    $point = [ordered]@{ t = $nowUtc.ToString('o'); v = $worst; why = $(if ($afterComplaint) { 'plainte' } else { 'seuil' }) }
    if ($distinct) { $point.held = $distinct; $point.holders = $boundTop }
    foreach ($proto in 'tcp', 'udp') {
        if (-not $usage[$proto]) { continue }
        $holders = @()
        foreach ($o in @($usage[$proto].ByProcess | Select-Object -First 5)) {
            $name = if ($o.ProcessId -eq 0) { 'TIME_WAIT' } else {
                $pn = "$((Get-Process -Id $o.ProcessId -ErrorAction SilentlyContinue).ProcessName)"
                if (-not $pn) { $pn = "pid $($o.ProcessId)" }
                $pn
            }
            $holders += @{ n = $name; pid = [int]$o.ProcessId; c = [int]$o.Count }
        }
        $point[$proto] = @{ used = [int]$usage[$proto].Used; limit = [int]$usage[$proto].Limit; top = $holders }
    }
    try { $null = Write-HistoryPoint -Backend $Backend -MeasureId 'net.ports' -Point ([pscustomobject]$point) } catch { }
    return [pscustomobject]@{ Percent = $worst; AfterComplaint = $afterComplaint }
}

<#
    DUE NOW. An action that changes something invalidates the cards it changed, and those cards must not then wait
    for their interval -- up to an hour for some. Invalidating therefore also tells the scheduler, which picks them
    up at its next pass, thirty seconds at most.
#>
function Reset-RefreshDue {
    param([string]$Backend = (Get-BackendRoot), [Parameter(Mandatory)][string[]]$Probes)
    $state = Get-RefreshState -Backend $Backend
    foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
        if ($Probes -notcontains $d.Probe) { continue }
        $entry = $state[$d.Key]
        if (-not $entry) { $entry = @{ fails = 0 } }
        $entry.lastStartedAt = 0
        $entry.nextAt = 0
        Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
    }
}

function Invoke-RefreshPass {
    param([string]$Backend = (Get-BackendRoot))
    # SILENT WHILE AN INSTALLATION RUNS, like the rest of the watch: the files move underfoot.
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return @() }
    }
    $decls = @(Get-RefreshDeclarations -Backend $Backend)
    if (-not $decls.Count) { return @() }
    $cfg = Get-RefreshConfig -Backend $Backend
    $state = Get-RefreshState -Backend $Backend
    $modes = @(Get-ActiveModes -Backend $Backend)
    $nowTicks = [datetime]::UtcNow.Ticks
    $running = 0

    # 1. WHAT IS STILL RUNNING, and what only looks like it. A process that is gone leaves its line behind; a process
    #    that overstays is named once and stops holding a place -- it is not stopped.
    foreach ($d in $decls) {
        $entry = $state[$d.Key]
        if (-not $entry -or -not [int]$entry.pid) { continue }
        $alive = $false
        try { $alive = [bool](Get-Process -Id ([int]$entry.pid) -ErrorAction Stop) } catch { }
        if (-not $alive) {
            $entry.pid = 0; $entry.long = $false
            Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
            continue
        }
        $elapsed = ($nowTicks - [long]$entry.startedAt) / 1e7
        $max = $(if ($d.MaxSeconds) { [int]$d.MaxSeconds } else { [int]$cfg.DefaultMaxSeconds })
        if ($elapsed -ge $max -and -not $entry.long) {
            $entry.long = $true
            Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
            try {
                Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                    "calcul trop long : $($d.Key), PID $($entry.pid), " + [int]$elapsed + " s (limite $max s)")
                $line = [ordered]@{ at = ([datetime]::UtcNow).ToString('o'); key = $d.Key
                                    pid = [int]$entry.pid; seconds = [int]$elapsed; max = $max }
                Add-HistoryLine -Path (Get-VarPath -Backend $Backend -Kind 'history' -File 'refresh-long.jsonl') `
                                -Line ($line | ConvertTo-Json -Depth 4 -Compress) | Out-Null
            } catch { }
        }
        # A computation past its limit no longer counts against the limit: the others must not wait for it.
        if (-not $entry.long) { $running++ }
    }

    # 2. WHAT IS DUE, on elapsed time, and never on a number of passes.
    $due = @()
    foreach ($d in $decls) {
        $entry = $state[$d.Key]
        if ($entry -and [int]$entry.pid -and -not $d.Parallel) { continue }
        $interval = Get-RefreshInterval -Declaration $d -Modes $modes
        if ($interval -le 0) { continue }
        if ($d.OnlyWhen -and ($modes -notcontains $d.OnlyWhen)) { continue }
        if ($entry -and [long]$entry.nextAt -gt $nowTicks) { continue }
        $since = [double]::MaxValue
        if ($entry -and [long]$entry.lastStartedAt) { $since = ($nowTicks - [long]$entry.lastStartedAt) / 1e7 }
        if ($since -lt $interval) { continue }
        $due += [pscustomobject]@{ D = $d; Overdue = $since - $interval }
    }

    <#
        3. THE MOST OVERDUE FIRST, up to the limit -- AND A TIE IS BROKEN, NEVER LEFT TO CHANCE.

        A computation that has never run has no last start, so its lateness is infinite. On a fresh state that is
        true of EVERY declaration at once, and Sort-Object gives no order to equal values: three were picked out of
        fifteen, arbitrarily, and the same ones kept being picked. Measured on 30/09, on this computer: the two
        computations of the Debogage module had NEVER been started since the scheduler exists -- no entry, no
        failure, nothing to see. Their cards had been showing a measure 29 hours and 10 days old, as if fresh.

        The key breaks the tie. It is stable, it is ours, and after one pass every declaration has a real timestamp,
        so the order goes back to being decided by lateness alone.
    #>
    $started = @()
    foreach ($item in @($due | Sort-Object @{ Expression = { $_.Overdue }; Descending = $true },
                                            @{ Expression = { $_.D.Key };  Descending = $false })) {
        if ([int]$cfg.MaxParallel -gt 0 -and $running -ge [int]$cfg.MaxParallel) { break }
        $d = $item.D
        # NOT $pid: PowerShell owns that name and refuses to have it written to.
        $childPid = $null
        try {
            $childPid = Start-DetachedAction -Backend $Backend `
                        -Script (Join-Path $Backend 'workers/refresh.worker.ps1') `
                        -ArgsMap @{ key = $d.Key; probe = $d.Probe; account = "$($d.Account)" }
        } catch { }
        <#
            A REFUSED LAUNCH IS A FAILURE OF THE COMPUTATION, and it is counted as one.

            It used to be a bare "continue": nothing written, no entry, no failure, no trace. The card then froze for
            ever while the state stayed silent -- and, worse, a computation that has never started is the latest of
            all, so it came back first at every pass and was refused again. A silent refusal that repeats for ever is
            the shape this very scheduler was written to prevent (D125).

            Counted as a failure, it takes the doubling delay like the others: it stops being the oldest, it stops
            holding the first place, and the card says it.
        #>
        if (-not $childPid) {
            $entry = $state[$d.Key]
            if (-not $entry) { $entry = @{ fails = 0 } }
            $cfgFail = Get-RefreshConfig -Backend $Backend
            $entry.fails = [int]$entry.fails + 1
            $wait = [Math]::Min([int]$cfgFail.FailBackoffSeconds * [Math]::Pow(2, [int]$entry.fails - 1), [int]$cfgFail.FailBackoffMaxSeconds)
            $entry.nextAt = [datetime]::UtcNow.AddSeconds($wait).Ticks
            $entry.lastError = 'le lancement a été refusé (plafond de tâches de fond, ou démarrage impossible)'
            $state[$d.Key] = $entry
            Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
            try {
                Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (
                    "planifie : " + $d.Key + " n'a pas pu demarrer (" + $entry.fails + ") ; prochaine tentative dans " + [int]$wait + " s")
            } catch { }
            continue
        }
        $entry = $state[$d.Key]
        if (-not $entry) { $entry = @{ fails = 0 } }
        $entry.pid = [int]$childPid
        $entry.startedAt = $nowTicks
        $entry.lastStartedAt = $nowTicks
        $entry.long = $false
        $state[$d.Key] = $entry
        Update-RefreshState -Backend $Backend -Key $d.Key -Entry $entry
        $started += $d.Key
        $running++
    }
    return $started
}

<#
    WHAT THE SCHEDULER HAS TO SAY, read by the self-watch card -- which only reads, never acts (D14).
#>
function Get-RefreshRows {
    param([string]$Backend = (Get-BackendRoot))
    $cfg = Get-RefreshConfig -Backend $Backend
    $state = Get-RefreshState -Backend $Backend
    $modes = @(Get-ActiveModes -Backend $Backend)
    $nowTicks = [datetime]::UtcNow.Ticks
    $rows = @()
    foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
        $entry = $state[$d.Key]
        $interval = Get-RefreshInterval -Declaration $d -Modes $modes
        $said = $(if ($interval -gt 0) { "toutes les $interval s" } else { 'à la demande' })
        $status = 'ok'
        if ($entry -and [int]$entry.pid) {
            $elapsed = [int](($nowTicks - [long]$entry.startedAt) / 1e7)
            $said = "en cours depuis $elapsed s"
            if ($entry.long) { $said = "TROP LONG : $elapsed s"; $status = 'warn' }
        } elseif ($entry -and [int]$entry.fails) {
            $said = "$($entry.fails) échec(s) : $($entry.lastError)"
            $status = 'warn'
        }
        $rows += [pscustomobject]@{
            Key    = $d.Key
            Said   = $said
            Status = $status
            Ms     = $(if ($entry) { [int]$entry.lastMs } else { 0 })
            At     = $(if ($entry -and [long]$entry.lastEndedAt) { [datetime]([long]$entry.lastEndedAt) } else { $null })
        }
    }
    return $rows
}

<#
    WATCH TASKS: WHAT THE SERVER APP DOES BY ITSELF, SEEN LIKE EVERYTHING ELSE.

    Every thirty seconds the server app does seven jobs nobody asked for: reading the sentinels, launching the card
    computations that are due, looking at free disk space, questioning WSL, sampling the ports. None of them showed
    anywhere. If one hung, nothing said so, and the cards it feeds aged in silence -- on 06/10 it took digging
    through logs an ordinary session cannot even open to learn why a card stayed grey.

    CORE-OPERATIONS required it from the start: EVERY operation of Vigie is seen while it lasts. So this was a
    defect, not an improvement -- and the design page had written the opposite.

    THE MECHANISM ALREADY EXISTS and is not doubled: a mark set before, a result written after, /operations serving
    both. A watch task enters it under the reserved module `veille`. Nothing new: no file, no route, no reader.

    WHAT IT COSTS: eight writes of 150 bytes per thirty-second round, 23 000 a day. Measured rather than assumed:
    4 KB per write, 92 MB a day, 34 GB a year -- one hundredth of a percent of an ordinary disk's endurance. The
    price is negligible, and it is the minimum: with no mark there is nothing to look at.

    Full design: doc/progress/targeting/operations.md, in the section on the design that was settled.
#>
function Invoke-WatchCycle {
    param([Parameter(Mandatory)][scriptblock]$Body, [string]$Backend = (Get-BackendRoot))
    # THE ROUND CARRIES A CEILING OF ITS OWN, wider than the sum of theirs: a round that passes it is stuck
    # somewhere, even if no single task declared itself.
    Set-ModuleBusyMark -Module 'veille' -Label (Get-Label 'common.veille-tour') -ProcessId $PID `
                       -Action 'watch-cycle' -Resources @() -MaxSeconds 180 -Backend $Backend
    try { & $Body }
    finally { Clear-ModuleBusyMark -Module 'veille' -Backend $Backend }
}

<#
    ONE WATCH TASK, WRAPPED.

    The body knows nothing of the mark: it measures, it computes, it returns. The wrapper sets, judges and reports.
    Adding a task tomorrow means wrapping it in this function, and nothing else.

    An overrun is written ONCE per occurrence, as an operation result: it then shows among the recent results
    whatever card is switched on, and the card about Vigie's own processes picks it up so the bubble leaves --
    every error reaches the user, a rule the owner restated on 07/10.
#>
function Invoke-WatchTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][int]$MaxSeconds,
        [Parameter(Mandatory)][scriptblock]$Body,
        [string]$Backend = (Get-BackendRoot)
    )
    Set-ModuleBusyMark -Module 'veille' -Label $Label -ProcessId $PID -Action ('watch:' + $Name) `
                       -Resources @() -MaxSeconds $MaxSeconds -Backend $Backend
    $t0 = Get-Date
    try { & $Body }
    finally {
        $seconds = [int]((Get-Date) - $t0).TotalSeconds
        if ($seconds -gt $MaxSeconds) {
            try {
                Set-ModuleLastRun -Module 'veille' -Action ('watch:' + $Name) -Label $Label -Code 1 `
                                  -Seconds $seconds -Error (Get-Label 'common.veille-trop-longue' $MaxSeconds) -Backend $Backend
                Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' `
                          -Message (Get-Label 'common.veille-depassement' $Name $seconds $MaxSeconds)
            } catch { }
        }
    }
}

function Invoke-WatchPass {
    param([string]$Backend = (Get-BackendRoot))
    <#
        SILENT WHILE AN INSTALLATION RUNS -- the target said so, the code did not.

        An update replaces the files under the watch's feet and restarts the server: the
        resident is not armed yet, so the game sentinel reads "inconnu", then "aucun" a
        minute later. Two alerts, on every single deployment, describing nothing but our own
        work -- measured on 03/09 at 09:39 and 09:40. An alert series that fills up with the
        deployments teaches its reader to ignore it.

        The lock already exists and already says it: an installation holds the resource
        'machine'. We ask it, and we say nothing at all -- no reading, no memory write, no
        event. What the pass would have seen is not lost: it is read at the next pass, once
        the machine belongs to us again.
    #>
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    $memoryPath = Get-WatchMemoryPath -Backend $Backend
    $memory = @{}
    if (Test-PathSafe $memoryPath) {
        try { $j = Get-Content $memoryPath -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $memory[$p.Name] = $p.Value } } catch { }
    }
    $now = [datetime]::UtcNow
    $events = @()
    $toRecompute = @()
    $changed = $false

    foreach ($w in @(Get-WatchDeclarations -Backend $Backend)) {
        $known = $memory[$w.Key]
        $due = $true
        if ($known -and $known.at) {
            try { $due = ($now - (ConvertTo-UtcDate $known.at)).TotalSeconds -ge $w.Seconds } catch { }
        }
        if (-not $due) { continue }

        $value = $null
        try { $value = "$(& $w.Script 2>$null | Select-Object -Last 1)".Trim() }
        catch {
            # A READING THAT FAILS IS A VALUE LIKE ANY OTHER: "we do not know" is a state,
            # and its appearance deserves an event as much as any other change.
            #
            # BUT THE VALUE STAYS "erreur", WITHOUT THE MESSAGE. A message often carries a
            # delay, a time or an identifier: it changes at every pass, every pass then
            # passes for a change, and a breakdown that lasts writes one history line a
            # minute -- thousands of lines all saying the same thing. The detail goes to the
            # log, where it costs nothing and where it is looked for when needed.
            $value = 'erreur'
            try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -NoEcho `
                            -Message ("veille : " + $w.Key + " a echoue -- " + $_.Exception.Message) } catch { }
        }

        $before = $(if ($known) { "$($known.value)" } else { $null })
        $memory[$w.Key] = @{ value = $value; at = $now.ToString('o') }
        $changed = $true
        # A READING THAT CHANGES MAKES A LINE OF HISTORY. The watch's memory keeps only the
        # last state -- it answers "where are we?", never "since when?" nor "how many times
        # tonight?". The history keeps the succession of states AND what each one triggered:
        # it is the trace of the alert.
        # The very first reading is written down too, or the series begins in a void.
        if ($null -eq $before -or $before -ne $value) {
            Write-SentinelSample -Backend $Backend -Key $w.Key -From $before -To $value -Cards @($w.Cards)
        }
        if ($null -ne $before -and $before -ne $value) {
            $events += [pscustomobject]@{ Key = $w.Key; Label = $w.Label; From = $before; To = $value; Cards = @($w.Cards) }
            $toRecompute += @($w.Cards)
        }
    }

    if ($changed) {
        try {
            $tmp = "$memoryPath.tmp"
            ($memory | ConvertTo-Json -Depth 6) | Out-File -FilePath $tmp -Encoding UTF8
            Move-Item -Path $tmp -Destination $memoryPath -Force
        } catch { }
    }

    foreach ($e in $events) {
        Write-Log -Backend $Backend -Name 'state' -NoEcho `
                  -Message ("veille : " + $e.Label + " passe de « " + $e.From + " » a « " + $e.To + " »")
    }

    # THE CARDS NAMED, THROUGH THE EXISTING PATH. We aim at the PROBES of the card's folder:
    # the same resolution a card's button uses.
    <#
        A SENTINEL THAT CHANGED ASKS, IT DOES NOT COMPUTE. Computing here held the watch loop for as long as the card
        took -- thirteen seconds for the deployment one -- while the scheduler, one line below, is made for exactly
        this. The card is marked due and taken at this very pass.
    #>
    $cards = @($toRecompute | Where-Object { $_ } | Select-Object -Unique)
    foreach ($card in $cards) {
        $probes = @()
        foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
            if (@($d.Cards) -contains $card) { $probes += $d.Probe }
        }
        if ($probes.Count) { try { Reset-RefreshDue -Backend $Backend -Probes $probes } catch { } }
        else { try { $null = Get-State -Backend $Backend -ForceModule $card -WaitSeconds 30 } catch { } }
    }
    # AND THE SCHEDULER'S PASS (D124): a change is not the only reason to compute. What must be sampled is sampled
    # because the server watches, not because someone is looking.
    Invoke-WatchTask -Name 'scheduler' -Label (Get-Label 'common.veille-ordonnanceur') -MaxSeconds 10 -Backend $Backend -Body {
        try { $null = Invoke-RefreshPass -Backend $Backend } catch { }
    }
    # AND THE DISK, when it empties faster than anyone would notice.
    Invoke-WatchTask -Name 'disk' -Label (Get-Label 'common.veille-disque') -MaxSeconds 5 -Backend $Backend -Body {
        try { $null = Invoke-DiskWatch -Backend $Backend } catch { }
    }
    # AND WHAT WSL HOLDS INSIDE, which only a session can see.
    Invoke-WatchTask -Name 'wsl' -Label (Get-Label 'common.veille-wsl') -MaxSeconds 25 -Backend $Backend -Body {
        try { $null = Update-WslUsage -Backend $Backend } catch { }
    }
    # AND WHICH PACKAGE MANAGERS EACH ACCOUNT HAS, for the same reason: one installed in a profile is invisible from
    # the service account, and winget was missing from the panel until 05/10 for exactly that.
    Invoke-WatchTask -Name 'packages' -Label (Get-Label 'common.veille-paquets') -MaxSeconds 65 -Backend $Backend -Body {
        try { $null = Update-PkgInventory -Backend $Backend } catch { }
    }
    # AND THE EPHEMERAL PORTS, read every pass, written only when they fill or right after Windows complains.
    Invoke-WatchTask -Name 'ports' -Label (Get-Label 'common.veille-ports') -MaxSeconds 5 -Backend $Backend -Body {
        try { $null = Invoke-PortWatch -Backend $Backend } catch { }
    }
    return $events
}

# --- Aggregating the probes (logged) ----------------------------------------
# How long a probe's cache stays valid, in seconds: short for what moves fast, long for what
# is stable.
# THE GAME MODE: WHILE A GAME RUNS, VIGIE STEPS BACK.
#
# Measured on 28/09, an ACOdyssey session of 77 minutes: 383 card recomputations, 1582 s of processing, 34 % of one
# core without pause -- 400 s for the packages card alone (winget, choco, pip), 301 s for the gaming card, 213 s for
# the network. The game stuttered, and Vigie had its share in it. Every request from the interface hands one stale
# probe to a background task; with caches of five seconds, everything is always stale.
#
# During a game, the cards that speak of the game keep their pace; the others go to a quarter of an hour at least,
# and the heavy ones to an hour. An explicit request (the card's refresh button) always goes through: the game mode
# slows the background down, it forbids nothing.
# THE CARDS THAT STILL WATCH THE GAME, each with the pace it keeps while playing. They are the only ones left
# quick, so they would otherwise run far more often than before -- the opposite of the aim: the gaming card costs
# 5.5 s per recomputation (244 times on 28/09, 22 minutes of processor for the day alone).
$script:GameModeUseful = @{ 'gaming.probe.ps1' = 30; 'perf.probe.ps1' = 20; 'self.probe.ps1' = 120; 'vigie.probe.ps1' = 300 }
$script:GameModeHeavy  = @('packages.probe.ps1', 'deployment.probe.ps1', 'lock.probe.ps1', 'pending.probe.ps1',
                           'accounts.probe.ps1', 'history.probe.ps1', 'wsl.probe.ps1', 'os.probe.ps1')
$script:GameModeFloor  = 900      # the other cards: a quarter of an hour at least
$script:GameModeHeavyTtl = 3600   # the heavy ones: one hour

# A probe's cache duration at this instant, game mode included. With no game running, it is the table below.
# -Base gives the duration OUTSIDE any game: comparing the two says whether a card is held back, and the card then
# says so itself rather than leaving the reader with a figure quietly twenty minutes old (28/09).
function Get-ProbeTtlNow {
    param([Parameter(Mandatory)][string]$Name, [int]$Default = 30, [string]$Backend = (Get-BackendRoot), [switch]$InGame, [switch]$Base)
    if ($Base) { return $(if ($script:ProbeTtls.ContainsKey($Name)) { [int]$script:ProbeTtls[$Name] } else { $Default }) }
    $ttl = $(if ($script:ProbeTtls.ContainsKey($Name)) { [int]$script:ProbeTtls[$Name] } else { $Default })
    # THE STORAGE CARD FOLLOWS ITS ANALYSIS: while the scan writes its progress, the card must show it moving.
    if ($Name -eq 'disk.probe.ps1') {
        try {
            $scanFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan.json'
            if ((Test-PathSafe $scanFile) -and (([datetime]::UtcNow - (Get-Item -LiteralPath $scanFile).LastWriteTimeUtc).TotalMinutes -lt 2)) { return 5 }
        } catch { }
    }
    if (-not $InGame) { return $ttl }
    if ($script:GameModeUseful.ContainsKey($Name)) { return [Math]::Max($ttl, [int]$script:GameModeUseful[$Name]) }
    if ($script:GameModeHeavy -contains $Name) { return [Math]::Max($ttl, $script:GameModeHeavyTtl) }
    return [Math]::Max($ttl * 20, $script:GameModeFloor)
}

# IS A GAME RUNNING? Its name, or $null. Reads the session state, whose process is checked (Get-GameSession): a
# closed game does not keep Vigie stepped back. Never throws.
function Get-GameModeName {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $session = Get-GameSession -Backend $Backend
        if ($session -and $session.name) { return "$($session.name)" }
    } catch { }
    return $null
}

<#
    WHAT A CARD COSTS DECIDES HOW LONG IT KEEPS.

    Every request from the interface hands ONE stale probe to a background task. With a cache of five seconds, a
    card is stale at almost every request, and the cheapness of the reading stops mattering: measured over the day
    of 28/09, the packages card was recomputed 305 times for 1128 s of processing (3.7 s each, winget, choco, pip)
    and the network card 171 times for 713 s. Nobody asked for winget five times a minute.

    The durations below therefore follow the COST, not the wish: a card that takes seconds keeps for minutes. What
    keeps the cards honest is elsewhere and untouched -- an action invalidates the cards it changes, the refresh
    button forces a recomputation, and a sentinel recalculates its cards the moment its value moves (connection,
    power, game). The storage card is the exception: while an analysis runs, it carries its progress, and a
    progress shown once a minute is not a progress.
#>
$script:ProbeTtls = @{
    # 15, not 8: the card costs 1.1 s per recomputation, and nobody reads the processor load eight times a minute.
    'perf.probe.ps1'    = 15
    # 60, not 15: the probe takes 4.2 s (connection test with timeouts), and the 'internet' sentinel recalculates
    # this card the moment the connection moves.
    'net.probe.ps1'     = 60
    # 60, not 600: the card carries the memory of the virtual machine, which moves by gigabytes; the probe costs 0.1 s.
    'wsl.probe.ps1'     = 60
    # 60 at rest, 5 while a space analysis runs (Get-ProbeTtlNow): the card carries its progress (D60), and a
    # progress refreshed once a minute is not a progress.
    'disk.probe.ps1'    = 60
    # 300, not 5: winget, choco and pip are questioned each time, 3.7 s per pass. An upgrade invalidates this card
    # itself (result.invalidate), so nothing waits five minutes to be seen.
    'packages.probe.ps1' = 300
    # 60: the 'power' sentinel already recalculates this card whenever the current changes direction.
    'power.probe.ps1'   = 60
    'history.probe.ps1' = 120
    'firewall.probe.ps1'= 120
    'defender.probe.ps1'= 300
    'vbs.probe.ps1'     = 300
    'lock.probe.ps1'    = 600
    'pending.probe.ps1' = 900
    # ACCOUNTS CHANGE RARELY: creating a Windows account does not happen within the day. One
    # hour, and the "Actualiser la liste" button for whoever has just created one.
    'accounts.probe.ps1' = 3600
    # THE DEPLOYMENT, on the other hand, MUST SEE A COMMIT ARRIVE -- and it is deferrable, so
    # this short delay costs the request nothing: it leaves with the value already known.
    'deployment.probe.ps1' = 60
    'os.probe.ps1'      = 3600
    # THE SYSTEM LOG: read in 0.08 s, and a serious error must show within the minute.
    'events.probe.ps1'  = 60
    # VIGIE'S OWN PROCESSES: a runaway must show within the minute, and the reading costs a few milliseconds.
    'self.probe.ps1'    = 30
    # 30, not 10: 5.5 s per recomputation on 28/09 -- the most expensive card of all, and the one a game keeps quick.
    'gaming.probe.ps1'  = 30
}

# Brings a date read from JSON back to a UTC [datetime], whatever its shape.
#
# ConvertFrom-Json sometimes converts ISO-8601 strings into [datetime] itself: depending on
# the path one receives a string or an object, and the Kind may be Utc, Local or Unspecified.
# Comparing without normalising gives an age wrong by several hours -- which is what made the
# state cache useless. So the conversion happens HERE, in one single place.
function ConvertTo-UtcDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    $d = if ($Value -is [datetime]) { $Value }
         else { [datetimeoffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
    switch ($d.Kind) {
        'Local'       { return $d.ToUniversalTime() }
        'Unspecified' { return [datetime]::SpecifyKind($d, [DateTimeKind]::Utc) }
        default       { return $d }
    }
}

# --- The log of probe runs ---------------------------------------------------
# EVERY real run of a probe and its duration are kept, SYSTEMATICALLY, wherever it comes
# from: a user's request, a background refresh, or the contract check. Without that trace,
# "Vigie sometimes takes a long time to load" stays an impression: one knows neither WHICH
# probe cost the time, nor whether it is usual.
#
# Format: one JSON line per run (JSONL). Append-only, so the file is never read back in order
# to write -- which is what makes it usable under concurrency.
# This log is also the first sampling the history will rest on.
$script:ProbeRunMaxBytes = 1.5MB   # au-dela, on ne garde que les passages recents
$script:ProbeRunKeepLines = 5000

function Write-ProbeRun {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Probe,
        [Parameter(Mandatory)][int]$Ms,
        # Where the run came from: 'forced' (the Refresh button), 'background' (a worker),
        # 'check' (the contract check).
        [string]$Origin = 'background',
        [ValidateSet('ok','error','empty')][string]$Outcome = 'ok',
        [int]$Modules = 0,
        [string]$Detail
    )
    try {
        $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'probe-runs.jsonl'
        $rec = [ordered]@{
            at      = [datetime]::UtcNow.ToString('o')
            probe   = $Probe
            ms      = $Ms
            origin  = $Origin
            outcome = $Outcome
            modules = $Modules
        }
        if ($Detail) { $rec.detail = $Detail }
        $line = ($rec | ConvertTo-Json -Compress -Depth 4)

        $mx = New-Object System.Threading.Mutex($false, 'Local\VigieProbeRuns')
        $got = $false
        try {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if (-not $got) { return }

            [IO.File]::AppendAllText($file, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

            # A lazy purge: the file is only read when it has really grown.
            $fi = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
            if ($fi -and $fi.Length -gt $script:ProbeRunMaxBytes) {
                $lines = [IO.File]::ReadAllLines($file)
                if ($lines.Count -gt $script:ProbeRunKeepLines) {
                    $garde = $lines[($lines.Count - $script:ProbeRunKeepLines)..($lines.Count - 1)]
                    [IO.File]::WriteAllLines($file, $garde, [Text.UTF8Encoding]::new($false))
                }
            }
        } finally {
            if ($got) { try { $mx.ReleaseMutex() } catch { } }
            try { $mx.Dispose() } catch { }
        }
    } catch {
        # The log must NEVER make a probe fail: it observes, it does not arbitrate.
    }
}
# --- The history of measurements (series) -------------------------------------
# Values already computed by the probes are noted IN PASSING: the only hook is a probe's
# successful recomputation inside Get-State -- no probe writes by itself, and the history has
# no cadence of its own. Storage: one JSONL file per measurement in var/history/ (distinct
# from var/cache/: a lost history does not recompute itself). Best effort: a write error is
# logged and never makes a recomputation fail.
#
# THE catalogue of measurements (D15: one value, one definition). For each of them: the
# source probe, its nature (gauge/event), its unit, the default minimum interval (which the
# configuration can override, see Get-HistoryConfig) and the extractor, which reads the value
# from the MODULES THE PROBE RETURNED -- never by running anything again.
# The extractor returns $null (nothing to note) or @{ v = <value>; key = <optional token> }.
# `key` serves measurements tied to an external one: a point is written only when it changes.
# For instance net.latency only has a NEW value when `measAt` moves, whatever the number of
# recomputations of the probe between two throughput or latency measurements.
$script:MeasureCatalog = @{
    'disk.free' = @{
        # Tolerance: one gigabyte. Below that, free space has not moved for whoever reads it.
        Probe = 'disk.probe.ps1'; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 30; Tolerance = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'storage' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'free' } | Select-Object -First 1
            if ($null -eq $f -or $null -eq $f.value) { return $null }
            $v = 0.0
            if (-not [double]::TryParse("$($f.value)", [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
            return @{ v = $v }
        }
    }
    # A game session (the gaming module): noted ONLY while a game runs -- the very presence of
    # the points tells the session (start, end, intensity). The game's name travels with each
    # point (field n), to answer "why was it slow last night?" without displaying anything
    # (Q2: recording only).
    'game.gpu' = @{
        # Tolerance: five points. A GPU swinging between 22 and 25 % tells nothing -- that is
        # the noise of an instantaneous measurement, not a variation of the game.
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = '%'; IntervalMinutes = 1; Tolerance = 5
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $r = @($m.fields) | Where-Object { "$($_.key)" -eq 'game-res' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $r) { return $null }
            if ("$($r.value)" -notmatch 'GPU\s+([0-9]+(?:[.,][0-9]+)?)\s*%') { return $null }
            return @{ v = [double](($Matches[1]) -replace ',', '.'); n = "$($g.value)" }
        }
    }
    'game.vram' = @{
        # Tolerance: two hundred megabytes, the precision of what is displayed.
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 1; Tolerance = 0.2
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $r = @($m.fields) | Where-Object { "$($_.key)" -eq 'game-res' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $r) { return $null }
            if ("$($r.value)" -notmatch 'VRAM\s+([0-9]+(?:[.,][0-9]+)?)\s*Go') { return $null }
            return @{ v = [double](($Matches[1]) -replace ',', '.'); n = "$($g.value)" }
        }
    }
    'game.hogs' = @{
        Probe = 'gaming.probe.ps1'; Kind = 'gauge'; Unit = 'applis'; IntervalMinutes = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'gaming' } | Select-Object -First 1
            if (-not $m) { return $null }
            $g = @($m.fields) | Where-Object { "$($_.key)" -eq 'game' } | Select-Object -First 1
            $h = @($m.fields) | Where-Object { "$($_.key)" -eq 'hogs' } | Select-Object -First 1
            if (-not $g -or "$($g.value)" -eq 'aucun' -or -not $h) { return $null }
            # THE VALUE NAMES, IT NO LONGER COUNTS: it reads "Chrome and 2 more" in French since 06/09, while the extractor
            # looked for a leading number -- so the history of 28/09 read zero greedy application for a whole
            # session. The count is read from the sentence, and the NAMES travel with the point.
            $text = "$($h.value)"
            $n = 0
            if ($text -match '^([0-9]+)') { $n = [int]$Matches[1] }
            elseif ($text -match '^Aucune') { $n = 0 }
            elseif ($text -match 'et\s+([0-9]+)\s+autres') { $n = [int]$Matches[1] + 1 }
            elseif ($text -match '\set\s') { $n = 2 }
            elseif ($text.Trim()) { $n = 1 }
            return @{ v = [double]$n; n = $(if ($n) { $text } else { "$($g.value)" }) }
        }
    }
    <#
        WHAT THE COMPUTER WAS DOING, NOT ONLY THE GAME.

        On 28/09 a game stuttered for 77 minutes and nothing could say why: the game's GPU and VRAM were recorded,
        the processor, the memory in use and the committed memory were not. These three follow the Resources card,
        at all times -- they serve any enquiry, not only games -- and every point carries THE NAME OF THE GAME
        running when there is one: the series is then read session by session.
    #>
    'perf.cpu' = @{
        # One point every five minutes at rest, every minute while a game runs: these series serve an enquiry,
        # and nobody needs the processor load of every second (owner, 28/09).
        Probe = 'perf.probe.ps1'; IntervalMinutesInGame = 1; Kind = 'gauge'; Unit = '%'; IntervalMinutes = 5; Tolerance = 10
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'perf' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'cpu' } | Select-Object -First 1
            if (-not $f -or $null -eq $f.value) { return $null }
            $point = @{ v = [double]$f.value }
            $game = Get-GameModeName
            if ($game) { $point.n = $game }
            return $point
        }
    }
    'perf.ram' = @{
        # One point every five minutes at rest, every minute while a game runs: these series serve an enquiry,
        # and nobody needs the processor load of every second (owner, 28/09).
        Probe = 'perf.probe.ps1'; IntervalMinutesInGame = 1; Kind = 'gauge'; Unit = '%'; IntervalMinutes = 5; Tolerance = 2
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'perf' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'ramUsed' } | Select-Object -First 1
            if (-not $f) { return $null }
            if ("$($f.value)" -notmatch '\(([0-9]+)\s*%\)') { return $null }
            $point = @{ v = [double]$Matches[1] }
            $game = Get-GameModeName
            if ($game) { $point.n = $game }
            return $point
        }
    }
    'perf.commit' = @{
        # One point every five minutes at rest, every minute while a game runs: these series serve an enquiry,
        # and nobody needs the processor load of every second (owner, 28/09).
        Probe = 'perf.probe.ps1'; IntervalMinutesInGame = 1; Kind = 'gauge'; Unit = 'Go'; IntervalMinutes = 5; Tolerance = 1
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'perf' } | Select-Object -First 1
            if (-not $m) { return $null }
            $f = @($m.fields) | Where-Object { "$($_.key)" -eq 'commit' } | Select-Object -First 1
            if (-not $f) { return $null }
            if ("$($f.value)" -notmatch '^([0-9]+(?:[.,][0-9]+)?)\s*Go') { return $null }
            $point = @{ v = [double](($Matches[1]) -replace ',', '.') }
            $game = Get-GameModeName
            if ($game) { $point.n = $game }
            return $point
        }
    }
    'net.latency' = @{
        # Tolerance: five milliseconds. Below that, it is the normal variation of a ping.
        Probe = 'net.probe.ps1'; Kind = 'gauge'; Unit = 'ms'; IntervalMinutes = 0; Tolerance = 5
        Extract = {
            param($Modules)
            $m = @($Modules) | Where-Object { "$($_.id)" -eq 'net' } | Select-Object -First 1
            if (-not $m) { return $null }
            $lat = @($m.fields) | Where-Object { "$($_.key)" -eq 'latency' } | Select-Object -First 1
            $mea = @($m.fields) | Where-Object { "$($_.key)" -eq 'measAt' }  | Select-Object -First 1
            # No date field means latency never measured: nothing to note.
            if (-not $lat -or -not $mea -or $null -eq $mea.value) { return $null }
            # The displayed value is text ("23 ms"): the number is extracted from it.
            if ("$($lat.value)" -notmatch '^\s*([0-9]+(?:[.,][0-9]+)?)\s*ms') { return $null }
            $v = [double](($Matches[1]) -replace ',', '.')
            # The key is the measurement's date, NORMALISED: ConvertFrom-Json returns
            # sometimes a string, sometimes a [datetime] (D44) -- comparing the raw forms
            # would write a point at every recomputation.
            $key = $null
            try { $key = (ConvertTo-UtcDate $mea.value).ToString('o') } catch { return $null }
            return @{ v = $v; key = $key }
        }
    }
}

# Resolves the history's configuration in LAYERS (the same logic as the config, D33):
# internal defaults -> the History section of config.psd1 (overridden by config.local.psd1)
# -> the per-measurement setting, the most specific winning. Without -MeasureId: the global
# values. With it: the EFFECTIVE values of that measurement (RetentionDays, IntervalMinutes,
# MaxLines). RetentionDays <= 0 on a measurement means: stop sampling it.
function Get-HistoryConfig {
    param([string]$Backend = (Get-BackendRoot), [string]$MeasureId, [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    $h = $Config.History
    $res = @{ Enabled = $true; RetentionDays = 90; MaxLinesPerMeasure = 50000; Measures = @{} }
    if ($h -is [hashtable]) {
        if ($h.ContainsKey('Enabled'))            { $res.Enabled            = [bool]$h.Enabled }
        if ($h.ContainsKey('RetentionDays'))      { $res.RetentionDays      = [int]$h.RetentionDays }
        if ($h.ContainsKey('MaxLinesPerMeasure')) { $res.MaxLinesPerMeasure = [int]$h.MaxLinesPerMeasure }
        if ($h.Measures -is [hashtable])          { $res.Measures           = $h.Measures }
    }
    if (-not $MeasureId) { return $res }
    $cat = $script:MeasureCatalog[$MeasureId]
    $eff = @{
        Enabled         = $res.Enabled
        RetentionDays   = $res.RetentionDays
        MaxLines        = $res.MaxLinesPerMeasure
        IntervalMinutes = $(if ($cat -and $cat.ContainsKey('IntervalMinutes')) { [int]$cat.IntervalMinutes } else { 0 })
        # HOW MUCH MUST IT MOVE TO COUNT? Below that, it is noise: a GPU swinging between 22
        # and 25 % within the same minute tells nothing, and writing it three times only
        # fills the disk. 0 means every variation counts.
        Tolerance       = $(if ($cat -and $cat.ContainsKey('Tolerance')) { [double]$cat.Tolerance } else { 0 })
    }
    $mo = $res.Measures[$MeasureId]
    if ($mo -is [hashtable]) {
        if ($mo.ContainsKey('RetentionDays'))   { $eff.RetentionDays   = [int]$mo.RetentionDays }
        if ($mo.ContainsKey('IntervalMinutes')) { $eff.IntervalMinutes = [int]$mo.IntervalMinutes }
        if ($mo.ContainsKey('Tolerance'))       { $eff.Tolerance       = [double]$mo.Tolerance }
    }
    # Zero retention means the measurement is off. The existing file is NOT deleted:
    # destroying an archive stays a manual and deliberate gesture.
    if ($eff.RetentionDays -le 0) { $eff.Enabled = $false }
    return $eff
}

# Appends ONE line to a history file, under that file's mutex (the same convention as
# Update-StateJson). It is necessary: two simultaneous recomputations really do exist -- a
# forced request and a background refresh -- and their writes must not interleave.
<#
    ONE FILE PER MEASUREMENT AND PER DAY: var/history/<measure>/<YYYY-MM-DD>.jsonl

    A single file per measurement grew endlessly, and the purge had to READ IT WHOLE, parse
    every line, throw the old ones away and rewrite everything -- under the lock, blocking the
    writes. Cut up by day, purging comes down to DELETING files: no reading, no parsing, no
    rewriting. Reading a 24-hour window now opens one file or two instead of walking ninety
    days to throw 98 % of them away.
#>
function Get-MeasureDayFile {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId,
        [datetime]$Day = [datetime]::UtcNow
    )
    $dir = Join-Path (Get-VarPath -Backend $Backend -Kind 'history') $MeasureId
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null } catch { }
    }
    Join-Path $dir ($Day.ToUniversalTime().ToString('yyyy-MM-dd') + '.jsonl')
}

<#
    THE LOCK'S NAME TAKES THE MEASUREMENT INTO ACCOUNT, not only the file.

    Since the split by day, every file of a given day is called the same thing
    (2026-09-01.jsonl): a lock named after the file alone would make the disk measurement wait
    because the network one is writing. Two measurements have nothing to share.
#>
<#
    AND IT COVERS THE WHOLE COMPUTER, not one session.

    It was named "Local\...". A Local lock exists ONLY inside one Windows session: the server app writes from the
    service's session, a client app from its account's, and each took a DIFFERENT lock bearing the same name. The
    one that can really hurt is the purge, which REWRITES a file while another session appends to it.

    "Global\" is shared by the whole computer. It needs an explicit access right: created by the elevated service
    account, its default list would stop an ordinary client app from opening it -- and that app would then write
    with NO lock at all, which is worse than the disease. Get-HistoryMutex grants the right as it creates it.
#>
function Get-HistoryMutexName {
    param([Parameter(Mandatory)][string]$Path)
    $leaf   = Split-Path $Path -Leaf
    $parent = Split-Path (Split-Path $Path -Parent) -Leaf
    return ('Global\VigieHistory_' + (($parent + '_' + $leaf) -replace '[^A-Za-z0-9]', '_'))
}

<#
    THE LOCK ITSELF, OPEN TO EVERY ACCOUNT ON THE COMPUTER.

    One door: everything touching the history comes through here, and nobody builds a Mutex by hand. The right is
    granted as it is created -- anyone may take it and give it back -- otherwise only the service account that
    created it could use it at all.

    If none of that works, it returns $null and the caller writes anyway: a history with no lock beats no history,
    and the writing itself is built to hold (see Add-HistoryLine).
#>
function Get-HistoryMutex {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $rules = New-Object System.Security.AccessControl.MutexSecurity
        $everyone = New-Object System.Security.Principal.SecurityIdentifier(
            [System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $rules.AddAccessRule((New-Object System.Security.AccessControl.MutexAccessRule(
            $everyone,
            ([System.Security.AccessControl.MutexRights]'Synchronize, Modify'),
            [System.Security.AccessControl.AccessControlType]::Allow)))
        $created = $false
        return [System.Threading.MutexAcl]::Create($false, $Name, [ref]$created, $rules)
    } catch { }
    # MutexAcl is not everywhere: fall back on a plain lock, which is enough between processes of one account, and
    # on the resilient write for the rest.
    try { return (New-Object System.Threading.Mutex($false, $Name)) } catch { }
    try { return [System.Threading.Mutex]::OpenExisting($Name) } catch { }
    return $null
}

<#
    THE LAST SAFETY NET, AND NOTHING MORE.

    A measurement must not be able to fill the disk because it has started changing at every
    pass. The guard reads in one system call -- the SIZE of the day's file -- without counting
    or parsing anything. Past it, the measurement does not fall silent: it is THROTTLED to one
    line a minute (the file's date says when the last one landed). Falling silent at noon
    would leave us blind to the real incident of the afternoon.

    With the rule "the same value is never written twice", this net should never serve: if it
    triggers, that is a DEFECT to correct, and that is why it says so in the log.
#>
<#
    THE LAST POINTS ALREADY WRITTEN, without rereading the file.

    We only read the END of the file (two kilobytes are enough for a few lines): the cost
    does not depend on the file size, even after thousands of points. Returns, newest
    first: the value, and the OFFSET where its line starts -- that offset is what allows
    erasing the last line without rewriting everything.
#>
function Get-HistoryTailPoints {
    param([Parameter(Mandatory)][string]$Path, [int]$Count = 2)
    $tail = @()
    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($fi.Length -le 0) { return $tail }
        $size = [int][Math]::Min($fi.Length, 2048)
        $start  = $fi.Length - $size
        $buffer = New-Object byte[] $size
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $null = $fs.Seek($start, [IO.SeekOrigin]::Begin)
            $null = $fs.Read($buffer, 0, $size)
        } finally { $fs.Dispose() }
        $text = [Text.Encoding]::UTF8.GetString($buffer)
        # The buffer's first line is probably cut in half: it is thrown away, unless the file
        # was read from its very beginning.
        $lines = $text -split "`r?`n"
        if ($start -gt 0 -and $lines.Count) { $lines = $lines[1..($lines.Count - 1)] }
        # The offset of each line kept, counted back from the end.
        $offset = $fi.Length
        for ($i = $lines.Count - 1; $i -ge 0 -and $tail.Count -lt $Count; $i--) {
            $l = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($l)) { continue }
            $offset -= ([Text.Encoding]::UTF8.GetByteCount($l) + [Environment]::NewLine.Length)
            $o = $null
            try { $o = $l | ConvertFrom-Json } catch { continue }
            $v = 0.0
            if (-not [double]::TryParse("$($o.v)", [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return @() }
            $at = $null
            try { $at = ConvertTo-UtcDate $o.at } catch { }
            $tail += [pscustomobject]@{ V = $v; At = $at; Offset = $offset }
        }
    } catch { return @() }
    return $tail
}

<#
    A POINT BETWEEN ITS TWO NEIGHBOURS SAYS NOTHING: WE ERASE IT.

    When a point arrives, the PREVIOUS one becomes judgeable: if it sits between the one
    before it and the one being written, it lies on the line joining them -- it can be
    deduced, so it is not kept. Only TURNING POINTS remain: the extremes of the
    fluctuations, which carry the whole shape of the curve and all its records.

    So we look BACKWARDS, at write time: no delay, no second pass, and the current day
    stays accurate to the second. Erasing costs one call -- the file is truncated at the
    offset of its last line, never rewritten.

    TWO GUARDS:
      - the tolerance: a turn smaller than it is not a turn, it is noise;
      - the heartbeat: never erase if that would dig a hole longer than fifteen minutes,
        or "stable" could no longer be told from "nothing measures any more".
#>
function Remove-RedundantHistoryPoint {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][double]$NewValue,
        [double]$Tolerance = 0,
        [int]$HeartbeatMinutes = 15
    )
    $tail = @(Get-HistoryTailPoints -Path $Path -Count 2)
    if ($tail.Count -lt 2) { return $false }
    $previous = $tail[0]      # N-1, celui qu'on juge
    $beforeThat   = $tail[1]      # N-2
    $low  = [Math]::Min($beforeThat.V, $NewValue) - $Tolerance
    $high = [Math]::Max($beforeThat.V, $NewValue) + $Tolerance
    if ($previous.V -lt $low -or $previous.V -gt $high) { return $false }
    if ($beforeThat.At -and ([datetime]::UtcNow - $beforeThat.At).TotalMinutes -ge $HeartbeatMinutes) { return $false }
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $fs.SetLength($previous.Offset) } finally { $fs.Dispose() }
        return $true
    } catch { return $false }
}

function Write-HistoryPoint {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId,
        [Parameter(Mandatory)]$Point,
        # EVENTS are never compacted: each one is a unique fact, and "in between" means
        # nothing for a state.
        [switch]$Compact,
        [double]$Tolerance = 0,
        [int]$MaxBytes = 5242880
    )
    $file = Get-MeasureDayFile -Backend $Backend -MeasureId $MeasureId
    $fi = $null
    try { $fi = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue } catch { }
    if ($fi -and $fi.Length -ge $MaxBytes) {
        if (([datetime]::UtcNow - $fi.LastWriteTimeUtc).TotalSeconds -lt 60) { return $false }
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -NoEcho `
                        -Message (Get-Label 'common.historique-bride' $MeasureId) } catch { }
    }
    # The PREVIOUS point becomes judgeable now that the next one is known.
    if ($Compact) {
        $v = 0.0
        if ([double]::TryParse("$($Point.v)", [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
            $null = Remove-RedundantHistoryPoint -Path $file -NewValue $v -Tolerance $Tolerance
        }
    }
    return (Add-HistoryLine -Path $file -Line ($Point | ConvertTo-Json -Compress -Depth 4))
}

<#
    A LINE GOES IN WHOLE, OR NOT AT ALL.

    The lock comes first, and it now covers the whole computer. But a lock can be missing -- an account without the
    right to open it, a wait that expires -- and what was written then had no protection at all.

    So the write itself refuses sharing: the file is opened to APPEND, for EXCLUSIVE writing, the line goes in one
    call, and the file closes. Another process writing at the same instant does not get in -- it retries, and
    returns $false if it never does. A lost line shows in the count; a half-written one does not.
#>
function Add-HistoryLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Line, [int]$Tries = 5)
    $mx = Get-HistoryMutex -Name (Get-HistoryMutexName -Path $Path)
    $got = $false
    try {
        if ($mx) {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
        }
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Line + [Environment]::NewLine)
        for ($i = 0; $i -lt $Tries; $i++) {
            try {
                $fs = [IO.File]::Open($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Dispose() }
                return $true
            } catch [System.IO.IOException] {
                # SOMEONE ELSE HOLDS THE FILE: wait a little and try again. That is the normal case when two
                # processes write within the same second, not a failure.
                Start-Sleep -Milliseconds (30 * ($i + 1))
            } catch { return $false }
        }
        return $false
    } finally {
        if ($got) { try { $mx.ReleaseMutex() } catch { } }
        if ($mx) { try { $mx.Dispose() } catch { } }
    }
}

# Samples the measurements of ONE probe, just after its successful recomputation (a single
# call site: the loop of Get-State). It consults the catalogue, applies the minimum interval
# through the index (history-index.json: lastAt, lastValue and lastKey per measurement,
# written by Update-StateJson and therefore merged under a mutex), and appends to
# var/history/<measureId>.jsonl. It also triggers the purge, at most once per 24 h.
# Best effort from end to end: no failure ever reaches the recomputation.
function Write-MeasureSamples {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$Probe,
        [Parameter(Mandatory)]$Modules
    )
    try {
        $ids = @($script:MeasureCatalog.Keys | Where-Object { $script:MeasureCatalog[$_].Probe -eq $Probe })
        if ($ids.Count -eq 0) { return }
        $cfg = Get-Config -Backend $Backend
        $global = Get-HistoryConfig -Backend $Backend -Config $cfg
        if (-not $global.Enabled) { return }
        # Read once for the whole pass: a game running changes the pace of some measures.
        $inGameMeasures = [bool](Get-GameModeName -Backend $Backend)
        $indexFile = Get-VarPath -Backend $Backend -Kind 'history' -File 'history-index.json'
        $index = $null
        if (Test-Path -LiteralPath $indexFile) {
            try { $index = Get-Content -LiteralPath $indexFile -Raw | ConvertFrom-Json } catch { }
        }
        foreach ($id in ($ids | Sort-Object)) {
            $cat = $script:MeasureCatalog[$id]
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg
            if (-not $eff.Enabled) { continue }
            $sample = $null
            try { $sample = & $cat.Extract $Modules } catch { $sample = $null }
            if ($null -eq $sample -or $null -eq $sample.v) { continue }
            $prop  = if ($index) { $index.PSObject.Properties[$id] } else { $null }
            $entry = if ($prop) { $prop.Value } else { $null }
            # A keyed measurement, tied to an external one: a point is written only when the
            # key changes. The key read back goes through ConvertTo-UtcDate: ConvertFrom-Json
            # returns the stored date as a [datetime] (D44), and comparing it as it stands
            # with the extractor's 'o' string NEVER matched -- seen in testing, one point per
            # recomputation.
            if ($sample.key -and $entry -and $entry.lastKey) {
                $prevKey = "$($entry.lastKey)"
                try { $prevKey = (ConvertTo-UtcDate $entry.lastKey).ToString('o') } catch { }
                if ($prevKey -eq "$($sample.key)") { continue }
            }
            # An ordinary gauge: the minimum interval since the last point.
            # WHILE A GAME RUNS, a measure may ask for a closer pace (IntervalMinutesInGame): the enquiry needs the
            # minute, the rest of the day does not.
            $interval = [int]$eff.IntervalMinutes
            if ($inGameMeasures -and $cat.IntervalMinutesInGame) { $interval = [int]$cat.IntervalMinutesInGame }
            if ((-not $sample.key) -and $interval -gt 0 -and $entry -and $entry.lastAt) {
                try {
                    $last = ConvertTo-UtcDate $entry.lastAt
                    if ($last -and ($nowUtc - $last).TotalMinutes -lt $interval) { continue }
                } catch { }
            }
            # THE SAME VALUE IS NEVER WRITTEN TWICE.
            #
            # The value noted is not a raw measurement: it is the one the CARD displays, so
            # already rounded to what matters -- space in GB, the GPU in per cent, latency in
            # ms. Two identical readings therefore carry the same information, and rewriting
            # it only fills the disk.
            #
            # A HEARTBEAT: after fifteen minutes, a point is written anyway. Without it a
            # flat series becomes a hole, and "stable" can no longer be told from "nothing
            # measures any more" -- which is quite another piece of news.
            # THE TOLERANCE DOES NOT FILTER HERE: it serves the compaction of a closed day,
            # where the next point is known and a real turn can be told from a fluctuation.
            # At write time, that is not yet known.
            # Not rewriting the SAME value, on the other hand, requires knowing nothing.
            $noise = $false
            if ($entry -and $null -ne $entry.lastValue) {
                if ("$($entry.lastValue)" -eq "$($sample.v)") { $noise = $true }
                # A HEARTBEAT: after fifteen minutes a point is written anyway. Without it a
                # flat series becomes a hole, and "stable" can no longer be told from
                # "nothing measures any more" -- which is quite another piece of news.
                if ($noise -and $entry.lastAt) {
                    try {
                        $last = ConvertTo-UtcDate $entry.lastAt
                        if ($last -and ($nowUtc - $last).TotalMinutes -ge 15) { $noise = $false }
                    } catch { $noise = $false }
                }
            }
            if ($noise) { continue }
            # Optional field n: a NAME attached to the point, such as a session's game -- it
            # is what will answer "what was running at that hour?".
            $obj = [ordered]@{ at = $nowUtc.ToString('o'); v = $sample.v }
            if ($sample.n) { $obj.n = "$($sample.n)" }
            if (Write-HistoryPoint -Backend $Backend -MeasureId $id -Point $obj -Compact -Tolerance $eff.Tolerance) {
                $set = @{ lastAt = $nowUtc.ToString('o'); lastValue = $sample.v }
                if ($sample.key) { $set.lastKey = "$($sample.key)" }
                try { Update-StateJson -Path $indexFile -Set @{ $id = $set } | Out-Null } catch { }
            }
        }
        # The purge: at most once per 24 h, carried by a recomputation already under way, so
        # there is never a wake-up of its own. The date is laid BEFORE purging, so that two
        # simultaneous recomputations do not start two purges.
        $due = $true
        $pp = if ($index) { $index.PSObject.Properties['purgedAt'] } else { $null }
        if ($pp -and $pp.Value) {
            try {
                $p = ConvertTo-UtcDate $pp.Value
                if ($p -and ($nowUtc - $p).TotalHours -lt 24) { $due = $false }
            } catch { }
        }
        if ($due) {
            try { Update-StateJson -Path $indexFile -Set @{ purgedAt = $nowUtc.ToString('o') } | Out-Null } catch { }
            Invoke-HistoryPurge -Backend $Backend
            try { $null = Invoke-LogPurge -Backend $Backend } catch { }
        }
    } catch {
        # The history OBSERVES, it does not arbitrate: no failure ever reaches Get-State.
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (Get-Label 'common.historique-echantillonnage-ignore' $Probe $_.Exception.Message) } catch { }
    }
}

<#
    THE LOGS ARE KEPT 30 DAYS, then deleted. The requirement: doc/progress/targeting/components.md, in its section
    on retention. Everything under var/log counts -- the logs, the diagnostic copies of other
    accounts, the .reg backups -- and a folder left empty goes too. A log still being written is recent, so it stays.
#>
function Invoke-LogPurge {
    param([string]$Backend = (Get-BackendRoot))
    $days = 30
    try { $configured = [int]((Get-Config -Backend $Backend).LogRetentionDays); if ($configured -gt 0) { $days = $configured } } catch { }
    $dir = Get-VarPath -Backend $Backend -Kind 'log'
    $limit = (Get-Date).AddDays(-$days)
    $removed = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        if ($file.LastWriteTime -ge $limit) { continue }
        try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $removed++ } catch { }
    }
    <#
        AND A CEILING IN MEGABYTES, because an age is not a size.

        Thirty days of logs weighed 166 MB for the service account on 29/09 -- 703 files, several of them 4 MB a day
        -- on a machine whose disk was down to 31 GB. An age alone bounds nothing: a busy day writes ten times what a
        quiet one writes. Past the ceiling, the OLDEST files go, one by one, until the total is back under it.

        WHAT IS NEVER TOUCHED: anything written in the last hour. A log being written is the one being read when
        something goes wrong, and it is never the one to sacrifice.
    #>
    $maxMb = 60
    try { $configured = [int]((Get-Config -Backend $Backend).LogMaxMb); if ($configured -gt 0) { $maxMb = $configured } } catch { }
    if ($maxMb -gt 0) {
        $recent = (Get-Date).AddHours(-1)
        $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime)
        $total = ($files | Measure-Object Length -Sum).Sum
        foreach ($f in $files) {
            if ($total -le ($maxMb * 1MB)) { break }
            if ($f.LastWriteTime -ge $recent) { continue }
            try {
                $size = $f.Length
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $total -= $size
                $removed++
            } catch { }
        }
    }
    foreach ($folder in @(Get-ChildItem -LiteralPath $dir -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                          Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue).Count) {
            Remove-Item -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    return $removed
}

# Purges the files of var/history/: a retention in days (global, overridden per measurement)
# PLUS a ceiling in lines, a size guard so that a badly set interval cannot fill the disk.
# Rewriting is ATOMIC (.tmp, a guard, then Move-Item) under the file's mutex. Unreadable
# lines, from an interrupted write, are removed and counted, never blocking. probe-runs.jsonl
# is NOT concerned: it lives in var/cache/ and keeps its own purge by size (D52).
function Invoke-HistoryPurge {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $cfg = Get-Config -Backend $Backend
        $dir = Get-VarPath -Backend $Backend -Kind 'history'
        $nowUtc = [datetime]::UtcNow

        # PURGING THE PER-DAY FILES: we DELETE, we read nothing back. The file's name carries
        # its date -- which is all one needs to decide.
        foreach ($measure in @(Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue)) {
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $measure.Name -Config $cfg
            if ($eff.RetentionDays -le 0) { continue }
            $limit = $nowUtc.Date.AddDays(-$eff.RetentionDays)
            foreach ($day in @(Get-ChildItem -Path $measure.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
                $date = [datetime]::MinValue
                if (-not [datetime]::TryParseExact([IO.Path]::GetFileNameWithoutExtension($day.Name), 'yyyy-MM-dd',
                        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) { continue }
                if ($date -lt $limit) {
                    try {
                        Remove-Item -LiteralPath $day.FullName -Force -ErrorAction Stop
                        Write-Log -Backend $Backend -Name 'state' -NoEcho `
                                  -Message (Get-Label 'common.historique-jour-supprime' $measure.Name $day.Name)
                    } catch { }
                    continue
                }

            }
        }

        # THE OLD FLAT FILES, on the other hand, are still purged line by line: they carry no
        # date in their name. That path will disappear with them.
        $files = @(Get-ChildItem -Path $dir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
        foreach ($fi in $files) {
            $id  = [IO.Path]::GetFileNameWithoutExtension($fi.Name)
            $eff = Get-HistoryConfig -Backend $Backend -MeasureId $id -Config $cfg
            # Retention <= 0: the measurement is no longer sampled, but an existing archive is
            # never emptied -- that stays a manual gesture.
            if ($eff.RetentionDays -le 0) { continue }
            $cutoff = $nowUtc.AddDays(-$eff.RetentionDays)
            $mx = Get-HistoryMutex -Name (Get-HistoryMutexName -Path $fi.FullName)
            $got = $false
            try {
                try { $got = $mx.WaitOne(5000) }
                catch [System.Threading.AbandonedMutexException] { $got = $true }
                catch { $got = $false }
                if (-not $got) { continue }
                $lines = [IO.File]::ReadAllLines($fi.FullName)
                $keep = New-Object System.Collections.Generic.List[string]
                $dropped = 0
                foreach ($l in $lines) {
                    if ([string]::IsNullOrWhiteSpace($l)) { $dropped++; continue }
                    $o = $null
                    try { $o = $l | ConvertFrom-Json } catch { $dropped++; continue }
                    $at = $null
                    try { $at = ConvertTo-UtcDate $o.at } catch { }
                    if (-not $at -or $at -lt $cutoff) { $dropped++; continue }
                    $keep.Add($l)
                }
                if ($eff.MaxLines -gt 0 -and $keep.Count -gt $eff.MaxLines) {
                    $excess = $keep.Count - $eff.MaxLines
                    $keep.RemoveRange(0, $excess)
                    $dropped += $excess
                }
                if ($dropped -gt 0) {
                    $tmp = $fi.FullName + '.tmp'
                    [IO.File]::WriteAllLines($tmp, $keep, [Text.UTF8Encoding]::new($false))
                    # A size guard: if lines are kept, the .tmp cannot be empty.
                    $ok = (Test-Path -LiteralPath $tmp) -and ($keep.Count -eq 0 -or (Get-Item -LiteralPath $tmp).Length -gt 0)
                    if ($ok) { Move-Item -Path $tmp -Destination $fi.FullName -Force }
                    else { try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { } }
                    Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'common.historique-purge-de-ligne' $fi.Name $dropped $keep.Count)
                }
            } finally {
                if ($got) { try { $mx.ReleaseMutex() } catch { } }
                try { $mx.Dispose() } catch { }
            }
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (Get-Label 'common.historique-purge-en-echec' $_.Exception.Message) } catch { }
    }
}

# Reads a history window ("24h", "7d") as a [TimeSpan].
# $null means an invalid form: the route then answers 400, and this function never guesses.
# The bounds are wide but finite: a huge window is not a malformed one, it simply reads the
# whole file (the retention already bounds the data).
function ConvertTo-HistoryWindow {
    param([string]$Window)
    if (-not $Window) { return $null }
    if ($Window -notmatch '^([0-9]{1,4})([hd])$') { return $null }
    $n = [int]$Matches[1]
    if ($n -le 0) { return $null }
    if ($Matches[2] -eq 'h') { return [TimeSpan]::FromHours($n) }
    return [TimeSpan]::FromDays($n)
}

# Reads the series of ONE measurement for GET /history/{measureId}. Read only, under the
# SAME mutex as the writing: an append may be under way during the reading. Unreadable
# lines, from an interrupted write, are ignored without failing.
# Rend $null si la mesure n'est pas au catalogue (la route repond 404) ; sinon un
# objet conforme au schema History du contrat : points (decimes a ~$MaxPoints pour
# a gauge, as they stand for an event -- they are rare) plus a summary computed BEFORE the
# decimation. A file that is missing or empty gives no points and summary.count = 0: a young
# history is not an error.
# THE DEFINITION OF A MEASUREMENT, from the catalogue or from a SENTINEL.
#
# The catalogue is fixed in this file; the sentinels, on the other hand, are declared by the
# modules (module.psd1, the Sentinels key) and so cannot appear in it. Their measurement is
# resolved here, on the fly: the identifier "watch.<key>", nature 'event' -- a state written
# ONLY when it changes, which is exactly what the history's design calls an event. Nothing is
# duplicated: the same var/history/ folder, the same purge, the same
# GET /history/{measureId} route.
function Get-MeasureDefinition {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId
    )
    $cat = $script:MeasureCatalog[$MeasureId]
    if ($cat) { return $cat }
    if ($MeasureId -notlike 'watch.*') { return $null }
    $key = $MeasureId.Substring(6)
    $w = @(Get-WatchDeclarations -Backend $Backend | Where-Object { "$($_.Key)" -eq $key })[0]
    if (-not $w) { return $null }
    return @{ Probe = ''; Kind = 'event'; Unit = ''; IntervalMinutes = 0; Label = "$($w.Label)" }
}

# A sentinel's history identifier. ONE single place builds it: the reading and the writing
# cannot drift apart.
function Get-SentinelMeasureId {
    param([Parameter(Mandatory)][string]$Key)
    return ('watch.' + $Key)
}

function Get-MeasureHistory {
    param(
        [string]$Backend = (Get-BackendRoot),
        [Parameter(Mandatory)][string]$MeasureId,
        [Parameter(Mandatory)][TimeSpan]$Window,
        [string]$WindowLabel = '',
        [int]$MaxPoints = 200
    )
    $cat = Get-MeasureDefinition -Backend $Backend -MeasureId $MeasureId
    if (-not $cat) { return $null }
    # ONLY THE DAYS OF THE WINDOW ARE OPENED. One day more on each side: the window does not
    # begin at midnight, and the files are dated in UTC.
    $lines = @()
    $firstDay = ([datetime]::UtcNow - $Window).Date.AddDays(-1)
    $days = @()
    for ($j = $firstDay; $j -le ([datetime]::UtcNow.Date); $j = $j.AddDays(1)) {
        $days += (Get-MeasureDayFile -Backend $Backend -MeasureId $MeasureId -Day $j)
    }
    # THE OLD FLAT FILE is still read for as long as it exists: nobody loses their history
    # because the filing changed. Nothing is written to it any more.
    $days += (Get-VarPath -Backend $Backend -Kind 'history' -File ($MeasureId + '.jsonl'))
    foreach ($file in $days) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $mx = Get-HistoryMutex -Name (Get-HistoryMutexName -Path $file)
        $got = $false
        try {
            try { $got = $mx.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            # The mutex is unavailable: we read anyway -- the worst case is a truncated final
            # line, already handled -- rather than returning an error to the client.
            $lines += [IO.File]::ReadAllLines($file)
        } finally {
            if ($got) { try { $mx.ReleaseMutex() } catch { } }
            try { $mx.Dispose() } catch { }
        }
    }
    $nowUtc = [datetime]::UtcNow
    $cutoff = $nowUtc - $Window
    # Filtering and normalising. The file is append-only and therefore already chronological;
    # it is sorted again all the same: an interrupted purge or a forged line must not return
    # a series out of order.
    $pts = New-Object System.Collections.Generic.List[object]
    <#
        SKIPPED LINES ARE COUNTED, AND SAID.

        An unreadable line was skipped in silence. A wholly damaged file therefore returned ZERO points -- exactly
        what a measure never taken returns: the two were indistinguishable on screen (seen on 06/10). Handling an
        error without reporting it is half the rule (components.md).
    #>
    $unreadable = 0
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { $unreadable++; continue }
        $at = $null
        # ConvertFrom-Json returns the date sometimes as a string, sometimes as a [datetime]
        # (D44): ConvertTo-UtcDate normalises, and comparing without it would skew the window.
        try { $at = ConvertTo-UtcDate $o.at } catch { continue }
        if (-not $at -or $null -eq $o.v) { continue }
        if ($at -lt $cutoff) { continue }
        # AN EVENT IS NOT A NUMBER. Its value is a state ("oui", "Actif", "erreur: ..."):
        # handing it to TryParse would throw it away outright.
        # Where it came from and what the change triggered are kept too: that is what makes
        # the difference between a value and an ALERT.
        if ("$($cat.Kind)" -eq 'event') {
            $pts.Add([pscustomobject]@{ atUtc = $at; v = "$($o.v)"; from = "$($o.from)"; cards = @($o.cards) })
            continue
        }
        $v = 0.0
        if (-not [double]::TryParse("$($o.v)", [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { continue }
        $pts.Add([pscustomobject]@{ atUtc = $at; v = $v })
    }
    $sorted = @($pts | Sort-Object atUtc)
    # The summary covers ALL the points of the window, before decimation: decimation can drop
    # the extreme, and the summary must not lose it.
    $summary = [ordered]@{ count = $sorted.Count; min = $null; max = $null; first = $null; last = $null }
    if ($sorted.Count -gt 0 -and "$($cat.Kind)" -eq 'event') {
        $summary.first = $sorted[0].v
        $summary.last  = $sorted[$sorted.Count - 1].v
    }
    elseif ($sorted.Count -gt 0) {
        $mesures = $sorted | Measure-Object -Property v -Minimum -Maximum
        $summary.min   = $mesures.Minimum
        $summary.max   = $mesures.Maximum
        $summary.first = $sorted[0].v
        $summary.last  = $sorted[$sorted.Count - 1].v
    }
    # Uniform decimation by index, the first and last points kept. Events will go through as
    # they are: they are rare, and every occurrence counts.
    $kept = $sorted
    if ("$($cat.Kind)" -ne 'event' -and $MaxPoints -gt 0 -and $sorted.Count -gt $MaxPoints) {
        $kept = New-Object System.Collections.Generic.List[object]
        $step = ($sorted.Count - 1) / [double]($MaxPoints - 1)
        $lastIdx = -1
        for ($i = 0; $i -lt $MaxPoints; $i++) {
            $idx = [int][math]::Round($i * $step)
            if ($idx -eq $lastIdx) { continue }   # deux i arrondis au meme index
            $kept.Add($sorted[$idx])
            $lastIdx = $idx
        }
    }
    return [ordered]@{
        measureId = $MeasureId
        kind      = "$($cat.Kind)"
        unit      = "$($cat.Unit)"
        window    = $WindowLabel
        points    = @($kept | ForEach-Object {
            $pt = [ordered]@{ at = $_.atUtc.ToString('o'); v = $_.v }
            if ("$($cat.Kind)" -eq 'event') { $pt.from = $_.from; $pt.cards = @($_.cards) }
            $pt })
        summary   = $summary
        # WHAT COULD NOT BE READ. Zero points alone did not say whether the measure had never been taken or its
        # file was damaged: the difference is read here.
        unreadable = $unreadable
    }
}

function Get-State {
    param(
        [string]$Backend = (Get-BackendRoot),
        [switch]$Force,
        # Seconds to wait for the recomputation lock. 0 means give up if a computation is
        # already running. Only an EXPLICIT request from the user waits; the background
        # refresh gives up, or the workers pile up blocking one another.
        # Capped below the client's own delay (90 s): waiting longer than it does would mean
        # working for a request already abandoned.
        [int]$WaitSeconds = 0,
        <#
            WHO ARE WE COMPUTING FOR? A card that speaks of "vous" has one cache entry per
            account. The background refresh runs with no session: it did not know who to keep
            its result for, so those cards were left out of the deferred work and recomputed
            INSIDE each request -- 2 seconds for the accounts, 5 for the deployment, at every
            display.

            So it is told who. The account travels all the way to the worker, which writes
            under the right key, and nothing forces a computation while somebody waits.
        #>
        [string]$Account,
        # A TARGETED RECOMPUTATION: the identifier of the module whose values must be fresh,
        # and OF THAT ONE ONLY. It is what a card's "Refresh" button asks for: to be given
        # the recomputed result, and not the last known value while a background refresh
        # lags behind -- seen on the Gaming card, which announced "no game" while the probe
        # already saw the game under way.
        [string]$ForceModule = '',
        <#
            THE PROBES TO RECOMPUTE, AND THOSE ALONE.

            The background refresh called Get-State -Force: it recomputed ALL SEVENTEEN
            probes, including the ones just done. A full pass takes a minute and a half --
            lock 11 s, gaming 14 s, deployment 13 s -- and during that time the others' delays
            expire: the next request deferred again, started another full pass, and the
            machine never stopped. Measured on 31/08 in state_20260831.log: passes chaining
            without a break, and a /state taking 27 seconds.

            So it is given the exact list of what is stale.
        #>
        [string[]]$Only = @()
    )
    $probesDir = Join-Path $Backend 'probes'
    $cacheFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'state-cache.json'
    $stateDir  = Split-Path $cacheFile -Parent
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    <#
        NOBODY AGES MORE THAN A DAY.

        The rule, from the owner on 01/09: every card recomputes itself from time to time, at
        least once a day, and never all of them at once. The "never all" is held by the
        background refresh, which takes only ONE per response; the "at least once a day" is
        held here, by this ceiling.

        Without it, a generous delay would be enough -- the accounts are at one hour -- for a
        card to stay for days on a false measurement if nobody looks at it.
    #>
    $maxTtl = 86400
    $defaultTtl = 30

    # Loads the existing cache. ALWAYS, even with -Force: forcing means "recompute", not
    # "forget everything". Starting from an empty cache made the modules disappear one by one
    # from the file during the recomputation, and a simultaneous reader received a TRUNCATED
    # state -- a card vanished for the length of the refresh.
    <#
        THE WHOLE RESPONSE IS TIMED, NOT ONLY THE CARDS.

        The per-card detail gave 140 ms while the response took several SECONDS: the time was
        elsewhere -- reading the cache, walking the probes, the module catalogue -- and showed
        nowhere. A partial stopwatch is worse than none: it acquits what it does not measure.

        Every phase is measured, returned in "timings" and written to the log.
    #>
    $tPhase = [Diagnostics.Stopwatch]::StartNew()
    $phases = [ordered]@{}
    $markPhase = {
        param([string]$phaseName)
        $phases[$phaseName] = [math]::Round($tPhase.Elapsed.TotalMilliseconds, 1)
        $tPhase.Restart()
    }

    $cache = @{}
    if (Test-Path $cacheFile) {
        try { $j = Get-Content $cacheFile -Raw | ConvertFrom-Json; foreach ($pr in $j.PSObject.Properties) { $cache[$pr.Name] = $pr.Value } } catch { }
    }
    & $markPhase 'lecture-cache'

    # Which probe produces the module aimed at? The cache says so: each entry carries the
    # module the probe returned, or its array of modules.
    # "-Only" aims at probes by their FILE NAME, as "-ForceModule" aims at a card: both feed
    # the same list, and there is only one mechanism.
    $targetedProbes = @()
    foreach ($n in @($Only)) { if ("$n".Trim()) { $targetedProbes += "$n".Trim() } }
    if ($ForceModule) {
        foreach ($probeName in @($cache.Keys)) {
            $e = $cache[$probeName]
            if (-not $e -or -not $e.module) { continue }
            foreach ($mm in @($e.module)) {
                if ("$($mm.id)" -eq $ForceModule) { $targetedProbes += "$probeName" }
            }
        }
        <#
            THE CACHE DOES NOT KNOW EVERYTHING: IT ONLY KNOWS WHAT IT HAS ALREADY SEEN.

            That card-to-probe correspondence was read ONLY from the cache. A card never
            computed does not appear there, so its button aimed at NOTHING: the response came
            back 200, with no field, still "not measured yet". The card could never fill
            again -- not by its button, not by the page, not by the installation. Measured on
            01/09: GET /modules/deployment?fresh=1 -> 200, 0 fields, pending still true.

            The probe's folder carries its card's name: when the cache does not answer, the
            disk is asked, and it always knows.
        #>
        if (-not $targetedProbes.Count) {
            $probeDir = Join-Path $probesDir $ForceModule
            if (Test-PathSafe $probeDir) {
                foreach ($pf in @(Get-ChildItem -LiteralPath $probeDir -Filter '*.probe.ps1' -File -ErrorAction SilentlyContinue)) {
                    $targetedProbes += $pf.Name
                }
            }
        }
    }

    # Probes and freshness (invalidation PER probe: the file's mtime plus its TTL)
    #
    # The age is computed ENTIRELY in UTC. The date is written in UTC (`ToUniversalTime`); it
    # used to be compared with `Get-Date`, which returns LOCAL time. On a machine at UTC+2
    # every entry therefore looked two hours old: not one was ever judged fresh, the cache was
    # useless, and every call to /state recomputed the twelve probes -- some twenty seconds,
    # ten of them for the `lock` probe alone.
    & $markPhase 'ciblage'
    $nowUtc = [datetime]::UtcNow
    $probeFiles = @(Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -ErrorAction SilentlyContinue | Sort-Object FullName)
    # Modules the user has switched off (D48): their probes leave the computation AND the
    # display. The filter works on the PARENT FOLDER -- a module is a folder.
    $unitsCoupees = @(Get-InactiveUnits -Backend $Backend)
    if ($unitsCoupees.Count -gt 0) {
        $probeFiles = @($probeFiles | Where-Object {
            $unitsCoupees -notcontains (Split-Path (Split-Path $_.FullName -Parent) -Leaf)
        })
    }
    # WHO IS ASKING: the cards that speak of "vous" have their own entry per account.
    $stateRequester = $(if ($PSBoundParameters.ContainsKey('Account')) { $Account } else { Get-RequesterAccount })
    # THE PROBES ARE TOLD who this computation is for, just before each one runs (see Get-StateAccount): they take no
    # argument, and the scheduler has no cookie to read.
    # THE GAME MODE, read once per pass: during a game, the cards that do not watch it space themselves out.
    $inGame = [bool](Get-GameModeName -Backend $Backend)
    $stale = @()
    foreach ($pf in $probeFiles) {
        $name = $pf.Name; $stamp = "$($pf.LastWriteTimeUtc.Ticks)"
        $key = Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester
        $ttl = Get-ProbeTtlNow -Name $name -Default $defaultTtl -Backend $Backend -InGame:$inGame
        if ($ttl -gt $maxTtl) { $ttl = $maxTtl }
        $entry = $cache[$key]; $fresh = $false
        # -Force: everything is considered stale, without anything being erased.
        # A probe AIMED AT is stale by definition: that is the whole meaning of the request.
        if (-not $Force -and ($targetedProbes -notcontains $key) -and ($targetedProbes -notcontains $name) -and
            $entry -and $entry.at -and ("$($entry.codeStamp)" -eq $stamp)) {
            try {
                $at = ConvertTo-UtcDate $entry.at
                if ($at -and ($nowUtc - $at).TotalSeconds -lt $ttl) { $fresh = $true }
            } catch { }
        }
        if (-not $fresh) {
            # HOW LATE IS IT, RELATIVE TO ITS OWN DELAY? That is what decides which goes
            # first: a network card, valid for 15 s, is five times later than a system card
            # valid for an hour at the same instant.
            $age = $ttl + 1
            try { if ($entry -and $entry.at) { $age = ($nowUtc - (ConvertTo-UtcDate $entry.at)).TotalSeconds } } catch { }
            $stale += [pscustomobject]@{ File = $pf.FullName; Name = $name; Key = $key; Stamp = $stamp
                                         Overdue = $(if ($ttl -gt 0) { $age / $ttl } else { $age })
                                         PerAccount = (Test-ProbeIsPerAccount -ProbeFile $pf.FullName) }
        }
    }

    # Recomputation is SINGLE-FLIGHT: one thread recomputes at a time, and the other requests
    # serve the existing cache at once -- which avoids the herd effect, and the 408s with it.
    # SERVE FIRST, RECOMPUTE AFTERWARDS.
    #
    # A stale probe that ALREADY has a cached value must not keep the display waiting: the
    # known value is returned at once and the recomputation happens in the background. Only
    # the probes with NOTHING cached are computed inside the request -- otherwise there would
    # be nothing to show.
    #
    # Before, any staleness blocked the response: depending on the moment, opening Vigie took
    # from 0.3 s to more than 20 s, with nothing explaining the difference to the user.
    # The "Refresh" button (-Force) keeps its recomputation synchronous: that is exactly what
    # it is asked for.
    if (-not $Force -and $stale.Count -gt 0) {
        <#
            A DISPLAY KEEPS NOBODY WAITING.

            Neither the loading of the page nor the automatic polling: they serve what is
            cached, as it stands, and leave. A card not yet known does not display -- it will
            appear when someone has asked for it.

            The one exception is the probe AIMED AT: a card's button, or the refresh button at
            the top of the page, which recompute what they are pointed at. A recomputation is
            ASKED FOR; it does not start by itself because a date has expired.

            What happens BEHIND, on the other hand: one stale probe -- one only, per pass --
            leaves as a detached background task, so the value is ready next time. Nobody
            waits for it.

            The old version recomputed all seventeen every time: the delays of the
            others expired during the pass, the next request started another one, and the
            machine never stopped -- /state at 27 seconds (measured on 31/08).
        #>
        <#
            NOTHING IS COMPUTED BECAUSE SOMEONE IS LOOKING (D124, and the owner said it again on 29/09: he expects
            EVERY computation to happen in the background, asynchronously).

            A request serves the cache, always. What has to be computed is computed by the scheduler, at the interval
            each module declares, whether a session is open or not. Two exceptions, and they are not requests:

              - "-Only", which is the background worker itself saying WHICH computation it is running;
              - a card asked for explicitly ("-ForceModule", the refresh button), which no longer computes here
                either: it is marked due, the scheduler takes it within thirty seconds, and the panel reads the
                result when it is written.
        #>
        $targeted = { param($e) ($targetedProbes -contains $e.Key) -or ($targetedProbes -contains $e.Name) }
        $toRefresh = @()
        if ($Only -and @($Only).Count) {
            $stale = @($stale | Where-Object { (& $targeted $_) })
        } else {
            if ($targetedProbes.Count) {
                try { Reset-RefreshDue -Backend $Backend -Probes @($stale | Where-Object { (& $targeted $_) } | ForEach-Object { $_.Name }) } catch { }
            }
            $stale = @()
        }

        <#
            AND ONE SINGLE PROBE LEAVES AS A BACKGROUND TASK. Non-blocking, rare, per card.

            WHICH ONE? THE LATEST RELATIVE TO ITS OWN DELAY. Taking the first to hand ran all
            seventeen in single file: a network outage -- a card valid for 15 seconds --
            waited its turn behind cards valid for an hour, so a quarter of an hour before
            being seen. The ratio of age to delay puts each back in its place: what moves
            fast goes fast.

            The response is already built by the time we get here: nobody waits. ONE stale
            probe -- the first -- is handed to a detached process, which will recompute it and
            write the result for next time. That is how the Deployment card ends up seeing a
            commit without the page load paying for it.

            ONE only, and one at a time: recomputing all seventeen chained passes of a minute
            and a half that kept restarting one another.
        #>
        <#
            A BACKGROUND WORKER NEVER SPAWNS A BACKGROUND WORKER (29/09, and it cost 79 processes).

            This hand-off is for a REQUEST that found a stale probe. A worker also calls Get-State, so without this
            it hands off in turn, and each hand-off hands off again: the machine filled with pwsh processes within
            two minutes of the deployment. A detached worker carries VIGIE_NO_BACKGROUND and stops the chain here.

            The lock it used to test is per-probe now, so a global test proved nothing: we test the lock of the very
            probe we are about to hand off, which is the only one that matters.
        #>
        $chosen = "$(($toRefresh | Sort-Object Overdue -Descending | Select-Object -First 1).Name)"
        if ($toRefresh.Count -gt 0 -and -not $env:VIGIE_NO_BACKGROUND -and $chosen) {
            $alreadyRunning = $false
            try {
                $tmp = $null
                $lock = 'Local\VigieStateRecompute_' + ($chosen -replace '[^A-Za-z0-9]', '_')
                if ([System.Threading.Mutex]::TryOpenExisting($lock, [ref]$tmp)) {
                    $alreadyRunning = -not $tmp.WaitOne(0)
                    if (-not $alreadyRunning) { try { $tmp.ReleaseMutex() } catch { } }
                    try { $tmp.Dispose() } catch { }
                }
            } catch { }
            if (-not $alreadyRunning) {
                try {
                    $w = Join-Path $Backend 'workers/state-refresh.worker.ps1'
                    $null = Start-DetachedAction -Script $w -Backend $Backend `
                                -ArgsMap @{ account = "$stateRequester"; probe = $chosen }
                } catch { }
            }
        }
    }

    if ($stale.Count -gt 0) {
        $slow  = @('lock.probe.ps1','pending.probe.ps1','wsl.probe.ps1')   # calculees en dernier
        $stale = @($stale | Sort-Object @{ Expression = { if ($slow -contains $_.Name) { 1 } else { 0 } } }, Name)
        <#
            ONE LOCK PER PROBE WHEN ONE PROBE IS COMPUTED (D124). A single global lock made the scheduler's limit a
            decoration: three launches would simply have queued behind each other. Computing SEVERAL probes still takes
            the shared lock -- that path is the explicit refresh, and it is the one that must not be run twice at once.
            A single-probe worker and a multi-probe refresh can therefore overlap on the same probe; it costs one
            wasted pass, and the cache write is protected file by file (Update-StateJson).
        #>
        $lockName = 'Local\VigieStateRecompute'
        if ($stale.Count -eq 1) { $lockName = 'Local\VigieStateRecompute_' + ($stale[0].Name -replace '[^A-Za-z0-9]', '_') }
        $mx = $null; $got = $false
        try {
            $mx = New-Object System.Threading.Mutex($false, $lockName)
            # An EXPLICIT request (-Force, the "Refresh" button) WAITS its turn; ordinary
            # requests do not wait and make do with the cache.
            # With WaitOne(0) for everyone, the button did nothing as soon as a background
            # refresh held the lock: it handed back at once.
            <#
                A PERSONAL CARD MUST BE COMPUTED NOW, or it never will be. The background
                refresh runs with no session: it writes under the anonymous key, never under
                "@<account>". If the request asking for it does not wait for the lock, its
                entry stays stale indefinitely -- seen on 30/08: the card announced v0.1.29-dev5
                while the installation was at v0.1.30, and two calls in a row gave the same
                answer.

                So for those cards we wait our turn, even without an explicit request.
            #>
            $personnelles = @($stale | Where-Object { $_.PerAccount }).Count
            $secondes = [Math]::Max($WaitSeconds, $(if ($personnelles) { 30 } else { 0 }))
            $waitMs = [Math]::Min($secondes, 75) * 1000
            try { $got = $mx.WaitOne($waitMs) }
            catch [System.Threading.AbandonedMutexException] { $got = $true }
            catch { $got = $false }
            if ($got) {
                # Where the run came from, for the log: an explicit request waits
                # (WaitSeconds > 0 or -Force), and the rest is a background refresh.
                $origine = if ($Force -or $ForceModule -or $WaitSeconds -gt 0) { 'forced' } else { 'background' }
                foreach ($sp in $stale) {
                    $t0 = Get-Date
                    try {
                        # FOR WHOM, said just before the probe runs and taken back just after: a probe dot-sources
                        # this library itself, so nothing else reaches it (D128).
                        $global:VigieStateAccount = $stateRequester
                        $m = & $sp.File
                        $elapsedMs = [int]((Get-Date) - $t0).TotalMilliseconds
                        if ($m) { $cache[$sp.Key] = [ordered]@{ module = $m; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp } }
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms $elapsedMs -Origin $origine -Outcome ($(if ($m) { 'ok' } else { 'empty' })) -Modules @($m).Count
                        Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'common.sonde-recalculee-ms' $sp.Name $elapsedMs)
                        # History: samples the catalogue's measurements AFTER a successful
                        # recomputation. Best effort -- the function never fails.
                        if ($m) { Write-MeasureSamples -Backend $Backend -Probe $sp.Name -Modules @($m) }
                    } catch {
                        Write-ProbeRun -Backend $Backend -Probe $sp.Name -Ms ([int]((Get-Date) - $t0).TotalMilliseconds) -Origin $origine -Outcome 'error' -Detail $_.Exception.Message
                        Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (Get-Label 'common.sonde-erreur' $sp.Name $_.Exception.Message)
                        <#
                            AN ERROR LOOKS LIKE EVERYTHING ELSE.

                            The failure card was called "accounts.probe.ps1" and landed under
                            "Systeme": a file's name, in the wrong group. Nobody knows which
                            card that corresponds to, and it is exactly the moment one needs
                            to know.

                            The probe's folder IS its module -- probes/<unit>/ -- and its
                            module.psd1 carries the label displayed. That is used: the card
                            keeps its place and its name, and says what failed.
                        #>
                        $unit = Split-Path (Split-Path $sp.File -Parent) -Leaf
                        $label = $unit
                        try {
                            $decl = Join-Path (Split-Path $sp.File -Parent) 'module.psd1'
                            if (Test-Path -LiteralPath $decl) {
                                $d = Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop
                                if ($d.Label) { $label = "$($d.Label)" }
                            }
                        } catch { }
                        # SCOPE 'machine': a probe that threw says so to everyone. The failure is the computer's,
                        # not an account's -- and the card it replaces may have had either scope.
                        $errMod = New-ModuleObject -Id $sp.Name -Theme $unit -Label $label -Scope 'machine' -Status 'error' -Fields @(
                            New-Field -Key 'error' -Label 'Erreur' -Value $_.Exception.Message -Kind 'text' -Status 'error'
                            New-Field -Key 'probe' -Label 'Sonde' -Value $sp.Name -Kind 'text'
                        )
                        $cache[$sp.Key] = [ordered]@{ module = $errMod; at = (Get-Date).ToUniversalTime().ToString('o'); codeStamp = $sp.Stamp }
                    }
                    # Written MERGED, entry by entry, under a mutex (Update-StateJson).
                    #
                    # The whole file used to be rewritten from the in-memory copy: two
                    # simultaneous recomputations -- the forced request and the background
                    # refresh -- clobbered each other, and an entry already corrected went
                    # back to its old value: a card in error rose again after being fixed.
                    # Rewriting ONLY the probe just computed removes the race.
                    # -Depth 24: a card may carry a TREE (the disk analysis).
                    # At the default depth (8), ConvertTo-Json truncates IN SILENCE and the
                    # deep branches reach the interface EMPTY -- seen on 26/08: lines with
                    # neither name nor size under every folder.
                    try { Update-StateJson -Path $cacheFile -Set @{ $sp.Key = $cache[$sp.Key] } -Depth 24 | Out-Null } catch { }
                }
            }
        } finally {
            # AND IT IS TAKEN BACK. A global left behind would answer for the next computation, which may be for
            # somebody else or for nobody.
            $global:VigieStateAccount = $null
            if ($got -and $mx) { try { $mx.ReleaseMutex() } catch { } }
            if ($mx) { try { $mx.Dispose() } catch { } }
        }
    }

    # Assembles the modules from the cache, in the order of the probe files.
    # A probe may return ONE module or an ARRAY of modules (flattened here).
    <#
        WHAT EACH CARD COSTS IS MEASURED. Not the total: the detail.

        "I want to see what takes time to load, card by card." Without that, a slow /state is
        a single figure from which nothing can be deduced -- it took a day to find that the 28
        seconds came from a rights check, and not from the probes everyone suspected.

        The time is carried by the card itself (the "ms" field) and summarised in the "state"
        log. It counts the SERVICE: reading the cache, the state of the operations, the rights
        of the actions -- everything happening while the page waits.
    #>
    & $markPhase 'fraicheur'
    $modules = @()
    $chrono = @{}
    <#
        WHAT THE SCHEDULER KNOWS ABOUT EACH CARD, read ONCE for all of them (S16).

        A value twenty-two hours old looked exactly like a value from this second: nothing, on the card or in the
        contract, told them apart. A card now carries what is needed to know -- when the probe produced what it
        shows, when the scheduler last passed, and the interval that applies -- plus its consecutive failures,
        without which it serves its last successful value in silence.

        Read per card, this would be twenty readings of the same state file for one page.
    #>
    $refreshByCard = @{}
    try {
        $refreshState = Get-RefreshState -Backend $Backend
        $refreshModes = @(Get-ActiveModes -Backend $Backend)
        foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
            $entry = $refreshState[$d.Key]
            $info = [pscustomobject]@{
                Seconds   = (Get-RefreshInterval -Declaration $d -Modes $refreshModes)
                # THE TICKS ARE UTC, and a date built on them is born "unspecified": handed over as is, the page
                # would read it as local time and show a two-hour gap (D44).
                EndedAt   = $(if ($entry -and [long]$entry.lastEndedAt) { ([datetime]::new([long]$entry.lastEndedAt, [DateTimeKind]::Utc)).ToString('o') } else { '' })
                Fails     = $(if ($entry) { [int]$entry.fails } else { 0 })
                LastError = $(if ($entry) { "$($entry.lastError)" } else { '' })
                # STARTED BUT NEVER FINISHED is not the same breakdown as NEVER STARTED, and both looked alike:
                # a card that stops moving, with no failure counted. So the start is said too.
                StartedAt = $(if ($entry -and [long]$entry.lastStartedAt) { ([datetime]::new([long]$entry.lastStartedAt, [DateTimeKind]::Utc)).ToString('o') } else { '' })
            }
            # A per-account card has one declaration per account: the requester's is the one that concerns it.
            if ($d.Account -and "$($d.Account)" -ne "$stateRequester") { continue }
            foreach ($card in @($d.Cards)) {
                if (-not $card) { continue }
                if (-not $refreshByCard.ContainsKey("$card")) { $refreshByCard["$card"] = @() }
                $refreshByCard["$card"] += $info
            }
        }
    } catch { }
    foreach ($pf in $probeFiles) {
        $t = [Diagnostics.Stopwatch]::StartNew()
        $e = $cache[(Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester)]
        $t.Stop()
        # HELD BACK? The pace travels with the card, computed here so that no probe has to know about it: the
        # interface says it in the card's header, and only on the cards actually slowed down.
        $paceNow  = Get-ProbeTtlNow -Name $pf.Name -Default $defaultTtl -Backend $Backend -InGame:$inGame
        $paceBase = Get-ProbeTtlNow -Name $pf.Name -Default $defaultTtl -Backend $Backend -Base
        if ($e -and $e.module) {
            foreach ($mm in @($e.module)) {
                $modules += $mm
                if ($mm -and $mm.id) { $chrono["$($mm.id)"] = [double]$t.Elapsed.TotalMilliseconds }
                # MARKED ONLY WHEN IT MATTERS: twice its usual pace AND at least two minutes. Saying "held back" for
                # twenty seconds instead of fifteen would be noise on every card of a game session.
                if ($mm -and $paceNow -ge [Math]::Max(120, 2 * $paceBase)) {
                    $pace = @{ seconds = $paceNow; reason = 'jeu' }
                    try {
                        if ($mm -is [System.Collections.IDictionary]) { $mm['pace'] = $pace }
                        else { Add-Member -InputObject $mm -NotePropertyName 'pace' -NotePropertyValue $pace -Force }
                    } catch { }
                }
                # FRESHNESS TRAVELS WITH THE CARD (S16): three moments, three different questions -- when the probe
                # produced what is being read, when the scheduler last passed, and how often it is meant to.
                if ($mm -and $mm.id) {
                    try {
                        # ONE DATE FORMAT TOWARDS THE PAGE (D44): the cache keeps "at" in whatever shape
                        # ConvertFrom-Json gave it, which follows the culture. We answer ISO 8601, always.
                        <#
                            AND WHEN THE ENTRY CARRIES NO DATE, WE ASK THE PROBE'S NEWEST STAMP rather than send
                            nothing -- or worse, the year 0001, which is what an unparsable value converts to and
                            what the accounts card was showing. A card holding a value has been computed; the only
                            question is when, and the stamp of its probe answers it.
                        #>
                        $computed = ''
                        try { $u = ConvertTo-UtcDate $e.at; if ($u -and $u.Year -gt 1) { $computed = $u.ToString('o') } } catch { }
                        if (-not $computed) {
                            try {
                                $u = ConvertTo-UtcDate (Get-ProbeCacheStamp -Backend $Backend -Probe $pf.Name)
                                if ($u -and $u.Year -gt 1) { $computed = $u.ToString('o') }
                            } catch { }
                        }
                        $fresh = @{ computedAt = $computed }
                        $decl = @($refreshByCard["$($mm.id)"])[0]
                        if ($decl) {
                            $fresh.seconds = [int]$decl.Seconds
                            if ($decl.EndedAt) { $fresh.refreshedAt = "$($decl.EndedAt)" }
                            if ($decl.StartedAt) { $fresh.startedAt = "$($decl.StartedAt)" }
                            if ([int]$decl.Fails -gt 0) { $fresh.fails = [int]$decl.Fails; $fresh.lastError = "$($decl.LastError)" }
                        }
                        if ($mm -is [System.Collections.IDictionary]) { $mm['freshness'] = $fresh }
                        else { Add-Member -InputObject $mm -NotePropertyName 'freshness' -NotePropertyValue $fresh -Force }
                    } catch { }
                }
                # TO BE RECOMPUTED: the card shows, and says it is waiting for its measurement.
                if ($mm -and $e.pending) {
                    try {
                        if ($mm -is [System.Collections.IDictionary]) { $mm['pending'] = $true }
                        else { Add-Member -InputObject $mm -NotePropertyName 'pending' -NotePropertyValue $true -Force }
                    } catch { }
                }
            }
        }
    }

    <#
        A PROBE ALWAYS HAS ITS CARD. WITHOUT EXCEPTION.

        A card shows full, empty, or in error -- it is never missing. A probe that has never
        produced anything had no cache entry, and therefore no card: a hole in the page, whose
        contents nobody can guess.

        So a waiting card is returned, built on what is known without running anything at all:
        the folder's module.psd1 gives its title, the folder gives its group. It carries "en
        attente de mesure" and its button, which is enough to fill it.
    #>
    & $markPhase 'assemblage'
    $known = @($modules | ForEach-Object { "$($_.id)" })
    foreach ($pf in $probeFiles) {
        $unit = Split-Path (Split-Path $pf.FullName -Parent) -Leaf
        if ($known -contains $unit) { continue }
        $e = $cache[(Get-ProbeCacheKey -ProbeFile $pf.FullName -Account $stateRequester)]
        if ($e -and $e.module) { continue }
        $cardLabel = $unit
        $cardTheme = $unit
        try {
            $decl = Import-PowerShellDataFile -Path (Join-Path (Split-Path $pf.FullName -Parent) 'module.psd1')
            if ($decl.Label) { $cardLabel = "$($decl.Label)" }
            # THE GROUP IS DECLARED, and the folder serves as the default otherwise.
            # "deployment" is not a group: its card is read under "Comptes", and the header
            # displayed "DEPLOYMENT" in English for want of knowing.
            if ($decl.Theme) { $cardTheme = "$($decl.Theme)" }
        } catch { }
        # SCOPE 'machine': this card says only that a measurement has not happened yet, which is true for everyone.
        $modules += (New-ModuleObject -Id $unit -Theme $cardTheme -Label $cardLabel -Scope 'machine' -Status 'neutral' -Fields @() -Actions @())
        $chrono[$unit] = 0
        try { Add-Member -InputObject $modules[-1] -NotePropertyName 'pending' -NotePropertyValue $true -Force } catch { }
    }

    <#
        "AN OPERATION IS RUNNING" IS READ NOW, NOT AT THE TIME OF THE COMPUTATION.

        A probe lays that state while it runs -- and its rendering is then served from the
        cache. An operation started AFTER that computation therefore did not show: the
        Deployment card stayed normal, its buttons active, while the update was running (seen
        on 31/08, the notification announcing "running for 26 s" while the card showed
        nothing).

        It is not a measurement, it is a present fact: it is read again at every response and
        laid over the rendering, whatever its age. The field also disappears by itself when
        the mark is gone.
    #>
    foreach ($m in $modules) {
        if (-not $m -or -not $m.id) { continue }
        $mark = Get-ModuleBusyMark -Module "$($m.id)" -Backend $Backend
        $props = @{ busy = [bool]$mark
                    busyAction = $(if ($mark) { $(if ("$($mark.button)") { "$($mark.button)" } else { "$($mark.action)" }) } else { $null })
                    busyResources = $(if ($mark -and $mark.resources) { @($mark.resources) } else { @() }) }
        foreach ($k in @($props.Keys)) {
            $v = $props[$k]
            try {
                if ($m -is [System.Collections.IDictionary]) {
                    if ($v -or $v -is [array]) { $m[$k] = $v } else { $m.Remove($k) | Out-Null }
                } else {
                    Add-Member -InputObject $m -NotePropertyName $k -NotePropertyValue $v -Force
                }
            } catch { }
        }
    }

    # INVARIANT (D66): an action NAMED by a field (fixAction) must appear among the card's
    # actions, or the interface has neither label nor kind to draw and the fixing button does
    # not appear. It is completed here rather than obliging every probe to redeclare the
    # action in its own bar.
    foreach ($m in $modules) {
        $connues = @(@($m.actions) | Where-Object { $_ -and $_.id } | ForEach-Object { "$($_.id)" })
        foreach ($ch in @($m.fields)) {
            $fa = "$($ch.fixAction)"
            if (-not $fa -or $connues -contains $fa) { continue }
            $pres = Get-ActionPresentation -Type $fa -Backend $Backend
            $act = New-Action -Id $fa -Label $pres.label -Kind $pres.kind -Severity $pres.severity `
                              -Help "Résolution proposée par la ligne « $($ch.label) »."
            try { $m.actions = @(@($m.actions) + $act) } catch { }
            $connues += $fa
        }
    }

    # Rights: every action says whether THIS account can launch it, and if not why (D65). It
    # is done here, once and for all, rather than in each probe.
    foreach ($m in $modules) {
        $tDroits = [Diagnostics.Stopwatch]::StartNew()
        foreach ($act in @($m.actions)) {
            if (-not $act -or -not $act.id) { continue }
            $droit = Test-ActionAllowed -Type "$($act.id)" -Backend $Backend
            try {
                if ($act -is [System.Collections.IDictionary]) {
                    $act['allowed'] = $droit.allowed
                    if (-not $droit.allowed) { $act['deniedReason'] = $droit.reason }
                } else {
                    Add-Member -InputObject $act -NotePropertyName 'allowed' -NotePropertyValue $droit.allowed -Force
                    if (-not $droit.allowed) { Add-Member -InputObject $act -NotePropertyName 'deniedReason' -NotePropertyValue $droit.reason -Force }
                }
            } catch { }
        }
        $tDroits.Stop()
        if ($m -and $m.id) {
            $ms = [math]::Round(([double]$chrono["$($m.id)"] + $tDroits.Elapsed.TotalMilliseconds), 1)
            $chrono["$($m.id)"] = $ms
            try {
                if ($m -is [System.Collections.IDictionary]) { $m['ms'] = $ms }
                else { Add-Member -InputObject $m -NotePropertyName 'ms' -NotePropertyValue $ms -Force }
            } catch { }
        }
    }

    & $markPhase 'chronometrage'
    # THE DETAIL, IN THE LOG: one line, sorted from the slowest to the quickest.
    try {
        $timingLines = @($chrono.GetEnumerator() | Sort-Object Value -Descending |
                          ForEach-Object { "$($_.Key)=$($_.Value)ms" })
        if ($timingLines.Count) {
            Write-Log -Backend $Backend -Name 'state' -NoEcho `
                      -Message ("service par carte : " + ($timingLines -join ' '))
            Write-Log -Backend $Backend -Name 'state' -NoEcho `
                      -Message ("phases : " + (($phases.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)ms" }) -join ' '))
        }
    } catch { }

    & $markPhase 'droits-et-operations'
    $present = @($modules | Select-Object -ExpandProperty theme -Unique)
    $themes  = @($script:ThemeCatalog | Where-Object { $present -contains $_.id })
    # THE MODULE CATALOGUE was taken out of the object so it could be MEASURED: as long as
    # it was written inside the final construction, its cost drowned in "the rest".
    $unites = @(Get-UnitCatalog -Backend $Backend)
    & $markPhase 'catalogue-modules'
    # THE REST: version, build stamp, machine name. Measured too, or "the rest" becomes the
    # place where time hides again.
    $version = (Get-AppVersion -Backend $Backend)
    $build   = (Get-AppBuildId -Backend $Backend)
    & $markPhase 'identite-de-version'

    [pscustomobject][ordered]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        version     = $version
        build       = $build
        host        = "$env:COMPUTERNAME"
        themes      = $themes
        modules     = @($modules)
        # THE DETAIL OF THE TIME, in the response: what is not measured gets suspected.
        timings     = $phases
        # ALL the folder-modules, disabled ones included (D48): that is what lets the
        # management view offer to switch back on what is no longer displayed.
        units       = $unites
    }
}

# --- THE HARDWARE SHEET: what does not move ----------------------------------
#
# The second export asked for, the other being the state at this instant: the PHYSICAL
# characteristics of the machine. They are read once and kept: a memory module does not
# change between two refreshes, and the inventory costs several seconds (CIM over a dozen
# classes).
#
# Every section is independent and defensive: a CIM class absent or refused gives an empty
# section, never an error -- a partial sheet beats no sheet.
function Get-HardwareSpecs {
    param(
        [string]$Backend = (Get-BackendRoot),
        # A fresh reading: after a hardware change, or from the export.
        [switch]$Force
    )
    $cacheFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'hardware.json'
    if (-not $Force -and (Test-Path -LiteralPath $cacheFile)) {
        try {
            $j = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            $at = ConvertTo-UtcDate $j.at
            # Seven days: hardware does not change, but an eternal sheet would survive a new
            # disk or a new memory module without anybody knowing.
            if ($at -and ([datetime]::UtcNow - $at).TotalDays -lt 7) { return $j }
        } catch { }
    }

    function Lire { param([string]$Classe, [string]$Espace = 'root/cimv2')
        try { return @(Get-CimInstance -Namespace $Espace -ClassName $Classe -ErrorAction Stop) } catch { return @() }
    }
    $go = { param($octets) if ($octets) { [math]::Round(([double]$octets) / 1GB, 1) } else { $null } }

    $cs   = @(Lire 'Win32_ComputerSystem')   | Select-Object -First 1
    $bios = @(Lire 'Win32_BIOS')             | Select-Object -First 1
    $cb   = @(Lire 'Win32_BaseBoard')        | Select-Object -First 1
    $os   = @(Lire 'Win32_OperatingSystem')  | Select-Object -First 1
    $enc  = @(Lire 'Win32_SystemEnclosure')  | Select-Object -First 1

    # Laptop or desktop? The chassis type says so (8-14 and 30-32 mean mobile).
    $mobile = $false
    try {
        foreach ($t in @($enc.ChassisTypes)) {
            if ((8..14) -contains [int]$t -or (30..32) -contains [int]$t) { $mobile = $true }
        }
    } catch { }

    $machine = [ordered]@{
        nom          = "$env:COMPUTERNAME"
        fabricant    = "$($cs.Manufacturer)"
        modele       = "$($cs.Model)"
        famille      = "$($cs.SystemFamily)"
        forme        = $(if ($mobile) { 'Portable' } else { 'Poste fixe' })
        numeroSerie  = "$($bios.SerialNumber)"
        uuid         = "$((@(Lire 'Win32_ComputerSystemProduct') | Select-Object -First 1).UUID)"
        os           = "$($os.Caption)"
        osVersion    = "$($os.Version)"
        osArchi      = "$($os.OSArchitecture)"
        installeLe   = $(try { ([datetime]$os.InstallDate).ToString('o') } catch { '' })
    }

    $motherboard = [ordered]@{
        fabricant = "$($cb.Manufacturer)"
        modele    = "$($cb.Product)"
        version   = "$($cb.Version)"
        bios      = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
        biosDate  = $(try { ([datetime]$bios.ReleaseDate).ToString('o') } catch { '' })
    }

    $processeurs = @(foreach ($c in (Lire 'Win32_Processor')) {
        [ordered]@{
            nom       = "$($c.Name)".Trim()
            fabricant = "$($c.Manufacturer)"
            coeurs    = [int]$c.NumberOfCores
            fils      = [int]$c.NumberOfLogicalProcessors
            frequence = [int]$c.MaxClockSpeed          # MHz
            socket    = "$($c.SocketDesignation)"
            cacheL3Ko = [int]$c.L3CacheSize
        }
    })

    # Memory type: the SMBIOS code, translated. A number tells nobody anything.
    $typesMem = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'LPDDR4'; 36 = 'LPDDR5' }
    $memoryModules = @(foreach ($m in (Lire 'Win32_PhysicalMemory')) {
        $t = $null
        try { if ($typesMem.ContainsKey([int]$m.SMBIOSMemoryType)) { $t = $typesMem[[int]$m.SMBIOSMemoryType] } } catch { }
        [ordered]@{
            emplacement = "$($m.DeviceLocator)"
            tailleGo    = (& $go $m.Capacity)
            type        = $(if ($t) { $t } else { '' })
            vitesse     = [int]$m.Speed                # MT/s
            fabricant   = "$($m.Manufacturer)".Trim()
            reference   = "$($m.PartNumber)".Trim()
        }
    })
    $memoire = [ordered]@{
        totalGo   = (& $go $cs.TotalPhysicalMemory)
        barrettes = $memoryModules
        # What the motherboard can take: useful when an upgrade is being considered.
        emplacements = [int]((@(Lire 'Win32_PhysicalMemoryArray') | Select-Object -First 1).MemoryDevices)
    }

    $disques = @(foreach ($d in (Lire 'MSFT_PhysicalDisk' 'root/microsoft/windows/storage')) {
        $bus = switch ([int]$d.BusType) { 7 { 'USB' } 8 { 'RAID' } 11 { 'SATA' } 17 { 'NVMe' } default { '' } }
        $media = switch ([int]$d.MediaType) { 3 { 'Disque dur' } 4 { 'SSD' } 5 { 'SCM' } default { '' } }
        [ordered]@{
            modele    = "$($d.FriendlyName)".Trim()
            tailleGo  = (& $go $d.Size)
            type      = $media
            bus       = $bus
            sante     = $(switch ([int]$d.HealthStatus) { 0 { 'Sain' } 1 { 'A surveiller' } 2 { 'Defaillant' } default { '' } })
            firmware  = "$($d.FirmwareVersion)"
            numeroSerie = "$($d.SerialNumber)".Trim()
        }
    })
    # Fallback: on a machine with no Storage namespace, Win32_DiskDrive is enough.
    if (-not $disques.Count) {
        $disques = @(foreach ($d in (Lire 'Win32_DiskDrive')) {
            [ordered]@{ modele = "$($d.Model)".Trim(); tailleGo = (& $go $d.Size)
                        type = ''; bus = "$($d.InterfaceType)"; sante = ''
                        firmware = "$($d.FirmwareRevision)".Trim(); numeroSerie = "$($d.SerialNumber)".Trim() }
        })
    }

    # VRAM IS NOT READ FROM AdapterRAM: that field is a signed 32-bit integer, it caps at
    # 4 GB and returns nonsense beyond it (an 8 GB RTX 4070 appears there with 4 GB, sometimes
    # less). The real value is in the driver's registry key, qwMemorySize, on 64 bits.
    $vramByName = @{}
    try {
        $classe = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        # SilentlyContinue rather than Stop: one of this class's sub-keys is refused even to
        # an administrator ("Requested registry access is not allowed"), and with Stop the
        # enumeration stopped BEFORE the NVIDIA card -- the VRAM then fell back on AdapterRAM,
        # which caps at 4 GB. Seen on this very machine.
        foreach ($k in (Get-ChildItem -Path $classe -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $pr = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if ($pr -and $pr.DriverDesc -and $pr.'HardwareInformation.qwMemorySize') {
                $vramByName["$($pr.DriverDesc)"] = [math]::Round(([double]$pr.'HardwareInformation.qwMemorySize') / 1GB, 1)
            }
        }
    } catch { }

    $graphiques = @(foreach ($g in (Lire 'Win32_VideoController')) {
        $gpuName = "$($g.Name)".Trim()
        [ordered]@{
            nom        = $gpuName
            vramGo     = $(if ($vramByName.ContainsKey($gpuName)) { $vramByName[$gpuName] } else { (& $go $g.AdapterRAM) })
            pilote     = "$($g.DriverVersion)"
            piloteDate = $(try { ([datetime]$g.DriverDate).ToString('o') } catch { '' })
            resolution = $(if ($g.CurrentHorizontalResolution) { "$($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution)" } else { '' })
        }
    })

    # Monitors: WmiMonitorID returns arrays of codes, not strings.
    $decodeWmiText = { param($codes) if (-not $codes) { return '' }
        (-join ($codes | Where-Object { $_ -gt 0 } | ForEach-Object { [char][int]$_ })).Trim() }
    $ecrans = @(foreach ($e in (Lire 'WmiMonitorID' 'root/wmi')) {
        $size = ''
        [ordered]@{
            fabricant = (& $decodeWmiText $e.ManufacturerName)
            modele    = (& $decodeWmiText $e.UserFriendlyName)
            serie     = (& $decodeWmiText $e.SerialNumberID)
            annee     = [int]$e.YearOfManufacture
        }
    })
    # Inches: a separate class (physical dimensions, in centimetres).
    $sizes = @(Lire 'WmiMonitorBasicDisplayParams' 'root/wmi')
    for ($i = 0; $i -lt $ecrans.Count -and $i -lt $sizes.Count; $i++) {
        try {
            $l = [double]$sizes[$i].MaxHorizontalImageSize
            $h = [double]$sizes[$i].MaxVerticalImageSize
            if ($l -gt 0 -and $h -gt 0) {
                $ecrans[$i]['pouces'] = [math]::Round([math]::Sqrt($l * $l + $h * $h) / 2.54, 1)
            }
        } catch { }
    }

    # PHYSICAL network adapters.
    #
    # Win32_NetworkAdapter.PhysicalAdapter is NOT enough: it answers "yes" for Bluetooth PAN,
    # for VirtualBox and VMware adapters, and for WAN Miniport ones. Get-NetAdapter -Physical,
    # on the other hand, rests on the real device type -- it is used as a white list wherever
    # it is available.
    $reelles = $null
    try { $reelles = @((Get-NetAdapter -Physical -ErrorAction Stop).InterfaceDescription) } catch { }
    $reseau = @(foreach ($a in (Lire 'Win32_NetworkAdapter')) {
        if (-not $a.PhysicalAdapter) { continue }
        if (-not "$($a.MACAddress)") { continue }
        if ($reelles -and ($reelles -notcontains "$($a.Description)")) { continue }
        if (-not $reelles -and "$($a.Name)" -match 'Virtual|Host-Only|Bluetooth|Miniport|Loopback') { continue }
        [ordered]@{
            nom       = "$($a.Name)".Trim()
            fabricant = "$($a.Manufacturer)".Trim()
            mac       = "$($a.MACAddress)"
            # Windows returns 0xFFFFFFFFFFFFFFFF when the link is not established, which gave
            # "9223372036855 Mb/s" on the sheet. Past 100 Gb/s the value means nothing: we
            # display nothing rather than an absurdity.
            debitMax  = $(if ($a.Speed -and ([double]$a.Speed) -lt 1e11) { [math]::Round(([double]$a.Speed) / 1e6) } else { $null })   # Mb/s
        }
    })

    $batterie = $null
    $bat = @(Lire 'Win32_Battery') | Select-Object -First 1
    if ($bat) {
        $pleine = @(Lire 'BatteryFullChargedCapacity' 'root/wmi') | Select-Object -First 1
        $batterie = [ordered]@{
            nom         = "$($bat.Name)".Trim()
            chimie      = $(switch ([int]$bat.Chemistry) { 3 { 'Nickel-Cadmium' } 4 { 'Nickel-Hydrure' } 5 { 'Lithium-ion' } 6 { 'Zinc-air' } 7 { 'Lithium-polymere' } default { '' } })
            capaciteMwh = $(if ($pleine) { [int]$pleine.FullChargedCapacity } else { $null })
            tension     = $(if ($bat.DesignVoltage) { [int]$bat.DesignVoltage } else { $null })   # mV
        }
    }

    $fiche = [pscustomobject][ordered]@{
        at          = (Get-Date).ToUniversalTime().ToString('o')
        machine     = $machine
        carteMere   = $motherboard
        processeurs = $processeurs
        memoire     = $memoire
        disques     = $disques
        graphiques  = $graphiques
        ecrans      = $ecrans
        reseau      = $reseau
        batterie    = $batterie
    }
    try {
        $d = Split-Path $cacheFile -Parent
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        ($fiche | ConvertTo-Json -Depth 12) | Out-File -FilePath $cacheFile -Encoding UTF8
    } catch { }
    return $fiche
}

# --- A CARD'S BACKGROUND TASK: saying it, and for as long as it lasts --------
#
# The owner's rule: "a card that launches an action in the background should go into the
# operation-running state immediately". The interface marks it from the click, but that
# marking does not survive the first refresh: it is the SERVER that must carry the truth, or
# the card goes calm again while the work continues -- seen on 26/08 during the installation
# of PowerShell 7 from the Accounts card.
#
# The mark carries the process id of what was launched: for as long as it lives, the card is
# busy; the moment it dies, the mark clears itself. Nothing to clean up by hand, and a brutal
# stop does not leave a card busy for ever.
function Get-ModuleBusyMarkPath {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'run' -File ('busy-' + $Module + '.json')
}

function Set-ModuleBusyMark {
    param(
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][string]$Label,
        [int]$ProcessId,
        [string]$Action = '',
        # What this work TAKES UP: it is what will allow refusing whatever would disturb it,
        # and only that (D93).
        [string[]]$Resources = @(),
        # The card button that spins when it is not the action itself, the launch time, the operation's log.
        [string]$Button = '',
        [string]$At = '',
        [string]$Log = '',
        # HOW LONG THIS WORK MAY TAKE before it is treated as stuck. Carried by the mark so that the READER can
        # judge: if the process that set the mark is blocked, it can no longer judge anything itself.
        [int]$MaxSeconds = 0,
        [string]$Backend = (Get-BackendRoot)
    )
    $f = Get-ModuleBusyMarkPath -Module $Module -Backend $Backend
    $d = Split-Path $f -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    if (-not $Resources -or -not $Resources.Count) { $Resources = @(Get-ActionResources -Type $Action -Module $Module) }
    $o = [ordered]@{ label = $Label; pid = $ProcessId; action = $Action
                     resources = @($Resources)
                     button = $Button; log = $Log; maxSeconds = $MaxSeconds
                     at = $(if ($At) { $At } else { (Get-Date).ToUniversalTime().ToString('o') }) }
    try { ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath $f -Encoding UTF8 } catch { }
}

function Get-ModuleBusyMark {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    $f = Get-ModuleBusyMarkPath -Module $Module -Backend $Backend
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $o = $null
    try { $o = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json } catch { }
    if (-not $o) { return $null }
    $alive = $false
    try {
        $process = Get-Process -Id ([int]$o.pid) -ErrorAction Stop
        $alive = $true
        # A PROCESS ID IS REUSED. A process born well after the mark is not the one it names.
        try {
            $markedAt = ConvertTo-UtcDate $o.at
            if ($markedAt -and $process.StartTime.ToUniversalTime() -gt $markedAt.AddSeconds(5)) { $alive = $false }
        } catch { }
    } catch { $alive = $false }
    if (-not $alive) {
        # A PROCESS GONE WITHOUT A RESULT IS A FAILURE, never a silent end: the disappearance of the mark was read
        # as "finished" (12/09). A result written since the launch means the operation did end properly.
        $lastRun = Get-ModuleLastRun -Module $Module -Backend $Backend
        $resultAt = if ($lastRun) { ConvertTo-UtcDate $lastRun.at } else { $null }
        $launchedAt = ConvertTo-UtcDate $o.at
        if (-not $resultAt -or ($launchedAt -and $resultAt -lt $launchedAt)) {
            Set-ModuleLastRun -Module $Module -Action "$($o.action)" -Label "$($o.label)" -Code -1 -Log "$($o.log)" `
                              -Error (Get-Label 'common.operation-sans-resultat') -Backend $Backend
        }
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $o
}

# --- WHAT VIGIE TAKES UP ON THE MACHINE --------------------------------------
#
# Asked for on 27/08: "it would be good to show Vigie's storage, for all the users, and so
# follow what our app consumes". An application that watches other people's disk space owes
# it to say what it takes itself.
#
# Three items, and they are not alike:
#   - the PROGRAM : the shared installation (Program Files), the same for everyone;
#   - the DATA    : cache, history, logs -- ONE SET PER ACCOUNT;
#   - the REPOSITORY : on a development workstation, the sources and dist/.
#
# The data of OTHER accounts are only readable when elevated: without elevation we return
# what we can see, and we SAY so rather than announcing a false total.
function Get-VigieFootprint {
    param([string]$Backend = (Get-BackendRoot))

    function Poids {
        param([string]$Path)
        if (-not (Test-PathSafe $Path)) { return 0 }
        try {
            return [long]((Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                           Measure-Object -Property Length -Sum).Sum)
        } catch { return 0 }
    }

    $partagee = Get-SharedInstallPath
    $programme = Poids $partagee

    # Each account's data: %LOCALAPPDATA%\Sowapps\Vigie, and the old location without the
    # publisher's name, for installations from before D72.
    $perAccount = @()
    $inaccessibles = 0
    $currentAccountVar = $null
    foreach ($c in @(Get-UserAccounts -Backend $Backend)) {
        $local = Join-Path (Join-Path (Join-Path $env:SystemDrive 'Users') $c.name) 'AppData\Local'
        $total = 0
        $vu = $false
        foreach ($d in @((Join-Path (Join-Path $local 'Sowapps') 'Vigie'), (Join-Path $local 'Vigie'))) {
            if (Test-PathSafe $d) { $vu = $true; $total += (Poids $d) }
        }
        # A folder present but unreadable gives 0: without elevation it cannot be told from an
        # empty one. So the uncertainty is counted separately.
        if ($vu -and $total -eq 0 -and -not $c.current) { $inaccessibles++ }
        # THE CURRENT ACCOUNT knows where ITS data are: Get-VarRoot is authoritative. On a
        # development workstation they live in the repository (var/), not in %LOCALAPPDATA% --
        # without that we announced 320 bytes for an account taking up megabytes.
        if ($c.current) {
            $sien = Get-VarRoot -Backend $Backend
            if ($sien -and (Test-Path -LiteralPath $sien)) {
                $total = Poids $sien
                $vu = $true
                $currentAccountVar = $sien
            }
        }
        if ($vu) { $perAccount += [pscustomobject]@{ name = $c.name; bytes = $total; current = $c.current } }
    }

    # The development repository, when it is distinct from the shared installation.
    $repositoryRoot = Get-RepoRoot
    $sources = 0
    if ($repositoryRoot -and (-not $partagee -or $repositoryRoot -ne $partagee)) {
        $sources = Poids $repositoryRoot
        # The current account's var/ is ALREADY counted in the data: it is taken out of the
        # repository, or the total counts it twice.
        if ($currentAccountVar -and $currentAccountVar.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $sources = [Math]::Max(0, $sources - (Poids $currentAccountVar))
        }
    }

    $dataBytes = 0
    foreach ($x in $perAccount) { $dataBytes += $x.bytes }

    [pscustomobject][ordered]@{
        programme     = $programme          # installation partagee
        programmePath = $partagee
        donnees       = $dataBytes            # somme des donnees par compte
        parCompte     = $perAccount
        sources       = $sources            # depot de developpement (0 en usage normal)
        sourcesPath   = $(if ($sources) { $repositoryRoot } else { $null })
        total         = ($programme + $dataBytes + $sources)
        complet       = (Test-IsElevated) -and ($inaccessibles -eq 0)
        inaccessibles = $inaccessibles
    }
}

# --- WHAT IS RUNNING, FOR EVERYONE (D95) -------------------------------------
#
# The notifications lived in the PAGE: a second window open knew nothing of an operation
# launched from the first, and a page opened AFTER a deployment had left saw no trace of it
# at all. The server, on the other hand, knows: it holds the operation marks and their
# results.
#
# So the complete state is returned -- what is running, and what has just finished -- and
# every page agrees with it. The server is the source, the pages are reflections.
<#
    WHAT IS RUNNING, AND WHAT IS PUBLISHED OF IT.

    A watch task comes round every thirty seconds: showing each one would put something permanently in "what is
    running", for information nobody reads. Its mark still always exists -- that is what makes a hang visible --
    but it is PUBLISHED only past its ceiling. -IncludeWatch returns everything, for the debug card, which does
    want the whole list.

    While all is well: nothing. The moment a task overruns: it appears like any other operation.
#>
function Get-RunningOperations {
    param([string]$Backend = (Get-BackendRoot), [switch]$IncludeWatch)
    $ops = @()
    $folder = Split-Path (Get-ModuleBusyMarkPath -Module 'x' -Backend $Backend) -Parent
    if (Test-Path -LiteralPath $folder) {
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)) {
            $module = ($f.BaseName -replace '^busy-', '')
            $m = Get-ModuleBusyMark -Module $module -Backend $Backend
            if (-not $m) { continue }
            # THE PROCESS NUMBER TRAVELS TOO. The protocol says the mark carries it, and that /operations is the
            # ONE place where an operation's state is read. The route dropped it, so through the door the protocol
            # designates nobody could tell a live operation from a dead one -- the check existed, reading the mark
            # directly, elsewhere. Found on 06/10 while proving the protocol on a 613-second disk analysis.
            <#
                AND THE READER SAYS WHETHER IT IS LATE.

                The mark carries its own ceiling; here we compare it to the clock. The judgement has to live on this
                side: a watch task that hangs hangs the timer with it, and nothing in that runspace can report
                anything any more. This function runs in the HTTP request, which is another thread -- so a blocked
                task is seen even when everything else is frozen.
            #>
            $maxSeconds = 0
            try { $maxSeconds = [int]$m.maxSeconds } catch { }
            $running = 0
            try { $running = [int]([datetime]::UtcNow - (ConvertTo-UtcDate $m.at)).TotalSeconds } catch { }
            $ops += [pscustomobject][ordered]@{
                module    = $module
                label     = "$($m.label)"
                action    = "$($m.action)"
                pid       = [int]$m.pid
                resources = @($m.resources)
                at        = "$($m.at)"
                seconds   = $running
                maxSeconds = $maxSeconds
                overdue   = ($maxSeconds -gt 0 -and $running -gt $maxSeconds)
            }
        }
    }
    if (-not $IncludeWatch) {
        $ops = @($ops | Where-Object { "$($_.module)" -ne 'veille' -or $_.overdue })
    }
    return $ops
}

# The RECENT results: what finished recently enough that a page opened since still has reason
# to show it. Past that, it is history: it lives on the card concerned, not in the
# notifications.
function Get-RecentOperationResults {
    param([int]$Minutes = 15, [string]$Backend = (Get-BackendRoot))
    $res = @()
    $folder = Split-Path (Get-ModuleLastRunPath -Module 'x' -Backend $Backend) -Parent
    if (-not (Test-Path -LiteralPath $folder)) { return $res }
    $limit = [datetime]::UtcNow.AddMinutes(-$Minutes)
    foreach ($f in @(Get-ChildItem -LiteralPath $folder -Filter 'lastrun-*.json' -File -ErrorAction SilentlyContinue)) {
        $module = ($f.BaseName -replace '^lastrun-', '')
        $r = Get-ModuleLastRun -Module $module -Backend $Backend
        if (-not $r) { continue }
        $when = ConvertTo-UtcDate $r.at
        if (-not $when -or $when -lt $limit) { continue }
        $res += [pscustomobject][ordered]@{
            module  = $module
            label   = "$($r.label)"
            action  = "$($r.action)"
            code    = [int]$r.code
            seconds = [int]$r.seconds
            log     = "$($r.log)"
            error   = "$($r.error)"
            at      = "$($r.at)"
        }
    }
    return $res
}

# --- WHO HOLDS WHAT: the lock PER RESOURCE (D93) ------------------------------
#
# Blocking EVERY action as soon as an operation runs was crude -- and above all it protected
# nothing: the interface greyed out buttons, but a page left open could still send the action
# to the server. It is the SERVER that must arbitrate.
#
# So an action declares what it TAKES UP. Two actions sharing no resource can run together;
# checking one manager's updates while a disk analysis runs has no reason to be forbidden.
#
# The 'machine' resource is a special case: it crosses EVERYTHING. It belongs to the gestures
# that touch the whole installation or restart the application.
$script:RessourcesParAction = @{
    # What touches the installation or restarts Vigie: nothing else during that time.
    'vigie-update'         = @('machine')
    'pwsh-install-machine' = @('machine')
    'system-restart'       = @('machine')
    'repair-tasks'         = @('taches')
    'service-account-repair' = @('machine')
    'service-clone-repair' = @('clone')
    'service-clone-reset'  = @('clone')
    # Windows Update: the lock, the scan and the installation tread on each other.
    'update-mode-on'       = @('windows-update')
    'update-mode-off'      = @('windows-update')
    'wu-scan'              = @('windows-update')
    'wu-install'           = @('windows-update')
    'wu-list-pending'      = @('windows-update')
    'run-audit'            = @('windows-update')
    <#
        PACKAGE MANAGERS: THE RESERVATION NAMES THE MANAGER, NOT THE FAMILY.

        It read 'paquets' for all of them, on the grounds that they shared one installer. They do not: pip has
        nothing to do with Chocolatey, and it showed on screen -- an upgrade of Chocolatey switched off pip's own
        "check for updates" button. Seen by the owner on 06/10.

        What stays true, and what he asked to keep: checking and upgrading THE SAME manager exclude each other. So
        the resource becomes "paquets-<manager>", returned by Get-ActionResources once it is told which card.
    #>
    'pkg-upgrade'          = @('paquets')
    'pkg-check-updates'    = @('paquets')
    'pkg-list-updates'     = @()               # lecture d'un cache : rien a reserver
    # Disk, network, WSL, accounts.
    'disk-analyze'         = @('disque')
    'disk-analyze-stop'    = @()               # ARRETER doit rester possible pendant
    'disk-tree'            = @()               # lecture d'un cache
    'net-speedtest'        = @('reseau')
    'net-dns-flush'        = @('reseau')
    'net-publicip'         = @()
    'wsl-start'            = @('wsl')
    'wsl-restart'          = @('wsl')
    'wsl-shutdown'         = @('wsl')
    'toggle-vbs'           = @('securite')
    'toggle-hvci'          = @('securite')
    'accounts-refresh'     = @('comptes')
    'diag-account-logs'    = @('comptes')
}

# What an action takes up. By default: NOTHING -- an undeclared action is assumed harmless
# (opening a folder, reading a cache). What gets in the way is declared, not the reverse: a
# default list too wide would end up blocking everything without anyone knowing why.
function Get-ActionResources {
    param([Parameter(Mandatory)][string]$Type, [string]$Module)
    if (-not $script:RessourcesParAction.ContainsKey($Type)) { return @() }
    $res = @($script:RessourcesParAction[$Type])
    # THE MANAGER AS A SUFFIX when the card names it: "pkg-choco" gives "paquets-choco". With no module -- a
    # declaration read out of context -- the family resource is kept, which is wider and never wrong.
    if ($Module -and $Module -like 'pkg-*') {
        $manager = $Module -replace '^pkg-', ''
        if ($manager -and $manager -ne 'none') {
            $res = @($res | ForEach-Object { if ("$_" -eq 'paquets') { 'paquets-' + $manager } else { "$_" } })
        }
    }
    return @($res)
}

# The resources currently HELD, and by what. The live marks are read back: a mark whose
# process is dead holds nothing any more, and it clears itself as it is read.
function Get-HeldResources {
    param([string]$Backend = (Get-BackendRoot))
    $tenues = @()
    $folder = Split-Path (Get-ModuleBusyMarkPath -Module 'x' -Backend $Backend) -Parent
    if (-not (Test-Path -LiteralPath $folder)) { return $tenues }
    foreach ($f in @(Get-ChildItem -LiteralPath $folder -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)) {
        $module = ($f.BaseName -replace '^busy-', '')
        $m = Get-ModuleBusyMark -Module $module -Backend $Backend
        if (-not $m) { continue }
        foreach ($r in @($m.resources)) {
            if ("$r") { $tenues += [pscustomobject]@{ resource = "$r"; label = "$($m.label)"; module = $module } }
        }
    }
    return $tenues
}

# Can THIS action be launched now? Returns $null if so, otherwise the reason, in plain words.
function Test-ActionResourcesFree {
    param([Parameter(Mandatory)][string]$Type, [string]$Module, [string]$Backend = (Get-BackendRoot))
    $veut = @(Get-ActionResources -Type $Type -Module $Module)
    if (-not $veut.Count) { return $null }
    $tenues = @(Get-HeldResources -Backend $Backend)
    if (-not $tenues.Count) { return $null }
    foreach ($t in $tenues) {
        # 'machine' crosses everything, in both directions.
        if ($t.resource -eq 'machine' -or $veut -contains 'machine' -or $veut -contains $t.resource) {
            return ("« " + $t.label + " » est en cours et utilise déjà " +
                    $(if ($t.resource -eq 'machine') { "toute la machine" } else { "la même ressource (" + $t.resource + ")" }) +
                    ". Nouvel essai possible quand cette opération sera terminée.")
        }
    }
    return $null
}

# --- THE FATE OF A BACKGROUND TASK: keep it, then say it ---------------------
#
# "Following errors is paramount": an asynchronous action cannot fail in silence. The watcher
# (workers/watched-action.worker.ps1) writes here what it observed; the card's probe reads it
# back and turns it into a line, green or red.
function Get-ModuleLastRunPath {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'cache' -File ('lastrun-' + $Module + '.json')
}

<#
    WHY IT FAILED: WE READ IT IN THE LOG, WE DO NOT GUESS IT.

    The watcher knows only an EXIT CODE. So the card displayed "ECHEC le 31/08/2026 10:56 --
    code de sortie 4": a number, to a person who wants to know what happened. The script, on
    the other hand, said it -- "Une installation est deja en cours (fhaza, processus
    44940...)" -- and that sentence is in the log the watcher already holds in its hand.

    So the LAST failure line is taken from it, the one the console marked "[X]". It is
    general: any script of the repository using console-ui becomes readable on the card,
    without declaring anything.

    If the log holds none -- a process killed, a script that said nothing -- the exit code is
    kept: a number beats nothing.
#>
function Get-FailureReasonFromLog {
    param([Parameter(Mandatory)][string]$Log)
    if (-not $Log -or -not (Test-PathSafe $Log)) { return $null }
    <#
        WE READ IN UTF-8, AND WE CATCH OURSELVES IF IT IS NOT.

        Logs written before the display was forced to UTF-8 are in the system's code page:
        read as UTF-8, their accents become "?". It is DETECTED -- the replacement character
        U+FFFD -- and the file is read again in the default code page. An existing log must
        not become unreadable because the writing was corrected.
    #>
    $lines = $null
    try { $lines = @(Get-Content -LiteralPath $Log -Encoding UTF8 -ErrorAction Stop) } catch { return $null }
    if (($lines -join '') -match [char]0xFFFD) {
        # "-Encoding Default" NO LONGER MEANS "the system's code page": since PowerShell 7 it
        # is UTF-8, so re-reading that way gave exactly the same "?". We name the machine's
        # ANSI code page, assuming nothing.
        try {
            $ansi = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
            $lines = @([IO.File]::ReadAllText($Log, $ansi) -split "`r?`n")
        } catch { }
    }
    $reason = $null
    try {
        foreach ($line in $lines) {
            # "[X]" is console-ui's failure mark, the same everywhere.
            if ("$line" -match '\[X\]\s*(.+?)\s*$') { $reason = $Matches[1].Trim() }
        }
    } catch { }
    if ($reason) { return $reason }
    return $null
}

function Set-ModuleLastRun {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Action = '', [string]$Label = '',
        [Parameter(Mandatory)][int]$Code,
        [int]$Seconds = 0, [string]$Log = '', [string]$Error = '',
        [string]$Backend = (Get-BackendRoot)
    )
    # THE REASON RATHER THAN THE CODE, as soon as it can be read.
    if (-not $Error -and $Code -ne 0 -and $Log) {
        $lu = Get-FailureReasonFromLog -Log $Log
        if ($lu) { $Error = $lu }
    }
    $f = Get-ModuleLastRunPath -Module $Module -Backend $Backend
    $d = Split-Path $f -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $o = [ordered]@{ action = $Action; label = $Label; code = $Code; seconds = $Seconds
                     log = $Log; error = $Error; at = (Get-Date).ToUniversalTime().ToString('o') }
    try { ($o | ConvertTo-Json -Depth 4) | Out-File -FilePath $f -Encoding UTF8 } catch { }
}

function Get-ModuleLastRun {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    $f = Get-ModuleLastRunPath -Module $Module -Backend $Backend
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch { return $null }
}

function Clear-ModuleLastRun {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    Remove-Item -LiteralPath (Get-ModuleLastRunPath -Module $Module -Backend $Backend -VarRoot $VarRoot) `
                -Force -ErrorAction SilentlyContinue
}

function Clear-ModuleBusyMark {
    param([Parameter(Mandatory)][string]$Module, [string]$Backend = (Get-BackendRoot))
    Remove-Item -LiteralPath (Get-ModuleBusyMarkPath -Module $Module -Backend $Backend) `
                -Force -ErrorAction SilentlyContinue
}

# THE ONLY WAY TO LAUNCH AN ASYNCHRONOUS OPERATION. The rules: doc/progress/targeting/operations.md, section
# "Le protocole des opérations asynchrones". A PowerShell worker and an external program take the same road:
# the watcher runs either one, waits for its end and writes the result. The busy mark is written HERE,
# with the watcher's process id, before the action answers.
function Start-Operation {
    param(
        [Parameter(Mandatory)][string]$Module,     # the card concerned (module id)
        [Parameter(Mandatory)][string]$Action,     # the action id, which names the operation for the pages
        [Parameter(Mandatory)][string]$Label,      # what the pages display
        [string[]]$Probes = @(),                   # probes to recompute at the end
        [string]$Worker = '',                      # either a worker of workers/, run by this pwsh...
        [hashtable]$ArgsMap = @{},
        [string]$File = '',                        # ...or an external program
        [string[]]$Arguments = @(),
        [string]$Log = '',
        [string]$Button = '',                      # the card button that spins, when it is not the action
        [string]$Backend = (Get-BackendRoot)
    )
    $exe = $null
    try { $exe = (Get-Process -Id $PID).Path } catch { }
    if (-not $exe) { $exe = 'pwsh.exe' }
    if ($Worker) {
        $workerPath = Join-Path (Join-Path $Backend 'workers') $Worker
        if (-not (Test-Path -LiteralPath $workerPath)) { throw "Worker introuvable : $workerPath" }
        $workerArgs = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($ArgsMap | ConvertTo-Json -Compress -Depth 6)))
        $File = $exe
        $Arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $workerPath,
                       '-Backend', $Backend, '-ArgsB64', $workerArgs)
    }
    if (-not $File) { throw 'Start-Operation : ni worker ni programme.' }
    if (-not $Log) {
        $Log = Join-Path (Get-LogDir -Backend $Backend) ($Action + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    }
    $watcher = Join-Path (Join-Path $Backend 'workers') 'watched-action.worker.ps1'
    if (-not (Test-Path -LiteralPath $watcher)) { throw "Veilleur introuvable : $watcher" }
    $payload = @{ module = $Module; action = $Action; label = $Label; probes = @($Probes)
                  file = $File; arguments = @($Arguments); log = $Log }
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress -Depth 6)))
    # The previous result goes at launch: the card would otherwise show yesterday's failure during today's work.
    Clear-ModuleLastRun -Module $Module -Backend $Backend
    # Taken BEFORE the start: a watcher that ends at once writes a result dated after this, not before.
    $launchedAt = (Get-Date).ToUniversalTime().ToString('o')
    $p = $null
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $exe
        # ArgumentList, NOT Arguments: .NET quotes each value itself (D116).
        foreach ($piece in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                             '-File', $watcher, '-Backend', $Backend, '-ArgsB64', $b64)) {
            [void]$psi.ArgumentList.Add([string]$piece)
        }
        $psi.UseShellExecute  = $false
        $psi.CreateNoWindow   = $true
        $psi.WindowStyle      = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.WorkingDirectory = $Backend
        $p = [System.Diagnostics.Process]::Start($psi)
    } catch {
        # A launch that fails is a result too, and the card must be able to say it.
        Set-ModuleLastRun -Module $Module -Action $Action -Label $Label -Code -1 -Log $Log -Error $_.Exception.Message -Backend $Backend
        throw
    }
    if (-not $p) {
        Set-ModuleLastRun -Module $Module -Action $Action -Label $Label -Code -1 -Log $Log `
                          -Error (Get-Label 'common.operation-non-lancee') -Backend $Backend
        return $null
    }
    # THE MARK EXISTS BEFORE THE ANSWER. Written by the watcher once started, it arrived after the action had
    # answered, and the page took the Windows Update installation for finished (12/09).
    Set-ModuleBusyMark -Module $Module -Label $Label -ProcessId $p.Id -Action $Action -Button $Button `
                       -At $launchedAt -Log $Log -Backend $Backend
    return $p.Id
}

# THE PROTOCOL'S FAILURE, WHEN THE WORKER COULD NOT SAY IT. A card whose worker writes its own detail shows the
# last run only when that detail predates the run: a process gone, a launch refused. Otherwise the detail says it.
function New-UnreportedFailureField {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Action = '',
        $WrittenAt = $null,
        [string]$Backend = (Get-BackendRoot)
    )
    $lastRun = Get-ModuleLastRun -Module $Module -Backend $Backend
    if (-not $lastRun -or [int]$lastRun.code -eq 0) { return $null }
    if ($Action -and "$($lastRun.action)" -ne $Action) { return $null }
    $endedAt = ConvertTo-UtcDate $lastRun.at
    $written = if ($WrittenAt) { ConvertTo-UtcDate $WrittenAt } else { $null }
    if ($written -and $endedAt -and $written -ge $endedAt.AddSeconds(-[int]$lastRun.seconds - 5)) { return $null }
    return (New-LastRunField -Module $Module -Backend $Backend)
}

# The line the card shows afterwards: nothing while no work has happened, a green line when
# it succeeded, a RED line with its log when it failed.
function New-LastRunField {
    param(
        [Parameter(Mandatory)][string]$Module,
        [string]$Key = 'lastrun',
        [string]$Backend = (Get-BackendRoot)
    )
    $r = Get-ModuleLastRun -Module $Module -Backend $Backend
    if (-not $r) { return $null }
    $when = ''
    try { $when = (ConvertTo-UtcDate $r.at).ToLocalTime().ToString('dd/MM/yyyy HH:mm') } catch { }
    $elapsedMs = if ([int]$r.seconds -ge 60) { [string][int]([int]$r.seconds / 60) + ' min' } else { "$([int]$r.seconds) s" }
    if ([int]$r.code -eq 0) {
        # SUCCEEDED: the DATE is enough (the owner's rule of 27/08). An operation that
        # succeeded has nothing to tell on the card; the duration and the log stay available
        # in the line's detail, for whoever looks for them.
        return (New-Field -Key $Key -Label "$($r.label)" -Value $when `
                          -Kind 'text' -Status 'ok' `
                          -Help "Dernière opération lancée depuis cette carte : elle a abouti." `
                          -Guide ("Durée : " + $elapsedMs +
                                  $(if ($r.log) { [Environment]::NewLine + "Journal : " + $r.log } else { '' })))
    }
    <#
        THE VALUE SAYS THE STATE, THE DETAIL TELLS THE STORY.

        It used to carry everything: "ECHEC le 31/08/2026 10:56 -- Une installation est deja
        en cours (fhaza, processus 44940, depuis 10:49:18)". In a card's right-hand column
        that ran to three lines and pushed the rest away, while the neighbouring lines answer
        in one word. A value is what one reads at a glance.

        So "Echec" stays on the right -- in red, nothing need be added to see it -- and WHEN,
        WHY, HOW LONG and WHERE TO READ go into the line's detail, which exists for that.
    #>
    $detail = if ($r.error) { "$($r.error)" } else { "code de sortie " + [int]$r.code }
    return (New-Field -Key $Key -Label "$($r.label)" -Value 'Échec' `
                      -Kind 'text' -Status 'error' `
                      -Help "La dernière opération lancée depuis cette carte a échoué. Elle n'a pas abouti : rien ne s'est fait à moitié sans le dire." `
                      -Guide ("Le " + $when + " — " + $detail + [Environment]::NewLine +
                              "Durée : " + $elapsedMs +
                              $(if ($r.log) { [Environment]::NewLine + "Journal complet : " + $r.log } else { '' })))
}

# --- WHICH Windows ACCOUNTS have Vigie (D65) ----------------------------------
# The computer has several accounts; the user chooses which ones have Vigie, and may change
# their mind at any time (the requirement: "a tool must always allow changing which account
# has access").
#
# Enabling an account means laying down ITS startup scheduled task. Nothing else: the
# settings are already per account (the %LOCALAPPDATA% layer), and the runtime data follow
# the account as soon as the installation is not writable (Get-VarRoot).
#
# The run level follows the ACCOUNT, not our wishes: `Highest` for an administrator,
# `Limited` for a standard account. Giving Highest to a standard account would not work --
# and MUST not: Vigie gives nothing more than Windows does.
$script:VigieTaskPrefix = 'Vigie - '

# WHICH pwsh can ANOTHER account launch?
#
# An expensive trap, seen on 26/08: the task for "Famille" was created with
# (Get-Command pwsh).Source, which here is
# C:\Users\fhaza\AppData\Local\Microsoft\WindowsApps\pwsh.exe -- a path inside THE
# ADMINISTRATOR'S PROFILE. No other account can read that, and the Store alias points in any
# case to an MSIX package registered for the one account that installed it. So the task was
# created without an error... and never launched anything for Famille: Vigie did not start,
# with not one message.
#
# Only a MACHINE installation -- the MSI, under Program Files -- will do. It is looked for,
# and when it is missing we REFUSE to enable the account, saying what to do, rather than
# laying a task that will fail silently at every logon.
# HOW PowerShell 7 is installed for the machine. A SINGLE definition (D15): the installation
# script and the Accounts card's button run exactly the same thing.
# `--scope machine` is the essential point: without it, winget lays the MSIX package in the
# profile of whoever installs, and the other accounts cannot launch it.
function Get-SharedPwshInstallArgs {
    # --installer-type msi: WITHOUT it, winget chooses the MSIX package and tries to
    # "provision" it for every account -- an operation that fails on this machine with
    # 0x80070005 (winget's log of 26/08: ProvisionPackageOperation). And the MSI is precisely
    # what we want: it lays pwsh.exe in C:\Program Files\PowerShell\7, a real path every
    # session can launch, with no per-account registration. The MSIX, even provisioned,
    # remains a per-user package.
    @('install', '--id', 'Microsoft.PowerShell', '-e', '--scope', 'machine',
      '--installer-type', 'msi',
      '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements',
      '--silent', '--disable-interactivity')
}

function Get-SharedPwshPath {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($r in $roots) {
        $d = Join-Path $r 'PowerShell'
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $trouves = @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending |
                     ForEach-Object { Join-Path $_.FullName 'pwsh.exe' } |
                     Where-Object { Test-Path -LiteralPath $_ })
        if ($trouves.Count) { return $trouves[0] }
    }
    return $null
}


# The administrators group by its SID: the name depends on the language of Windows
# ("Administrateurs" here, "Administrators" elsewhere) -- the SID does not.
function Test-LocalAccountIsAdmin {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $grp = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
        $membres = @(Get-LocalGroupMember -Group $grp.Name -ErrorAction Stop)
        return [bool](@($membres | Where-Object { "$($_.Name)" -like "*\$Name" }).Count -gt 0)
    } catch { return $false }
}

# A task's principal is written "MACHINE\account" or "account", depending on the tool that
# created it. We compare the ACCOUNT NAME, with no regular expression: escaping the backslash
# is a nest of mistakes -- a badly escaped regex made the whole account inventory fail,
# silently, on every account of the machine.
function Test-TaskUserIs {
    param([string]$UserId, [Parameter(Mandatory)][string]$Name)
    if (-not $UserId) { return $false }
    # [char]92 is the backslash, built rather than written: the successive layers of writing
    # eat the escapes (seen several times that day).
    $court = @(("$UserId").Split([char]92))[-1]
    return ($court -eq $Name)
}

# IS THE INSTALLATION SHARED? In other words: can another account of the machine so much as
# READ the application?
#
# The question is not theoretical: on a development workstation, or a clone of the
# repository, Vigie lives in somebody's personal space, and offering to enable it for another
# account would mean offering a task that fails silently at every logon (raised by the
# owner). So the REAL rights are looked at, and nothing is assumed.
#
# The groups whose read access makes the installation reachable by everyone:
#   S-1-5-32-545 Users | S-1-1-0 Everyone | S-1-5-11 Authenticated Users
function Test-InstallationPartagee {
    param([string]$Path = (Get-RepoRoot))
    $sids = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        foreach ($ace in $acl.Access) {
            if ("$($ace.AccessControlType)" -ne 'Allow') { continue }
            $sid = $null
            try { $sid = "$($ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value)" } catch { }
            if (-not $sid -or $sids -notcontains $sid) { continue }
            if (("$($ace.FileSystemRights)" -match 'Read|ReadAndExecute|Modify|FullControl')) { return $true }
        }
    } catch { }
    return $false
}

# WHERE is the SHARED installation, the one every account can read?
#
# On a development workstation Vigie runs from the repository, which the others cannot read;
# a deployed copy may exist beside it. An account's startup task must point at THAT ONE, or
# it fails silently at every logon -- which is exactly the trap that was raised: the
# deployment had been done, but the task would have aimed at the personal repository.
<#
    WHERE THE SHARED INSTALLATION LIVES.

    THE CHOSEN FOLDER IS DECLARED, because nothing else could find it. Program Files is
    guessable; "D:\Outils\Vigie" is not -- and an installation nobody can locate cannot be
    updated, diagnosed, nor uninstalled. So the setup writes the path it used under
    HKLM\SOFTWARE\Sowapps\Vigie, and this function reads it FIRST.

    The declaration is never believed on its word: the marker file must be there. A folder
    moved or deleted by hand would otherwise be announced as an installation forever.
#>
function Get-InstallPathDeclarationKey { 'HKLM:\SOFTWARE\Sowapps\Vigie' }

<#
    THE IDENTITY THE NOTIFICATIONS ARE SENT UNDER.

    A toast carries the name of the application that raised it, not the title we wrote.
    Ours is pwsh.exe, so every bubble said "PowerShell" (reported 07/09, subject S11).
    Windows reads that name from a declared identity, so we declare one.

    MACHINE-WIDE, AND ON PURPOSE. HKLM\SOFTWARE\Classes shows through HKEY_CLASSES_ROOT
    for every account, so ONE key serves every session -- and the uninstall has ONE key to
    remove. Writing it per account would mean going into the registry hive of people who
    are not logged in, on the very day we are removing Vigie.
#>
function Get-VigieToastIdentity { 'Sowapps.Vigie' }

function Get-VigieToastIdentityKey {
    'HKLM:\SOFTWARE\Classes\AppUserModelId\' + (Get-VigieToastIdentity)
}

<#
    IT IS THE SERVER APP THAT KEEPS IT TRUE, not the installer alone.

    Declaring it only from install.ps1 looked right and was not: an update runs the
    installer of the version ALREADY in place, so the very first machine to receive this
    declaration would have run an installer that knew nothing about it -- measured on 07/09,
    the key was still missing after deploying the code that writes it. Anything that only
    happens at install time reaches every machine except the ones already running.

    So the elevated server app checks it at every pass. It reads first and writes only when
    something is missing or has moved: an installation that changed folder re-declares its
    icon by itself.
#>
function Test-VigieToastIdentityDeclared {
    param([string]$InstallPath)
    try {
        $key = Get-VigieToastIdentityKey
        if (-not (Test-Path -LiteralPath $key)) { return $false }
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        if ("$($p.DisplayName)" -ne 'Vigie') { return $false }
        if ($InstallPath) {
            $ico = Join-Path (Join-Path (Join-Path (Join-Path $InstallPath 'apps') 'client') 'assets') 'ok.ico'
            if ((Test-Path -LiteralPath $ico) -and "$($p.IconUri)" -ne $ico) { return $false }
        }
        return $true
    } catch { return $false }
}

function Set-VigieToastIdentity {
    param([string]$InstallPath)
    if (Test-VigieToastIdentityDeclared -InstallPath $InstallPath) { return $true }
    $key = Get-VigieToastIdentityKey
    try {
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name 'DisplayName' -Value 'Vigie' -PropertyType String -Force | Out-Null
        # THE ICON IS THE DELIVERED ONE, and it is only declared when it is actually THERE:
        # an IconUri pointing at nothing gives a notification with no image, which is worse
        # than declaring none at all.
        if ($InstallPath) {
            $ico = Join-Path (Join-Path (Join-Path (Join-Path $InstallPath 'apps') 'client') 'assets') 'ok.ico'
            if (Test-Path -LiteralPath $ico) {
                New-ItemProperty -Path $key -Name 'IconUri' -Value $ico -PropertyType String -Force | Out-Null
            }
        }
        return $true
    } catch { return $false }
}

function Remove-VigieToastIdentity {
    $key = Get-VigieToastIdentityKey
    try {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop }
        return $true
    } catch { return $false }
}

<#
    EVERYTHING THAT GOES WRONG WITH WINDOWS UPDATE, IN ONE PLACE.

    The card showed a number and nothing else. On 18/09, 15 updates were requested and 14 became "not found at install
    time": only a Lenovo driver was installed, and the card still read "installation réussie". A few days earlier it
    announced 46 to 48 updates where an online search found 4, and nothing recorded either figure, so neither could be
    checked afterwards. The owner asked on 20/09 that the card report every problem, one way or another.

    Every reading here is cheap: the update history is read in 35 ms, the System log through its own filter.
    Nothing is installed, nothing is hidden, nothing is repaired: the card says, the user decides.
#>
function Get-WindowsUpdateAilments {
    param(
        [string]$Backend = (Get-BackendRoot),
        # The local count the card shows, the last online scan, and the last installation run, as the probe knows them.
        [int]$LocalCount = -1,
        $Scan,
        $Install
    )
    $found = @()

    # --- What the history says: an update installed again and again, and the failures ---------
    $history = @()
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $total = $searcher.GetTotalHistoryCount()
        if ($total -gt 0) { $history = @($searcher.QueryHistory(0, [math]::Min(120, $total))) }
    } catch { }
    $recent = @($history | Where-Object { $_.Date -and $_.Date -gt (Get-Date).AddDays(-7) })
    foreach ($group in @($recent | Where-Object { $_.ResultCode -eq 2 } | Group-Object Title | Where-Object { $_.Count -ge 3 })) {
        $last = @($group.Group | Sort-Object Date -Descending)[0]
        $found += [pscustomobject]@{
            Status = 'warn'
            Label  = 'Mise à jour réinstallée en boucle'
            Detail = "$($group.Name) — installée avec succès $($group.Count) fois en sept jours, la dernière le " +
                     $last.Date.ToLocalTime().ToString('dd/MM à HH:mm') + ". Windows la repropose sans cesse : la réinstaller ne change rien."
        }
    }
    foreach ($entry in @($recent | Where-Object { $_.ResultCode -in 4, 5 })) {
        $code = ''
        try { $code = '0x{0:X8}' -f $entry.HResult } catch { }
        $found += [pscustomobject]@{
            Status = 'error'
            Label  = $(if ($entry.ResultCode -eq 5) { 'Installation annulée' } else { 'Installation en échec' })
            Detail = "$($entry.Title) — le " + $entry.Date.ToLocalTime().ToString('dd/MM à HH:mm') + $(if ($code) { ", code $code" } else { '' }) + '.'
        }
    }

    # --- What the last installation run left behind -------------------------------------------
    if ($Install -and "$($Install.phase)" -eq 'termine') {
        # @($null) IS AN ARRAY OF ONE: an installation run from before these identifiers were kept counted one missing
        # update that never existed, and the card went red for it (20/09).
        $missing = @()
        try { $missing = @($Install.introuvables | Where-Object { $_ }) } catch { }
        if ($missing.Count) {
            $found += [pscustomobject]@{
                Status = 'error'
                Label  = "Mises à jour disparues au moment d'installer"
                Detail = $(if ($missing.Count -eq 1) { "Une mise à jour demandée n'était plus servie" } else { "$($missing.Count) mises à jour demandées n'étaient plus servies" }) +
                         " par Windows quand l'installation a commencé : elles venaient du cache local, qui les gardait alors que Windows ne les propose plus. " +
                         "Une recherche en ligne remet la liste à jour."
            }
        }
    }

    # --- The local cache against the last online search ----------------------------------------
    if ($Scan -and $null -ne $Scan.trouvees -and $LocalCount -ge 0) {
        $online = [int]$Scan.trouvees
        $age = $null
        try { $age = ([datetime]::UtcNow - (ConvertTo-UtcDate $Scan.at)).TotalDays } catch { }
        if ([math]::Abs($LocalCount - $online) -ge 2) {
            $found += [pscustomobject]@{
                Status = 'warn'
                Label  = "Le cache local et l'analyse en ligne ne disent pas la même chose"
                Detail = "Le cache local de Windows en annonce $LocalCount, la dernière analyse en ligne en a trouvé $online" +
                         $(if ($null -ne $age) { ', il y a ' + [math]::Round($age) + ' jour(s)' } else { '' }) +
                         ". C'est l'analyse en ligne qui fait foi : « Recherche en ligne » remet le compte au clair."
            }
        }
    }

    # --- What Windows itself logged about its updates -------------------------------------------
    $logged = @()
    try {
        $logged = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
                                                     Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop)
    } catch { }
    if ($logged.Count) {
        $last = @($logged | Sort-Object TimeCreated -Descending)[0]
        $message = ''
        try { $message = (("$($last.Message)" -replace '\s+', ' ').Trim()) } catch { }
        if ($message.Length -gt 180) { $message = $message.Substring(0, 179) + '…' }
        <#
            THIS ONE COMES FROM THE LOG, so it obeys D127. Nothing here can check whether those failures still stand,
            so it is judged on its age -- and being declassed does NOT remove it: the line stays, and says how often
            it came back. Three failures in seven days is a state; one from a week ago is not.
        #>
        $verdict = Get-JournalFactVerdict -LastAt $last.TimeCreated -Count $logged.Count -WindowDays 7 -Still 'inconnu' -Level 'warn' `
                                          -HighlightMinutes $(try { [int](Get-ModuleSetting -Unit 'system' -Key 'EventHighlightMinutes' -Backend $Backend) } catch { 60 })
        $found += [pscustomobject]@{
            Status = $verdict.Weight
            Label  = 'Erreurs de Windows Update dans le journal Système'
            Detail = $verdict.Said + ' — ' + $verdict.Recurrence + ' (' + $last.TimeCreated.ToString('dd/MM à HH:mm') + ") : $message"
        }
    }

    <#
        AND WHAT BLOCKS IT, NAMED -- asked for on 30/09, and asked for once before that.

        "Installation en échec, 0x80073D02" tells nobody anything. Windows itself knows the answer and writes it in
        its own deployment log: the update of a Store package cannot be applied while a process is holding it, and
        event 419 NAMES the package that must be closed. Read on this computer on 29/09: Phone Link was being updated
        from 1.26072.255.0 while that very version was running.

        Event 493 is the other half: the deployment service still cannot delete some files of an old package, and it
        retries -- 376 times in seven days here, every six minutes, restarts included. That one does not resolve
        itself, so it is said too, with its rate, rather than left as background noise in a log nobody opens.

        The whole reading is one targeted query, 255 ms measured, and this card is computed every six hours.
    #>
    $deployment = @()
    $deploymentUnreadable = $null
    try {
        $deployment = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'
                                                         Id = 419, 493; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop)
    } catch {
        # "NO EVENT FOUND" IS NOT A FAILURE; anything else is -- and what cannot look says so. Silence here would
        # have read as "nothing is blocking", when in truth nobody had been able to look.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { $deploymentUnreadable = $_.Exception.Message }
    }
    if ($deploymentUnreadable) {
        $found += [pscustomobject]@{
            Status = 'warn'
            Label  = "Journal de déploiement des paquets illisible"
            Detail = "Vigie n'a pas pu lire « Microsoft-Windows-AppXDeploymentServer/Operational », qui nomme " +
                     "l'application à fermer quand une mise à jour est bloquée : $deploymentUnreadable"
        }
    }
    $highlight = try { [int](Get-ModuleSetting -Unit 'system' -Key 'EventHighlightMinutes' -Backend $Backend) } catch { 60 }

    $blocked = @($deployment | Where-Object { $_.Id -eq 419 })
    if ($blocked.Count) {
        $lastBlock = @($blocked | Sort-Object TimeCreated -Descending)[0]
        # THE PACKAGE FULL NAME IS IN THE MESSAGE. We keep the readable part: the name, without the version and the
        # publisher hash, which say nothing to whoever reads the card.
        $apps = @()
        foreach ($b in $blocked) {
            foreach ($m in [regex]::Matches("$($b.Message)", '([A-Za-z0-9\.]+)_[0-9\.]+_[a-z0-9]+__[a-z0-9]+')) {
                $name = $m.Groups[1].Value
                if ($apps -notcontains $name) { $apps += $name }
            }
        }
        <#
            AND WHOSE SESSION, because the answer differs. A package held open belongs to ONE account: the event
            carries its SID, and only the person signed in there can close the application. Saying "an open
            application blocks an update" without saying where sends everyone looking on their own desktop, including
            the three accounts that have nothing open. S02, the same shape as winget: a per-account fact reported as
            if it were a fact about the machine.
        #>
        $accounts = @()
        foreach ($b in $blocked) {
            if (-not $b.UserId) { continue }
            $who = "$($b.UserId)"
            try { $who = $b.UserId.Translate([System.Security.Principal.NTAccount]).Value } catch { }
            if ($who -and $accounts -notcontains $who) { $accounts += $who }
        }
        $verdict = Get-JournalFactVerdict -LastAt $lastBlock.TimeCreated -Count $blocked.Count -WindowDays 7 -Still 'inconnu' -Level 'warn' -HighlightMinutes $highlight
        $found += [pscustomobject]@{
            Status = $verdict.Weight
            Label  = 'Mise à jour bloquée par une application ouverte'
            Detail = $verdict.Said + ' — ' + $verdict.Recurrence + '. ' +
                     $(if ($accounts.Count -eq 1) { 'Sur le compte ' + $accounts[0] + '. ' }
                       elseif ($accounts.Count -gt 1) { 'Sur les comptes ' + ($accounts -join ', ') + '. ' }
                       else { "Windows n'a pas nommé le compte concerné. " }) +
                     $(if ($apps.Count) { 'Windows nomme ce qu''il faut fermer : ' + ($apps -join ', ') + '. ' } else { '' }) +
                     "Un paquet en cours d'utilisation ne peut pas être remplacé : la mise à jour s'applique à la " +
                     "fermeture de session ou au redémarrage, quand plus rien ne le tient."
        }
    }

    $stuck = @($deployment | Where-Object { $_.Id -eq 493 })
    if ($stuck.Count -ge 5) {
        $lastStuck = @($stuck | Sort-Object TimeCreated -Descending)[0]
        # THE RATE IS TAKEN OVER THE LAST DAY, not over the seven: the machine is off part of the week, and an average
        # spread over those gaps says one attempt every 24 minutes where the last two hours show one every six.
        $lastDay = @($stuck | Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-24) }).Count
        $verdict = Get-JournalFactVerdict -LastAt $lastStuck.TimeCreated -Count $stuck.Count -WindowDays 7 -Still 'inconnu' -Level 'warn' -HighlightMinutes $highlight
        <#
            AND WE GO AND LOOK, since the server app is the one that can. C:\Program Files\WindowsApps is closed to an
            ordinary session and open to it: naming the files, and whoever holds them, is exactly what Vigie is for
            here. The owner asked for it on 30/09: a card must offer a way forward, and more information to deal with
            the thing differently IS a way forward. Read only: the Restart Manager is asked WHO holds, never to act.
        #>
        $stuckFiles = @()
        $stuckHolders = @()
        $stuckUnreadable = $null
        try {
            # NO Test-Path GATE HERE. On this very folder it THROWS for an ordinary session -- the trap Test-PathSafe
            # exists for -- and under the default preference it answers "false", which reads as "the folder is empty".
            # The card would then have said the opposite of the truth. We read, and a refusal is said as a refusal.
            $deletedDir = Join-Path $env:ProgramFiles 'WindowsApps\Deleted'
            # BOUNDED: a card names what blocks, it does not inventory a folder. Twenty files is already more than
            # anyone reads, and the count above says how many there are.
            $stuckFiles = @(Get-ChildItem -LiteralPath $deletedDir -Recurse -File -Force -ErrorAction Stop |
                            Select-Object -First 20)
            if ($stuckFiles.Count) {
                $stuckHolders = Get-FileHolders -Path @($stuckFiles | ForEach-Object { $_.FullName })
            }
        } catch { $stuckUnreadable = $_.Exception.Message }

        $names = @($stuckFiles | ForEach-Object { $_.Name } | Select-Object -Unique -First 5)
        $who = if ($stuckUnreadable) { "Le dossier n'a pas pu être lu : $stuckUnreadable" }
               elseif (-not $stuckFiles.Count) { "Le dossier est vide : ce que Windows n'arrive pas à supprimer n'y est plus." }
               elseif ($null -eq $stuckHolders) { "Windows n'a pas voulu dire qui les tient." }
               elseif (@($stuckHolders).Count) {
                   'Tenus par : ' + ((@($stuckHolders | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" } | Select-Object -Unique)) -join ', ') + '.'
               } else { "Aucun processus ne les tient en ce moment : c'est la suppression elle-même qui échoue, pas un verrou." }
        $which = if ($names.Count) { ' Fichiers : ' + ($names -join ', ') + $(if ($stuckFiles.Count -ge 20) { ', et d''autres' } else { '' }) + '.' } else { '' }

        $found += [pscustomobject]@{
            Status = $verdict.Weight
            Label  = "Windows n'arrive pas à finir de supprimer un ancien paquet"
            Detail = $verdict.Said + ' — ' + $verdict.Recurrence +
                     $(if ($lastDay -ge 2) { ", soit une tentative toutes les " + [math]::Max(1, [int][math]::Round(1440 / $lastDay)) + " minutes depuis un jour" } else { '' }) +
                     ". Des fichiers d'un paquet désinstallé restent sous « C:\Program Files\WindowsApps\Deleted » " +
                     "et le service de déploiement réessaie sans fin." + $which + ' ' + $who
        }
    }

    return $found
}

<#
    THE PENDING UPDATE LIST, BUILT ONCE FOR EVERYONE.

    It was built TWICE, and the two copies drifted exactly as the discipline warns. The card
    counted the search's result minus the updates Windows re-offers after installing them;
    the dialog listed the search's result minus the superseded driver versions. Neither knew
    about the other, so the card announced 49 while the dialog offered 48 -- seen on screen
    on 11/09. Two numbers for one thing, and the owner had to work out which to believe.

    So the list is built here, once, and both read it. Whoever adds a third rule tomorrow
    adds it in one place, and the card cannot disagree with the dialog any more.

    WE DO NOT TOUCH HOW WINDOWS UPDATE WORKS. Everything here is about the list we SHOW; the
    selection still goes to Windows' own installer, which sequences and resolves what it has
    to.
#>
function Get-PendingUpdateList {
    param([string]$Backend = (Get-BackendRoot))

    $found = $null
    $lines = @()
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $searcher.Online = $false
        $found = $searcher.Search("IsInstalled=0 And IsHidden=0")
    } catch {
        return [pscustomobject]@{ ok = $false; all = @(); offered = @(); drivers = 0
                                  setAsideOlder = 0; alreadyDone = @() }
    }

    for ($i = 0; $i -lt $found.Updates.Count; $i++) {
        $u = $found.Updates.Item($i)
        # MaxDownloadSize is 0 once the update is already downloaded.
        $size = 0;      try { $size = [int64]$u.MaxDownloadSize } catch { }
        $driver = $false; try { $driver = ($u.Type -eq 2) } catch { }
        $kb = @();      try { foreach ($k in $u.KBArticleIDs) { $kb += "KB$k" } } catch { }
        $model = '';    try { if ($u.DriverModel) { $model = "$($u.DriverModel)" } } catch { }
        $class = '';    try { if ($u.DriverClass) { $class = "$($u.DriverClass)" } } catch { }
        $when = '';     try { if ($u.DriverVerDate) { $when = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch { }
        $provider = ''; try { if ($u.DriverProvider) { $provider = "$($u.DriverProvider)" } } catch { }
        $lines += [pscustomobject][ordered]@{
            id = "$($u.Identity.UpdateID)"; titre = "$($u.Title)"; kb = ($kb -join ', ')
            octets = $size; pilote = $driver; modele = $model; classe = $class; dateP = $when
            provider = $provider; telecharge = [bool]$u.IsDownloaded
            groupe = ''; libelle = ''; remplacee = $false; echec = ''; dejaFaite = $false
        }
    }

    # --- The group, once the list is complete (D118) ---------------------------------------
    $seenByKey = @{}
    foreach ($line in $lines) {
        if (-not $line.pilote -or -not "$($line.provider)".Trim()) { continue }
        $key = Get-VendorKey "$($line.provider)"
        if (-not $seenByKey.ContainsKey($key)) { $seenByKey[$key] = @() }
        $seenByKey[$key] += "$($line.provider)"
    }
    foreach ($line in $lines) {
        if (-not $line.pilote) { $line.groupe = 'Windows'; continue }
        $key = Get-VendorKey "$($line.provider)"
        $line.groupe = $(if ($key) { Get-VendorName -Key $key -Seen $seenByKey[$key] -Backend $Backend }
                         else { 'Pilotes sans constructeur déclaré' })
        if ("$($line.modele)".Trim()) { $line.libelle = "$($line.modele)" }
    }

    # --- What the last installation failed at, and what it succeeded at ---------------------
    $failed = @{}
    $installed = @()
    try {
        $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'wu-install.json'
        if (Test-PathSafe $file) {
            $last = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($last.echecs.PSObject.Properties)) { $failed[$entry.Name] = "$($entry.Value)" }
            if ($last.phase -eq 'termine' -and -not $last.error) {
                if ($last.detail) {
                    foreach ($d in @($last.detail)) { if (@($d).Count -ge 2 -and "$($d[1])" -match 'Install') { $installed += "$($d[0])" } }
                } elseif ($last.titres) { $installed = @($last.titres) }
            }
        }
    } catch { }
    foreach ($line in $lines) {
        if ($failed.ContainsKey("$($line.id)")) { $line.echec = $failed["$($line.id)"] }
        # RE-OFFERED: Windows says "installed successfully" then detects the SAME update
        # again -- the known loop of badly targeted OEM drivers. Reinstalling changes nothing.
        if ($installed -contains "$($line.titre)") { $line.dejaFaite = $true }
    }

    # --- Two versions of one driver: the newest is the one we keep -------------------------
    #
    # THE CLASS IS PART OF THE PAIR, and the dates must actually differ. "Intel(R) UHD
    # Graphics" appears twice on the SAME date, once as Display and once as Extension: two
    # components of one device, not two versions of one component.
    $byModel = @{}
    foreach ($line in $lines) {
        if (-not "$($line.modele)".Trim()) { continue }
        $key = "$($line.groupe)|$($line.modele)|$($line.classe)".ToLowerInvariant()
        if (-not $byModel.ContainsKey($key)) { $byModel[$key] = @() }
        $byModel[$key] += $line
    }
    foreach ($key in @($byModel.Keys)) {
        $family = @($byModel[$key])
        if ($family.Count -lt 2) { continue }
        $dates = @($family | ForEach-Object { "$($_.dateP)" } | Sort-Object -Unique)
        if ($dates.Count -lt 2) { continue }
        $newest = @($family | Sort-Object { "$($_.dateP)" } -Descending)[0]
        foreach ($line in $family) { if ("$($line.dateP)" -ne "$($newest.dateP)") { $line.remplacee = $true } }
    }

    # --- The order puts the two versions side by side inside their group -------------------
    $lines = @($lines | Sort-Object @{ Expression = { "$($_.groupe)" } },
                                    @{ Expression = { "$($_.modele)" } },
                                    @{ Expression = { "$($_.classe)" } },
                                    @{ Expression = { "$($_.dateP)" }; Descending = $true })

    # --- What we offer ----------------------------------------------------------------------
    $older = 0
    $offered = @()
    foreach ($line in $lines) {
        if ($line.dejaFaite) { continue }
        if (-not $line.remplacee) { $offered += $line; continue }
        $key = "$($line.groupe)|$($line.modele)|$($line.classe)".ToLowerInvariant()
        # When the newest one failed, the older one is the only way forward left.
        $newerFailed = @($lines | Where-Object {
            -not $_.remplacee -and "$($_.groupe)|$($_.modele)|$($_.classe)".ToLowerInvariant() -eq $key -and "$($_.echec)".Trim()
        }).Count -gt 0
        if ($newerFailed) { $offered += $line } else { $older++ }
    }

    [pscustomobject]@{
        ok = $true
        all = @($lines)
        offered = @($offered)
        drivers = @($lines | Where-Object { $_.pilote }).Count
        setAsideOlder = $older
        alreadyDone = @($lines | Where-Object { $_.dejaFaite } | ForEach-Object { "$($_.titre)" })
    }
}

<#
    THE MAKER'S NAME, WHEN THE MAKER SPELLS IT SEVERAL WAYS.

    Windows Update hands out the provider of each driver, and the same company writes
    itself as it pleases: "INTEL", "Intel Corporation" and "Intel(R) Corporation" were
    three separate piles for twenty-one updates on 10/09, out of sixteen spellings for
    twelve makers.

    TWO STAGES, AND THE ORDER MATTERS. First a mechanical fold, which knows nothing and
    cannot be wrong about a brand: upper case, decorations and punctuation dropped, then
    the legal-form suffixes at the END of the name only -- "Corp" inside a name stays.
    Only what survives that reaches the second stage, config/vendor-names.json, a written
    table for the case no text processing will ever solve: two genuinely different names
    for one maker (D118).

    The label shown is never a manufactured string: either the table's name, or a spelling
    actually seen -- mixed case preferred over shouting, then the most frequent.
#>
$script:VendorSuffixes = @('CORPORATION', 'CORP', 'INCORPORATED', 'INC', 'LIMITED', 'LTD',
                           'COMPANY', 'CO', 'GMBH', 'AG', 'AB', 'SA', 'BV', 'NV', 'LLC', 'PLC',
                           'TECHNOLOGY', 'TECHNOLOGIES', 'SEMICONDUCTOR', 'SEMICONDUCTORS',
                           'SYSTEMS', 'ELECTRONICS', 'SOFTWARE')

function Get-VendorKey {
    param([string]$Name)
    if (-not "$Name".Trim()) { return '' }
    $key = "$Name".ToUpperInvariant()
    $key = $key -replace '\((R|TM|C)\)', ' '
    $key = $key -replace '[^A-Z0-9]+', ' '
    $key = ($key -replace '\s+', ' ').Trim()
    # SUFFIXES STACK: "Co.,Ltd" carries two. We strip while there are any, and never empty
    # the name doing so -- "Technology Ltd" must stay TECHNOLOGY.
    $again = $true
    while ($again) {
        $again = $false
        foreach ($suffix in $script:VendorSuffixes) {
            $shorter = $key -replace ('\s+' + $suffix + '$'), ''
            if ($shorter -ne $key -and $shorter.Trim()) { $key = $shorter.Trim(); $again = $true }
        }
    }
    $key
}

function Get-VendorTable {
    param([string]$Backend = (Get-BackendRoot))
    if ($null -ne $script:VendorTable) { return $script:VendorTable }
    $script:VendorTable = @{}
    $file = Join-Path (Join-Path (Split-Path (Split-Path $Backend -Parent) -Parent) 'config') 'vendor-names.json'
    if (Test-PathSafe $file) {
        try {
            $read = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($read.noms.PSObject.Properties)) {
                # THE TABLE IS INDEXED BY THE FOLDED KEY, not by what is written. Whoever
                # keeps this file copies the name AS THEY SEE IT; folding it is the code's
                # job, exactly as it folds what comes from Windows. Hand-written "A-Volute"
                # matched nothing, the key being "A VOLUTE" (10/09).
                if ("$($entry.Value.nom)".Trim()) { $script:VendorTable[(Get-VendorKey $entry.Name)] = "$($entry.Value.nom)" }
            }
        } catch { }
    }
    $script:VendorTable
}

function Get-VendorName {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Key,
        [string[]]$Seen = @(),
        [string]$Backend = (Get-BackendRoot)
    )
    $table = Get-VendorTable -Backend $Backend
    if ($Key -and $table.ContainsKey($Key)) { return $table[$Key] }
    $candidates = @($Seen | Where-Object { "$_".Trim() })
    if (-not $candidates.Count) { return $Key }
    # A SPELLING ACTUALLY SEEN, never a manufactured string. "INTEL" is the most frequent
    # one here and it SHOUTS: at equal information, mixed case wins.
    $best = $candidates | Group-Object | ForEach-Object {
        [pscustomobject]@{
            Nom   = $_.Name
            Crie  = [bool]($_.Name -cmatch '^[^a-z]+$')
            Vues  = $_.Count
            Long  = $_.Name.Length
        }
    } | Sort-Object Crie, @{ Expression = 'Vues'; Descending = $true }, Long
    @($best)[0].Nom
}
<#
    THE NOTIFICATION DOOR -- conception : doc/progress/targeting/notifications.md.

    The client app describes an EVENT and never an display: a subject, a state, a text and
    a duration. Which tool shows it is decided here, at the moment of showing, among the
    files of apps/client/notify/ -- one per tool, ranked by their name, exactly as the game
    identification methods are (probes/gaming/identify/).

    Before this, ShowBalloonTip was called at five places. Changing tool meant rewriting
    five callers, and no tool works on every machine: the real API is unreachable from
    PowerShell 7 without going round, the recommended one lives in a SDK to install. The
    defect was not the tool chosen -- it was that there was no PLACE to change it.

    THE LAST RANK IS ALWAYS AVAILABLE, and that is what makes the rest safe: a tool can be
    added, removed or wrong without a notification ever being lost.
#>
function Get-VigieToastImage {
    param([Parameter(Mandatory)][string]$ClientRoot, [string]$State = 'ok')
    $name = switch ($State) { 'ok' { 'ok' } 'warn' { 'warn' } 'error' { 'error' } default { 'error' } }
    # THE PNG FIRST. Notification rendering picks a small frame out of a .ico and blows it
    # up -- the outline comes out as a staircase, seen on screen on 10/09. The .ico stays
    # as the answer of last resort: an installation from before the PNG must still notify.
    foreach ($extension in @('.png', '.ico')) {
        $path = Join-Path (Join-Path $ClientRoot 'assets') ($name + $extension)
        if (Test-PathSafe $path) { return $path }
    }
    return $null
}

<#
    THE LABEL THAT MAKES A NOTIFICATION REPLACE THE PREVIOUS ONE.

    Seen on screen on 10/09: four notifications about the SAME subject stacked up in the
    action centre instead of superseding one another. Windows only replaces a notification
    by another carrying the same tag, and mine carried none.

    The tag is the subject's reference -- "gaming.hogs" -- so a field going back to normal
    replaces its own alert instead of sitting next to it. Two contradictory lines about one
    subject is worse than no line at all.

    Windows caps a tag at 64 characters and refuses some of them; we keep what is plainly
    safe and cut. A subject with no reference gets none, and stacks -- which is the old
    behaviour, not a new defect.
#>
function Get-VigieToastTag {
    param([string]$Key)
    if (-not "$Key".Trim()) { return '' }
    $tag = ("$Key" -replace '[^A-Za-z0-9._-]', '-')
    if ($tag.Length -gt 64) { $tag = $tag.Substring(0, 64) }
    $tag
}

function Get-VigieToastXml {
    param(
        # AN EMPTY SUBJECT IS A CASE, NOT AN ERROR. Refused by the binder, it would throw
        # inside a tool, the door would read that as a decline and try the next rank -- one
        # by one, down to the balloon, for something we can answer in one line.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Subject,
        [string]$Body = '',
        [string]$Image,
        # WHAT A CLICK OPENS. Windows ignores a click on a toast that names no target, and the only target a script
        # can offer is a protocol -- "vigie://panel", declared by the client app for its account (28/09).
        [string]$Launch,
        [switch]$Long
    )
    if (-not $Subject) { return $null }
    # ESCAPED, ALWAYS. An application named "AT&T" or a title carrying an angle bracket
    # would otherwise produce a document that does not parse, and a lost notification.
    $xml = '<toast'
    if ($Launch) { $xml += ' activationType="protocol" launch="' + [System.Security.SecurityElement]::Escape($Launch) + '"' }
    if ($Long) { $xml += ' duration="long"' }
    $xml += '><visual><binding template="ToastGeneric">'
    $xml += '<text>' + [System.Security.SecurityElement]::Escape($Subject) + '</text>'
    if ($Body) { $xml += '<text>' + [System.Security.SecurityElement]::Escape($Body) + '</text>' }
    if ($Image -and (Test-PathSafe $Image)) {
        $uri = 'file:///' + "$Image".Replace([char]92, '/')
        $xml += '<image placement="appLogoOverride" src="' + [System.Security.SecurityElement]::Escape($uri) + '"/>'
    }
    $xml + '</binding></visual></toast>'
}

function Show-VigieNotification {
    param(
        [Parameter(Mandatory)]$Notification,
        [Parameter(Mandatory)]$Context
    )
    $folder = Join-Path $Context.ClientRoot 'notify'
    foreach ($tool in @(Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $shown = $false
        try { $shown = [bool](@(& $tool.FullName -Notification $Notification -Context $Context) | Select-Object -Last 1) } catch { $shown = $false }
        if ($shown) { return $tool.BaseName }
    }
    return $null
}

function Get-SharedInstallPath {
    $declared = $null
    try {
        $key = Get-InstallPathDeclarationKey
        if (Test-Path -LiteralPath $key) {
            $declared = "$((Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).InstallPath)"
        }
    } catch { }
    if ($declared) {
        $marqueurDeclare = Join-Path (Join-Path (Join-Path $declared 'apps') 'client') 'client.ps1'
        if (Test-Path -LiteralPath $marqueurDeclare -ErrorAction SilentlyContinue) { return $declared }
    }
    # Program Files is readable by every account BY CONSTRUCTION: an installation sitting
    # there is shared, with no need to question the ACLs. Reading the rights is kept for
    # locations outside Program Files, which the user chose.
    # The previous version relied on Get-Acl alone and answered "not shared" from the server
    # while the deployment had been done -- a hard thing to diagnose.
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($b in $bases) {
        foreach ($name in @((Join-Path 'Sowapps' 'Vigie'), 'Vigie')) {
            $c = Join-Path $b $name
            # A path built by Join-Path: a literal backslash has already been eaten by my
            # writing tools and turned into tabs (seen on this very file).
            $marqueur = Join-Path (Join-Path (Join-Path $c 'apps') 'client') 'client.ps1'
            if (Test-Path -LiteralPath $marqueur) { return $c }
        }
    }
    # An installation outside Program Files: the ACL decides.
    if (Test-InstallationPartagee) { return (Get-RepoRoot) }
    return $null
}

<#
    WHAT THE PRODUCT OWNS AT THE ROOT OF ITS FOLDER.

    Installed in Program Files, Vigie is alone and the folder is hers: it goes whole. Chosen
    elsewhere -- "D:\Outils\Vigie", or worse "D:\Outils" passed as an argument -- the folder
    may hold someone else's things, and deleting it whole would carry them away.

    So this list says what is OURS. It is the top level of the published archive, plus what
    running produces: var/ (data), dist/ and logs/ (working files). Anything else in that
    folder belongs to somebody, and stays.
#>
function Get-InstallOwnEntries {
    @('apps', 'config', 'doc', 'lang', 'notes', 'scripts', 'var', 'dist', 'logs',
      'setup.cmd', 'uninstall.cmd', 'CHANGELOG.md', 'CLAUDE.md', 'LICENSE', 'README.md', 'README.fr.md')
}

<#
    DECLARING THE INSTALL FOLDER, at the scale of the computer.

    Written by the setup, read by everyone, removed by the uninstall. One value, and it
    answers one question -- "where is Vigie?". Nothing else lives there.
#>
function Set-InstallPathDeclaration {
    param([Parameter(Mandatory)][string]$Path)
    $key = Get-InstallPathDeclarationKey
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name 'InstallPath' -Value $Path -PropertyType String -Force | Out-Null
}
# What is WRONG, in plain words, ready to be displayed. $null when all is well.
# TWO NATURES OF FAULT, and only one of them repairs.
#
#   STRUCTURE: the interpreter, the path, whether it is enabled. That is corrected at once.
#   HISTORY  : the task never ran, or its last launch failed. No rewriting erases that --
#              only its next run will say.
#
# Confusing the two led to rewriting a perfectly healthy task, then announcing the same
# fault again: "rewritten, but: <exactly what we had just read>" (seen on 28/08).
# WRITING A PROPERTY THAT MAY NOT EXIST YET.
#
# An object returned by ConvertFrom-Json has a FIXED shape: its properties are the JSON's,
# and assigning another one THROWS. When that JSON is a cache written by an earlier version
# of the product, any code adding a field breaks silently -- and the stale value stays on
# screen. That is what announced "1 tache hors service" for a healthy task (28/08): the
# previous day's cache had the last word.
#
# To be used whenever writing into an object that MAY come from a cache or from an API.
function Set-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if (-not $Object) { return }
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $null -Force
    }
    $Object.$Name = $Value
}

# CAN AN ACCOUNT READ THIS FILE? The question is not theoretical: "Famille" has every right
# on C:\EspaceRestreint and Workspaces, and NONE from Git\ onwards. Its task therefore
# launched a script it could not open, and PowerShell returned 64 -- "cannot open the file"
# -- with not one log line (seen on 28/08).
#
# WE DO NOT WALK UP THE PATH. Windows grants users the "bypass traverse checking" privilege
# by default: crossing a folder requires no right on it, and only the rights of the target
# file count. Walking up each level added verdicts that varied with who asked -- an elevated
# session read ACLs an ordinary session could not, and the two did not answer alike.
function Test-PathReadableByAccount {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sid,
        # Does the account belong to the administrators? Without that precision, a right
        # granted to administrators would be taken for a right granted to everyone.
        [switch]$IsAdmin
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $acl = $null
    try { $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop } catch { return $true }   # on ne conclut pas d'une ACL illisible

    # The groups that contain any ORDINARY local account. "Administrators" is not one of
    # them: counting it made us say Famille could read a folder reserved to fhaza, to the
    # administrators and to SYSTEM -- the guard was wrong in exactly the same way as the code
    # it was meant to protect.
    $universal = @('S-1-1-0', 'S-1-5-32-545', 'S-1-5-11')
    if ($IsAdmin) { $universal += 'S-1-5-32-544' }

    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        if (-not ($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read)) { continue }
        $ruleSid = try { $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { '' }
        if ($ruleSid -eq $Sid -or $universal -contains $ruleSid) { return $true }
    }
    return $false
}

<#
    IS THAT TASK REALLY RUNNING?

    A scheduled task killed by a shutdown can stay in state Running with no process left.
    Declared MultipleInstances=IgnoreNew, it then IGNORES every logon trigger: the account
    never gets Vigie again, and rebooting does not clear it. Measured on 04/09 -- « Vigie -
    Famille » still Running at 22:15, last run 18:38, no process, no icon on that session.

    So we do not believe the state: we look for the process the task launches, owned by the
    account the task runs as. No process, no run.
#>
function Test-VigieTaskProcessAlive {
    param([Parameter(Mandatory)]$Task)
    $action = @($Task.Actions)[0]
    $file = $null
    if ("$($action.Arguments)" -match '-File\s+"([^"]+)"') { $file = $Matches[1] }
    if (-not $file) { return $true }   # rien a comparer : on ne conclut pas
    $wanted = (Split-Path $file -Leaf)
    $owner = ("$($Task.Principal.UserId)" -split [regex]::Escape([string][char]92))[-1]
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue)) {
        if ("$($p.CommandLine)" -notlike ('*' + $wanted + '*')) { continue }
        $who = $null
        try { $who = "$((Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop).User)" } catch { }
        # NO READABLE OWNER, NO VERDICT: a process we can see without knowing whose it is
        # remains a reason to stay silent.
        if (-not $who -or $who -eq $owner) { return $true }
    }
    return $false
}

<#
    THE LEGACY NAME IS NORMALISED, AND IT DOES NOT WAIT FOR A BREAKDOWN.

    D117 gave everybody one scheme, "Vigie - <account>". But the rename rode on the repair
    path, and the repair path skips a healthy task -- so the one machine that carried the
    old name kept it for ever. Measured on 06/09, right after deploying D117: Famille was
    correctly named, fhaza's task was still plain "Vigie", because nothing was wrong with
    it. A convention that only applies to broken things is not a convention.

    THE NEW ONE IS BORN BEFORE THE OLD ONE DIES, always: Set-VigieAccountEnabled rebuilds
    the task under the new name, we CHECK it exists, and only then does the old one go. A
    failure in between leaves the account with two tasks -- never with none.

    Returns the new name when the rename happened, $null when it did not (and the caller
    then keeps working with the task it has).
#>
function Rename-VigieLegacyTask {
    param(
        [Parameter(Mandatory)][string]$Account,
        [string]$Backend = (Get-BackendRoot)
    )
    $newName = Get-VigieAccountTaskName -Name $Account
    if ($newName -eq 'Vigie') { return $null }   # ceinture : jamais se renommer en soi-meme
    try {
        $null = Set-VigieAccountEnabled -Name $Account -Enabled $true -Backend $Backend
        if (-not (Get-ScheduledTask -TaskName $newName -ErrorAction SilentlyContinue)) { return $null }
        Unregister-ScheduledTask -TaskName 'Vigie' -Confirm:$false -ErrorAction Stop
        return $newName
    } catch { return $null }
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

function Get-VigieTaskStructureAilment {
    param([Parameter(Mandatory)]$Task)
    $a = @($Task.Actions)[0]
    if (-not $a) { return "la tâche ne lance rien" }
    $exe = "$($a.Execute)".Trim('"')
    if (-not $exe) { return "aucun interpréteur" }
    <#
        THE INTERPRETER IS NOT ALWAYS WHAT THE TASK EXECUTES. Since 29/09 a client app is started through
        "conhost --headless <interpreter> ...", which is what keeps an empty terminal off the screen. The checks below
        are about the INTERPRETER -- a MSIX package, a path inside a profile -- so that is what must be read, wherever
        it sits. Reading conhost instead would have declared every one of those faults cured.
    #>
    if ((Split-Path $exe -Leaf) -ieq 'conhost.exe' -and "$($a.Arguments)" -match '--headless\s+"([^"]+)"') {
        $exe = $Matches[1]
    }
    if (-not (Test-Path -LiteralPath $exe)) { return "l'interpréteur n'existe plus : $exe" }
    # EXISTING IS NOT ENOUGH. Two paths look valid and are nonetheless unusable:
    #   - an MSIX package (C:\Program Files\WindowsApps\...) can only be launched by the
    #     accounts it is REGISTERED for, and its folder stays on disk after deregistration:
    #     Test-Path answers yes, the launch fails;
    #   - a path inside an account's profile (C:\Users\somebody\...) is unreadable by the
    #     others.
    # That is exactly what stopped Vigie starting for "Famille" (D79, D83).
    $profilesFolder = Join-Path $env:SystemDrive 'Users'
    $msixFolder    = Join-Path $env:ProgramFiles 'WindowsApps'
    if ($exe.StartsWith($msixFolder, [StringComparison]::OrdinalIgnoreCase)) {
        return "interpréteur MSIX, enregistré par compte : $exe"
    }
    if ($exe.StartsWith($profilesFolder, [StringComparison]::OrdinalIgnoreCase)) {
        return "interpréteur dans un profil, illisible par les autres comptes : $exe"
    }
    if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
        $launched = $Matches[1]
        if (-not (Test-Path -LiteralPath $launched)) { return ("l'application n'est plus là : " + $launched) }
        <#
            EXISTING IS NOT ENOUGH HERE EITHER: the task must launch THE client app of the current installation. On
            30/09 the folder was renamed, the old copy stayed behind, and the task went on naming it -- the file was
            still there, so nothing was declared broken, and the account ran two client apps at once, each with its
            own icon. A task that starts another application than the one installed cannot do its job.
        #>
        $expected = Join-Path (Join-Path (Get-RepoRoot) 'apps') (Join-Path 'client' 'client.ps1')
        if ((Test-Path -LiteralPath $expected) -and ($launched.Trim() -ine $expected)) {
            return ("la tâche lance une autre application que celle installée : " + $launched)
        }
    }
    <#
        A WINDOW NOBODY ASKED FOR IS NOT A BREAKDOWN, and saying it here was a mistake -- measured within the minute
        on 29/09: this function feeds the deployment card, which then announced, in red, that two accounts had no working
        client app -- about client apps that were running perfectly. A structural ailment says the task CANNOT work. An old launch
        line works; it merely shows a window, and that is repaired by rewriting the task at the next installation,
        not by alarming whoever reads the card.
    #>
    # DISABLED is structural: the task is there, well formed, and Windows refuses to launch
    # it. One gesture repairs it (Enable-ScheduledTask), so it belongs here and not to the
    # history.
    if ("$($Task.State)" -eq 'Disabled') { return "la tâche est désactivée dans Windows" }

    # STUCK IN "RUNNING": structural too, and one gesture repairs it (Stop-ScheduledTask).
    # While that state lasts, no logon starts anything -- the task is declared IgnoreNew.
    if ("$($Task.State)" -eq 'Running' -and -not (Test-VigieTaskProcessAlive -Task $Task)) {
        return "Windows la croit en cours alors que rien ne tourne : elle ne redémarrera plus"
    }

    # NO READABILITY VERDICT HERE, and that is a choice.
    #
    # This same check serves to CHOOSE a task's path (Set-VigieAccountEnabled) and proves
    # itself there: it did send "Famille" away from the repository, unreadable for
    # it, towards the shared installation. But when it JUDGES an existing task, it declared
    # unreadable a file that the same function, called from an ordinary session on the same
    # file and the same account, called readable.
    #
    # A diagnosis that contradicts itself depending on the observer diagnoses nothing -- and
    # showing "broken" on something that works is worse than staying silent (D105). Until
    # that gap is understood, the question is only asked at the moment a task is written,
    # where a mistake is corrected at once.

    # A TASK THAT LAUNCHES THE REPOSITORY is a structural fault: the working folder may be
    # unreadable to the account starting -- "Famille" has no right at all on
    # C:\EspaceRestreint, and neither has VigieService -- and it may move or disappear. The
    # task then starts nothing, without a word.
    #
    # It is NOT a matter of the declared environment: Vigie always runs from the shared
    # installation, development included. In dev it is the SOURCE of what is deployed there
    # that changes -- a branch rather than a published version -- and that reads in the
    # version number. Comparing the location with the declaration therefore reported a
    # permanent gap with nothing to repair (seen on 30/08).
    if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
        if ((Get-PathStage -Path $Matches[1]) -ne 'prod') {
            return "elle démarre depuis le dépôt de travail, pas depuis l'installation partagée"
        }
    }

    return $null
}

# What Get-VigieTaskHistoryAilment says of a task never launched: the cards tell it apart from a failed launch.
function Get-VigieTaskNeverRunText { "la tâche n'a jamais été exécutée" }

# The COMPLETE state: the structure first, then the history.
function Get-VigieTaskHistoryAilment {
    param([Parameter(Mandatory)]$Task)
    $a = @($Task.Actions)[0]
    if (-not $a) { return $null }
    # A TASK WHOSE CLIENT APP IS ALIVE HAS NOTHING LEFT TO CONFIRM. Its last result can be a start refused because
    # it was already running (0x800710E0 under IgnoreNew): on 13/09 an update started fhaza's running task, and the
    # card said "never started" of a client app in front of him. The process decides, not the state, which a
    # re-registration resets while the instance still runs.
    if (Test-VigieTaskProcessAlive -Task $Task) { return $null }
    # A TASK HEALTHY ON PAPER MAY NEVER HAVE RUN.
    #
    # Everything above examines the DEFINITION: the interpreter exists, the script exists.
    # That says nothing about what happened. So "Vigie activée" was displayed for an account
    # where Vigie had never started once -- seen on Famille on 28/08: the task present, the
    # session open, and no log anywhere.
    $info = $null
    try { $info = $Task | Get-ScheduledTaskInfo -ErrorAction Stop } catch { }
    if ($info) {
        # UNSIGNED, AND THAT IS THE WHOLE PROBLEM. Windows returns an HRESULT on 32 unsigned
        # bits: 0x800710E0 is 2 147 946 720, beyond Int32. The cast threw, and the whole
        # action failed on "Cannot convert value ... to type System.Int32" -- at the precise
        # moment one was trying to read why a task had failed.
        $code = [long]$info.LastTaskResult
        # The codes that are NOT failures: 0 success; 0x00041301 running; 0x00041302
        # termination requested; 0x00041303 never launched (handled just below).
        $benins = @(0, 267009, 267010, 267011)
        $jamais = (-not $info.LastRunTime) -or ($info.LastRunTime.Year -lt 2000) -or ($code -eq 267011)
        if ($jamais) { return (Get-VigieTaskNeverRunText) }
        if ($benins -notcontains $code) {
            # A FAILURE OLDER THAN THE INSTALLED CODE CONCERNS NOBODY ANY MORE.
            #
            # The "Famille" task had failed at 05:55; the fix was deployed at 08:44. Going on
            # showing it asked the user to "confirm" the failure of a program that no longer
            # exists -- while the deployment had happened by itself. So the failure's date is
            # compared with that of the file the task launches: if the application has changed
            # since, we say nothing.
            $since = $null
            if ("$($a.Arguments)" -match '-File\s+"([^"]+)"') {
                try { $since = (Get-Item -LiteralPath $Matches[1] -ErrorAction Stop).LastWriteTime } catch { }
            }
            if ($since -and $since -gt $info.LastRunTime) { return $null }
            return ("la dernière exécution a échoué (code 0x" + ([uint32]$code).ToString('X8') + ", le " +
                    $info.LastRunTime.ToString('dd/MM/yyyy HH:mm') + ")")
        }
    }
    return $null
}

function Get-VigieTaskAilment {
    param([Parameter(Mandatory)]$Task)
    $mal = Get-VigieTaskStructureAilment -Task $Task
    if ($mal) { return $mal }
    return (Get-VigieTaskHistoryAilment -Task $Task)
}

# Repairs what can be repaired, and REPORTS what it did. Silent when all is well. It never
# creates a missing task: enabling an account stays a decision.
function Repair-VigieTasks {
    param([string]$Backend = (Get-BackendRoot))
    $repairs = @()
    if (-not (Test-IsElevated)) { return $repairs }
    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { "$($_.TaskName)" -eq 'Vigie' -or "$($_.TaskName)".StartsWith($script:VigieTaskPrefix) })
    } catch { return $repairs }

    foreach ($t in $tasks) {
        $name = "$($t.TaskName)"
        # THE SERVER TASK IS NOT AN ACCOUNT'S: taken by its prefix, it was diagnosed as the task of an account named
        # after its suffix. Its maintenance is service-account-repair.
        if ($name -eq (Get-ServiceTaskName)) { continue }
        # WHOSE task is this? "Vigie - X" says it in its name; plain "Vigie" says it in its
        # PRINCIPAL -- we read that, rather than assume it belongs to whoever is looking.
        # The legacy task belongs to whoever installed it, not to the requester.
        $account = if ($name -eq 'Vigie') { ("$($t.Principal.UserId)" -split [regex]::Escape([string][char]92))[-1] }
                  else                  { $name.Substring($script:VigieTaskPrefix.Length) }

        # THE OLD NAME IS FIXED EVEN WHEN NOTHING IS WRONG, hence BEFORE the diagnosis: a
        # healthy task leaves this loop untouched, so the machine carrying "Vigie" would
        # have kept it for ever (measured on 06/09, right after D117 was deployed).
        if ($name -eq 'Vigie' -and $account) {
            $renamed = Rename-VigieLegacyTask -Account $account -Backend $Backend
            if ($renamed) {
                $repairs += [pscustomobject]@{ tache = $name; mal = "elle portait l'ancien nom"; repare = $true; attente = $false }
                try { $t = Get-ScheduledTask -TaskName $renamed -ErrorAction Stop } catch { continue }
                $name = $renamed
            }
        }

        # ON NE REECRIT PAS UNE TACHE SAINE. Un defaut d'HISTOIRE -- jamais lancee, ou
        # dernier lancement en echec -- ne se corrige par aucune ecriture : il se
        # confirmera au prochain demarrage du compte, et pas avant. Le signaler, oui ;
        # pretendre le reparer, non.
        $mal = Get-VigieTaskStructureAilment -Task $t
        if (-not $mal) {
            $histoire = Get-VigieTaskHistoryAilment -Task $t
            if ($histoire) {
                $repairs += [pscustomobject]@{ tache = $name; mal = $histoire; repare = $false; attente = $true }
            }
            continue
        }
        try {
            # UNBLOCK FIRST. A task Windows believes running refuses everything: we end it,
            # which returns its state to the truth, before rewriting it.
            if ("$($t.State)" -eq 'Running' -and -not (Test-VigieTaskProcessAlive -Task $t)) {
                try { Stop-ScheduledTask -TaskName $name -ErrorAction Stop } catch { }
            }
            if ($name -eq 'Vigie') {
                # Notre propre tache : on la reecrit avec l'interpreteur de la machine et
                # le chemin ou l'application se trouve REELLEMENT maintenant.
                $pwsh = Get-SharedPwshPath
                if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
                $client = Join-Path (Join-Path (Get-RepoRoot) 'apps') (Join-Path 'client' 'client.ps1')
                if (-not $pwsh -or -not (Test-Path -LiteralPath $client)) { continue }
                Set-ScheduledTask -TaskName $name -Action (New-VigieClientAction -Pwsh $pwsh -Client $client) -ErrorAction Stop | Out-Null
                # AND WE TRY THE RENAME AGAIN (D117). Reaching here means the pass at the top
                # of the loop failed -- the task answers again now that it has been rewritten,
                # so the attempt is worth making a second time.
                if ($account) {
                    $renamed = Rename-VigieLegacyTask -Account $account -Backend $Backend
                    if ($renamed) { $name = $renamed }
                }
            } else {
                # Tache d'un autre compte : Set-VigieAccountEnabled sait la refaire
                # entierement (interpreteur machine, installation partagee, niveau).
                $null = Set-VigieAccountEnabled -Name $account -Enabled $true -Backend $Backend
            }
            # UNE TACHE DESACTIVEE SE REACTIVE. Vigie savait le DIRE depuis ce matin, et
            # s'arretait la : elle reecrivait l'action puis reannoncait « desactivee »,
            # ce qui n'aide personne. Enable-ScheduledTask est le geste qui manquait.
            # Idempotent : une tache deja active ne bouge pas.
            try { Enable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null } catch { }

            # ON CONSTATE (D43). Reecrire la tache ne guerit pas tout : un ECHEC PASSE
            # reste inscrit dans son historique tant qu'elle n'a pas retourne au travail,
            # c'est-a-dire tant que ce compte n'a pas rouvert de session. Annoncer
            # « reparee » dans ce cas serait un faux succes -- et l'ecran continuerait a
            # afficher « hors service » juste a cote, en se contredisant (vu le 28/08).
            # ON RELIT APRES COUP, pas dans la foulee : Windows rend l'ancien etat pendant
            # un court instant apres une reecriture, et la tache paraissait encore
            # desactivee alors qu'elle ne l'etait deja plus (constate le 28/08).
            Start-Sleep -Milliseconds 400
            $after = $null
            try { $after = Get-VigieTaskAilment -Task (Get-ScheduledTask -TaskName $name -ErrorAction Stop) } catch { }
            if ($after) {
                $repairs += [pscustomobject]@{ tache = $name; mal = $mal; repare = $false; reste = $after }
                Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-reecrite-mais' $name $after)
            } else {
                $repairs += [pscustomobject]@{ tache = $name; mal = $mal; repare = $true }
                Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-reparee' $name $mal)
            }
        } catch {
            $repairs += [pscustomobject]@{ tache = $name; mal = $mal; repare = $false; erreur = "$($_.Exception.Message)" }
            Write-Log -Backend $Backend -Name 'comptes' -Level 'ERROR' `
                      -Message (Get-Label 'common.tache-non-reparee' $name $mal $_.Exception.Message)
        }
    }
    if ($repairs.Count) { Clear-ComputerAccountsCache -Backend $Backend }
    return $repairs
}

function Get-VigieAccountTaskName {
    param([Parameter(Mandatory)][string]$Name)
    $script:VigieTaskPrefix + $Name
}

# Les comptes de la machine, avec pour chacun : est-il administrateur, Vigie demarre-t-il
# avec lui, et par quelle tache. La tache historique s'appelle « Vigie » tout court : elle
# compte comme active pour le compte qu'elle vise, sinon l'ecran dirait faussement
# « inactif » a l'utilisateur qui s'en sert depuis le debut.
# L'inventaire coute environ deux secondes (comptes, groupes, profils, taches) et ne
# change qu'exceptionnellement : on le MEMORISE. Un jour de validite, un bouton pour
# forcer le releve, et toute activation de compte l'invalide d'elle-meme.
$script:AccountsTtlHours = 24

function Get-ComputerAccountsCachePath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'accounts.json'
}

function Clear-ComputerAccountsCache {
    param([string]$Backend = (Get-BackendRoot))
    $f = Get-ComputerAccountsCachePath -Backend $Backend
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

# L'ETAT DES TACHES SE RELIT, TOUJOURS.
#
# La liste des comptes est chere a etablir (profils, SID, registre) et change rarement :
# elle se met en cache 24 h. L'etat de leur tache de demarrage, lui, est bon marche a lire
# et peut changer a tout moment -- et s'il ment, il ment sur la seule chose qui compte.
# La carte a affiche « Vigie activee » pendant des heures pour un compte dont la tache
# avait disparu (28/08). Ces trois champs-la ne sont donc jamais servis depuis le cache.
function Update-AccountTasks {
    param([object[]]$Accounts)
    if (-not $Accounts -or -not $Accounts.Count) { return @($Accounts) }
    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { $_.TaskName -eq 'Vigie' -or $_.TaskName -like ($script:VigieTaskPrefix + '*') })
    } catch {
        # Sans elevation, Windows masque une partie des taches : on ne sait pas, et on ne
        # PRETEND pas savoir. Les valeurs du cache sont conservees telles quelles.
        return @($Accounts)
    }
    foreach ($c in $Accounts) {
        $name = "$($c.name)"
        $task = @($tasks | Where-Object {
            $_.TaskName -eq (Get-VigieAccountTaskName -Name $name) -or
            ($_.TaskName -eq 'Vigie' -and (Test-TaskUserIs -UserId "$($_.Principal.UserId)" -Name $name))
        })[0]
        # UN CACHE PEUT VENIR D'UNE VERSION PLUS ANCIENNE, et ses objets n'ont alors pas
        # les proprietes qu'on veut ecrire. Assigner une propriete absente LEVE, et la
        # valeur d'origine -- perimee -- restait affichee (constate le 28/08 : « 1 tache
        # hors service » pour une tache saine). On les cree si elles manquent.
        Set-ObjectProperty -Object $c -Name 'enabled' -Value ([bool]$task)
        Set-ObjectProperty -Object $c -Name 'task' -Value $(if ($task) { "$($task.TaskName)" } else { $null })
        # DEUX CHAMPS, deux natures : « taskAilment » est ce qui empeche la tache de
        # fonctionner ; « taskPending » est ce qui ne se saura qu'a son prochain
        # demarrage. Les confondre faisait annoncer « hors service » une tache saine.
        $mal = if ($task) { Get-VigieTaskStructureAilment -Task $task } else { $null }
        Set-ObjectProperty -Object $c -Name 'taskAilment' -Value $mal
        Set-ObjectProperty -Object $c -Name 'taskPending' `
            -Value $(if ($task -and -not $mal) { Get-VigieTaskHistoryAilment -Task $task } else { $null })
    }
    return @($Accounts)
}

<#
    CE QUI DEPEND DE QUI DEMANDE.

    « VOUS » et « ce compte n'est pas un compte technique » ne sont pas des faits sur le
    poste : ce sont des faits sur la RELATION entre le poste et la personne qui regarde.
    Ils se posent donc au moment de repondre, jamais dans le releve mis en cache -- sinon
    le premier a demander fixe la reponse de tous les autres.
#>
<#
    LES QUATRE CERCLES DE COMPTES -- ET CHACUN A SON NOM.

    Chaque appelant refiltrait a sa facon (« Where -not technical » recopie a sept
    endroits), et le seul qui ne l'a pas fait a depose un ordre de relance dans le dossier
    du compte de SERVICE : « Relance demandee aux autres comptes : Famille, fhaza,
    VigieService ». Personne ne devait jamais le lire.

      1. TOUS les comptes de l'ORDINATEUR  Get-ComputerAccounts  -- VigieService en est
      2. les comptes de PERSONNE           Get-UserAccounts      -- il n'en est pas
      3. ceux qui ont Vigie ACTIVEE        Get-EnabledAccounts   -- ils ont une app cliente
      4. ceux qui TOURNENT en ce moment    (tache + app cliente vivante)

    Le cercle 4 n'a pas de fonction : personne n'en a besoin. Une relance s'adresse au
    cercle 3 -- une app cliente eteinte demarrera de toute facon avec le nouveau code, et
    verifier son battement de coeur ajouterait un acces disque pour rien.
#>
# UN compte, par son nom. Recopie a trois endroits sous la forme « Get-ComputerAccounts |
# Where-Object { $_.name -eq X } », avec a chaque fois le meme piege : sans @(...) autour,
# un resultat unique n'est pas un tableau et l'index [0] rend un caractere.
function Get-AccountByName {
    param([Parameter(Mandatory)][string]$Name, [string]$Backend = (Get-BackendRoot))
    @(Get-ComputerAccounts -Backend $Backend | Where-Object { "$($_.name)" -eq $Name })[0]
}

function Get-UserAccounts {
    param([switch]$Force, [string]$Backend = (Get-BackendRoot))
    @(Get-ComputerAccounts -Force:$Force -Backend $Backend | Where-Object { -not $_.technical })
}

function Get-EnabledAccounts {
    param([string]$Backend = (Get-BackendRoot))
    @(Get-UserAccounts -Backend $Backend | Where-Object { $_.enabled })
}

function Get-UserRegistryRoots {
    <# Les ruches de registre des VRAIS utilisateurs connectes, sous la forme
       'Registry::HKEY_USERS\<SID>'.

       POURQUOI : le serveur tourne sous le compte de service, donc HKCU designe la ruche
       du service -- celle de personne. Une sonde qui lit un reglage par utilisateur
       (bibliotheques Steam, jeux reconnus par la Game Bar, preferences d'une appli) ne
       doit JAMAIS passer par HKCU : elle regarderait a cote et ne verrait rien. Constate
       le 01/09 : Assassin's Creed Odyssey joue sur le compte Famille n'etait pas reconnu
       comme jeu, la sonde interrogeant HKCU du service.

       On ecarte .DEFAULT, les vues _Classes et les comptes systeme (S-1-5-18/19/20). Une
       ruche non chargee (utilisateur deconnecte) n'apparait pas : c'est voulu, on ne
       monte pas les ruches des absents.
    #>
    $roots = @()
    try {
        # SilentlyContinue and not Stop: enumeration trips on protected hives while still
        # returning the others; stopping at the first would lose them all.
        foreach ($k in (Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue)) {
            $sid = Split-Path $k.Name -Leaf
            if ($sid -notmatch '^S-1-5-21-[\d-]+$') { continue }
            $roots += "Registry::HKEY_USERS\$sid"
        }
    } catch { }
    $roots
}

function Get-AccountRegistryRoot {
    <# La ruche de registre d'UN compte nomme, ou $null si elle n'est pas chargee.

       Une ruche n'est montee que pendant la session de son proprietaire : un compte
       deconnecte n'a rien a lire, et on ne monte pas la ruche des absents.
    #>
    param([Parameter(Mandatory)][string]$Account)
    try {
        $sid = (New-Object System.Security.Principal.NTAccount($Account)).Translate(
                   [System.Security.Principal.SecurityIdentifier]).Value
    } catch { return $null }
    $root = "Registry::HKEY_USERS\$sid"
    if (Test-Path -LiteralPath $root) { return $root }
    return $null
}

function Add-AccountsPerspective {
    param($Accounts)
    # Sans session, PERSONNE n'est « vous » : c'est plus vrai, et c'est plus sur que de
    # designer le compte du service.
    $requester = Get-RequesterAccount
    foreach ($c in @($Accounts)) {
        $isMe = [bool]$requester -and ("$($c.name)" -eq "$requester")
        $c | Add-Member -NotePropertyName current -NotePropertyValue $isMe -Force
        # Celui qui utilise Vigie en ce moment n'est jamais un compte d'outil.
        if ($isMe) { $c | Add-Member -NotePropertyName technical -NotePropertyValue $false -Force }
    }
    return $Accounts
}

<#
    LES COMPTES DE CET ORDINATEUR -- pas des « comptes Vigie ».

    La fonction s'appelait Get-VigieAccounts : elle ne rend rien qui appartienne a Vigie,
    elle rend les comptes que WINDOWS declare, avec pour chacun ce que Vigie en sait.
    Le nom faisait croire a une liste de comptes autorises, ce qui est le cercle 3.
#>
function Get-ComputerAccounts {
    param(
        [switch]$Force,                       # bouton « Actualiser la liste »
        [string]$Backend = (Get-BackendRoot)
    )
    $cache = Get-ComputerAccountsCachePath -Backend $Backend
    if (-not $Force -and (Test-Path -LiteralPath $cache)) {
        try {
            $j = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
            $age = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $j.at)).TotalHours
            if ($age -lt $script:AccountsTtlHours -and $j.users) {
                return (Add-AccountsPerspective (Update-AccountTasks -Accounts @($j.users)))
            }
        } catch { }
    }
    $liste = @(Get-ComputerAccountsFresh -Backend $Backend)
    try {
        $tmp = "$cache.tmp"
        (@{ at = (Get-Date).ToUniversalTime().ToString('s'); users = $liste } | ConvertTo-Json -Depth 6) |
            Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $cache -Force
    } catch { }
    # LA PERSPECTIVE APRES LE CACHE, jamais avant : ce qu'on ecrit sur le disque doit
    # rester vrai pour n'importe qui.
    return (Add-AccountsPerspective $liste)
}

# Le releve REEL, sans cache.
function Get-ComputerAccountsFresh {
    param([string]$Backend = (Get-BackendRoot))
    # PROFILS REELLEMENT UTILISES : c'est LE discriminant entre un compte de personne et un
    # compte d'outil. Win32_UserProfile.LastUseTime dit quand le profil a servi pour de bon
    # (ouverture de session). Le LastLogon du COMPTE, lui, ment : un compte de bac a sable
    # affichait « connecte aujourd'hui » sans avoir jamais ouvert de session -- signale par
    # l'utilisateur, verifie le 26/08 (LastUseTime vide, profil jamais charge).
    $profils = @{}
    try {
        foreach ($up in (Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special })) {
            $cle = "$($up.SID)"
            if ($cle) { $profils[$cle] = $up }
        }
    } catch { }

    # QUELS COMPTES SONT DES COMPTES DE PERSONNE ? Windows le dit lui-meme :
    # Winlogon\SpecialAccounts\UserList liste les comptes MASQUES de l'ecran de connexion
    # (valeur 0). C'est ainsi que les outils declarent leurs comptes de service.
    # Tous les criteres essayes avant etaient faux : le profil (les bacs a sable en ont
    # un), sa date d'usage (invisible hors elevation, d'ou deux verdicts contradictoires
    # entre l'agent et le serveur), son contenu (Desktop present quand meme),
    # l'appartenance au groupe Utilisateurs (ils en sont membres).
    $masquesConnexion = @{}
    try {
        $cleMasques = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if (Test-Path $cleMasques) {
            foreach ($pr in (Get-ItemProperty $cleMasques).PSObject.Properties) {
                if ($pr.Name -like 'PS*') { continue }
                if ([int]$pr.Value -eq 0) { $masquesConnexion[$pr.Name.ToLower()] = $true }
            }
        }
    } catch { }

    $tasks = @()
    try { $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq 'Vigie' -or $_.TaskName -like ($script:VigieTaskPrefix + '*') }) } catch { }
    $Accounts = @()
    try { $Accounts = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled }) } catch { }
    @(foreach ($c in $Accounts) {
        $name = "$($c.Name)"
        $task = @($tasks | Where-Object {
            $_.TaskName -eq (Get-VigieAccountTaskName -Name $name) -or
            ($_.TaskName -eq 'Vigie' -and (Test-TaskUserIs -UserId "$($_.Principal.UserId)" -Name $name))
        })[0]
        # VRAI compte ou compte TECHNIQUE ? On ne juge pas sur le NOM (une liste noire
        # serait fausse le jour ou quelqu'un appelle son compte « Sandbox ») mais sur un
        # FAIT : ce profil a-t-il deja servi a ouvrir une session ? Un compte d'outil est
        # cree, parfois authentifie, mais son profil n'est jamais charge.
        # Ce critere ne demande AUCUNE elevation, contrairement a l'inspection du contenu
        # du profil qui avait ete essayee d'abord -- et qui laissait passer les bacs a sable.
        $profil  = Join-Path (Join-Path $env:SystemDrive 'Users') $name
        $aProfil = Test-Path -LiteralPath $profil
        $up = $profils["$($c.SID)"]
        $alreadyUsed = [bool]($up -and ($up.LastUseTime -or $up.Loaded))
        # ATTENTION : LastUseTime n'est visible QUE d'un processus eleve. Depuis une
        # session ordinaire, tous les profils paraissent « jamais utilises » -- le critere
        # seul se contredisait donc d'un contexte a l'autre (constate le 26/08 : un compte
        # d'outil ecarte cote agent, affiche cote serveur).
        # Quand on est eleve, on tranche sur le CONTENU du profil : un compte de personne
        # a un Bureau ou des Documents ; un compte d'outil n'en a pas.
        # CE RELEVE NE SAIT PAS QUI REGARDE, et c'est voulu : il est MIS EN CACHE dans un
        # fichier commun. Y ecrire quoi que ce soit de relatif au demandeur, c'est servir
        # a Famille la reponse calculee pour fhaza. Tout ce qui depend de la personne est
        # pose apres coup, par Add-AccountsPerspective.
        $technique = [bool]$masquesConnexion[$name.ToLower()]

        [pscustomobject][ordered]@{
            name        = $name
            fullName    = "$($c.FullName)"
            description = "$($c.Description)"
            admin       = (Test-LocalAccountIsAdmin -Name $name)
            hasProfile  = $aProfil
            technical   = $technique
            # Date de derniere UTILISATION du profil (plus fiable que LastLogon).
            lastUse     = $(if ($up -and $up.LastUseTime) { ([datetime]$up.LastUseTime).ToString('s') } else { $null })
            enabled     = [bool]$task
            task        = if ($task) { "$($task.TaskName)" } else { $null }
            # La tache existe-t-elle VRAIMENT en etat de marche ? Une tache qui pointe
            # vers un interpreteur disparu se lance et meurt aussitot, sans un mot :
            # Vigie ne demarre pas et l'ecran des comptes affiche « activee ». C'est
            # exactement ce qui est arrive le 26/08 (D83).
            taskAilment = if ($task) { Get-VigieTaskStructureAilment -Task $task } else { $null }
            # Ce qui attend son prochain demarrage : signale, mais pas « hors service ».
            taskPending = if ($task -and -not (Get-VigieTaskStructureAilment -Task $task)) { Get-VigieTaskHistoryAilment -Task $task } else { $null }
            # Le compte qui execute le serveur en ce moment : l'interface doit pouvoir dire
            # « c'est vous » et empecher de se retirer soi-meme par megarde.
            current     = $false          # pose par Add-AccountsPerspective, jamais mis en cache
            lastLogon   = if ($c.LastLogon) { $c.LastLogon.ToString('s') } else { $null }
        }
    })
}

# Pose (ou retire) la tache de demarrage d'UN compte. Exige l'elevation : creer une tache
# pour autrui est une operation d'administration -- Windows l'exige, Vigie aussi.
function Set-VigieAccountEnabled {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Enabled,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-IsElevated)) { throw "Modifier les comptes autorises demande un compte administrateur." }
    $account = @(Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })[0]
    if (-not $account) { throw "Compte inconnu sur cette machine : $Name" }
    # Un AUTRE compte que le sien exige que l'application lui soit lisible.
    if ($Enabled -and -not $account.current -and -not (Get-SharedInstallPath)) {
        throw "Aucune installation lisible par les autres comptes : deployez d'abord Vigie pour tous, sinon la tache de $Name echouerait a chaque ouverture de session."
    }

    if (-not $Enabled) {
        # On retire la tache DEDIEE. La tache historique « Vigie » n'est pas supprimee
        # ici : elle est le demarrage installe par install-autostart, et son retrait a son
        # propre script (uninstall-autostart) -- supprimer sans le dire serait pire.
        $t = Get-VigieAccountTaskName -Name $Name
        try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop } catch { }
        Clear-ComputerAccountsCache -Backend $Backend
        return (Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })
    }

    # POUR SOI : l'interpreteur courant convient, quel que soit son emplacement.
    # POUR UN AUTRE COMPTE : il lui faut un pwsh installe pour la MACHINE, sinon la tache
    # pointerait dans notre profil et ne lancerait rien chez lui (constate avec Famille).
    $pwsh = if ($account.current) { (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
            else                 { Get-SharedPwshPath }
    if (-not $pwsh -and $account.current) { throw "pwsh introuvable : impossible de creer la tache." }
    if (-not $pwsh) {
        throw ("PowerShell 7 n'est installe que pour ce compte (paquet du Store). La tache de " +
               $Name + " pointerait vers un chemin du profil de ce compte, illisible pour lui : Vigie ne " +
               "demarrerait pas, sans message. PowerShell 7 doit etre installe pour toute la machine " +
               "(winget install --id Microsoft.PowerShell --scope machine), puis ce compte reactive.")
    }
    # Le compte doit pouvoir LIRE ce que sa tache lance.
    # LE CHEMIN SUIT L'ENVIRONNEMENT DECLARE. Poser systematiquement l'installation
    # partagee ferait demarrer un autre compte sur la production alors que la machine se
    # declare en developpement -- et Vigie signalerait ensuite l'ecart qu'elle vient de
    # creer elle-meme.
    # LA LISIBILITE PASSE AVANT LA PREFERENCE. L'environnement declare dit ou l'on
    # VOUDRAIT tourner ; ce que le compte peut LIRE dit ou l'on PEUT tourner. Pointer la
    # tache de « Famille » vers le depot -- illisible pour elle a partir de Git\ -- a
    # produit un code 64, « impossible d'ouvrir le fichier », sans le moindre journal.
    $targetSid = $null
    try { $targetSid = (Get-LocalUser -Name $Name -ErrorAction Stop).SID.Value } catch { }
    if (-not $targetSid) { throw ("Compte introuvable sur cette machine : " + $Name) }

    # L'INSTALLATION PARTAGEE D'ABORD, TOUJOURS. L'environnement declare dit d'ou vient ce
    # qu'on deploie, pas ou ca tourne : une tache qui lance un depot personnel est
    # illisible pour les autres comptes et disparait si le dossier bouge. Le depot ne sert
    # de repli que s'il n'existe aucune installation partagee -- et seulement pour le
    # compte qui la possede.
    $candidates = @((Get-SharedInstallPath), (Get-RepoRoot))
    $appRoot = $null
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $probe = Join-Path (Join-Path $candidate 'apps') (Join-Path 'client' 'client.ps1')
        if (-not (Test-Path -LiteralPath $probe)) { continue }
        if (Test-PathReadableByAccount -Path $probe -Sid $targetSid -IsAdmin:([bool]$account.admin)) {
            $appRoot = $candidate
            break
        }
    }
    if (-not $appRoot) {
        throw ("Aucune copie de Vigie n'est lisible par " + $Name +
               " : deployez-la pour tous les comptes avant de l'activer.")
    }
    $client = Join-Path $appRoot 'apps/client/client.ps1'
    if (-not (Test-Path -LiteralPath $client)) { throw "Application introuvable : $client" }

    $action  = New-VigieClientAction -Pwsh $pwsh -Client $client
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    # 45 s : pwsh vient du Store (MSIX) et n'est pas toujours pret a l'instant du logon.
    $trigger.Delay = 'PT45S'
    $niveau  = if ($account.admin) { 'Highest' } else { 'Limited' }
    $princ   = New-ScheduledTaskPrincipal -UserId ("$env:COMPUTERNAME\$Name") -LogonType Interactive -RunLevel $niveau
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                  -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $taskName = Get-VigieAccountTaskName -Name $Name
    # On CONSTATE (D43) : une creation qui ne leve pas n'est pas une creation qui a eu
    # lieu. Le journal garde la trace des deux, et l'appelant recoit une vraie erreur.
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $princ -Settings $set -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Log -Backend $Backend -Name 'comptes' -Level 'ERROR' -Message (Get-Label 'common.creation-de-la-tache' $taskName $_.Exception.Message)
        throw ("Windows a refuse de creer la tache pour " + $Name + " : " + $_.Exception.Message)
    }
    $verif = $null
    try { $verif = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch { }
    if (-not $verif) {
        Write-Log -Backend $Backend -Name 'comptes' -Level 'ERROR' -Message (Get-Label 'common.tache-absente-juste-apres' $taskName)
        throw ("La tache de " + $Name + " n'existe pas apres creation : Windows l'a refusee sans le dire.")
    }
    Write-Log -Backend $Backend -Name 'comptes' -Message (Get-Label 'common.tache-creee' $taskName $princ.UserId $niveau)
    Clear-ComputerAccountsCache -Backend $Backend
    return (Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })
}


# --- OU S'EXECUTE UNE ACTION : sur le serveur, ou sur le bureau d'un compte ? ----------
#
# LE PROBLEME. Un serveur n'a pas d'ecran. Aujourd'hui il en a un par accident -- c'est le
# app cliente de fhaza qui la lance, donc dans une session de bureau. Le jour ou il devient la
# tache de machine, il tournera en session 0 : « Start-Process explorer.exe » y reussit
# sans que PERSONNE ne voie jamais la fenetre. L'action se declarerait faite, et rien ne
# se passerait a l'ecran.
#
# Et meme aujourd'hui, le probleme existe deja : si Famille demande d'ouvrir un dossier,
# c'est sur le bureau de FHAZA qu'il s'ouvre, parce que c'est la que tourne le serveur.
#
# LA REGLE. Une action declare ou elle doit s'executer, en tete de son fichier :
#     # @execution: session    -- elle s'execute dans la session du DEMANDEUR
#     # @execution: serveur    -- elle n'a besoin de personne (defaut)
# Le silence vaut « serveur » : c'est le cas courant, et une action qui n'ouvre rien n'a
# aucune raison de faire un detour.
#
# « ADMIN » ET « SESSION » VONT TRES BIEN ENSEMBLE, contrairement a ce que j'avais cru.
# Test-ActionAllowed refuse une action admin a un compte standard, et a une fenetre qui
# ne dit pas qui elle est, AVANT toute execution. Une action admin n'est donc demandee que
# par un administrateur -- et la tache d'app cliente d'un administrateur tourne en RunLevel
# Highest, donc elevee. Elle peut faire les deux.
#
# Le jour ou l'on voudra qu'un compte standard VOIE ces boutons et declenche une demande
# d'elevation, ce sera un autre sujet : il faudra qu'un administrateur puisse l'autoriser
# depuis l'interface, pour toutes les instances de Vigie. Hors perimetre aujourd'hui.
function Get-ActionExecutor {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($line in (Get-Content -LiteralPath $f -TotalCount 40)) {
                if ($line -match '^\s*#\s*@execution\s*:\s*(session|serveur)') { return $Matches[1] }
            }
        }
    } catch { }
    return 'serveur'
}

# Le dossier d'ordres d'un compte : c'est la que son app cliente regarde, une fois par seconde.
function Get-AccountRunDir {
    param([Parameter(Mandatory)][string]$Account)
    $varRoot = Get-AccountVarRoot -Account $Account
    if (-not $varRoot) { return $null }
    return (Join-Path $varRoot 'run')
}

<#
    FAIRE EXECUTER UNE ACTION PAR L'APP CLIENTE D'UN COMPTE.

    On depose un ordre dans son dossier, et on attend son compte rendu. L'app cliente tourne
    dans SA session, avec SES droits et SON bureau : la fenetre s'ouvre la ou le
    demandeur la voit, et l'action n'obtient rien que Windows lui refuserait.

    LE CANAL D'ORDRES EST UNE SURFACE D'ATTAQUE (conception, C8). Il vit dans le profil du
    compte, ou lui seul et les administrateurs ecrivent. Un dossier ou tout le monde
    pourrait deposer serait un moyen de faire executer n'importe quoi par n'importe qui.

    RIEN N'EST GARANTI DE L'AUTRE COTE : l'app cliente peut etre arrete, la session fermee, le
    compte deconnecte. On rend alors $null, et l'appelant decide -- ici, il execute
    lui-meme, comme avant. Une action qui ne s'ouvre pas sur le bon bureau vaut mieux
    qu'une action qui ne s'ouvre pas du tout.
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
    # PAS DE REPONSE : on retire notre ordre. Sans cela, une app cliente qui revient dans une
    # heure ouvrirait une fenetre que plus personne n'attend.
    Remove-Item -LiteralPath $order -Force -ErrorAction SilentlyContinue
    return $null
}

# --- QUI a le droit de lancer une action (D65) ---------------------------------
# Regle de BASE, choisie par l'utilisateur : Vigie ne permet rien de plus que ce que
# Windows permet deja a ce compte. Un compte standard ne doit pas obtenir par Vigie ce que
# Windows lui refuse -- l'application deviendrait un moyen d'elevation de privileges.
#
# Mais c'est une valeur PAR DEFAUT, pas un dogme : on doit pouvoir changer d'avis sur UNE
# action precise. D'ou deux niveaux :
#   1. la DECLARATION, en tete du fichier d'action : `# @droits: admin` ou `# @droits: tous` ;
#      elle vit a cote du code qu'elle protege, et se lit sans executer le script ;
#   2. la POLITIQUE de la machine, config/actions.policy.json, qui peut ouvrir ou fermer
#      une action nommement -- c'est le point ou l'utilisateur change d'avis.
# En l'absence de declaration : `admin`. Le silence n'ouvre rien.
function Get-ActionRequirement {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    # 1. Politique de la machine (elle tranche).
    try {
        $pol = Get-MachineConfigPath -File 'actions.policy.json'
        if (Test-Path -LiteralPath $pol) {
            $j = Get-Content -LiteralPath $pol -Raw -Encoding UTF8 | ConvertFrom-Json
            $v = $j.PSObject.Properties | Where-Object { $_.Name -eq $Type } | Select-Object -First 1
            if ($v -and "$($v.Value)" -match '^(admin|tous)$') { return "$($v.Value)" }
        }
    } catch { }
    # 2. Declaration de l'action.
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($line in (Get-Content -LiteralPath $f -TotalCount 40)) {
                # La valeur peut etre suivie d'un commentaire : on s'arrete au mot, pas a la ligne.
                if ($line -match '^\s*#\s*@droits\s*:\s*(admin|tous)') { return $Matches[1] }
            }
        }
    } catch { }
    return 'admin'
}

# L'action est-elle lancable ICI et MAINTENANT ? Rend un objet parlant : le front doit
# pouvoir DIRE pourquoi un bouton est inerte (une action ne disparait jamais -- D59).
# Ce que l'action AFFICHE quand un champ la cite : libelle, genre, severite. Declares en
# tete du fichier d'action (`# @libelle: Texte | kind | severity`), a cote des droits.
# Sans declaration : « Resoudre », en immediate/fix -- un bouton parlant vaut mieux que
# pas de bouton (D66), mais un libelle precis vaut mieux qu'un mot generique.
function Get-ActionPresentation {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    $label = 'Résoudre'; $kind = 'immediate'; $sev = 'fix'
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($line in (Get-Content -LiteralPath $f -TotalCount 40)) {
                if ($line -match '^\s*#\s*@libelle\s*:\s*(.+)$') {
                    $bouts = @("$($Matches[1])" -split '\|' | ForEach-Object { $_.Trim() })
                    # Le commentaire qui suit « -- » ne fait pas partie de la declaration.
                    if ($bouts.Count -ge 1 -and $bouts[0]) { $label = ($bouts[0] -replace '\s*--.*$', '').Trim() }
                    if ($bouts.Count -ge 2 -and $bouts[1]) { $kind  = ($bouts[1] -replace '\s*--.*$', '').Trim() }
                    if ($bouts.Count -ge 3 -and $bouts[2]) { $sev   = ($bouts[2] -replace '\s*--.*$', '').Trim() }
                    break
                }
            }
        }
    } catch { }
    [pscustomobject]@{ label = $label; kind = $kind; severity = $sev }
}

<#
    QUI DEMANDE A-T-IL LE DROIT ? -- ET NON : LE SERVEUR EST-IL ELEVE ?

    Cette fonction posait la mauvaise question. Elle repondait « oui » des que
    Test-IsElevated etait vrai -- or le serveur tourne SOUS UN COMPTE DE SERVICE
    ADMINISTRATEUR, donc toujours. Une action « @droits: admin » passait pour n'importe
    qui : un compte standard, et meme un navigateur ouvert sur l'adresse sans aucune
    identification. Pendant ce temps l'ecran des utilisateurs affichait « un compte
    standard n'obtient aucun droit en plus : Vigie lui refuse les actions administrateur ».
    Le texte promettait une garde qui n'existait pas, et le commentaire d'a cote la
    decrivait comme acquise.

    D65 tranche : par defaut Vigie ne permet rien de plus que ce que Windows permet deja a
    ce compte. Une action qui touche la machine se juge donc sur LE DEMANDEUR.

    TROIS REFUS, ET ILS NE DISENT PAS LA MEME CHOSE :
      - on ne sait pas qui demande -- fenetre ouverte sans identification ;
      - on sait, et ce compte n'est pas administrateur ;
      - le demandeur en a le droit, mais le serveur n'est pas eleve : il ne PEUT pas.

    HORS CONTEXTE WEB -- rafraichissement de fond, script lance a la main -- le demandeur
    est celui qui execute. Sans cela, tout ce qui ne vient pas d'un navigateur se verrait
    refuser ses propres actions.
#>
<#
    CE COMPTE EST-IL ADMINISTRATEUR ? Une reponse, gardee le temps qu'il faut.

    Cette question est posee pour CHAQUE action de CHAQUE carte a chaque construction de
    l'etat -- des dizaines de fois. Elle passait par Get-AccountByName, donc par l'
    inventaire des comptes, qui reinterroge les taches planifiees a chaque appel : 2,2
    secondes la fois. Mesure le 31/08 : onze appels, 25 secondes, et un /state a 28.

    L'appartenance au groupe des administrateurs ne change pas dans la minute. On la garde
    cinq minutes, par compte. C'est un cache de LECTURE : il ne decide de rien, il evite
    de redemander la meme chose a Windows quarante fois de suite.
#>
$script:AdminMemo = @{}
function Test-RequesterIsAdmin {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $memo = $script:AdminMemo[$Account]
    if ($memo -and ((Get-Date) - [datetime]$memo.at).TotalMinutes -lt 5) { return [bool]$memo.admin }
    $verdict = $false
    try { $verdict = Test-LocalAccountIsAdmin -Name $Account } catch { }
    $script:AdminMemo[$Account] = @{ admin = $verdict; at = (Get-Date) }
    return $verdict
}

function Test-ActionAllowed {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot),
        [AllowNull()][AllowEmptyString()][string]$Requester
    )
    $besoin = Get-ActionRequirement -Type $Type -Backend $Backend
    if ($besoin -ne 'admin') { return [pscustomobject]@{ allowed = $true; requirement = $besoin; reason = $null } }

    if (-not $PSBoundParameters.ContainsKey('Requester')) {
        $Requester = $(if ($WebEvent) { Get-RequesterAccount } else { Get-ProcessAccount })
    }

    if (-not $Requester) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système, et Vigie ne sait pas qui la demande. Le panneau s'ouvre depuis l'icône de Vigie."
        }
    }
    $isAdmin = Test-RequesterIsAdmin -Account $Requester -Backend $Backend

    if (-not $isAdmin) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système : elle demande un compte administrateur. Windows la refuserait de la même façon."
        }
    }
    if (-not (Test-IsElevated)) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système, et l'app serveur ne tourne pas avec les droits nécessaires."
        }
    }
    [pscustomobject]@{ allowed = $true; requirement = 'admin'; reason = $null }
}

# --- OU vivent les reglages : MACHINE puis UTILISATEUR (D65) -------------------
# L'ordinateur a plusieurs comptes Windows et chacun doit avoir SES reglages.
# Trois couches, de la plus generale a la plus personnelle :
#   1. les defauts VERSIONNES        (probes/<module>/module.psd1, Config)
#   2. la couche MACHINE             (config/*.local.* dans l'installation) -- ce qui
#      etait deja regle avant le multi-utilisateur reste donc en place pour tout le monde
#   3. la couche UTILISATEUR         (%LOCALAPPDATA%\Sowapps\Vigie) -- ce compte-ci
# On LIT les trois (la plus personnelle gagne) ; on ECRIT toujours dans la couche
# utilisateur : un compte ne modifie jamais les reglages d'un autre.
#
# Un processus eleve du meme compte partage son LOCALAPPDATA : le serveur eleve et le
# app cliente ecrivent donc bien au meme endroit que l'utilisateur connecte.
<#
    LES REGLAGES D'UN COMPTE VIVENT CHEZ LUI, ET ON VA LES Y CHERCHER.

    Jusqu'ici cette fonction rendait toujours le dossier du compte qui EXECUTE -- donc
    celui du serveur. Consequence constatee le 28/08 : Famille et fhaza voyaient les
    memes modules, la meme liste de paquets ignores, les memes notifications, parce que
    c'etait la configuration de fhaza dans les deux cas. Masquer une carte chez l'un la
    masquait chez l'autre.

    Avec -Account, on lit le dossier de CE compte. Sans, celui du processus : c'est le
    bon comportement pour un script local ou une tache, qui n'a pas de demandeur.

    On ne CREE rien dans le profil d'un autre : poser un dossier chez quelqu'un qui n'a
    jamais ouvert Vigie n'a pas de sens, et le serveur n'a aucune raison d'ecrire chez
    lui avant qu'il ne le demande.
#>
function Get-AccountConfigDir {
    param([Parameter(Mandatory)][string]$Account)
    $profil = Join-Path $env:SystemDrive (Join-Path 'Users' $Account)
    if (-not (Test-PathSafe $profil)) { return $null }
    return (Join-Path (Join-Path (Join-Path (Join-Path $profil 'AppData') 'Local') 'Sowapps') 'Vigie')
}

function Get-UserConfigDir {
    # Vigie est une application de SOWAPPS : ses donnees vivent sous le nom de l'editeur,
    # comme celles de n'importe quel logiciel installe (Editeur\Produit).
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    $d = Join-Path (Join-Path $base 'Sowapps') 'Vigie'
    if (-not (Test-Path -LiteralPath $d)) {
        try { New-Item -ItemType Directory -Path $d -Force -WhatIf:$false | Out-Null } catch { }
        # Reprise de l'emplacement precedent (sans editeur) : personne ne doit perdre ses
        # reglages parce que le rangement a change.
        $ancien = Join-Path $base 'Vigie'
        if ((Test-Path -LiteralPath $ancien) -and (Test-Path -LiteralPath $d)) {
            try {
                foreach ($x in (Get-ChildItem -LiteralPath $ancien -Force -ErrorAction SilentlyContinue)) {
                    $targetPath = Join-Path $d $x.Name
                    if (-not (Test-Path -LiteralPath $targetPath)) { Move-Item -LiteralPath $x.FullName -Destination $targetPath -Force }
                }
            } catch { }
        }
    }
    $d
}
function Get-UserConfigPath {
    param(
        [Parameter(Mandatory)][string]$File,
        # Le compte dont on veut les reglages. Par defaut : celui qui execute.
        [string]$Account
    )
    if ($Account) {
        $d = Get-AccountConfigDir -Account $Account
        if ($d) { return (Join-Path $d $File) }
    }
    return (Join-Path (Get-UserConfigDir) $File)
}
function Get-MachineConfigPath { param([Parameter(Mandatory)][string]$File) Join-Path (Get-RepoRoot) (Join-Path 'config' $File) }

# --- Gestion des modules (D48) ------------------------------------------------
# Un MODULE (unite) = un DOSSIER de sondes, declare par un module.psd1 versionne.
# L'activation est un choix de l'utilisateur : config/modules.local.psd1, jamais
# versionne. Un module coupe retire ses sondes du calcul, mais reste EXPOSE dans la
# cle units[] du contrat -- sinon l'interface ne pourrait plus proposer de le rallumer.
# Couche utilisateur si elle existe, couche machine sinon (D65). On n'UNIT pas les deux :
# rallumer chez soi un module coupe pour la machine doit rester possible.
# LE DEMANDEUR, PAS L'EXECUTANT. Get-ActionRequester rend le compte de la session quand
# la demande vient d'une page identifiee, et celui du processus sinon : c'est exactement
# la regle voulue pour des reglages personnels.
function Get-UnitsLocalPath { Get-UserConfigPath -File 'modules.local.psd1' -Account (Get-ActionRequester) }

# CE QUE L'UTILISATEUR A EXPLICITEMENT ALLUME. Distinct de « pas eteint » : un module
# peut naitre ETEINT (module.psd1 : DefautActif = $false), et il faut alors savoir si
# l'utilisateur l'a allume pour de bon ou s'il n'a simplement jamais eu d'avis.
function Get-EnabledUnits {
    <#
        A MODULE ONE ACCOUNT HAS TURNED ON IS COMPUTED, whoever asks -- and that includes nobody.

        This choice lives in the profile of whoever made it. The scheduler, which computes without anyone asking, has
        no requester: it read the service account's file, found nothing, fell back on the module's default and left
        the module out. Measured on 30/09: the two computations of the Debogage module -- turned on months earlier --
        had NEVER been started once, while both their cards were displayed as if they were fresh.

        So the answer is the union: every account's choice is read, and one "yes" is enough. Computing serves whoever
        looks, and it cannot depend on who happens to be looking.
    #>
    <#
        READ FROM THE PROFILES THEMSELVES, not from the list of accounts: establishing that list costs two seconds
        (measured 29/09) and this is asked once per module. A file that exists is an account that has an opinion.
        Kept for thirty seconds, because Get-InactiveUnits asks it ten times in a row.
    #>
    $nowTicks = [datetime]::UtcNow.Ticks
    if ($script:EnabledUnitsAt -and (($nowTicks - [long]$script:EnabledUnitsAt) / 1e7) -lt 30) {
        return @($script:EnabledUnitsCache)
    }
    $found = @()
    $seen = $false
    try {
        $users = Join-Path $env:SystemDrive 'Users'
        foreach ($dir in @(Get-ChildItem -LiteralPath $users -Directory -ErrorAction SilentlyContinue)) {
            $p = Join-Path $dir.FullName 'AppData\Local\Sowapps\Vigie\modules.local.psd1'
            if (-not (Test-PathSafe $p)) { continue }
            try { $found += @((Import-PowerShellDataFile -Path $p).Enabled | ForEach-Object { "$_" }); $seen = $true } catch { }
        }
    } catch { }
    if ($seen) {
        $script:EnabledUnitsCache = @($found | Where-Object { $_ } | Select-Object -Unique)
        $script:EnabledUnitsAt = $nowTicks
        return @($script:EnabledUnitsCache)
    }
    foreach ($p in @((Get-UnitsLocalPath), (Get-MachineConfigPath -File 'modules.local.psd1'))) {
        if (Test-Path -LiteralPath $p) {
            try { return @((Import-PowerShellDataFile -Path $p).Enabled | ForEach-Object { "$_" }) } catch { return @() }
        }
    }
    return @()
}

# Le module est-il actif, tout compte fait ? Trois cas, dans cet ordre :
#   1. l'utilisateur l'a eteint          -> non
#   2. l'utilisateur l'a allume          -> oui
#   3. personne n'a rien dit             -> ce que declare le module (actif, sauf avis
#                                           contraire ecrit dans module.psd1)
function Test-UnitEnabled {
    param(
        [Parameter(Mandatory)][string]$UnitId,
        [string]$Backend = (Get-BackendRoot)
    )
    if ((Get-DisabledUnits) -contains $UnitId) { return $false }
    if ((Get-EnabledUnits)  -contains $UnitId) { return $true }
    $decl = @{}
    $f = Join-Path (Join-Path (Join-Path $Backend 'probes') $UnitId) 'module.psd1'
    if (Test-Path -LiteralPath $f) {
        try { $decl = Import-PowerShellDataFile -Path $f } catch { }
    }
    if ($decl.ContainsKey('DefautActif')) { return [bool]$decl.DefautActif }
    return $true
}

# La liste des modules a EXCLURE du calcul, defauts compris. C'est elle que consulte
# Get-State : un module eteint ne coute rien, ni calcul ni carte.
function Get-InactiveUnits {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    @(foreach ($d in (Get-ChildItem -Path $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if (-not (Test-UnitEnabled -UnitId $d.Name -Backend $Backend)) { $d.Name }
    })
}

function Get-DisabledUnits {
    foreach ($p in @((Get-UnitsLocalPath), (Get-MachineConfigPath -File 'modules.local.psd1'))) {
        if (Test-Path -LiteralPath $p) {
            try { return @((Import-PowerShellDataFile -Path $p).Disabled | ForEach-Object { "$_" }) } catch { return @() }
        }
    }
    return @()
}

function Set-UnitEnabled {
    param(
        [Parameter(Mandatory)][string]$UnitId,
        [Parameter(Mandatory)][bool]$Enabled
    )
    $off = [System.Collections.Generic.List[string]]::new()
    foreach ($u in (Get-DisabledUnits)) { if ($u -ne $UnitId) { $off.Add($u) } }
    if (-not $Enabled) { $off.Add($UnitId) }
    # ALLUMER se garde aussi : un module qui naît éteint (debogage) doit rester allume
    # apres un redemarrage. Sans cette seconde liste, il se serait ré-éteint tout seul.
    $on = [System.Collections.Generic.List[string]]::new()
    foreach ($u in (Get-EnabledUnits)) { if ($u -ne $UnitId) { $on.Add($u) } }
    if ($Enabled) { $on.Add($UnitId) }
    $listeOn = ($on | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $liste = ($off | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $text = "@{`n    # Choix de l'utilisateur sur les modules (D48). Fichier ecrit par l'application`n" +
             "    # (vue de gestion des modules), jamais versionne.`n" +
             "    #   Disabled : eteints a la main.`n" +
             "    #   Enabled  : allumes a la main -- utile pour ceux qui naissent eteints (debogage).`n" +
             "    Disabled = @($liste)`n    Enabled = @($listeOn)`n}`n"
    $p = Get-UnitsLocalPath
    Set-Content -LiteralPath $p -Value $text -Encoding UTF8
}

function Get-UnitCatalog {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    $off = Get-DisabledUnits
    @(foreach ($dir in (Get-ChildItem -Path $probesDir -Directory | Sort-Object Name)) {
        $decl = @{}
        $declPath = Join-Path $dir.FullName 'module.psd1'
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        $probes = @(Get-ChildItem -Path $dir.FullName -Filter '*.probe.ps1' -File)
        [pscustomobject][ordered]@{
            id          = $dir.Name
            label       = if ($decl.Label) { "$($decl.Label)" } else { $dir.Name }
            description = if ($decl.Description) { "$($decl.Description)" } else { '' }
            enabled     = (Test-UnitEnabled -UnitId $dir.Name -Backend $Backend)
            # Un module de DEBOGAGE ne s'impose pas : il naît éteint et l'écran de
            # gestion doit pouvoir le dire au lieu de laisser croire a une panne.
            offByDefault = ($decl.ContainsKey('DefautActif') -and -not [bool]$decl.DefautActif)
            probes      = @($probes | ForEach-Object { $_.Name -replace '\.probe\.ps1$', '' })
        }
    })
}

# --- Parametres de modules (D57) ----------------------------------------------
# Modele valide par l'utilisateur : la CONFIG (module.psd1, versionnee) porte les valeurs
# par DEFAUT ; un PARAMETRE est une surcharge de l'utilisateur, posee via le menu
# Parametres et stockee dans config/parameters.local.json (jamais versionne).
# Chaque parametre a pour defaut une valeur de config -- c'est la regle, pas l'exception.
# On ECRIT dans la couche utilisateur (D65).
function Get-ParametersLocalPath { Get-UserConfigPath -File 'parameters.local.json' -Account (Get-ActionRequester) }

# Lecture d'UNE couche.
function Get-ParameterOverridesFrom {
    param([Parameter(Mandatory)][string]$Path)
    $out = @{}
    if (Test-Path -LiteralPath $Path) {
        try {
            $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($u in $j.PSObject.Properties) {
                $out[$u.Name] = @{}
                foreach ($k in $u.Value.PSObject.Properties) { $out[$u.Name][$k.Name] = $k.Value }
            }
        } catch { }
    }
    return $out
}

# Machine PUIS utilisateur : le reglage personnel gagne, cle par cle (et seulement les
# cles reglees -- le reste continue de suivre la machine, puis le defaut du module).
function Get-ParameterOverrides {
    param([switch]$UtilisateurSeul)
    $out = @{}
    $couches = if ($UtilisateurSeul) { @((Get-ParametersLocalPath)) }
               else { @((Get-MachineConfigPath -File 'parameters.local.json'), (Get-ParametersLocalPath)) }
    foreach ($c in $couches) {
        $couche = Get-ParameterOverridesFrom -Path $c
        foreach ($u in $couche.Keys) {
            if (-not $out.ContainsKey($u)) { $out[$u] = @{} }
            foreach ($k in $couche[$u].Keys) { $out[$u][$k] = $couche[$u][$k] }
        }
    }
    return $out
}

# La valeur EFFECTIVE d'un reglage : surcharge utilisateur si presente, sinon la config
# du module. C'est LE point d'entree des sondes -- elles ne lisent jamais le fichier local.
function Get-ModuleSetting {
    param(
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][string]$Key,
        [string]$Backend = (Get-BackendRoot)
    )
    $sur = Get-ParameterOverrides
    if ($sur.ContainsKey($Unit) -and $sur[$Unit].ContainsKey($Key)) { return $sur[$Unit][$Key] }
    $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $Unit) 'module.psd1'
    if (Test-Path -LiteralPath $declPath) {
        try {
            $d = Import-PowerShellDataFile -Path $declPath
            if ($d.Config -and $d.Config.ContainsKey($Key)) { return $d.Config[$Key] }
        } catch { }
    }
    return $null
}

# Catalogue pour l'interface : chaque module declare (module.psd1) ses parametres
# reglables -- cle, libelle, type, aide -- et la valeur courante est calculee ici.
function Get-ModuleParameterCatalog {
    param([string]$Backend = (Get-BackendRoot))
    # `sur` = ce que CE compte a regle ; `mach` = ce qui est regle pour la machine.
    $sur  = Get-ParameterOverrides -UtilisateurSeul
    $mach = Get-ParameterOverridesFrom -Path (Get-MachineConfigPath -File 'parameters.local.json')
    @(foreach ($u in (Get-UnitCatalog -Backend $Backend)) {
        $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $u.id) 'module.psd1'
        $decl = @{}
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        if (-not $decl.Parameters) { continue }
        $params = @(foreach ($pm in @($decl.Parameters)) {
            $cle = "$($pm.Key)"
            $defaut = if ($decl.Config -and $decl.Config.ContainsKey($cle)) { $decl.Config[$cle] } else { $null }
            # Ce dont ce compte HERITE s'il n'a rien regle : le defaut du module, ou le
            # reglage de la machine s'il y en a un (D65).
            if ($mach.ContainsKey($u.id) -and $mach[$u.id].ContainsKey($cle)) { $defaut = $mach[$u.id][$cle] }
            $courant = if ($sur.ContainsKey($u.id) -and $sur[$u.id].ContainsKey($cle)) { $sur[$u.id][$cle] } else { $defaut }
            [ordered]@{
                key      = $cle
                label    = "$($pm.Label)"
                type     = if ($pm.Type) { "$($pm.Type)" } else { 'int' }
                unit     = if ($pm.Unit) { "$($pm.Unit)" } else { $null }
                help     = if ($pm.Help) { "$($pm.Help)" } else { '' }
                # Bornes de curseur : l'interface propose un reglage guide, la saisie
                # manuelle reste toujours possible (champ nombre synchronise).
                min      = if ($null -ne $pm.Min)  { [int]$pm.Min }  else { $null }
                max      = if ($null -ne $pm.Max)  { [int]$pm.Max }  else { $null }
                step     = if ($null -ne $pm.Step) { [int]$pm.Step } else { $null }
                default  = $defaut
                value    = $courant
                overridden = ($sur.ContainsKey($u.id) -and $sur[$u.id].ContainsKey($cle))
            }
        })
        [pscustomobject][ordered]@{ unit = $u.id; label = $u.label; params = $params }
    })
}

# Pose (ou retire) des surcharges. $null pour une cle = retour a la valeur de config.
# Seules les cles DECLAREES par le module sont acceptees : un parametre non declare
# n'a pas d'interface, il n'a donc pas non plus de surcharge.
function Set-ModuleParameters {
    param(
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][hashtable]$Values,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = @(Get-ModuleParameterCatalog -Backend $Backend | Where-Object { $_.unit -eq $Unit })
    if (-not $cat) { throw "Module sans parametres declares : $Unit" }
    $connues = @($cat[0].params | ForEach-Object { $_.key })
    # UtilisateurSeul : on ne recopie pas les valeurs de la machine dans le fichier
    # personnel -- sinon elles y seraient figees et ne suivraient plus l'installation.
    $sur = Get-ParameterOverrides -UtilisateurSeul
    if (-not $sur.ContainsKey($Unit)) { $sur[$Unit] = @{} }
    foreach ($k in $Values.Keys) {
        if ($connues -notcontains "$k") { throw "Parametre non declare : $Unit.$k" }
        if ($null -eq $Values[$k]) { $sur[$Unit].Remove("$k") }
        else { $sur[$Unit]["$k"] = $Values[$k] }
    }
    if ($sur[$Unit].Count -eq 0) { $sur.Remove($Unit) }
    $p = Get-ParametersLocalPath
    $tmp = "$p.tmp"
    ($sur | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $p -Force
}

# --- Reglages des notifications (D54) ----------------------------------------
# L'APP CLIENTE notifie sur bascule d'un MODULE (resultat de sonde) ; la couleur de son icone,
# elle, reste le statut de l'APPLICATION -- les deux roles ne se melangent pas.
#
# Reglages : un interrupteur global + un reglage FIN par module. Le global MASQUE, il
# n'ecrase pas : couper tout puis rallumer retrouve les choix fins intacts. C'est pour
# cela que les deux vivent dans des cles separees.
#
# Stockage : config/notifications.local.json a la racine (jamais versionne). JSON et non
# psd1 : ce fichier est ECRIT par le backend (l'interface le modifie via l'API), et le
# app cliente le RELIT ; JSON se lit et s'ecrit sans peine des deux cotes.
# Ecriture : couche utilisateur (D65). Lecture : la sienne si elle existe, celle de la
# machine sinon.
function Get-NotificationSettingsPath { Get-UserConfigPath -File 'notifications.local.json' -Account (Get-ActionRequester) }
function Get-NotificationSettingsReadPath {
    foreach ($p in @((Get-NotificationSettingsPath), (Get-MachineConfigPath -File 'notifications.local.json'))) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Get-NotificationSettingsPath)
}

function Get-NotificationSettings {
    param([string]$Backend = (Get-BackendRoot))
    $s = [ordered]@{ enabled = $true; modules = [ordered]@{}; notifs = [ordered]@{} }
    $p = Get-NotificationSettingsReadPath
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $j.enabled) { $s.enabled = [bool]$j.enabled }
            if ($j.modules) { foreach ($pr in $j.modules.PSObject.Properties) { $s.modules[$pr.Name] = [bool]$pr.Value } }
            if ($j.notifs)  { foreach ($pr in $j.notifs.PSObject.Properties)  { $s.notifs[$pr.Name]  = [bool]$pr.Value } }
        } catch { }
    }
    [pscustomobject]$s
}

function Set-NotificationSettings {
    param(
        [string]$Backend = (Get-BackendRoot),
        $Enabled,
        # Table module -> $true/$false. FUSIONNEE avec l'existant : ne fournir que ce qui
        # change ; une cle absente garde son reglage (le global ne perd jamais le fin).
        [hashtable]$Modules,
        # Table « <module>.<notification> » -> $true/$false. Fusionnee comme le reste.
        [hashtable]$Notifs
    )
    $cur = Get-NotificationSettings -Backend $Backend
    $out = [ordered]@{ enabled = [bool]$cur.enabled; modules = [ordered]@{}; notifs = [ordered]@{} }
    foreach ($k in @($cur.modules.Keys)) { $out.modules["$k"] = [bool]$cur.modules[$k] }
    foreach ($k in @($cur.notifs.Keys))  { $out.notifs["$k"]  = [bool]$cur.notifs[$k] }
    if ($null -ne $Enabled) { $out.enabled = [bool]$Enabled }
    if ($Modules) { foreach ($k in $Modules.Keys) { $out.modules["$k"] = [bool]$Modules[$k] } }
    if ($Notifs)  { foreach ($k in $Notifs.Keys)  { $out.notifs["$k"]  = [bool]$Notifs[$k] } }
    $p = Get-NotificationSettingsPath
    $tmp = "$p.tmp"
    ($out | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $p -Force
    [pscustomobject]$out
}

# --- CATALOGUE DES NOTIFICATIONS (D54, revu le 26/08) -------------------------
# Une notification n'est PAS « une carte » : c'est un EVENEMENT nomme, que le module
# declare. « Session de jeu » ne dit rien a personne ; « Temperature GPU elevee » si.
# (Signale par l'utilisateur : l'ecran listait les cartes, pas les notifications.)
#
# Declaration, dans probes/<module>/module.psd1 :
#   Notifications = @(
#       @{ Key = 'gpu-temp'; Label = 'Temperature GPU elevee'
#          Field = 'gpu-temp'; Card = 'gaming'; Help = '...' }
#   )
# Key   : identifiant stable du reglage (jamais affiche) ;
# Label : ce que l'utilisateur lit ;
# Card / Field : la carte et le champ dont la BASCULE declenche la notification.
#
# Un module sans declaration retombe sur une notification unique par carte : l'ancien
# comportement, pour ne rien perdre en route.
function Get-NotificationCatalog {
    param([string]$Backend = (Get-BackendRoot))
    @(foreach ($u in (Get-UnitCatalog -Backend $Backend)) {
        $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $u.id) 'module.psd1'
        $decl = @{}
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        $notifs = @(foreach ($nn in @($decl.Notifications)) {
            if (-not $nn -or -not $nn.Key) { continue }
            [ordered]@{
                key   = "$($nn.Key)"
                label = "$($nn.Label)"
                help  = if ($nn.Help) { "$($nn.Help)" } else { '' }
                card  = if ($nn.Card) { "$($nn.Card)" } else { '' }
                field = if ($nn.Field) { "$($nn.Field)" } else { '' }
                # QUI peut y faire quelque chose, et faut-il quand meme prevenir ?
                rights   = if ($nn.Droits) { "$($nn.Droits)" } else { 'tous' }
                critical = [bool]$nn.Critique
            }
        })
        [pscustomobject][ordered]@{ unit = $u.id; label = $u.label; enabled = $u.enabled; notifications = $notifs }
    })
}

# L'app cliente applique la regle SANS refaire la logique : une notification pour ce module
# passe-t-elle ? (global coupe = rien ; sinon le reglage fin, actif par defaut)
function Test-NotificationAllowed {
    param(
        [Parameter(Mandatory)][string]$ModuleId,
        # Cle de la notification declaree par le module. Absente : on juge au niveau du
        # module, comme avant.
        [string]$Key,
        $Settings
    )
    if (-not $Settings) { $Settings = Get-NotificationSettings }
    if (-not [bool]$Settings.enabled) { return $false }
    # DROITS (regle utilisateur, 26/08) : on ne derange pas quelqu'un avec un probleme
    # qu'il ne peut pas resoudre. Une notification dont la resolution exige un
    # administrateur ne s'affiche donc pas pour un compte standard...
    # ...SAUF si elle est declaree CRITIQUE : antivirus coupe, pare-feu ouvert, mises a
    # jour en attente. Dans ce cas l'utilisateur doit savoir, ne serait-ce que pour le
    # signaler a un administrateur -- l'app cliente le lui dit explicitement.
    if ($Key -and -not (Test-IsElevated)) {
        $decl = $null
        foreach ($u in (Get-NotificationCatalog)) {
            if ($u.unit -ne $ModuleId) { continue }
            $decl = @($u.notifications | Where-Object { $_.key -eq $Key })[0]
            break
        }
        if ($decl -and "$($decl.rights)" -eq 'admin' -and -not $decl.critical) { return $false }
    }
    # Reglage FIN (par notification) : il l'emporte sur celui du module.
    if ($Key -and $Settings.notifs) {
        $ref = "$ModuleId.$Key"
        $p = $Settings.notifs.PSObject.Properties | Where-Object { $_.Name -eq $ref } | Select-Object -First 1
        if (-not $p -and ($Settings.notifs -is [System.Collections.IDictionary]) -and $Settings.notifs.Contains($ref)) {
            return [bool]$Settings.notifs[$ref]
        }
        if ($p) { return [bool]$p.Value }
    }
    # `modules` est un DICTIONNAIRE (jamais un objet JSON brut : Get-NotificationSettings
    # normalise) -- l'acces passe donc par ContainsKey. La premiere version interrogeait
    # PSObject.Properties, qui sur un dictionnaire decrit le conteneur et pas les cles :
    # tous les reglages fins etaient silencieusement ignores.
    if ($Settings.modules.Contains("$ModuleId")) { return [bool]$Settings.modules["$ModuleId"] }
    return $true
}

# --- Actions ---------------------------------------------------------------
function New-JobId { [guid]::NewGuid().ToString('N').Substring(0, 12) }

# --- DEUX ENVIRONNEMENTS SUR UNE MEME MACHINE -------------------------------
#
# Le depot (developpement) et l'installation partagee (production locale) coexistent sur
# un poste de developpeur. Savoir LEQUEL repond n'est pas un detail : un correctif
# deploye au mauvais endroit coute une heure a comprendre.
#
# Deux notions, a ne pas confondre :
#   - l'environnement DECLARE : ce que la machine dit vouloir etre (reglage, defaut prod) ;
#   - l'environnement OBSERVE : d'ou le code qui tourne vient REELLEMENT.
# Quand les deux different, c'est un defaut nomme, pas un mystere.
<#
    CE QUE VOIT UNE FENETRE QUI NE DIT PAS QUI ELLE EST.

    Ouvrir l'adresse a la main -- une navigation privee, un signet, un autre navigateur --
    ne prouve rien : il n'y a pas de session, donc Vigie ne sait pas qui regarde. Elle
    servait pourtant le panneau ENTIER, jeton d'API compris. N'importe quel programme du
    poste pouvait donc lire l'etat de la machine, et agir.

    Deux comportements, et c'est l'ADMINISTRATEUR qui tranche :
      'error' (defaut) -- une page qui dit qu'on ne sait pas qui vous etes, et rien
                          d'autre : ni etat, ni jeton, ni liste de cartes ;
      'cards'          -- le panneau, avec les droits d'un compte standard : les actions
                          qui touchent la machine restent refusees (Test-ActionAllowed).

    Le reglage vit dans la declaration de l'ORDINATEUR (machine.psd1) : il vaut pour
    toutes les installations de la machine, et seul un administrateur peut l'ecrire.
#>
function Get-AnonymousAccess {
    param([string]$Backend = (Get-BackendRoot))
    $value = ''
    try { $value = "$((Get-Config -Backend $Backend).AnonymousAccess)".Trim().ToLowerInvariant() } catch { }
    if ($value -in @('error', 'cards')) { return $value }
    return 'error'
}

function Get-DeclaredStage {
    param([string]$Backend = (Get-BackendRoot))
    <#
        LE STAGE, PAS « L'ENVIRONNEMENT ».

        « Environnement » ne disait pas de quoi on parlait : ce reglage, le serveur, ou
        l'ordinateur entier ? C'est un STAGE au sens deploiement -- dev, prod, et la place
        pour un « staging » plus tard.

        L'ancien nom reste LU : un config.local.psd1 deja pose sur une machine ne doit pas
        cesser de fonctionner parce qu'on a trouve un meilleur mot.
    #>
    try {
        $cfg = Get-Config -Backend $Backend
        foreach ($k in @('Stage', 'Environment')) {
            $value = "$($cfg.$k)".Trim().ToLowerInvariant()
            if ($value -in @('dev', 'prod')) { return $value }
        }
    } catch { }
    return 'prod'      # defaut : une machine est en production tant qu'on n'a pas dit l'inverse
}

# D'ou vient le code qui tourne : sous Program Files, c'est l'installation partagee ;
# ailleurs, c'est un depot de travail. On lit le CHEMIN, pas une intention.
function Get-PathStage {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        if ("$Path".StartsWith("$root", [StringComparison]::OrdinalIgnoreCase)) { return 'prod' }
    }
    return 'dev'
}

function Get-RunningStage {
    param([string]$Backend = (Get-BackendRoot))
    Get-PathStage -Path $Backend
}

# Le libelle affiche, en clair : « Production » ne dit pas d'ou vient le code.
<#
    L'ENVIRONNEMENT DIT LA SOURCE, PAS L'EMPLACEMENT.

    Les libelles disaient « Developpement (depot) » / « Production (installation
    partagee) », comme si le code tournait a deux endroits. Il n'en tourne qu'un :
    l'installation partagee, developpement compris. Ce qui change, c'est CE QU'ON Y
    DEPLOIE -- une branche du depot, ou une version publiee.
#>
function Get-StageLabel {
    param([Parameter(Mandatory)][ValidateSet('dev', 'prod')][string]$Stage)
    # L'ENVIRONNEMENT NE DIT PAS LA SOURCE. Les deux libelles la nommaient (« source : le
    # depot », « source : versions publiees ») : c'est un REGLAGE A PART (UpdateSource),
    # et une production peut se synchroniser depuis un clone local sans cesser d'en etre
    # une. Deux axes, aucun deduit de l'autre.
    # MAJUSCULE INITIALE : c'est une VALEUR affichee dans une carte, pas un mot au milieu
    # d'une phrase -- check-probes le verifie. Les phrases, elles, ont leurs propres
    # libelles.
    if ($Stage -eq 'dev') { return 'Développement' }
    return 'Production'
}

# --- TRACABILITE : toute action laisse une trace, deux fois ------------------
#
# « On doit toujours pouvoir retrouver et justifier une action de Vigie. » Une trace
# qu'un fichier supprime fait disparaitre n'est pas une trace : chaque action ecrit donc
# AUSSI dans le journal des evenements Windows, la ou un administrateur va deja chercher
# quand il enquete, et d'ou Vigie ne peut pas l'effacer.
#
# Ce qui est trace : les actions REUSSIES, les actions REFUSEES et celles qui ECHOUENT.
# Le refus compte autant que la reussite -- c'est meme lui qu'on relit apres un incident.
$script:VigieEventSource = 'Vigie'
$script:VigieEventLog    = 'Application'

# Identifiants d'evenement, stables : ils servent a filtrer dans l'Observateur.
$script:VigieEventIds = @{ done = 1000; denied = 1001; failed = 1002 }

# La source doit exister AVANT d'ecrire, et la creer exige l'elevation. On la pose a
# l'installation ; ici on se contente de la creer si on peut, et de ne jamais faire
# echouer une action pour un probleme de journal.
function Register-VigieEventSource {
    param([switch]$Quiet)
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($script:VigieEventSource)) { return $true }
    } catch {
        # Sans elevation, meme la LECTURE est refusee : on ne sait pas, donc on n'affirme rien.
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-etat') -ForegroundColor DarkGray }
        return $false
    }
    try {
        [System.Diagnostics.EventLog]::CreateEventSource($script:VigieEventSource, $script:VigieEventLog)
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-source' $script:VigieEventSource) -ForegroundColor Green }
        return $true
    } catch {
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-source-2' $_.Exception.Message) -ForegroundColor Yellow }
        return $false
    }
}

# Le compte qui DEMANDE l'action. Aujourd'hui le serveur tourne dans la session de son
# utilisateur : c'est donc lui. Quand le serveur deviendra une tache machine servant
# plusieurs comptes, seule CETTE fonction changera -- tout le reste de la chaine parle
# deja de « demandeur » et non de « moi ».
<#
    QUI DEMANDE ? Le compte derriere la requete, pas le compte qui fait tourner le serveur.

    Cette fonction rendait l'identite du PROCESSUS -- c'est-a-dire toujours celle du
    serveur. Tant qu'il y avait un serveur par session, c'etait juste par accident. Avec
    un serveur unique pour la machine, c est faux pour tout le monde sauf lui : une action
    demandee par Famille serait journalisee au nom de fhaza, et executee sur SON bureau.

    L'ordre des preuves :
      1. le cookie de session, quand la demande vient d une page identifiee -- la seule
         source qui dise vraiment QUI regarde ;
      2. a defaut, l identite du processus : un script local, une tache planifiee, un
         diagnostic. C est alors le compte du serveur, et c est exact.

    LE NOM EST RENDU SANS SON DOMAINE. « HYPERION\fhaza » ne se joint pas a un chemin de
    profil : Get-AccountVarRoot en tirerait « C:\Users\HYPERION\fhaza ».
#>
<#
    QUI DEMANDE -- ou RIEN.

    Get-ActionRequester doit toujours rendre un nom : il signe le journal d'audit, et une
    trace anonyme ne vaut rien. Il retombe donc sur le compte du processus quand aucune
    session n'est ouverte.

    C'EST EXACTEMENT CE QUI NE VA PAS pour tout ce qui parle de « vous ». Une page ouverte
    sans ticket (un signet, un rechargement) n'a pas de cookie : le repli designe alors le
    compte du service, et la carte Comptes affiche « VOUS » sur VigieService -- constate le
    29/08.

    Cette fonction-ci ne se rabat sur rien : pas de session, pas de personne. A l'appelant
    de dire ce que « personne » signifie chez lui -- souvent « aucun compte n'est vous »,
    parfois « on previent tout le monde ».
#>
<#
    THE ACCOUNT THE CURRENT COMPUTATION IS FOR -- one door, and probes know no other.

    `Get-RequesterAccount` reads the session cookie of a WEB REQUEST. It therefore answers nothing at all when the
    SCHEDULER computes (D124), which has no requester: the refresh worker runs outside any request. A per-account
    probe that asked it directly saw $null half the time, and silently dropped what belongs to an account -- measured
    on 06/10, the winget card vanished from the panel for the very account that owns winget.

    `Get-State` says who it computes for, here, before running the probes; the cookie remains the fallback for code
    that runs inside a request without going through Get-State.
#>
<#
    AND IT IS A GLOBAL, WHICH IS NOT A SHORTCUT: a script variable cannot cross into a probe.

    Every probe begins by dot-sourcing this library into ITS OWN script scope. That re-runs the line below and
    redefines this function there, so a `$script:` variable set by Get-State was invisible to the probe -- the probe
    read its own copy, freshly reset to $null. Measured on 06/10: the scheduler computed the packages card for
    `fhaza`, the account's inventory held winget, and the card came out without it. Each link worked alone; the chain
    did not.

    Get-State therefore sets it in the global scope, right before running each probe, and clears it after. The window
    is inside the single-flight mutex that already serialises recomputation.
#>
if (-not (Get-Variable -Name 'VigieStateAccount' -Scope Global -ErrorAction SilentlyContinue)) {
    $global:VigieStateAccount = $null
}
function Get-StateAccount {
    if ($global:VigieStateAccount) { return $global:VigieStateAccount }
    return (Get-RequesterAccount)
}

function Get-RequesterAccount {
    try {
        if ($WebEvent) {
            $sid = $null
            try { $sid = $WebEvent.Cookies['vigie_session'].Value } catch { }
            if ($sid) {
                $account = Get-SessionAccount -SessionId $sid
                if ($account) { return $account }
            }
        }
    } catch { }
    return $null
}

function Get-ActionRequester {
    try {
        if ($WebEvent) {
            $sid = $null
            try { $sid = $WebEvent.Cookies['vigie_session'].Value } catch { }
            if ($sid) {
                $account = Get-SessionAccount -SessionId $sid
                if ($account) { return $account }
            }
        }
    } catch { }
    try {
        $name = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
        $sep = $name.LastIndexOf([char]92)
        if ($sep -ge 0) { $name = $name.Substring($sep + 1) }
        return $name
    } catch { return 'inconnu' }
}

function Write-VigieAudit {
    param(
        [Parameter(Mandatory)][ValidateSet('done', 'denied', 'failed')][string]$Outcome,
        [Parameter(Mandatory)][string]$Action,
        [string]$Module,
        [string]$Requester = (Get-ActionRequester),
        [string]$Rights = 'tous',
        [string]$Detail,
        [int]$Milliseconds = 0,
        [string]$Backend = (Get-BackendRoot)
    )
    $outcomeLabel = switch ($Outcome) {
        'done'   { 'REUSSIE' }
        'denied' { 'REFUSEE' }
        'failed' { 'ECHEC' }
    }
    $entry = ("{0} | action={1} | module={2} | demandeur={3} | droits={4}" -f
              $outcomeLabel, $Action, $(if ($Module) { $Module } else { '-' }), $Requester, $Rights)
    if ($Milliseconds -gt 0) { $entry += (" | duree={0} ms" -f $Milliseconds) }
    if ($Detail) { $entry += (" | " + $Detail) }

    # 1. Le journal de Vigie : le detail, relu pendant un depannage.
    try {
        $level = if ($Outcome -eq 'failed') { 'ERROR' } elseif ($Outcome -eq 'denied') { 'WARN' } else { 'INFO' }
        Write-Log -Backend $Backend -Name 'audit' -Level $level -Message $entry
    } catch { }

    # 2. Le journal des evenements Windows : la trace opposable.
    #
    # ELLE NE DOIT JAMAIS FAIRE ECHOUER L'ACTION. Un journal indisponible est un probleme
    # de journal, pas un probleme d'action -- mais il se voit dans celui de Vigie, sinon
    # on croirait la trace ecrite alors qu'elle ne l'est pas.
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($script:VigieEventSource)) {
            $type = switch ($Outcome) {
                'done'   { [System.Diagnostics.EventLogEntryType]::Information }
                'denied' { [System.Diagnostics.EventLogEntryType]::Warning }
                'failed' { [System.Diagnostics.EventLogEntryType]::Error }
            }
            [System.Diagnostics.EventLog]::WriteEntry(
                $script:VigieEventSource, $entry, $type, $script:VigieEventIds[$Outcome])
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'audit' -Level 'WARN' `
                        -Message (Get-Label 'common.journal-des-evenements-windows' $_.Exception.Message) } catch { }
    }
}

function Invoke-ActionById {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Module,
        [hashtable]$Params,
        [string]$Backend = (Get-BackendRoot)
    )
    # Sécurité : n'accepter qu'un identifiant simple (pas de traversee de chemin)
    if ($Type -notmatch '^[a-z][a-z0-9-]{1,40}$') {
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = "Type d'action invalide." }
    }
    # Garde REELLE : le bouton grise n'est qu'un affichage ; c'est ici que le refus
    # compte, une requete pouvant arriver sans passer par l'interface.
    # TRACE DE BOUT EN BOUT. Ce point est le seul par ou passe une action : c'est donc ici,
    # et nulle part ailleurs, qu'on ecrit qui a demande quoi et ce qui en est sorti. Un
    # REFUS se trace autant qu'une reussite -- c'est meme lui qu'on relit apres un incident.
    $requester = Get-ActionRequester
    $rights    = try { (Get-ActionRequirement -Type $Type -Backend $Backend) } catch { 'tous' }
    $timer    = [System.Diagnostics.Stopwatch]::StartNew()

    $droit = Test-ActionAllowed -Type $Type -Backend $Backend
    if (-not $droit.allowed) {
        Write-VigieAudit -Outcome 'denied' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("raison=" + $droit.reason) -Backend $Backend
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $droit.reason }
    }
    $file = Join-Path $Backend ("actions/$Type.action.ps1")
    $full = try { (Resolve-Path -LiteralPath $file -ErrorAction Stop).Path } catch { $null }
    $actionsDir = (Resolve-Path -LiteralPath (Join-Path $Backend 'actions')).Path
    if (-not $full -or -not $full.StartsWith($actionsDir)) {
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = "Action inconnue : $Type" }
    }
    # LE VERROU EST ICI, pas dans l'interface (D93). Une page restee ouverte peut
    # toujours envoyer une action : c'est le serveur qui doit dire non.
    # THE MODULE COUNTS: "paquets" becomes "paquets-choco" according to the card, so two different managers no
    # longer block one another (D130).
    $conflit = Test-ActionResourcesFree -Type $Type -Module $Module -Backend $Backend
    if ($conflit) {
        Write-VigieAudit -Outcome 'denied' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("ressource occupee : " + $conflit) -Backend $Backend
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $conflit }
    }
    try {
        # DANS QUELLE SESSION ? Une action declaree « session » doit s'executer chez le DEMANDEUR,
        # pas la ou tourne le serveur. On la lui fait executer par son app cliente ; s'il ne
        # repond pas, on l'execute ici comme avant plutot que de ne rien faire.
        $res = $null
        if ((Get-ActionExecutor -Type $Type -Backend $Backend) -eq 'session' -and $requester -and $requester -ne '-') {
            $relais = Invoke-ClientTask -Account $requester -Type $Type -Params $Params -Module $Module -Backend $Backend
            if ($relais) {
                $res = @{ message = "$($relais.message)"; result = $relais.result }
            } else {
                try { Write-Log -Backend $Backend -Name 'actions' -Level 'WARN' `
                                -Message ("Action " + $Type + " : l'app cliente de " + $requester + " n'a pas repondu, execution locale.") } catch { }
            }
        }
        if (-not $res) { $res = & $file -Module $Module -Params $Params }
        # Invalidation ciblee du cache : les sondes citees seront recalculees au prochain /state
        try {
            $inv = if ($res -and $res.result -and $res.result.invalidate) { @($res.result.invalidate) } else { @() }
            if ($inv.Count) { Remove-ProbeCache -Names $inv -Backend $Backend }
            <#
                ET ELLE NE SORT PAS D'ICI.

                « invalidate » est une CONSIGNE INTERNE : quelles sondes recalculer. Elle
                etait consommee ici puis renvoyee telle quelle au navigateur, qui n'en
                fait rien -- des noms de fichiers PowerShell dans une reponse JSON, sous
                les yeux de qui ouvre l'onglet reseau (releve le 01/09). Ce que le client
                doit connaitre, ce sont des CARTES, pas nos fichiers.
            #>
            if ($res -and $res.result -and $res.result.PSObject.Properties['invalidate']) {
                try {
                    if ($res.result -is [System.Collections.IDictionary]) { $res.result.Remove('invalidate') }
                    else { $res.result.PSObject.Properties.Remove('invalidate') }
                } catch { }
            }
        } catch { }
        # Une action peut rendre « ok = false » sans lever : c'est un echec, et il se trace
        # comme tel. Se fier au seul try/catch laisserait passer les echecs polis.
        $succeeded = -not ($res -and $res.result -and $res.result.PSObject.Properties['ok'] -and $res.result.ok -eq $false)
        Write-VigieAudit -Outcome $(if ($succeeded) { 'done' } else { 'failed' }) -Action $Type -Module $Module `
                         -Requester $requester -Rights $rights -Detail ("" + $res.message) `
                         -Milliseconds ([int]$timer.ElapsedMilliseconds) -Backend $Backend
        [pscustomobject]@{ jobId = (New-JobId); status = 'done'; message = $res.message; result = $res.result }
    } catch {
        Write-VigieAudit -Outcome 'failed' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("exception : " + $_.Exception.Message) `
                         -Milliseconds ([int]$timer.ElapsedMilliseconds) -Backend $Backend
        [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $_.Exception.Message }
    }
}

# --- Atelier : present en local ? --------------------------------------------
# L'Atelier est un outil de developpement lance A LA MAIN : l'interface de Vigie ne
# montre un lien vers lui QUE s'il repond vraiment. La detection vit ici (serveur) car
# le front ne peut pas sonder un autre port proprement, et le port de l'Atelier n'est
# defini que dans SA config (D15) -- on la lit, on ne la recopie pas.
function Get-AtelierUrl {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $cfgPath = Join-Path (Get-RepoRoot) 'apps/atelier/config/config.psd1'
        if (-not (Test-Path -LiteralPath $cfgPath)) { return $null }
        $acfg = Import-PowerShellDataFile -Path $cfgPath
        $port = [int]$acfg.Port
        if (-not $port) { return $null }
        $addr = (Get-Config -Backend $Backend).BindAddress
        if (-not $addr) { $addr = '127.0.0.1' }
        # Connexion TCP brute, delai court : sur l'hote local, un port ferme repond
        # immediatement -- ce test ne ralentit pas /health.
        $c = [System.Net.Sockets.TcpClient]::new()
        try {
            if (-not $c.ConnectAsync($addr, $port).Wait(250)) { return $null }
        } finally { $c.Dispose() }
        return ('http://{0}:{1}/apps/atelier/index.html' -f $addr, $port)
    } catch { return $null }
}

# --- Idempotence : le serveur ecoute-t-il deja ? ---------------------------
function Test-ServerUp {
    # Pas de valeur par defaut : l'adresse et le port n'ont qu'UNE definition (config.psd1).
    param([Parameter(Mandatory)][string]$Address, [Parameter(Mandatory)][int]$Port)
    try {
        $c = [System.Net.Sockets.TcpClient]::new()
        $c.Connect($Address, $Port)
        $c.Close()
        return $true
    } catch { return $false }
}

# --- Elevation : expliquer AVANT de demander ---------------------------------
# Principe (demande explicite de l'utilisateur, D22) : on n'envoie jamais l'invite
# UAC "nue". On affiche d'abord une fenetre qui dit ce qui va etre modifie et
# pourquoi l'elevation est necessaire, comme le fait Android avant une permission.
# L'utilisateur peut refuser sans qu'aucune invite systeme n'apparaisse.

# Echappe une chaine pour l'inserer dans une commande PowerShell (guillemets simples).
function ConvertTo-PSLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    "'" + $Value.Replace("'", "''") + "'"
}

# Le processus courant est-il eleve ? (une seule redaction de ce test)
# Le test d'elevation n'a qu'UNE implementation (Test-Elevated, plus haut). Ce nom-ci
# est celui qu'emploient les scripts d'installation ; il delegue au lieu de reecrire le
# meme test une seconde fois (D15). Les deux copies existaient et pouvaient diverger.
function Test-IsElevated { Test-Elevated }

# --- Habillage des fenetres (DWM) --------------------------------------------
# Barre de titre sombre et coins arrondis Windows 11. Declare UNE SEULE FOIS ici
# et utilise partout (fenetre de consentement, menu de l'app cliente) : la signature
# P/Invoke ne doit pas etre recopiee dans chaque script.
# Sans effet sur les versions de Windows anterieures : l'appel echoue sans dommage.
function Set-WindowChrome {
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [switch]$DarkTitleBar,
        [switch]$RoundedCorners,
        # Couleur de bordure au format COLORREF (0x00BBGGRR). -1 = ne pas toucher.
        [int]$BorderColor = -1
    )
    if ($Handle -eq [IntPtr]::Zero) { return }
    try {
        if (-not ('VigieNative.Dwm' -as [type])) {
            Add-Type -Namespace VigieNative -Name Dwm -MemberDefinition '[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);' -ErrorAction Stop
        }
        # 20 = DWMWA_USE_IMMERSIVE_DARK_MODE, 33 = WINDOW_CORNER_PREFERENCE, 34 = BORDER_COLOR
        if ($DarkTitleBar)   { $v = 1; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 20, [ref]$v, 4) }
        if ($RoundedCorners) { $v = 2; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 33, [ref]$v, 4) }
        if ($BorderColor -ne -1) { $v = $BorderColor; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 34, [ref]$v, 4) }
    } catch { }
}

# D'ou vient ce lancement ? Renvoie une chaine descriptive si un agent automatise
# est detecte, sinon $null (lancement a la main).
# Enjeu de securite : une demande de droits administrateur qui ne vient PAS d'un clic
# de l'utilisateur doit s'annoncer comme telle. Sans cela, un agent pourrait obtenir
# une elevation que l'utilisateur croirait avoir lui-meme declenchee.
function Get-LaunchOrigin {
    if ($env:AI_AGENT)       { return $env:AI_AGENT }
    if ($env:CLAUDECODE)     { return 'Claude Code' }
    if ($env:GITHUB_ACTIONS) { return 'GitHub Actions' }
    if ($env:TF_BUILD)       { return 'Azure Pipelines' }
    return $null
}

# Decoupe un controle en rectangle arrondi. Necessaire pour les menus contextuels :
# DWM (Set-WindowChrome) n'arrondit PAS les fenetres sans cadre standard, ce qui laisse
# un menu a coins carres. La region, elle, s'applique toujours.
# Contrepartie assumee : bords sans anticrenelage et ombre coupee au trace.
function Set-RoundedRegion {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [int]$Radius = 8
    )
    try {
        if ($Radius -le 0 -or $Control.Width -le 0 -or $Control.Height -le 0) { return }
        $w = $Control.Width; $h = $Control.Height
        $d = [Math]::Min($Radius * 2, [Math]::Min($w, $h))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $d, $d, 180, 90)
        $path.AddArc($w - $d, 0, $d, $d, 270, 90)
        $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
        $path.AddArc(0, $h - $d, $d, $d, 90, 90)
        $path.CloseFigure()
        $old = $Control.Region
        $Control.Region = New-Object System.Drawing.Region($path)
        if ($old) { $old.Dispose() }
        $path.Dispose()
    } catch { }
}

# Fenetre explicative. Renvoie $true si l'utilisateur accepte de continuer.
# -AssumeYes court-circuite l'affichage (execution non interactive, tache planifiee).
function Show-ElevationRationale {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Summary,
        [string[]]$Changes = @(),
        # Origine du lancement. Par defaut : detectee automatiquement, pour qu'un agent
        # ne puisse pas masquer son role en oubliant de le declarer.
        [string]$InitiatedBy = (Get-LaunchOrigin),
        [switch]$AssumeYes
    )
    if ($AssumeYes) { return $true }

    # LA FENETRE VIT DANS scripts/lib/show-confirm.ps1, et nulle part ailleurs.
    #
    # Elle doit pouvoir s'afficher AVANT la premiere elevation, quand PowerShell 7 n'est
    # pas encore installe : elle est donc ecrite pour tourner aussi sous Windows
    # PowerShell 5.1, et vit hors de cette bibliotheque qui, elle, vise PS7. La dessiner
    # une seconde fois ici aurait garanti que les deux divergent des la premiere retouche.
    $script = $null
    try { $script = Join-Path (Get-RepoRoot) 'scripts/lib/show-confirm.ps1' } catch { }

    if ($script -and (Test-Path -LiteralPath $script)) {
        $exe = $null
        try { $exe = (Get-Process -Id $PID).Path } catch { }
        if (-not $exe) { $exe = 'powershell.exe' }
        # LE TEXTE NE TRAVERSE PAS LA LIGNE DE COMMANDE. Passe en argument, il subit la
        # page de code du processus appele : « securite » y devient « sIcuritI » (constate
        # le 29/08). Ces textes-la sont CONSTRUITS -- ils viennent de l'action, pas d'un
        # libelle -- donc aucune cle ne les designe : ils passent par un fichier, et seul
        # son chemin, en ASCII, franchit la frontiere.
        $payload = Join-Path ([IO.Path]::GetTempPath()) ('vigie-confirm-' + [guid]::NewGuid().ToString('N') + '.json')
        $data = @{ title = "$Title"; summary = "$Summary"
                   changes = ($Changes -join '|'); initiatedBy = "$InitiatedBy" }
        [System.IO.File]::WriteAllText($payload, ($data | ConvertTo-Json -Compress -Depth 4),
                                       (New-Object System.Text.UTF8Encoding($false)))
        # RAW VALUES: the call operator quotes each argument itself, so a value wrapped by
        # hand arrives WITH its quotes. The opposite of Start-Process (D116).
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script,
                  '-PayloadFile', $payload)
        try {
            & $exe @argv
            # 0 = continuer ; 3 = refus ; 1 = pas d'interface, et le script l'a dit en
            # console. Tout ce qui n'est pas 0 REFUSE : rien ne s'eleve sans consentement.
            return ($LASTEXITCODE -eq 0)
        } catch {
            Write-Host (Get-Label 'common.impossible-afficher-la-fenetre' $_.Exception.Message) -ForegroundColor Yellow
        } finally {
            # DANS UN « finally », pas apres le return : un nettoyage place apres ne
            # s'execute jamais, et le fichier -- qui porte le texte de la fenetre --
            # resterait dans le dossier temporaire a chaque elevation. Et « finally »
            # vient APRES « catch » : l'ordre inverse ne s'analyse pas.
            try { Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

    # Repli : le script est introuvable (installation abimee). On explique en console et
    # on REFUSE -- utiliser -Yes pour un lancement volontairement automatise.
    $nl = [Environment]::NewLine
    Write-Host ""
    if ($InitiatedBy) {
        Write-Host (Get-Label 'common.demande-par-un-agent' $InitiatedBy) -ForegroundColor Yellow
        Write-Host (Get-Label 'common.ce-est-pas-toi') -ForegroundColor Yellow
    }
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $Summary
    if ($Changes.Count) { Write-Host (($Changes | ForEach-Object { "   - $_" }) -join $nl) }
    Write-Host (Get-Label 'common.fenetre-de-confirmation-introuvable') -ForegroundColor Yellow
    return $false
}

# Relance LE MEME script en session elevee en conservant ses parametres, puis
# restitue sa sortie. On ne peut pas rediriger un processus lance avec -Verb RunAs :
# la session elevee ecrit donc dans un journal, qu'on relit ensuite.
# Renvoie le code de retour de la session elevee.
function Invoke-ElevatedSelf {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$LogDir = $env:TEMP
    )
    # -WhatIf ne doit PAS s'appliquer a la relance : c'est le script relance qui doit
    # simuler ses propres operations. Sans -WhatIf:$false, -WhatIf simulerait l'elevation
    # et rien ne s'executerait - on ne verrait donc jamais ce qui allait etre fait.
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name  = [IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $log   = Join-Path $LogDir ('elevated_' + $name + '_' + $stamp + '.log')

    # UTF-8 IMPOSE DES LES DEUX BOUTS. Sans cela, la session elevee ecrit son journal
    # dans la page de code de la console (850 ou 1252 selon la machine) et le parent le
    # relit en UTF-8 : « Trouve » revenait « Trouv├® » (constate le 27/08). Les accents
    # ne sont pas negociables (D41).
    $parts = @('$OutputEncoding=[Text.Encoding]::UTF8;',
               '[Console]::OutputEncoding=[Text.Encoding]::UTF8;',
               '&', (ConvertTo-PSLiteral $ScriptPath))
    foreach ($a in $Arguments) {
        if ($a -like '-*') { $parts += $a } else { $parts += (ConvertTo-PSLiteral ([string]$a)) }
    }
    $cmd = ($parts -join ' ') + ' *> ' + (ConvertTo-PSLiteral $log)

    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-Host (Get-Label 'common.pwsh-introuvable') -ForegroundColor Red; return 1 }

    try {
        # The command block travels as ONE argument -- it is full of spaces, and split by
        # the command line it would only be rejoined by luck.
        $proc = Start-ChildProcess -FilePath $pwshPath `
                    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) `
                    -Options @{ Verb = 'RunAs'; Wait = $true; PassThru = $true
                                WindowStyle = 'Hidden'; WhatIf = $false }
    } catch {
        Write-Host (Get-Label 'common.elevation-refusee-ou-impossible' $_.Exception.Message) -ForegroundColor Yellow
        return 1
    }

    if (Test-Path -LiteralPath $log) {
        Write-Host (Get-Label 'common.compte-rendu-de-la')
        Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ }
        Write-Host (Get-Label 'common.journal' $log)
    } else {
        Write-Host (Get-Label 'common.aucune-sortie-produite-par') -ForegroundColor Yellow
    }
    return $proc.ExitCode
}
