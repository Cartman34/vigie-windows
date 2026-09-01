# @author Florent HAZARD <f.hazard@sowapps.com>
<# Worker DETACHE : recalcule UNE sonde perimee, hors de toute requete HTTP.

   LA REGLE (utilisateur) : « le serveur peut le lancer seul en background mais ca doit
   etre non bloquant », et « rare, et par carte uniquement ». Personne n'attend derriere
   ce processus : la reponse est deja partie avec la valeur connue.

   UNE SEULE SONDE PAR PASSAGE. La version precedente appelait Get-State -Force et
   recalculait les dix-sept : une passe durait une minute et demie, les delais des autres
   expiraient pendant ce temps, et la requete suivante en relancait une -- la machine ne
   s'arretait plus (mesure le 31/08, /state a 27 secondes). On en prend UNE, la plus
   ancienne, et on s'arrete.

   Le verrou 'VigieStateRecompute' empeche deux passages simultanes ; l'appelant le
   verifie AVANT de lancer, pour ne pas payer un demarrage de pwsh pour rien.
#>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

$account = $null
$probe = $null
if ($ArgsB64) {
    try {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        if ($a.account) { $account = "$($a.account)" }
        if ($a.probe)   { $probe   = "$($a.probe)" }
    } catch { }
}
if (-not $probe) { return }

try {
    $t0 = Get-Date
    $stateArgs = @{ Backend = $Backend; Only = @($probe) }
    if ($account) { $stateArgs['Account'] = $account }
    $null = Get-State @stateArgs
    Write-Log -Backend $Backend -Name 'state' -NoEcho `
              -Message ("fond : " + $probe + " recalculee en " + [int]((Get-Date) - $t0).TotalMilliseconds + " ms")
} catch {
    Write-Log -Backend $Backend -Name 'state' -Level 'ERROR' `
              -Message ("fond : " + $probe + " -- " + $_.Exception.Message)
}
