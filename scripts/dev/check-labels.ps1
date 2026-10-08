# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-labels.ps1 -- NO MISSING KEY GOES OUT IN A DELIVERY. READ ONLY.

    Intent: be the counterpart of the mechanism that took the labels out of the code. That move removed one defect
    -- lost accents -- and created another, more insidious one: a mistyped key is not seen on rereading, does not
    make the parsing fail, and only appears at the moment the message must be displayed. That is to say, often
    during an incident, when one most needs to read. Without this checker, the mechanism should not have been
    adopted.

    Usage:
      pwsh -File .\scripts\dev\check-labels.ps1
      pwsh -File .\scripts\dev\check-labels.ps1 -Detail
    Exit codes: 0 = nothing blocking; 2 = at least one key absent or wrongly filled.

    WHAT IS CHECKED

    1. EVERY KEY THAT IS ASKED FOR EXISTS. `Get-Label 'x.y'` without "x.y" in lang/fr.json is a blocking fault.
       It is the failure mode we refused from the start.

    2. THE HOLES MATCH. A label that says "{0}" and "{1}" asks for two values. Too few, and the message displays
       "{1}" as it stands; too many, and the surplus is ignored in silence. We count on both sides.

    3. ORPHAN LABELS ARE REPORTED, without blocking. A key nobody calls any more is not a fault: it may serve the
       front end, or a rare code path. But we want to see it, otherwise the file swells indefinitely.

    4. EVERY LANGUAGE HAS THE SAME KEYS. The day en.json exists, a key present on one side and absent on the
       other is a hole in the translation.
#>




param(
    [switch] $Detail
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SKIPPED = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')   # .claude : les worktrees y vivent, et un worktree est une copie du depot
$REFERENCE_LANGUAGE = 'fr'

# --- The labels that are declared ---------------------------------------------
$langDir = Join-Path $repoRoot 'lang'
if (-not (Test-Path -LiteralPath $langDir)) {
    Write-Title 'Libellés'
    Write-Fail 'Le dossier lang/ est absent : aucun libellé à vérifier.'
    Write-Outcome -Failures 1
    exit 2
}

$tables = @{}
foreach ($f in (Get-ChildItem -LiteralPath $langDir -File -Filter '*.json')) {
    $lang = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $obj = [IO.File]::ReadAllText($f.FullName, (New-Object Text.UTF8Encoding($false))) | ConvertFrom-Json
    $t = @{}
    foreach ($p in $obj.PSObject.Properties) { $t[$p.Name] = [string]$p.Value }
    $tables[$lang] = $t
}
if (-not $tables.ContainsKey($REFERENCE_LANGUAGE)) {
    Write-Title 'Libellés'
    Write-Fail ("lang/{0}.json est absent : c'est la langue de référence." -f $REFERENCE_LANGUAGE)
    Write-Outcome -Failures 1
    exit 2
}
$reference = $tables[$REFERENCE_LANGUAGE]

# How many distinct holes does a label ask for? "{0} {1} {0}" asks for two.
function Get-SlotCount {
    param([string]$Text)
    $seen = @{}
    foreach ($m in [regex]::Matches($Text, '\{(\d+)\}')) { $seen[[int]$m.Groups[1].Value] = $true }
    if (-not $seen.Count) { return 0 }
    return (($seen.Keys | Measure-Object -Maximum).Maximum + 1)
}

# --- The keys the code asks for -----------------------------------------------
#
# We go through the syntax tree and not through a regular expression: we have to COUNT THE ARGUMENTS of the call,
# which a textual pattern cannot do as soon as a value itself holds brackets.
$missing  = @()
$mismatch = @()
$used     = @{}

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }

    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) { continue }

    $calls = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-Label'
    }, $true)

    foreach ($c in $calls) {
        $elems = @($c.CommandElements)
        if ($elems.Count -lt 2) { continue }
        $keyAst = $elems[1]
        if (-not ($keyAst -is [System.Management.Automation.Language.StringConstantExpressionAst])) {
            # A computed key cannot be checked here; we report it rather than ignore it.
            # EXCEPT IN THE RESOLVER. show-confirm.ps1 receives keys as parameters and resolves them: that is its
            # reason for being, and reporting it there would amount to blaming a translator for translating.


            if ($rel -ne 'scripts/lib/show-confirm.ps1') {
                $mismatch += @{ File = $rel; Line = $c.Extent.StartLineNumber
                                Message = 'clé calculée : impossible à vérifier à froid' }
            }
            continue
        }
        $key = $keyAst.Value
        $used[$key] = $true
        if (-not $reference.ContainsKey($key)) {
            $missing += @{ File = $rel; Line = $c.Extent.StartLineNumber; Message = $key }
            continue
        }
        $given = $elems.Count - 2
        $wanted = Get-SlotCount $reference[$key]
        if ($given -lt $wanted) {
            $mismatch += @{ File = $rel; Line = $c.Extent.StartLineNumber
                            Message = ("{0} : {1} trou(s) attendu(s), {2} fourni(s)" -f $key, $wanted, $given) }
        }
    }
}

