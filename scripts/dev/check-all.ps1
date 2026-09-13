# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    EVERY VERIFIER OF THE REPOSITORY, IN ONE COMMAND. READ ONLY.

    Why it exists. Before each delivery the verifiers of scripts/dev are run one by one, and the list grows: on 13/09
    it held ten, plus the probes check. A list typed from memory loses one; this script finds them by their name,
    check-*.ps1, so a new verifier is run the day it is added.

    What it shows. One line per verifier, and the full output of those that fail, so a green run stays short.
    -Probes adds scripts/check-probes.ps1 -All, which executes every probe: it is slower, and it is the
    validation required before a delivery that touches a probe (doc/en/agent-working/briefing.md).

    Exit codes: 0 = every verifier agrees; 2 = at least one failed.
#>
[CmdletBinding()]
param([switch] $Probes)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$pwsh = (Get-Process -Id $PID).Path
$runs = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'check-*.ps1' -File |
          Where-Object { $_.Name -ne 'check-all.ps1' } | Sort-Object Name |
          ForEach-Object { [pscustomobject]@{ Name = $_.BaseName; Path = $_.FullName; Arguments = @() } })
if ($Probes) {
    $runs += [pscustomobject]@{ Name = 'check-probes'; Path = (Join-Path (Join-Path $repoRoot 'scripts') 'check-probes.ps1'); Arguments = @('-All') }
}

Write-Title (Get-Label 'check-all.titre')
$failed = @()
foreach ($run in $runs) {
    $started = Get-Date
    $output = @(& $pwsh -NoProfile -File $run.Path @($run.Arguments) 2>&1)
    $code = $LASTEXITCODE
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    if ($code -eq 0) {
        Write-Ok (Get-Label 'check-all.accord' $run.Name $seconds)
    } else {
        Write-Fail (Get-Label 'check-all.echec' $run.Name $code $seconds)
        foreach ($line in $output) { if ("$line".Trim()) { Write-Detail "$line" } }
        $failed += $run.Name
    }
}

if ($failed.Count) { Write-Warn (Get-Label 'check-all.echecs' ($failed -join ', ')) }
Write-Outcome -What (Get-Label 'check-all.termine') -Failures $failed.Count
if ($failed.Count) { exit 2 }
exit 0
