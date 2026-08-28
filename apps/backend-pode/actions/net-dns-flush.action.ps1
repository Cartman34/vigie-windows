# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
# @libelle: Purger le cache DNS | immediate | fix   -- affiche quand un champ cite cette action (D66)
<# Action : purge le cache DNS -- Windows ET le proxy local s'il existe (Acrylic).

   Pourquoi : un cache DNS perime rend QUELQUES sites inaccessibles (constate le 25/08 :
   Facebook et Instagram injoignables via Acrylic) alors que la resolution generale
   fonctionne. Acrylic garde son cache en memoire : le purger = redemarrer son service.

   Constat a chaque etape (D43) : on verifie que le service est revenu ET qu'une
   resolution reelle aboutit avant d'annoncer un succes. Prudence machine : si le
   service ne revient pas, on le relance une seconde fois avant d'echouer. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$etapes = @()

# 1) Cache du resolveur Windows : toujours, c'est sans risque.
$r = Invoke-Native -File "$env:SystemRoot\System32\ipconfig.exe" -Arguments @('/flushdns')
$etapes += $(if ($r.Ok) { 'cache Windows purgé' } else { 'cache Windows : échec' })

# 2) Proxy DNS local, s'il existe : detecte par le port 53 (Acrylic ou n'importe quel
#    autre -- et rien du tout si la machine n'en a pas). Redemarrer = cache memoire vide.
$proxy = Get-LocalDnsProxyService
$svc = if ($proxy) { Get-Service -Name $proxy.Name -ErrorAction SilentlyContinue } else { $null }
if ($svc) {
    try {
        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
        # Le cache disque, s'il a ete ecrit, se supprime service arrete.
        try {
            $bin = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'").PathName.Trim('"')
            $dat = Join-Path (Split-Path $bin -Parent) 'AcrylicCache.dat'
            if (Test-Path -LiteralPath $dat) { Remove-Item -LiteralPath $dat -Force }
        } catch { }
        Start-Service -Name $svc.Name -ErrorAction Stop
    } catch {
        # Ne jamais laisser la machine sans resolveur : une seconde tentative de demarrage.
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

# 3) Constat final : une resolution reelle doit aboutir.
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
