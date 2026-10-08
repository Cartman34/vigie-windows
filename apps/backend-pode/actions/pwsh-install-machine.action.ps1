# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- installe un logiciel pour toute la machine : Windows exige l'elevation (D65)
# @libelle: Installer PowerShell 7 pour la machine | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# An action: it installs PowerShell 7 for THE WHOLE MACHINE (winget, machine scope).

   Intent: make sure every account's start-up task can start pwsh. When PowerShell 7 comes from the Store, its
   path lives in the profile of whoever installed it -- unreadable to the others, and the alias points at an MSIX
   package registered for them alone. The task is created without an error and starts nothing: Vigie does not
   start, with no message (observed on 26/08 with one of the accounts).
   Usage: it is called from the Deployment card's button. An MSI installation lays pwsh under Program Files:
   every account can start it. It runs in the background, its output going into a log file (never into a pipe
   nobody reads: that blocks the process). #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

if (Get-SharedPwshPath) {
    return @{ message = "PowerShell 7 est déjà installé pour la machine : " + (Get-SharedPwshPath)
              result  = @{ ok = $true; invalidate = @('accounts.probe.ps1', 'deployment.probe.ps1') } }
}
$winget = (Get-Command winget -ErrorAction SilentlyContinue)
if (-not $winget) {
    return @{ message = "winget est introuvable : installez PowerShell 7 depuis github.com/PowerShell/PowerShell (paquet MSI)."
              result  = @{ ok = $false } }
}

$journal = Join-Path (Get-LogDir -Backend $backend) ('pwsh-install_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')

$lance = $false
try {
    # The watcher waits for the end and REPORTS the exit code (D82). The old version started winget and forgot
    # about it: the failure of 26/08 (0x80070005, which had uninstalled the existing PowerShell on the way)
    # produced neither a red line nor a notification.
    $lance = [bool](Start-Operation -Module 'deployment' -Probes @('deployment.probe.ps1') `
                        -Label 'Installation de PowerShell 7' -Action 'pwsh-install-machine' `
                        -File $winget.Source -Arguments (Get-SharedPwshInstallArgs) `
                        -Log $journal -Backend $backend)
    Write-Log -Backend $backend -Name 'comptes' -Message (Get-Label 'pwsh-install-machine.installation-de-powershell-machine' $journal)
} catch {
    Write-Log -Backend $backend -Name 'comptes' -Level 'ERROR' -Message $_.Exception.Message
}

if (-not $lance) { return @{ message = "Impossible de lancer l'installation."; result = @{ ok = $false } } }

@{
    message = "Installation de PowerShell 7 pour la machine lancée. Elle dure une à deux minutes ; réactivez ensuite les comptes concernés."
    result  = @{ ok = $true; async = $true; module = 'deployment'; invalidate = @('accounts.probe.ps1', 'deployment.probe.ps1') }
}
