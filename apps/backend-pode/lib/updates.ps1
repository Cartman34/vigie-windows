# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, log, native, packages, paths, settings, var, watches
<#
    Intent: THE WINDOWS UPDATE MACHINERY: the lock that keeps Windows from rebooting the machine on its own, what the catalogue of its scheduled tasks says, and the audit that tells whether an installation really happened.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
            id = "$($u.Identity.UpdateID)"; title = "$($u.Title)"; kb = ($kb -join ', ')
            bytes = $size; driver = $driver; model = $model; driverClass = $class; driverDate = $when
            provider = $provider; downloaded = [bool]$u.IsDownloaded
            group = ''; label = ''; superseded = $false; failure = ''; alreadyDone = $false
        }
    }

    # --- The group, once the list is complete (D118) ---------------------------------------
    $seenByKey = @{}
    foreach ($line in $lines) {
        if (-not $line.driver -or -not "$($line.provider)".Trim()) { continue }
        $key = Get-VendorKey "$($line.provider)"
        if (-not $seenByKey.ContainsKey($key)) { $seenByKey[$key] = @() }
        $seenByKey[$key] += "$($line.provider)"
    }
    foreach ($line in $lines) {
        if (-not $line.driver) { $line.group = 'Windows'; continue }
        $key = Get-VendorKey "$($line.provider)"
        $line.group = $(if ($key) { Get-VendorName -Key $key -Seen $seenByKey[$key] -Backend $Backend }
                         else { 'Pilotes sans constructeur déclaré' })
        if ("$($line.model)".Trim()) { $line.label = "$($line.model)" }
    }

    # --- What the last installation failed at, and what it succeeded at ---------------------
    $failed = @{}
    $installed = @()
    try {
        $file = Get-VarPath -Backend $Backend -Kind 'cache' -File 'wu-install.json'
        if (Test-PathSafe $file) {
            $last = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            # THE FILE MAY HAVE BEEN WRITTEN BY THE PREVIOUS VERSION, which named these two in French. They are read
            # under both spellings HERE, so a record of an installation that already happened is not lost by a
            # rename -- the same takeover Get-UserConfigDir does for the settings folder. The old spelling can go
            # once an installation has been run by this version, which rewrites the file.
            $lastFailures = $(if ($null -ne $last.failures) { $last.failures } else { $last.echecs })
            $lastTitles   = $(if ($null -ne $last.titles)   { $last.titles }   else { $last.titres })
            foreach ($entry in @($lastFailures.PSObject.Properties)) { $failed[$entry.Name] = "$($entry.Value)" }
            if ($last.phase -eq 'termine' -and -not $last.error) {
                if ($last.detail) {
                    foreach ($d in @($last.detail)) { if (@($d).Count -ge 2 -and "$($d[1])" -match 'Install') { $installed += "$($d[0])" } }
                } elseif ($lastTitles) { $installed = @($lastTitles) }
            }
        }
    } catch { }
    foreach ($line in $lines) {
        if ($failed.ContainsKey("$($line.id)")) { $line.failure = $failed["$($line.id)"] }
        # RE-OFFERED: Windows says "installed successfully" then detects the SAME update
        # again -- the known loop of badly targeted OEM drivers. Reinstalling changes nothing.
        if ($installed -contains "$($line.title)") { $line.alreadyDone = $true }
    }

    # --- Two versions of one driver: the newest is the one we keep -------------------------
    #
    # THE CLASS IS PART OF THE PAIR, and the dates must actually differ. "Intel(R) UHD
    # Graphics" appears twice on the SAME date, once as Display and once as Extension: two
    # components of one device, not two versions of one component.
    $byModel = @{}
    foreach ($line in $lines) {
        if (-not "$($line.model)".Trim()) { continue }
        $key = "$($line.group)|$($line.model)|$($line.driverClass)".ToLowerInvariant()
        if (-not $byModel.ContainsKey($key)) { $byModel[$key] = @() }
        $byModel[$key] += $line
    }
    foreach ($key in @($byModel.Keys)) {
        $family = @($byModel[$key])
        if ($family.Count -lt 2) { continue }
        $dates = @($family | ForEach-Object { "$($_.driverDate)" } | Sort-Object -Unique)
        if ($dates.Count -lt 2) { continue }
        $newest = @($family | Sort-Object { "$($_.driverDate)" } -Descending)[0]
        foreach ($line in $family) { if ("$($line.driverDate)" -ne "$($newest.driverDate)") { $line.superseded = $true } }
    }

    # --- The order puts the two versions side by side inside their group -------------------
    $lines = @($lines | Sort-Object @{ Expression = { "$($_.group)" } },
                                    @{ Expression = { "$($_.model)" } },
                                    @{ Expression = { "$($_.driverClass)" } },
                                    @{ Expression = { "$($_.driverDate)" }; Descending = $true })

    # --- What we offer ----------------------------------------------------------------------
    $older = 0
    $offered = @()
    foreach ($line in $lines) {
        if ($line.alreadyDone) { continue }
        if (-not $line.superseded) { $offered += $line; continue }
        $key = "$($line.group)|$($line.model)|$($line.driverClass)".ToLowerInvariant()
        # When the newest one failed, the older one is the only way forward left.
        $newerFailed = @($lines | Where-Object {
            -not $_.superseded -and "$($_.group)|$($_.model)|$($_.driverClass)".ToLowerInvariant() -eq $key -and "$($_.failure)".Trim()
        }).Count -gt 0
        if ($newerFailed) { $offered += $line } else { $older++ }
    }

    [pscustomobject]@{
        ok = $true
        all = @($lines)
        offered = @($offered)
        drivers = @($lines | Where-Object { $_.driver }).Count
        setAsideOlder = $older
        alreadyDone = @($lines | Where-Object { $_.alreadyDone } | ForEach-Object { "$($_.title)" })
    }
}
