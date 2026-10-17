# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-front.ps1 - DOES THE PANEL'S PAGE PARSE?

    WHY THIS VERIFIER EXISTS. On 28/09 a rename left "async async function" in index.html. One syntax error, and the
    WHOLE script of the page dies: the panel opens on its loading screen and never leaves it. Vigie no longer started,
    from the point of view of whoever uses it, and no verifier could say so -- they read PowerShell, markup, labels,
    never the JavaScript.

    WHAT IT DOES. It extracts the <script> blocks of the page and hands them to a parser, without executing them. Node
    is not installed under Windows here, but it is inside WSL: it is used when it answers, and its absence is said
    plainly -- a verifier that cannot verify must say so, never keep quiet.

    EVERY PAGE OF THE PANEL, not just index.html. It read one file, so the report page and the no-session page were
    never parsed -- and the report page is the one a rename of the hardware sheet touches. A page nobody checks is a
    page that breaks in front of its reader.

    AND THE SCRIPT FILES THE PAGE POINTS AT (17/10, S25). This read the <script> blocks written INSIDE the page and
    left out those with a src, which was right while the whole script lived in the page. The moment the panel's
    2 824 lines moved to a real file (UI-ASSETS), that rule made this verifier parse nothing at all: it would have
    said "aucun script a parser" about the page it exists to protect. A local file the page loads is the page's
    script, wherever it is stored.
#>
param([switch]$Detail)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
Write-Title 'La page du panneau'

# THE PAGES OF THE PANEL, in the order a reader meets them.
$pages = @('apps/frontend-web/views/index.pode', 'apps/frontend-web/report.html', 'apps/frontend-web/no-session.html')
$missing = @($pages | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repoRoot $_)) })
if ($missing.Count) { Write-Fail ('Page introuvable : ' + ($missing -join ', ')); exit 2 }

function Get-Analyser {
    $node = (Get-Command node -ErrorAction SilentlyContinue).Source
    if ($node) { return @{ Kind = 'windows'; Exe = $node } }
    $wsl = (Get-Command wsl.exe -ErrorAction SilentlyContinue).Source
    if ($wsl) {
        $found = ''
        try { $found = (& $wsl -e bash -lc 'command -v node' 2>$null | Select-Object -First 1) } catch { }
        if ($found) { return @{ Kind = 'wsl'; Exe = $wsl } }
    }
    return $null
}

$analyser = Get-Analyser
if (-not $analyser) {
    Write-Warn "Aucun analyseur JavaScript disponible (ni node sous Windows, ni node dans WSL) : les pages n'ont PAS été vérifiées."
    Write-Info 'Installer Node, ou lancer ce vérificateur depuis une machine qui en a un.'
    exit 0
}

