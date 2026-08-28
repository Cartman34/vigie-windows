<#
    install-service.ps1 - Le serveur de Vigie devient un SERVICE DE MACHINE. IDEMPOTENT.

    Aujourd'hui, chaque compte lance son propre serveur au moment de sa session. Un compte
    STANDARD ne le peut pas : le serveur exige l'elevation, et Windows lui reclamerait un
    mot de passe d'administrateur qu'il n'a pas. Et deux sessions ouvertes en meme temps
    se disputent le meme port.

    D'ou un serveur UNIQUE, lance au demarrage de la machine, sous un compte
    administrateur DEDIE -- pas SYSTEM, dont les pleins pouvoirs ne se justifient pas.
    Conception complete : doc/progress/targeting/multi-account-server.md.

    LE MOT DE PASSE N'EST PAS UN SECRET A FAIRE VIVRE. Il est genere ici, passe une seule
    fois a Register-ScheduledTask, et c'est WINDOWS qui le conserve dans son coffre pour
    lancer la tache. Ce script ne l'ecrit nulle part et ne le rend pas.

    PRUDENCE VOULUE : la tache est creee DESACTIVEE. Tant qu'on ne l'active pas, rien ne
    change au demarrage de la machine, et le chemin actuel continue de fonctionner. Les
    deux ne doivent JAMAIS tourner ensemble : ils se disputeraient le port.

    CE N'EST PAS UN POINT D'ENTREE. L'installation de Vigie n'en a qu'UN -- setup.cmd, qui
    appelle install.ps1 -- et c'est lui qui appelle cette etape. Un utilisateur n'a pas a
    savoir qu'elle existe, ni dans quel ordre lancer quoi : l'idempotence fait la
    difference entre une premiere installation et une mise a jour.

    Il reste lancable a la main pour les gestes qui ne sont PAS l'installation :

      pwsh -File .\scripts\lib\install-service.ps1 -Lister    # etat des lieux, ne change rien
      pwsh -File .\scripts\lib\install-service.ps1 -Activer   # bascule vers le service
      pwsh -File .\scripts\lib\install-service.ps1 -Retirer   # revient en arriere

    Codes de retour : 0 = fait ; 1 = prerequis manquant ; 2 = une etape a echoue ;
                      3 = refuse par l'utilisateur.
#>
param(
    [switch] $Lister,
    [switch] $Activer,
    [switch] $Retirer,
    [switch] $Yes
)
$ErrorActionPreference = 'Stop'

# Le script a descendu d un cran (scripts/lib/) : la racine est deux niveaux au-dessus.
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'

$SERVICE_ACCOUNT = 'VigieService'
$SERVICE_TASK    = 'Vigie - Serveur'

function Say { param([string]$Text, [string]$Color = 'Gray') Write-Host $Text -ForegroundColor $Color }

function Get-ServiceAccount {
    try { return (Get-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop) } catch { return $null }
}
function Get-ServiceTask {
    try { return (Get-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop) } catch { return $null }
}

# --- Etat des lieux -------------------------------------------------------------------
function Show-State {
    $account = Get-ServiceAccount
    $task    = Get-ServiceTask
    Say ""
    Say "=== Service de machine ===" 'Cyan'
    Say ""
    Say ("  Compte dédié    : " + $(if ($account) { $SERVICE_ACCOUNT + " (actif=" + $account.Enabled + ")" } else { "absent" })) `
        $(if ($account) { 'Green' } else { 'Yellow' })
    Say ("  Tâche machine  : " + $(if ($task) { $SERVICE_TASK + " (" + $task.State + ")" } else { "absente" })) `
        $(if ($task) { 'Green' } else { 'Yellow' })
    Say ("  Environnement  : " + (Get-EnvironmentLabel -Environment (Get-DeclaredEnvironment -Backend $backend)))
    $listening = $null
    try { $listening = Get-NetTCPConnection -LocalPort ([int](Get-Config -Backend $backend).Port) -State Listen -ErrorAction Stop } catch { }
    Say ("  Serveur en ligne : " + $(if ($listening) { "oui (PID " + $listening[0].OwningProcess + ")" } else { "non" }))
    Say ""
}

