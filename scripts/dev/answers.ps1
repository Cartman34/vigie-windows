# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    WAS THIS ALREADY ASKED? Searches what the owner has already answered or settled, before a question is asked. READ ONLY.

    Why it exists. On 14/09 five questions were put to the owner; two had already been answered, one of them the day
    before. The answers lived in a conversation, and a conversation is gone after a compaction. notes/answers.md now keeps
    every answer; this script searches it together with the decisions, the target plan and the open subjects.

    How it matches. Every word given must appear on the line, accents and case ignored. A line of a table is one answer,
    a line of a document one statement: the file and line number are printed so the context can be opened.

    Exit codes: 0 = at least one match; 1 = nothing found.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string] $About)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

function ConvertTo-Plain {
    param([string]$Text)
    $decomposed = "$Text".ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    return (-join ($decomposed.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' }))
}

$words = @((ConvertTo-Plain $About) -split '\s+' | Where-Object { $_.Length -ge 3 })
$sources = @('notes/answers.md', 'doc/progress/decisions.md', 'notes/subjects.md')
$sources += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'doc/progress/targeting') -Filter '*.md' -File | Sort-Object Name |
              ForEach-Object { 'doc/progress/targeting/' + $_.Name })

Write-Title (Get-Label 'answers.titre' $About)
$found = 0
foreach ($rel in $sources) {
    $path = Join-Path $repoRoot $rel
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $number = 0
    foreach ($line in [IO.File]::ReadLines($path)) {
        $number++
        if (-not $words.Count) { break }
        $plain = ConvertTo-Plain $line
        if (@($words | Where-Object { -not $plain.Contains($_) }).Count) { continue }
        $found++
        $shown = if ($line.Length -gt 220) { $line.Substring(0, 220) + '…' } else { $line }
        Write-Info ('{0}:{1}' -f $rel, $number)
        Write-Detail $shown.Trim()
    }
}
if ($found) { Write-Ok (Get-Label 'answers.trouvees' $found) } else { Write-Warn (Get-Label 'answers.rien') }
if ($found) { exit 0 }
exit 1
