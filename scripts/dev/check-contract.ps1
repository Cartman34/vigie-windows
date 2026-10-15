# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-contract.ps1 -- DOES THE CONTRACT SAY WHAT THE SERVER SERVES ? READ ONLY.

    Intent: hold the rule that already exists -- `api/openapi.yaml` is the source of truth of the REST contract
    (D30) -- with a mechanism instead of a good intention. WHY IT EXISTS: on 15/10 I found `GET /hardware` absent
    from the contract while the report page reads it; listing the routes then showed SEVEN undocumented ones. No
    checker compared the two sides, so the gap could only be found by someone looking for it, and it had been
    there for weeks.

    Usage:
      pwsh -File .\scripts\dev\check-contract.ps1
      pwsh -File .\scripts\dev\check-contract.ps1 -Detail
    Exit codes: 0 = the two sides say the same thing; 2 = a route is served and not documented, or documented and
                not served.

    HOW IT READS THE CONTRACT, AND WHY THAT IS ENOUGH. There is no YAML parser on this machine (D06), so the
    paths are read by INDENTATION: a path is a line of two spaces then a slash, a method a line of four spaces
    then `get:` or `post:`. That is the shape openapi.yaml has, and the file is written by hand in that shape; if
    somebody reshapes it, this checker says it finds nothing rather than pretending -- an empty contract is
    refused below.

    WHAT IT DOES NOT CHECK: whether the SCHEMAS match what the route really returns. That would need to run the
    route, and it is `check-probes` plus the front end that judge the content. This one answers one question
    only, the one nobody was answering: is every door of the house on the plan?
#>
[CmdletBinding()]
param(
    [switch] $Detail
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

Write-Title 'Le contrat et les routes'

$serverFile = Join-Path $repoRoot 'apps/backend-pode/server.ps1'
$contractFile = Join-Path $repoRoot 'apps/backend-pode/api/openapi.yaml'
foreach ($f in @($serverFile, $contractFile)) {
    if (-not (Test-Path -LiteralPath $f)) { Write-Fail "Fichier introuvable : $f"; exit 2 }
}

# --- 1. What the server serves ------------------------------------------------------------------------------
#
# ONLY THE API ROUTES: those declared under $base. The page, the report and the icon are served by their own
# routes, which are not the REST contract and have nothing to do here.
Write-Step 'Ce que le serveur sert'
$served = @{}
foreach ($line in (Get-Content -LiteralPath $serverFile -Encoding UTF8)) {
    $m = [regex]::Match("$line", 'Add-PodeRoute\s+-Method\s+(\w+)\s+-Path\s+"\$base(/[^"]*)"')
    if (-not $m.Success) { continue }
    # Pode names a parameter `:id`, the contract `{id}`: one spelling for the comparison.
    $path = [regex]::Replace($m.Groups[2].Value, ':([A-Za-z]\w*)', '{$1}')
    $served[($m.Groups[1].Value.ToUpperInvariant() + ' ' + $path)] = $true
}
if (-not $served.Count) { Write-Fail "Aucune route lue dans server.ps1 : ce contrôle ne peut rien affirmer."; exit 2 }
Write-Detail "$($served.Count) route(s) d'API déclarées."

# --- 2. What the contract describes --------------------------------------------------------------------------
Write-Step 'Ce que le contrat décrit'
$documented = @{}
$currentPath = $null
$inPaths = $false
foreach ($line in (Get-Content -LiteralPath $contractFile -Encoding UTF8)) {
    if ("$line" -match '^paths:') { $inPaths = $true; continue }
    if ("$line" -match '^[a-zA-Z]') { $inPaths = $false; continue }   # components:, info:, ... : we have left
    if (-not $inPaths) { continue }
    $p = [regex]::Match("$line", '^  (/\S*):\s*$')
    if ($p.Success) { $currentPath = $p.Groups[1].Value; continue }
    $v = [regex]::Match("$line", '^    (get|post|put|patch|delete):\s*$')
    if ($v.Success -and $currentPath) { $documented[($v.Groups[1].Value.ToUpperInvariant() + ' ' + $currentPath)] = $true }
}
if (-not $documented.Count) { Write-Fail "Aucun chemin lu dans openapi.yaml : la forme du fichier a changé."; exit 2 }
Write-Detail "$($documented.Count) route(s) décrites."

# --- 3. The two sides, in both directions --------------------------------------------------------------------
Write-Step 'Les deux côtés disent-ils la même chose ?'
$undocumented = @($served.Keys  | Where-Object { -not $documented.ContainsKey($_) } | Sort-Object)
$unserved     = @($documented.Keys | Where-Object { -not $served.ContainsKey($_) }    | Sort-Object)

if ($undocumented.Count) {
    Write-Fail "$($undocumented.Count) route(s) servies et absentes du contrat (D30) :"
    foreach ($r in $undocumented) { Write-Detail $r }
}
if ($unserved.Count) {
    Write-Fail "$($unserved.Count) route(s) décrites et plus servies : le contrat promet ce que personne ne tient."
    foreach ($r in $unserved) { Write-Detail $r }
}
if ($Detail -and -not ($undocumented.Count + $unserved.Count)) {
    foreach ($r in @($served.Keys | Sort-Object)) { Write-Detail $r }
}

if ($undocumented.Count + $unserved.Count) { exit 2 }
Write-Ok "Les $($served.Count) routes servies sont décrites, et rien n'est décrit en trop."
Write-Outcome -What 'Le contrat et les routes coïncident'
exit 0
