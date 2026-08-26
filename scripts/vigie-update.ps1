<#
    vigie-update.ps1 - Met a jour l'installation partagee, puis relance Vigie.

    Enchainement, sans intervention (D81 : les processus s'enchainent seuls, et le
    resultat de chaque sous-processus est LU) :
      1. deploy-prod.ps1  -> pose le tag, fabrique l'archive, la deploie
      2. scripts/tray.ps1 -Restart -> le tray relance le serveur avec le nouveau code

    Codes de retour : 0 = a jour et relancee ; 1 = le deploiement a echoue ;
                      2 = deploiement fait, mais la relance n'a pas abouti.

    Appele par l'action « Mettre a jour Vigie », sous le veilleur (D82) : ce code de
    retour finit en ligne verte ou rouge sur la carte de debogage.
#>
param(
    # Emplacement de l'installation partagee. Defaut : celui de deploy-prod.
    [string] $Destination
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'

$avant = Get-BuildStamp -Root $repoRoot
Write-Host ("Version de depart : " + $avant.version + $(if ($avant.commit) { " (" + $avant.commit.Substring(0, 8) + ")" }))

# --- 1. Deploiement -----------------------------------------------------------
$deploy = Join-Path $PSScriptRoot 'deploy-prod.ps1'
if (-not (Test-Path -LiteralPath $deploy)) {
    Write-Host "deploy-prod.ps1 introuvable." -ForegroundColor Red
    exit 1
}
$pwsh = (Get-Process -Id $PID).Path
$argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $deploy + '"'), '-Yes')
if ($Destination) { $argv += @('-Destination', ('"' + $Destination + '"')) }

Write-Host "Deploiement..."
$p = Start-Process -FilePath $pwsh -ArgumentList $argv -Wait -PassThru -WindowStyle Hidden
Write-Host ("deploy-prod a rendu le code " + $p.ExitCode + ".")
if ($p.ExitCode -ne 0) {
    Write-Host "Le deploiement a echoue : Vigie n'est PAS relancee, l'ancienne version continue de tourner." -ForegroundColor Red
    exit 1
}

# --- 2. Relance ---------------------------------------------------------------
# Le tray relance le serveur AVEC lui (D78) : c'est ce qui charge le nouveau code.
$tray = Join-Path $PSScriptRoot 'tray.ps1'
Write-Host "Relance de Vigie..."
$r = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                                                   '-File', ('"' + $tray + '"'), '-Restart') `
                   -Wait -PassThru -WindowStyle Hidden
Write-Host ("La relance a rendu le code " + $r.ExitCode + ".")
if ($r.ExitCode -ne 0) {
    Write-Host "Le deploiement est fait, mais la relance n'a pas abouti : relancez Vigie a la main." -ForegroundColor Yellow
    exit 2
}

$apres = Get-BuildStamp -Root $repoRoot
Write-Host ("Vigie est a jour : " + $apres.version + $(if ($apres.commit) { " (" + $apres.commit.Substring(0, 8) + ")" }))
exit 0
