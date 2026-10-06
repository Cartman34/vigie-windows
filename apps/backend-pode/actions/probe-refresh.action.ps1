# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- touche le cache commun, donc ce que tous les comptes voient (D65)
# @execution: serveur   -- le cache des sondes vit chez l'app serveur
<#
    Action: mark a probe's cache stale, so that the scheduler computes it again at its next pass.

    WHY IT EXISTS. A card is computed by the scheduler, never by a request (D124), and some intervals are long on
    purpose -- the packages card is worth one reading a day. After a correction to a probe there was therefore NO way
    to see the new behaviour: the installation does not invalidate the renderings, and a card kept the one from
    before for up to twenty-four hours. On 06/10 three successive deployments were read against a cache computed
    before the first of them, and each reading looked like the fix had not worked.

    WHAT IT DOES. Exactly what `Remove-ProbeCache` does, which is the one path: the known rendering is KEPT and
    marked to be recomputed -- a card never disappears -- and the scheduler is told, so an invalidated card does not
    wait out its whole interval. The per-account entries go with it (`<probe>@<account>`).

    WHAT IT DOES NOT DO: compute. Nothing is computed inside a request (D124); the answer says what was marked, and
    the card refreshes by itself within the pass that follows.

    Parameters: probe = the probe's file name, for instance "packages.probe.ps1". Without it, nothing is touched.
#>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$probe = if ($Params -and $Params.probe) { "$($Params.probe)" } else { $null }
if (-not $probe) { return @{ message = "Aucune sonde précisée."; result = @{ ok = $false } } }

# A FILE NAME, AND NOTHING THAT LOOKS LIKE A PATH: the cache is shared, and an action that takes a path takes
# anything. The probe must exist in this installation, otherwise nothing is touched.
if ($probe -notmatch '^[a-z][a-z0-9-]{0,40}\.probe\.ps1$') {
    return @{ message = "Nom de sonde invalide : $probe"; result = @{ ok = $false } }
}
$found = @(Get-ChildItem -LiteralPath (Join-Path $backend 'probes') -Recurse -File -Filter $probe -ErrorAction SilentlyContinue)
if (-not $found.Count) {
    return @{ message = "Sonde inconnue dans cette installation : $probe"; result = @{ ok = $false } }
}

try { Remove-ProbeCache -Names @($probe) -Backend $backend } catch {
    return @{ message = "Invalidation impossible : $($_.Exception.Message)"; result = @{ ok = $false } }
}
Write-Log -Backend $backend -Name 'actions' -Message ("sonde marquée à recalculer : " + $probe)

@{
    message = "$probe est marquée à recalculer : sa carte se met à jour d'elle-même au prochain passage."
    result  = @{ ok = $true; probe = $probe }
}
