<# Worker DETACHE : recalcule les sondes perimees, hors de toute requete HTTP.

   Appele par Get-State quand des sondes ont expire mais possedent deja une valeur : la
   requete rend immediatement ce qu'elle sait, ce worker rafraichit derriere. L'affichage
   ne depend donc plus de la sonde la plus lente.

   Get-State -Force prend le verrou 'VigieStateRecompute' : si un recalcul est deja en
   cours, celui-ci n'en lance pas un second, il sort. Aucun risque d'empilement.
#>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

try {
    $t0 = Get-Date
    $null = Get-State -Backend $Backend -Force
    Write-Log -Backend $Backend -Name 'state' -Message (
        "rafraichissement de fond termine (" + [int]((Get-Date) - $t0).TotalMilliseconds + " ms)")
} catch {
    Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (
        "rafraichissement de fond : " + $_.Exception.Message)
}
