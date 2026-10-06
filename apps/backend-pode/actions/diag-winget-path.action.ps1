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

# AND READABLE IS NOT WORKING. winget run outside its per-user alias, under a service account with no session, is
# not something to assume: it is asked to say its version, then to list what is pending. Read only, both of them.
. (Join-Path $backend 'lib/common.ps1')
$exe = $null
try {
    $exe = @(Get-ChildItem -LiteralPath $dir -Filter 'Microsoft.DesktopAppInstaller_*_x64__*' -Directory -ErrorAction Stop |
             ForEach-Object { Join-Path $_.FullName 'winget.exe' } |
             Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Last 1)
} catch { }
if (-not $exe) { $lines += 'aucun winget.exe atteignable' }
else {
    $lines += "essai : $exe"
    $v = Invoke-Native -File $exe -Arguments @('--version')
    $lines += "--version : ok=" + $v.Ok + " code=" + $v.Code + " sortie=" + (("$($v.Output)" -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1))
    $u = Invoke-Native -File $exe -Arguments @('upgrade', '--include-unknown', '--disable-interactivity', '--accept-source-agreements')
    $premieres = @("$($u.Output)" -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -First 3)
    $lines += "upgrade : ok=" + $u.Ok + " code=" + $u.Code + " lignes=" + @("$($u.Output)" -split "`r?`n").Count
    $lines += "debut : " + ($premieres -join ' / ')
}
@{ message = ($lines -join ' | '); result = @{ ok = $true } }
