# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : arrete WSL (borne par un delai pour ne pas figer). #>
param([string]$Module, [hashtable]$Params)
$job = Start-Job { & wsl.exe --shutdown 2>&1 }
$ok = Wait-Job $job -Timeout 15
Remove-Job $job -Force -ErrorAction SilentlyContinue
# Attend la disparition du processus WSL (max ~6 s) pour un etat a jour immediat.
for ($i = 0; $i -lt 12; $i++) {
    if (-not (Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
if ($ok) { @{ message = 'WSL arrêté.'; result = @{ ok = $true; invalidate = @('wsl.probe.ps1') } } }
else     { @{ message = 'Délai dépassé en arrêtant WSL.'; result = @{ ok = $false; invalidate = @('wsl.probe.ps1') } } }
