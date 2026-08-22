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
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.PowerShell -e --source winget --accept-package-agreements --accept-source-agreements
        Write-Host "Si l'installation a reussi, RELANCE install.ps1 (il basculera en PS7)." -ForegroundColor Green
    } else {
        Write-Host "winget introuvable. Installe PowerShell 7 : https://aka.ms/powershell-release" -ForegroundColor Yellow
    }
    return
}

$backend = $PSScriptRoot
. (Join-Path $backend 'lib/common.ps1')

$logDir = Get-LogDir -Backend $backend
$log    = Join-Path $logDir ('install_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }

try {
    $isAdmin = Test-Elevated
    $scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }
    Write-Log -Backend $backend -Name 'install' -Message ("Installation (PowerShell " + $PSVersionTable.PSVersion + ", eleve=" + $isAdmin + ", portee=" + $scope + ")")

    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Log -Backend $backend -Name 'install' -Message "Installation du provider NuGet..."
        Install-PackageProvider -Name NuGet -Force -Scope $scope | Out-Null
    } else { Write-Log -Backend $backend -Name 'install' -Message "Provider NuGet : deja present." }

    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # Chemin AllUsers de reference (partage par tous les PS7).
    $allUsersPode = Join-Path $env:ProgramFiles 'PowerShell\Modules\Pode'

    if ($isAdmin) {
        # En admin : on garantit une copie AllUsers, visible par tous les PS7.
        if (Test-Path $allUsersPode) {
            $v = (Get-ChildItem $allUsersPode -Directory -ErrorAction SilentlyContinue | Select-Object -Last 1).Name
            Write-Log -Backend $backend -Name 'install' -Message ("Pode (AllUsers) : deja present (" + $v + ").")
        } else {
            Write-Log -Backend $backend -Name 'install' -Message "Installation de Pode (AllUsers)..."
            Install-Module Pode -Scope AllUsers -Force
            Write-Log -Backend $backend -Name 'install' -Message "Pode installe (AllUsers)."
        }
    } else {
        if (Get-Module -ListAvailable -Name Pode) {
            Write-Log -Backend $backend -Name 'install' -Message ("Pode : deja installe (v" + (Get-Module -ListAvailable -Name Pode | Select-Object -First 1).Version + ").")
        } else {
            Write-Log -Backend $backend -Name 'install' -Message "Installation de Pode (CurrentUser)..."
            Install-Module Pode -Scope CurrentUser -Force
            Write-Log -Backend $backend -Name 'install' -Message "Pode installe (CurrentUser)."
        }
    }

    $null = Get-ApiToken -Backend $backend
    Write-Log -Backend $backend -Name 'install' -Message "Jeton d'API pret : backend/.secrets/api.token"

    $wvKeys = @(
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    $wv = $false; foreach ($k in $wvKeys) { if (Test-Path $k) { $wv = $true } }
    Write-Log -Backend $backend -Name 'install' -Message ("WebView2 runtime : " + $(if ($wv) { 'present' } else { 'absent' }))

    Write-Host ""
    Write-Host "Termine. Pour lancer :  pwsh -File .\run.ps1" -ForegroundColor Green
}
catch {
    Write-Log -Backend $backend -Name 'install' -Level 'ERROR' -Message ("FATAL: " + $_.Exception.Message)
    Write-Host ($_ | Out-String) -ForegroundColor Red
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
