# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
# @libelle: Purger le cache DNS | immediate | fix   -- affiche quand un champ cite cette action (D66)
<# An action: it purges the DNS cache -- Windows's AND the local proxy's if there is one (Acrylic).

   Intent: fix the case where a stale DNS cache makes SOME sites unreachable (observed on 25/08: two sites
   unreachable through Acrylic) while the general resolution works. Acrylic keeps its cache in memory: purging it
   means restarting its service.
   Usage: it is called from the Network card. Observation at every step (D43): we check that the service has come
   back AND that a real resolution succeeds before announcing a success. Caution for the machine: if the service
   does not come back, we start it a second time before failing. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$etapes = @()

# 1) Windows's resolver cache: always, it is without risk.
$r = Invoke-Native -File "$env:SystemRoot\System32\ipconfig.exe" -Arguments @('/flushdns')
$etapes += $(if ($r.Ok) { 'cache Windows purgé' } else { 'cache Windows : échec' })

# 2) A local DNS proxy, if there is one: detected by port 53 (Acrylic or any other -- and nothing at all if the
#    machine has none). Restarting it means an empty memory cache.
$proxy = Get-LocalDnsProxyService
$svc = if ($proxy) { Get-Service -Name $proxy.Name -ErrorAction SilentlyContinue } else { $null }
if ($svc) {
    try {
        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
        # The disc cache, if it was written, is deleted with the service stopped.
        try {
            $bin = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'").PathName.Trim('"')
            $dat = Join-Path (Split-Path $bin -Parent) 'AcrylicCache.dat'
            if (Test-Path -LiteralPath $dat) { Remove-Item -LiteralPath $dat -Force }
        } catch { }
        Start-Service -Name $svc.Name -ErrorAction Stop
    } catch {
        # Never leave the machine without a resolver: a second attempt at starting it.
        try { Start-Service -Name $svc.Name -ErrorAction SilentlyContinue } catch { }
    }
    $revenu = $false
    for ($i = 0; $i -lt 10; $i++) {
        if ((Get-Service -Name $svc.Name).Status -eq 'Running') { $revenu = $true; break }
        Start-Sleep -Milliseconds 500
    }
    $etapes += $(if ($revenu) { "service $($svc.Name) redémarré (cache local vidé)" } else { "service $($svc.Name) : NON revenu" })
    if (-not $revenu) {
        return @{ message = "Purge incomplète : le service $($svc.Name) n'est pas revenu — démarrez-le dans services.msc."
                  result = @{ ok = $false; invalidate = @('net.probe.ps1') } }
    }
}

# 3) The final observation: a real resolution must succeed.
$resolu = $false
for ($i = 0; $i -lt 6; $i++) {
    try { if (Resolve-DnsName 'www.microsoft.com' -Type A -QuickTimeout -ErrorAction Stop) { $resolu = $true; break } } catch { }
    Start-Sleep -Milliseconds 500
}
if ($resolu) {
    @{ message = ("Cache DNS purgé (" + ($etapes -join ' ; ') + "). Résolution vérifiée.")
       result = @{ ok = $true; invalidate = @('net.probe.ps1') } }
} else {
    @{ message = ("Purge faite (" + ($etapes -join ' ; ') + ") mais la résolution ne répond pas encore — réessayez dans quelques secondes.")
       result = @{ ok = $false; invalidate = @('net.probe.ps1') } }
}
