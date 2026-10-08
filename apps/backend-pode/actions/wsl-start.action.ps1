# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# An action: it starts WSL (booting the default distribution), bounded by a timeout. Intent: boot the VM without ever freezing on it. Usage: cited by the WSL card. #>
param([string]$Module, [hashtable]$Params)
# -e true: it runs /bin/true inside the default distribution -> which boots the WSL VM.
$job = Start-Job { & wsl.exe -e true 2>&1 }
$null = Wait-Job $job -Timeout 25
Remove-Job $job -Force -ErrorAction SilentlyContinue
# It confirms the start (the WSL process appearing, ~10 s at most).
$running = $false
for ($i = 0; $i -lt 20; $i++) {
    if (Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue) { $running = $true; break }
    Start-Sleep -Milliseconds 500
}
if ($running) { @{ message = 'WSL démarré.'; result = @{ ok = $true; invalidate = @('wsl.probe.ps1') } } }
else          { @{ message = 'WSL lancé mais état non confirmé.'; result = @{ ok = $false; invalidate = @('wsl.probe.ps1') } } }
