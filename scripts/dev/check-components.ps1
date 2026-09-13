# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    EVERY WRITE ON THE MACHINE BELONGS TO A PIECE OF THE INVENTORY, OR THIS CHECK FAILS. READ ONLY.

    Why it exists. On 13/09 deployment stopped because the service clone had been created without an answer to the
    situations of its life, and the same day's inventory found other pieces without one. A piece nobody lists is a
    piece nobody asks those questions about. doc/progress/implemented/components.md lists the pieces; this check
    makes sure no code writes on the machine without its writer being listed there.

    What is compared. Every call that writes on the machine -- a local account, a scheduled task, a registry value,
    an event source, a user right, a git declaration of the computer, an access rule -- is attributed to its
    enclosing function in lib/common.ps1, or to its file anywhere else. That function or file must appear in the
    section "Où chaque pièce s'écrit" of the inventory, and a name listed there must still write something.

    What it does NOT see: files written under var/ or ProgramData, and a write through a command it does not know.

    Exit codes: 0 = inventory and code agree; 2 = at least one gap.
#>
[CmdletBinding()]
param([switch] $Detail)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$inventoryRel  = 'doc/progress/implemented/components.md'
$inventoryPath = Join-Path $repoRoot $inventoryRel
$library       = 'apps/backend-pode/lib/common.ps1'
$newline       = [string][char]10
$writePatterns = @(
    'New-LocalUser|Set-LocalUser|Remove-LocalUser|Add-LocalGroupMember',
    'Register-ScheduledTask|Unregister-ScheduledTask|Set-ScheduledTask',
    'CreateEventSource|DeleteEventSource',
    'secedit([.]exe)?.*/configure',
    'safe[.]directory.*--(add|unset)|--(add|unset).*safe[.]directory',
    'New-ItemProperty|Set-ItemProperty|Remove-ItemProperty',
    'icacls([.]exe)?.*/(grant|deny|remove|reset|setowner)',
    'takeown'
)
$writePattern = '(' + ($writePatterns -join ')|(') + ')'

Write-Title (Get-Label 'check-components.titre')
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    Write-Fail (Get-Label 'check-components.inventaire-introuvable' $inventoryRel)
    Write-Outcome -What (Get-Label 'check-components.termine') -Failures 1
    exit 2
}

# --- The inventory's writers ------------------------------------------------------------
$listed = @()
$inside = $false
foreach ($line in ([IO.File]::ReadAllText($inventoryPath) -split $newline)) {
    $line = $line.TrimEnd([char]13)
    if ($line.StartsWith('## ')) { $inside = $line.Substring(3).Trim().StartsWith('Où chaque pièce'); continue }
    if (-not $inside -or -not $line.StartsWith('|')) { continue }
    $m = [regex]::Match($line, '^[|][ ]*`([^`]+)`')
    if ($m.Success) { $listed += $m.Groups[1].Value }
}

# --- The code's writers -----------------------------------------------------------------
$writers = @{}
$writes = 0
$files = @()
foreach ($top in @('apps', 'scripts')) {
    $files += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot $top) -Recurse -File -Filter '*.ps1' | Where-Object {
        $rel = $_.FullName.Substring($repoRoot.Length + 1).Replace([char]92, [char]47)
        $rel -notmatch '/(var|dist|node_modules)/' -and $rel -notlike 'scripts/dev/*'
    })
}
foreach ($file in $files) {
    $rel = $file.FullName.Substring($repoRoot.Length + 1).Replace([char]92, [char]47)
    $text = [IO.File]::ReadAllText($file.FullName)
    # Block comments are blanked line for line, so that a word in a comment writes nothing.
    $text = [regex]::Replace($text, '(?s)<#.*?#>', { param($m) [regex]::Replace($m.Value, '[^' + [char]10 + ']', '') })
    $owner = $null
    foreach ($line in ($text -split $newline)) {
        $definition = [regex]::Match($line, '^[ ]*function[ ]+([A-Za-z0-9-]+)')
        if ($definition.Success) { $owner = $definition.Groups[1].Value }
        if ($line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch $writePattern) { continue }
        $writes++
        $writer = if ($rel -eq $library -and $owner) { $owner } else { $rel }
        $writers[$writer] = $true
    }
}

$failures = 0
$absent = @($writers.Keys | Where-Object { $listed -notcontains $_ } | Sort-Object)
if ($absent.Count) {
    Write-Fail (Get-Label 'check-components.absent' $absent.Count ($absent -join ', '))
    $failures++
}
$ghosts = @($listed | Where-Object { -not $writers.ContainsKey($_) } | Sort-Object -Unique)
if ($ghosts.Count) {
    Write-Fail (Get-Label 'check-components.fantome' ($ghosts -join ', '))
    $failures++
}

Write-Info (Get-Label 'check-components.comptees' $writes $writers.Count)
if ($Detail) { foreach ($name in ($writers.Keys | Sort-Object)) { Write-Detail $name } }
if ($failures) { Write-Warn (Get-Label 'check-components.comment-faire' $inventoryRel) }
else { Write-Ok (Get-Label 'check-components.accord') }
Write-Outcome -What (Get-Label 'check-components.termine') -Failures $failures
if ($failures) { exit 2 }