# --- Le compte dedie ------------------------------------------------------------------
#
# Un mot de passe long et aleatoire, genere ici, passe une seule fois a Windows. On ne le
# conserve pas : si la tache doit etre reenregistree, on en genere un nouveau et on
# reinitialise le compte -- geste d'administrateur, comme le reste.
function New-ServicePassword {
    $bytes = [byte[]]::new(24)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    # Base64 peut contenir des caracteres que certaines API digerent mal : on garde un
    # alphabet sur, et une longueur qui compense largement.
    $safe = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
    return ($safe + 'aA1!')
}

function Set-ServiceAccountReady {
    $account = Get-ServiceAccount
    $password = New-ServicePassword
    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    if (-not $account) {
        Say ("Création du compte " + $SERVICE_ACCOUNT + "...") 'Cyan'
        # 48 CARACTERES, PAS UN DE PLUS : c'est la limite que Windows impose a la
        # description d'un compte local. Une phrase de 66 signes a fait echouer la
        # premiere installation (28/08) -- et l'echec, lui, etait bien signale.
        New-LocalUser -Name $SERVICE_ACCOUNT -Password $secure -FullName 'Vigie - service local' `
                      -Description 'Service local de Vigie (pas de session)' `
                      -PasswordNeverExpires -UserMayNotChangePassword -ErrorAction Stop | Out-Null
    } else {
        Say ("Le compte " + $SERVICE_ACCOUNT + " existe : mot de passe renouvelé.") 'DarkGray'
        Set-LocalUser -Name $SERVICE_ACCOUNT -Password $secure -ErrorAction Stop
    }

    # Administrateur : le serveur tient le verrou de Windows Update et ecrit dans HKLM.
    try {
        $admins = (Get-LocalGroup -SID 'S-1-5-32-544').Name
        $member = @(Get-LocalGroupMember -Group $admins -ErrorAction SilentlyContinue |
                    Where-Object { "$($_.Name)" -like ('*\' + $SERVICE_ACCOUNT) })
        if (-not $member.Count) {
            Add-LocalGroupMember -Group $admins -Member $SERVICE_ACCOUNT -ErrorAction Stop
            Say "  ajouté aux administrateurs." 'DarkGray'
        }
    } catch { Say ("  groupe administrateurs : " + $_.Exception.Message) 'Yellow' }

    # MASQUE DE L'ECRAN DE CONNEXION. Ce compte n'est pas une personne : il n'a rien a
    # faire dans la liste des utilisateurs. C'est la meme cle que Vigie lit deja pour
    # reconnaitre un compte technique -- la boucle est bouclee.
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name $SERVICE_ACCOUNT -Value 0 -PropertyType DWord -Force | Out-Null
        Say "  masqué de l'écran de connexion." 'DarkGray'
    } catch { Say ("  masquage impossible : " + $_.Exception.Message) 'Yellow' }

    return $password
}

# --- La tache machine -----------------------------------------------------------------
function Register-ServiceTask {
    param([Parameter(Mandatory)][string]$Password)

    $pwsh = Get-SharedPwshPath
    if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $pwsh) { Say "PowerShell 7 introuvable pour la machine." 'Red'; return $false }

    # LE SERVEUR SUIT L'ENVIRONNEMENT DECLARE (D107) : sur un poste de developpement, il
    # tourne depuis le depot ; en production, depuis l'installation partagee.
    $appRoot = if ((Get-DeclaredEnvironment -Backend $backend) -eq 'dev') { Get-RepoRoot } else { Get-SharedInstallPath }
    if (-not $appRoot) { $appRoot = Get-RepoRoot }
    $start = Join-Path (Join-Path $appRoot 'apps/backend-pode') 'start.ps1'
    if (-not (Test-Path -LiteralPath $start)) { Say ("Serveur introuvable : " + $start) 'Red'; return $false }

    $action  = New-ScheduledTaskAction -Execute $pwsh `
                   -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $start + '"')
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId ("$env:COMPUTERNAME\$SERVICE_ACCOUNT") `
                     -LogonType Password -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    try {
        Register-ScheduledTask -TaskName $SERVICE_TASK -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Password $Password -Force -ErrorAction Stop | Out-Null
    } catch {
        Say ("Windows a refusé d'enregistrer la tâche : " + $_.Exception.Message) 'Red'
        return $false
    }

    # DESACTIVEE A LA CREATION. Deux serveurs sur le meme port se marcheraient dessus :
    # la bascule est un geste separe, et volontaire (-Activer).
    try { Disable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop | Out-Null } catch { }
    Say ("Tâche « " + $SERVICE_TASK + " » enregistrée, DÉSACTIVÉE.") 'Green'
    return $true
}

# --- Le droit de la relancer, pour les comptes ordinaires -----------------------------
#
# Le tray n'est pas eleve : sans ce droit, il ne pourrait ni arreter ni relancer le
# serveur. Windows l'accorde par le descripteur de securite de la tache.
function Grant-TaskControl {
    try {
        $sddl = 'D:(A;;GA;;;BA)(A;;GA;;;SY)(A;;GRGX;;;BU)'   # admins+systeme total, utilisateurs lecture+execution
        $out = & schtasks.exe /change /TN $SERVICE_TASK /RU ("$env:COMPUTERNAME\$SERVICE_ACCOUNT") 2>&1
        $null = $out
        $folder = New-Object -ComObject 'Schedule.Service'
        $folder.Connect()
        $task = $folder.GetFolder('\').GetTask($SERVICE_TASK)
        $task.SetSecurityDescriptor($sddl, 0)
        Say "Les comptes de la machine peuvent démarrer et arrêter le service." 'DarkGray'
        return $true
    } catch {
        Say ("Droits sur la tâche non posés : " + $_.Exception.Message) 'Yellow'
        Say "Le tray d'un compte standard ne pourra pas relancer le serveur." 'Yellow'
        return $false
    }
}

# --- Retrait --------------------------------------------------------------------------
function Remove-Service {
    $done = $true
    if (Get-ServiceTask) {
        try { Unregister-ScheduledTask -TaskName $SERVICE_TASK -Confirm:$false -ErrorAction Stop; Say "Tâche retirée." 'Green' }
        catch { Say ("Tâche non retirée : " + $_.Exception.Message) 'Red'; $done = $false }
    }
    if (Get-ServiceAccount) {
        try { Remove-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop; Say "Compte retiré." 'Green' }
        catch { Say ("Compte non retiré : " + $_.Exception.Message) 'Red'; $done = $false }
    }
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if (Test-Path -LiteralPath $key) { Remove-ItemProperty -Path $key -Name $SERVICE_ACCOUNT -ErrorAction SilentlyContinue }
    } catch { }
    return $done
}

# --- Deroulement ----------------------------------------------------------------------
if ($Lister) { Show-State; exit 0 }

if (-not (Test-IsElevated)) {
    Say "Cette opération crée un compte et une tâche machine : elle demande l'élévation." 'Yellow'
    Say "Rien n'a été touché." 'Yellow'
    exit 1
}

if ($Retirer) {
    Show-State
    if (Remove-Service) { Show-State; exit 0 }
    exit 2
}

Show-State

# UNE ETAPE QUI ECHOUE LE DIT, elle ne plante pas. Sans ce filet, l'erreur remontait
# brute et le script rendait 1 sans expliquer ce qui n'allait pas.
try {
    $password = Set-ServiceAccountReady
} catch {
    Say ("Le compte de service n'a pas pu être préparé : " + $_.Exception.Message) 'Red'
    exit 2
}
if (-not (Register-ServiceTask -Password $password)) { exit 2 }
$null = Grant-TaskControl
# Le mot de passe ne sert plus a rien : Windows le detient. On l'efface de la memoire.
$password = $null
[System.GC]::Collect()

Say ""
Say "Service prêt, mais DÉSACTIVÉ : rien ne change au démarrage tant qu'on ne bascule pas." 'Cyan'
Say "Pour basculer : pwsh -File .\scripts\install-service.ps1 -Activer" 'DarkGray'
Show-State
exit 0
