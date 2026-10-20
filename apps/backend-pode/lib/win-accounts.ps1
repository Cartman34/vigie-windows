# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: paths
<#
    Intent: THE WINDOWS ACCOUNTS OF THIS COMPUTER, as facts: who exists, the SID of each, where its registry hive and its own var folder are, whether it is an administrator, and which account a given process runs as. Read by whoever needs to know whose something is -- the rights, the sessions, the games, an install lock. Vigie's own account gestures are accounts.ps1.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
    the service account, every place that said $env:USERNAME meaning "the person in front of the
    screen" names the service -- and on 29/08 the Accounts card therefore marked the service account as the reader,
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


function Get-UserRegistryRoots {
    <# The registry hives of the REAL signed-in users, in the form
       'Registry::HKEY_USERS\<SID>'.

       WHY: the server runs under the service account, so HKCU names the service's hive --
       nobody's. A probe reading a per-user setting (Steam libraries, the games the Game Bar
       knows, an application's preferences) must NEVER go through HKCU: it would look beside
       the point and see nothing. Seen on 01/09: Assassin's Creed Odyssey, played on the
       Famille account, was not recognised as a game, the probe questioning the service's
       HKCU.

       .DEFAULT, the _Classes views and the system accounts (S-1-5-18/19/20) are left out. A
       hive that is not loaded, its user being signed out, does not appear: that is intended,
       we do not mount absent people's hives.
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
