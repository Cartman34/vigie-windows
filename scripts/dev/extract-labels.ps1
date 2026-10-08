# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    extract-labels.ps1 -- TAKES THE FRENCH TEXT OUT OF THE SCRIPTS and files it in lang/fr.json.
    READ ONLY by default; -Apply rewrites the files.

    Intent: move two hundred labels without damaging any of them, and without having to know which.
    Usage:
      pwsh -File .\scripts\dev\extract-labels.ps1              # what would be done
      pwsh -File .\scripts\dev\extract-labels.ps1 -Apply       # do it
      pwsh -File .\scripts\dev\extract-labels.ps1 -Apply -Path scripts/install.ps1

    WHY A TOOL AND NOT A REREADING. There are more than two hundred labels spread over some thirty files. Moving
    them by hand means damaging a few without ever knowing which. A tool that gets it wrong gets it wrong the
    same way everywhere, and that shows and is fixed in one go.

    IT READS THE TREE, NOT TEXT. A regular expression does not know where a concatenation of a string, a
    variable and another string ends -- it miscounts the brackets as soon as a nested call is inside. So we go
    through PowerShell's own parser ([Parser]::ParseFile): what it calls a string IS a string, without
    discussion.

    WHAT IS EXTRACTED
      - the argument of the display functions: Write-Title/Step/Ok/Warn/Fail/Info/Detail
      - the -Message of Write-Log
      - what is left of Write-Host

    THE HOLES. A concatenation around a variable becomes a label with "{0}" in it and the call becomes
    `Get-Label 'key' $name`. Numbered and not named: a translation has the right to change the order of the
    pieces, not to invent names.

    THE KEYS are "<file>.<beginning-of-the-text-in-dashes>". Readable in the code and in the JSON, and one finds
    where a message comes from without looking for it.
