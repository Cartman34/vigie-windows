<#
    vigie-diag-compte.ps1 - Relit les journaux de Vigie d'un AUTRE compte, pour depannage.

    Il ne lit rien lui-meme : il demande a VIGIE de le faire (le serveur tourne deja eleve
    quand un administrateur l'utilise). Deux consequences voulues :
      - aucune invite UAC de plus a chaque diagnostic ;
      - le filtre est celui de toutes les operations sensibles : l'action est declaree
        « @droits: admin », donc un compte standard se voit refuser -- exactement comme
        pour le verrou Windows Update (D65).

    LECTURE SEULE chez le compte vise. Le jeton d'API de ce compte n'est jamais copie.

    Usage :
      pwsh -File .\scripts\vigie-diag-compte.ps1                    # liste les comptes
      pwsh -File .\scripts\vigie-diag-compte.ps1 -Compte Famille

    Codes de retour : 0 = fait ; 1 = compte ou donnees introuvables ; 2 = Vigie injoignable ;
    3 = refuse (compte non administrateur).
#>
param([string] $Compte)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

if (-not $Compte) {
    Write-Info (Get-Label 'vigie-diag-compte.comptes-de-cette-machine')
    Get-ComputerAccounts | ForEach-Object {
        Write-Host ("  {0} {1,-24} {2}" -f $(if ($_.enabled) { '[x]' } else { '[ ]' }), $_.name,
                    $(if ($_.admin) { 'administrateur' } else { 'standard' }))
    }
    Write-Info (Get-Label 'vigie-diag-compte.pour-rapatrier-les-journaux')
    Write-Info (Get-Label 'vigie-diag-compte.pwsh-file-scripts-vigie')
    exit 0
}

# On passe par l'API locale : c'est Vigie qui detient l'elevation, pas ce script.
$url   = (Get-AppUrl -Backend $backend).TrimEnd('/')
$cfg   = Get-Config -Backend $backend
$token = Get-ApiToken -Backend $backend
if (-not $token) { Write-Warn (Get-Label 'vigie-diag-compte.jeton-api-introuvable-vigie'); exit 2 }

$corps = @{ type = 'diag-account-logs'; module = 'accounts'; params = @{ account = $Compte } } | ConvertTo-Json -Depth 4
try {
    $rep = Invoke-RestMethod -Method Post -Uri ($url + $cfg.ApiBase + '/actions') -Body $corps -ContentType 'application/json' -Headers @{
        Authorization = 'Bearer ' + $token
        # L'anti-CSRF du serveur n'accepte que les origines de bouclage.
        Origin        = $url
    } -TimeoutSec 60
} catch {
    $msg = "$($_.Exception.Message)"
    if ($msg -match '400|403') {
        Write-Warn (Get-Label 'vigie-diag-compte.vigie-refuse-cette-operation')
        exit 3
    }
    Write-Warn (Get-Label 'vigie-diag-compte.vigie-injoignable' $msg)
    Write-Info (Get-Label 'vigie-diag-compte.verifiez-que-application-tourne')
    exit 2
}

Write-Host $rep.message
if ($rep.result -and $rep.result.ok) {
    Write-Info ("  -> " + $rep.result.path)
    Write-Info (Get-Label 'vigie-diag-compte.ces-fichiers-se-lisent')
    exit 0
}
exit 1
