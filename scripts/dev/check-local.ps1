# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    THE RULES THAT ARE DECIDED INSIDE ONE FILE.

    Intent: hold the three rules that need nothing but the file they read -- so they can be asked of the CHANGED
    files instead of the whole repository. They lived in check-coherence until 15/10, where they were mixed with
    rules that need every file; a verifier with a mixed scope cannot be run on a list, and the splat rule alone
    cost 3 715 ms of a 7 500 ms pass, all of it spent parsing 153 files to ask each one a local question
    (notes/evidence/2026-10-15-what-makes-check-coherence-slow.md).

    Usage:
      pwsh -File .\scripts\dev\check-local.ps1                      # every .ps1 of the repository
      pwsh -File .\scripts\dev\check-local.ps1 -Files a.ps1,b.ps1   # these files only
      pwsh -File .\scripts\dev\check-local.ps1 -FilesFrom list.txt  # the same, one path per line
    Exit codes: 0 = nothing to report; 2 = at least one shortfall.

    Each rule carries, above it, the defect it was born of. They are moved here word for word: that history is
    what keeps somebody from deciding the rule is pointless.
#>
[CmdletBinding()]
param(
    [switch] $Detail,
    # The files to read. Empty: the whole repository, which is what -All of check-all comes to.
    [string[]] $Files,
    # The same list, read from a file -- a list can outgrow a command line.
    [string] $FilesFrom
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$skipped = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')
function Test-Skipped {
    param([string]$Relative)
    foreach ($s in $skipped) {
        if ($Relative -like ($s + '/*') -or $Relative -like ('*/' + $s + '/*')) { return $true }
    }
    return $false
}
function Get-Relative {
    param([string]$Full)
    $Full.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
}


<#
    THE FILES TO READ. Given, read from a file, or all of them. A path that does not exist is dropped in silence:
    the orchestrator hands over what git says changed, and git names deleted files too.
#>
function Get-SubjectScripts {
    $wanted = @()
    if ($Files) { $wanted += $Files }
    if ($FilesFrom) {
        if (-not (Test-Path -LiteralPath $FilesFrom -PathType Leaf)) { throw "Liste de fichiers introuvable : $FilesFrom" }
        $wanted += @(Get-Content -LiteralPath $FilesFrom -Encoding UTF8 | Where-Object { "$_".Trim() })
    }
    if (-not $wanted.Count) {
        return @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue |
                 Where-Object { -not (Test-Skipped (Get-Relative $_.FullName)) })
    }
    $out = @()
    foreach ($w in $wanted) {
        if ("$w" -notlike '*.ps1') { continue }
        $full = $(if ([IO.Path]::IsPathRooted($w)) { $w } else { Join-Path $repoRoot $w })
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        if (Test-Skipped (Get-Relative $full)) { continue }
        $out += Get-Item -LiteralPath $full
    }
    return @($out)
}

$scripts = @(Get-SubjectScripts)
$faults = @()

# --- 4. A variable does not carry a parameter's name --------------------------
#
# POWERSHELL IGNORES CASE: a lower-case and an upper-case spelling are THE SAME VARIABLE. Writing an assignment
# with a different case inside a script that declares that parameter is not a local variable: it is an
# ASSIGNMENT TO THE PARAMETER. If the parameter carries a ValidateSet, the script dies on the spot, with a message
# about something else.
#
# Twice on the same day, 30/08, in the same file. The second time, the update died at line 192 in front of the
# user.

