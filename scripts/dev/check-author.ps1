# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-author.ps1 - Chaque fichier de CODE porte son auteur. LECTURE SEULE.

    LA REGLE (demande utilisateur, 01/09) : tout fichier de code de ce depot porte la
    ligne « @author » avec le nom et l'adresse du proprietaire, EN TETE, avant le reste.

    POURQUOI UN VERIFICATEUR ET PAS UNE HABITUDE : un fichier ajoute un mois plus tard ne
    l'aura pas, et personne ne le verra. Le controle coute une seconde ; relire cent
    trente fichiers a la main, non.

    Les documents (.md) ne sont pas concernes : c'est la section « Auteur » du README qui
    porte l'information, une fois pour toutes.

    Usage :
      pwsh -File .\scripts\dev\check-author.ps1
      pwsh -File .\scripts\dev\check-author.ps1 -Fix

    Codes de retour : 0 = tous la portent ; 2 = il en manque.
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

    # ON LIT D'ABORD, ON ECRIT ENSUITE. Jamais les deux dans la meme expression : c'est
    # ainsi qu'on vide un fichier sans s'en apercevoir.
    $lines = @($text -split "`r?`n")
    $head = if ($lines.Count) { $lines[0].Trim().ToLowerInvariant() } else { '' }
    $after = 0
    if ($head.StartsWith('<!doctype') -or $head.StartsWith('@echo') -or $head.StartsWith('#!')) { $after = 1 }
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
