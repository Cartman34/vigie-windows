# @author Florent HAZARD <f.hazard@sowapps.com>
<#
.SYNOPSIS
    Pilote l'app Vigie de la barre systeme : etat, arret, redemarrage.

.DESCRIPTION
    L'app cliente tourne ELEVE. Depuis une session normale on ne peut ni lire sa ligne de
    commande, ni signaler un objet noyau qu'il a cree : il fallait le tuer a l'aveugle,
    ce qui laissait son icone en fantome dans la zone de notification.

    Ce script depose un ORDRE dans apps/client/var/run/ ; l'app cliente le lit et sort proprement,
    en liberant son icone. Le meme dossier porte un battement de coeur (client.alive) qui
    permet de connaitre son etat sans inspecter le processus.

    Inspectable a l'oeil, scriptable depuis n'importe quoi, et ouvert aux evolutions :
    un nouvel ordre est un nouveau nom de fichier, sans toucher au mecanisme.

.PARAMETER Status
    Affiche si l'app cliente est vivant, depuis quand, et l'etat qu'il affiche.

.PARAMETER Stop
    Demande l'arret. Attend la confirmation par disparition du battement de coeur.

.PARAMETER Restart
    Demande à l'app cliente de se relancer.

.PARAMETER TimeoutSec
    Delai d'attente de la confirmation (defaut 15 s).

.EXAMPLE
    pwsh -File .\scripts\client.ps1 -Status

.EXAMPLE
    pwsh -File .\scripts\client.ps1 -Stop

.NOTES
    Codes de retour : 0 = succes ; 1 = app cliente absente ; 2 = ordre non pris en compte a temps.
    Demarrer l'app cliente : Start-ScheduledTask -TaskName Vigie
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Status')]  [switch] $Status,
    [Parameter(ParameterSetName = 'Stop')]    [switch] $Stop,
    [Parameter(ParameterSetName = 'Restart')] [switch] $Restart,
    # 15 s etait trop juste. Mesure du 26/08 : un redemarrage complet prend 9 a 11 s
    # (ordre lu dans la seconde, pwsh + compilations C# ~5 s, premier battement 2 s
    # apres). Machine occupee -- un deploiement en cours, justement -- et le compte y
    # est. On declarait donc un echec sur une relance qui aboutissait.
    [int] $TimeoutSec = 45
)

$ErrorActionPreference = 'Stop'
$repoRoot  = Split-Path $PSScriptRoot -Parent
# LE MEME CALCUL QUE L'APP CLIENTE, ET PAR LE MEME CODE. Ce chemin etait ecrit a la main
# (« apps/client/var/run ») : sur une installation partagee, l'emetteur cherchait donc le
# battement dans Program Files pendant que l'app cliente l'ecrivait dans le profil du compte.
# Program Files est en LECTURE SEULE (D97) ; c'est Get-VarPath qui sait ou vont les
# donnees, et personne d'autre.
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$runDir    = Get-VarPath -Backend (Join-Path $repoRoot 'apps/client') -Kind 'run'
$heartbeat = Join-Path $runDir 'client.alive'

# L'app cliente ecrit son battement toutes les 8 s : au-dela de 30 s, on le considere mort.
$SEUIL_SEC = 30

function Get-ClientState {
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
    $t = Get-ClientState
    if ($t -and $t.AgeSec -le $SEUIL_SEC) {
        Write-Info (Get-Label 'client.en-marche-pid' $t.Pid $t.Etat $t.AgeSec)
        exit 0
    }
    if ($t) { Write-Host (Get-Label 'client.arrete-dernier-signe' $t.AgeSec $t.Pid) }
    else    { Write-Host (Get-Label 'client.arrete-aucun-battement') }
    exit 1
}

