# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- lit sous Program Files\WindowsApps, ferme a une session ordinaire (D65)
# @execution: serveur   -- c'est justement le compte du serveur qu'on interroge
# TEMPORARY, READ ONLY: the server app says whether it reaches winget, in its PATH and by full path. Removed as
# soon as the measurement is taken -- it exists to answer one question of the plan, not to stay.
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
$lines = @()
$lines += "compte : " + [Security.Principal.WindowsIdentity]::GetCurrent().Name
$lines += "winget dans le PATH : " + $(if (Get-Command winget -ErrorAction SilentlyContinue) { 'oui' } else { 'non' })
$dir = Join-Path $env:ProgramFiles 'WindowsApps'
try {
    $found = @(Get-ChildItem -LiteralPath $dir -Filter 'Microsoft.DesktopAppInstaller_*' -Directory -ErrorAction Stop)
    $lines += "dossiers DesktopAppInstaller : " + $found.Count
    foreach ($d in @($found | Select-Object -Last 2)) {
        $exe = Join-Path $d.FullName 'winget.exe'
        $lines += "  " + $d.Name + " -> winget.exe " + $(if (Test-Path -LiteralPath $exe) { 'present' } else { 'absent' })
    }
} catch { $lines += "lecture de WindowsApps refusee : " + $_.Exception.Message }
@{ message = ($lines -join ' | '); result = @{ ok = $true } }
