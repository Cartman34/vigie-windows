<#
    extract-labels.ps1 - SORT LE TEXTE FRANÇAIS DES SCRIPTS et le range dans lang/fr.json.
    LECTURE SEULE par défaut ; -Apply réécrit les fichiers.

    POURQUOI UN OUTIL ET PAS UNE RELECTURE. Il y a plus de deux cents libellés répartis
    dans une trentaine de fichiers. Les déplacer à la main, c'est en abîmer quelques-uns
    sans jamais savoir lesquels. Un outil qui se trompe se trompe pareil partout, et ça,
    ça se voit et ça se corrige d'un coup.

    IL LIT L'ARBRE, PAS DU TEXTE. Une expression régulière ne sait pas où finit
    `("Tâche « " + $nom + " » posée.")` -- elle compte mal les parenthèses dès qu'un appel
    imbriqué s'y trouve. On passe donc par l'analyseur de PowerShell lui-même
    ([Parser]::ParseFile) : ce qu'il appelle une chaîne EST une chaîne, sans discussion.

    CE QUI EST EXTRAIT
      - l'argument des fonctions d'affichage : Write-Title/Step/Ok/Warn/Fail/Info/Detail
      - le -Message de Write-Log
      - ce qui reste de Write-Host

    LES TROUS. « "Tâche " + $nom + " posée." » devient « Tâche {0} posée. » et l'appel
    devient `Get-Label 'cle' $nom`. Numérotés et non nommés : une traduction a le droit
    de changer l'ordre des morceaux, pas d'inventer des noms.

    LES CLÉS sont « <fichier>.<début-du-texte-en-tirets> ». Lisibles dans le code et dans
    le JSON, et on retrouve d'où vient un message sans le chercher.

    Usage :
      pwsh -File .\scripts\dev\extract-labels.ps1              # ce qui serait fait
      pwsh -File .\scripts\dev\extract-labels.ps1 -Apply       # le faire
      pwsh -File .\scripts\dev\extract-labels.ps1 -Apply -Path scripts/install.ps1
#>
param(
    # Réécrire les fichiers et produire lang/fr.json. Sans lui, on ne fait que lister.
    [switch] $Apply,
    # Se limiter à un fichier ou un dossier (chemin relatif à la racine du dépôt).
    [string] $Path,
    [string] $Language = 'fr'
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SHOW_COMMANDS = @('write-title', 'write-step', 'write-ok', 'write-warn', 'write-fail',
                   'write-info', 'write-detail', 'write-host')

# Ces fichiers PORTENT le mécanisme : ils ne peuvent pas en dépendre.
$EXCLUDED = @('scripts/lib/i18n.ps1', 'scripts/lib/console-ui.ps1',
              'scripts/dev/extract-labels.ps1', 'scripts/dev/check-labels.ps1')
$SKIPPED_DIRS = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')   # .claude : les worktrees y vivent, et un worktree est une copie du depot

# --- Fabrique de clés -------------------------------------------------------------------
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

# --- Lecture d'une expression : le texte, et ses trous ----------------------------------
#
# Rend @{ Text = 'Tâche {0} posée.'; Args = @('$nom') } ou $null si l'expression n'a
# aucune partie littérale -- « Write-Info $ligne » n'a pas de libellé à extraire.
function Read-Expression {
    param([System.Management.Automation.Language.Ast]$Ast)

    $text = ''
    $slots = @()
    $sawLiteral = $false

    function Walk {
        param($node)
        if ($node -is [System.Management.Automation.Language.ParenExpressionAst]) {
            # UNE PARENTHESE PEUT CONTENIR UN APPEL, pas seulement une expression :
            # « (Get-EnvironmentLabel -Environment $e) » n'a pas de .Expression. Sans ce
            # controle, l'argument disparaissait en silence et l'appel produit finissait
            # par « Get-Label 'cle' ) ».
            $inner = $node.Pipeline.PipelineElements[0]
            if ($inner -and $inner.PSObject.Properties['Expression'] -and $inner.Expression) {
                Walk $inner.Expression
            } else {
                $script:_text += ('{' + $script:_slots.Count + '}')
                $script:_slots += $node.Extent.Text
            }
            return
        }
        # L'OPERATEUR -f PORTE DEJA SES TROUS. « "Tray PID {0}" -f $id » a exactement la
        # forme qu'on veut : le libelle est a gauche, les valeurs a droite. On ne le
        # traite que s'il constitue TOUT l'argument, sinon les numeros de trous de la
        # chaine entreraient en collision avec ceux qu'on a deja poses.
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
            # « "Version $v posée" » : les morceaux imbriqués deviennent des trous, le
            # reste du texte est conservé tel quel.
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
        # Tout le reste est une valeur : un trou.
        $script:_text += ('{' + $script:_slots.Count + '}')
        $script:_slots += $node.Extent.Text
    }

    $script:_text = ''
    $script:_slots = @()
    $script:_sawLiteral = $false
    Walk $Ast
    if (-not $script:_sawLiteral) { return $null }
    # Un texte sans une seule lettre n'est pas un libellé (« {0} », « --- »).
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

    # Les remplacements se font de la FIN vers le DÉBUT : sinon chaque réécriture décale
    # les positions de toutes les suivantes.
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
            # Le premier élément après le nom, s'il n'est pas un paramètre nommé.
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
        # Déjà externalisé : on ne repasse pas dessus.
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

    # LE FICHIER A-T-IL ACCES AUX LIBELLES ? Get-Label vient soit de common.ps1 (tout le
    # backend), soit de console-ui.ps1 (les scripts). Un fichier qui ne charge ni l'un ni
    # l'autre casserait A L'EXECUTION, sur sa ligne d'affichage. On ne le touche pas, on
    # le nomme.
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

    # On FUSIONNE avec l'existant : une passe sur un seul fichier ne doit pas effacer les
    # libellés des autres.
    $merged = [ordered]@{}
    if (Test-Path -LiteralPath $file) {
        $old = ([IO.File]::ReadAllText($file, (New-Object Text.UTF8Encoding($false))) | ConvertFrom-Json)
        foreach ($p in $old.PSObject.Properties) { $merged[$p.Name] = [string]$p.Value }
    }
    foreach ($k in $labels.Keys) { $merged[$k] = $labels[$k] }

    $sorted = [ordered]@{}
    foreach ($k in ($merged.Keys | Sort-Object)) { $sorted[$k] = $merged[$k] }
    $json = ($sorted | ConvertTo-Json -Depth 3)
    # JSON : UTF-8 SANS BOM, c'est la norme et c'est ce que fetch() attend.
    [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Ok ("lang/{0}.json : {1} libellé(s)." -f $Language, $sorted.Count)
} else {
    Write-Info 'Rien écrit. Relancez avec -Apply.'
}

Write-Outcome -What 'Extraction terminée'
exit 0