# --- Arret / redemarrage -----------------------------------------------------
$avant = Get-ClientState
if (-not $avant -or $avant.AgeSec -gt $SEUIL_SEC) {
    # RELANCER CE QUI NE TOURNE PLUS, C'EST LE DEMARRER.
    #
    # On rendait 1 en disant « rien a faire » -- et la mise a jour, qui appelle ce script
    # pour recharger le nouveau code, concluait a un echec alors que le deploiement avait
    # reussi : « le deploiement est fait, mais la relance n'a pas abouti » (constate le
    # 28/08). Un arret n'est pas un echec de relance : c'est justement le cas ou il faut
    # demarrer.
    if (-not $Restart) {
        Write-Info (Get-Label 'client.deja-arrete-rien')
        exit 0
    }
    Write-Info (Get-Label 'client.arrete-demarrage')
    try {
        Start-ScheduledTask -TaskName 'Vigie' -ErrorAction Stop
    } catch {
        Write-Warn (Get-Label 'client.la-tache-de-demarrage' $_.Exception.Message)
        exit 2
    }
    # ON CONSTATE (D43) : la tache lancee ne prouve pas l'app cliente vivante.
    $limite = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $limite) {
        Start-Sleep -Milliseconds 800
        $e = Get-ClientState
        if ($e -and $e.AgeSec -le $SEUIL_SEC) {
            Write-Info (Get-Label 'client.demarre-pid' $e.Pid)
            exit 0
        }
    }
    Write-Warn (Get-Label 'client.pas-donne-signe')
    exit 2
}

$ordre = if ($Restart) { 'restart' } else { 'stop' }
$ack   = Join-Path $runDir ($ordre + '.ack')
Remove-Item -LiteralPath $ack -Force -ErrorAction SilentlyContinue
Send-Order $ordre
Write-Info (Get-Label 'client.ordre-depose-pid' $ordre $avant.Pid)
# 1) A-T-IL LU L'ORDRE ? L'app cliente pose un accuse des qu'elle le consomme. Sans cette
#    etape, un echec ne disait pas s'il fallait depanner une app cliente figee ou une relance
#    lente : deux causes differentes, deux gestes differents.
$vuLe = (Get-Date).AddSeconds(10)
$lu = $false
while ((Get-Date) -lt $vuLe) {
    if (Test-Path -LiteralPath $ack) { $lu = $true; break }
    Start-Sleep -Milliseconds 200
}
if ($lu) {
    Remove-Item -LiteralPath $ack -Force -ErrorAction SilentlyContinue
    Write-Info (Get-Label 'client.ordre-lu-par-le')
} else {
    Write-Warn (Get-Label 'client.ordre-pas-lu')
    Write-Info (Get-Label 'client.verifie-apps-client-var')
    exit 2
}

<#
    ON N'ATTEND PAS QU'UNE APPLICATION DEMARRE.

    Regle deja posee pour l'app serveur, et violee ici : on guettait pendant 45 secondes
    l'apparition d'un NOUVEAU numero de processus. Le 30/08, la relance a rendu « code 2 »
    -- donc l'installation a annonce deux echecs -- alors que l'app cliente tournait :
    l'ancienne instance n'avait pas encore rendu son verrou quand la nouvelle a demarre,
    celle-ci est sortie sur « deja lance », et le numero n'a jamais change.

    L'ACCUSE DE RECEPTION EST LA PREUVE. Il est ecrit par l'app cliente elle-meme, au
    moment ou elle prend l'ordre : a partir de la, elle s'arrete et repart, et ce qu'elle
    met a le faire ne regarde pas celui qui a demande.

    Un ARRET, lui, se constate : le battement de coeur disparait, c'est un fait, pas une
    estimation -- et c'est justement ce qu'on veut verifier avant de rendre la main.
#>
if ($Restart) {
    Write-Host (Get-Label 'client.relance-demandee')
    exit 0
}

$fin = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $fin) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-ClientState)) {
        Write-Host (Get-Label 'client.arrete-proprement-icone'); exit 0
    }
}

# L'ordre a bien ete lu (accuse recu) : ce qui manque, c'est le RETOUR.
Write-Warn (Get-Label 'client.ordre-lu-mais-rien' $TimeoutSec)
Write-Info (Get-Label 'client.la-relance-peut-etre')
exit 2
