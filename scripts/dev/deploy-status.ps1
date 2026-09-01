# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    deploy-status.ps1 - OU EN EST LE DEPLOIEMENT ? LECTURE SEULE.

    POURQUOI CE SCRIPT EXISTE. Apres chaque installation je repose les memes questions --
    le serveur est-il revenu, quelle version est posee, le depot est-il en avance, la
    derniere installation a-t-elle rate quelque chose -- et je les reposais en lignes de
    commande batardes, illisibles et jamais deux fois pareilles. Une question qui revient
    est un script, pas une improvisation.

    IL N'ECRIT RIEN et ne declenche aucun recalcul : il lit l'etat, les versions et le
    dernier journal d'installation.

    Usage :
      pwsh -File .\scripts\dev\deploy-status.ps1
      pwsh -File .\scripts\dev\deploy-status.ps1 -Attendre 120   # attend le retour du serveur

    Codes de retour : 0 = installation et depot au meme niveau, serveur debout ;
                      1 = le serveur ne repond pas ; 2 = un ecart ou un echec a signaler.
#>
[CmdletBinding()]
param(
    # Secondes d'attente du retour du serveur. 0 = on constate, on n'attend pas.
    [int] $Attendre = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

Write-Title (Get-Label 'deploy-status.titre')

# --- 1. Le serveur repond-il ? ------------------------------------------------------
Write-Step (Get-Label 'deploy-status.etape-serveur')
$port = [int](Get-Config -Backend $backend).Port
$serverUp = $false
$deadline = (Get-Date).AddSeconds([Math]::Max($Attendre, 0))
do {
    $serverUp = [bool](Get-PortListener -Port $port)
    if ($serverUp) {
        try {
            $null = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/health") -TimeoutSec 5
        } catch { $serverUp = $false }
    }
    if (-not $serverUp -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
} while (-not $serverUp -and (Get-Date) -lt $deadline)

if ($serverUp) { Write-Ok (Get-Label 'deploy-status.serveur-repond' $port) }
else         { Write-Fail (Get-Label 'deploy-status.serveur-muet' $port) }

# --- 2. Les versions ----------------------------------------------------------------
Write-Step (Get-Label 'deploy-status.etape-versions')
$installed = $null
$here = $null
try { $installed = (Get-BuildStamp -Root (Get-SharedInstallPath)).version } catch { }
try { $here = (Get-BuildStamp -Root $repoRoot).version } catch { }
Write-Info (Get-Label 'deploy-status.version-installee' $(if ($installed) { $installed } else { 'inconnue' }))
Write-Info (Get-Label 'deploy-status.version-depot'     $(if ($here) { $here } else { 'inconnue' }))
$gap = -not (Test-SameVersion -A "$installed" -B "$here")
if ($gap) { Write-Warn (Get-Label 'deploy-status.versions-differentes') }
else        { Write-Ok (Get-Label 'deploy-status.versions-identiques') }

# --- 3. La derniere operation --------------------------------------------------------
#
# ON DEMANDE A VIGIE PLUTOT QUE DE CHERCHER UN FICHIER. Le journal d'une installation
# lancee par la carte vit dans le profil du compte de service ; celui de ce depot date de
# la derniere fois qu'on a lance setup.cmd d'ici. Chercher « le dernier journal » a cote
# de soi, c'est lire le mauvais (constate le 01/09 : un journal du 26/08 presente comme
# le dernier). Le serveur, lui, sait ce qui s'est reellement passe.
Write-Step (Get-Label 'deploy-status.etape-journal')
$session = $null
if ($serverUp) {
    try { $session = Open-VigieSession -BaseUrl ("http://127.0.0.1:$port") -Backend $backend } catch { }
}
if (-not $session) {
    Write-Info (Get-Label 'deploy-status.operations-sans-serveur')
} else {
    $operations = $null
    try { $operations = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/operations") -WebSession $session -TimeoutSec 20 } catch { }
    $recent = @()
    if ($operations) { $recent = @($operations.results) }
    if (-not $recent.Count) {
        Write-Info (Get-Label 'deploy-status.aucune-operation')
    } else {
        foreach ($o in ($recent | Select-Object -First 3)) {
            $when = "$($o.at)"
            try { $when = (ConvertTo-UtcDate $o.at).ToLocalTime().ToString('dd/MM HH:mm') } catch { }
            if ([int]$o.code -eq 0) {
                Write-Ok (Get-Label 'deploy-status.operation-reussie' "$($o.label)" $when ([int]$o.seconds))
            } else {
                Write-Fail (Get-Label 'deploy-status.operation-echouee' "$($o.label)" $when `
                                      $(if ($o.error) { "$($o.error)" } else { "code " + [int]$o.code }))
            }
        }
    }
}

# --- 4. Les sentinelles ---------------------------------------------------------------
#
# ON DEMANDE A VIGIE, ON NE LIT PAS SON FICHIER. La memoire de la veille vit dans le var
# du compte de service : une session ordinaire ne peut meme pas la lire, et ce script
# annoncait « jamais relevee » alors qu'il ne savait pas (constate le 01/09). La carte
# Debogage porte l'information, Vigie la sert avec les droits de qui demande.
Write-Step (Get-Label 'deploy-status.etape-sentinelles')
if (-not $serverUp) {
    Write-Info (Get-Label 'deploy-status.sentinelles-sans-serveur')
} else {
    $card = $null
    try {
        if (-not $session) { $session = Open-VigieSession -BaseUrl ("http://127.0.0.1:$port") -Backend $backend }
        if ($session) {
            $card = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/api/v1/modules/vigie-debug") `
                                       -WebSession $session -TimeoutSec 30
        }
    } catch { }
    $field = $null
    if ($card) { $field = @($card.fields | Where-Object { $_.key -eq 'veille' }) | Select-Object -First 1 }
    if (-not $field) {
        Write-Info (Get-Label 'deploy-status.sentinelles-sans-reponse')
    } else {
        Write-Info (Get-Label 'deploy-status.sentinelles-etat' "$($field.value)")
        foreach ($l in @("$($field.guide)" -split "`r?`n")) { if ("$l".Trim()) { Write-Detail "$l" } }
        if ("$($field.status)" -eq 'warn') { Write-Warn (Get-Label 'deploy-status.veille-arretee') }
    }
}

Write-Outcome -What (Get-Label 'deploy-status.verdict')
if (-not $serverUp) { exit 1 }
if ($gap) { exit 2 }
exit 0
