<# Action update-mode-off : RE-VERROUILLE (aucune MAJ auto + verrou ACL).
   Appelle LocalAgentAdmin/tools/update-mode.ps1 -Off, journalise sa sortie,
   PUIS verifie reellement l'etat obtenu (ne renvoie pas un faux succes). #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')
$tools = Get-ToolsPath -Backend $backend
if (-not $tools) { return New-ToolsMissingResult }
$script = Join-Path $tools 'update-mode.ps1'
if (-not (Test-Path $script)) { return @{ message = "Script introuvable : $script"; result = @{ ok = $false } } }

$log = Join-Path (Get-LogDir -Backend $backend) ('action-update-mode-off_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { & $script -Off *>&1 | Out-File -FilePath $log -Encoding UTF8 } catch { "EXCEPTION: $($_.Exception.Message)" | Out-File -FilePath $log -Encoding UTF8 }

# Trace de l'ACL reelle (pour diagnostic) puis verification via le helper partage
try {
    "----- icacls UpdateOrchestrator apres verrouillage -----" | Out-File -FilePath $log -Append -Encoding UTF8
    (Invoke-Native -File 'icacls.exe' -Arguments @("$env:windir\System32\Tasks\Microsoft\Windows\UpdateOrchestrator")).Output |
        Out-File -FilePath $log -Append -Encoding UTF8
} catch { }
$applied = Test-UpdateTasksAclLock
$noAuto = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name NoAutoUpdate -ErrorAction SilentlyContinue).NoAutoUpdate

$inv = @('lock.probe.ps1','pending.probe.ps1')
if ($applied) {
    @{ message = 'Verrou complet appliqué : mises à jour automatiques coupées ET verrou ACL posé.'; result = @{ ok = $true; invalidate = $inv } }
} elseif ($noAuto -eq 1) {
    @{ message = "Mises à jour automatiques coupées, mais le verrou ACL n'a PAS pu être posé (dossiers protégés par Windows). Détails dans le journal : $log"; result = @{ ok = $false; invalidate = $inv } }
} else {
    @{ message = "Échec du verrouillage (ni verrou ACL, ni coupure des MAJ auto). Détails : $log"; result = @{ ok = $false; invalidate = $inv } }
}
