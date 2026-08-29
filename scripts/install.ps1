<#
    install.ps1 - Installe les prerequis. IDEMPOTENT. Cible PowerShell 7.
    Journalise dans backend/logs/install_*.log (transcript). Fichier en ASCII
    pour rester lisible par PowerShell 5.1 au moment de basculer en pwsh.

    Portee des modules :
      - eleve (admin)     -> AllUsers  : C:\Program Files\PowerShell\Modules
                             (visible par TOUS les PowerShell 7 : MSI, Store,
                              tache planifiee, eleve ou non). Recommande.
      - non eleve         -> CurrentUser (repli).

    Usage :  powershell -File .\install.ps1   (basculera en pwsh)
#>
$ErrorActionPreference = 'Stop'

# LE MEME AFFICHAGE QUE PARTOUT. Charge des le debut, avant meme la bascule en
# PowerShell 7 : cette premiere passe tourne sous 5.1, et elle affiche deja.
. (Join-Path $PSScriptRoot 'lib/console-ui.ps1')

# --- Cible PowerShell 7 : bascule si lance en 5.1 ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # L'interpreteur de la MACHINE d'abord : c'est celui que lanceront les taches de
    # demarrage, donc celui avec lequel il faut installer.
    $pwsh = Join-Path (Join-Path (Join-Path $env:ProgramFiles 'PowerShell') '7') 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwsh)) {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    }
    if ($pwsh) {
        Write-Info (Get-Label 'install.bascule-en-powershell')
        & $pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        # LE CODE DE LA PASSE LANCEE EST LE NOTRE. Sans cette ligne, un echec de
        # l'installation reelle remontait en succes a l'appelant : le lanceur affichait
        # « Termine » sur une installation ratee (constate le 26/08).
        exit $LASTEXITCODE
    }
    Write-Step (Get-Label 'install.powershell-est-absent-installation')
    # L'ELEVATION est indispensable ici : une installation en portee machine sans droits
    # administrateur echoue sur « 0x80070005 : Access is denied » -- et winget ayant deja
    # retire l'eventuelle version du compte, la machine se retrouve SANS PowerShell 7
    # (vecu le 26/08). On le dit AVANT d'essayer, plutot que de laisser ce trou.
    $estAdmin = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $estAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
                        [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }
    if (-not $estAdmin) {
        Write-Fail (Get-Label 'install.cette-etape-doit-etre')
        Write-Detail (Get-Label 'install.double-cliquez-sur-setup')
                return
    }
    $cible = Join-Path (Join-Path (Join-Path $env:ProgramFiles 'PowerShell') '7') 'pwsh.exe'

    # 1) winget, en imposant le MSI.
    #
    # Deux pieges rencontres le 26/08, dans cet ordre :
    #   - sans --installer-type msi, winget prend le MSIXBUNDLE et tente de le
    #     « provisionner » pour tous les comptes : echec 0x80070005 -- et il avait DEJA
    #     desinstalle la version du compte, la machine s'est donc retrouvee SANS
    #     PowerShell du tout ;
    #   - avec --installer-type msi, la source winget n'a AUCUN paquet MSI pour cet
    #     identifiant : elle balaie toutes les versions puis renonce (0x8a150010).
    # D'ou le repli ci-dessous. Un installateur doit ABOUTIR, pas renvoyer l'utilisateur
    # vers une page de telechargement.
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.PowerShell -e --scope machine --installer-type msi --source winget --accept-package-agreements --accept-source-agreements
    }

    # 2) Repli : le MSI publie par l'equipe PowerShell, installe pour TOUTE la machine.
    if (-not (Test-Path -LiteralPath $cible)) {
        Write-Warn (Get-Label 'install.winget-pas-de-paquet')
        try {
            # TLS 1.2 : Windows PowerShell 5.1 ne l'active pas toujours, et GitHub refuse
            # tout le reste. Sans cette ligne, le telechargement echoue sur une erreur de
            # connexion qui n'explique rien.
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
                                     -Headers @{ 'User-Agent' = 'Vigie-install' } -TimeoutSec 60
            $asset = @($rel.assets | Where-Object { $_.name -like '*-win-x64.msi' }) | Select-Object -First 1
            if (-not $asset) { throw "aucun MSI x64 dans la derniere version publiee" }
            $msi = Join-Path $env:TEMP $asset.name
            # SANS CECI, Windows PowerShell 5.1 s'enlise : le rendu de sa barre de
            # progression coute plus cher que le telechargement lui-meme, et sur 108 Mo
            # la commande semble figee de longues minutes APRES que le fichier soit
            # complet -- constate le 26/08, fichier entier sur disque et script toujours
            # en attente. C'est un defaut connu de 5.1 ; on eteint la barre.
            $ProgressPreference = 'SilentlyContinue'
            $mo  = [math]::Round(([double]$asset.size) / 1MB, 1)
            # Deja telecharge ET complet ? On ne recommence pas : une tentative
            # precedente peut avoir bute apres coup (voir ci-dessus).
            $dejaLa = $false
            if (Test-Path -LiteralPath $msi) {
                $dejaLa = ((Get-Item -LiteralPath $msi).Length -eq [long]$asset.size)
                if (-not $dejaLa) { Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue }
            }
            if ($dejaLa) {
                Write-Detail (Get-Label 'install.deja-telecharge-mo' $asset.name $mo)
            } else {
                Write-Info (Get-Label 'install.telechargement-de-mo' $asset.name $mo)
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing -TimeoutSec 900
                Write-Detail (Get-Label 'install.telechargement-termine')
            }
            Write-Info (Get-Label 'install.installation-pour-toute-la')
            # ALLUSERS=1 : installation MACHINE. /qn : sans interface, on est deja eleve.
            # /qb et non /qn : une installation de deux minutes doit se VOIR. Une barre
            # de progression vaut mieux qu'une fenetre muette dont on ne sait pas si elle
            # travaille ou si elle est bloquee.
            $mi = Start-Process -FilePath 'msiexec.exe' -Wait -PassThru -ArgumentList @(
                      '/i', ('"' + $msi + '"'), '/qb', 'ALLUSERS=1', 'ADD_PATH=1')
            # LE RESULTAT SE LIT. 0 = installe ; 3010 = installe, redemarrage demande ;
            # 1618 = un autre installateur travaille deja ; le reste est un echec qu'il
            # faut nommer, pas passer sous silence.
            switch ([int]$mi.ExitCode) {
                0    { Write-Ok (Get-Label 'install.installation-reussie') }
                3010 { Write-Warn (Get-Label 'install.installee-windows-demande-un') }
                1618 { Write-Warn (Get-Label 'install.un-autre-installateur-windows') }
                default { Write-Fail (Get-Label 'install.msiexec-echoue-code' $mi.ExitCode) }
            }
            if ([int]$mi.ExitCode -eq 0 -or [int]$mi.ExitCode -eq 3010) {
                Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Fail (Get-Label 'install.echec-du-repli-msi' $_.Exception.Message)
        }
    }

    # 3) On CONSTATE, et on enchaine tout seul : l'utilisateur n'a pas a relancer.
    if (Test-Path -LiteralPath $cible) {
        Write-Ok (Get-Label 'install.powershell-installe-pour-la' $cible)
        Write-Detail (Get-Label 'install.installation-se-poursuit-avec')
        & $cible -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
    Write-Fail (Get-Label 'install.powershell-pas-pu-etre')
    Write-Detail (Get-Label 'install.telechargez-le-msi-la')
    Write-Detail (Get-Label 'install.fichier-powershell-version-win')
    exit 1
}

Write-Title (Get-Label 'install.titre')
Write-Step (Get-Label 'install.etape-prerequis')

# Les scripts de gestion vivent dans scripts/ : les apps sont dans apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

# --- VIGIE S'INSTALLE DANS PROGRAM FILES ------------------------------------
#
# Une application Windows vit dans Program Files, pas dans le dossier ou l'archive a
# ete decompressee. Sans cette copie, la tache de demarrage pointait sur ce dossier :
# l'utilisateur devait le garder a vie, et le vider par megarde cassait Vigie.
#
# Trois cas OU L'ON NE BOUGE PAS :
#   - un DEPOT git : c'est un poste de developpement, Vigie tourne depuis les sources ;
#   - on y est deja : la copie relancerait le script indefiniment ;
#   - sans elevation : ecrire dans Program Files est refuse. On le dit, et on continue
#     sur place plutot que d'echouer -- Vigie reste utilisable.
$destPartagee = Join-Path $env:ProgramFiles (Join-Path 'Sowapps' 'Vigie')
$ici          = (Resolve-Path -LiteralPath $repoRoot).Path
$estDepot     = Test-Path -LiteralPath (Join-Path $repoRoot '.git')
$dejaLa       = ($ici.TrimEnd([char]92) -ieq $destPartagee.TrimEnd([char]92))

if (-not $estDepot -and -not $dejaLa) {
    if (-not (Test-Elevated)) {
        Write-Warn (Get-Label 'install.sans-droits-administrateur-vigie')
        Write-Detail (Get-Label 'install.elle-fonctionnera-depuis-ce')
    } else {
        Write-Step (Get-Label 'install.installation-de-vigie-dans' $destPartagee)
        $copieFaite = $false
        try {
            # Les REGLAGES de la machine deja poses survivent : les ecraser serait une
            # regression a chaque mise a jour (meme regle que deploy-prod.ps1).
            $cfgDest = Join-Path $destPartagee 'config'
            $garde   = $null
            if (Test-Path -LiteralPath $cfgDest) {
                $garde = Join-Path $env:TEMP ('vigie-cfg-' + [guid]::NewGuid().ToString('N').Substring(0,8))
                New-Item -ItemType Directory -Path $garde -Force | Out-Null
                foreach ($motif in @('*.local.*', 'actions.policy.json')) {
                    Get-ChildItem -Path $cfgDest -File -Filter $motif -ErrorAction SilentlyContinue |
                        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $garde -Force }
                }
            }

            New-Item -ItemType Directory -Path $destPartagee -Force | Out-Null
            # var/ ne se copie pas : jeton, journaux et caches appartiennent a l'endroit
            # ou Vigie tourne, pas a la version qu'on installe.
            Get-ChildItem -LiteralPath $repoRoot -Force |
                Where-Object { $_.Name -ne 'var' -and $_.Name -ne '.git' } |
                ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destPartagee -Recurse -Force }

            if ($garde) {
                New-Item -ItemType Directory -Path $cfgDest -Force | Out-Null
                Get-ChildItem -Path $garde -File | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $cfgDest -Force
                }
                Remove-Item -LiteralPath $garde -Recurse -Force -ErrorAction SilentlyContinue
                Write-Detail (Get-Label 'install.reglages-de-la-machine')
            }
            $copieFaite = Test-Path -LiteralPath (Join-Path $destPartagee 'setup.cmd')
        } catch {
            Write-Fail (Get-Label 'install.la-copie-echoue' $_.Exception.Message)
        }

        if ($copieFaite) {
            # LA SUITE SE FAIT LA-BAS. C'est la copie installee qui pose la tache de
            # demarrage : sinon la tache pointerait encore sur le dossier telecharge.
            Write-Detail (Get-Label 'install.installation-se-poursuit-depuis')
            $suite = Join-Path (Join-Path $destPartagee 'scripts') 'install.ps1'
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $suite
            exit $LASTEXITCODE
        }
        Write-Warn (Get-Label 'install.vigie-fonctionnera-depuis-ce')
    }
}

