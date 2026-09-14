# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    EVERY DOCUMENT IS WRITTEN IN THE LANGUAGE OF ITS FOLDER, OR THIS CHECK FAILS. RATCHET. READ ONLY.

    Why it exists. On 10/09, 845 lines of French were found under doc/en/, there for months, and D120 wrote that no tool
    compared a file's language with its folder's: "a rule hoped for, not held". The rule itself lives in
    doc/en/developing/conventions.md, section "Language".

    How a language is read. Code blocks and inline code are set aside, then the common short words of each language are
    counted. On 13/09 every document of the repository fell clearly on one side, the smaller count at most a tenth of the
    larger; a document with fewer than twenty such words is not judged.

    The ratchet. The documents still in French under doc/en/ are listed below (seven on 13/09, none since 14/09). A new one is refused; a listed one
    that has been translated, moved or removed must leave the list, so the list only goes down.

    What it does NOT see: a paragraph in the wrong language inside a document of the right one, and the vocabulary --
    the glossary's words are not structured enough to be compared mechanically.

    Exit codes: 0 = every document agrees with its folder; 2 = at least one gap.
#>
[CmdletBinding()]
param([switch] $Detail)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

# THE DOCUMENTS STILL IN FRENCH UNDER doc/en/. Seven on 13/09, all translated on 14/09. This list only goes down.
$frenchUnderEnglish = @()
# The language each place requires, the first matching prefix winning.
$places = @(
    @{ Prefix = 'doc/en/';      Language = 'en' },
    @{ Prefix = 'doc/fr/';      Language = 'fr' },
    @{ Prefix = 'doc/progress/'; Language = 'fr' },
    @{ Prefix = 'doc/README.md'; Language = 'en' },
    @{ Prefix = 'notes/';       Language = 'fr' },
    @{ Prefix = 'README.md';    Language = 'en' },
    @{ Prefix = 'README.fr.md'; Language = 'fr' },
    @{ Prefix = 'CHANGELOG.md'; Language = 'fr' }
)
$frenchWords  = @('le', 'la', 'les', 'des', 'une', 'est', 'pas', 'pour', 'qui', 'dans', 'du', 'et', 'ce', 'que', 'sur', 'avec', 'sont', 'au', 'aux', 'il', 'elle', 'ne', 'se')
$englishWords = @('the', 'and', 'is', 'of', 'to', 'in', 'not', 'that', 'for', 'with', 'are', 'it', 'this', 'be', 'by', 'on', 'from', 'which', 'when', 'what')
$minimumWords = 20

function Get-DocumentLanguage {
    param([Parameter(Mandatory)][string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    $text = [regex]::Replace($text, '(?s)```.*?```', ' ')
    $text = [regex]::Replace($text, '`[^`]*`', ' ')
    $french = 0
    $english = 0
    foreach ($m in [regex]::Matches($text.ToLowerInvariant(), '\p{L}+')) {
        if ($frenchWords -contains $m.Value) { $french++ } elseif ($englishWords -contains $m.Value) { $english++ }
    }
    if ($french + $english -lt $minimumWords) { return $null }
    if ($french -gt $english) { return 'fr' }
    return 'en'
}

Write-Title (Get-Label 'check-language.titre')
$excluded = '/(var|dist|node_modules|local|\.git|\.claude)/'
$documents = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.md' | ForEach-Object {
    $_.FullName.Substring($repoRoot.Length + 1).Replace([char]92, [char]47)
} | Where-Object { ('/' + $_) -notmatch $excluded } | Sort-Object)

$failures = 0
$read = 0
$unjudged = 0
foreach ($rel in $documents) {
    $place = $places | Where-Object { $rel.StartsWith($_.Prefix) } | Select-Object -First 1
    if (-not $place) { continue }
    $read++
    $language = Get-DocumentLanguage -Path (Join-Path $repoRoot $rel)
    if (-not $language) { $unjudged++; continue }
    if ($Detail) { Write-Detail ('{0}  {1}' -f $language, $rel) }
    if ($language -eq $place.Language) { continue }
    if ($place.Language -eq 'en' -and $language -eq 'fr' -and $frenchUnderEnglish -contains $rel) { continue }
    Write-Fail (Get-Label 'check-language.langue-du-dossier' $rel $language $place.Language)
    $failures++
}
foreach ($rel in $frenchUnderEnglish) {
    $path = Join-Path $repoRoot $rel
    if ((Test-Path -LiteralPath $path) -and (Get-DocumentLanguage -Path $path) -eq 'fr') { continue }
    Write-Fail (Get-Label 'check-language.liste-a-baisser' $rel)
    $failures++
}

Write-Info (Get-Label 'check-language.comptes' $read $unjudged $frenchUnderEnglish.Count)
if ($failures) { Write-Warn (Get-Label 'check-language.comment-faire') }
else { Write-Ok (Get-Label 'check-language.accord') }
Write-Outcome -What (Get-Label 'check-language.termine') -Failures $failures
if ($failures) { exit 2 }
exit 0
