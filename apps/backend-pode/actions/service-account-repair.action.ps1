# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- it rewrites the service account and the server task (D65)
<# Action: repairs the service account -- a new password, the right to run tasks, the line that hides it -- and
   re-registers the server task with that password, then enables it again. The running server is not stopped: it
   keeps its token, and the next start uses the new password. The maintenance doc/progress/targeting/components.md
   requires for the service account; the work itself is install-service.ps1 -Repair. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$script = Join-Path (Join-Path (Join-Path (Get-RepoRoot) 'scripts') 'lib') 'install-service.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    return @{ message = "Script du service introuvable : $script"; result = @{ ok = $false } }
}
$pwsh = $null
try { $pwsh = (Get-Process -Id $PID).Path } catch { }
if (-not $pwsh) { $pwsh = 'pwsh.exe' }

$launched = $false
try {
    $launched = [bool](Start-Operation -Module 'deployment' -Action 'service-account-repair' -Label 'Réparation du compte de service' `
                           -Probes @('deployment.probe.ps1') -File $pwsh `
                           -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script, '-Repair') `
                           -Backend $backend)
} catch { }
if (-not $launched) { return @{ message = "Impossible de lancer la réparation du compte de service."; result = @{ ok = $false } } }
@{
    message = "Réparation du compte de service lancée."
    result  = @{ ok = $true; async = $true; module = 'deployment' }
}
