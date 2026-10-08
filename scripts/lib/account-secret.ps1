# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    account-secret.ps1 -- THE ACCOUNT'S SECRET: laying it down, reading it, and refusing to trust it when its
    rights no longer hold. Loadable on its own (no dependency on Pode).

    Intent: make sure that only the account itself can read what identifies it, and prove it at every read rather
    than trust the place it is stored in.
    Usage: dot-source it, then Get-AccountSecret / New-AccountSecret. The design:
    doc/progress/targeting/multi-account-server.md, section C7.

    WHY THIS FILE EXISTS. A secret everybody can read is not a secret, and no location is safe BY INHERITANCE --
    measured on this machine on 28/08:

      C:\ProgramData          the built-in Users group has read AND write
      %LOCALAPPDATA%          the account, SYSTEM, the Administrators -- AND a group added by a third-party tool,
                              with read access

    The second case is the more instructive: that profile is supposed to be private, and it already was not. So we
    trust no inheritance: the ACL is LAID DOWN, and CHECKED AGAIN at every read. A discrepancy counts as a
    compromise, not as a warning.

    What is allowed, and nothing else:
      - the owning account   : read and write
      - SYSTEM               : full (the service will need it)
      - the Administrators   : full (irreducible under Windows, and without consequence: an administrator can
                               already do everything)
#>

# The allowed identities, by their SID -- never by their name, which changes with the language of Windows.
$script:SecretAllowedSids = @(
    'S-1-5-18',        # SYSTEM
    'S-1-5-32-544'     # the Administrators (built-in group)
)

<#
    THE RULES OF AN ACL, THROUGH ONE SINGLE ROAD.

    Windows exposes those rules in two ways, and they do not say the same thing: "$acl.Access" sometimes returns an
    EMPTY collection on a descriptor that is nevertheless complete -- observed on 28/08, on the server side, while
    the same read from an ordinary session did show the three rules. The security check concluded from that that
    the owner could no longer read their own secret, and refused everything.

    So we wrap the system call instead of repeating it. GetAccessRules asks for the rules explicitly, inherited ones
    included, and returns them translated into SIDs. One single entry point, one single behaviour -- and the day
    Windows changes its mind, one single place to fix.
#>


function Get-AclAccessRules {
    param([Parameter(Mandatory)]$Acl)
    return @($Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
}

function Get-AccountSecretPath {
    param(
        # The root of the account's data. By default: the current account's.
        [string]$VarRoot = (Get-VarRoot)
    )
    Join-Path (Join-Path $VarRoot 'secrets') 'account.secret'
}

# Lays the WANTED ACL on a folder: inheritance cut, and only what we allow.
function Set-SecretFolderAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        # The SID of the account that owns the secret.
        [Parameter(Mandatory)][string]$OwnerSid
    )
    # WE WRITE THE RIGHTS SECTION ONLY. A security descriptor carries three: the rights, the owner, and the
    # auditing. Set-Acl writes all of them -- and laying down the auditing demands the SeSecurityPrivilege, which a
    # process that is not elevated does not have. The rights were applied correctly, but Windows complained every
    # time; where ErrorActionPreference is 'Stop', that complaint becomes a fatal error on an operation that
    # nevertheless succeeded.
    #
    # GetAccessControl/SetAccessControl with the Access section touch the rights only, and so demand nothing in
    # particular.

    $item = Get-Item -LiteralPath $Path -Force
    $acl = [System.IO.FileSystemAclExtensions]::GetAccessControl(
                $item, [System.Security.AccessControl.AccessControlSections]::Access)
    # INHERITANCE IS CUT, and the inherited rules are NOT copied over: that is exactly what let through a group
    # added by a third-party tool.
    $acl.SetAccessRuleProtection($true, $false)
    # We enumerate by SID: "$acl.Access" returns null entries on a descriptor loaded section by section, and
    # RemoveAccessRule then refuses to work.
    foreach ($rule in (Get-AclAccessRules -Acl $acl)) { [void]$acl.RemoveAccessRule($rule) }

    # THE INHERITANCE FLAGS ONLY EXIST ON A FOLDER. Setting them on a file makes the rule be rejected in silence:
    # the file ends up with a protected and EMPTY ACL, which nobody can read any more -- not even its owner.
    # Observed under test on 28/08, and that is precisely the kind of defect a reread does not see.
    $isFile  = Test-Path -LiteralPath $Path -PathType Leaf
    $inherit = if ($isFile) { [System.Security.AccessControl.InheritanceFlags]::None }
               else { [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' }
    $none    = [System.Security.AccessControl.PropagationFlags]::None
    $allow   = [System.Security.AccessControl.AccessControlType]::Allow

    foreach ($sid in (@($OwnerSid) + $script:SecretAllowedSids)) {
        try {
            $id = New-Object System.Security.Principal.SecurityIdentifier($sid)
            $rights = if ($sid -eq $OwnerSid) {
                [System.Security.AccessControl.FileSystemRights]'Read, Write, Delete'
            } else {
                [System.Security.AccessControl.FileSystemRights]::FullControl
            }
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $id, $rights, $inherit, $none, $allow)))
        } catch { }
    }
    [System.IO.FileSystemAclExtensions]::SetAccessControl($item, $acl)
}

