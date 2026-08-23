<# Sonde : Windows (edition / activation / build). LECTURE SEULE, rapide. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$caption = if ($os) { $os.Caption.Trim() } else { 'inconnu' }
$build   = if ($os) { "$($os.Version) ($($os.BuildNumber))" } else { '?' }
$edId    = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction SilentlyContinue).EditionID
$isPro   = ($edId -like 'Professional*') -or ($caption -match 'Pro')
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue | Select-Object -First 1
$activated = [bool]($lic -and $lic.LicenseStatus -eq 1)
New-ModuleObject -Id 'os' -Theme 'system' -Label 'Windows' -Status $(if ($activated) {'ok'} else {'warn'}) -Fields @(
    New-Field -Key 'edition'   -Label 'Édition'    -Value $caption    -Kind 'text' -Status $(if ($isPro) {'ok'} else {'neutral'}) -Help 'Édition de Windows installée (Pro attendu).'
    New-Field -Key 'activated' -Label 'Activation' -Value $activated  -Kind 'bool' -Status $(if ($activated) {'ok'} else {'warn'})    -Help 'Windows est activé (licence valide).'
    New-Field -Key 'build'     -Label 'Version'    -Value $build      -Kind 'text' -Status 'neutral'                                 -Help 'Version et numéro de build de Windows.'
)
