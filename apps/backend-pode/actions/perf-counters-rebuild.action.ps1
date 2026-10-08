# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
# @libelle: Reconstruire les compteurs | immediate | fix   -- affiche quand un champ cite cette action (D66)
<# An action: it rebuilds Windows's performance counters.

   Intent: give back to the Gaming card the ability to say WHO is using the graphics processor. When the GPU
   counters (or others) stop answering, it cannot. The official repair is `lodctr /R`, which rebuilds the
   counters database from the system's files, followed by a resynchronisation of WMI.
   Usage: it is called from the Gaming card. Nothing is deleted, nothing is installed: we rebuild an index.

   A REAL OBSERVATION (D43): we do not make do with the exit code, we ask Windows for the GPU counters again in
   order to say whether they REALLY answer after the operation. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$etapes = @()

# 1) Rebuilding the counters database (32 and 64 bit, depending on the machine).
$r = Invoke-Native -File "$env:SystemRoot\System32\lodctr.exe" -Arguments @('/R')
$etapes += $(if ($r.Ok) { 'base des compteurs reconstruite' } else { "lodctr /R : echec (code $($r.ExitCode))" })

# 2) Resynchronising WMI: without it, the counters stay absent from the queries.
$r2 = Invoke-Native -File "$env:SystemRoot\System32\wbem\winmgmt.exe" -Arguments @('/resyncperf')
$etapes += $(if ($r2.Ok) { 'WMI resynchronise' } else { "winmgmt /resyncperf : echec (code $($r2.ExitCode))" })

# 3) The observation: do the GPU counters answer now?
$repondent = $false
# Read through PDH directly (VigiePdh), like the gaming card: a rate needs two readings, a short moment apart.
$pdh = $null
try {
    $pdh = [VigiePdh]::new()
    $engines = $pdh.Add('\GPU Engine(*)\Utilization Percentage')
    if ($engines -ge 0 -and $pdh.Collect()) {
        Start-Sleep -Milliseconds 250
        if ($pdh.Collect()) { $repondent = [bool](@($pdh.Read($engines)).Count -gt 0) }
    }
} catch { } finally { if ($pdh) { $pdh.Dispose() } }

if ($repondent) {
    @{ message = ("Compteurs reconstruits (" + ($etapes -join ' ; ') + "). Les compteurs GPU répondent de nouveau.")
       result = @{ ok = $true; invalidate = @('gaming.probe.ps1', 'perf.probe.ps1') } }
} else {
    @{ message = ("Reconstruction faite (" + ($etapes -join ' ; ') + ") mais les compteurs GPU ne répondent toujours pas : un redémarrage de Windows est souvent nécessaire pour qu'ils reviennent.")
       result = @{ ok = $false; invalidate = @('gaming.probe.ps1', 'perf.probe.ps1') } }
}
