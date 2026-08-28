<#
    start.ps1 - Point d'entree du backend. IDEMPOTENT. Cible PowerShell 7.
    Journalise tout dans backend/logs/ (transcript + Write-Log + logs Pode via
    server.ps1). Bascule en pwsh si lance en 5.1. Ne relance pas si deja en cours.
    Si Pode manque, l'installe automatiquement (via install.ps1) puis re-verifie.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')

# --- Cible PowerShell 7 + droits admin (le serveur doit avoir les droits) ---
$isAdmin = Test-Elevated
if (($PSVersionTable.PSVersion.Major -lt 7) -or (-not $isAdmin)) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { Write-Warn (Get-Label 'start.powershell-requis-lance-abord'); return }
    $relArgs = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    if (-not $isAdmin) { Start-Process $pwsh.Source -Verb RunAs -ArgumentList $relArgs }
    else               { Start-Process $pwsh.Source -ArgumentList $relArgs }
    return
}

$backend = $PSScriptRoot
. (Join-Path $backend 'lib/common.ps1')

# LA SOURCE DU JOURNAL D'EVENEMENTS, si elle manque. Une installation anterieure a la
# tracabilite ne l'a pas ; le serveur est eleve, il peut la poser. Silencieux : ce n'est
# pas une raison de ne pas demarrer.
try { $null = Register-VigieEventSource -Quiet } catch { }

$logDir   = Get-LogDir -Backend $backend
$startLog = Join-Path $logDir ('start_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $startLog -Force | Out-Null } catch { }

try {
    Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.powershell' $PSVersionTable.PSVersion)

    $pode = Get-Module -ListAvailable -Name Pode | Select-Object -First 1
    if (-not $pode) {
        Write-Log -Backend $backend -Name 'start' -Level 'WARN' -Message (Get-Label 'start.module-pode-absent-installation')
        & (Join-Path $backend 'install.ps1')
        $pode = Get-Module -ListAvailable -Name Pode | Select-Object -First 1
        if (-not $pode) {
            Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message (Get-Label 'start.pode-toujours-absent-apres')
            return
        }
    }
    Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.pode' $pode.Version)

    $cfg = Get-Config -Backend $backend
    if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
        Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.deja-en-cours-sur' (Get-AppUrl -Config $cfg))
        return
    }

    $env:VIGIE_BACKEND = $backend
    $env:VIGIE_TOKEN   = Get-ApiToken -Backend $backend
    $env:VIGIE_PORT    = "$($cfg.Port)"

    # AUTO-REPARATION DE NOS PROPRES TACHES, au demarrage (D83).
    # Autorise explicitement : « l'app peut auto-corriger le systeme tant que c'est du
    # pur Vigie ». Une tache qui vise un interpreteur disparu se lance et meurt sans un
    # mot ; la reparer ici, c'est la reparer avant que quiconque s'en apercoive. Ne
    # touche a aucune tache qui ne soit pas la notre, et ne cree jamais rien.
    try {
        $repares = @(Repair-VigieTasks -Backend $backend)
        foreach ($r in $repares) {
            Write-Log -Backend $backend -Name 'start' -Level $(if ($r.repare) { 'INFO' } else { 'ERROR' }) `
                      -Message (Get-Label 'start.tache' $r.tache $r.mal $(if ($r.repare) { 'reparee' } else { 'ECHEC' }))
        }
    } catch {
        Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message (Get-Label 'start.auto-reparation' $_.Exception.Message)
    }

    Import-Module Pode
    Write-Log -Backend $backend -Name 'start' -Message (Get-Label 'start.demarrage' (Get-ApiUrl -Config $cfg))
    Write-Info (Get-Label 'start.ui' (Get-AppUrl -Config $cfg))
    Start-PodeServer -Threads 3 {
        . "$env:VIGIE_BACKEND/server.ps1"
    }
}
catch {
    Write-Log -Backend $backend -Name 'start' -Level 'ERROR' -Message (Get-Label 'start.fatal' $_.Exception.Message)
    Write-Fail ($_ | Out-String)
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
