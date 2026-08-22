<# Worker DETACHE : verifie les MAJ d'UN gestionnaire et fusionne le resultat,
   puis invalide la sonde packages pour que la carte s'actualise aussitot.
   Lance par Start-DetachedAction (pwsh cache). N'ecrit QUE dans .state (lecture
   seule cote systeme). Traite erreurs + sortie via Get-PkgUpdates/Invoke-Native. #>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

# Parametres (JSON base64).
$mgr = $null
try {
    if ($ArgsB64) {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))
        $a = $json | ConvertFrom-Json
        $mgr = "$($a.mgr)"
    }
} catch { }
if (-not $mgr) { return }

$outFile = Join-Path $Backend '.state\pkgupdates.json'
try {
    $u = Get-PkgUpdates -Id $mgr
    # Ecrit le resultat final : l'absence de "checking" signale la fin.
    Update-StateJson -Path $outFile -Set @{ $mgr = @{ count = [int]$u.count; items = @($u.items); at = (Get-Date).ToString('s') } } | Out-Null
    Write-Log -Backend $Backend -Name 'pkgcheck' -Message ("$mgr : $([int]$u.count) MAJ disponible(s)")
} catch {
    try { Update-StateJson -Path $outFile -Set @{ $mgr = @{ count = 0; items = @(); at = (Get-Date).ToString('s'); error = $_.Exception.Message } } | Out-Null } catch { }
    Write-Log -Backend $Backend -Name 'pkgcheck' -Level 'ERROR' -Message ("$mgr : " + $_.Exception.Message)
}

# Rafraichissement immediat de la carte au prochain acces (sans attendre le TTL).
try { Remove-ProbeCache -Names @('packages.probe.ps1') -Backend $Backend } catch { }
