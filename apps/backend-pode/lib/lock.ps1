# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: A LOCK SHARED BY EVERY ACCOUNT ON THE COMPUTER, named after the file it protects. One door: nobody
    builds a Mutex by hand. The right is granted as the lock is created, so the elevated service and an ordinary
    client app can both take it -- without that, the app would write with no lock at all, which is worse than the
    disease. If nothing works it answers nothing, and the caller writes anyway: a written file with no lock beats
    no file.
    Usage: dot-sourced by common.ps1, never run on its own. It takes the path it is given and calls nothing of
    the project.
#>

<#
    THE NAME TAKES THE FOLDER INTO ACCOUNT, not only the file.

    Since the history was split by day, every file of a given day is called the same thing (2026-09-01.jsonl): a
    lock named after the file alone would make the disk measurement wait because the network one is writing. Two
    measurements have nothing to share.

    The FAMILY is what separates two kinds of file that happen to share a name -- a series of points and a state
    cache are not waiting for each other.

    AND IT COVERS THE WHOLE COMPUTER, not one session.

    It was named "Local\...". A Local lock exists ONLY inside one Windows session: the server app writes from the
    service's session, a client app from its account's, and each took a DIFFERENT lock bearing the same name. The
    one that can really hurt is the purge, which REWRITES a file while another session appends to it. That is
    exactly the hole `store.ps1` had kept, with its own "Local\VigieState_" lock -- the same mechanism written a
    second time, and written without its rights.
#>
function Get-LockName {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Family)
    $leaf   = Split-Path $Path -Leaf
    $parent = Split-Path (Split-Path $Path -Parent) -Leaf
    return ('Global\Vigie' + $Family + '_' + (($parent + '_' + $leaf) -replace '[^A-Za-z0-9]', '_'))
}

<#
    THE LOCK ITSELF, OPEN TO EVERY ACCOUNT ON THE COMPUTER.

    One door: everything that serialises a write comes through here, and nobody builds a Mutex by hand. The right
    is granted as it is created -- anyone may take it and give it back -- otherwise only the service account that
    created it could use it at all.

    If none of that works, it returns nothing and the caller writes anyway: a written file with no lock beats no
    file, and the writing itself is built to hold (see Add-HistoryLine).
#>
function Get-NamedLock {
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
    WHY TAKING AND RELEASING IS NOT IN HERE.

    The four places that lock all wrap the same five lines -- wait, treat an ABANDONED lock as taken because its
    holder died mid-write and refusing would mean never writing again, release, dispose. Wrapping them in a
    function taking a scriptblock would change what those bodies MEAN: one of them `continue`s the enclosing loop
    when the lock is refused, another accumulates into a variable of the calling scope, which a scriptblock copies
    instead of sharing. The duplication worth removing is the lock's NAME and its CREATION, which `store.ps1` had
    written a second time -- and written without its rights.
#>
