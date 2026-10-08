# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    run.ps1 -- starts the panel. IDEMPOTENT. Targets PowerShell 7.

    Intent: one command that gets from nothing to a panel open in the browser, whatever the session it is typed
    in. It switches back to pwsh if started under 5.1, and elevates (UAC) if needed: the server must run with
    administrator rights in order to read and apply the Windows Update state. The windows it restarts keep
    -NoExit (they no longer close by themselves on an error). If Pode is missing, it is installed automatically
    (install.ps1). The browser is opened only once the server is really listening.
    It logs its decisions into backend/logs/run_*.log.

    Usage:
        pwsh -File .\run.ps1              # starts it and opens the interface (asks for UAC)
        pwsh -File .\run.ps1 -NoBrowser   # without the browser
#>
param(
    [switch]$Admin,      # kept for compatibility; the elevation is automatic anyway
    [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
# The management scripts live in scripts/: the apps are in apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, see common.ps1
. (Join-Path $backend 'lib/common.ps1')

$needPwsh = $PSVersionTable.PSVersion.Major -lt 7
$isAdmin  = Test-Elevated
$needElev = (-not $isAdmin)   # the server must run with the rights (UAC if needed)

$runLog = Join-Path (Get-LogDir -Backend $backend) ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $runLog -Force | Out-Null } catch { }
Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.run-ps1-ps-eleve' $PSVersionTable.PSVersion $isAdmin)

# --- Restart under pwsh and/or elevated if needed (the window is kept) ---
if ($needPwsh -or $needElev) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message (Get-Label 'run.powershell-requis-lance-install')
        try { Stop-Transcript | Out-Null } catch { }
        return
    }
    # RAW VALUES: Start-ChildProcess is what quotes them (D116). This script may live
    # under "C:\Program Files\Sowapps\Vigie", where a bare path dies on
    # "C:\Program is not a script".
    $argList = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    if ($NoBrowser) { $argList += '-NoBrowser' }
    Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.relance-pwsh-eleve' $needElev)
    try {
        $opts = @{}
        if ($needElev) { $opts['Verb'] = 'RunAs' }
        Start-ChildProcess -FilePath $pwsh.Source -Arguments $argList -Options $opts
    } catch {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message (Get-Label 'run.relance-echouee' $_.Exception.Message)
        Write-Warn (Get-Label 'run.relance-impossible-ouvre-un')
    }
    try { Stop-Transcript | Out-Null } catch { }
    return
}

# --- Prerequis Pode : auto-installation si absent (idempotent) ---
if (-not (Get-Module -ListAvailable -Name Pode)) {
    Write-Log -Backend $backend -Name 'run' -Level 'WARN' -Message (Get-Label 'run.pode-manquant-installation-automatique')
    & (Join-Path $backend 'install.ps1')
    if (-not (Get-Module -ListAvailable -Name Pode)) {
        Write-Log -Backend $backend -Name 'run' -Level 'ERROR' -Message (Get-Label 'run.pode-toujours-absent-apres')
        try { Stop-Transcript | Out-Null } catch { }
        return
    }
}

$cfg = Get-Config -Backend $backend
$url = Get-AppUrl -Config $cfg

if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
    Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.deja-en-cours-ouverture' $url)
    if (-not $NoBrowser) { Start-Process $url }
    try { Stop-Transcript | Out-Null } catch { }
    return
}

# --- Opening the browser: we wait until the server really listens ---
# (a background job, because start.ps1 blocks; a TCP probe for up to 40 s)
if (-not $NoBrowser) {
    Start-Job -ScriptBlock {
        param($u, $addr, $port)
        for ($i = 0; $i -lt 80; $i++) {
            try {
                $c = [System.Net.Sockets.TcpClient]::new()
                $c.Connect($addr, [int]$port)
                if ($c.Connected) { $c.Close(); Start-Sleep -Milliseconds 500; Start-Process $u; return }
            } catch { Start-Sleep -Milliseconds 500 }
        }
        Start-Process $u
    } -ArgumentList $url, $cfg.BindAddress, $cfg.Port | Out-Null
    Write-Log -Backend $backend -Name 'run' -Message (Get-Label 'run.navigateur-planifie-attente-ecoute' $url)
}

try { Stop-Transcript | Out-Null } catch { }   # start.ps1 a son propre transcript
& (Join-Path $backend 'start.ps1')
