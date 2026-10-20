# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, log, native, packages, paths, var, win-acl, win-tasks
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
    # The only refusal this product lays on a task folder is SYSTEM's: a refusal found there IS the lock. How a
    # refusal is read -- icacls, then .NET -- is the business of `win-acl`.
    return (Test-PathDenied -Path $Path -Sid (Get-UpdateTaskCatalog).SidSystem)
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
        $r1 = Remove-PathDenial   -Path $d -Sid $cat.SidSystem -Quiet
        $r2 = Set-PathFullControl -Path $d -Sid $cat.SidSystem -Quiet
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
            $rt = Set-PathOwnerAdmins  -Path $d
            $rg = Set-PathFullControl  -Path $d -Sid $cat.SidAdmins
            $rd = Add-PathWriteDenial  -Path $d -Sid $cat.SidSystem
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
