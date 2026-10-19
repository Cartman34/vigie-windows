# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-layers.ps1 -- THE SHAPE OF THE LIBRARY: a frozen floor, and no cycle above it.

    WHY THIS VERIFIER EXISTS. `common.ps1` reached 11 910 lines because nothing said where a new function should
    go, so it went where the others were. The library is leaving by subject (S28) under a structure the owner
    settled on 19/10: the FLOOR -- what depends on nothing of the project -- never calls upwards, and above it the
    subjects call each other as the subject requires, with one single rule, NO CYCLE.

    A structure nobody checks is a structure that lasts until the next hurry. This reads the real calls from the
    syntax tree, not the intentions.

    WHAT EACH PIECE DECLARES, in its first lines:
      # @layer: floor      or      # @layer: subject
      # @uses: format, paths
    `@uses:` must say exactly what the piece really uses -- no less (a hidden dependency), no more (a dependency
    that went away and was never erased).

    In PowerShell a cycle BREAKS NOTHING: the facade sources everything and a function resolves when it is called.
    The cycle does not cost a failure, it costs the ability to reason about one piece without reading the others.
    That is why it needs a verifier to exist at all.

    Usage:
      pwsh -File .\scripts\dev\check-layers.ps1
      pwsh -File .\scripts\dev\check-layers.ps1 -Detail
#>
param([switch]$Detail)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
Write-Title 'Les couches de la bibliothèque'

$libDir = Join-Path $repoRoot 'apps/backend-pode/lib'
$facade = 'common.ps1'

# THE SIZE CEILING OF A PIECE, and it never goes up. It is a DESIGN limit, not today's maximum: pieces arrive
# from a monolith, so one of 400 lines is progress. Past 600, a piece is a monolith in the making. 19/10: the
# floor's first piece, format.ps1, is 97 lines.
# common.ps1 is the facade and is counted apart: it is what is emptying.
$PIECE_CEILING = 600

$pieces = @(Get-ChildItem -LiteralPath $libDir -File -Filter '*.ps1' | Where-Object { $_.Name -ne $facade })
if (-not $pieces.Count) { Write-Warn 'Aucun morceau dans lib/ : rien à vérifier.'; exit 0 }

# --- What each piece declares, and what it defines ----------------------------------------------------------
$declaredUses = @{}
$layer = @{}
$defines = @{}        # function name -> piece
$sizes = @{}
$bad = 0