# --- The keys the front end asks for ------------------------------------------
#
# THE BROWSER CONSUMES THE SAME FILE. Checking only the .ps1 files would leave half the keys without a net -- and
# it is on the interface side that a missing key shows up most.
foreach ($h in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.html' -ErrorAction SilentlyContinue)) {
    $rel = $h.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $text = [IO.File]::ReadAllText($h.FullName, (New-Object Text.UTF8Encoding($false)))

    # A COMMENT EXPLAINING THE MECHANISM IS NOT A CALL. The instructions write a data-i18n attribute with a
    # placeholder key; the checker then demanded a key by that placeholder's name. We neutralise the comment lines
    # before looking.
    $text = [regex]::Replace($text, '(?m)^\s*//.*$', '')

    # L('key'), L('key', value) ... and the marks of the static HTML.
    foreach ($m in [regex]::Matches($text, "L\('([a-zA-Z0-9._-]+)'")) {
        $key = $m.Groups[1].Value
        $used[$key] = $true
        if (-not $reference.ContainsKey($key)) {
            $line = ($text.Substring(0, $m.Index) -split "`n").Count
            $missing += @{ File = $rel; Line = $line; Message = $key }
        }
    }
    foreach ($m in [regex]::Matches($text, 'data-i18n(?:-attr)?="([^"]+)"')) {
        foreach ($part in ($m.Groups[1].Value -split ';')) {
            $key = if ($part -like '*:*') { ($part -split ':', 2)[1].Trim() } else { $part.Trim() }
            $used[$key] = $true
            if (-not $reference.ContainsKey($key)) {
                $line = ($text.Substring(0, $m.Index) -split "`n").Count
                $missing += @{ File = $rel; Line = $line; Message = $key }
            }
        }
    }
}

# A KEY THAT IS CITED IS A KEY THAT IS USED. Since the confirmation window receives them as parameters -- through
# -TitleKey and its kin -- the key no longer appears inside a call to Get-Label. Looking for the NAME itself,
# wherever it is, avoids declaring orphan labels that are indeed displayed.
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.html' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $body = [IO.File]::ReadAllText($f.FullName, (New-Object Text.UTF8Encoding($false)))
    foreach ($k in $reference.Keys) {
        if (-not $used.ContainsKey($k) -and $body.Contains("'" + $k + "'")) { $used[$k] = $true }
    }
}

$orphans = @($reference.Keys | Where-Object { -not $used.ContainsKey($_) })

