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
# ONE PATH, AS A STRING: wrapping the pipeline in @() gave a one-element array, which Invoke-Native refused.
$exe = @($exe) | Select-Object -First 1
if ($exe) { $exe = "$exe" }
if (-not $exe) { $lines += 'aucun winget.exe atteignable' }
else {
    $lines += "essai : " + (Split-Path $exe -Leaf)
    # THREE QUESTIONS, NOT ONE. Does the one door work here at all (choco answers through it every day)? Does it
    # fail on winget alone? And does a redirected process succeed where the door fails -- which is what the error
    # itself suggests, since the encoding is only honoured on a redirected stream.
    try {
        $c = Invoke-Native -File 'choco' -Arguments @('--version')
        $lines += "porte/choco : ok=" + $c.Ok + " code=" + $c.ExitCode
    } catch { $lines += "porte/choco LEVE : " + $_.Exception.Message }
    try {
        $v = Invoke-Native -File $exe -Arguments @('--version')
        $lines += "porte/winget : ok=" + $v.Ok + " code=" + $v.ExitCode + " sortie=" + "$($v.Output)".Trim()
    } catch { $lines += "porte/winget LEVE : " + $_.Exception.Message }
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $exe
        foreach ($a in @('--version')) { $psi.ArgumentList.Add($a) }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $psi.UseShellExecute = $false
        $pr = [Diagnostics.Process]::Start($psi)
        $sortie = $pr.StandardOutput.ReadToEnd()
        $pr.WaitForExit(20000) | Out-Null
        $lines += "redirige/winget : code=" + $pr.ExitCode + " sortie=" + "$sortie".Trim()
    } catch { $lines += "redirige/winget LEVE : " + $_.Exception.Message }
}
@{ message = ($lines -join ' | '); result = @{ ok = $true } }
