# @author Florent HAZARD <f.hazard@sowapps.com>
<# Worker: ONE scheduled computation, run outside any HTTP request (D124).

   The scheduler decides WHAT and WHEN; this runs it and reports what happened. Nobody waits behind this process: the
   answer the interface reads has already left, with the value known at the time.

   What it writes back, in var/run/refresh.json, under its own key: the process id cleared, how long it took, and --
   only if the computation threw -- one more failure and the moment before which it must not be tried again. That
   delay doubles at each failure up to its cap, so a broken computation stops being the oldest one and stops taking
   the place of the others (owner, 29/09).
#>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

$key = $null
$probe = $null
if ($ArgsB64) {
    try {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        if ($a.key)   { $key   = "$($a.key)" }
        if ($a.probe) { $probe = "$($a.probe)" }
    } catch { }
}
if (-not $key -or -not $probe) { return }

$state = Get-RefreshState -Backend $Backend
$entry = $state[$key]
if (-not $entry) { $entry = @{ fails = 0 } }
$t0 = Get-Date
try {
    # THE PROOF OF A RESULT is that the cache moved. An exception is not the only way to fail: Get-State catches a
    # probe's error so the other cards still answer, and the computation then returns having written nothing.
    $before = Get-ProbeCacheStamp -Backend $Backend -Probe $probe
    $null = Get-State -Backend $Backend -Only @($probe)
    $after = Get-ProbeCacheStamp -Backend $Backend -Probe $probe
    if ("$after" -eq "$before") { throw "le calcul n'a rien ecrit (sonde en erreur ou introuvable)" }
    $entry.fails = 0
    $entry.nextAt = 0
    $entry.lastError = ''
    Write-Log -Backend $Backend -Name 'state' -NoEcho `
              -Message ("planifie : " + $key + " calcule en " + [int]((Get-Date) - $t0).TotalMilliseconds + " ms")
} catch {
    $cfg = Get-RefreshConfig -Backend $Backend
    $entry.fails = [int]$entry.fails + 1
    $wait = [Math]::Min([int]$cfg.FailBackoffSeconds * [Math]::Pow(2, [int]$entry.fails - 1), [int]$cfg.FailBackoffMaxSeconds)
    $entry.nextAt = [datetime]::UtcNow.AddSeconds($wait).Ticks
    $entry.lastError = "$($_.Exception.Message)"
    Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' `
              -Message ("planifie : " + $key + " a echoue (" + $entry.fails + ") -- " + $entry.lastError +
                        " ; prochaine tentative dans " + [int]$wait + " s")
}
$entry.pid = 0
$entry.long = $false
$entry.lastEndedAt = [datetime]::UtcNow.Ticks
$entry.lastMs = [int]((Get-Date) - $t0).TotalMilliseconds
Update-RefreshState -Backend $Backend -Key $key -Entry $entry