foreach ($f in $pieces) {
    $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    $sizes[$name] = (Get-Content -LiteralPath $f.FullName -Encoding UTF8 | Measure-Object).Count

    $m = [regex]::Match($text, '(?m)^#[^\S
]*@layer:[^\S
]*(\S+)')
    if (-not $m.Success) { Write-Fail "$($f.Name) ne déclare pas sa couche (« # @layer: floor » ou « # @layer: subject »)."; $bad++; continue }
    $layer[$name] = $m.Groups[1].Value

    $u = [regex]::Match($text, '(?m)^#[^\S
]*@uses:[^\S
]*([^
]*)$')
    if (-not $u.Success) { Write-Fail "$($f.Name) ne déclare pas « # @uses: » (vide est permis, absent ne l'est pas)."; $bad++; continue }
    $declaredUses[$name] = @($u.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $errors = $null; $tokens = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { Write-Fail "$($f.Name) ne se parse pas : $($errors[0].Message)"; $bad++; continue }
    foreach ($fn in $tree.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $defines[$fn.Name] = $name
    }
}
if ($bad) { exit 2 }

# --- What each piece REALLY uses, read from the tree --------------------------------------------------------
$realUses = @{}
foreach ($f in $pieces) {
    $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    $tokens = $null; $errors = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    $used = @{}
    foreach ($c in $tree.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $cmd = $c.GetCommandName()
        if ($cmd -and $defines.ContainsKey($cmd) -and $defines[$cmd] -ne $name) { $used[$defines[$cmd]] = $true }
    }
    $realUses[$name] = @($used.Keys | Sort-Object)
}

Write-Step 'Chaque morceau déclare ce qu''il utilise'
foreach ($name in ($realUses.Keys | Sort-Object)) {
    $missing = @($realUses[$name] | Where-Object { $declaredUses[$name] -notcontains $_ })
    $stale = @($declaredUses[$name] | Where-Object { $realUses[$name] -notcontains $_ })
    if ($missing.Count) { $bad++; Write-Fail ("{0}.ps1 utilise {1} sans le déclarer dans « @uses: »." -f $name, ($missing -join ', ')) }
    if ($stale.Count) { $bad++; Write-Fail ("{0}.ps1 déclare {1} dans « @uses: » et ne l'utilise pas." -f $name, ($stale -join ', ')) }
}
if (-not $bad) { Write-Ok ("$($pieces.Count) morceau(x) : ce qui est déclaré est exactement ce qui est appelé.") }

Write-Step 'Le socle n''appelle jamais vers le haut'
$up = @()
foreach ($name in ($layer.Keys | Sort-Object)) {
    if ($layer[$name] -ne 'floor') { continue }
    foreach ($u in $realUses[$name]) { if ($layer[$u] -ne 'floor') { $up += ('{0}.ps1 (socle) appelle {1}.ps1, qui n''en est pas' -f $name, $u) } }
}
if ($up.Count) { $bad++; Write-Fail 'Un morceau du socle appelle un sujet : la couche basse cesse alors d''être une couche.'; $up | ForEach-Object { Write-Detail $_ } }
else { Write-Ok ("Socle : $(@($layer.Keys | Where-Object { $layer[$_] -eq 'floor' }).Count) morceau(x), aucun appel vers le haut.") }

Write-Step 'Aucun cycle entre les morceaux'
# A depth-first walk; the first edge that comes back on the path IS the cycle, and it is named in full.
$state = @{}
$cycle = $null
function Test-Cycle {
    param([string]$Node, [System.Collections.ArrayList]$Path)
    if ($script:cycle) { return }
    $script:state[$Node] = 'open'
    [void]$Path.Add($Node)
    foreach ($next in $script:realUses[$Node]) {
        if (-not $script:realUses.ContainsKey($next)) { continue }
        if ($script:state[$next] -eq 'open') {
            $script:cycle = (@($Path) + $next) -join ' -> '
            return
        }
        if ($script:state[$next] -ne 'done') { Test-Cycle -Node $next -Path $Path }
        if ($script:cycle) { return }
    }
    $Path.RemoveAt($Path.Count - 1)
    $script:state[$Node] = 'done'
}
foreach ($name in ($realUses.Keys | Sort-Object)) {
    if ($state[$name] -ne 'done' -and -not $cycle) { Test-Cycle -Node $name -Path ([System.Collections.ArrayList]::new()) }
}
if ($cycle) { $bad++; Write-Fail "Un circuit : $cycle" ; Write-Info 'Un cycle ne casse rien à l''exécution ; il retire la possibilité de lire un morceau seul.' }
else { Write-Ok 'Le graphe des morceaux est acyclique.' }

Write-Step 'La taille des morceaux'
$biggest = 0
$tooBig = @()
foreach ($name in ($sizes.Keys | Sort-Object)) {
    if ($sizes[$name] -gt $biggest) { $biggest = $sizes[$name] }
    if ($sizes[$name] -gt $PIECE_CEILING) { $tooBig += ('{0}.ps1 : {1} lignes' -f $name, $sizes[$name]) }
}
if ($tooBig.Count) {
    $bad++
    Write-Fail "Plafond dépassé ($PIECE_CEILING lignes) : un morceau grossit au lieu d'être découpé."
    $tooBig | ForEach-Object { Write-Detail $_ }
} else {
    $facadeLines = (Get-Content -LiteralPath (Join-Path $libDir $facade) -Encoding UTF8 | Measure-Object).Count
    Write-Ok ("Le plus gros morceau à $biggest lignes (plafond $PIECE_CEILING) ; la façade common.ps1 en a encore $facadeLines.")
}

if ($Detail) {
    Write-Step 'Le graphe, tel qu''il est'
    foreach ($name in ($realUses.Keys | Sort-Object)) {
        Write-Detail ('{0,-14} [{1,-7}] {2,4} lignes -> {3}' -f $name, $layer[$name], $sizes[$name],
                      $(if ($realUses[$name].Count) { $realUses[$name] -join ', ' } else { 'rien' }))
    }
}

if ($bad) { exit 2 }
Write-Outcome -What 'La bibliothèque garde sa forme'
exit 0
