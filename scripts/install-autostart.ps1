# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    install-autostart.ps1 -- PERMANENT access to the panel. IDEMPOTENT.

    Intent: register a scheduled task that starts the server at every logon (elevated, hidden), so that Vigie is
    there without anybody having to launch it.
    Usage:  pwsh -ExecutionPolicy Bypass -File .\install-autostart.ps1
            pwsh -ExecutionPolicy Bypass -File .\install-autostart.ps1 -Yes   (no window)
    Exit codes: 0 = installed; 1 = a missing prerequisite; 3 = refused by the user.

    It needs administrator rights. Before any UAC prompt, a window explains what is about to be changed and why
    (D22): nothing is elevated without consent.
#>

param(
    # Skip the graphical explanation: a deliberately automated run.
    [switch] $Yes,

    <#
        WHO WE LAY THE TASK DOWN FOR -- not necessarily whoever runs (D109).

        Started from the card's button, the installation runs under the SERVICE's account. So this task was being
        registered for it: on 31/08 the task moved from a person's account to the service's, that person ended up
        with Vigie inactive and their client app no longer started at logon -- while a technical account, which
        never opens a session, inherited an Interactive task.

        So the server passes the account of the person who clicked. With no indication, we fall back on the
        account that runs: that is the case of a launch by hand, where there is nobody else.
    #>


    [string] $Account
)

$ErrorActionPreference = 'Stop'
# The management scripts live in scripts/: the apps are in apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # the same display as everywhere
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, see common.ps1
. (Join-Path $backend 'lib/common.ps1')
<#
    THE TASK STARTS THE SHARED INSTALLATION, NOT THE REPOSITORY.

    It used to point at the folder the installation had been started from: on a development workstation, the
    REPOSITORY. Three consequences, all observed on 30/08: the card reports a gap (an account starting from the
    working repository), the task is counted as out of service, and above all it will no longer start the day
    that folder moves -- or from an account that has no right to read it.

    Everything runs from the shared installation. The repository only serves to build it.
#>
$appRoot  = $repoRoot
try {
    $partagee = Get-SharedInstallPath
    if ($partagee) { $appRoot = $partagee }
} catch { }
$client     = Join-Path $appRoot 'apps/client/client.ps1'   # l'app cliente est une app a part
<#
    ONE NAMING SCHEME, FOR EVERYBODY: "Vigie - <account>".

    This script used to hard-code "Vigie" while the server named every other account's
    task "Vigie - <account>". Two schemes for one thing: the client app looked for the
    first name and therefore never found its own on a secondary account -- it said so in
    its log at every start, on 04/09, without anyone being able to act on it.

    A legacy "Vigie" task stays recognised everywhere, and the repair renames it.
#>
$forAccount = $Account
if (-not $forAccount) { $forAccount = Get-ProcessAccount }
$taskName = Get-VigieAccountTaskName -Name $forAccount
# The URL derives from config.psd1: the address and the port have only ONE definition (D15).
$appUrl   = Get-AppUrl -Backend $backend

if (-not (Test-IsElevated)) {
    $ok = Show-ElevationRationale -AssumeYes:$Yes `
        -Title   "Installer Vigie au démarrage de session" `
        -Summary "Vigie va s'enregistrer pour démarrer automatiquement à chaque ouverture de session. C'est réversible à tout moment avec uninstall-autostart.ps1." `
        -Changes @(
            "Tâche planifiée '$taskName' : lance $client à l'ouverture de session",
            "Elle s'exécute avec les droits administrateur (nécessaire pour le verrou Windows Update)",
            "L'application est lancée tout de suite après l'installation",
            "Aucun fichier du système n'est modifié ou supprimé"
        )
    if (-not $ok) { Write-Host (Get-Label 'install-autostart.installation-annulee-rien-ete'); exit 3 }

    $code = Invoke-ElevatedSelf -ScriptPath $PSCommandPath -Arguments @('-Yes') -LogDir (Get-LogDir -Backend $backend)
    exit $code
}

# The MACHINE's interpreter first: it is the only one every session can start, and it does not depend on the
# registration of a Store package. Failing that, the current account's -- enough for ITS OWN task, but not for
# somebody else's.
$pwsh = Get-SharedPwshPath
if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
if (-not $pwsh) { Write-Warn (Get-Label 'install-autostart.pwsh-introuvable-lance-abord'); exit 1 }

# ONE launch line for everyone: New-VigieClientAction, in lib/common.ps1.
$action    = New-VigieClientAction -Pwsh $pwsh -Client $client

$trigger   = New-ScheduledTaskTrigger -AtLogOn
# A 45 s delay: pwsh comes from the Microsoft Store (MSIX) and its package may not be available yet at the instant
# of the logon -- the task failed with 0xC0070154 (observed on 24/08, a session opened at 19:04, Vigie never
# started). Three retries a minute apart cover the case where the delay would not be enough.
$trigger.Delay = 'PT45S'
<#
    THE TASK'S ACCOUNT, AND ITS LEVEL, FOLLOW THE PERSON.

    The level is deduced from the account, never from what we fancy: Highest for an administrator, Limited for a
    standard account. Giving Highest to a standard account would not work, and MUST not work -- Vigie gives
    nothing more than Windows does.
#>
$forWhom = $forAccount
<#
    THE LIST IS AUTHORITATIVE: we lay a client task down only for an account the interface allows to enable
    Vigie.

    I had written "if it is the service's account, refuse" -- a filter by hand, on a NAME, while the circle
    exists: Get-UserAccounts, the accounts of people. A technical account is not in it, and that is what must
    decide. Copying the service's name here means duplicating a rule that lives elsewhere, and missing every other
    account that must not receive one either.
#>

if (@(Get-UserAccounts -Backend $backend | ForEach-Object { "$($_.name)" }) -notcontains $forWhom) {
    Write-Fail (Get-Label 'install-autostart.compte-hors-liste' $forWhom)
    exit 1
}
$niveau = $(if (Test-LocalAccountIsAdmin -Name $forWhom) { 'Highest' } else { 'Limited' })
$principal = New-ScheduledTaskPrincipal -UserId ("$env:USERDOMAIN\" + $forWhom) -LogonType Interactive -RunLevel $niveau
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Info (Get-Label 'install-autostart.tache-enregistree-lancement-ouverture' $taskName)
<#
    NO SHORTCUT ON THE DESKTOP -- AND WE REMOVE THE ONE WE LAID.

    It pointed straight at the URL, and so at a panel WITHOUT an identity: no opening proof, no cookie, nobody is
    "you", and no action knows who is asking for it. We were opening Vigie through a degraded door, laid by us, on
    the desktop.

    Vigie opens through its icon in the notification area, which borrows the whole chain. Opening the URL by hand
    stays possible and works -- that is how one debugs in a real browser -- but it is a developer's gesture, not
    what one installs for everybody.

    The removal happens HERE because the installation is the only gesture: what is missing is missing from the
    installation, never from a command to be typed once.
#>
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Vigie.url'
if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
    Write-Info (Get-Label 'install-autostart.raccourci-bureau-retire' $lnk)
}
Start-ScheduledTask -TaskName $taskName
Write-Info (Get-Label 'install-autostart.app-barre-systeme-lancee' $appUrl)
exit 0
