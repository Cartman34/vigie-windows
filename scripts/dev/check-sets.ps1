# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-sets.ps1 - "ALL" IS ASKED FOR, NEVER ASSUMED. READ ONLY, NOTHING IS EXECUTED.

    WHY THIS VERIFIER EXISTS. On 06/10 a call passed a package list under a parameter name the action did not read --
    `pkgs` where it expected `ids`. The list arrived empty, an empty list meant "the whole manager", and winget
    received `upgrade --all`: SIXTEEN programs installed instead of one, among them the owner's terminal, closed with
    the work running inside it, and WSL, which he had kept for himself. Nothing threw. Every link did what it was
    asked; the defect was that an ABSENCE was read as the widest possible permission.

    The convention existed -- `scripts/check-probes.ps1 -All` has worked that way from the start -- and was written
    nowhere, which is exactly why it was broken. It is now in `doc/en/developing/conventions.md` and arbitrated by
    **D131**; this verifier keeps it from depending on anyone's memory.

    WHAT IT DOES. Over every function that takes a set and acts on it, it checks two things:
      1. the function declares a `[switch]$All` -- the one way to say "the whole of it" ;
      2. it refuses when nothing is designated: somewhere in its body, the empty case returns instead of going on.

    WHAT IT CANNOT DO. It does not follow the logic: a function could declare the switch, return on empty, and still
    be wrong further down. What it guarantees is that the question was asked and answered in the code.

    THE LIST IS DECLARED, NOT GUESSED. A function acts on a set when nobody can tell from its name alone; guessing
    would either miss the dangerous ones or flood the output. Every entry added here is a gesture that, done to
    everything, costs something -- installing, deleting, stopping, resetting.
#>
param([switch]$Detail)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
Write-Title (Get-Label 'check-sets.titre')

# THE FUNCTIONS THAT ACT ON A SET, each with the parameter that designates the subjects.
$watched = @(
    @{ Function = 'Start-PkgJob';      Subject = 'Pkgs';  Where = 'apps/backend-pode/lib/common.ps1' }
    @{ Function = 'Invoke-PkgUpgrade'; Subject = 'Pkgs';  Where = 'apps/backend-pode/lib/common.ps1' }
)

$missingSwitch = @()
$missingRefusal = @()
$checked = 0

foreach ($entry in $watched) {
    $path = Join-Path $repoRoot $entry.Where
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count) { continue }   # check-powershell owns parse errors.

    $fn = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $_.Name -eq $entry.Function })
    if (-not $fn.Count) { continue }
    $checked++
    $body = "$($fn[0].Extent.Text)"

    if ($body -notmatch '\[switch\]\s*\$All\b') {
        $missingSwitch += [pscustomobject]@{ Name = $entry.Function; File = $entry.Where }
    }
    <#
        THE REFUSAL, read as a shape and not as a meaning: the body names its subject, tests that there is none, and
        leaves. A function that goes on without ever testing it has no empty case at all -- which is the defect.
    #>
    $subject = [regex]::Escape('$' + $entry.Subject)
    $hasEmptyTest = ($body -match ('-not\s+\$' + [regex]::Escape($entry.Subject))) -or
                    ($body -match ('(?s)' + $subject + '[^\r\n]{0,80}Count')) -or
                    ($body -match '-not\s+\$choisis\.Count') -or
                    ($body -match '-not\s+\$liste\.Count')
    if (-not ($hasEmptyTest -and $body -match '(?m)^\s*(return|throw)\b')) {
        $missingRefusal += [pscustomobject]@{ Name = $entry.Function; File = $entry.Where }
    }
}

Write-Info (Get-Label 'check-sets.comptes' $checked $watched.Count)
$failed = $false
if ($missingSwitch.Count) {
    $failed = $true
    Write-Fail (Get-Label 'check-sets.sans-commutateur' $missingSwitch.Count)
    foreach ($row in $missingSwitch) { Write-Detail (Get-Label 'check-sets.ligne' $row.Name $row.File) }
}
if ($missingRefusal.Count) {
    $failed = $true
    Write-Fail (Get-Label 'check-sets.sans-refus' $missingRefusal.Count)
    foreach ($row in $missingRefusal) { Write-Detail (Get-Label 'check-sets.ligne' $row.Name $row.File) }
}
if ($failed) {
    Write-Warn (Get-Label 'check-sets.comment-faire')
    exit 2
}
Write-Ok (Get-Label 'check-sets.tout-se-demande')
exit 0