# Are the rights still the ones we laid down? Returns $null if so, otherwise what is wrong.
#
# CHECKING AT WRITE TIME IS NOT ENOUGH: a file's rights change after it is created -- a tool, a group policy, a
# human hand. A secret whose rights are checked only once is a secret whose state we do not know.
function Test-SecretAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerSid
    )
    if (-not (Test-Path -LiteralPath $Path)) { return "le secret n'existe pas" }
    try {
        $acl = Get-Acl -LiteralPath $Path
    } catch { return ("droits illisibles : " + $_.Exception.Message) }

    if (-not $acl.AreAccessRulesProtected) { return "l'héritage n'est pas coupé : des droits peuvent arriver du dossier parent" }

    # WE ENUMERATE BY SID, NEVER BY "$acl.Access".
    #
    # Depending on the context, "$acl.Access" returns an EMPTY collection while the file does carry its rules:
    # observed on 28/08, the server refused every secret saying the owner could no longer read, while the same
    # check passed from an ordinary session on the same file. An empty collection looks like "no rights at all" --
    # the worst of false positives for a security check, since it cries compromise on a healthy installation.
    #
    # GetAccessRules asks for the rules explicitly, inherited ones included, and returns them translated into
    # SIDs: no more empty collection, and no more translation to do ourselves.


    $rules = Get-AclAccessRules -Acl $acl

    # AN EMPTY ACL IS NOT A SAFE ACL: it is a file nobody can read. The first attempt produced exactly that, and
    # the check had let it through because it was only looking for intruders.
    $ownerCanRead = $false
    $allowed = @($OwnerSid) + $script:SecretAllowedSids
    foreach ($rule in $rules) {
        if ($rule.IdentityReference.Value -eq $OwnerSid -and
            ($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read)) {
            $ownerCanRead = $true
        }
    }
    if (-not $ownerCanRead) {
        # A SECURITY REFUSAL MUST SAY WHAT IT SAW. Without the ACL it observed, one has to guess -- and one does
        # not guess on a security incident.
        $vues = @($rules | ForEach-Object { $_.IdentityReference.Value + '=' + $_.FileSystemRights })
        return ("le compte propriétaire n'a plus le droit de lire son propre secret [attendu " +
                $OwnerSid + " ; vu " + ($vues -join ' | ') + "]")
    }

    foreach ($rule in $rules) {
        if ($allowed -notcontains $rule.IdentityReference.Value) {
            return ("un tiers y a accès : " + $rule.IdentityReference.Value)
        }
    }
    return $null
}

