# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-author.ps1 -- every CODE file carries its author. READ ONLY.

    Intent: make the rule hold for a file added a month later. THE RULE (the owner's request, 01/09): every code
    file of this repository carries the "@author" line with the owner's name and address, AT THE TOP, before the
    rest.

    Usage: pwsh -File .\scripts\dev\check-author.ps1 (-Fix lays the line down). Exit codes: 0 = they all carry
    it; 2 = some are missing.

    WHY A CHECKER AND NOT A HABIT: a file added a month later will not have it, and nobody will see it. The check
    costs a second; rereading a hundred and thirty files by hand does not.

    The documents (.md) are not concerned: it is the README's "Auteur" section that carries the information, once
    and for all.
#>


#>
param([switch] $Fix)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$AUTEUR  = 'Florent HAZARD <f.hazard@sowapps.com>'
$MARQUE  = '@author'
$IGNORES = @('dist', 'var', 'local', 'node_modules', '.git', '.claude')

function Get-AuthorLine {
    param([string]$Extension)
    if ($Extension -in '.ps1', '.psd1', '.psm1', '.py') { return "# $MARQUE $AUTEUR" }
    if ($Extension -in '.cmd', '.bat')                  { return "REM $MARQUE $AUTEUR" }
    if ($Extension -eq '.vbs')                          { return "' $MARQUE $AUTEUR" }
    if ($Extension -eq '.html')                         { return "<!-- $MARQUE $AUTEUR -->" }
    if ($Extension -in '.js', '.css')                   { return "/* $MARQUE $AUTEUR */" }
    # PHP CARRIES THE SAME LINE AS THE REST, and it did not: four of the five .php files had no author at all,
    # because this verifier simply did not know the extension. A convention nobody checks is a convention that
    # holds only where someone happened to remember it.
    if ($Extension -eq '.php')                          { return "/* $MARQUE $AUTEUR */" }
    return $null
}

Write-Title 'Auteur'
Write-Step 'Chaque fichier de code porte son auteur'

$missing = @()
$added = 0
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($IGNORES | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $line = Get-AuthorLine -Extension $f.Extension.ToLowerInvariant()
    if (-not $line) { continue }

    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($null -eq $text) { $text = '' }
    if ($text.Contains($MARQUE)) { continue }

    if (-not $Fix) { $missing += $rel; continue }

    # WE READ FIRST, WE WRITE AFTERWARDS. Never both in the same expression: that is how one empties a file
    # without noticing.
    $lines = @($text -split "`r?`n")
    $head = if ($lines.Count) { $lines[0].Trim().ToLowerInvariant() } else { '' }
    $after = 0
    if ($head.StartsWith('<!doctype') -or $head.StartsWith('@echo') -or $head.StartsWith('#!')) { $after = 1 }
    # AND IN PHP THE LINE GOES AFTER "<?php", NEVER BEFORE. Placed before, it is written
    # straight into the HTTP response: the file stops being PHP and becomes text followed
    # by PHP. Done once, seen at once -- and exactly the kind of automatism that breaks in
    # silence when nobody looks at the output.
    if ($head.StartsWith('<?php')) { $after = 1 }
    $new = @()
    if ($after -gt 0) { $new += $lines[0] }
    $new += $line
    $new += $lines[$after..($lines.Count - 1)]
    Set-Content -LiteralPath $f.FullName -Value ($new -join [Environment]::NewLine) -Encoding UTF8
    $added++
}

if ($Fix) {
    Write-Ok "$added fichier(s) complète(s)."
    Write-Outcome -What 'Auteur'
    exit 0
}
if (-not $missing.Count) {
    Write-Ok 'Tous les fichiers de code portent leur auteur.'
    Write-Outcome -What 'Auteur'
    exit 0
}
Write-Fail ("{0} fichier(s) sans auteur :" -f $missing.Count)
foreach ($m in $missing) { Write-Detail ('- ' + $m) }
Write-Warn 'Poser la ligne manquante : -Fix'
Write-Outcome -What 'Auteur'
exit 2
