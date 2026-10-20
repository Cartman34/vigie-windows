# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, format, log, native, paths, settings, var
<#
    Intent: THE SERVER APP AS A PROCESS: is it alive, why is it struggling, how is it stopped and brought back. Stopping it is Vigie's own business and nobody else's -- the reasons it reports are measured, never guessed.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- Background tasks (the rule: a slow action never blocks the request) ----
# Starts a worker script in a DETACHED pwsh, window hidden -- no console appears and no
# Terminal tab is restored. The pwsh executable is the current process's own, so no
# installation path is hard-coded anywhere. Parameters travel as base64 JSON, which is
# robust to quoting. Returns the process id.
# RESERVED FOR THE INTERNAL RECOMPUTE OF A STALE PROBE, whose place in the protocol is not settled (S14). An
# action never calls it: an asynchronous operation goes through Start-Operation, and check-operations refuses the rest.
function Start-DetachedAction {
    param(
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$ArgsMap = @{},
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-Path -LiteralPath $Script)) { throw "Worker introuvable : $Script" }
    <#
        THE HARD CEILING ON WHAT VIGIE MAY START -- and it is a REFUSAL, not a warning.

        On 29/09 a bad guard let each background task start another one: 150 elevated processes in two minutes, the
        machine down to 0,3 GB of free memory, and the server unable to listen on its own port. No count anywhere
        said stop. A product that watches a computer must never be what brings it down.

        Every process Vigie starts is written down here, with its id; the dead ones are dropped at each pass. Past
        MaxChildren live ones, the launch is REFUSED -- it returns nothing, it says so in the log, and the caller
        carries on without its background task. Nothing is ever stopped by this: refusing to start is enough.
    #>
    $childFile = $null
    try {
        $childFile = Get-VarPath -Backend $Backend -Kind 'run' -File 'children.json'
        $live = @()
        if (Test-PathSafe $childFile) {
            $raw = Get-Content -LiteralPath $childFile -Raw -Encoding UTF8 -ErrorAction Stop
            foreach ($id in @((ConvertFrom-Json $raw).ids)) {
                try { if (Get-Process -Id ([int]$id) -ErrorAction Stop) { $live += [int]$id } } catch { }
            }
        }
        $max = 12
        $reserve = 0
        try {
            $cfgChild = Get-RefreshConfig -Backend $Backend
            $max = [int]$cfgChild.MaxChildren
            $reserve = [int]$cfgChild.RefreshReserve
        } catch { }
        if ($max -le 0) { $max = 12 }
        if ($reserve -lt 0) { $reserve = 0 }
        <#
            WHAT IS SACRIFICED FIRST IS NOT THE REFRESH OF THE CARDS.

            On 15/10 the ceiling turned a launch away twenty-six times, and every single one of them was the
            scheduler's refresh worker: the screen therefore aged precisely while the machine was busy, which is
            when one looks at it. Everything else -- a disk scan, a package job, a client task -- can wait a pass
            without anybody noticing.

            So the ceiling is reached SOONER for everything else: the last places are kept for the refresh.
        #>
        $leaf = Split-Path $Script -Leaf
        $ceiling = $(if ($leaf -eq 'refresh.worker.ps1') { $max } else { [Math]::Max(1, $max - $reserve) })
        if ($live.Count -ge $ceiling) {
            <#
                A REFUSAL AT THE CEILING IS A REGULATION, NOT A BREAKDOWN.

                It used to be written as an ERROR, with the same words as a launch that could not start at all,
                and the caller counted it as a failure with a doubling delay. Twenty-six ERROR lines in one day
                for a guard doing exactly what it was asked to do (D126) drown the lines that mean something.

                The reason is left here for the caller to read: refusing to wait a pass is not the same thing as
                failing to start.
            #>
            $script:LastChildRefusal = 'plafond'
            Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                "lancement differe : $($live.Count) taches de fond vivantes, plafond $ceiling -- " + $leaf)
            return $null
        }
        $script:LastChildRefusal = ''
        $script:PendingChildren = $live
    } catch { $script:PendingChildren = @() }
    $exe = $null
    try { $exe = (Get-Process -Id $PID).Path } catch { }
    if (-not $exe) { try { $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { } }
    if (-not $exe) { $exe = 'pwsh.exe' }
    $json = ($ArgsMap | ConvertTo-Json -Compress -Depth 6)
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe
    # NB: no -WindowStyle argument -- it is not implemented outside Windows. The absence of a
    # window is guaranteed by CreateNoWindow + UseShellExecute=$false below.
    # ArgumentList, NOT Arguments: .NET quotes each value itself, while a command line built
    # by hand carries the trap a path ending with a backslash sets (D116).
    foreach ($piece in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                         '-File', $Script, '-Backend', $Backend, '-ArgsB64', $b64)) {
        [void]$psi.ArgumentList.Add([string]$piece)
    }
    # THE CHILD IS A BACKGROUND TASK, AND IT SAYS SO: Get-State reads this and never hands off in turn (29/09).
    $psi.UseShellExecute = $false
    [void]$psi.EnvironmentVariables.Remove('VIGIE_NO_BACKGROUND')
    [void]$psi.EnvironmentVariables.Add('VIGIE_NO_BACKGROUND', '1')
    $psi.CreateNoWindow  = $true
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = $Backend
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p) { return $null }
    # WRITTEN DOWN THE MOMENT IT EXISTS, or the ceiling above counts nothing.
    try {
        $ids = @($script:PendingChildren) + @([int]$p.Id)
        Set-Content -LiteralPath $childFile -Value (@{ ids = @($ids) } | ConvertTo-Json -Compress) -Encoding UTF8
    } catch { }
    return $p.Id
}

