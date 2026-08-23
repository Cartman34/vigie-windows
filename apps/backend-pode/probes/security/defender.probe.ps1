<#
    Sonde : Antivirus. LECTURE SEULE. Lit le Centre de sécurité Windows
    (root/SecurityCenter2) pour refleter l'antivirus REELLEMENT actif
    (Avast, Defender, etc.), pas seulement Defender.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$avs = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
if (-not $avs) {
    New-ModuleObject -Id 'antivirus' -Theme 'security' -Label 'Antivirus' -Status 'neutral' -Fields @(
        New-Field -Key 'status' -Label 'État' -Value 'indisponible' -Kind 'text' -Status 'neutral' -Help "Centre de sécurité Windows non interrogeable sur ce système."
    )
    return
}

$parsed = foreach ($a in $avs) {
    $st  = [int]$a.productState
    $hex = ('{0:x6}' -f $st)
    [pscustomobject]@{
        name       = $a.displayName
        enabled    = ($hex.Substring(2,2) -in '10','11')
        upToDate   = ($hex.Substring(4,2) -eq '00')
        isDefender = ($a.displayName -match 'Defender')
    }
}
# Antivirus principal : un antivirus tiers actif en priorite, sinon le premier actif, sinon le premier
$primary = $parsed | Where-Object { $_.enabled -and -not $_.isDefender } | Select-Object -First 1
if (-not $primary) { $primary = $parsed | Where-Object { $_.enabled } | Select-Object -First 1 }
if (-not $primary) { $primary = $parsed | Select-Object -First 1 }

$others = @($parsed | Where-Object { $_.name -ne $primary.name })
$modSt  = if ($primary.enabled -and $primary.upToDate) { 'ok' } elseif ($primary.enabled) { 'warn' } else { 'error' }

$fields = @(
    New-Field -Key 'name'     -Label 'Antivirus'    -Value $primary.name       -Kind 'text' -Status 'ok' -Help "Antivirus enregistré et actif dans le Centre de sécurité Windows."
    New-Field -Key 'enabled'  -Label 'Actif'        -Value ([bool]$primary.enabled)  -Kind 'bool' -Status $(if ($primary.enabled) {'ok'} else {'error'}) `
        -Help "La protection de l'antivirus est active." -Guide "Ouvrez votre antivirus et activez la protection en temps réel."
    New-Field -Key 'upToDate' -Label 'À jour'       -Value ([bool]$primary.upToDate) -Kind 'bool' -Status $(if ($primary.upToDate) {'ok'} else {'warn'}) `
        -Help "Les définitions de l'antivirus sont à jour." -Guide "Ouvrez votre antivirus et lancez la mise à jour des définitions."
)
if ($others.Count -gt 0) {
    $fields += New-Field -Key 'others' -Label 'Autres détectés' -Value (($others | ForEach-Object { $_.name }) -join ', ') -Kind 'text' -Status 'neutral' -Help "Autres antivirus enregistrés (souvent Windows Defender en veille)."
}

New-ModuleObject -Id 'antivirus' -Theme 'security' -Label 'Antivirus' -Status $modSt -Fields $fields
