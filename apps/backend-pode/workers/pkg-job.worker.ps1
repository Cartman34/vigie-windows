<# Worker DETACHE unique : execute une operation paquet ('check' ou 'upgrade')
   pour UN gestionnaire, puis rafraichit le compte de MAJ et invalide la sonde.
   Lance par Start-PkgJob via Start-DetachedAction (pwsh cache). N'ecrit QUE dans
   var/cache + var/log. Traite erreurs + sortie via Get-PkgUpdates / Invoke-PkgUpgrade. #>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

# Parametres (JSON base64) : mgr + op.
$mgr = $null; $op = 'check'
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        $mgr = "$($a.mgr)"
        if ($a.op) { $op = "$($a.op)" }
    }
} catch { }
if (-not $mgr) { return }

$outFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'pkgupdates.json'
try {
    if ($op -eq 'upgrade') {
        $up = Invoke-PkgUpgrade -Id $mgr
        try { Write-Log -Backend $Backend -Name 'pkgupgrade' -Message ("$mgr : exit=$($up.exit) ok=$($up.ok)") } catch { }
        try {
            $logf = Join-Path (Get-LogDir -Backend $Backend) ("pkgupgrade_" + $mgr + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")
            "$($up.output)" | Out-File -FilePath $logf -Encoding UTF8
        } catch { }
    }
    # Dans les deux cas on rafraichit le compte de MAJ (l'absence de "checking" = fin).
    $u = Get-PkgUpdates -Id $mgr
    Update-StateJson -Path $outFile -Set @{ $mgr = @{ count = [int]$u.count; items = @($u.items); at = (Get-Date).ToString('s') } } | Out-Null
    Write-Log -Backend $Backend -Name 'pkgcheck' -Message ("$mgr ($op) : $([int]$u.count) MAJ disponible(s)")
} catch {
    try { Update-StateJson -Path $outFile -Set @{ $mgr = @{ count = 0; items = @(); at = (Get-Date).ToString('s'); error = $_.Exception.Message } } | Out-Null } catch { }
    Write-Log -Backend $Backend -Name 'pkgcheck' -Level 'ERROR' -Message ("$mgr ($op) : " + $_.Exception.Message)
}

# Rafraichissement immediat de la carte au prochain acces (sans attendre le TTL).
try { Remove-ProbeCache -Names @('packages.probe.ps1') -Backend $Backend } catch { }