# --- The languages against each other -----------------------------------------
$gaps = @()
foreach ($lang in ($tables.Keys | Where-Object { $_ -ne $REFERENCE_LANGUAGE })) {
    foreach ($k in $reference.Keys) {
        if (-not $tables[$lang].ContainsKey($k)) { $gaps += ("{0} : {1}" -f $lang, $k) }
    }
    foreach ($k in $tables[$lang].Keys) {
        if (-not $reference.ContainsKey($k)) { $gaps += ("{0} : {1} (absente de {2})" -f $lang, $k, $REFERENCE_LANGUAGE) }
    }
}

# --- The banned words ---------------------------------------------------------
#
# "MACHINE" SAYS NOTHING TO WHOEVER READS. It is our design vocabulary, not that of somebody in front of their
# screen. We speak of "l'ordinateur", or of "tous les comptes" -- depending on what we mean, and that is exactly
# the point: the banned word hid two different ideas.
#
# The exception holds for a COMMAND or an ARGUMENT, never for a sentence: "--scope machine" is a winget flag,
# "-Scope machine" the value the code writes to declare a card's scope (D128). An identifier is not translated.
#
# THE OTHER BANNED WORD IS NOT A FRENCH WORD, nor anybody's word. The two applications are called "l'app serveur"
# and "l'app cliente" -- the web page included: for whoever uses it, the icon and the panel come together, and it
# is the client app that opens the browser. The paths and the file names carried it until 30/09; they no longer do
# (apps/client/, client.ps1). The pattern catches the ISOLATED word only: a path or an identifier still holding it
# would pass, and that is what check-naming counts.


$regles = @(
    @{ Mot = 'machine'; Motif = '(?i)machine';                          Sauf = '(--scope|-Scope)\s+.?machine' }
    @{ Mot = 'tray';    Motif = '(?i)(?<![\w/\.-])tray(?![\w/\.-])'; Sauf = $null }
)
foreach ($r in $regles) {
    foreach ($k in ($reference.Keys | Sort-Object)) {
        $v = $reference[$k]
        if ($v -notmatch $r.Motif) { continue }
        if ($r.Sauf -and $v -match $r.Sauf) { continue }
        $missing += @{ File = 'lang/fr.json'; Line = 0
                       Message = ("mot banni « " + $r.Mot + " » -- " + ("{0} : « {1} »" -f $k, $v)) }
    }
}

# --- Verdict ----------------------------------------------------------------------------
Write-Title 'Libellés'
Write-Info ("{0} déclaré(s), {1} réclamé(s) par le code" -f $reference.Count, $used.Count)

if ($missing.Count) {
    Write-Fail ("{0} clé(s) réclamée(s) et ABSENTE(s) : le message sortirait en « [?...] »." -f $missing.Count)
    foreach ($m in ($missing | Select-Object -First 20)) { Write-Detail ("{0}:{1} -- {2}" -f $m.File, $m.Line, $m.Message) }
}
if ($mismatch.Count) {
    Write-Fail ("{0} appel(s) dont les trous ne correspondent pas." -f $mismatch.Count)
    foreach ($m in ($mismatch | Select-Object -First 20)) { Write-Detail ("{0}:{1} -- {2}" -f $m.File, $m.Line, $m.Message) }
}
if ($gaps.Count) {
    Write-Fail ("{0} écart(s) entre les langues." -f $gaps.Count)
    foreach ($g in ($gaps | Select-Object -First 20)) { Write-Detail $g }
}
if ($orphans.Count) {
    # NOT A FAULT: the front end consumes the same file, and some code paths are rare. We say it, we do not block.
    Write-Warn ("{0} libellé(s) que plus aucun script ne réclame." -f $orphans.Count)
    if ($Detail) { foreach ($o in ($orphans | Sort-Object)) { Write-Detail $o } }
}

$failures = $missing.Count + $mismatch.Count + $gaps.Count
if ($failures) { Write-Outcome -Failures 1; exit 2 }
Write-Ok 'Toutes les clés existent, tous les trous sont remplis.'
Write-Outcome -Failures 0
exit 0
