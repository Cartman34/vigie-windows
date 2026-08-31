<#
    install-autostart.ps1 - Acces PERMANENT au panneau. IDEMPOTENT.
    Enregistre une tache planifiee qui lance le serveur a chaque ouverture de
    session (en eleve, cache).

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
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')
<#
    LA TACHE LANCE L'INSTALLATION PARTAGEE, PAS LE DEPOT.

    Elle pointait sur le dossier d'ou l'installation avait ete lancee : sur un poste de
    developpement, le DEPOT. Trois consequences, toutes constatees le 30/08 : la carte
    signale un ecart (« fhaza démarre depuis le dépôt de travail »), la tache est comptee
    hors service, et surtout elle ne demarrera plus le jour ou ce dossier bouge -- ou
    depuis un compte qui n'a pas le droit de le lire.

    Tout tourne depuis l'installation partagee. Le depot ne sert qu'a la fabriquer.
#>
$appRoot  = $repoRoot
try {
    $partagee = Get-SharedInstallPath
    if ($partagee) { $appRoot = $partagee }
} catch { }
$tray     = Join-Path $appRoot 'apps/tray/tray.ps1'   # le tray est une app a part
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
            "L'application est lancée tout de suite après l'installation",
            "Aucun fichier de ton système n'est modifié ou supprimé"
        )
    if (-not $ok) { Write-Host (Get-Label 'install-autostart.installation-annulee-rien-ete'); exit 3 }

    $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments @('-Yes') -LogDir (Get-LogDir -Backend $backend)
    exit $code
}

# L'interpreteur de la MACHINE d'abord : c'est le seul que toutes les sessions peuvent
# lancer, et il ne depend pas de l'enregistrement d'un paquet du Store. A defaut, celui
# du compte courant -- suffisant pour SA propre tache, mais pas pour celle d'un autre.
$pwsh = Get-SharedPwshPath
if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
if (-not $pwsh) { Write-Warn (Get-Label 'install-autostart.pwsh-introuvable-lance-abord'); exit 1 }

$arg       = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $tray + '"'
$action    = New-ScheduledTaskAction -Execute $pwsh -Argument $arg
$trigger   = New-ScheduledTaskTrigger -AtLogOn
# 45 s de delai : pwsh vient du Microsoft Store (MSIX) et son paquet peut ne pas etre
# encore disponible a l'instant du logon -- la tache echouait en 0xC0070154 (constate
# le 24/08, session ouverte a 19:04, Vigie jamais demarre). Trois reprises espacees
# d'une minute couvrent le cas ou le delai ne suffirait pas.
$trigger.Delay = 'PT45S'
$principal = New-ScheduledTaskPrincipal -UserId ("$env:USERDOMAIN\$(Get-ProcessAccount)") -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Info (Get-Label 'install-autostart.tache-enregistree-lancement-ouverture' $taskName)
<#
    PAS DE RACCOURCI SUR LE BUREAU -- ET ON RETIRE CELUI QU'ON A POSE.

    Il pointait droit sur l'URL, donc sur un panneau SANS identite : pas de preuve
    d'ouverture, pas de cookie, personne n'est « vous », et aucune action ne sait qui la
    demande. On ouvrait Vigie par une porte degradee, posee par nous, sur le bureau.

    Vigie s'ouvre par son icone dans la barre systeme, qui elle emprunte la chaine
    complete. Ouvrir l'URL a la main reste possible et fonctionne -- c'est ainsi qu'on
    debogue dans un vrai navigateur -- mais c'est un geste de developpeur, pas ce qu'on
    installe pour tout le monde.

    Le retrait se fait ICI parce que l'installation est le seul geste : ce qui manque
    manque dans l'installation, jamais dans une commande a taper une fois.
#>
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Vigie.url'
if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
    Write-Info (Get-Label 'install-autostart.raccourci-bureau-retire' $lnk)
}
Start-ScheduledTask -TaskName $taskName
Write-Info (Get-Label 'install-autostart.app-barre-systeme-lancee' $appUrl)
exit 0
