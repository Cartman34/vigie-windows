<#
    uninstall-autostart.ps1 - Retire l'acces permanent. IDEMPOTENT. Admin.
#>
$ErrorActionPreference = 'SilentlyContinue'
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    return
}
Unregister-ScheduledTask -TaskName 'Vigie' -Confirm:$false
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Vigie.url'
if (Test-Path $lnk) { Remove-Item $lnk -Force }
Write-Host "Acces permanent retire (tache + raccourci)."