$logDir = Get-LogDir -Backend $backend
$log    = Join-Path $logDir ('install_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }

try {
    $isAdmin = Test-Elevated
    $scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }
    Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-powershell-eleve-portee' $PSVersionTable.PSVersion $isAdmin $scope)

    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-du-provider-nuget')
        Install-PackageProvider -Name NuGet -Force -Scope $scope | Out-Null
    } else { Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.provider-nuget-deja-present') }

    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # Chemin AllUsers de reference (partage par tous les PS7).
    $allUsersPode = Join-Path $env:ProgramFiles 'PowerShell\Modules\Pode'

    if ($isAdmin) {
        # En admin : on garantit une copie AllUsers, visible par tous les PS7.
        if (Test-Path $allUsersPode) {
            $v = (Get-ChildItem $allUsersPode -Directory -ErrorAction SilentlyContinue | Select-Object -Last 1).Name
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-allusers-deja-present' $v)
        } else {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-de-pode-allusers')
            Install-Module Pode -Scope AllUsers -Force
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-installe-allusers')
        }
    } else {
        if (Get-Module -ListAvailable -Name Pode) {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-deja-installe' (Get-Module -ListAvailable -Name Pode | Select-Object -First 1).Version)
        } else {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-de-pode-currentuser')
            Install-Module Pode -Scope CurrentUser -Force
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-installe-currentuser')
        }
    }

    # --- DEPENDANCE : PowerShell 7 doit etre installe POUR LA MACHINE -----------
    # Vigie demarre par une tache planifiee, une par compte. Un pwsh installe pour le
    # seul compte courant (paquet du Store) vit dans SON profil : la tache des autres
    # comptes pointerait dans un dossier qu'ils ne peuvent pas lire. On le traite ICI,
    # a l'installation, plutot que de le decouvrir le jour ou un compte ne demarre pas.
    $pwshMachine = Get-SharedPwshPath
    if ($pwshMachine) {
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.powershell-machine-present' $pwshMachine)
    } elseif ($isAdmin -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.powershell-existe-que-pour')
        try {
            & 'winget.exe' @(Get-SharedPwshInstallArgs) | Write-Host
            $pwshMachine = Get-SharedPwshPath
        } catch { }
        if ($pwshMachine) {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.powershell-machine-installe' $pwshMachine)
        } else {
            Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.powershell-machine-installation-sans')
        }
    } else {
        Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.powershell-est-installe-que')
        Write-Detail (Get-Label 'install.faire-une-fois-en')
        Write-Detail (Get-Label 'install.winget-install-id-microsoft')
    }

    # LA TRACE AVANT LES DROITS. Poser la source du journal des evenements exige
    # l'elevation : c'est donc ici, une fois, et pas au premier usage. Sans elle, une
    # action privilegiee ne laisserait qu'une trace dans un fichier -- effacable.
    if ($isAdmin) {
        if (Register-VigieEventSource) {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.journal-des-evenements-source')
        } else {
            Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.journal-des-evenements-source-2')
        }
    }

    $null = Get-ApiToken -Backend $backend
    Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.jeton-api-pret-backend')

    $wvKeys = @(
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    $wv = $false; foreach ($k in $wvKeys) { if (Test-Path $k) { $wv = $true } }
    Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.webview2-runtime' $(if ($wv) { 'présent' } else { 'absent' }))

    # --- L'INSTALLATION VA JUSQU'AU BOUT ---------------------------------------
    # « Le script d'install est cense tout faire » : il ne s'arrete donc pas aux
    # prerequis pour renvoyer l'utilisateur vers deux autres commandes. Il enregistre
    # le demarrage automatique et lance l'application.
    #
    # C'est aussi ce qui REPARE une tache existante : elle est reecrite avec
    # l'interpreteur de la machine. Le 26/08, la tache pointait vers le pwsh du paquet
    # Store, supprime entre-temps -- Vigie ne demarrait plus du tout, et rien ne le
    # disait.
    # LE SERVICE DE MACHINE, prepare mais pas active. Une seule installation : c'est ici
    # que les nouvelles pieces arrivent, et l'idempotence fait la difference entre une
    # premiere pose et une mise a jour. La tache est creee DESACTIVEE -- rien ne change au
    # demarrage tant que la bascule n'est pas faite.
    $service = Join-Path (Join-Path $PSScriptRoot 'lib') 'install-service.ps1'
    if ($isAdmin -and (Test-Path -LiteralPath $service)) {
        try {
            # ON GARDE CE QUE L'ETAPE AFFICHE. « | Write-Host » le montrait et le perdait :
            # le journal du 29/08 s'arretait a « WebView2 runtime », juste avant ce bloc,
            # alors que l'ecran, lui, montrait toute la suite. Un journal qui s'interrompt
            # avant la partie interessante ne sert a rien -- et c'est precisement celle
            # qu'on relit quand l'installation s'est mal passee.
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $service 2>&1 |
                ForEach-Object {
                    $ligne = "$_"
                    Write-Host $ligne
                    try { Write-Log -Backend $backend -Name 'install' -Message $ligne -NoEcho } catch { }
                }
            # ON LIT LE CODE DE RETOUR. Il etait journalise sans etre teste : le 28/08,
            # l'enregistrement de la tache a echoue et l'installation a fini en vert.
            # Un code non nul est un ECHEC -- Write-Log ERROR le compte, et le verdict
            # final ne peut plus l'ignorer.
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.service-de-machine-pret')
            } else {
                Write-Log -Backend $backend -Name 'install' -Level 'ERROR' `
                          -Message (Get-Label 'install.service-de-machine-echec' $LASTEXITCODE)
            }
        } catch {
            Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.service-de-machine' $_.Exception.Message)
        }
    }

    $autostart = Join-Path $PSScriptRoot 'install-autostart.ps1'
    if (-not $isAdmin) {
        Write-Ok (Get-Label 'install.prerequis-installes')
        Write-Warn (Get-Label 'install.le-demarrage-automatique-demande')
        Write-Detail (Get-Label 'install.relancez-cette-installation-en')
    } elseif (Test-Path -LiteralPath $autostart) {
        Write-Step (Get-Label 'install.demarrage-automatique')
        # -Yes : on est deja eleve et l'utilisateur a deja consenti en lancant
        # l'installation ; une seconde fenetre d'explication serait du bruit.
        # LE RESULTAT SE LIT : 0 = fait, 3 = refuse, le reste est un echec.
        & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $autostart -Yes
        $codeAuto = $LASTEXITCODE
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.demarrage-automatique-code' $codeAuto)
        switch ([int]$codeAuto) {
            0 { Write-Ok (Get-Label 'install.vigie-demarre-chaque-ouverture') }
            3 { Write-Warn (Get-Label 'install.demarrage-automatique-refuse-vigie') }
            default {
                Write-Fail (Get-Label 'install.le-demarrage-automatique-echoue' $codeAuto)
                Write-Detail (Get-Label 'install.vigie-reste-lancable-la')
            }
        }
    }

    # LE VERDICT SE CALCULE. Write-Outcome compte ce que Write-Fail et Write-Warn ont
    # affiche : aucune installation ne peut plus finir en vert avec un echec derriere elle.
    $failures = Get-UiFailureCount
    $warnings = Get-UiWarningCount
    Write-Outcome -What (Get-Label 'install.verdict') `
                  -NextStep (Get-Label 'install.verdict-panneau')

    <#
        ET UNE FENETRE, PAS UN « APPUYEZ SUR UNE TOUCHE ».

        L'installation se lance par un double-clic : elle doit se conclure comme une
        application, pas comme un script. La fenetre dit ce qui a ete fait et ce qui
        reste a savoir ; la console garde le detail pour qui veut le lire.

        SI ELLE NE PEUT PAS S'AFFICHER -- pas d'interface, session sans bureau -- on ne
        bloque rien : la conclusion est deja a l'ecran, et setup.cmd garde son « pause »
        pour les cas d'echec.
    #>
    try {
        $window = Join-Path $PSScriptRoot 'lib/show-confirm.ps1'
        if (Test-Path -LiteralPath $window) {
            $title = if ($failures -gt 0) { Get-Label 'install.fenetre-titre-echec' }
                     elseif ($warnings -gt 0) { Get-Label 'install.fenetre-titre-reserve' }
                     else { Get-Label 'install.fenetre-titre' }
            $summary = if ($failures -gt 0) { Get-Label 'install.fenetre-resume-echec' }
                      else { Get-Label 'install.fenetre-resume' }
            $facts = @(
                (Get-Label 'install.fenetre-fait-panneau'),
                (Get-Label 'install.fenetre-fait-session'),
                (Get-Label 'install.fenetre-fait-journal')
            ) -join '|'
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $window `
                -Title $title -Summary $summary -Changes $facts `
                -OkText (Get-Label 'install.fenetre-fermer') -CancelText '' -Note '' | Out-Null
        }
    } catch { }

    if ($failures -gt 0) { try { Stop-Transcript | Out-Null } catch { }; exit 1 }
}
catch {
    Write-Log -Backend $backend -Name 'install' -Level 'ERROR' -Message (Get-Label 'install.fatal' $_.Exception.Message)
    Write-Fail ($_ | Out-String)
    # ON SORT EN ECHEC. Le bloc se contentait d'afficher l'erreur : le script rendait 0,
    # et le lanceur enchainait comme si tout allait bien.
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
