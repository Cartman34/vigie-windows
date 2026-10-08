# @author Florent HAZARD <f.hazard@sowapps.com>
<# A DETACHED worker: it recomputes ONE stale probe, outside any HTTP request.

   Intent: let the server compute by itself without anybody waiting. THE RULE (the owner's): "the server may
   start it on its own in the background but it must be non-blocking", and "rare, and per card only". Nobody is
   waiting behind this process: the answer has already left with the known value.
   Usage: it is started by the scheduler. The 'VigieStateRecompute' lock prevents two simultaneous passes; the
   caller checks it BEFORE starting, so as not to pay for a pwsh startup for nothing.

   ONE SINGLE PROBE PER PASS. The previous version called Get-State -Force and recomputed all seventeen: one
   pass lasted a minute and a half, the others' delays expired meanwhile, and the next request started another
   one -- the machine never stopped (measured on 31/08, /state at 27 seconds). We take ONE, the oldest, and we
   stop.
#>


param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

$account = $null
$probe = $null
if ($ArgsB64) {
    try {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        if ($a.account) { $account = "$($a.account)" }
        if ($a.probe)   { $probe   = "$($a.probe)" }
    } catch { }
}
if (-not $probe) { return }

try {
    $t0 = Get-Date
    $stateArgs = @{ Backend = $Backend; Only = @($probe) }
    if ($account) { $stateArgs['Account'] = $account }
    $null = Get-State @stateArgs
    Write-Log -Backend $Backend -Name 'state' -NoEcho `
              -Message ("fond : " + $probe + " recalculee en " + [int]((Get-Date) - $t0).TotalMilliseconds + " ms")
} catch {
    Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' `
              -Message ("fond : " + $probe + " -- " + $_.Exception.Message)
}
