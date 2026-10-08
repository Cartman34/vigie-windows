# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    SEARCH THE DECISIONS BEFORE DESIGNING.

    Intent: make searching cost TEN SECONDS. doc/progress/decisions.md is the project's source of truth -- "never
    to be lost". It runs to more than two thousand lines: nobody rereads it in full before every change, and that
    is exactly how one redoes what is already decided.

    Usage:
        pwsh -File scripts/dev/decisions.ps1              # every title
        pwsh -File scripts/dev/decisions.ps1 -About <words>
    The search ignores accents and case, so an unaccented word finds its accented spelling.

    On 29/08 I reinvented "where the code we deploy comes from" while D99 and the UpdateSource setting had been
    answering it for a long time; I filed a computer-wide setting inside every copy while D33 describes the
    configuration layers; I redefined a function that already existed. Three times the same defect: not looking.
#>




[CmdletBinding()]
param(
    # One or more words. A decision comes up if its TITLE or its TEXT holds them.
    [string] $About,

    # A decision's number: displays its whole text.
    [string] $Number,

    # Search the text, not only the titles (wider, noisier).
    [switch] $Full
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$file = Join-Path $repoRoot 'doc/progress/decisions.md'
if (-not (Test-Path -LiteralPath $file)) {
    Write-Fail (Get-Label 'decisions.fichier-introuvable' $file)
    exit 2
}

# Accents must not make a match fail: an unaccented word must find its accented spelling. We compare forms
# without diacritics, on both sides.
function ConvertTo-Plain {
    param([string]$Text)
    $d = "$Text".Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') { [void]$sb.Append($c) }
    }
    return $sb.ToString().ToLowerInvariant()
}

$lines = Get-Content -LiteralPath $file -Encoding UTF8
# A decision begins with "## Dnn - title" and runs until the next one.
$entries = @()
$current = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^#{2,3}\s+(D\d+[a-z]*)\s*(?:\(revu\))?\s*[—-]\s*(.+)$') {
        if ($current) { $entries += $current }
        $current = [pscustomobject]@{
            Id = $Matches[1]; Title = $Matches[2].Trim(); Line = $i + 1
            Body = New-Object Collections.Generic.List[string]
        }
    } elseif ($current) {
        $current.Body.Add($lines[$i])
    }
}
if ($current) { $entries += $current }

if ($Number) {
    $target = @($entries | Where-Object { $_.Id -ieq $Number.Trim() })
    if (-not $target.Count) {
        Write-Fail (Get-Label 'decisions.numero-inconnu' $Number)
        exit 2
    }
    foreach ($e in $target) {
        Write-Title ($e.Id + ' — ' + $e.Title)
        Write-Detail (Get-Label 'decisions.ligne' $e.Line)
        $e.Body | ForEach-Object { Write-Host $_ }
    }
    exit 0
}

$retenues = $entries
if ($About) {
    $mots = @(ConvertTo-Plain $About) -split '\s+' | Where-Object { $_ }
    $retenues = @($entries | Where-Object {
        $title = ConvertTo-Plain $_.Title
        $Text = if ($Full) { ConvertTo-Plain ($_.Body -join ' ') } else { '' }
        $tous = $true
        foreach ($m in $mots) { if (($title -notlike ('*' + $m + '*')) -and ($Text -notlike ('*' + $m + '*'))) { $tous = $false; break } }
        $tous
    })
}

Write-Title (Get-Label 'decisions.titre')
foreach ($e in $retenues) {
    Write-Host ('{0,-6} {1}' -f $e.Id, $e.Title)
}
Write-Info (Get-Label 'decisions.sur-total' $retenues.Count $entries.Count)
if ($About -and -not $retenues.Count) {
    Write-Detail (Get-Label 'decisions.rien-trouve-full')
}
exit 0
