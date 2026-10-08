# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    vigie-diag-account.ps1 -- reads back ANOTHER account's Vigie logs, for troubleshooting.

    Intent: look into another account without opening a second road to its data. It reads nothing itself: it asks
    VIGIE to do it (the server already runs elevated when an administrator uses it). Two wanted consequences:
      - not one more UAC prompt at every diagnosis;
      - the filter is the one of every sensitive operation: the action is declared as needing an administrator, so
        a standard account is refused -- exactly as for the Windows Update lock (D65).

    READ ONLY on the account that is aimed at. That account's API token is never copied.

    Usage:
      pwsh -File .\scripts\vigie-diag-account.ps1                    # lists the accounts
      pwsh -File .\scripts\vigie-diag-account.ps1 -Account <name>
    Exit codes: 0 = done; 1 = the account or the data could not be found; 2 = Vigie is unreachable;
    3 = refused (not an administrator account).
#>


param([string] $Account)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

if (-not $Account) {
    Write-Info (Get-Label 'vigie-diag-account.comptes-de-cette-machine')
    Get-ComputerAccounts | ForEach-Object {
        Write-Host ("  {0} {1,-24} {2}" -f $(if ($_.enabled) { '[x]' } else { '[ ]' }), $_.name,
                    $(if ($_.admin) { 'administrateur' } else { 'standard' }))
    }
    Write-Info (Get-Label 'vigie-diag-account.pour-rapatrier-les-journaux')
    Write-Info (Get-Label 'vigie-diag-account.pwsh-file-scripts-vigie')
    exit 0
}

# Through the local API: Vigie holds the elevation, this script does not.
$url   = (Get-AppUrl -Backend $backend).TrimEnd('/')
$cfg   = Get-Config -Backend $backend
$token = Get-ApiToken -Backend $backend
if (-not $token) { Write-Warn (Get-Label 'vigie-diag-account.jeton-api-introuvable-vigie'); exit 2 }

$corps = @{ type = 'diag-account-logs'; module = 'accounts'; params = @{ account = $Account } } | ConvertTo-Json -Depth 4
try {
    $rep = Invoke-RestMethod -Method Post -Uri ($url + $cfg.ApiBase + '/actions') -Body $corps -ContentType 'application/json' -Headers @{
        Authorization = 'Bearer ' + $token
        # The server's anti-CSRF accepts loopback origins only.
        Origin        = $url
    } -TimeoutSec 60
} catch {
    $msg = "$($_.Exception.Message)"
    if ($msg -match '400|403') {
        Write-Warn (Get-Label 'vigie-diag-account.vigie-refuse-cette-operation')
        exit 3
    }
    Write-Warn (Get-Label 'vigie-diag-account.vigie-injoignable' $msg)
    Write-Info (Get-Label 'vigie-diag-account.verifiez-que-application-tourne')
    exit 2
}

Write-Host $rep.message
if ($rep.result -and $rep.result.ok) {
    Write-Info ("  -> " + $rep.result.path)
    Write-Info (Get-Label 'vigie-diag-account.ces-fichiers-se-lisent')
    exit 0
}
exit 1
