# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# An action: it asks the disc analysis under way to stop.
   Intent: stop it cleanly without losing what is known. We do NOT kill the worker: we lay down a flag it reads
   again at every progress point (about every 1.5 s). It then stops cleanly and leaves the last complete result
   in place -- a partial result would be misleading. Usage: it is called from the Storage card. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$stopFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.stop'
Set-Content -LiteralPath $stopFile -Value ((Get-Date).ToUniversalTime().ToString('s')) -Encoding UTF8

@{
    message = "Arrêt demandé : l'analyse s'interrompt dans quelques secondes."
    result  = @{ ok = $true; async = $true; module = 'storage'; invalidate = @('disk.probe.ps1') }
}
