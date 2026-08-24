<# Sonde : disque C:. LECTURE SEULE, rapide. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
$freeGB = if ($c) { [math]::Round($c.FreeSpace/1GB) } else { 0 }
$totGB  = if ($c) { [math]::Round($c.Size/1GB) } else { 0 }
$usedPct= if ($c -and $c.Size) { [math]::Round(($c.Size - $c.FreeSpace)/$c.Size*100) } else { 0 }
# Seuil : config du module (module.psd1), surchargeable dans le menu Parametres (D57).
$threshold = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskWarnGb')
if (-not $threshold) { $threshold = 60 }   # filet si la declaration disparaissait
$st = if ($freeGB -lt 20) { 'error' } elseif ($freeGB -lt $threshold) { 'warn' } else { 'ok' }
New-ModuleObject -Id 'disk-c' -Theme 'system' -Label 'Disque C:' -Status $st -Fields @(
    New-Field -Key 'free'      -Label 'Espace libre'   -Value $freeGB   -Kind 'number' -Unit 'Go' -Status $st       -Help 'Espace disponible sur C:. En dessous du seuil, risque de saturation.' -FixAction 'disk-cleanup' -Guide 'Libérez de l''espace : ouvrez le Nettoyage de disque, videz la corbeille, désinstallez des applications inutiles.'
    New-Field -Key 'threshold' -Label 'Seuil d''alerte' -Value $threshold -Kind 'number' -Unit 'Go' -Status 'neutral' -Help 'Seuil en dessous duquel on alerte. Reglable : Paramètres > Modules > Système.'
    New-Field -Key 'used'      -Label 'Occupation'     -Value $usedPct  -Kind 'number' -Unit '%'  -Status 'neutral' -Help 'Pourcentage d''occupation du disque C:.'
    New-Field -Key 'total'     -Label 'Taille totale'  -Value $totGB    -Kind 'number' -Unit 'Go' -Status 'neutral' -Help 'Capacité totale du disque C:.'
) -Actions @(New-Action -Id 'disk-cleanup' -Severity 'fix' -Label 'Nettoyage de disque...' -Kind 'manual' -Help "Ouvre l'outil Windows 'Nettoyage de disque' (cleanmgr). Vous choisissez quoi supprimer ; rien n'est supprimé automatiquement.")
