<# Action : redemarre WSL (arret propre puis boot), borne par des delais. #>
param([string]$Module, [hashtable]$Params)
# 1) Arret.
$job = Start-Job { & wsl.exe --shutdown 2>&1 }
$null = Wait-Job $job -Timeout 15
Remove-Job $job -Force -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 12; $i++) {
    if (-not (Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
# 2) Redemarrage (boot distrib par defaut).
$job2 = Start-Job { & wsl.exe -e true 2>&1 }
$null = Wait-Job $job2 -Timeout 20
Remove-Job $job2 -Force -ErrorAction SilentlyContinue
$running = $false
for ($i = 0; $i -lt 20; $i++) {
    if (Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue) { $running = $true; break }
    Start-Sleep -Milliseconds 500
}
if ($running) { @{ message = 'WSL redemarre.'; result = @{ ok = $true; invalidate = @('wsl.probe.ps1') } } }
else          { @{ message = 'WSL redemarrage : etat non confirme.'; result = @{ ok = $false; invalidate = @('wsl.probe.ps1') } } }
