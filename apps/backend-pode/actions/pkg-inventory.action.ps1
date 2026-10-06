# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- needs no privilege Windows does not already grant (D65)
# @execution: session   -- a package manager belongs to the session that installed it
<#
    Action: which package managers this account really has, and which version.

    WHY IT EXISTS. Measured on 05/10: the server app saw two managers, Chocolatey and pip, both installed
    machine-wide. It did not see winget -- the Windows package manager -- although this account has it, because its
    executable lives in the account's own profile (`AppData\Local\Microsoft\WindowsApps\winget.exe`) and the service
    account's PATH never names that folder. The card said nothing about the main manager of the machine.

    WHAT IT DOES. It resolves every manager of the catalogue and reads its version, in the session of whoever asks,
    with their PATH. Nothing is installed, nothing is updated: this is a reading.

    WHAT IT DOES NOT DO: look for updates. That costs network and seconds, it is the job of `pkg-check-updates`, and
    it follows the protocol of operations.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$managers = @()
foreach ($mg in (Get-PackageManagerCatalog)) {
    $cmd = $null
    try { $cmd = Get-Command $mg.id -ErrorAction SilentlyContinue } catch { }
    if (-not $cmd) { continue }
    $source = if ($cmd.Source) { "$($cmd.Source)" } else { "$($mg.id)" }
    # THE VERSION, read the same way the probe reads it, so that both tell the same story. A manager that answers
    # nothing readable is still present: present and unreadable is a fact, absent is another.
    $version = 'installé'
    try {
        if (@($mg.verArgs).Count -gt 0 -and $cmd.Source) {
            $r = Invoke-Native -File $cmd.Source -Arguments $mg.verArgs
            if ($r.Ok -and $r.Output) {
                $first = (($r.Output -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
                $match = [regex]::Match($first, '\d+(?:\.\d+)+')
                if ($match.Success) { $version = $match.Value } elseif ($first) { $version = $first }
            }
        }
    } catch { }
    $managers += @{ id = "$($mg.id)"; source = $source; version = $version }
}

@{
    message = $(if ($managers.Count) { "$($managers.Count) gestionnaire(s) de paquets lu(s)." } else { 'Aucun gestionnaire de paquets sur ce compte.' })
    result  = @{ ok = $true; managers = $managers; at = (Get-Date).ToUniversalTime().ToString('o') }
}