# Get-PortListener lives in scripts/lib/tcp-ports.ps1, loaded at the top of this file.

# WHY THE SERVER DOES NOT ANSWER, as far as a client app can measure it alone (CORE-CLIENT): short lines, the likeliest
# first, empty when nothing measurable explains it. On 17/09 the client app said only "server unreachable" while the memory,
# the network ports and the desktop heap of the computer were exhausted -- all of it readable from any account.
# Each reading is a direct call to Windows (a few milliseconds each, the log filtered by the log service); the netsh
# range reading (0.2 s) is paid only when the ports are counted. Never throws.
function Get-ServerTroubleReasons {
    param([int]$Port = 0, [string]$Backend = (Get-BackendRoot))
    $reasons = @()
    try {
        $memory = Get-MemoryStatus
        if ($memory -and $memory.CommitLimit -gt 0) {
            $pct = [math]::Round(100 * $memory.CommitUsed / $memory.CommitLimit)
            if ($pct -ge 90) { $reasons += (Get-Label 'client.raison-memoire' $pct) }
        }
    } catch { }
    try {
        foreach ($proto in 'tcp', 'udp') {
            $range = Get-EphemeralPortRange -Protocol $proto
            if (-not $range) { continue }
            $usage = Get-EphemeralPortUsage -Protocol $proto -Start $range.Start -Count $range.Count
            if ($usage -and $usage.Used -ge 0.8 * $usage.Limit) { $reasons += (Get-Label 'client.raison-ports' $proto.ToUpper() $usage.Used $usage.Limit) }
        }
    } catch { }
    try {
        # What Windows logged in the last 30 minutes that stops a server from answering.
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Tcpip', 'Win32k', 'Microsoft-Windows-Resource-Exhaustion-Detector'
                                                     Id = 4231, 4266, 704, 2004; StartTime = (Get-Date).AddMinutes(-30) } -ErrorAction Stop)
        foreach ($provider in @($events | Group-Object ProviderName)) {
            $at = @($provider.Group | Sort-Object TimeCreated -Descending)[0].TimeCreated.ToString('HH:mm')
            switch ($provider.Name) {
                'Tcpip'  { $reasons += (Get-Label 'client.raison-journal-ports' $at) }
                'Win32k' { $reasons += (Get-Label 'client.raison-journal-bureau' $at) }
                default  { $reasons += (Get-Label 'client.raison-journal-memoire' $at) }
            }
        }
    } catch { }
    try {
        if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }
        $listener = Get-PortListener -Port $Port
        if ($listener) {
            $count = 1 + @(Get-ProcessDescendants -ProcessId ([int]$listener.OwningProcess)).Count
            $limit = 20
            try { $limit = [int](Get-ModuleSetting -Unit 'debug' -Key 'SelfMaxProcesses' -Backend $Backend) } catch { }
            if ($count -gt $limit) { $reasons += (Get-Label 'client.raison-processus' $count) }
        }
    } catch { }
    return $reasons
}

