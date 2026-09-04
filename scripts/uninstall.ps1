# @author Florent HAZARD <f.hazard@sowapps.com>
<#
.SYNOPSIS
    Removes Vigie from this computer, entirely.

.DESCRIPTION
    Target: doc/progress/targeting/uninstall.md. This script removes what the installation
    put in place, in an order that matters, and SAYS what it could not remove.

    IT MUST WORK WHEN NOTHING ELSE DOES. One uninstalls precisely on the day the server app
    is dead, or the installation is half undone. So it depends on as little as possible: the
    shared library when it is readable, and nothing but Windows otherwise.

    IDEMPOTENT: something already gone is not a failure. Running it twice must succeed
    twice.

    WHAT IS NEVER REMOVED: the prerequisites. PowerShell 7 and the Pode module may have been
    installed by the setup, but we cannot know who else on this machine uses them.

.PARAMETER Yes
    Asks nothing. The announcement window was already shown by uninstall.cmd, before the
    elevation.

.NOTES
    Exit codes: 0 = everything removed; 2 = something is left (and it is named).
#>
[CmdletBinding()]
param([switch] $Yes)

$ErrorActionPreference = 'Stop'
# Management scripts live in scripts/; the apps live in apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # the same display as everywhere else
$backend  = Join-Path $repoRoot 'apps/backend-pode'    # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

Write-Title (Get-Label 'uninstall.titre')

if (-not (Test-IsElevated)) {
    Write-Fail (Get-Label 'uninstall.elevation-requise')
    exit 2
}

# WHAT STAYS BEHIND IS NAMED. An uninstall that fails halfway is the worst state of all:
# without the list of what remains, nobody can finish the job by hand.
$leftBehind = @()
function Add-Leftover {
    param([Parameter(Mandatory)][string]$What, [string]$How = '')
    $script:leftBehind += [pscustomobject]@{ What = $What; How = $How }
}

# WHERE IS THE INSTALLATION? Read ONCE, up here: the git step needs it to name our own
# declarations, and the folder step to remove it. Reading it twice risks two answers.
$shared = $null
try { $shared = Get-SharedInstallPath } catch { }

# --- 0. Stop what is still running ----------------------------------------------------
#
# NOTHING IS REMOVED UNDER A RUNNING PROGRAM. The server app, its residents and the client
# apps hold files open in the folder we are about to delete; and a client app started by
# hand outlives the task that would have carried it away. The installation already stops
# them all before replacing files -- the same three calls, for the same reason.
#
# A failure here is not fatal: it is named, and the folder step will say what it could not
# remove. Stopping is a precaution, not a permission.
Write-Step (Get-Label 'uninstall.etape-arret')
try {
    $stoppedTasks = @(Stop-TrayTasks -Backend $backend)
    if ($stoppedTasks.Count) { Write-Ok (Get-Label 'uninstall.app-clientes-arretees' (($stoppedTasks | ForEach-Object { $_.name }) -join ', ')) }
} catch { Write-Warn (Get-Label 'uninstall.arret-partiel' $_.Exception.Message) }
try {
    $standalone = Stop-StandaloneTrays
    if ($standalone -gt 0) { Write-Ok (Get-Label 'uninstall.app-clientes-hors-tache' $standalone) }
} catch { Write-Warn (Get-Label 'uninstall.arret-partiel' $_.Exception.Message) }
$serverStopped = $false
try { $serverStopped = [bool](Stop-ServerApp -Backend $backend) } catch { }
if ($serverStopped) {
    Write-Ok (Get-Label 'uninstall.app-serveur-arretee')
} else {
    Write-Warn (Get-Label 'uninstall.app-serveur-toujours-la')
}

# --- 1. The Windows Update lock ------------------------------------------------------
#
# FIRST, AND THE ORDER IS NOT A DETAIL. Vigie denies SYSTEM access to the Windows Update
# task folders; leaving that denial behind locks the computer for good, with nothing left to
# explain it or lift it. While Vigie is still here she can do it cleanly -- afterwards it
# would have to be done by hand.
Write-Step (Get-Label 'uninstall.etape-verrou')
$lockLifted = $false
try { $lockLifted = [bool](Set-UpdateLock -Etat 'leve' -Backend $backend) } catch { $lockLifted = $false }
if ($lockLifted) {
    Write-Ok (Get-Label 'uninstall.verrou-leve')
} else {
    # WE CHECK RATHER THAN BELIEVE: the lock may never have been placed.
    $stillLocked = $true
    try { $stillLocked = [bool](Test-UpdateTasksAclLock -Backend $backend) } catch { }
    if ($stillLocked) {
        Write-Fail (Get-Label 'uninstall.verrou-reste')
        Add-Leftover -What (Get-Label 'uninstall.reste-verrou') -How (Get-Label 'uninstall.reste-verrou-comment')
    } else {
        Write-Ok (Get-Label 'uninstall.verrou-absent')
    }
}

