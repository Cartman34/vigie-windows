# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Redémarrer Windows | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# Action : redemarrer Windows.

   Intent: make the most intrusive gesture of the application safe. It closes everything the user has open.
   Three precautions, in this order:

   2. the restart is DEFERRED by 60 seconds, not immediate;
   3. it stays CANCELLABLE during that delay (the system-restart-cancel action).

   An immediate and irrevocable restart behind a single click would be a trap.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$delai = 60
if ($Params -and $Params.delay) {
    try { $d = [int]$Params.delay; if ($d -ge 0 -and $d -le 3600) { $delai = $d } } catch { }
}

# shutdown.exe rather than Restart-Computer: it alone knows how to DEFER and to let itself be cancelled.
$r = Invoke-Native -File 'shutdown.exe' -Arguments @(
    '/r', '/t', "$delai", '/c', "Redemarrage demande depuis Vigie : le travail en cours est a enregistrer."
)
if (-not $r.Ok) {
    return @{
        message = "Le redémarrage n'a pas pu être programmé (code $($r.ExitCode)). $($r.Output)"
        result  = @{ ok = $false }
    }
}

Update-StateJson -Path (Get-VarPath -Backend $backend -Kind 'cache' -File 'restart.json') -Set @{
    pending = $true
    at      = (Get-Date).ToUniversalTime().ToString('o')
    delay   = $delai
} | Out-Null

@{
    message = "Redémarrage programmé dans $delai secondes. Il reste annulable."
    result  = @{ ok = $true; invalidate = @('lock.probe.ps1','pending.probe.ps1') }
}