foreach ($f in $scripts) {
    $rel = Get-Relative $f.FullName
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }

    # The SCRIPT's param() block: its names are the ones that can be overwritten.
    $errors = $null; $tokens = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) { continue }
    $block = $tree.ParamBlock
    if (-not $block) { continue }
    $names = @($block.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    if (-not $names.Count) { continue }

    # Every assignment whose name EQUALS a parameter's but for the case, while being spelled differently: that is
    # the sign one believed one was creating a variable of one's own.
    foreach ($a in $tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $left = $a.Left
        if ($left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        $used = $left.VariablePath.UserPath
        foreach ($p in $names) {
            # "-cne": CASE SENSITIVE. With "-ne", the comparison ignores case like the rest of PowerShell -- the
            # rule could never fire, and I believed it sound because it was going green.
            if ($used -cne $p -and $used -ieq $p) {
                $faults += ("variable « `${0} » : c'est le paramètre « `${1} » (la casse ne compte pas) -- {2}:{3}" -f
                            $used, $p, $rel, $left.Extent.StartLineNumber)
            }
        }
    }
}


# --- 6. A SPLATTED NAME THAT NOBODY ASSIGNS -----------------------------------------------
#
# POWERSHELL SAYS NOTHING ABOUT A VARIABLE THAT DOES NOT EXIST: it reads as empty, and the
# line runs. Splatted, the whole argument list simply vanishes -- "& $pwsh @suite" launched
# an interpreter with NO ARGUMENT and returned its exit code as if the work had been done.
# The name had been renamed to $nextArgs three lines above; the splat kept the old one.
#
# Found on 03/09 in install.ps1, on the 5.1 -> 7 switch: every installation started from
# Windows PowerShell went through this line. Third fault of the same family -- the version
# pills, then $fields, then this one -- and the first two were only seen from the outside,
# on a card that had gone empty.
#
# The rule stays on SPLATS, where an empty read is always a defect: elsewhere, a variable
# read before its assignment has honest uses that no scan can tell apart.
$autoVariables = @('_', 'args', 'PSItem', 'true', 'false', 'null', 'PSScriptRoot', 'PSCommandPath',
                   'Matches', 'LASTEXITCODE', 'Error', 'PID', 'Host', 'MyInvocation', 'PSVersionTable',
                   'input', 'PSBoundParameters', 'this', 'PSCmdlet', 'ExecutionContext', 'PSHOME')
foreach ($f in $scripts) {
    $rel = Get-Relative $f.FullName
    $errors = $null; $tokens = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) { continue }

    $splats = @($tree.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Splatted }, $true))
    if (-not $splats.Count) { continue }

    # Every name the file gives a value to, in any scope: an assignment, a parameter, a
    # foreach variable. Scope is not followed on purpose -- naming it once anywhere is
    # enough to clear it, and what we hunt is a name that exists NOWHERE.
    $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($a in $tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        foreach ($v in $a.Left.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
            [void]$known.Add($v.VariablePath.UserPath)
        }
    }
    foreach ($pa in $tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
        [void]$known.Add($pa.Name.VariablePath.UserPath)
    }
    foreach ($fe in $tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
        [void]$known.Add($fe.Variable.VariablePath.UserPath)
    }

    foreach ($v in $splats) {
        $name = $v.VariablePath.UserPath
        if ($name.Contains([char]58)) { continue }   # $env:, $script:, ... : another scope answers for it
        if ($autoVariables -contains $name) { continue }
        if ($known.Contains($name)) { continue }
        $faults += ("« @{0} » : aucune valeur n'est jamais donnée à `${0} -- les arguments partent vides -- {1}:{2}" -f
                    $name, $rel, $v.Extent.StartLineNumber)
    }
}

# --- 7. A CONCATENATION INSIDE A COMMA LIST ------------------------------------------------
#
# THE COMMA BINDS TIGHTER THAN THE PLUS. In @('a' + 'b', 'c' + 'd'), PowerShell reads
# 'a' + ('b','c') + 'd' -- one element instead of two, and no error anywhere. Written on
# 02/09 in a guard rail, which then never fired; written again on 03/09 in the store filter,
# which then let every launcher process through. Twice the same day, both times found by
# testing the result rather than by rereading the line.
#
# A single-element array is not concerned: without a comma there is nothing to bind.
foreach ($f in $scripts) {
    $rel = Get-Relative $f.FullName
    $errors = $null; $tokens = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) { continue }
    # WE LOOK FOR THE MIS-PARSE ITSELF, not for what was meant. Once collapsed, the tree
    # holds an addition whose operand is a BARE comma list -- the very shape that cannot be
    # written on purpose. An array built with @( ) is another node, and stays untouched.
    foreach ($sum in $tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)) {
        if ($sum.Operator -ne [System.Management.Automation.Language.TokenKind]::Plus) { continue }
        foreach ($side in @($sum.Left, $sum.Right)) {
            if ($side -isnot [System.Management.Automation.Language.ArrayLiteralAst]) { continue }
            if ($side.Elements.Count -lt 2) { continue }
            $faults += ("concaténation dans une liste à virgules : la virgule lie plus fort que le plus -- {0}:{1}" -f
                        $rel, $sum.Extent.StartLineNumber)
        }
    }
}


# --- Verdict -----------------------------------------------------------------------------
Write-Title 'Règles locales à un fichier'
Write-Info ("{0} fichier(s) lu(s)." -f $scripts.Count)
if (-not $faults.Count) {
    Write-Ok "Aucun manquement."
    Write-Outcome -What 'Règles locales vérifiées'
    exit 0
}
Write-Fail ("{0} manquement(s) :" -f $faults.Count)
foreach ($x in $faults) { Write-Detail ('- ' + $x) }
Write-Outcome -What 'Règles locales vérifiées'
exit 2
