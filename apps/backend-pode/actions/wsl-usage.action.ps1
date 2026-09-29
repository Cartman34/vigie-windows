# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- needs no privilege Windows does not already grant (D65)
# @execution: session   -- WSL belongs to the session: the service account has no distribution
<#
    Action: what the WSL distributions really hold, seen from the inside.

    WHY IT EXISTS. A virtual disk never gives back the space freed inside it: 150,7 GB on C: on 28/09, for far less
    content, and the storage card could only see the file. Only a reading made INSIDE the distribution can tell the
    difference, and the server app has none -- it runs under a service account, where WSL does not exist.

    WHAT IT DOES NOT DO: start a distribution. Only those already running are read; starting a virtual machine to take
    a measurement would cost more than what is being measured.
#>
param([string]$Module, [hashtable]$Params)

$distributions = @()
try {
    $running = (& wsl.exe --list --running --quiet 2>$null) -replace "`0", '' | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
    foreach ($name in @($running)) {
        # df on the root, in bytes: one line to read, and nothing that depends on a human-readable layout.
        $lines = @(& wsl.exe -d $name -e df -B1 --output=size,used,target / 2>$null)
        foreach ($line in @($lines | Select-Object -Skip 1)) {
            $parts = @("$line".Trim() -split '\s+' | Where-Object { $_ })
            if ($parts.Count -lt 3) { continue }
            $size = 0; $used = 0
            if (-not [int64]::TryParse($parts[0], [ref]$size)) { continue }
            if (-not [int64]::TryParse($parts[1], [ref]$used)) { continue }
            $distributions += @{ name = $name; sizeBytes = $size; usedBytes = $used; mount = "$($parts[2])" }
            break
        }
    }
} catch {
    return @{ message = "Lecture WSL impossible : $($_.Exception.Message)"; result = @{ ok = $false } }
}

@{
    message = $(if ($distributions.Count) { "$($distributions.Count) distribution(s) lue(s)." } else { 'Aucune distribution WSL en marche.' })
    result  = @{ ok = $true; distributions = $distributions; at = (Get-Date).ToUniversalTime().ToString('o') }
}
