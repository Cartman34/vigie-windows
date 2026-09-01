# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : demarre WSL (boot de la distribution par defaut), borne par un delai. #>
param([string]$Module, [hashtable]$Params)
# -e true : execute /bin/true dans la distrib par defaut -> booter la VM WSL.
$job = Start-Job { & wsl.exe -e true 2>&1 }
$null = Wait-Job $job -Timeout 25
Remove-Job $job -Force -ErrorAction SilentlyContinue
# Confirme le demarrage (apparition du processus WSL, max ~10 s).
$running = $false
for ($i = 0; $i -lt 20; $i++) {
    if (Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue) { $running = $true; break }
    Start-Sleep -Milliseconds 500
}
if ($running) { @{ message = 'WSL démarré.'; result = @{ ok = $true; invalidate = @('wsl.probe.ps1') } } }
else          { @{ message = 'WSL lancé mais état non confirmé.'; result = @{ ok = $false; invalidate = @('wsl.probe.ps1') } } }
