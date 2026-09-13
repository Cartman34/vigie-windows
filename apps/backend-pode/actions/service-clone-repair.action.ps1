# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- it rewrites data the service account owns (D65)
<# Action: repairs the service clone -- forced fetch, then a fresh clone if git still refuses.
   The maintenance of the clone, as doc/progress/targeting/components.md requires it. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$launched = $false
try {
    $launched = [bool](Start-Operation -Module 'deployment' -Action 'service-clone-repair' -Label 'Réparation du clone du service' `
                           -Probes @('deployment.probe.ps1') -Worker 'service-clone.worker.ps1' -ArgsMap @{ mode = 'repair' } -Backend $backend)
} catch { }
if (-not $launched) { return @{ message = "Impossible de lancer la réparation du clone du service."; result = @{ ok = $false } } }
@{
    message = "Réparation du clone du service lancée."
    result  = @{ ok = $true; async = $true; module = 'deployment' }
}
