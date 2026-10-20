# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses: native
<#
    Intent: THE ACCESS RIGHTS WINDOWS LAYS ON A PATH: is a refusal there, refuse writing, take the refusal away,
    grant full control, hand ownership to the administrators. The mechanism and nothing else -- WHICH path and WHY
    belong to the subject that calls, and Vigie's own rights, who may run which action, are `rights.ps1`.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# AN ACCOUNT IS AIMED AT BY SID, NEVER BY NAME: Windows translates the names per language, and "SYSTEM" is not
# what a French installation calls it. icacls takes a SID when it is prefixed with a star.
function Get-AclSidArgument {
    param([Parameter(Mandatory)][string]$Sid)
    return ('*' + $Sid)
}

# IS A REFUSAL LAID ON THIS PATH?
#
# icacls is the authoritative source, because it is also what lays the refusal down. A single "(DENY)" entry is
# the answer, and "(DENY)" is NOT localised, so the reading holds whatever the language of Windows.
#
# The .NET fallback, for when icacls cannot be run, is narrower by construction: it reads the refusals and
# compares their account to the SID asked for. The two readings answer the same question on a path whose only
# refusal is the one we lay.
function Test-PathDenied {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sid)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $r = Invoke-Native -File 'icacls.exe' -Arguments @($Path)
        if ($r.Output -match '\(DENY\)') { return $true }
    } catch { }
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $wanted = New-Object System.Security.Principal.SecurityIdentifier($Sid)
        foreach ($ace in $acl.Access) {
            if ($ace.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Deny) { continue }
            try { if (($ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])) -eq $wanted) { return $true } } catch { }
        }
    } catch { }
    return $false
}

# FULL CONTROL, INHERITED BY WHAT THE FOLDER CONTAINS AND WILL CONTAIN -- (OI)(CI).
# Returns what the command answered: the caller is the one that says what was done (D43).
function Set-PathFullControl {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sid, [switch]$Quiet)
    $line = @($Path, '/grant', ((Get-AclSidArgument -Sid $Sid) + ':(OI)(CI)F'), '/t', '/c')
    if ($Quiet) { $line += '/q' }
    return (Invoke-Native -File 'icacls.exe' -Arguments $line)
}

# REFUSE WRITING: creating a file (WD), creating a folder (AD), deleting a child (DC). Reading is left alone, so
# whoever is refused still sees what is there -- it is the WRITING that must not happen.
function Add-PathWriteDenial {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sid, [switch]$Quiet)
    $line = @($Path, '/deny', ((Get-AclSidArgument -Sid $Sid) + ':(OI)(CI)(WD,AD,DC)'), '/t', '/c')
    if ($Quiet) { $line += '/q' }
    return (Invoke-Native -File 'icacls.exe' -Arguments $line)
}

# TAKE THE REFUSAL AWAY. Removing a refusal that is not there has no effect, which is what makes the gesture
# replayable.
function Remove-PathDenial {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sid, [switch]$Quiet)
    $line = @($Path, '/remove:d', (Get-AclSidArgument -Sid $Sid), '/t', '/c')
    if ($Quiet) { $line += '/q' }
    return (Invoke-Native -File 'icacls.exe' -Arguments $line)
}

# OWNERSHIP TO THE ADMINISTRATORS, down the whole tree. Without it the refusals below cannot be laid on a folder
# Windows owns: `/d O` answers the question takeown asks when it meets a folder it cannot read.
function Set-PathOwnerAdmins {
    param([Parameter(Mandatory)][string]$Path)
    return (Invoke-Native -File 'takeown.exe' -Arguments @('/f', $Path, '/r', '/a', '/d', 'O'))
}
