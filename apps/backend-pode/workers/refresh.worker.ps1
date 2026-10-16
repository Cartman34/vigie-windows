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
$account = $null
if ($ArgsB64) {
    try {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        if ($a.key)   { $key   = "$($a.key)" }
        if ($a.probe) { $probe = "$($a.probe)" }
        if ($a.account) { $account = "$($a.account)" }
    } catch { }
}
if (-not $key -or -not $probe) { return }

$state = Get-RefreshState -Backend $Backend
$entry = $state[$key]
if (-not $entry) { $entry = @{ fails = 0 } }
# The time the machine was AWAKE, not the time on the wall: a sleep in the middle used to be counted in
# (S22, read in the logs on 16/10).
$t0 = [Environment]::TickCount64
try {
    # THE PROOF OF A RESULT is that the cache moved. An exception is not the only way to fail: Get-State catches a
    # probe's error so the other cards still answer, and the computation then returns having written nothing.
    # FOR WHOM: a per-account measure is computed for ONE account, and its proof is that account's entry.
    $before = Get-ProbeCacheStamp -Backend $Backend -Probe $probe -Account $account
    $null = $(if ($account) { Get-State -Backend $Backend -Only @($probe) -Account $account }
                else        { Get-State -Backend $Backend -Only @($probe) })
    $after = Get-ProbeCacheStamp -Backend $Backend -Probe $probe -Account $account
    if ("$after" -eq "$before") { throw "le calcul n'a rien ecrit (sonde en erreur ou introuvable)" }
    $entry.fails = 0
    $entry.nextAt = 0
    $entry.lastError = ''
    $entry.waiting = $false
    Write-Log -Backend $Backend -Name 'state' -NoEcho `
              -Message ("planifie : " + $key + " calcule en " + [int]([Environment]::TickCount64 - $t0) + " ms")
} catch {
    <#
        AN ABSENCE IS NOT A BREAKDOWN.

        A measure that belongs to an account is computed IN that account's session (D128): without a living client
        app, nothing can be written, and that is not the probe's fault. The scheduler went on declaring it all the
        same -- an account counts as "in session" by its mounted registry hive, which outlives its client app by
        hours -- so the same four computations failed every hour on 15 and 16/10, each failure doubling the delay
        and each line written as an ERROR.

        So we ask: does this account's client app still beat? If it does not, the computation is WAITING, it says
        so, it counts no failure, and it comes back at its own pace.
    #>
    $waiting = $false
    if ($account) {
        try {
            $beat = Get-ClientHeartbeat -Account $account
            # Three minutes with no beat is the threshold the self-watch card already uses: the beat is every
            # eight seconds, and a loaded machine misses a few.
            if (-not $beat -or ([datetime]::UtcNow - $beat.At).TotalMinutes -ge 3) { $waiting = $true }
        } catch { }
    }
    if ($waiting) {
        $entry.waiting  = $true
        $entry.lastError = "en attente de la session de $account"
        $entry.pid = 0
        $entry.long = $false
        # No failure counted, no doubling delay: it will be tried again when its turn comes round.
        $entry.nextAt = 0
        Update-RefreshState -Backend $Backend -Key $key -Entry $entry
        try {
            Write-Log -Backend $Backend -Name 'state' -Level 'WARN' -Message (
                "planifie : " + $key + " attend la session de " + $account + " (app cliente silencieuse)")
        } catch { }
        return
    }
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
$entry.lastMs = [int]([Environment]::TickCount64 - $t0)
Update-RefreshState -Backend $Backend -Key $key -Entry $entry
