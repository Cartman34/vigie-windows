# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- it rewrites data the service account owns (D65)
<# Action: rebuilds the service clone from the declared source, whatever its state. The old clone goes only once
   the new one exists. The maintenance of the clone, as doc/progress/targeting/components.md requires it. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$launched = $false
try {
    $launched = [bool](Start-Operation -Module 'deployment' -Action 'service-clone-reset' -Label 'Réinitialisation du clone du service' `
                           -Probes @('deployment.probe.ps1') -Worker 'service-clone.worker.ps1' -ArgsMap @{ mode = 'reset' } -Backend $backend)
} catch { }
if (-not $launched) { return @{ message = "Impossible de lancer la réinitialisation du clone du service."; result = @{ ok = $false } } }
@{
    message = "Réinitialisation du clone du service lancée."
    result  = @{ ok = $true; async = $true; module = 'deployment' }
}
