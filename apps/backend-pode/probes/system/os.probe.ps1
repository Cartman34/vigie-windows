# @author Florent HAZARD <f.hazard@sowapps.com>
<# Sonde : Windows (edition / activation / build / redemarrage en attente). LECTURE SEULE, rapide. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$caption = if ($os) { $os.Caption.Trim() } else { 'inconnu' }
$build   = if ($os) { "$($os.Version) ($($os.BuildNumber))" } else { '?' }
$edId    = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction SilentlyContinue).EditionID
$isPro   = ($edId -like 'Professional*') -or ($caption -match 'Pro')
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue | Select-Object -First 1
$activated = [bool]($lic -and $lic.LicenseStatus -eq 1)

# Redemarrage en attente : etat GENERAL de Windows (deux marqueurs du registre poses par
# la maintenance systeme, mises a jour comprises). Le champ vivait dans la carte du
# verrouillage Windows Update ; il concerne la machine entiere, il vit donc ici.
$reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
          (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

# Redemarrage : propose SEULEMENT quand il est utile, et toujours annulable.
$restartPending = Test-RestartCountdown -Backend $backend
$actions = @()
if ($restartPending) {
    $actions += New-Action -Id 'system-restart-cancel' -Label 'Annuler le redémarrage' -Severity 'fix' `
        -BusyLabel 'Annulation…' -Confirm -Help "Annule le redémarrage programmé. Windows reste allumé."
} elseif ($reboot) {
    $actions += New-Action -Id 'system-restart' -Label 'Redémarrer Windows' -Severity 'fix' `
        -BusyLabel 'Redémarrage programmé…' -ConfirmTwice -Kind 'confirm' `
        -Help "Redémarre Windows dans 60 secondes pour terminer les mises à jour installées. Enregistrez votre travail : toutes les applications seront fermées. Le redémarrage reste annulable pendant le délai."
}

New-ModuleObject -Id 'os' -Theme 'system' -Label 'Windows' -Status $(if ($activated -and -not $reboot) {'ok'} else {'warn'}) -Fields @(
    New-Field -Key 'edition'   -Label 'Édition'    -Value $caption    -Kind 'text' -Status $(if ($isPro) {'ok'} else {'neutral'}) -Help 'Édition de Windows installée (Pro attendu).'
    New-Field -Key 'activated' -Label 'Activation' -Value $activated  -Kind 'bool' -Status $(if ($activated) {'ok'} else {'warn'})    -Help 'Windows est activé (licence valide).'
    New-Field -Key 'build'     -Label 'Version'    -Value $build      -Kind 'text' -Status 'neutral'                                 -Help 'Version et numéro de build de Windows.'
    # Un redemarrage en attente n'est PAS une erreur : c'est l'issue NORMALE d'une mise a
    # jour ou d'une maintenance installee. C'est un point a traiter, donc « à voir ».
    New-Field -Key 'rebootPending' -Label 'Redémarrage en attente' -Value ([bool]$reboot) -Kind 'bool' -Status $(if ($reboot) {'warn'} else {'ok'}) `
        -Help "Une mise à jour ou une maintenance est installée mais ne sera active qu'après un redémarrage de Windows." `
        -FixAction $(if ($reboot -and -not $restartPending) { 'system-restart' } else { $null }) `
        -Guide $(if ($reboot) {
            "Ce que c'est : une mise à jour a été installée ; Windows a besoin de redémarrer pour la terminer. Ce n'est pas une panne.`n`n" +
            "Le risque à ne rien faire : les correctifs installés ne protègent pas encore, et Windows finira par redémarrer de lui-même si le verrouillage est levé.`n`n" +
            "Ce que vous pouvez faire :`n" +
            "- redémarrer quand cela vous arrange (le bouton « Redémarrer Windows » ci-dessous, ou menu Démarrer > Redémarrer) — c'est la seule action qui lève cet état ;`n" +
            "- continuer à travailler : Vigie ne force jamais un redémarrage, et le verrou du Mode MAJ empêche Windows de le faire."
        } else {
            "Aucun redémarrage en attente : toutes les mises à jour installées sont actives."
        })
) -Actions $actions
