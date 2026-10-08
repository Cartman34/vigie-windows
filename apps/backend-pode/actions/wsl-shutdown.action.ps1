# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# An action: it stops WSL (bounded by a timeout so as not to freeze). Intent: stop the VM without ever hanging on it. Usage: cited by the WSL card. #>
param([string]$Module, [hashtable]$Params)
$job = Start-Job { & wsl.exe --shutdown 2>&1 }
$ok = Wait-Job $job -Timeout 15
Remove-Job $job -Force -ErrorAction SilentlyContinue
# It waits for the WSL process to disappear (~6 s at most) so that the state is up to date at once.
for ($i = 0; $i -lt 12; $i++) {
    if (-not (Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
if ($ok) { @{ message = 'WSL arrêté.'; result = @{ ok = $true; invalidate = @('wsl.probe.ps1') } } }
else     { @{ message = 'Délai dépassé en arrêtant WSL.'; result = @{ ok = $false; invalidate = @('wsl.probe.ps1') } } }
