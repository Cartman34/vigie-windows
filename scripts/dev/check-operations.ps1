# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    THE OPERATIONS INVENTORY TELLS THE TRUTH, OR THIS CHECK FAILS. READ ONLY.

    Why it exists. On 12/09 a Windows Update installation announced itself finished the moment
    it started: four long operations had been launched outside the shared protocol for seventeen
    days, and every search for "where does this operation happen" started from the code, by
    groping. doc/progress/implemented/operations.md lists every operation; this check keeps it
    true in both directions, as doc/progress/targeting/operations.md requires in its section
    "L'inventaire".

    What is compared, code against inventory:
      1. actions    -- every actions/*.action.ps1, and the launch function its row names;
      2. workers    -- every workers/*.worker.ps1;
      3. API writes -- every POST route of server.ps1;
      4. timers     -- every Add-PodeTimer of server.ps1, from code to inventory only;
      5. launches   -- every call to a detached launch function, attributed to its action, its
                       enclosing function or its file, which the inventory must name;
      6. processes  -- every raw process creation in the server app sits inside a launch function
                       listed by the inventory;
      7. scripts    -- every scripts/*.ps1, .cmd and .vbs, verifiers excepted;
      8. protocol   -- no detached launch outside Start-Operation, except in the internal pass Get-State;
      9. long rows  -- every long action's row declares the shared protocol, server-restart excepted.
    The two exceptions are the questions still open in S14.

    What it does NOT see: the client app's timers are anonymous Windows Forms timers that nothing
    names, so their rows are kept by review only. A launch written at the top level of a file,
    after a function, is attributed to that function: no file of the repository does it today.

    Exit codes: 0 = inventory and code agree; 2 = at least one gap.
#>
[CmdletBinding()]
param([switch] $Detail)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$inventoryPath   = Join-Path $repoRoot 'doc/progress/implemented/operations.md'
$backend         = Join-Path $repoRoot 'apps/backend-pode'
$launchFunctions = @('Start-Operation', 'Start-DetachedAction', 'Start-PkgJob', 'Start-ServerRelauncher')
# Verifiers are not operations of the product: they read the repository and run nothing on the machine.
$scriptsNotOperations = @('check-probes.ps1')
# THE PROTOCOL, AS FAR AS THE CODE SHOWS IT (doc/progress/targeting/operations.md). Each exception is a
# question still open in S14, and disappears with its answer.
$detachedAllowedIn  = @('Get-State')
$pendingArbitration = @('server-restart')
$newline = [string][char]10

Write-Title (Get-Label 'check-operations.titre')
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    Write-Fail (Get-Label 'check-operations.inventaire-introuvable' $inventoryPath)
    Write-Outcome -What (Get-Label 'check-operations.termine') -Failures 1
    exit 2
}
$inventory = [IO.File]::ReadAllText($inventoryPath)

# --- Reading the inventory ----------------------------------------------------------------

function Get-InventorySection {
    param([Parameter(Mandatory)][string]$Title)
    $inside = $false
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($inventory -split $newline)) {
        $line = $line.TrimEnd([char]13)
        if ($line.StartsWith('## ')) { $inside = $line.Substring(3).Trim().StartsWith($Title); continue }
        if ($inside) { $out.Add($line) }
    }
    return $out
}

# One object per table row, so that a table of one row is not unrolled into its cells.
function Get-TableRows {
    param([AllowEmptyCollection()][string[]]$Lines = @())
    foreach ($line in $Lines) {
        if (-not $line.StartsWith('|')) { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        [pscustomobject]@{ Cells = $cells }
    }
}

function Get-Backticked {
    param([string]$Cell)
    $m = [regex]::Match("$Cell", '^`([^`]+)`')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Block comments are blanked line for line, so that line numbers still point at the source.
function Get-CodeLines {
    param([Parameter(Mandatory)][string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    $text = [regex]::Replace($text, '(?s)<#.*?#>', { param($m) [regex]::Replace($m.Value, '[^' + [char]10 + ']', '') })
    return ($text -split $newline)
}

$failures = 0
function Compare-Sets {
    param([string]$Category, [string[]]$InCode = @(), [string[]]$InInventory = @(), [switch]$CodeToInventoryOnly)
    $absent = @($InCode | Where-Object { $InInventory -notcontains $_ } | Sort-Object -Unique)
    if ($absent.Count) {
        Write-Fail (Get-Label 'check-operations.absent-inventaire' $Category ($absent -join ', '))
        $script:failures++
    }
    if ($CodeToInventoryOnly) { return }
    $ghosts = @($InInventory | Where-Object { $InCode -notcontains $_ } | Sort-Object -Unique)
    if ($ghosts.Count) {
        Write-Fail (Get-Label 'check-operations.fantome' $Category ($ghosts -join ', '))
        $script:failures++
    }
}

# --- 1. Actions ---------------------------------------------------------------------------

$codeActions = @(Get-ChildItem -LiteralPath (Join-Path $backend 'actions') -Filter '*.action.ps1' -File |
                 ForEach-Object { $_.Name.Substring(0, $_.Name.Length - '.action.ps1'.Length) })
$actionRows = @{}
foreach ($row in (Get-TableRows -Lines (Get-InventorySection 'Les actions'))) {
    $name = Get-Backticked $row.Cells[0]
    if ($name) { $actionRows[$name] = $row }
}
Compare-Sets -Category (Get-Label 'check-operations.categorie-actions') -InCode $codeActions -InInventory @($actionRows.Keys)

# --- 2. Workers ---------------------------------------------------------------------------

$codeWorkers = @(Get-ChildItem -LiteralPath (Join-Path $backend 'workers') -Filter '*.worker.ps1' -File | ForEach-Object Name)
$inventoryWorkers = @([regex]::Matches($inventory, 'workers/([A-Za-z0-9-]+[.]worker[.]ps1)') |
                      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Compare-Sets -Category (Get-Label 'check-operations.categorie-workers') -InCode $codeWorkers -InInventory $inventoryWorkers

# --- 3. API writes, 4. timers -------------------------------------------------------------

$serverText = [IO.File]::ReadAllText((Join-Path $backend 'server.ps1'))
$codeRoutes = @([regex]::Matches($serverText, 'Add-PodeRoute[ ]+-Method[ ]+Post[ ]+-Path[ ]+"[$]base(/[^"]+)"') |
                ForEach-Object { 'POST ' + $_.Groups[1].Value })
$inventoryRoutes = @(foreach ($row in (Get-TableRows -Lines (Get-InventorySection "Les écritures par l'API"))) {
    $name = Get-Backticked $row.Cells[0]
    if ($name) { $name }
})
Compare-Sets -Category (Get-Label 'check-operations.categorie-api') -InCode $codeRoutes -InInventory $inventoryRoutes

$codeTimers = @([regex]::Matches($serverText, "Add-PodeTimer[ ]+-Name[ ]+'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$inventoryTimers = @($codeTimers | Where-Object { $inventory.Contains('`' + $_ + '`') })
Compare-Sets -Category (Get-Label 'check-operations.categorie-minuteurs') -InCode $codeTimers -InInventory $inventoryTimers -CodeToInventoryOnly

# --- 5. Launches, 6. raw processes --------------------------------------------------------

$launchTable = @{}
foreach ($row in (Get-TableRows -Lines (Get-InventorySection 'Les fonctions de lancement'))) {
    $name = Get-Backticked $row.Cells[0]
    if ($name) { $launchTable[$name] = $true }
}
$launchPattern = '(?<![A-Za-z0-9-])(' + ($launchFunctions -join '|') + ')(?![A-Za-z0-9-])'
$rawProcess    = [regex]::Escape('[System.Diagnostics.Process]::Start(')
$launchesSeen  = 0
$unattributed  = New-Object System.Collections.Generic.List[string]
$offProtocol   = New-Object System.Collections.Generic.List[string]

$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'apps') -Recurse -File -Filter '*.ps1' | Where-Object {
    $rel = $_.FullName.Substring($repoRoot.Length + 1).Replace([char]92, [char]47)
    $rel -notmatch '/(var|dist|node_modules)/'
})
foreach ($file in $sourceFiles) {
    $rel = $file.FullName.Substring($repoRoot.Length + 1).Replace([char]92, [char]47)
    $isAction = $rel -like 'apps/backend-pode/actions/*.action.ps1'
    $actionName = if ($isAction) { $file.Name.Substring(0, $file.Name.Length - '.action.ps1'.Length) } else { $null }
    $lines = @(Get-CodeLines -Path $file.FullName)
    $owner = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $definition = [regex]::Match($line, '^[ ]*function[ ]+([A-Za-z0-9-]+)')
        # A one-line function carries its body on the same line: only what follows the name is scanned.
        if ($definition.Success) { $owner = $definition.Groups[1].Value; $line = $line.Substring($definition.Index + $definition.Length) }
        if ($line.TrimStart().StartsWith('#')) { continue }
        $where = '{0}:{1}' -f $rel, ($i + 1)

        foreach ($m in [regex]::Matches($line, $launchPattern)) {
            $launchesSeen++
            $called = $m.Groups[1].Value
            if ($called -eq 'Start-DetachedAction' -and -not ($owner -and $detachedAllowedIn -contains $owner)) {
                $offProtocol.Add(('{0}  {1}' -f $where, $(if ($owner) { $owner } else { $file.Name })))
            }
            if ($isAction) {
                $row = $actionRows[$actionName]
                if (-not $row -or $row.Cells.Count -lt 6 -or $row.Cells[5] -notmatch [regex]::Escape($called)) {
                    $unattributed.Add(('{0}  {1}, {2}' -f $where, $called, $actionName))
                }
            } elseif ($owner) {
                if (-not $inventory.Contains('`' + $owner + '`')) { $unattributed.Add(('{0}  {1}, {2}' -f $where, $called, $owner)) }
            } elseif (-not $inventory.Contains($file.Name)) {
                $unattributed.Add(('{0}  {1}' -f $where, $called))
            }
        }

        if ($rel -like 'apps/backend-pode/*' -and $line -match $rawProcess) {
            if (-not $owner -or -not $launchTable.ContainsKey($owner)) {
                $unattributed.Add(('{0}  Process.Start, {1}' -f $where, $(if ($owner) { $owner } else { $file.Name })))
            }
        }
    }
}
if ($unattributed.Count) {
    Write-Fail (Get-Label 'check-operations.lancement-non-inventorie' $unattributed.Count)
    foreach ($one in $unattributed) { Write-Detail $one }
    $failures++
}

if ($offProtocol.Count) {
    Write-Fail (Get-Label 'check-operations.hors-protocole' $offProtocol.Count)
    foreach ($one in $offProtocol) { Write-Detail $one }
    $failures++
}
$longOffProtocol = @(foreach ($name in $actionRows.Keys) {
    $cells = $actionRows[$name].Cells
    if ($cells.Count -ge 7 -and $cells[4] -eq 'longue' -and -not $cells[6].StartsWith('commun') -and $pendingArbitration -notcontains $name) { $name }
})
if ($longOffProtocol.Count) {
    Write-Fail (Get-Label 'check-operations.longue-non-conforme' $longOffProtocol.Count (($longOffProtocol | Sort-Object) -join ', '))
    $failures++
}

# --- 7. Scripts ---------------------------------------------------------------------------

$codeScripts = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -File |
                 Where-Object { $_.Extension -in '.ps1', '.cmd', '.vbs' -and $scriptsNotOperations -notcontains $_.Name } |
                 ForEach-Object Name)
$scriptSection = (Get-InventorySection "L'installation et les scripts") -join $newline
$inventoryScripts = @([regex]::Matches($scriptSection, '`(?:scripts/)?([A-Za-z0-9-]+[.](?:ps1|cmd|vbs))`') |
                      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Compare-Sets -Category (Get-Label 'check-operations.categorie-scripts') -InCode $codeScripts -InInventory $inventoryScripts

# --- Verdict ------------------------------------------------------------------------------

Write-Info (Get-Label 'check-operations.comptees' $codeActions.Count $codeWorkers.Count $codeRoutes.Count $codeScripts.Count $launchesSeen)
if ($Detail) {
    foreach ($name in ($actionRows.Keys | Sort-Object)) { Write-Detail ('{0}  {1}' -f $name, $actionRows[$name].Cells[5]) }
}
if ($failures) {
    Write-Warn (Get-Label 'check-operations.comment-faire' 'doc/progress/implemented/operations.md')
} else {
    Write-Ok (Get-Label 'check-operations.accord')
}
Write-Outcome -What (Get-Label 'check-operations.termine') -Failures $failures
if ($failures) { exit 2 }
