<#
    install-autostart.ps1 - Acces PERMANENT au panneau. IDEMPOTENT.
    Enregistre une tache planifiee qui lance le serveur a chaque ouverture de
    session (en eleve, cache), et cree un raccourci bureau vers l'UI.

    Necessite les droits admin. Avant toute invite UAC, une fenetre explique ce
    qui va etre modifie et pourquoi (D22) : rien ne s'eleve sans consentement.

    Usage :  pwsh -ExecutionPolicy Bypass -File .\install-autostart.ps1
             pwsh -ExecutionPolicy Bypass -File .\install-autostart.ps1 -Yes   (sans fenetre)

    Codes de retour : 0 = installe ; 1 = prerequis manquant ; 3 = refuse par l'utilisateur.
#>
param(
    # Passe l'explication graphique : execution volontairement automatisee.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
# Les scripts de gestion vivent dans scripts/ : les apps sont dans apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')
$tray     = Join-Path $repoRoot 'apps/tray/tray.ps1'   # le tray est une app a part
$taskName = 'Vigie'
# L'URL derive de config.psd1 : adresse et port n'ont qu'UNE definition (D15).
$appUrl   = Get-AppUrl -Backend $backend

if (-not (Test-IsElevated)) {
    $ok = Show-ElevationRationale -AssumeYes:$Yes `
        -Title   "Installer Vigie au démarrage de session" `
        -Summary "Vigie va s'enregistrer pour démarrer automatiquement à chaque ouverture de session. C'est réversible à tout moment avec uninstall-autostart.ps1." `
        -Changes @(
            "Tâche planifiée '$taskName' : lance $tray à l'ouverture de session",
            "Elle s'exécute avec les droits administrateur (nécessaire pour le verrou Windows Update)",
            "Raccourci sur le bureau : Vigie.url → $appUrl",
            "L'application est lancée tout de suite après l'installation",
            "Aucun fichier de ton système n'est modifié ou supprimé"
        )
    if (-not $ok) { Write-Host "Installation annulée. Rien n'a été modifié."; exit 3 }

    $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments @('-Yes') -LogDir (Get-LogDir -Backend $backend)
    exit $code
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { Write-Host "pwsh introuvable. Lance d'abord install.ps1 (installe PowerShell 7)." -ForegroundColor Yellow; exit 1 }

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
Set-Content -Path $lnk -Value ("[InternetShortcut]`r`nURL=" + $appUrl + "`r`n") -Encoding ASCII
Write-Host ("Raccourci bureau cree : " + $lnk)

Start-ScheduledTask -TaskName $taskName
Write-Host ("App barre systeme lancee (icone dans la zone de notification). Serveur en fond, panneau sur " + $appUrl)
exit 0