<#
    IS THIS PROCESS OURS? Asked before anything is ever stopped.

    Stopping was decided on ONE clue: whoever holds port 47600. Nothing said it was Vigie. A port is taken by the
    first comer, so a program that grabbed 47600 before Vigie -- or after it died -- would have been killed by an
    update, in silence. The owner's rule is absolute: nothing is stopped without his word, and the exception he
    granted on 29/09 covers VIGIE'S OWN processes, so we must be able to prove it is one.

    The proof is the command line: a PowerShell running a script that lives under our installation. An unreadable
    command line proves nothing, so it answers NO -- and nothing is stopped.
#>
function Test-VigieProcess {
    param([Parameter(Mandatory)][int]$ProcessId, [string]$Backend = (Get-BackendRoot))
    if ($ProcessId -le 0) { return $false }
    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        if (-not $p) { return $false }
        if ("$($p.Name)" -notin @('pwsh.exe', 'powershell.exe')) { return $false }
        $line = "$($p.CommandLine)"
        if (-not $line) { return $false }
        # BOTH AT ONCE: our installation AND one of our scripts. The path alone is not enough -- it travels as an
        # argument in command lines that are not ours at all, and a check that says yes too easily is worse than none.
        $roots = @("$Backend".TrimEnd([char]92, [char]47))
        try { $roots += (Split-Path $roots[0] -Parent) } catch { }
        $under = $false
        foreach ($root in @($roots | Where-Object { $_ })) {
            if ($line -like ('*' + $root + '*')) { $under = $true; break }
        }
        if (-not $under) { return $false }
        foreach ($ours in @('server.ps1', 'start.ps1', 'client.ps1', 'protocol.ps1', '.worker.ps1', '.resident.ps1')) {
            if ($line -like ('*' + $ours + '*')) { return $true }
        }
        return $false
    } catch { return $false }
}

