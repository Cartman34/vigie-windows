# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- it deletes data the service account owns (D65)
<# Action: resets one part of the server's data -- params.part = 'cache' or 'history'. The cache is recomputed at the
   next reading; the history starts again from the next measurement. Busy marks live in var/run and are not touched:
   an operation in progress stays visible. The maintenance doc/progress/targeting/components.md requires for both. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$part = if ($Params) { "$($Params.part)" } else { '' }
if (@('cache', 'history') -notcontains $part) {
    return @{ message = "Partie à réinitialiser inconnue : « cache » ou « history » attendu."; result = @{ ok = $false } }
}
$dir = Get-VarPath -Backend $backend -Kind $part
$removed = 0
$failed = @()
foreach ($entry in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
    try {
        Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
        $removed++
    } catch {
        $failed += ($entry.Name + ' : ' + $_.Exception.Message)
    }
}
$label = if ($part -eq 'cache') { 'Cache' } else { 'Historique des mesures' }
if ($failed.Count) {
    return @{ message = ($label + " réinitialisé en partie : " + $failed.Count + " élément(s) n'ont pas pu être supprimés.")
              result  = @{ ok = $false; removed = $removed; failed = $failed } }
}
@{
    message = ($label + " réinitialisé : " + $removed + " élément(s) supprimé(s).")
    result  = @{ ok = $true; removed = $removed }
}
