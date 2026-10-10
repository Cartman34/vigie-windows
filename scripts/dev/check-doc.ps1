# @author Florent HAZARD <f.hazard@sowapps.com>
<# check-doc.ps1 -- does the documentation stand up? READ ONLY.

   Intent: judge the documentation's shape, never its text. Two checks, both mechanical:

     1. DEAD LINKS: every relative reference must designate a file that exists.
     2. fr/en SYNCHRONISATION: the two languages tell the same thing, so their STRUCTURE must coincide -- the
        same division into headings, the same tables, the same code blocks, the same number of references. The
        text differs, the framework does not. It is that check which caught an English page asserting that the
        installation does not need administrator rights, while the French said the opposite.

   Usage: pwsh -File .\scripts\dev\check-doc.ps1. Exit codes: 0 = nothing to report; 2 = at least one gap.

   French is the MASTER language (D93): a gap is fixed by bringing the English into line with it, never the other
   way round.
#>
param([switch]$Quiet)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$doc      = Join-Path $repoRoot 'doc'
$problems    = 0

function Write-Line { param([string]$text, [string]$Couleur = 'Gray')
    if (-not $Quiet) { Write-Host $text -ForegroundColor $Couleur } }

# --- 1. Liens morts ---------------------------------------------------------
$exclus = @('.git', 'node_modules', 'dist', 'var', 'local')
$files = Get-ChildItem -Path $repoRoot -Filter '*.md' -Recurse -File |
    Where-Object { $p = $_.FullName; -not ($exclus | Where-Object { $p -like ('*' + [IO.Path]::DirectorySeparatorChar + $_ + [IO.Path]::DirectorySeparatorChar + '*') }) }

$morts = @()
foreach ($f in $files) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($text, '\[[^\]]*\]\(([^)#\s]+)(?:#[^)]*)?\)')) {
        $target = $m.Groups[1].Value
        if ($target -match '^(https?:|mailto:)') { continue }
        $Path = Join-Path (Split-Path $f.FullName -Parent) $target
        if (-not (Test-Path -LiteralPath $Path)) {
            $morts += ((Resolve-Path -LiteralPath $f.FullName -Relative) + '  ->  ' + $target)
        }
    }
}
Write-Line ("{0} fichier(s) markdown lus." -f $files.Count)
if ($morts.Count) {
    $problems = 2
    Write-Line ("{0} lien(s) mort(s) :" -f $morts.Count) 'Red'
    foreach ($x in $morts) { Write-Line ("   " + $x) 'Red' }
} else { Write-Line "Aucun lien mort." 'Green' }

# --- 2. Synchronisation fr / en ---------------------------------------------
function Get-Profil {
    param([string]$Path)
    $text  = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $lines = $text -split "`n"
    # The "translated from the French" mention exists ONLY on the English side: that is deliberate, it does not
    # count as a gap. It spans two lines, the second of which carries the reference -- so both must be set aside,
    # not only the one that announces itself.
    $useful = $lines | Where-Object { $_ -notmatch 'master version' -and $_ -notmatch 'the French page' }
    [pscustomobject]@{
        Titres  = @($useful | Where-Object { $_ -match '^#{1,4} ' }).Count
        Tableau = @($useful | Where-Object { $_ -match '^\|' }).Count
        Code    = @($useful | Where-Object { $_ -match '^```' }).Count
        Renvois = @([regex]::Matches(($useful -join "`n"), '\]\(([^)\s]+)\)') |
                    Where-Object { $_.Groups[1].Value -notmatch '^(https?:|mailto:|#)' }).Count
    }
}

$paires = @()
$paires += ,@((Join-Path $repoRoot 'README.fr.md'), (Join-Path $repoRoot 'README.md'))
$paires += ,@((Join-Path $doc 'fr/README.md'),      (Join-Path $doc 'en/README.md'))
foreach ($sous in @('using', 'operating')) {
    $d = Join-Path $doc ('fr/' + $sous)
    if (-not (Test-Path -LiteralPath $d)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $d -Filter '*.md' -File | Sort-Object Name)) {
        $paires += ,@($f.FullName, (Join-Path $doc ('en/' + $sous + '/' + $f.Name)))
    }
}

$ecarts = 0
foreach ($paire in $paires) {
    $fr, $en = $paire[0], $paire[1]
    $name = (Resolve-Path -LiteralPath $fr -Relative)
    if (-not (Test-Path -LiteralPath $en)) {
        $ecarts++; Write-Line ("SANS JUMEAU  " + $name) 'Yellow'; continue
    }
    $a = Get-Profil -Path $fr
    $b = Get-Profil -Path $en
    $d = @()
    if ($a.Titres  -ne $b.Titres)  { $d += ("titres {0} vs {1}"            -f $a.Titres,  $b.Titres) }
    if ($a.Tableau -ne $b.Tableau) { $d += ("lignes de tableau {0} vs {1}" -f $a.Tableau, $b.Tableau) }
    if ($a.Code    -ne $b.Code)    { $d += ("blocs de code {0} vs {1}"     -f ($a.Code/2), ($b.Code/2)) }
    if ($a.Renvois -ne $b.Renvois) { $d += ("renvois {0} vs {1}"           -f $a.Renvois, $b.Renvois) }
    if ($d.Count) {
        $ecarts++
        Write-Line ("{0,-42} {1}" -f $name, ($d -join ' | ')) 'Yellow'
    }
}
Write-Line ("{0} paire(s) fr/en comparee(s)." -f $paires.Count)
if ($ecarts) {
    if ($problems -eq 0) { $problems = 2 }
    Write-Line ("{0} paire(s) desynchronisee(s). Le francais fait foi (D93)." -f $ecarts) 'Yellow'
} else { Write-Line "Les deux langues ont la meme charpente." 'Green' }

# --- 3. The table of decisions is complete ------------------------------------
#
# It had stopped at D50 and nobody saw it: 48 decisions were missing, in a file that announces that adding a
# decision means adding its number to a line.
# A table of contents that is incomplete is worse than an absent one -- it gives the illusion of having read everything.
$dec = Join-Path $doc 'progress/decisions.md'
if (Test-Path -LiteralPath $dec) {
    $text  = Get-Content -LiteralPath $dec -Raw -Encoding UTF8
    $iSomm  = $text.IndexOf('## Sommaire')
    $iPrem  = $text.IndexOf("`n## D01")
    if ($iSomm -ge 0 -and $iPrem -gt $iSomm) {
        $sommaire = $text.Substring($iSomm, $iPrem - $iSomm)
        $cites  = @([regex]::Matches($sommaire, '\bD\d+(?:bis)?\b') | ForEach-Object { $_.Value })
        $headings = @([regex]::Matches($text, '(?m)^## (D\d+(?:bis)?)') | ForEach-Object { $_.Groups[1].Value }) | Select-Object -Unique
        $absents = @($headings | Where-Object { $cites -notcontains $_ })
        if ($absents.Count) {
            if ($problems -eq 0) { $problems = 2 }
            Write-Line ("{0} decision(s) absente(s) du sommaire : {1}" -f $absents.Count, ($absents -join ' ')) 'Yellow'
        } else {
            Write-Line ("Sommaire des decisions complet ({0} entrees)." -f $headings.Count) 'Green'
        }
    }
}

exit $problems
