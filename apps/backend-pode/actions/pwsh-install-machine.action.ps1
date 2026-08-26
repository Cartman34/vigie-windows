# @droits: admin   -- installe un logiciel pour toute la machine : Windows exige l'elevation (D65)
# @libelle: Installer PowerShell 7 pour la machine | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# Action : installe PowerShell 7 pour TOUTE LA MACHINE (winget, portee machine).

   Pourquoi cette action existe : les taches de demarrage des autres comptes lancent pwsh.
   Quand PowerShell 7 vient du Store, son chemin vit dans le profil de celui qui l'a
   installe -- illisible pour les autres, et l'alias renvoie a un paquet MSIX enregistre
   pour lui seul. La tache se cree sans erreur et ne lance rien : Vigie ne demarre pas,
   sans message (constate le 26/08 avec le compte Famille).

   L'installation MSI, elle, pose pwsh sous Program Files : tous les comptes peuvent le
   lancer. Tache de fond, sortie dans un fichier journal (jamais dans un tuyau que
   personne ne lit : ca bloque le processus). #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

if (Get-SharedPwshPath) {
    return @{ message = "PowerShell 7 est deja installe pour la machine : " + (Get-SharedPwshPath)
              result  = @{ ok = $true; invalidate = @('comptes.probe.ps1') } }
}
$winget = (Get-Command winget -ErrorAction SilentlyContinue)
if (-not $winget) {
    return @{ message = "winget est introuvable : installez PowerShell 7 depuis github.com/PowerShell/PowerShell (paquet MSI)."
              result  = @{ ok = $false } }
}

$journal = Join-Path (Get-LogDir -Backend $backend) ('pwsh-install_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')

$lance = $false
try {
    # Le veilleur attend la fin et RAPPORTE le code de sortie (D82). L'ancienne version
    # lancait winget et l'oubliait : l'echec du 26/08 (0x80070005, qui avait au passage
    # desinstalle le PowerShell existant) n'a produit ni ligne rouge ni notification.
    $lance = [bool](Start-WatchedAction -Module 'accounts' -Probe 'comptes.probe.ps1' `
                        -Label 'Installation de PowerShell 7' -Action 'pwsh-install-machine' `
                        -File $winget.Source -Arguments (Get-SharedPwshInstallArgs) `
                        -Log $journal -Backend $backend)
    Write-Log -Backend $backend -Name 'comptes' -Message ("installation de PowerShell 7 (machine) lancee, journal : " + $journal)
} catch {
    Write-Log -Backend $backend -Name 'comptes' -Level 'ERROR' -Message $_.Exception.Message
}

if (-not $lance) { return @{ message = "Impossible de lancer l'installation."; result = @{ ok = $false } } }

@{
    message = "Installation de PowerShell 7 pour la machine lancee. Elle dure une a deux minutes ; reactivez ensuite les comptes concernes."
    result  = @{ ok = $true; async = $true; module = 'accounts'; invalidate = @('comptes.probe.ps1') }
}
