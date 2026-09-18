# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
# @libelle: Reconstruire les compteurs | immediate | fix   -- affiche quand un champ cite cette action (D66)
<# Action : reconstruit les compteurs de performance de Windows.

   Quand les compteurs GPU (ou d'autres) ne repondent plus, la carte Jeux ne peut plus
   dire QUI utilise le processeur graphique. La reparation officielle est `lodctr /R`,
   qui reconstruit la base des compteurs depuis les fichiers du systeme, suivie d'une
   resynchronisation de WMI.

   Rien n'est supprime, rien n'est installe : on reconstruit un index.

   CONSTAT REEL (D43) : on ne se contente pas du code de retour, on redemande les
   compteurs GPU a Windows pour dire s'ils repondent VRAIMENT apres l'operation. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$etapes = @()

# 1) Reconstruction de la base des compteurs (32 et 64 bits selon la machine).
$r = Invoke-Native -File "$env:SystemRoot\System32\lodctr.exe" -Arguments @('/R')
$etapes += $(if ($r.Ok) { 'base des compteurs reconstruite' } else { "lodctr /R : echec (code $($r.ExitCode))" })

# 2) Resynchronisation WMI : sans elle, les compteurs restent absents des requetes.
$r2 = Invoke-Native -File "$env:SystemRoot\System32\wbem\winmgmt.exe" -Arguments @('/resyncperf')
$etapes += $(if ($r2.Ok) { 'WMI resynchronise' } else { "winmgmt /resyncperf : echec (code $($r2.ExitCode))" })

# 3) Constat : les compteurs GPU repondent-ils maintenant ?
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