<#
    A SECRET FILE READ BY ITS OWNER, UNDER THE RULE OF TARGET C7 -- used for the local API token.

    Created with its rights when missing. Read after checking them: a third party with access means compromised -- the
    file is revoked, a new value issued, and $script:SecretIncident says what was seen for the caller to log. Rights
    that are merely inherited, with no third party, are closed again WITHOUT reissuing: a token files written before
    14/09 all look like that, and reissuing on every read would cut the server off from its pages.
    -NewValue builds a fresh value. Returns the value.
#>
function Get-ProtectedSecretFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerSid,
        [Parameter(Mandatory)][scriptblock]$NewValue
    )
    $script:SecretIncident = $null
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path -LiteralPath $Path) {
        $acl = Get-Acl -LiteralPath $Path
        $allowed = @($OwnerSid) + $script:SecretAllowedSids
        $third = @(Get-AclAccessRules -Acl $acl | Where-Object { $allowed -notcontains $_.IdentityReference.Value } |
                   ForEach-Object { $_.IdentityReference.Value } | Select-Object -Unique)
        if (-not $third.Count) {
            if (Test-SecretAcl -Path $Path -OwnerSid $OwnerSid) { Set-SecretFolderAcl -Path $Path -OwnerSid $OwnerSid }
            return ([System.IO.File]::ReadAllText($Path)).Trim()
        }
        $script:SecretIncident = ("un tiers y a accès : " + ($third -join ', '))
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    $value = "$(& $NewValue)"
    [System.IO.File]::WriteAllText($Path, $value, (New-Object System.Text.UTF8Encoding($false)))
    Set-SecretFolderAcl -Path $Path -OwnerSid $OwnerSid
    return $value
}

# Writes a fresh secret, with its rights. Returns the secret in clear -- it is up to the caller not to log it.
function New-AccountSecret {
    param(
        [string]$VarRoot = (Get-VarRoot),
        [string]$OwnerSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    )
    $file = Get-AccountSecretPath -VarRoot $VarRoot
    $dir  = Split-Path $file -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-SecretFolderAcl -Path $dir -OwnerSid $OwnerSid

    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $secret = [Convert]::ToBase64String($bytes)
    [System.IO.File]::WriteAllText($file, $secret, (New-Object System.Text.UTF8Encoding($false)))
    Set-SecretFolderAcl -Path $file -OwnerSid $OwnerSid
    return $secret
}

# Reads the secret AFTER checking its rights. Returns $null if the file is missing; THROWS if the rights no longer
# hold -- that is an incident, not a nominal case.
function Get-AccountSecret {
    param(
        [string]$VarRoot = (Get-VarRoot),
        [string]$OwnerSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value,
        # Recreate the secret if it is missing.
        [switch]$Create
    )
    $file = Get-AccountSecretPath -VarRoot $VarRoot
    if (-not (Test-Path -LiteralPath $file)) {
        if ($Create) { return (New-AccountSecret -VarRoot $VarRoot -OwnerSid $OwnerSid) }
        return $null
    }
    $wrong = Test-SecretAcl -Path $file -OwnerSid $OwnerSid
    if ($wrong) {
        # COMPROMISED: revoked, reissued, and the incident logged (target C7, point 3). Until 14/09 the read only threw,
        # and nothing ever reissued: the account stayed without a session. The owner's own read (-Create) now does it;
        # the server's read of another account still refuses, and that account's next read reissues.
        $incident = "Secret de compte compromis (" + $wrong + ")"
        if (-not $Create) { throw ($incident + " : il doit être révoqué et réémis.") }
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            try { Write-Log -Level 'ERROR' -Name 'session' -Message ($incident + " : révoqué et réémis.") } catch { }
        }
        Remove-Item -LiteralPath $file -Force -ErrorAction Stop
        return (New-AccountSecret -VarRoot $VarRoot -OwnerSid $OwnerSid)
    }
    return ([System.IO.File]::ReadAllText($file)).Trim()
}

# The fingerprint is all the server needs to keep: comparing a fingerprint is enough to recognise, and reading the
# server's table then gives nothing usable.
function Get-SecretFingerprint {
    param([Parameter(Mandatory)][string]$Secret)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Secret))
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
