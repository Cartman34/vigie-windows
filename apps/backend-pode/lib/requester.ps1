# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: sessions
<#
    Intent: WHO THIS COMPUTATION IS FOR: the account a probe is computing for, the one the request comes from, and the one an action is launched by. Read by whoever keeps a result per account -- the settings, the rights, the state -- and that is why it is not inside any of them.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
