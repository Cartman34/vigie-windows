# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: WHAT AN ACTION TOUCHES: the resources each action holds while it runs, declared once. The shape of an action reads it (contract) and so does the operation that takes them (operations), which is why it sits below both.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

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
    # THE INVENTORY LAUNCHES EVERY MANAGER to ask it its version, in an account's session. It declared nothing,
    # so it ran for 24 minutes beside an upgrade of the same manager without either knowing (16/10). It is a
    # reading OF THE MANAGERS, not of a cache: it takes them up for as long as it asks.
    'pkg-inventory'        = @('paquets')
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