#>
param(
    # Rewrite the files and produce lang/fr.json. Without it, we only list.
    [switch] $Apply,
    # Limit it to one file or folder (a path relative to the root of the repository).
    [string] $Path,
    [string] $Language = 'fr'
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SHOW_COMMANDS = @('write-title', 'write-step', 'write-ok', 'write-warn', 'write-fail',
                   'write-info', 'write-detail', 'write-host')

# These files CARRY the mechanism: they cannot depend on it.
$EXCLUDED = @('scripts/lib/i18n.ps1', 'scripts/lib/console-ui.ps1',
              'scripts/dev/extract-labels.ps1', 'scripts/dev/check-labels.ps1')
$SKIPPED_DIRS = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')   # .claude : les worktrees y vivent, et un worktree est une copie du depot

# --- The key factory ----------------------------------------------------------
# « Tâche « Vigie » enregistrée, DÉSACTIVÉE. » -> « tache-vigie-enregistree »
function ConvertTo-Slug {
    param([string]$Text, [int]$WordCount = 4)
    $flat = $Text -replace '\{\d+\}', ' '
    $flat = $flat.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $flat.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    $flat = $sb.ToString().ToLowerInvariant() -replace '[^a-z0-9]+', ' '
    $words = @($flat.Trim() -split '\s+' | Where-Object { $_.Length -gt 1 })
    if (-not $words.Count) { return 'texte' }
    return (($words | Select-Object -First $WordCount) -join '-')
}

# --- Reading an expression: the text, and its holes ---------------------------
#
# It returns @{ Text = '... {0} ...'; Args = @('$name') }, or $null if the expression has no literal part at all
# -- a display call on a bare variable has no label to extract.
function Read-Expression {
    param([System.Management.Automation.Language.Ast]$Ast)

    $text = ''
    $slots = @()
    $sawLiteral = $false

    function Walk {
        param($node)
        if ($node -is [System.Management.Automation.Language.ParenExpressionAst]) {
            # A BRACKET CAN HOLD A CALL, not only an expression: a parenthesised function call has no
            # .Expression. Without this check, the argument disappeared in silence and the call that was produced
            # ended with an orphan closing bracket.
            $inner = $node.Pipeline.PipelineElements[0]
            if ($inner -and $inner.PSObject.Properties['Expression'] -and $inner.Expression) {
                Walk $inner.Expression
            } else {
                $script:_text += ('{' + $script:_slots.Count + '}')
                $script:_slots += $node.Extent.Text
            }
            return
        }
        # THE -f OPERATOR ALREADY CARRIES ITS HOLES. A format string followed by -f and its values has exactly
        # the shape we want: the label on the left, the values on the right. We treat it only when it makes up
        # the WHOLE argument, otherwise the hole numbers of that string would collide with the ones we have
        # already laid down.
        if ($node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
            $node.Operator -eq [System.Management.Automation.Language.TokenKind]::Format -and
            $node.Left -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $script:_slots.Count -eq 0 -and $script:_text -eq '') {
            $script:_text += $node.Left.Value
            $script:_sawLiteral = $true
            $right = $node.Right
            if ($right -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                foreach ($e in $right.Elements) { $script:_slots += $e.Extent.Text }
            } else {
                $script:_slots += $right.Extent.Text
            }
            return
        }
        if ($node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
            $node.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
            Walk $node.Left
            Walk $node.Right
            return
        }
        if ($node -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $script:_text += $node.Value
            $script:_sawLiteral = $true
            return
        }
        if ($node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            # An interpolated string: the nested pieces become holes, the rest of the text is kept as it stands.
            $whole = $node.Extent.Text
            $inner = $whole.Substring(1, $whole.Length - 2)   # sans les guillemets
            $base  = $node.Extent.StartOffset + 1
            $cursor = 0
            foreach ($n in ($node.NestedExpressions | Sort-Object { $_.Extent.StartOffset })) {
                $rel = $n.Extent.StartOffset - $base
                if ($rel -gt $cursor) { $script:_text += $inner.Substring($cursor, $rel - $cursor); $script:_sawLiteral = $true }
                $script:_text += ('{' + $script:_slots.Count + '}')
                $script:_slots += $n.Extent.Text
                $cursor = $rel + $n.Extent.Text.Length
            }
            if ($cursor -lt $inner.Length) { $script:_text += $inner.Substring($cursor); $script:_sawLiteral = $true }
            return
        }
        # Everything else is a value: a hole.
        $script:_text += ('{' + $script:_slots.Count + '}')
        $script:_slots += $node.Extent.Text
    }

    $script:_text = ''
    $script:_slots = @()
    $script:_sawLiteral = $false
    Walk $Ast
    if (-not $script:_sawLiteral) { return $null }
    # A text without a single letter is not a label.
    if ($script:_text -notmatch '\p{L}') { return $null }
    return @{ Text = $script:_text; Args = @($script:_slots) }
}

# --- Parcours ---------------------------------------------------------------------------
$labels   = [ordered]@{}
$usedKeys = @{}
$edits    = 0
$touched  = 0
$unreachable = 0

$searchRoot = if ($Path) { Join-Path $repoRoot $Path } else { $repoRoot }
$files = if (Test-Path -LiteralPath $searchRoot -PathType Leaf) {
    @(Get-Item -LiteralPath $searchRoot)
} else {
    Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue
}

Write-Title 'Extraction des libellés'

foreach ($f in ($files | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($EXCLUDED -contains $rel) { continue }
    if ($SKIPPED_DIRS | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }

    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) { Write-Warn ($rel + " : illisible (" + $errors.Count + " erreur(s) de syntaxe), ignoré"); continue }

    $stem = [IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '\.(probe|action|worker)$', ''

    # The replacements are made from the END towards the BEGINNING: otherwise each rewrite shifts the positions of
    # all the following ones.
    $replacements = @()

    $commands = $ast.FindAll({
        param($n) $n -is [System.Management.Automation.Language.CommandAst]
    }, $true)

    foreach ($cmd in $commands) {
        $name = $cmd.GetCommandName()
        if (-not $name) { continue }
        $lower = $name.ToLowerInvariant()

        $target = $null
        if ($SHOW_COMMANDS -contains $lower) {
            # The first element after the name, if it is not a named parameter.
            $elems = @($cmd.CommandElements)
            if ($elems.Count -ge 2 -and
                -not ($elems[1] -is [System.Management.Automation.Language.CommandParameterAst])) {
                $target = $elems[1]
            }
        } elseif ($lower -eq 'write-log') {
            $elems = @($cmd.CommandElements)
            for ($i = 1; $i -lt $elems.Count - 1; $i++) {
                if ($elems[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $elems[$i].ParameterName -ieq 'Message') {
                    $target = $elems[$i + 1]; break
                }
            }
        }
        if (-not $target) { continue }
        # Already externalised: we do not go over it again.
        if ($target.Extent.Text -match 'Get-Label') { continue }

        $read = Read-Expression -Ast $target
        if (-not $read) { continue }

        $slug = ConvertTo-Slug $read.Text
        $key  = $stem + '.' + $slug
        $n = 2
        while ($usedKeys.ContainsKey($key) -and $usedKeys[$key] -ne $read.Text) { $key = $stem + '.' + $slug + '-' + $n; $n++ }
        $usedKeys[$key] = $read.Text
        $labels[$key] = $read.Text

        $call = "(Get-Label '" + $key + "'"
        foreach ($a in $read.Args) { $call += ' ' + $a }
        $call += ')'

        $replacements += @{ Start = $target.Extent.StartOffset; End = $target.Extent.EndOffset; Text = $call }
        $edits++
    }

    # DOES THE FILE HAVE ACCESS TO THE LABELS? Get-Label comes either from common.ps1 (the whole server app) or
    # from console-ui.ps1 (the scripts). A file that loads neither would break AT RUN TIME, on its display line.
    # We do not touch it, we name it.

    $srcText = [IO.File]::ReadAllText($f.FullName, (New-Object Text.UTF8Encoding($false)))
    $reachable = ($srcText -match '(?m)^\s*\.\s.*(common|console-ui|i18n)\.ps1') -or ($rel -eq 'apps/backend-pode/lib/common.ps1')
    if ($replacements.Count -and -not $reachable) {
        Write-Warn ($rel + " : n'a acces ni a common.ps1 ni a console-ui.ps1 -- laisse tel quel")
        $unreachable++
        continue
    }

    if ($replacements.Count -and $Apply) {
        $src = [IO.File]::ReadAllText($f.FullName, (New-Object Text.UTF8Encoding($false)))
        foreach ($r in ($replacements | Sort-Object Start -Descending)) {
            $src = $src.Substring(0, $r.Start) + $r.Text + $src.Substring($r.End)
        }
        [IO.File]::WriteAllText($f.FullName, $src, (New-Object Text.UTF8Encoding($true)))
        $touched++
    }
    if ($replacements.Count) { Write-Detail ('{0,4}  {1}' -f $replacements.Count, $rel) }
}

Write-Info ("{0} libellé(s) dans {1} fichier(s)." -f $edits, $touched)
if ($unreachable) { Write-Warn ("{0} fichier(s) laissés de côté : pas d'accès aux libellés." -f $unreachable) }

if ($Apply) {
    $langDir = Join-Path $repoRoot 'lang'
    if (-not (Test-Path -LiteralPath $langDir)) { New-Item -ItemType Directory -Path $langDir -Force | Out-Null }
    $file = Join-Path $langDir ($Language + '.json')

    # We MERGE with what exists: a pass over one single file must not erase the other files' labels.
    $merged = [ordered]@{}
    if (Test-Path -LiteralPath $file) {
        $old = ([IO.File]::ReadAllText($file, (New-Object Text.UTF8Encoding($false))) | ConvertFrom-Json)
        foreach ($p in $old.PSObject.Properties) { $merged[$p.Name] = [string]$p.Value }
    }
    foreach ($k in $labels.Keys) { $merged[$k] = $labels[$k] }

    $sorted = [ordered]@{}
    foreach ($k in ($merged.Keys | Sort-Object)) { $sorted[$k] = $merged[$k] }
    $json = ($sorted | ConvertTo-Json -Depth 3)
    # JSON: UTF-8 WITHOUT a BOM, which is the standard and what fetch() expects.
    [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Ok ("lang/{0}.json : {1} libellé(s)." -f $Language, $sorted.Count)
} else {
    Write-Info 'Rien écrit. Relancez avec -Apply.'
}

Write-Outcome -What 'Extraction terminée'
exit 0
