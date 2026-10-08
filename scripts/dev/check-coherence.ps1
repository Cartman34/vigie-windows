# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    THE INCONSISTENCIES I DO NOT SEE ON MY OWN.

    Intent: catch what no single reading catches -- a name defined twice, a decision cited that does not exist, a
    filter copied by hand, a variable that is really a parameter. Every rule here was born of a real defect, and
    the comment above it says which.
    Usage: pwsh -File .\scripts\dev\check-coherence.ps1 (-Detail to see each shortfall). Exit codes: 0 =
    consistent; 2 = at least one shortfall. The source of truth for the decisions is doc/progress/decisions.md;
    to consult it quickly, scripts/dev/decisions.ps1 -About "<words>".

    The first two rules were born the same day, of the same defect: believing that I remember.

    1. A FUNCTION IS DEFINED ONCE ONLY. I wrote a Get-MachineConfigPath while one already existed, three thousand
       lines further down, with an altogether different meaning. The last definition wins IN SILENCE: my function
       did not exist, and the call failed on a mandatory parameter that was not mine. Nothing, nowhere, had
       reported it.

    2. A DECISION THAT IS CITED EXISTS. The code refers to D65, D99, D107 -- that is what ties a line to its
       reason for being. A reference to a number that does not exist sends one looking for a rule that was never
       written.
#>
[CmdletBinding()]
param([switch] $Detail)

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

$faults = @()

# --- 1. One function, one definition ------------------------------------------
#
# We look at the SHARED LIBRARIES: the ones everybody loads together, so the ones where a redefinition really
# overwrites. Two independent scripts each naming their own little helper do not tread on each other, and
# reporting them would be noise.
$libs = @()
foreach ($d in @('apps/backend-pode/lib', 'scripts/lib')) {
    $p = Join-Path $repoRoot $d
    if (Test-Path -LiteralPath $p) {
        $libs += @(Get-ChildItem -LiteralPath $p -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
    }
}
$seen = @{}
foreach ($f in $libs) {
    $rel = Get-Relative $f.FullName
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
        $n++
        if ($line -match '^\s*function\s+([A-Za-z][\w-]*)') {
            $name = $Matches[1]
            if (-not $seen.ContainsKey($name)) { $seen[$name] = @() }
            $seen[$name] += ('{0}:{1}' -f $rel, $n)
        }
    }
}
foreach ($name in ($seen.Keys | Sort-Object)) {
    if ($seen[$name].Count -gt 1) {
        $faults += ("fonction définie {0} fois — {1} : {2}" -f $seen[$name].Count, $name, ($seen[$name] -join ' , '))
    }
}

# --- 2. A decision that is cited exists ---------------------------------------
$decisionsFile = Join-Path $repoRoot 'doc/progress/decisions.md'
$known = @{}
if (Test-Path -LiteralPath $decisionsFile) {
    foreach ($line in (Get-Content -LiteralPath $decisionsFile -Encoding UTF8)) {
        if ($line -match '^#{2,3}\s+(D\d+[a-z]*)') { $known[$Matches[1].ToUpperInvariant()] = $true }
    }
} else {
    $faults += ("fichier des décisions introuvable : " + $decisionsFile)
}

$cited = @{}
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1', '*.psd1', '*.html', '*.md' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
    if ($rel -eq 'doc/progress/decisions.md') { continue }
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $n++
        # A GROUP OF A GUID IS NOT A DECISION: the second group of an interface id of Windows Update was read as a
        # decision number on 15/09. A number between two hyphens with hexadecimal on both sides is skipped.
        foreach ($m in [regex]::Matches($line, '(?<![0-9A-Fa-f]-)\bD(\d{1,3})\b(?!-[0-9A-Fa-f])')) {
            $id = 'D' + $m.Groups[1].Value
            if ($known.ContainsKey($id)) { continue }
            $key = $id
            if (-not $cited.ContainsKey($key)) { $cited[$key] = @() }
            $cited[$key] += ('{0}:{1}' -f $rel, $n)
        }
    }
}
foreach ($id in ($cited.Keys | Sort-Object)) {
    $ou = $cited[$id]
    $extrait = if ($ou.Count -gt 3) { ($ou[0..2] -join ' , ') + (' … +' + ($ou.Count - 3)) } else { $ou -join ' , ' }
    $faults += ("décision citée mais inexistante — {0} : {1}" -f $id, $extrait)
}

