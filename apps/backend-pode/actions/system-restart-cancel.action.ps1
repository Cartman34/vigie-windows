# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : annuler un redemarrage programme.

   Contrepartie indispensable de system-restart : un compte a rebours qu'on ne peut pas
   arreter n'est pas un delai de grace, c'est un piege a retardement.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$r = Invoke-Native -File 'shutdown.exe' -Arguments @('/a')
$fichier = Get-VarPath -Backend $backend -Kind 'cache' -File 'restart.json'

# Code 1116 = « aucun arret en cours » : ce n'est pas une panne, c'est deja l'etat voulu.
if (-not $r.Ok -and $r.ExitCode -ne 1116) {
    return @{
        message = "L'annulation a échoué (code $($r.ExitCode)). $($r.Output)"
        result  = @{ ok = $false }
    }
}
Update-StateJson -Path $fichier -Set @{ pending = $false; at = (Get-Date).ToUniversalTime().ToString('o') } | Out-Null

$msg = if ($r.ExitCode -eq 1116) { "Aucun redémarrage n'était programmé." } else { "Redémarrage annulé." }
@{ message = $msg; result = @{ ok = $true; invalidate = @('lock.probe.ps1','pending.probe.ps1') } }
