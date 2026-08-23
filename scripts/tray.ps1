<#
.SYNOPSIS
    Pilote l'app Vigie de la barre systeme : etat, arret, redemarrage.

.DESCRIPTION
    Le tray tourne ELEVE. Depuis une session normale on ne peut ni lire sa ligne de
    commande, ni signaler un objet noyau qu'il a cree : il fallait le tuer a l'aveugle,
    ce qui laissait son icone en fantome dans la zone de notification.

    Ce script depose un ORDRE dans apps/tray/var/run/ ; le tray le lit et sort proprement,
    en liberant son icone. Le meme dossier porte un battement de coeur (tray.alive) qui
    permet de connaitre son etat sans inspecter le processus.

    Inspectable a l'oeil, scriptable depuis n'importe quoi, et ouvert aux evolutions :
    un nouvel ordre est un nouveau nom de fichier, sans toucher au mecanisme.

.PARAMETER Status
    Affiche si le tray est vivant, depuis quand, et l'etat qu'il affiche.

.PARAMETER Stop
    Demande l'arret. Attend la confirmation par disparition du battement de coeur.

.PARAMETER Restart
    Demande au tray de se relancer.

.PARAMETER TimeoutSec
    Delai d'attente de la confirmation (defaut 15 s).

.EXAMPLE
    pwsh -File .\scripts\tray.ps1 -Status

.EXAMPLE
    pwsh -File .\scripts\tray.ps1 -Stop

.NOTES
    Codes de retour : 0 = succes ; 1 = tray absent ; 2 = ordre non pris en compte a temps.
    Demarrer le tray : Start-ScheduledTask -TaskName Vigie
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Status')]  [switch] $Status,
    [Parameter(ParameterSetName = 'Stop')]    [switch] $Stop,
    [Parameter(ParameterSetName = 'Restart')] [switch] $Restart,
    [int] $TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'
$repoRoot  = Split-Path $PSScriptRoot -Parent
$runDir    = Join-Path $repoRoot 'apps/tray/var/run'
$heartbeat = Join-Path $runDir 'tray.alive'

# Le tray ecrit son battement toutes les 8 s : au-dela de 30 s, on le considere mort.
$SEUIL_SEC = 30

function Get-TrayState {
    if (-not (Test-Path -LiteralPath $heartbeat)) { return $null }
    try {
        # UTF8 explicite : l'etat contient des accents (« Démarrage… »).
        $parts = (Get-Content -LiteralPath $heartbeat -Raw -Encoding UTF8).Trim() -split ';'
        $age = ([datetime]::Now - [datetime]::Parse($parts[1])).TotalSeconds
        return [pscustomobject]@{ Pid = [int]$parts[0]; AgeSec = [int]$age; Etat = $parts[2] }
    } catch { return $null }
}

function Send-Order {
    param([string] $Nom)
    if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Path $runDir -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $runDir $Nom) -Value '' -Encoding ASCII -NoNewline
}

# --- Etat --------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Status' -or $Status) {
    $t = Get-TrayState
    if ($t -and $t.AgeSec -le $SEUIL_SEC) {
        Write-Host ("Tray EN MARCHE  - PID {0}, etat « {1} », vu il y a {2} s" -f $t.Pid, $t.Etat, $t.AgeSec)
        exit 0
    }
    if ($t) { Write-Host ("Tray ARRETE     - dernier signe de vie il y a {0} s (PID {1})" -f $t.AgeSec, $t.Pid) }
    else    { Write-Host "Tray ARRETE     - aucun battement de coeur" }
    exit 1
}

# --- Arret / redemarrage -----------------------------------------------------
$avant = Get-TrayState
if (-not $avant -or $avant.AgeSec -gt $SEUIL_SEC) {
    Write-Host "Tray deja arrete (rien a faire)."
    exit 1
}

$ordre = if ($Restart) { 'restart' } else { 'stop' }
Send-Order $ordre
Write-Host ("Ordre « {0} » depose (tray PID {1}). Attente de la confirmation..." -f $ordre, $avant.Pid)

# Confirmation : pour un arret, le battement disparait ; pour un redemarrage, un NOUVEAU
# processus reprend la main -- on attend donc un PID different.
$fin = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $fin) {
    Start-Sleep -Milliseconds 500
    $apres = Get-TrayState
    if ($Restart) {
        if ($apres -and $apres.Pid -ne $avant.Pid -and $apres.AgeSec -le $SEUIL_SEC) {
            Write-Host ("Tray relance (nouveau PID {0})." -f $apres.Pid); exit 0
        }
    } elseif (-not $apres) {
        Write-Host "Tray arrete proprement (icone liberee)."; exit 0
    }
}

Write-Host ("L'ordre n'a pas ete pris en compte en {0} s." -f $TimeoutSec) -ForegroundColor Yellow
Write-Host "Le tray est peut-etre fige. Verifie apps/tray/var/log/ et le dossier var/run/."
exit 2