# --- 2 and 3. The scheduled tasks ----------------------------------------------------
#
# ALL OF VIGIE'S, NOT A HAND-WRITTEN LIST. "Vigie - Serveur", "Vigie" and "Vigie - <account>":
# the prefix names them, and an account added tomorrow is taken too.
Write-Step (Get-Label 'uninstall.etape-taches')
$tasks = @()
try {
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
               Where-Object { "$($_.TaskName)" -eq 'Vigie' -or "$($_.TaskName)".StartsWith('Vigie - ') })
} catch { }
if (-not $tasks.Count) {
    Write-Ok (Get-Label 'uninstall.taches-aucune')
} else {
    foreach ($t in $tasks) {
        $name = "$($t.TaskName)"
        try {
            Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
            Write-Ok (Get-Label 'uninstall.tache-retiree' $name)
        } catch {
            Write-Fail (Get-Label 'uninstall.tache-reste' $name $_.Exception.Message)
            Add-Leftover -What (Get-Label 'uninstall.reste-tache' $name) `
                         -How (Get-Label 'uninstall.reste-tache-comment' $name)
        }
    }
}

# --- 4 and 5. The service account, and the line that hides it ------------------------
#
# THE INNER ORDER MATTERS TOO: the registry value goes BEFORE the account. It names an
# account; left behind, it would point at one that no longer exists.
Write-Step (Get-Label 'uninstall.etape-compte')
$serviceAccount = Get-ServiceAccountName
$hideKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
try {
    if (Test-Path -LiteralPath $hideKey) {
        $prop = Get-ItemProperty -LiteralPath $hideKey -Name $serviceAccount -ErrorAction SilentlyContinue
        if ($prop) {
            Remove-ItemProperty -LiteralPath $hideKey -Name $serviceAccount -ErrorAction Stop
            Write-Ok (Get-Label 'uninstall.registre-retire')
        }
    }
} catch {
    Write-Fail (Get-Label 'uninstall.registre-reste' $_.Exception.Message)
    Add-Leftover -What (Get-Label 'uninstall.reste-registre') -How (Get-Label 'uninstall.reste-registre-comment' $serviceAccount)
}

# THE PROFILE IS LOCATED BEFORE THE ACCOUNT GOES: afterwards nothing ties the folder to the
# vanished account any more.
$serviceProfile = $null
try {
    $account = Get-LocalUser -Name $serviceAccount -ErrorAction SilentlyContinue
    if ($account) {
        $sid = "$($account.SID.Value)"
        $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
        if (Test-Path -LiteralPath $key) {
            $serviceProfile = "$((Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).ProfileImagePath)"
        }
        Remove-LocalUser -Name $serviceAccount -ErrorAction Stop
        Write-Ok (Get-Label 'uninstall.compte-retire' $serviceAccount)
    } else {
        Write-Ok (Get-Label 'uninstall.compte-absent' $serviceAccount)
    }
} catch {
    Write-Fail (Get-Label 'uninstall.compte-reste' $serviceAccount $_.Exception.Message)
    Add-Leftover -What (Get-Label 'uninstall.reste-compte' $serviceAccount) `
                 -How (Get-Label 'uninstall.reste-compte-comment' $serviceAccount)
}

# --- 6. The service account's profile -------------------------------------------------
#
# DELETING AN ACCOUNT DOES NOT DELETE ITS PROFILE. The service's clone, cache and secrets
# live there: leaving them is leaving Vigie on the disk under another name.
if ($serviceProfile -and (Test-Path -LiteralPath $serviceProfile)) {
    try {
        Remove-Item -LiteralPath $serviceProfile -Recurse -Force -ErrorAction Stop
        Write-Ok (Get-Label 'uninstall.profil-retire' $serviceProfile)
    } catch {
        Write-Warn (Get-Label 'uninstall.profil-reste' $serviceProfile)
        Add-Leftover -What (Get-Label 'uninstall.reste-profil' $serviceProfile) `
                     -How (Get-Label 'uninstall.reste-profil-comment')
    }
}

# --- 7b. The install folder declaration -----------------------------------------------
#
# IT IS READ FIRST by Get-SharedInstallPath: left behind, it would point everyone at a
# folder that has been deleted.
try {
    $declKey = Get-InstallPathDeclarationKey
    if (Test-Path -LiteralPath $declKey) {
        Remove-Item -LiteralPath $declKey -Recurse -Force -ErrorAction Stop
        Write-Ok (Get-Label 'uninstall.declaration-retiree')
    }
} catch {
    Write-Warn (Get-Label 'uninstall.declaration-reste' $_.Exception.Message)
    Add-Leftover -What (Get-Label 'uninstall.reste-declaration') -How (Get-Label 'uninstall.reste-declaration-comment')
}

# --- 7. This computer's safe.directory declarations ------------------------------------
#
# PLACED SO THE SERVICE ACCOUNT COULD READ THE REPOSITORY. Afterwards they name paths with
# no reason left to sit in this computer's git configuration.
Write-Step (Get-Label 'uninstall.etape-git')
# WHAT WE DECLARED, NOT WHAT LOOKS LIKE OURS. Filtering on the word "vigie" would carry off
# the declaration of a same-named repository that owes us nothing. Set-GitSafeDirectory adds
# exactly two entries per repository -- "<repo>" and "<repo>/.git", in forward slashes -- and
# those, and nothing else, are what we remove.
$ourRepos = @()
foreach ($candidate in @($shared, (Get-LocalRepoPath -Backend $backend))) {
    if (-not $candidate) { continue }
    $normalized = "$candidate".Replace([char]92, [char]47).TrimEnd([char]47)
    $ourRepos += $normalized
    $ourRepos += ($normalized + '/.git')
}
$declared = @()
try {
    $declared = @(Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--get-all', 'safe.directory')) |
                Where-Object { "$_".Trim() }
} catch { }
$repoDeclared = @($declared | Where-Object { $ourRepos -contains "$_".Replace([char]92, [char]47).TrimEnd([char]47) })
if (-not $repoDeclared.Count) {
    Write-Ok (Get-Label 'uninstall.git-aucune')
} else {
    foreach ($value in $repoDeclared) {
        $null = Invoke-Git -Path $env:SystemDrive -Arguments @('config', '--system', '--unset-all', 'safe.directory', ([regex]::Escape("$value")))
        if (Get-GitLastError) {
            Write-Warn (Get-Label 'uninstall.git-reste' "$value")
            Add-Leftover -What (Get-Label 'uninstall.reste-git' "$value") `
                         -How (Get-Label 'uninstall.reste-git-comment' "$value")
        } else {
            Write-Ok (Get-Label 'uninstall.git-retiree' "$value")
        }
    }
}

# --- 9. Every account's data -----------------------------------------------------------
#
# THE DISK IS THE AUTHORITY, NOT THE ACCOUNT LIST. We look for data folders in EVERY profile:
# a deleted account leaves its profile behind, and Vigie wrote there. Trusting the accounts
# that still exist -- or worse, the active ones -- would leave those folders.
#
# Announced BEFORE the elevation by uninstall.cmd: here we carry out what was accepted.
Write-Step (Get-Label 'uninstall.etape-donnees')
$profilesRoot = Join-Path $env:SystemDrive 'Users'
$dataFolders = @()
if (Test-Path -LiteralPath $profilesRoot) {
    foreach ($p in @(Get-ChildItem -LiteralPath $profilesRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        $candidate = Join-Path $p.FullName 'AppData\Local\Sowapps\Vigie'
        # -ErrorAction SilentlyContinue IS NOT A MATTER OF STYLE: on a profile whose ACL
        # denies us, Test-Path THROWS, and "Stop" would abort the whole uninstall over a
        # folder we only meant to look at. Measured dry on 03/09 on the service profile.
        if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) { $dataFolders += $candidate }
    }
}
if (-not $dataFolders.Count) {
    Write-Ok (Get-Label 'uninstall.donnees-aucune')
} else {
    foreach ($folder in $dataFolders) {
        try {
            Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
            Write-Ok (Get-Label 'uninstall.donnees-retirees' $folder)
        } catch {
            Write-Warn (Get-Label 'uninstall.donnees-restent' $folder)
            Add-Leftover -What (Get-Label 'uninstall.reste-donnees' $folder) `
                         -How (Get-Label 'uninstall.reste-donnees-comment')
        }
    }
    # The "Sowapps" folder goes only if it is EMPTY: another product from the same publisher
    # may live there, and it is not ours to carry off.
    foreach ($folder in $dataFolders) {
        $parent = Split-Path $folder -Parent
        try {
            if ((Test-Path -LiteralPath $parent) -and -not @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue).Count) {
                Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }
}

# --- 8. The shared install folder ------------------------------------------------------
#
# LAST, BECAUSE IT HOLDS WHAT IS RUNNING. This script may live inside it: one does not saw
# the branch before finishing the rest. When we do run from that folder, the removal is left
# to a detached process that waits for us to exit.
Write-Step (Get-Label 'uninstall.etape-dossier')
if (-not $shared -or -not (Test-Path -LiteralPath $shared -ErrorAction SilentlyContinue)) {
    Write-Ok (Get-Label 'uninstall.dossier-absent')
} else {
    <#
        WE NEVER DELETE A REPOSITORY. THIS IS THE GUARD THAT MATTERS MOST.

        Get-SharedInstallPath falls back to "the current folder, if every account can read
        it" -- and EVERY folder created at the root of C: inherits Users:ReadAndExecute
        (measured on 03/09). On a machine where Vigie runs from C:\Dev\vigie-windows, that
        fallback would hand this script a git repository, and it would delete it: recursively,
        forced, without a word.

        An installation is a COPY. A repository is somebody's work. The presence of .git is
        the difference, and it settles the question before anything is removed.
    #>
    if (Test-Path -LiteralPath (Join-Path $shared '.git') -ErrorAction SilentlyContinue) {
        Write-Warn (Get-Label 'uninstall.dossier-est-un-depot' $shared)
        Add-Leftover -What (Get-Label 'uninstall.reste-depot' $shared) -How (Get-Label 'uninstall.reste-depot-comment')
        $shared = $null
    }
}
<#
    NOR DO WE TOUCH WHAT WAS USED TO INSTALL.

    The repository or the extracted archive the person kept on their disk belongs to them:
    uninstalling Vigie must not carry away the means of installing her again. Both are
    declared by the setup -- SourcePath for a repository, InstallSource for anything else --
    and either one is enough to spare the folder.
#>
if ($shared) {
    $origins = @()
    try {
        $conf = Get-Config -Backend $backend
        foreach ($candidate in @("$($conf.SourcePath)", "$($conf.InstallSource)")) {
            if ("$candidate".Trim()) { $origins += "$candidate".TrimEnd([char]92).ToLowerInvariant() }
        }
    } catch { }
    if ($origins -contains "$shared".TrimEnd([char]92).ToLowerInvariant()) {
        Write-Warn (Get-Label 'uninstall.dossier-est-la-source' $shared)
        Add-Leftover -What (Get-Label 'uninstall.reste-source' $shared) -How (Get-Label 'uninstall.reste-source-comment')
        $shared = $null
    }
}
if ($shared) {
}
if ($shared) {
    <#
        INSTALLED ELSEWHERE: WE REMOVE OUR OWN THINGS, NOT THE FOLDER THAT HOLDS THEM.

        Under Program Files the folder is ours alone -- it was created for Vigie -- so it goes
        whole. A chosen folder is another matter: "D:\Outils" can be passed as the install
        path and hold a dozen other tools; deleting it whole would carry them away.

        So elsewhere we remove exactly what we put there (Get-InstallOwnEntries), then the
        folder itself IF it is empty. What remains is not a failure: it is somebody's, and it
        is said rather than deleted.
    #>
    $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    $underProgramFiles = $false
    foreach ($base in $programFiles) {
        if ("$shared".ToLowerInvariant().StartsWith("$base".TrimEnd([char]92).ToLowerInvariant() + [char]92)) { $underProgramFiles = $true }
    }
    $runningFromShared = $repoRoot.TrimEnd([char]92).ToLowerInvariant() -eq "$shared".TrimEnd([char]92).ToLowerInvariant()
    if (-not $underProgramFiles -and -not $runningFromShared) {
        $ours = @(Get-InstallOwnEntries)
        $foreign = @()
        foreach ($entry in @(Get-ChildItem -LiteralPath $shared -Force -ErrorAction SilentlyContinue)) {
            if ($ours -notcontains $entry.Name) { $foreign += $entry.Name; continue }
            try { Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop }
            catch {
                $foreign += $entry.Name
                Add-Leftover -What (Get-Label 'uninstall.reste-element' $entry.FullName) `
                             -How (Get-Label 'uninstall.reste-element-comment')
            }
        }
        if ($foreign.Count) {
            Write-Ok (Get-Label 'uninstall.dossier-partiel' $shared ($foreign -join ', '))
        } else {
            try { Remove-Item -LiteralPath $shared -Force -ErrorAction Stop; Write-Ok (Get-Label 'uninstall.dossier-retire' $shared) }
            catch { Write-Ok (Get-Label 'uninstall.dossier-vide-reste' $shared) }
        }
        $shared = $null
    }
}
if ($shared) {
    if (-not $runningFromShared) {
        try {
            Remove-Item -LiteralPath $shared -Recurse -Force -ErrorAction Stop
            Write-Ok (Get-Label 'uninstall.dossier-retire' $shared)
        } catch {
            Write-Fail (Get-Label 'uninstall.dossier-reste' $shared $_.Exception.Message)
            Add-Leftover -What (Get-Label 'uninstall.reste-dossier' $shared) `
                         -How (Get-Label 'uninstall.reste-dossier-comment' $shared)
        }
    } else {
        # A DETACHED PROCESS, AND NOTHING MORE: it waits until we have let go, then deletes.
        # Values travel RAW -- Start-ChildProcess is what quotes them (D116).
        # IT REPORTS BACK. Without a log, a failure of this last removal would exist for
        # nobody: the script is already over when it happens, and "what stays behind is
        # named" cannot stop at the door of the last folder.
        $waiter = @'
param([int]$ParentPid, [string]$Folder, [string]$Report)
while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 300 }
Start-Sleep -Seconds 1
$erreur = $null
try { Remove-Item -LiteralPath $Folder -Recurse -Force -ErrorAction Stop }
catch { $erreur = "$($_.Exception.Message)" }
if (Test-Path -LiteralPath $Folder) {
    if (-not $erreur) { $erreur = 'le dossier est toujours la' }
    [IO.File]::WriteAllText($Report, (Get-Date).ToString('s') + ' -- ' + $Folder + ' : ' + $erreur,
                            (New-Object Text.UTF8Encoding($false)))
}
'@
        $waiterFile = Join-Path ([IO.Path]::GetTempPath()) ('vigie-uninstall-' + [guid]::NewGuid().ToString('N') + '.ps1')
        [System.IO.File]::WriteAllText($waiterFile, $waiter, (New-Object System.Text.UTF8Encoding($true)))
        $pwsh = (Get-Process -Id $PID).Path
        if (-not $pwsh) { $pwsh = 'powershell.exe' }
        $reportFile = Join-Path ([IO.Path]::GetTempPath()) 'vigie-uninstall-reste.txt'
        Remove-Item -LiteralPath $reportFile -Force -ErrorAction SilentlyContinue
        $null = Start-ChildProcess -FilePath $pwsh `
                    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $waiterFile,
                                 '-ParentPid', $PID, '-Folder', $shared, '-Report', $reportFile) `
                    -Options @{ WindowStyle = 'Hidden' }
        Write-Ok (Get-Label 'uninstall.dossier-differe' $shared)
        Write-Detail (Get-Label 'uninstall.dossier-differe-rapport' $reportFile)
    }
}

# --- Verdict ---------------------------------------------------------------------------
if (-not $leftBehind.Count) {
    Write-Outcome -What (Get-Label 'uninstall.verdict-complet')
    exit 0
}
Write-Fail (Get-Label 'uninstall.verdict-partiel' $leftBehind.Count)
foreach ($x in $leftBehind) {
    Write-Detail ('- ' + $x.What)
    if ($x.How) { Write-Detail ('  ' + $x.How) }
}
Write-Outcome -What (Get-Label 'uninstall.verdict-partiel-titre')
exit 2