# ONE PAGE, PARSED. It returns @{ Ok; Blocks; Kb; Output } and executes nothing.
function Test-PageScript {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Analyser)
    $html = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    # A VIEW IS RENDERED BEFORE IT IS READ (D132, UI-RENDER). What the browser receives is the RESULT, and the
    # template is not valid JavaScript on its own: the labels arrive as a bare JSON object, so `= $($data.labels);`
    # only becomes a statement once the view is rendered. The engine is Pode's own, with stand-in data.
    if ($Path -like '*.pode') {
        Import-Module Pode -ErrorAction Stop
        $render = & (Get-Module Pode) { Get-Command ConvertFrom-PodeFile }
        $html = & $render -Content $html -Data @{ token = 'x'; version = 'v0.0'; build = '0'; labels = '{}' }
    }
    # THE <script> BLOCKS OF THE PAGE, in order, leaving out those that point at a file.
    $blocs = @([regex]::Matches($html, '(?s)<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>') | ForEach-Object { $_.Groups[1].Value })
    # AND THE FILES IT POINTS AT, in the same order, when they are ours: a relative path next to the page. An
    # address with a scheme belongs to someone else and is not read here.
    # WHERE A RELATIVE ADDRESS POINTS: at the front end's folder, which is what the server serves at "/" -- not at
    # the folder the file happens to sit in. A view lives one level down, in views/, and still writes
    # "assets/js/panel.js" because the browser resolves that against the ADDRESS of the page, which is "/".
    $folder = Split-Path -Parent $Path
    if ($Path -like '*.pode') { $folder = Split-Path -Parent $folder }
    foreach ($m in [regex]::Matches($html, '<script([^>]*)\bsrc="([^"]+)"')) {
        $src = $m.Groups[2].Value
        if ($src -match '^[a-z]+:' -or $src.StartsWith('//')) { continue }
        $file = Join-Path $folder ($src -replace '\?.*$', '')
        if (-not (Test-Path -LiteralPath $file)) { return @{ Ok = $false; Blocks = 0; Kb = 0
                                                            Output = "Script introuvable : $src" } }
        # A MODULE IS NOT A BLOCK OF THE PAGE. It is parsed on its own, with its imports, by Test-ModuleGraph
        # below: glued to the others it would not even parse, since `import` is only legal at the top of a module.
        if ($m.Groups[1].Value -match 'type="module"') { $script:ModuleEntries += $file; continue }
        $blocs += (Get-Content -LiteralPath $file -Raw -Encoding UTF8)
    }
    # A PAGE WITHOUT A SCRIPT IS NOT A FAILURE: a page may be pure markup, and then there is nothing to parse.
    if (-not $blocs.Count) { return @{ Ok = $true; Blocks = 0; Kb = 0; Output = '' } }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('vigie-front-' + [guid]::NewGuid().ToString('N') + '.js')
    # A semicolon between two blocks: they are independent in the page, they must stay independent here.
    [IO.File]::WriteAllText($tmp, ($blocs -join ([Environment]::NewLine + ';' + [Environment]::NewLine)), [Text.UTF8Encoding]::new($false))
    $output = ''
    $code = 1
    if ($Analyser.Kind -eq 'windows') {
        $output = & $Analyser.Exe --check $tmp 2>&1
        $code = $LASTEXITCODE
    } else {
        # The Windows path as WSL sees it: the drive letter becomes /mnt/<letter>, and the separators turn round.
        $unix = '/mnt/' + $tmp.Substring(0, 1).ToLower() + ($tmp.Substring(2).Replace([char]92, [char]47))
        $output = & $Analyser.Exe -e bash -lc ("node --check '" + $unix + "'") 2>&1
        $code = $LASTEXITCODE
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return @{ Ok = ($code -eq 0); Blocks = $blocs.Count
              Kb = [math]::Round((($blocs -join '').Length / 1KB)); Output = $output }
}

