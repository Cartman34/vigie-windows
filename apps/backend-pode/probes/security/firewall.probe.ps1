<# Sonde : pare-feu Windows (profils actifs). LECTURE SEULE, rapide. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$fp = Get-NetFirewallProfile -ErrorAction SilentlyContinue
function FwOn($n) {
    $x = $fp | Where-Object { $_.Name -eq $n } | Select-Object -First 1
    if (-not $x) { return $null }
    $v = "$($x.Enabled)"
    return ($v -eq 'True' -or $v -eq '1')
}
$dom = FwOn 'Domain'; $priv = FwOn 'Private'; $pub = FwOn 'Public'
$known = @(@($dom, $priv, $pub) | Where-Object { $null -ne $_ })
$offCount = @($known | Where-Object { $_ -eq $false }).Count
$onCount  = @($known | Where-Object { $_ -eq $true }).Count
$modSt = if ($known.Count -eq 0) { 'neutral' } elseif ($offCount -eq 0) { 'ok' } elseif ($onCount -gt 0) { 'warn' } else { 'error' }

function FwField($key, $label, $val) {
    if ($null -eq $val) {
        New-Field -Key $key -Label $label -Value 'inconnu' -Kind 'text' -Status 'neutral' -Help "État du pare-feu non lisible pour ce profil."
    } else {
        New-Field -Key $key -Label $label -Value ([bool]$val) -Kind 'bool' -Status $(if ($val) {'ok'} else {'error'}) `
            -Help "Pare-feu Windows actif sur ce profil réseau." `
            -Guide "Activez le pare-feu pour ce profil : Sécurité Windows > Pare-feu et protection réseau."
    }
}
New-ModuleObject -Id 'firewall' -Theme 'security' -Label 'Pare-feu' -Status $modSt -Fields @(
    (FwField 'domain'  'Profil Domaine' $dom)
    (FwField 'private' 'Profil Privé'   $priv)
    (FwField 'public'  'Profil Public'  $pub)
)