# --- 3. The circles of accounts are not filtered again by hand ----------------
#
# The same "not technical" filter was copied in SEVEN places. A copied filter is a filter one forgets somewhere:
# the call that did not have it dropped a restart order inside the SERVICE account's folder, where nobody will
# ever read it.
#
# The three circles have names (common.ps1): Get-ComputerAccounts, Get-UserAccounts, Get-EnabledAccounts. We go
# through them -- otherwise the day a circle's definition changes, it changes in one place out of seven.
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
    # common.ps1 IS the implementation of the three circles.
    if ($rel -eq 'apps/backend-pode/lib/common.ps1') { continue }
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $n++
        if ($line -match '^\s*#') { continue }
        # THE PATTERNS ARE WRITTEN IN PIECES, or this file would report itself.
        #
        # AND WE AIM AT THE CIRCLES ONLY. The first attempt also caught a circle followed by a search on a name --
        # looking for ONE account by its name is not filtering a circle again. Only "technical" and "enabled"
        # define the circles.
        $marque = '$_.' + 'technical'
        $actif  = '$_.' + 'enabled'
        if ($line.Contains($marque)) {
            $faults += ("cercle de comptes recopié (utiliser Get-UserAccounts) -- {0}:{1}" -f $rel, $n)
        }
        if ($line.Contains($actif) -and ($line -match 'Accounts')) {
            $faults += ("cercle de comptes recopié (utiliser Get-EnabledAccounts) -- {0}:{1}" -f $rel, $n)
        }
    }
}

# --- 4. A variable does not carry a parameter's name --------------------------
#
# POWERSHELL IGNORES CASE: a lower-case and an upper-case spelling are THE SAME VARIABLE. Writing an assignment
# with a different case inside a script that declares that parameter is not a local variable: it is an
# ASSIGNMENT TO THE PARAMETER. If the parameter carries a ValidateSet, the script dies on the spot, with a message
# about something else.
#
# Twice on the same day, 30/08, in the same file. The second time, the update died at line 192 in front of the
# user.

foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
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

# --- 5. What an action returns to a person does not live at the service's ------
#
# THE DEFECT. An action that fetched logs copied them into the SERVER APP's var, then returned that path to the
# user. That was right on the day it was written: the server ran under the person's account then. Since it runs
# under a service account (28/08), that folder is unreadable to everybody but it -- "62 files fetched", true and
# useless. The code had not moved; the ground under it had.
#
# THE RULE. An action that returns a PATH in its result must have built it for somebody: Get-AccountVarRoot,
# Get-RequesterAccount, a public folder. If it only cites Get-VarPath / Get-LogDir / Get-VarRoot, it returns a
# service path to a person, and nobody will notice before trying to open it.
$actionsDir = Join-Path $repoRoot 'apps/backend-pode/actions'
if (Test-Path -LiteralPath $actionsDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $actionsDir -Filter '*.action.ps1' -File -ErrorAction SilentlyContinue)) {
        $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        if (-not $text) { continue }
        # Does it return a path? We look for a "path =" key in the result, anywhere, but not for a variable of the
        # same name: the first is a key returned to the caller, the second a working variable.
        #
        # THE SAME TRAP TWICE IN THIS ONE LINE. First an escape sequence written from a Python script, where it
        # became the BACKSPACE character: the rule was looking for a control character and never found anything.
        # Then a start-of-line anchor, which saw nothing as soon as the result fitted on a single line. Both times,
        # green was enough for me. A rule is proven by making it FAIL.
        # WE DO NOT READ THE COMMENTS. A route written inside an explanation, query string included, made the
        # checker accuse an action that returns no path at all.


        $code = [regex]::Replace($text, '(?s)<#.*?#>', '')
        $code = ($code -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        if ($code -notmatch '(?<![\w$])path\s*=') { continue }
        $duService  = ($code -match 'Get-VarPath|Get-LogDir|Get-VarRoot')
        $ofRequester = ($code -match 'Get-AccountVarRoot|Get-RequesterAccount')
        if ($duService -and -not $ofRequester) {
            $faults += ("action « {0} » : elle rend un chemin construit sur le var du service -- illisible depuis la session de qui la demande" -f $f.Name)
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
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
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
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
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
Write-Title 'Cohérence'
Write-Info ("{0} bibliothèque(s) partagée(s), {1} décision(s) connue(s)." -f $libs.Count, $known.Count)
if (-not $faults.Count) {
    Write-Ok "Aucune redéfinition, aucun renvoi mort."
    Write-Outcome -What 'Cohérence vérifiée'
    exit 0
}
Write-Fail ("{0} manquement(s) :" -f $faults.Count)
foreach ($x in $faults) { Write-Detail ('- ' + $x) }
Write-Outcome -What 'Cohérence vérifiée'
exit 2
