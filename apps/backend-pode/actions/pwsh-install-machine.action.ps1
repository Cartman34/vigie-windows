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
$erreurs = $journal -replace '\.log$', '.err.log'

$lance = $false
try {
    # Memes arguments que le script d'installation : une seule definition (D15).
    $argv = Get-SharedPwshInstallArgs
    $proc = Start-Process -FilePath $winget.Source -ArgumentList $argv -WindowStyle Hidden -PassThru `
                          -RedirectStandardOutput $journal -RedirectStandardError $erreurs
    $lance = [bool]$proc
    # La carte le DIT tant que le processus vit (D80).
    if ($lance) {
        Set-ModuleBusyMark -Module 'accounts' -Label 'Installation de PowerShell 7' `
                           -ProcessId $proc.Id -Action 'pwsh-install-machine' -Backend $backend
    }
    Write-Log -Backend $backend -Name 'comptes' -Message ("installation de PowerShell 7 (machine) lancee, journal : " + $journal)
} catch {
    Write-Log -Backend $backend -Name 'comptes' -Level 'ERROR' -Message $_.Exception.Message
}

if (-not $lance) { return @{ message = "Impossible de lancer l'installation."; result = @{ ok = $false } } }

@{
    message = "Installation de PowerShell 7 pour la machine lancee. Elle dure une a deux minutes ; reactivez ensuite les comptes concernes."
    result  = @{ ok = $true; async = $true; module = 'accounts'; invalidate = @('comptes.probe.ps1') }
}
