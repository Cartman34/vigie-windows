<# Sonde : ressources (RAM / CPU / uptime). LECTURE SEULE, rapide. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$freeGB = if ($os) { [math]::Round($os.FreePhysicalMemory/1MB,1) } else { 0 }
$totGB  = if ($os) { [math]::Round($os.TotalVisibleMemorySize/1MB,1) } else { 0 }
$ramPct = if ($totGB) { [math]::Round(($totGB-$freeGB)/$totGB*100) } else { 0 }
$cpuAvg = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average
$cpu = if ($null -ne $cpuAvg) { [math]::Round($cpuAvg) } else { 0 }
$up = if ($os) { (Get-Date) - $os.LastBootUpTime } else { [TimeSpan]::Zero }
$upTxt = "{0}j {1}h {2}m" -f $up.Days, $up.Hours, $up.Minutes
New-ModuleObject -Id 'perf' -Theme 'system' -Label 'Ressources' -Status $(if ($ramPct -ge 90 -or $cpu -ge 90) {'warn'} else {'ok'}) -Fields @(
    New-Field -Key 'ramUsed' -Label 'RAM utilisée' -Value $ramPct  -Kind 'number' -Unit '%'  -Status $(if ($ramPct -ge 90) {'warn'} else {'ok'})      -Help 'Pourcentage de mémoire vive utilisée.'
    New-Field -Key 'ramFree' -Label 'RAM libre'    -Value $freeGB  -Kind 'number' -Unit 'Go' -Status 'neutral'                                        -Help 'Mémoire vive disponible.'
    New-Field -Key 'cpu'     -Label 'CPU'          -Value $cpu     -Kind 'number' -Unit '%'  -Status $(if ($cpu -ge 90) {'warn'} else {'neutral'})   -Help 'Charge processeur instantanée.'
    New-Field -Key 'uptime'  -Label 'Uptime'       -Value $upTxt   -Kind 'text'               -Status 'neutral'                                        -Help 'Durée depuis le dernier démarrage de Windows.'
)
