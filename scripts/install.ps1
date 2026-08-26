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

# --- Cible PowerShell 7 : bascule si lance en 5.1 ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        Write-Host "Bascule en PowerShell 7..."
        & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        return
    }
    Write-Host "PowerShell 7 (pwsh) absent. Tentative d'installation via winget..." -ForegroundColor Yellow
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
        Write-Host "Cette etape doit etre lancee EN ADMINISTRATEUR (installation pour toute la machine)." -ForegroundColor Yellow
        Write-Host "Ouvre un terminal administrateur, puis relance :" -ForegroundColor Yellow
        Write-Host ("  powershell -ExecutionPolicy Bypass -File " + $PSCommandPath)
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
        Write-Host ""
        Write-Host "winget n'a pas de paquet MSI : passage par le MSI officiel de PowerShell." -ForegroundColor Yellow
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
            $mo  = [math]::Round(([double]$asset.size) / 1MB, 1)
            Write-Host ("Telechargement de " + $asset.name + " (" + $mo + " Mo)...")
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing -TimeoutSec 900
            Write-Host "Installation pour toute la machine..."
            # ALLUSERS=1 : installation MACHINE. /qn : sans interface, on est deja eleve.
            $mi = Start-Process -FilePath 'msiexec.exe' -Wait -PassThru -ArgumentList @(
                      '/i', ('"' + $msi + '"'), '/qn', 'ALLUSERS=1', 'ADD_PATH=1')
            Write-Host ("msiexec a rendu le code " + $mi.ExitCode + ".")
            Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host ("Echec du repli MSI : " + $_.Exception.Message) -ForegroundColor Red
        }
    }

    # 3) On CONSTATE, et on enchaine tout seul : l'utilisateur n'a pas a relancer.
    if (Test-Path -LiteralPath $cible) {
        Write-Host ""
        Write-Host ("PowerShell 7 installe pour la machine : " + $cible) -ForegroundColor Green
        Write-Host "Suite de l'installation avec lui..." -ForegroundColor Green
        & $cible -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        return
    }
    Write-Host ""
    Write-Host "PowerShell 7 n'a PAS pu etre installe." -ForegroundColor Red
    Write-Host "Telecharge le MSI a la main : https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
    Write-Host "(fichier PowerShell-<version>-win-x64.msi), puis relance cette installation."
    exit 1
}

# Les scripts de gestion vivent dans scripts/ : les apps sont dans apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

$logDir = Get-LogDir -Backend $backend
$log    = Join-Path $logDir ('install_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }

try {
    $isAdmin = Test-Elevated
    $scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }
    Write-Log -Backend $backend -Name 'install' -Message ("Installation (PowerShell " + $PSVersionTable.PSVersion + ", élevé=" + $isAdmin + ", portée=" + $scope + ")")

    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Log -Backend $backend -Name 'install' -Message "Installation du provider NuGet..."
        Install-PackageProvider -Name NuGet -Force -Scope $scope | Out-Null
    } else { Write-Log -Backend $backend -Name 'install' -Message "Provider NuGet : déjà présent." }

    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # Chemin AllUsers de reference (partage par tous les PS7).
    $allUsersPode = Join-Path $env:ProgramFiles 'PowerShell\Modules\Pode'

    if ($isAdmin) {
        # En admin : on garantit une copie AllUsers, visible par tous les PS7.
        if (Test-Path $allUsersPode) {
            $v = (Get-ChildItem $allUsersPode -Directory -ErrorAction SilentlyContinue | Select-Object -Last 1).Name
            Write-Log -Backend $backend -Name 'install' -Message ("Pode (AllUsers) : déjà présent (" + $v + ").")
        } else {
            Write-Log -Backend $backend -Name 'install' -Message "Installation de Pode (AllUsers)..."
            Install-Module Pode -Scope AllUsers -Force
            Write-Log -Backend $backend -Name 'install' -Message "Pode installé (AllUsers)."
        }
    } else {
        if (Get-Module -ListAvailable -Name Pode) {
            Write-Log -Backend $backend -Name 'install' -Message ("Pode : déjà installé (v" + (Get-Module -ListAvailable -Name Pode | Select-Object -First 1).Version + ").")
        } else {
            Write-Log -Backend $backend -Name 'install' -Message "Installation de Pode (CurrentUser)..."
            Install-Module Pode -Scope CurrentUser -Force
            Write-Log -Backend $backend -Name 'install' -Message "Pode installé (CurrentUser)."
        }
    }

    # --- DEPENDANCE : PowerShell 7 doit etre installe POUR LA MACHINE -----------
    # Vigie demarre par une tache planifiee, une par compte. Un pwsh installe pour le
    # seul compte courant (paquet du Store) vit dans SON profil : la tache des autres
    # comptes pointerait dans un dossier qu'ils ne peuvent pas lire. On le traite ICI,
    # a l'installation, plutot que de le decouvrir le jour ou un compte ne demarre pas.
    $pwshMachine = Get-SharedPwshPath
    if ($pwshMachine) {
        Write-Log -Backend $backend -Name 'install' -Message ("PowerShell 7 (machine) : présent, " + $pwshMachine)
    } elseif ($isAdmin -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log -Backend $backend -Name 'install' -Message "PowerShell 7 n'existe que pour ce compte : installation pour la machine..."
        try {
            & 'winget.exe' @(Get-SharedPwshInstallArgs) | Write-Host
            $pwshMachine = Get-SharedPwshPath
        } catch { }
        if ($pwshMachine) {
            Write-Log -Backend $backend -Name 'install' -Message ("PowerShell 7 (machine) installé : " + $pwshMachine)
        } else {
            Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message "PowerShell 7 (machine) : installation sans effet, les autres comptes ne pourront pas démarrer Vigie."
        }
    } else {
        Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message "PowerShell 7 n'est installé que pour ce compte. Relancez cette installation en administrateur, sinon les autres comptes ne pourront pas démarrer Vigie."
        Write-Host ""
        Write-Host "PowerShell 7 n'est installe que pour VOTRE compte." -ForegroundColor Yellow
        Write-Host "Les autres comptes ne pourront pas demarrer Vigie. A faire une fois, en administrateur :" -ForegroundColor Yellow
        Write-Host "  winget install --id Microsoft.PowerShell --scope machine"
    }

    $null = Get-ApiToken -Backend $backend
    Write-Log -Backend $backend -Name 'install' -Message "Jeton d'API prêt : backend/.secrets/api.token"

    $wvKeys = @(
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    $wv = $false; foreach ($k in $wvKeys) { if (Test-Path $k) { $wv = $true } }
    Write-Log -Backend $backend -Name 'install' -Message ("WebView2 runtime : " + $(if ($wv) { 'présent' } else { 'absent' }))

    Write-Host ""
    Write-Host "Terminé. Pour lancer :  pwsh -File .\run.ps1" -ForegroundColor Green
}
catch {
    Write-Log -Backend $backend -Name 'install' -Level 'ERROR' -Message ("FATAL: " + $_.Exception.Message)
    Write-Host ($_ | Out-String) -ForegroundColor Red
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
