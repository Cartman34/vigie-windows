<#
    install-autostart.ps1 - Acces PERMANENT au panneau. IDEMPOTENT.
    Enregistre une tache planifiee qui lance le serveur a chaque ouverture de
    session (en eleve, cache), et cree un raccourci bureau vers l'UI.
    Necessite les droits admin (auto-elevation).

    Usage :  powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1
#>
$ErrorActionPreference = 'Stop'
$backend  = $PSScriptRoot
$tray     = Join-Path $backend 'tray.ps1'
$taskName = 'Vigie'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevation requise pour enregistrer la tache planifiee..."
    Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    return
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { Write-Host "pwsh introuvable. Lance d'abord install.ps1 (installe PowerShell 7)." -ForegroundColor Yellow; return }

$arg       = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $tray + '"'
$action    = New-ScheduledTaskAction -Execute $pwsh -Argument $arg
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId ("$env:USERDOMAIN\$env:USERNAME") -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host ("Tache '" + $taskName + "' enregistree (lancement a l'ouverture de session, eleve).")

$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop 'Vigie.url'
Set-Content -Path $lnk -Value ("[InternetShortcut]`r`nURL=http://127.0.0.1:47600/`r`n") -Encoding ASCII
Write-Host ("Raccourci bureau cree : " + $lnk)

Start-ScheduledTask -TaskName $taskName
Write-Host "App barre systeme lancee (icone dans la zone de notification). Serveur en fond, panneau sur http://127.0.0.1:47600/"
