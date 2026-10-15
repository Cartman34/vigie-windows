# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    RENAME A FILE AND CARRY EVERY REFERENCE WITH IT, IN ONE COMMAND.

    Intent: make a rename a gesture one runs, not a hunt one conducts. On 15/10, renaming two verifiers touched
    SEVEN files -- the orchestrator's table, three documents, a measurement note, two verifiers naming each other
    -- and one of those rewrites made a dated record say something false. The owner's rule, that day: avoid
    having too many references, and have a script that does the operation rather than doing it by hand.

    Usage:
      pwsh -File .\scripts\dev\rename-file.ps1 -From scripts/dev/a.ps1 -To scripts/dev/b.ps1
      pwsh -File .\scripts\dev\rename-file.ps1 -From a.ps1 -To b.ps1 -DryRun     # says what it WOULD do
    Exit codes: 0 = renamed; 2 = refused before touching anything.

    WHAT IT DOES: `git mv`, then it rewrites every tracked text file that names the old file -- by its path and
    by its file name -- and it SAYS which ones, with the count. The BARE name, without its extension, is rewritten
    only on -BareName: a base name can be an ordinary word of the language, and rewriting it translated French
    prose the first time it was used. What it refuses: a destination that already exists,
    a source git does not track, a name git would consider the same file (Windows ignores case).

    WHAT IT DOES NOT DO, and that is deliberate: it does not touch the dated records of notes/evidence/. A record
    says what was measured ON ITS DAY, under the name of that day; rewriting it makes it lie -- which is exactly
    what happened on 15/10. It names them instead, so they can be read and corrected by hand if they must be.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $From,
    [Parameter(Mandatory)][string] $To,
    # Say what would be done, change nothing.
    [switch] $DryRun,
    <#
        ALSO REWRITE THE BARE NAME -- the file name without its extension -- which is OFF by default.

        A base name can be an ordinary word of the language. Renaming the report page with this on rewrote
        twenty-two files and translated that word wherever it stood in a sentence -- in the prose of the
        documentation, and inside messages the application displays. A file name is a technical token; a word of a
        sentence is not, and nothing tells them apart but the eye.

        Ask for it when the name is a token nobody would write as a word -- `check-file-coherence`, `vigie-fetch`
        -- and read the list it prints before saying yes.
    #>
    [switch] $BareName
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

Write-Title 'Renommage'

$fromRel = $From.Replace([char]92, [char]47).TrimStart('.', '/')
$toRel   = $To.Replace([char]92, [char]47).TrimStart('.', '/')
$fromFull = Join-Path $repoRoot $fromRel
$toFull   = Join-Path $repoRoot $toRel

if (-not (Test-Path -LiteralPath $fromFull -PathType Leaf)) { Write-Fail "Source introuvable : $fromRel"; exit 2 }
if ($fromRel -eq $toRel) { Write-Fail 'La source et la destination sont le même chemin.'; exit 2 }
if ((Test-Path -LiteralPath $toFull) -and ($fromRel.ToLowerInvariant() -ne $toRel.ToLowerInvariant())) {
    Write-Fail "La destination existe déjà : $toRel"; exit 2
}
$tracked = @(& git -C $repoRoot ls-files -- $fromRel)
if (-not $tracked.Count) { Write-Fail "git ne suit pas ce fichier : $fromRel"; exit 2 }

$fromName = Split-Path $fromRel -Leaf
$toName   = Split-Path $toRel -Leaf
$fromBase = [IO.Path]::GetFileNameWithoutExtension($fromName)
$toBase   = [IO.Path]::GetFileNameWithoutExtension($toName)

# WHO NAMES IT. Only what git tracks, and only text: a binary is not rewritten, and what is not versioned is not
# a reference of the project.
Write-Step 'Ce qui le désigne'
$named = @()
$needles = @($fromRel, $fromName)
if ($BareName) { $needles += $fromBase }
foreach ($rel in @(& git -C $repoRoot grep -l -F @($needles | ForEach-Object { '-e'; $_ }) -- . 2>$null)) {
    $clean = "$rel".Trim()
    if (-not $clean -or $clean -eq $fromRel) { continue }
    $named += $clean.Replace([char]92, [char]47)
}
$records = @($named | Where-Object { $_ -like 'notes/evidence/*' })
$toRewrite = @($named | Where-Object { $_ -notlike 'notes/evidence/*' })

foreach ($rel in $toRewrite) { Write-Detail $rel }
if (-not $toRewrite.Count) { Write-Detail 'Personne.' }
if ($records.Count) {
    Write-Warn "$($records.Count) relevé(s) daté(s) ne sont PAS réécrits : ils disent ce qui a été mesuré ce jour-là."
    foreach ($rel in $records) { Write-Detail $rel }
}

if ($DryRun) {
    Write-Info "Essai : rien n'a été touché. $($toRewrite.Count) fichier(s) seraient repris."
    Write-Outcome -What 'Renommage simulé'
    exit 0
}

Write-Step 'Le renommage'
$null = & git -C $repoRoot mv -- $fromRel $toRel
if ($LASTEXITCODE -ne 0) { Write-Fail "git mv a refusé (code $LASTEXITCODE)."; exit 2 }
Write-Ok "$fromRel -> $toRel"

Write-Step 'Les références'
$changed = 0
foreach ($rel in $toRewrite) {
    $full = Join-Path $repoRoot $rel
    # THE BYTES, NOT THE TEXT. `Get-Content -Raw` strips the byte-order mark before anyone can test for it, so
    # the first version of this script rewrote every .ps1 WITHOUT its mark -- which this repository requires, and
    # which check-encoding refuses. Caught by renaming a file and renaming it back: the tree did not come back
    # clean. A rename must be reversible to the byte.
    $bytes = [IO.File]::ReadAllBytes($full)
    if (-not $bytes.Length) { continue }
    $hasMark = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [Text.Encoding]::UTF8.GetString($bytes, $(if ($hasMark) { 3 } else { 0 }), $bytes.Length - $(if ($hasMark) { 3 } else { 0 }))
    # From the most precise to the least: the full path, then the file name, then the bare name. In that order a
    # path is never half-rewritten by the pass that follows.
    $new = $text.Replace($fromRel, $toRel).Replace($fromName, $toName)
    if ($BareName) { $new = $new.Replace($fromBase, $toBase) }
    if ($new -eq $text) { continue }
    $tmp = "$full.tmp"
    [IO.File]::WriteAllText($tmp, $new, [Text.UTF8Encoding]::new($hasMark))
    Move-Item -LiteralPath $tmp -Destination $full -Force
    $changed++
    Write-Detail $rel
}
Write-Ok "$changed fichier(s) repris."

Write-Info 'À lancer ensuite : pwsh -File scripts/dev/check-all.ps1 -All'
Write-Outcome -What 'Renommage fait'
exit 0