function Stop-ServerApp {
    param([string]$Backend = (Get-BackendRoot), [int]$Port = 0, [int]$TimeoutSec = 30)
    if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }

    try { Stop-ScheduledTask -TaskName (Get-ServiceTaskName) -ErrorAction SilentlyContinue } catch { }
    $held = Get-PortListener -Port $Port
    if ($held) {
        $owner = [int]$held.OwningProcess
        if (Test-VigieProcess -ProcessId $owner -Backend $Backend) {
            try { Stop-Process -Id $owner -Force -ErrorAction Stop } catch { }
        } else {
            # NOT OURS, NOT OUR CALL. The port is taken by something else: we say it and we leave it alone.
            try { Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                    "port $Port tenu par le PID $owner, qui n'est pas un processus de Vigie : rien n'est arrete") } catch { }
        }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-PortListener -Port $Port)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Start-ServerRelauncher {
    param(
        [Parameter(Mandatory)][string]$StartScript,
        [int]$Port = 0,
        [switch]$Wait,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not (Test-PathSafe $StartScript)) { throw ("start.ps1 introuvable : " + $StartScript) }
    if (-not $Port) { $Port = [int](Get-Config -Backend $Backend).Port }

    $target = $null
    $c = Get-PortListener -Port $Port
    if ($c) { $target = [int]$c.OwningProcess }
    if (-not $target) { throw ("Aucune app serveur n'ecoute sur le port " + $Port + ".") }
    # THE RELAUNCHER CARRIES THIS ID AND STOPS IT: it must be ours, or there is nothing to relaunch here.
    if (-not (Test-VigieProcess -ProcessId $target -Backend $Backend)) {
        throw ("Le port " + $Port + " est tenu par le PID " + $target + ", qui n'est pas un processus de Vigie : rien n'est arrete.")
    }

    $pwsh = $null
    try { $pwsh = (Get-Process -Id $PID).Path } catch { }
    if (-not $pwsh) { $pwsh = 'pwsh.exe' }

    # The folder of the busy marks comes from Get-VarPath, never from a recomposed path:
    # one definition, and it lives here.
    $runDir = Get-VarPath -Backend $Backend -Kind 'run'
    $waitBlock = if ($Wait) { @"
`$run = '$runDir'
while (`$true) {
    `$marques = @(Get-ChildItem -LiteralPath `$run -Filter 'busy-*.json' -File -ErrorAction SilentlyContinue)
    if (-not `$marques.Count) { break }
    Start-Sleep -Seconds 3
}
"@ } else { '' }

    <#
        THE SERVER BELONGS TO ITS TASK: WE RESTART THE TASK.

        I used to launch start.ps1 myself. The result, on 30/08: the update killed the server
        and the successor never held -- launched from an elevated session, it ran under THE
        WRONG ACCOUNT and died with it. Vigie stayed dead, the task "Ready", the port silent.

        The task, on the other hand, knows what it launches: the right account, with no open
        session, with its own rights. We stop it and start it again. start.ps1 run directly
        remains only for the case where there is no task -- a server started by hand, in
        development.
    #>
    $taskName = Get-ServiceTaskName
    $byTask = $false
    try { $byTask = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction Stop) } catch { }

    $stopSnippet = if ($byTask) { @"
try { Stop-ScheduledTask -TaskName '$taskName' -ErrorAction SilentlyContinue } catch { }
try { Stop-Process -Id $target -Force -ErrorAction SilentlyContinue } catch { }
"@ } else { @"
try { Stop-Process -Id $target -Force -ErrorAction SilentlyContinue } catch { }
"@ }

    $startSnippet = if ($byTask) { @"
Start-ScheduledTask -TaskName '$taskName'
"@ } else { @"
Start-Process -FilePath $(ConvertTo-PSLiteral $pwsh) -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$(ConvertTo-PSLiteral (ConvertTo-ProcessArgument $StartScript)) -WindowStyle Hidden
"@ }

    $portLib = ConvertTo-PSLiteral (Join-Path (Join-Path (Get-RepoRoot) 'scripts') (Join-Path 'lib' 'tcp-ports.ps1'))
    $script = @"
Start-Sleep -Milliseconds 400
. $portLib
$waitBlock
$stopSnippet
`$fin = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt `$fin) {
    `$held = Get-PortListener -Port $Port
    if (-not `$held) { break }
    Start-Sleep -Milliseconds 300
}
$startSnippet
"@

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pwsh
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $script)) {
        [void]$psi.ArgumentList.Add($a)
    }
    [void][System.Diagnostics.Process]::Start($psi)
    return $target
}

# --- Idempotence: is the server already listening? ---------------------------
function Test-ServerUp {
    # No default value: the address and the port have only ONE definition (config.psd1).
    param([Parameter(Mandatory)][string]$Address, [Parameter(Mandatory)][int]$Port)
    try {
        $c = [System.Net.Sockets.TcpClient]::new()
        $c.Connect($Address, $Port)
        $c.Close()
        return $true
    } catch { return $false }
}
