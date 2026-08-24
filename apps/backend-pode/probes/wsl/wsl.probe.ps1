<#
    Sonde : WSL2. LECTURE SEULE. N'appelle PAS wsl.exe (risque de blocage) :
    lit le registre + les processus. Rapide et sans figeage.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$installed = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
$default = '(aucune)'
try {
    $lxss = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
    $guid = (Get-ItemProperty $lxss -Name DefaultDistribution -ErrorAction SilentlyContinue).DefaultDistribution
    if ($guid) { $default = (Get-ItemProperty (Join-Path $lxss $guid) -Name DistributionName -ErrorAction SilentlyContinue).DistributionName }
} catch { }
$running = [bool](Get-Process -Name 'vmmemWSL','vmmem','wslservice' -ErrorAction SilentlyContinue)

# =============================================================================
# GRAVITE DE L'ETAT "INACTIF" - decision produit, UNE SEULE LIGNE A CHANGER.
# Le champ ET la carte en derivent : ils ne peuvent plus se contredire.
#   'error'   -> rouge  : WSL inactif est signale franchement   (choix actuel, D20)
#   'warn'    -> orange : a surveiller, sans alarmer
#   'neutral' -> gris   : etat normal, aucune alerte
# =============================================================================
$inactiveSeverity = 'error'

# Statut lisible + colore (Actif/Inactif) plutot qu'un simple Oui/Non.
$statutValue = if ($running) { 'Actif' } else { 'Inactif' }
$statutStat  = if ($running) { 'ok' } else { $inactiveSeverity }

# La carte porte le MEME jugement que le champ : une seule source de verite.
# WSL absent reste neutre : on ne reproche pas a la machine de ne pas l'avoir installe.
$st = if (-not $installed) { 'neutral' } elseif ($running) { 'ok' } else { $inactiveSeverity }

# Trio start/restart/stop : uniquement les boutons pertinents selon l'etat.
$wslActions = @()
if ($installed) {
    if ($running) {
        $wslActions += New-Action -Id 'wsl-restart' -Severity 'fix'  -Label 'Redémarrer' -Confirm -Kind 'confirm' -Help "Arrête puis relance WSL. Les programmes WSL non sauvegardés seront fermés."
        $wslActions += New-Action -Id 'wsl-shutdown' -Label 'Arrêter'    -Confirm -Kind 'confirm' -Help "Arrête proprement toutes les distributions WSL en cours."
    } else {
        $wslActions += New-Action -Id 'wsl-start' -Severity 'fix'    -Label 'Démarrer'   -Kind 'immediate' -Help "Démarre WSL (boot de la distribution par défaut)."
    }
}

New-ModuleObject -Id 'wsl' -Theme 'wsl' -Label 'WSL2' -Status $st -Fields @(
    New-Field -Key 'installed' -Label 'WSL installé'      -Value $installed -Kind 'bool' -Status $(if ($installed) {'ok'} else {'neutral'}) -Help 'Sous-système Windows pour Linux présent sur la machine.'
    New-Field -Key 'default'   -Label 'Distribution défaut' -Value $default -Kind 'text' -Status 'neutral' -Help 'Distribution WSL par défaut (lue dans le registre).'
    New-Field -Key 'running'   -Label 'Statut' -Value $statutValue -Kind 'text' -Status $statutStat -Help 'État actuel de WSL (Actif si un processus vmmem/wslservice tourne, sinon Inactif).'
) -Actions $wslActions
