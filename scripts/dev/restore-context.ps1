# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    RESTORE-CONTEXT: PUT THE RULES BACK IN PLACE AFTER A CONTEXT COMPACTION.

    Intent: make rereading a command rather than a duty. THE PROBLEM. When the agent's context is compacted, all
    that is left is a SUMMARY. The disciplines, the decisions and the design documents are no longer there. The
    agent then takes the work up again with its memories as its only source -- and a memory is not a
    verification. Observed on 31/08: I announced that a script was no longer called by anybody, and deleted it
    accordingly, while a button of the interface was still calling it. The sentence came from the summary, not
    from the repository.

    Usage: pwsh -File scripts/dev/restore-context.ps1 (-Court for a shorter pass). Exit codes: 0 = everything is
    there; 1 = a reference document is missing.

    THE PRINCIPLE. We do not count on the agent's vigilance to remember to reread: this script puts everything
    back under its eyes in one command. The entry point that refers to it is doc/en/agent-working/briefing.md,
    valid for any agent; a file one of them loads automatically (CLAUDE.md for Claude Code) is only an OPTIONAL
    shortcut to it, and carries no rule of its own.

    WHAT IT DOES. It invents nothing and copies nothing: it REREADS the repository's documents and displays
    them. The day a discipline changes, this script says the new one, without anybody touching it. If a document
    has gone, it says so and exits in error -- a resumption point referring to an absent file is worse than no
    point at all.
#>
[CmdletBinding()]
param(
    # -Court: the map of the documents and the state of the repository, without the text of the disciplines. For
    # a resumption inside a session, when the rules are still fresh.
    [switch] $Court
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

Write-Title (Get-Label 'restore-context.titre')

<#
    THE MAP OF THE DOCUMENTS. Each one's role is written here and NOWHERE ELSE in this form: these are sentences
    of orientation, not a duplicate of the content. The content stays in the files -- which are displayed
    further down.

    The label's key is WRITTEN, not computed: check-labels reads the calls cold and can only check what it sees.
    A key stored in a variable passes the check without being checked -- and that is exactly where the missing
    label hides.
#>
$documents = @(
    @{ path = 'doc/en/agent-working/briefing.md';     role = (Get-Label 'restore-context.role-briefing') }
    @{ path = 'doc/en/agent-working/disciplines.md';  role = (Get-Label 'restore-context.role-disciplines') }
    @{ path = 'doc/progress/decisions.md';            role = (Get-Label 'restore-context.role-decisions') }
    @{ path = 'doc/progress/targeting';               role = (Get-Label 'restore-context.role-targeting') }
    @{ path = 'doc/progress/implemented';             role = (Get-Label 'restore-context.role-implemented') }
)

$missing = 0
Write-Step (Get-Label 'restore-context.etape-documents')
foreach ($d in $documents) {
    $complet = Join-Path $repoRoot $d.path
    if (Test-Path -LiteralPath $complet) {
        Write-Detail ($d.path + ' — ' + $d.role)
    } else {
        Write-Fail (Get-Label 'restore-context.document-introuvable' $d.path)
        $missing++
    }
}

<#
    THE DISCIPLINES, IN FULL.

    Summarising them would be losing some of them, and the summary is precisely what failed. We read them as
    they are written.
#>
if (-not $Court) {
    $disciplines = Join-Path $repoRoot 'doc/en/agent-working/disciplines.md'
    if (Test-Path -LiteralPath $disciplines) {
        Write-Step (Get-Label 'restore-context.etape-disciplines')
        Get-Content -LiteralPath $disciplines -Encoding UTF8 | ForEach-Object { Write-Host $_ }
    }
}

<#
    WHERE THE REPOSITORY STANDS. The summary says what has been done; git says what IS. When the two diverge, git
    is the one that is right.
#>
Write-Step (Get-Label 'restore-context.etape-depot')
$branche = Invoke-Git -Path $repoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
Write-Detail (Get-Label 'restore-context.branche' "$branche".Trim())
foreach ($line in @(Invoke-Git -Path $repoRoot -Arguments @('log', '--oneline', '-5'))) {
    if ("$line".Trim()) { Write-Detail "$line" }
}
$enCours = @(Invoke-Git -Path $repoRoot -Arguments @('status', '--short') | Where-Object { "$_".Trim() })
if ($enCours.Count) {
    Write-Warn (Get-Label 'restore-context.travail-en-cours' $enCours.Count)
    foreach ($line in $enCours) { Write-Detail "$line" }
} else {
    Write-Detail (Get-Label 'restore-context.rien-en-cours')
}

<#
    WHAT WE DO NOT CONCLUDE WITHOUT A PROOF.

    One single rule is recalled here, because it is the one compaction makes us break: the summary asserts states
    of the repository ("no longer used", "already fixed", "proven"), and those assertions grow old. The checkers
    do not grow old.

#>
Write-Step (Get-Label 'restore-context.etape-preuve')
Write-Detail (Get-Label 'restore-context.preuve-reachable')
Write-Detail (Get-Label 'restore-context.preuve-decisions')
Write-Detail (Get-Label 'restore-context.preuve-verificateurs')

if ($missing) {
    Write-Fail (Get-Label 'restore-context.documents-manquants' $missing)
    exit 1
}
Write-Ok (Get-Label 'restore-context.pret')
exit 0
