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
#>
param([switch]$Detail)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
Write-Title 'La page du panneau'

$page = Join-Path $repoRoot 'apps/frontend-web/index.html'
if (-not (Test-Path -LiteralPath $page)) { Write-Fail "Page introuvable : $page"; exit 2 }

# THE <script> BLOCKS OF THE PAGE, in order, leaving out those that point at a file.
$html = Get-Content -LiteralPath $page -Raw -Encoding UTF8
$blocs = @([regex]::Matches($html, '(?s)<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>') | ForEach-Object { $_.Groups[1].Value })
if (-not $blocs.Count) { Write-Fail 'Aucun bloc <script> dans la page : lecture impossible.'; exit 2 }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('vigie-front-' + [guid]::NewGuid().ToString('N') + '.js')
# A semicolon between two blocks: they are independent in the page, they must stay independent here.
[IO.File]::WriteAllText($tmp, ($blocs -join ([Environment]::NewLine + ';' + [Environment]::NewLine)), [Text.UTF8Encoding]::new($false))

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
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Write-Warn "Aucun analyseur JavaScript disponible (ni node sous Windows, ni node dans WSL) : la page n'a PAS été vérifiée."
    Write-Info 'Installer Node, ou lancer ce vérificateur depuis une machine qui en a un.'
    exit 0
}

$output = ''
$code = 1
if ($analyser.Kind -eq 'windows') {
    $output = & $analyser.Exe --check $tmp 2>&1
    $code = $LASTEXITCODE
} else {
    # The Windows path as WSL sees it: C:\Temp\x.js becomes /mnt/c/Temp/x.js.
    $unix = '/mnt/' + $tmp.Substring(0, 1).ToLower() + ($tmp.Substring(2) -replace '\\', '/')
    $output = & $analyser.Exe -e bash -lc ("node --check '" + $unix + "'") 2>&1
    $code = $LASTEXITCODE
}
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

Write-Step 'Syntaxe du script de la page'
if ($code -eq 0) {
    Write-Ok ("La page se parse : $($blocs.Count) bloc(s), " + [math]::Round((($blocs -join '').Length / 1KB)) + ' Ko.')
    Write-Outcome -What 'La page du panneau se parse'
    exit 0
}
Write-Fail 'La page NE SE PARSE PAS : ouverte dans un navigateur, elle resterait sur son écran de chargement.'
foreach ($line in @($output | Where-Object { "$_".Trim() })) { Write-Detail "$line" }
exit 2
