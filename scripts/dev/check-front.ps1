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
$pages = @('apps/frontend-web/index.html', 'apps/frontend-web/report.html', 'apps/frontend-web/no-session.html')
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
    # THE <script> BLOCKS OF THE PAGE, in order, leaving out those that point at a file.
    $blocs = @([regex]::Matches($html, '(?s)<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>') | ForEach-Object { $_.Groups[1].Value })
    # AND THE FILES IT POINTS AT, in the same order, when they are ours: a relative path next to the page. An
    # address with a scheme belongs to someone else and is not read here.
    $folder = Split-Path -Parent $Path
    foreach ($m in [regex]::Matches($html, '<script[^>]*\bsrc="([^"]+)"')) {
        $src = $m.Groups[1].Value
        if ($src -match '^[a-z]+:' -or $src.StartsWith('//')) { continue }
        $file = Join-Path $folder ($src -replace '\?.*$', '')
        if (-not (Test-Path -LiteralPath $file)) { return @{ Ok = $false; Blocks = 0; Kb = 0
                                                            Output = "Script introuvable : $src" } }
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
if ($bad) { exit 2 }
Write-Outcome -What 'Les pages du panneau se parsent'
exit 0
