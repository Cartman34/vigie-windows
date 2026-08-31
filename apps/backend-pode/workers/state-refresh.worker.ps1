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

# POUR QUI. Sans session, ce worker ecrivait les cartes personnelles sous une cle
# anonyme -- c'est pourquoi elles etaient exclues du differe. Le compte lui est passe.
$pourQui = $null
if ($ArgsB64) {
    try {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        if ($a.account) { $pourQui = "$($a.account)" }
    } catch { }
}

try {
    $t0 = Get-Date
    $null = $(if ($pourQui) { Get-State -Backend $Backend -Force -Account $pourQui }
              else          { Get-State -Backend $Backend -Force })
    Write-Log -Backend $Backend -Name 'state' -Message (Get-Label 'state-refresh.rafraichissement-de-fond-termine' [int]((Get-Date) - $t0).TotalMilliseconds)
} catch {
    Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' -Message (Get-Label 'state-refresh.rafraichissement-de-fond' $_.Exception.Message)
}
