# @author Florent HAZARD <f.hazard@sowapps.com>
# @rights: all   -- needs no privilege Windows does not already grant (D65)
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

<#
    AND WHAT WSL ITSELF HAS TO SAY, brought back with the measurement.

    WSL speaks only on the console of whoever runs it: nothing of it reaches the Windows journal. Its warnings
    were therefore visible to nobody but the person typing -- a key written in the wrong section of `.wslconfig`
    was ignored for weeks, and the reclaiming of memory it was meant to switch on never ran.

    It has to be asked HERE: the configuration and the distributions belong to the account, and the server app
    runs under a service account that has neither. `--status` and `--version` answer without starting anything,
    and both carry a deadline: a cold WSL can be slow, and being patient is a choice, not a risk.
#>
$messages = @()
$timedOut = $false
foreach ($question in @(@('--status'), @('--version'))) {
    $r = Invoke-Native -File 'wsl.exe' -Arguments $question -TimeoutSeconds 30
    if ($r.TimedOut) { $timedOut = $true; continue }
    foreach ($line in @("$($r.Output)" -split "`r?`n")) {
        # WSL PREFIXES WHAT IT HAS TO SAY WITH ITS OWN NAME. Everything else is the answer we asked for.
        $t = "$line".Trim() -replace "`0", ''
        if ($t -match '^wsl\s*:\s*(.+)$') { $messages += $Matches[1].Trim() }
    }
}
$messages = @($messages | Select-Object -Unique)

# WHICH START OF THE VIRTUAL MACHINE WE ARE TALKING ABOUT. WSL reads its configuration when it STARTS, and says
# what it thinks of it then -- asked later, while it runs, it repeats nothing. So what it said is only true of
# the instance that was up at the time, and the reader needs to know which one.
$vmStarted = ''
foreach ($vm in @(Get-Process -Name 'vmmemWSL', 'wslservice' -ErrorAction SilentlyContinue)) {
    try { $vmStarted = $vm.StartTime.ToUniversalTime().ToString('o'); break } catch { }
}

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
    result  = @{ ok = $true; distributions = $distributions; messages = @($messages); timedOut = $timedOut
                 vmStartedAt = $vmStarted; at = (Get-Date).ToUniversalTime().ToString('o') }
}
