# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# An action: it cancels a scheduled restart.

   Intent: be the indispensable counterpart of system-restart -- a countdown one cannot stop is not a grace
   period, it is a delayed trap. Usage: it is called from the card that offered the restart.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$r = Invoke-Native -File 'shutdown.exe' -Arguments @('/a')
$file = Get-VarPath -Backend $backend -Kind 'cache' -File 'restart.json'

# Code 1116 = "no shutdown in progress": that is not a breakdown, it is already the wanted state.
if (-not $r.Ok -and $r.ExitCode -ne 1116) {
    return @{
        message = "L'annulation a échoué (code $($r.ExitCode)). $($r.Output)"
        result  = @{ ok = $false }
    }
}
Update-StateJson -Path $file -Set @{ pending = $false; at = (Get-Date).ToUniversalTime().ToString('o') } | Out-Null

$msg = if ($r.ExitCode -eq 1116) { "Aucun redémarrage n'était programmé." } else { "Redémarrage annulé." }
@{ message = $msg; result = @{ ok = $true; invalidate = @('lock.probe.ps1','pending.probe.ps1') } }