# THE MODULES OF THE PANEL, walked from the entry the page loads (D132, UI-MODULES).
#
# Two failures, and only the second one is new. A module must PARSE as a module -- node reads a ".mjs" file that
# way -- and every name it IMPORTS must actually be EXPORTED where it comes from. The second is the one that bit:
# cutting 2 800 lines into modules, an import that points at a name nobody exported kills the WHOLE page at load,
# before the first line runs, and nothing in the syntax says so.
function Test-ModuleGraph {
    param([Parameter(Mandatory)][string[]]$Entries, [Parameter(Mandatory)]$Analyser)
    $seen = @{}
    $queue = [System.Collections.Queue]::new()
    foreach ($e in $Entries) { $queue.Enqueue((Resolve-Path -LiteralPath $e).Path) }
    $problems = @()
    $files = @()
    while ($queue.Count) {
        $file = $queue.Dequeue()
        if ($seen.ContainsKey($file)) { continue }
        $seen[$file] = $true
        $files += $file
        $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        foreach ($i in [regex]::Matches($text, "(?m)^import\s*\{([^}]+)\}\s*from\s*'([^']+)'")) {
            $names = @($i.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $target = Join-Path (Split-Path -Parent $file) $i.Groups[2].Value
            if (-not (Test-Path -LiteralPath $target)) {
                $problems += ((Split-Path -Leaf $file) + " importe un fichier qui n'existe pas : " + $i.Groups[2].Value)
                continue
            }
            $target = (Resolve-Path -LiteralPath $target).Path
            $targetText = Get-Content -LiteralPath $target -Raw -Encoding UTF8
            foreach ($n in $names) {
                $exported = [regex]::IsMatch($targetText, "(?m)^export\s+(?:async\s+)?(?:function|class|const|let|var)\s+[^;]*?\b" + [regex]::Escape($n) + "\b")
                if (-not $exported) {
                    $problems += ((Split-Path -Leaf $file) + " importe « $n » de " + (Split-Path -Leaf $target) + ", qui ne l'exporte pas")
                }
            }
            $queue.Enqueue($target)
        }
    }
    # AND A NAME CALLED WITHOUT BEING IMPORTED, which no parser can see: it is valid JavaScript right up to the
    # moment the button is pressed. Cutting the panel up produced three of them in one go -- a call written inside
    # a template string, which the cutting tool had read as text rather than as code.
    $exported = @{}
    foreach ($file in $files) {
        $t = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        foreach ($e in [regex]::Matches($t, '(?m)^export\s+(?:async\s+)?(?:function|class|const|let|var)\s+([A-Za-z_$][\w$]*)')) {
            $exported[$e.Groups[1].Value] = $file
        }
        # `export let lastUnits=[], lastHost='';` exports TWO names, and the second is as importable as the first.
        foreach ($e in [regex]::Matches($t, '(?m)^export\s+(?:const|let|var)\s+[^;]*?,\s*([A-Za-z_$][\w$]*)\s*=')) {
            $exported[$e.Groups[1].Value] = $file
        }
    }
    foreach ($file in $files) {
        $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        $imported = @{}
        foreach ($i in [regex]::Matches($text, "(?m)^import\s*\{([^}]+)\}")) {
            foreach ($n in ($i.Groups[1].Value -split ',')) { $imported[$n.Trim()] = $true }
        }
        # The code, without its imports, its comments and its quoted text: "card-refresh" is a CSS class, not a
        # call to refresh, and an apostrophe in a French comment is enough to desynchronise a reader of quotes.
        $body = [regex]::Replace($text, '(?m)^import .*$', '')
        $body = [regex]::Replace($body, '(?s)/\*.*?\*/', ' ')
        $body = [regex]::Replace($body, '(?m)//.*$', ' ')
        $body = [regex]::Replace($body, "'(?:\\.|[^'\\])*'", "''")
        $body = [regex]::Replace($body, '"(?:\\.|[^"\\])*"', '""')
        foreach ($n in $exported.Keys) {
            if ($exported[$n] -eq $file -or $imported.ContainsKey($n)) { continue }
            # a module may declare a name of its own that another one also exports: then it is not a borrowing
            if ([regex]::IsMatch($body, '(?m)^\s*(?:export\s+)?(?:async\s+)?(?:function|class|const|let|var)\s+[^;]*?\b' + [regex]::Escape($n) + '\b')) { continue }
            if ([regex]::IsMatch($body, '(?<![\w$.])' + [regex]::Escape($n) + '(?![\w$])')) {
                $problems += ((Split-Path -Leaf $file) + " se sert de « $n » sans l'importer (il vient de " + (Split-Path -Leaf $exported[$n]) + ')')
            }
        }
    }

    # AND EACH ONE PARSES AS A MODULE. The extension is what tells node which language it is reading.
    foreach ($file in $files) {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('vigie-mod-' + [guid]::NewGuid().ToString('N') + '.mjs')
        Copy-Item -LiteralPath $file -Destination $tmp -Force
        if ($Analyser.Kind -eq 'windows') { $out = & $Analyser.Exe --check $tmp 2>&1; $code = $LASTEXITCODE }
        else {
            $unix = '/mnt/' + $tmp.Substring(0, 1).ToLower() + ($tmp.Substring(2).Replace([char]92, [char]47))
            $out = & $Analyser.Exe -e bash -lc ("node --check '" + $unix + "'") 2>&1
            $code = $LASTEXITCODE
        }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if ($code -ne 0) { $problems += ((Split-Path -Leaf $file) + ' ne se parse pas : ' + ($out -join ' ')) }
    }
    return @{ Ok = ($problems.Count -eq 0); Count = $files.Count; Problems = $problems }
}

$script:ModuleEntries = @()
Write-Step 'Syntaxe du script des pages'
$bad = 0
foreach ($rel in $pages) {
    $r = Test-PageScript -Path (Join-Path $repoRoot $rel) -Analyser $analyser
    if ($r.Ok) {
        $what = $(if ($r.Blocks) { "$($r.Blocks) bloc(s), $($r.Kb) Ko" } else { 'aucun script à parser' })
        Write-Ok ($rel + ' : ' + $what + '.')
    } else {
        $bad++
        Write-Fail ($rel + " NE SE PARSE PAS : ouverte dans un navigateur, elle resterait sur son écran de chargement.")
        foreach ($line in @($r.Output | Where-Object { "$_".Trim() })) { Write-Detail "$line" }
    }
}
if ($script:ModuleEntries.Count) {
    Write-Step 'Les modules du panneau'
    $g = Test-ModuleGraph -Entries $script:ModuleEntries -Analyser $analyser
    if ($g.Ok) {
        Write-Ok ("$($g.Count) module(s) : chaque import trouve son export, et chacun se parse.")
    } else {
        $bad++
        Write-Fail "Les modules ne tiennent pas ensemble : la page mourrait au chargement, avant la première ligne."
        foreach ($line in $g.Problems) { Write-Detail $line }
    }
}
<#
    THE SIZE RATCHET (D132, UI-SIZE). IT NEVER GOES UP.

    It is the only mechanism that stops the habit coming back: adding to the file that already exists is what
    produced both of this project's monoliths, index.html at 3 736 lines and common.ps1 at 11 791. No decision
    had allowed it -- and none forbade it either.

    17/10: the ceiling is set at 784, which is the style sheet, the largest piece left after the cut. The
    heaviest script is cards.js at 423 lines. Every cut that follows brings this number down as much.
#>
$PANEL_CEILING = 784
$panelFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'apps/frontend-web') -Recurse -File -Include '*.js', '*.css', '*.pode' -ErrorAction SilentlyContinue)
if ($panelFiles.Count) {
    Write-Step 'La taille des fichiers du panneau'
    $tooBig = @()
    $biggest = 0
    foreach ($f in $panelFiles) {
        $n = (Get-Content -LiteralPath $f.FullName -Encoding UTF8 | Measure-Object).Count
        if ($n -gt $biggest) { $biggest = $n }
        if ($n -gt $PANEL_CEILING) { $tooBig += ('{0} : {1} lignes' -f $f.Name, $n) }
    }
    if ($tooBig.Count) {
        $bad++
        Write-Fail ("Plafond dépassé ($PANEL_CEILING lignes) : un fichier du panneau grossit au lieu d'être découpé (D132, UI-SIZE).")
        foreach ($line in $tooBig) { Write-Detail $line }
    } else {
        Write-Ok ("$($panelFiles.Count) fichier(s), le plus gros à $biggest lignes (plafond $PANEL_CEILING).")
        if ($biggest -lt $PANEL_CEILING) { Write-Info "Le plafond peut descendre à $biggest." }
    }
}
if ($bad) { exit 2 }
Write-Outcome -What 'Les pages du panneau se parsent'
exit 0
