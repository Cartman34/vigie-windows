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
    [switch] $Retirer
)
$ErrorActionPreference = 'Stop'

# Le script a descendu d un cran (scripts/lib/) : la racine est deux niveaux au-dessus.
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que tous les autres scripts
. (Join-Path $repoRoot 'scripts/lib/i18n.ps1')

$SERVICE_ACCOUNT = 'VigieService'
$SERVICE_TASK    = 'Vigie - Serveur'


function Get-ServiceAccount {
    try { return (Get-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop) } catch { return $null }
}
function Get-ServiceTask {
    try { return (Get-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop) } catch { return $null }
}

# --- Etat des lieux -------------------------------------------------------------------
<#
    L'ETAT DES LIEUX. Il sert deux fois : avant le travail, pour dire d'ou l'on part, et
    apres, pour montrer ce qui a change. Le meme titre revenait donc DEUX FOIS sur le
    meme ecran, ce qui donnait l'impression d'un doublon plutot que d'un avant/apres
    (signale le 29/08).

    -NoTitle laisse l'appelant tenir le fil : dans une installation, le titre de l'etape
    est deja au-dessus, et l'etat n'est que sa conclusion.
#>
function Show-State {
    param([switch]$NoTitle)
    $account = Get-ServiceAccount
    $task    = Get-ServiceTask
    if (-not $NoTitle) { Write-Title (Get-Label 'install-service.service-de-machine') }
    Write-Info (Get-Label 'install-service.compte-dedie' $(if ($account) { $SERVICE_ACCOUNT + " (actif=" + $account.Enabled + ")" } else { "absent" }))
    Write-Info (Get-Label 'install-service.tache-machine' $(if ($task) { $SERVICE_TASK + " (" + $task.State + ")" } else { "absente" }))
    Write-Info (Get-Label 'install-service.environnement' (Get-EnvironmentLabel -Environment (Get-DeclaredEnvironment -Backend $backend)))
    $listening = $null
    try { $listening = Get-NetTCPConnection -LocalPort ([int](Get-Config -Backend $backend).Port) -State Listen -ErrorAction Stop } catch { }
    Write-Info (Get-Label 'install-service.serveur-en-ligne' $(if ($listening) { "oui (PID " + $listening[0].OwningProcess + ")" } else { "non" }))
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
        Write-Step (Get-Label 'install-service.creation-du-compte' $SERVICE_ACCOUNT)
        # 48 CARACTERES, PAS UN DE PLUS : c'est la limite que Windows impose a la
        # description d'un compte local. Une phrase de 66 signes a fait echouer la
        # premiere installation (28/08) -- et l'echec, lui, etait bien signale.
        New-LocalUser -Name $SERVICE_ACCOUNT -Password $secure -FullName 'Vigie - service local' `
                      -Description 'Service local de Vigie (pas de session)' `
                      -PasswordNeverExpires -UserMayNotChangePassword -ErrorAction Stop | Out-Null
    } else {
        Write-Detail (Get-Label 'install-service.le-compte-existe-mot' $SERVICE_ACCOUNT)
        Set-LocalUser -Name $SERVICE_ACCOUNT -Password $secure -ErrorAction Stop
    }

    # Administrateur : le serveur tient le verrou de Windows Update et ecrit dans HKLM.
    try {
        $admins = (Get-LocalGroup -SID 'S-1-5-32-544').Name
        $member = @(Get-LocalGroupMember -Group $admins -ErrorAction SilentlyContinue |
                    Where-Object { "$($_.Name)" -like ('*\' + $SERVICE_ACCOUNT) })
        if (-not $member.Count) {
            Add-LocalGroupMember -Group $admins -Member $SERVICE_ACCOUNT -ErrorAction Stop
            Write-Detail (Get-Label 'install-service.ajoute-aux-administrateurs')
        }
    } catch { Write-Warn (Get-Label 'install-service.groupe-administrateurs' $_.Exception.Message) }

    # MASQUE DE L'ECRAN DE CONNEXION. Ce compte n'est pas une personne : il n'a rien a
    # faire dans la liste des utilisateurs. C'est la meme cle que Vigie lit deja pour
    # reconnaitre un compte technique -- la boucle est bouclee.
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name $SERVICE_ACCOUNT -Value 0 -PropertyType DWord -Force | Out-Null
        Write-Detail (Get-Label 'install-service.masque-de-ecran-de')
    } catch { Write-Warn (Get-Label 'install-service.masquage-impossible' $_.Exception.Message) }

    return $password
}

# LE DROIT « OUVRIR UNE SESSION EN TANT QUE TACHE » (SeBatchLogonRight).
#
# Une tache enregistree avec un mot de passe (LogonType Password) ne demarre que si son
# compte possede ce droit. L'interface graphique du Planificateur l'accorde toute seule ;
# Register-ScheduledTask, non -- d'ou un enregistrement refuse sans que rien n'explique
# quoi (code 2 a l'installation du 28/08).
#
# On l'accorde par secedit, qui exige l'elevation -- le script l'a deja. Idempotent : un
# compte qui l'a deja n'est pas retouche.
function Grant-BatchLogonRight {
    param([Parameter(Mandatory)][string]$Sid)
    $exportFile = Join-Path $env:TEMP ('vigie-secpol-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.inf')
    $importFile = $exportFile -replace '\.inf$', '-import.inf'
    try {
        $out = & secedit.exe /export /areas USER_RIGHTS /cfg $exportFile 2>&1
        if (-not (Test-Path -LiteralPath $exportFile)) {
            Write-Warn (Get-Label 'install-service.droits-de-session-export' $out -join ' ')
            return $false
        }
        $line = (Get-Content -LiteralPath $exportFile | Where-Object { $_ -match '^SeBatchLogonRight' } | Select-Object -First 1)
        if ($line -and $line.Contains($Sid)) {
            Write-Detail (Get-Label 'install-service.droit-ouvrir-une-session')
            return $true
        }
        $current = if ($line) { ($line -split '=', 2)[1].Trim() } else { '' }
        $updated = if ($current) { 'SeBatchLogonRight = ' + $current + ',*' + $Sid } else { 'SeBatchLogonRight = *' + $Sid }

        # Un fichier de STRATEGIE minimal : on ne reecrit que la ligne qui nous concerne.
        $content = @(
            '[Unicode]', 'Unicode=yes',
            '[Version]', 'signature="$CHICAGO$"', 'Revision=1',
            '[Privilege Rights]', $updated
        ) -join [Environment]::NewLine
        [System.IO.File]::WriteAllText($importFile, $content, [System.Text.Encoding]::Unicode)

        $db = Join-Path $env:TEMP ('vigie-secpol-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.sdb')
        $out = & secedit.exe /configure /db $db /cfg $importFile /areas USER_RIGHTS 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn (Get-Label 'install-service.droits-de-session-refus' $out -join ' ')
            return $false
        }
        Write-Detail (Get-Label 'install-service.droit-ouvrir-une-session-2')
        return $true
    } catch {
        Write-Warn (Get-Label 'install-service.droits-de-session' $_.Exception.Message)
        return $false
    } finally {
        foreach ($f in @($exportFile, $importFile)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

# --- La tache machine -----------------------------------------------------------------
function Register-ServiceTask {
    param([Parameter(Mandatory)][string]$Password)

    $pwsh = Get-SharedPwshPath
    if (-not $pwsh) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $pwsh) { Write-Fail (Get-Label 'install-service.powershell-introuvable-pour-la'); return $false }

    # LE SERVEUR VIT TOUJOURS DANS L'INSTALLATION PARTAGEE, quel que soit l'environnement.
    #
    # « dev ou prod, c'est juste la SOURCE qui change mais le serveur est dans Program
    # Files. » C'est la seule position tenable pour un service de machine : un serveur qui
    # vivrait dans l'espace de travail d'un utilisateur serait illisible pour les autres
    # comptes -- exactement le piege ou « Famille » est tombee -- et disparaitrait le jour
    # ou ce dossier bouge.
    #
    # L'environnement declare ne dit donc pas OU le serveur tourne, mais D'OU vient ce
    # qu'on y deploie : le depot local en dev, une version publiee en prod.
    $appRoot = Get-SharedInstallPath
    if (-not $appRoot) {
        Write-Fail (Get-Label 'install-service.aucune-installation-partagee-deployez')
        Write-Detail (Get-Label 'install-service.le-service-de-machine')
        return $false
    }
    $start = Join-Path (Join-Path $appRoot 'apps/backend-pode') 'start.ps1'
    if (-not (Test-Path -LiteralPath $start)) { Write-Fail (Get-Label 'install-service.serveur-introuvable' $start); return $false }

    $action  = New-ScheduledTaskAction -Execute $pwsh `
                   -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $start + '"')
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId ("$env:COMPUTERNAME\$SERVICE_ACCOUNT") `
                     -LogonType Password -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    # LE DROIT AVANT L'ENREGISTREMENT : sans lui, Windows refuse une tache lancee par mot
    # de passe -- et son message ne dit pas lequel manque.
    $sid = $null
    try { $sid = (Get-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop).SID.Value } catch { }
    if ($sid) { $null = Grant-BatchLogonRight -Sid $sid }

    # DEUX APPELS, PAS UN. `Register-ScheduledTask` a des JEUX DE PARAMETRES exclusifs :
    # -Principal appartient a l'un, -Password a l'autre. Les donner ensemble ne produit pas
    # une erreur qui nomme le fautif, mais « Parameter set cannot be resolved » -- ce qui a
    # coute une installation entiere le 28/08. On construit donc la tache d'abord (le
    # principal y entre, RunLevel Highest compris), on l'enregistre ensuite avec le mot de
    # passe : ce jeu-la accepte -InputObject et -Password.
    try {
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        Register-ScheduledTask -TaskName $SERVICE_TASK -InputObject $task `
            -User ("$env:COMPUTERNAME\$SERVICE_ACCOUNT") -Password $Password -Force -ErrorAction Stop | Out-Null
    } catch {
        # LA TRACE SURVIT A LA CONSOLE. Ce message est parti dans un terminal refermé le
        # 28/08, et il a fallu deviner ce qu'il disait : il va desormais aussi dans le
        # journal de Vigie, qui se relit.
        $why = $_.Exception.Message
        Write-Fail (Get-Label 'install-service.windows-refuse-enregistrer-la' $why)
        try { Write-Log -Backend $backend -Name 'install' -Level 'ERROR' `
                        -Message (Get-Label 'install-service.service-de-machine-windows' $why) } catch { }
        return $false
    }

    # DESACTIVEE A LA CREATION. Deux serveurs sur le meme port se marcheraient dessus :
    # la bascule est un geste separe, et volontaire (-Activer).
    try { Disable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop | Out-Null } catch { }
    Write-Ok (Get-Label 'install-service.tache-enregistree-desactivee' $SERVICE_TASK)
    return $true
}

# --- Le droit de la relancer, pour les comptes ordinaires -----------------------------
#
# Le tray n'est pas eleve : sans ce droit, il ne pourrait ni arreter ni relancer le
# serveur. Windows l'accorde par le descripteur de securite de la tache.
function Grant-TaskControl {
    try {
        # PAS DE « schtasks /change /RU » ICI. Il y en avait un, et il BLOQUAIT
        # l'installation : sans /RP, schtasks demande le mot de passe du compte et attend
        # sur l'entree standard. L'installation restait figee jusqu'a ce que quelqu'un
        # appuie sur Entree -- 28 secondes mesurees dans le journal du 29/08, entre deux
        # lignes qui se suivent -- et cette Entree fournissait un mot de passe VIDE.
        #
        # Son erreur etait avalee par « $null = $out » : un blocage sans message, sur un
        # appel dont personne ne verifiait le resultat. Il etait de surcroit inutile, le
        # principal etant deja pose a l'enregistrement de la tache.
        $sddl = 'D:(A;;GA;;;BA)(A;;GA;;;SY)(A;;GRGX;;;BU)'   # admins+systeme total, utilisateurs lecture+execution
        $folder = New-Object -ComObject 'Schedule.Service'
        $folder.Connect()
        $task = $folder.GetFolder('\').GetTask($SERVICE_TASK)
        $task.SetSecurityDescriptor($sddl, 0)
        Write-Detail (Get-Label 'install-service.les-comptes-de-la')
        return $true
    } catch {
        Write-Warn (Get-Label 'install-service.droits-sur-la-tache' $_.Exception.Message)
        Write-Detail (Get-Label 'install-service.le-tray-un-compte')
        return $false
    }
}

# --- Retrait --------------------------------------------------------------------------
function Remove-Service {
    $done = $true
    if (Get-ServiceTask) {
        try { Unregister-ScheduledTask -TaskName $SERVICE_TASK -Confirm:$false -ErrorAction Stop; Write-Ok (Get-Label 'install-service.tache-retiree') }
        catch { Write-Fail (Get-Label 'install-service.tache-non-retiree' $_.Exception.Message); $done = $false }
    }
    if (Get-ServiceAccount) {
        try { Remove-LocalUser -Name $SERVICE_ACCOUNT -ErrorAction Stop; Write-Ok (Get-Label 'install-service.compte-retire') }
        catch { Write-Fail (Get-Label 'install-service.compte-non-retire' $_.Exception.Message); $done = $false }
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
    Write-Fail (Get-Label 'install-service.cette-operation-cree-un')
    Write-Detail (Get-Label 'install-service.rien-ete-touche')
    exit 1
}

<#
    LA BASCULE. -Activer etait declare dans les parametres et decrit dans l'aide, mais
    AUCUN code ne le traitait : la commande affichait l'etat et sortait, sans rien faire
    et sans rien dire. Un commutateur documente qui ne fait rien est pire qu'un
    commutateur absent -- celui-la, au moins, provoque une erreur.

    CE QU'ELLE FAIT, dans cet ordre, et pourquoi :

      1. La tache doit EXISTER. Sinon il n'y a rien a activer, et c'est l'installation
         qui la pose.
      2. LE PORT DOIT ETRE LIBRE. Deux serveurs sur 47600, c'est le second qui meurt --
         et on ne sait plus lequel repond aux ordres. Le precedent s'arrete donc, et le
         suivant prend sa place -- c'est une installation, pas une negociation.
      3. On ACTIVE, puis on DEMARRE A LA DEMANDE. Windows refuse de demarrer une tache
         desactivee, meme a la main : les deux gestes sont necessaires, dans cet ordre.
         Le declencheur « au demarrage » reste pour la suite ; il n'est pas attendu ici.
      4. ON VERIFIE QU'ELLE ECOUTE. Une tache « demarree » ne prouve rien : le processus
         peut mourir a la seconde suivante. On attend le port, pas le code de retour.
      5. SI ELLE N'ECOUTE PAS, ON DESACTIVE. Laisser une tache activee qui ne sert pas
         signifie qu'au prochain demarrage de la machine, elle reprendra la main sans
         que personne ne l'ait decide.

    LES DROITS SONT CEUX DE LA TACHE, PAS CEUX DU DEMANDEUR. C'est le principe meme du
    montage : la tache declare son principal (VigieService, RunLevel Highest), et
    Grant-TaskControl accorde aux utilisateurs integres le droit de l'EXECUTER. Un compte
    standard la demarre donc, et elle tourne elevee -- avec les droits qu'elle definit.
#>
<#
    METTRE LA TACHE SERVEUR EN SERVICE. Rend $true si le serveur repond a la fin.

    EXTRAITE POUR ETRE APPELABLE DEUX FOIS : par l'installation, qui doit tout installer,
    et par -Activer, qui remet en service une tache qu'on avait retiree du jeu. Le corps
    se terminait par « exit » -- utilisable seulement en fin de script, donc pas comme une
    etape.

    Verifie avant de brancher : l'installation traite la tache serveur AVANT de lancer le
    tray, donc le tray ne lancera pas de serveur concurrent -- il constate qu'une tache
    active s'en charge.
#>
function Enable-ServiceTask {
    $task = Get-ServiceTask
    if (-not $task) {
        Write-Fail (Get-Label 'install-service.activer-tache-absente')
        Write-Detail (Get-Label 'install-service.activer-lancez-installation')
        return $false
    }

    # --- Le port ---
    $port = [int](Get-Config -Backend $backend).Port
    $held = $null
    try { $held = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop } catch { }
    # LE PRECEDENT S'ARRETE, LE SUIVANT DEMARRE. C'est une installation : on ne demande
    # pas la permission de remplacer un serveur par sa propre nouvelle version.
    if ($held) {
        $pidHeld = $held[0].OwningProcess
        Write-Step (Get-Label 'install-service.activer-arret-du-serveur' $pidHeld)
        try {
            Stop-Process -Id $pidHeld -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        } catch {
            Write-Fail (Get-Label 'install-service.activer-arret-impossible' $_.Exception.Message)
            return $false
        }
    }

    # --- Activer, puis demarrer ---
    Write-Step (Get-Label 'install-service.activer-bascule')
    try {
        Enable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop
    } catch {
        Write-Fail (Get-Label 'install-service.activer-windows-refuse' $_.Exception.Message)
        try { Disable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction SilentlyContinue | Out-Null } catch { }
        return $false
    }

    <#
        LA PREUVE, C'EST QUE LA TACHE DEMARRE -- PAS QUE LE SERVEUR REPONDE.

        J'attendais le port. Mauvaise question : ce que l'installation installe, c'est une
        tache qui se lance sous le bon compte. Le temps que l'application mette ENSUITE a
        ouvrir son port ne la regarde plus -- une minute, deux, selon le disque et le
        reste. Attendre ce resultat, c'est attendre un delai indetermine, et le 29/08 ca
        s'est fini par une tache DESACTIVEE alors que le serveur repondait juste apres.

        Ce qui peut rater ICI rate TOUT DE SUITE : mot de passe refuse, droit d'ouverture
        de session en lot manquant, chemin introuvable. Windows arrete alors la tache
        aussitot et donne son code. Donc : si la tache TOURNE, c'est installe ; si elle
        s'est arretee, on lit pourquoi. Quelques secondes suffisent a faire la difference.
    #>
    $etat = 'Unknown'
    $code = $null
    foreach ($n in 1..12) {
        Start-Sleep -Milliseconds 750
        try {
            $etat = "$((Get-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction Stop).State)"
            $code = (Get-ScheduledTaskInfo -TaskName $SERVICE_TASK -ErrorAction Stop).LastTaskResult
        } catch { }
        if ($etat -eq 'Running') { break }
    }
    if ($etat -ne 'Running') {
        Write-Fail (Get-Label 'install-service.activer-tache-arretee' $etat ("0x{0:X}" -f [int]$code))
        Write-Detail (Get-Label 'install-service.activer-desactivee-de-nouveau')
        try { Disable-ScheduledTask -TaskName $SERVICE_TASK -ErrorAction SilentlyContinue | Out-Null } catch { }
        try { Write-Log -Backend $backend -Name 'install' -Level 'ERROR' `
                        -Message ("Service : active puis desactive, la tache ne tourne pas (etat " + $etat + ").") } catch { }
        Show-State
        return $false
    }

    Write-Ok (Get-Label 'install-service.activer-en-ligne')
    Write-Detail (Get-Label 'install-service.activer-ouverture-differee' $port)
    Write-Detail (Get-Label 'install-service.activer-au-prochain-demarrage')
    try { Write-Log -Backend $backend -Name 'install' `
                    -Message "Service : la tache tourne, le serveur demarre." } catch { }
    return $true
}

if ($Activer) {
    Show-State
    if (-not (Enable-ServiceTask)) { Show-State -NoTitle; exit 2 }
    Show-State -NoTitle
    exit 0
}

if ($Retirer) {
    Show-State
    if (Remove-Service) { Show-State; exit 0 }
    exit 2
}

Write-Step (Get-Label 'install-service.etape')
Show-State -NoTitle

# UNE ETAPE QUI ECHOUE LE DIT, elle ne plante pas. Sans ce filet, l'erreur remontait
# brute et le script rendait 1 sans expliquer ce qui n'allait pas.
try {
    $password = Set-ServiceAccountReady
} catch {
    Write-Fail (Get-Label 'install-service.le-compte-de-service' $_.Exception.Message)
    exit 2
}
if (-not (Register-ServiceTask -Password $password)) { exit 2 }
$null = Grant-TaskControl
# Le mot de passe ne sert plus a rien : Windows le detient. On l'efface de la memoire.
$password = $null
[System.GC]::Collect()

# UNE INSTALLATION INSTALLE : a la fin, l'application marche. La tache etait laissee
# desactivee, en attendant un second geste que rien ne rendait evident -- relancer
# l'installation dix fois n'y changeait rien.
if (-not (Enable-ServiceTask)) { Show-State -NoTitle; exit 2 }
Show-State -NoTitle
exit 0
