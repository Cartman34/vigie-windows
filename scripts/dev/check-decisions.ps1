# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    A DECISION WITHOUT ITS MEASUREMENT IS AN OPINION.

    Asked by the owner on 10/09: "everything must be proven, above all decisions -- for
    those it is mandatory". A decision settled on figures deposits those figures in
    notes/proofs/ and links to them; decisions.md keeps the what and the why.

    A RATCHET, like the ones in check-naming: 124 of the 125 existing entries carry no
    proof, and rewriting history is not on the table -- most of them were settled before
    the rule existed, and inventing a measurement after the fact would be worse than
    admitting the gap. So the count of unproven decisions can only go DOWN, which makes
    every NEW decision mandatory-proof: the ceiling has no room left.

    An old entry gains its proof the day someone passes by it, never in a dedicated
    campaign -- the same discipline as the other ratchets.
#>
[CmdletBinding()]
param([switch] $Detail)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

# THE CEILING. It goes down, never up.
$UNPROVEN_CEILING = 124

$file = Join-Path $repoRoot 'doc/progress/decisions.md'
if (-not (Test-Path -LiteralPath $file)) {
    Write-Title 'Décisions'
    Write-Fail (Get-Label 'check-decisions.fichier-introuvable' $file)
    exit 1
}

$proofDir = Join-Path $repoRoot 'notes/proofs'

# --- Every entry, and what it carries -----------------------------------------------------
$entries = @()
$current = $null
$body = New-Object System.Text.StringBuilder
foreach ($line in (Get-Content -LiteralPath $file -Encoding UTF8)) {
    if ($line -match '^#{2,3}\s+(D\d+[a-z]*)\b') {
        if ($current) { $entries += [pscustomobject]@{ Id = $current; Body = $body.ToString() } }
        $current = $Matches[1]
        $body = New-Object System.Text.StringBuilder
    } elseif ($current) {
        $null = $body.AppendLine($line)
    }
}
if ($current) { $entries += [pscustomobject]@{ Id = $current; Body = $body.ToString() } }

# --- Proven? And does the proof actually exist? -------------------------------------------
#
# CITING A MISSING PROOF IS WORSE THAN CITING NONE: it lends the appearance of rigour to a
# claim nothing supports.
$unproven = @()
$broken = @()
foreach ($entry in $entries) {
    $names = @([regex]::Matches($entry.Body, 'notes/proofs/([A-Za-z0-9._-]+\.md)') |
               ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if (-not $names.Count) { $unproven += $entry.Id; continue }
    foreach ($name in $names) {
        if (-not (Test-Path -LiteralPath (Join-Path $proofDir $name))) {
            $broken += ('{0} -> {1}' -f $entry.Id, $name)
        }
    }
}

Write-Title 'Décisions'
Write-Info (Get-Label 'check-decisions.comptees' $entries.Count ($entries.Count - $unproven.Count))

$failed = $false

if ($broken.Count) {
    $failed = $true
    Write-Fail (Get-Label 'check-decisions.preuve-absente' $broken.Count)
    foreach ($one in $broken) { Write-Detail $one }
}

Write-Info (Get-Label 'check-decisions.sans-preuve-plafond' $unproven.Count $UNPROVEN_CEILING)
if ($unproven.Count -gt $UNPROVEN_CEILING) {
    $failed = $true
    Write-Fail (Get-Label 'check-decisions.au-dessus' ($unproven.Count - $UNPROVEN_CEILING))
    Write-Warn (Get-Label 'check-decisions.comment-faire')
    if ($Detail) { foreach ($id in $unproven) { Write-Detail $id } }
} elseif ($unproven.Count -lt $UNPROVEN_CEILING) {
    Write-Ok (Get-Label 'check-decisions.de-moins' ($UNPROVEN_CEILING - $unproven.Count))
} else {
    Write-Ok (Get-Label 'check-decisions.plafond-tenu')
}

# THE VERDICT USES THE SAME BOX AS THE OTHER CHECKS: a conclusion that does not look like
# the other seven gets hunted for instead of read.
Write-Outcome -What 'Décisions prouvées' -Failures $(if ($failed) { 1 } else { 0 })
if ($failed) { exit 1 }
