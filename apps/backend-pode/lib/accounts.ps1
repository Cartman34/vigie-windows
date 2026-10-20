# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: deployment, elevation, format, log, paths, property, requester, task-ailment, var, win-accounts, win-tasks
<#
    Intent: WHICH WINDOWS ACCOUNTS HAVE VIGIE (D65): who exists on this machine, who is enabled, whose profile can be read, and the scheduled task that starts the client app for each. Writing needs an elevated server; without it the switches stay visible and say why.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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

function Get-VigieAccountTaskName {
    param([Parameter(Mandatory)][string]$Name)
    $script:VigieTaskPrefix + $Name
}

# The machine's accounts, each with: whether it is an administrator, whether Vigie starts
# with it, and through which task. The legacy task is called plain "Vigie": it counts as
# enabled for the account it aims at, or the screen would wrongly say "inactive" to the
# person who has been using it since the beginning.
# The inventory costs about two seconds (accounts, groups, profiles, tasks) and changes only
# exceptionally: it is REMEMBERED. One day of validity, a button to force the reading, and
# enabling any account invalidates it by itself.
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

# THE STATE OF THE TASKS IS ALWAYS READ BACK.
#
# The list of accounts is expensive to establish (profiles, SIDs, registry) and rarely
# changes: it is cached for 24 h. The state of their startup task, on the other hand, is
# cheap to read and can change at any moment -- and if it lies, it lies about the only thing
# that matters. The card showed "Vigie activée" for hours for an account whose task had
# disappeared (28/08). Those three fields are therefore never served from the cache.
function Update-AccountTasks {
    param([object[]]$Accounts)
    if (-not $Accounts -or -not $Accounts.Count) { return @($Accounts) }
    $tasks = @()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { $_.TaskName -eq 'Vigie' -or $_.TaskName -like ($script:VigieTaskPrefix + '*') })
    } catch {
        # Without elevation Windows hides part of the tasks: we do not know, and we do not
        # PRETEND to. The cached values are kept as they are.
        return @($Accounts)
    }
    foreach ($c in $Accounts) {
        $name = "$($c.name)"
        $task = @($tasks | Where-Object {
            $_.TaskName -eq (Get-VigieAccountTaskName -Name $name) -or
            ($_.TaskName -eq 'Vigie' -and (Test-TaskUserIs -UserId "$($_.Principal.UserId)" -Name $name))
        })[0]
        # A CACHE MAY COME FROM AN OLDER VERSION, and its objects then lack the properties we
        # want to write. Assigning an absent property THROWS, and the original value -- stale
        # -- stayed on screen (seen on 28/08: "1 tache hors service" for a healthy task). So
        # they are created when missing.
        Set-ObjectValue -Object $c -Name 'enabled' -Value ([bool]$task)
        Set-ObjectValue -Object $c -Name 'task' -Value $(if ($task) { "$($task.TaskName)" } else { $null })
        # TWO FIELDS, two natures: "taskAilment" is what stops the task working;
        # "taskPending" is what will only be known at its next start. Confusing them made a
        # healthy task be announced as out of service.
        $mal = if ($task) { Get-VigieTaskStructureAilment -Task $task } else { $null }
        Set-ObjectValue -Object $c -Name 'taskAilment' -Value $mal
        Set-ObjectValue -Object $c -Name 'taskPending' `
            -Value $(if ($task -and -not $mal) { Get-VigieTaskHistoryAilment -Task $task } else { $null })
    }
    return @($Accounts)
}

<#
    WHAT DEPENDS ON WHO IS ASKING.

    Naming the reader, and saying "this account is not a technical account", are not facts about the computer:
    they are facts about the RELATION between the computer and the person looking. So they are
    laid at the moment of answering, never in the cached reading -- or the first to ask fixes
    the answer for everybody else.
#>
<#
    THE FOUR CIRCLES OF ACCOUNTS -- AND EACH ONE HAS ITS NAME.

    Every caller filtered again in its own way ("Where -not technical" copied in seven
    places), and the one that did not dropped a restart order in the SERVICE account's folder:
    "Relance demandee aux autres comptes : Famille, fhaza, VigieService". Nobody was ever
    going to read it.

      1. ALL the COMPUTER's accounts   Get-ComputerAccounts  -- VigieService is one
      2. the accounts of a PERSON      Get-UserAccounts      -- it is not
      3. those with Vigie ENABLED      Get-EnabledAccounts   -- they have a client app
      4. those RUNNING right now       (task plus a live client app)

    Circle 4 has no function: nobody needs it. A restart addresses circle 3 -- a client app
    that is off will start with the new code anyway, and checking its heartbeat would add a
    disk access for nothing.
#>
# ONE account, by its name. Copied in three places as "Get-ComputerAccounts |
# Where-Object { $_.name -eq X }", each time with the same trap: without @(...) around it, a
# single result is not an array and the index [0] returns a character.
function Get-AccountByName {
    param([Parameter(Mandatory)][string]$Name, [string]$Backend = (Get-BackendRoot))
    @(Get-ComputerAccounts -Backend $Backend | Where-Object { "$($_.name)" -eq $Name })[0]
}


function Get-EnabledAccounts {
    param([string]$Backend = (Get-BackendRoot))
    @(Get-UserAccounts -Backend $Backend | Where-Object { $_.enabled })
}


function Get-AccountRegistryRoot {
    <# The registry hive of ONE named account, or $null when it is not loaded.

       A hive is only mounted during its owner's session: a signed-out account has nothing
       to read, and we do not mount absent people's hives.
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
    # With no session, NOBODY is the reader: that is truer, and safer than naming the service
    # account.
    $requester = Get-RequesterAccount
    foreach ($c in @($Accounts)) {
        $isMe = [bool]$requester -and ("$($c.name)" -eq "$requester")
        $c | Add-Member -NotePropertyName current -NotePropertyValue $isMe -Force
        # Whoever is using Vigie right now is never a tool's account.
        if ($isMe) { $c | Add-Member -NotePropertyName technical -NotePropertyValue $false -Force }
    }
    return $Accounts
}

<#
    THE ACCOUNTS OF THIS COMPUTER -- not "Vigie accounts".

    The function was called Get-VigieAccounts: it returns nothing belonging to Vigie, it
    returns the accounts WINDOWS declares, each with what Vigie knows about it. The name
    suggested a list of authorised accounts, which is circle 3.
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
    # THE PERSPECTIVE COMES AFTER THE CACHE, never before: what is written to disk must stay
    # true for anybody.
    return (Add-AccountsPerspective $liste)
}

# The REAL reading, with no cache.
function Get-ComputerAccountsFresh {
    param([string]$Backend = (Get-BackendRoot))
    # PROFILES REALLY USED: that is THE discriminator between a person's account and a tool's.
    # Win32_UserProfile.LastUseTime says when the profile genuinely served, at a logon. The
    # ACCOUNT's LastLogon, on the other hand, lies: a sandbox account showed "signed in today"
    # without ever having opened a session -- reported by the owner, checked on 26/08
    # (LastUseTime empty, the profile never loaded).
    $profils = @{}
    try {
        foreach ($up in (Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special })) {
            $cle = "$($up.SID)"
            if ($cle) { $profils[$cle] = $up }
        }
    } catch { }

    # WHICH ACCOUNTS BELONG TO A PERSON? Windows says so itself:
    # Winlogon\SpecialAccounts\UserList lists the accounts HIDDEN from the sign-in screen
    # (value 0). That is how tools declare their service accounts.
    # Every criterion tried before was wrong: the profile (sandboxes have one), its date of
    # use (invisible without elevation, hence two contradictory verdicts between the agent and
    # the server), its contents (a Desktop is there all the same), and membership of the Users
    # group (they are members).
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
        # A REAL account or a TECHNICAL one? We do not judge on the NAME -- a blacklist would
        # be wrong the day somebody calls their account "Sandbox" -- but on a FACT: has this
        # profile ever been used to open a session? A tool's account is created, sometimes
        # authenticated, but its profile is never loaded.
        # That criterion requires NO elevation, unlike inspecting the profile's contents which
        # was tried first -- and which let the sandboxes through.
        $profil  = Join-Path (Join-Path $env:SystemDrive 'Users') $name
        $aProfil = Test-Path -LiteralPath $profil
        $up = $profils["$($c.SID)"]
        $alreadyUsed = [bool]($up -and ($up.LastUseTime -or $up.Loaded))
        # BEWARE: LastUseTime is visible ONLY to an elevated process. From an ordinary session
        # every profile looks "never used" -- so the criterion alone contradicted itself from
        # one context to the other (seen on 26/08: a tool's account ruled out on the agent's
        # side, displayed on the server's).
        # When elevated, we decide on the profile's CONTENTS: a person's account has a Desktop
        # or Documents; a tool's account has none.
        # THIS READING DOES NOT KNOW WHO IS LOOKING, and that is intended: it is CACHED in a
        # shared file. Writing anything relative to the requester there means serving Famille
        # the answer computed for fhaza. Everything depending on the person is laid afterwards,
        # by Add-AccountsPerspective.
        $technique = [bool]$masquesConnexion[$name.ToLower()]

        [pscustomobject][ordered]@{
            name        = $name
            fullName    = "$($c.FullName)"
            description = "$($c.Description)"
            admin       = (Test-LocalAccountIsAdmin -Name $name)
            hasProfile  = $aProfil
            technical   = $technique
            # The profile's last USE date (more reliable than LastLogon).
            lastUse     = $(if ($up -and $up.LastUseTime) { ([datetime]$up.LastUseTime).ToString('s') } else { $null })
            enabled     = [bool]$task
            task        = if ($task) { "$($task.TaskName)" } else { $null }
            # Does the task REALLY exist in working order? A task pointing at an interpreter
            # that is gone starts and dies at once, without a word: Vigie does not start and
            # the accounts screen shows "activée". That is exactly what happened on 26/08
            # (D83).
            taskAilment = if ($task) { Get-VigieTaskStructureAilment -Task $task } else { $null }
            # What is waiting for its next start: reported, but not "out of service".
            taskPending = if ($task -and -not (Get-VigieTaskStructureAilment -Task $task)) { Get-VigieTaskHistoryAilment -Task $task } else { $null }
            # The account running the server right now: the interface must be able to say
            # "that is you" and stop anyone removing themselves by mistake.
            current     = $false          # pose par Add-AccountsPerspective, jamais mis en cache
            lastLogon   = if ($c.LastLogon) { $c.LastLogon.ToString('s') } else { $null }
        }
    })
}

# Lays down (or removes) ONE account's startup task. It requires elevation: creating a task
# for somebody else is an administration operation -- Windows requires it, and so does Vigie.
function Set-VigieAccountEnabled {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Enabled,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-IsElevated)) { throw "Modifier les comptes autorises demande un compte administrateur." }
    $account = @(Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })[0]
    if (-not $account) { throw "Compte inconnu sur cette machine : $Name" }
    # An account OTHER than one's own requires the application to be readable by it.
    if ($Enabled -and -not $account.current -and -not (Get-SharedInstallPath)) {
        throw "Aucune installation lisible par les autres comptes : deployez d'abord Vigie pour tous, sinon la tache de $Name echouerait a chaque ouverture de session."
    }

    if (-not $Enabled) {
        # The DEDICATED task is removed. The legacy "Vigie" task is not deleted here: it is
        # the startup installed by install-autostart, and its removal has its own script
        # (uninstall-autostart) -- deleting without saying so would be worse.
        $t = Get-VigieAccountTaskName -Name $Name
        try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop } catch { }
        Clear-ComputerAccountsCache -Backend $Backend
        return (Get-ComputerAccounts -Backend $Backend | Where-Object { $_.name -eq $Name })
    }

    # FOR ONESELF: the current interpreter will do, wherever it sits.
    # FOR ANOTHER ACCOUNT: it needs a pwsh installed for the MACHINE, or the task would point
    # inside our profile and launch nothing for them (seen with Famille).
    $pwsh = if ($account.current) { (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
            else                 { Get-SharedPwshPath }
    if (-not $pwsh -and $account.current) { throw "pwsh introuvable : impossible de creer la tache." }
    if (-not $pwsh) {
        throw ("PowerShell 7 n'est installe que pour ce compte (paquet du Store). La tache de " +
               $Name + " pointerait vers un chemin du profil de ce compte, illisible pour lui : Vigie ne " +
               "demarrerait pas, sans message. PowerShell 7 doit etre installe pour toute la machine " +
               "(winget install --id Microsoft.PowerShell --scope machine), puis ce compte reactive.")
    }
    # The account must be able to READ what its task launches.
    # THE PATH FOLLOWS THE DECLARED ENVIRONMENT. Always laying the shared installation would
    # start another account on production while the machine declares itself in development --
    # and Vigie would then report the very gap it had just created itself.
    # READABILITY COMES BEFORE PREFERENCE. The declared environment says where one WOULD LIKE
    # to run; what the account can READ says where one CAN run. Pointing Famille's task at the
    # repository -- unreadable to her from Git\ onwards -- produced exit code 64, "cannot open
    # the file", with not one log line.
    $targetSid = $null
    try { $targetSid = (Get-LocalUser -Name $Name -ErrorAction Stop).SID.Value } catch { }
    if (-not $targetSid) { throw ("Compte introuvable sur cette machine : " + $Name) }

    # THE SHARED INSTALLATION FIRST, ALWAYS. The declared environment says where what is
    # deployed comes from, not where it runs: a task launching a personal repository is
    # unreadable to the other accounts and disappears if the folder moves. The repository
    # serves as a fallback only when there is no shared installation at all -- and only for
    # the account that owns it.
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
    # 45 s: pwsh comes from the Store (MSIX) and is not always ready at the instant of logon.
    $trigger.Delay = 'PT45S'
    $niveau  = if ($account.admin) { 'Highest' } else { 'Limited' }
    $princ   = New-ScheduledTaskPrincipal -UserId ("$env:COMPUTERNAME\$Name") -LogonType Interactive -RunLevel $niveau
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                  -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $taskName = Get-VigieAccountTaskName -Name $Name
    # We OBSERVE (D43): a creation that does not throw is not a creation that happened. The
    # log keeps the trace of both, and the caller receives a real error.
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

# An account's order folder: that is where its client app looks, once a second.
function Get-AccountRunDir {
    param([Parameter(Mandatory)][string]$Account)
    $varRoot = Get-AccountVarRoot -Account $Account
    if (-not $varRoot) { return $null }
    return (Join-Path $varRoot 'run')
}

function Get-UserAccounts {
    param([switch]$Force, [string]$Backend = (Get-BackendRoot))
    @(Get-ComputerAccounts -Force:$Force -Backend $Backend | Where-Object { -not $_.technical })
}
