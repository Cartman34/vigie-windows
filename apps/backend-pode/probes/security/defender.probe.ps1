# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    A probe: the ANTIVIRUS. READ ONLY.
    Intent: reflect the antivirus that is REALLY active (a third-party one, Defender, whichever), not Defender
    alone -- so it reads the Windows Security Centre (root/SecurityCenter2) and not Defender's own module.
    Usage: it is run by the scheduler like any probe.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$avs = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
if (-not $avs) {
    New-ModuleObject -Id 'antivirus' -Theme 'security' -Label 'Antivirus' -Scope 'machine' -Status 'neutral' -Fields @(
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
# The main antivirus: an active third-party one first, otherwise the first active one, otherwise the first
$primary = $parsed | Where-Object { $_.enabled -and -not $_.isDefender } | Select-Object -First 1
if (-not $primary) { $primary = $parsed | Where-Object { $_.enabled } | Select-Object -First 1 }
if (-not $primary) { $primary = $parsed | Select-Object -First 1 }

$others = @($parsed | Where-Object { $_.name -ne $primary.name })
$modSt  = if ($primary.enabled -and $primary.upToDate) { 'ok' } elseif ($primary.enabled) { 'warn' } else { 'error' }

$fields = @(
    New-Field -Key 'name'     -Label 'Antivirus'    -Value $primary.name       -Kind 'text' -Status 'ok' -Help "Antivirus enregistré et actif dans le Centre de sécurité Windows."
    New-Field -Key 'enabled'  -Label 'Actif'        -Value ([bool]$primary.enabled)  -Kind 'bool' -Status $(if ($primary.enabled) {'ok'} else {'error'}) `
        -Help "La protection de l'antivirus est active." -Guide "À faire : ouvrir l'antivirus et activer la protection en temps réel."
    New-Field -Key 'upToDate' -Label 'À jour'       -Value ([bool]$primary.upToDate) -Kind 'bool' -Status $(if ($primary.upToDate) {'ok'} else {'warn'}) `
        -Help "Les définitions de l'antivirus sont à jour." -Guide "À faire : ouvrir l'antivirus et lancer la mise à jour des définitions."
)
if ($others.Count -gt 0) {
    $fields += New-Field -Key 'others' -Label 'Autres détectés' -Value (($others | ForEach-Object { $_.name }) -join ', ') -Kind 'text' -Status 'neutral' -Help "Autres antivirus enregistrés (souvent Windows Defender en veille)."
}

# THE BUTTON IS THERE EVEN WHEN ALL IS WELL (D114): a card permanently carries the useful destination of its
# subject -- here Windows Security, where one starts a scan again and switches a protection back on. One does not
# discover it on the day of the breakdown.
# SCOPE: the protection of the whole computer, never of one account.
New-ModuleObject -Id 'antivirus' -Theme 'security' -Label 'Antivirus' -Scope 'machine' -Status $modSt -Fields $fields `
    -Actions @(New-Action -Id 'open-security-settings' -Label 'Sécurité Windows' -Kind 'manual' -Severity 'info' `
                    -Help 'Ouvre la Sécurité Windows : état de l''antivirus, analyses, protections.')
