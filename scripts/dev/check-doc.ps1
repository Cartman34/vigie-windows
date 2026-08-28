<# check-doc.ps1 - La documentation tient-elle debout ? LECTURE SEULE.

   Deux controles, tous deux mecaniques -- ils ne jugent pas le texte, seulement sa
   charpente :

     1. LIENS MORTS : tout renvoi relatif doit designer un fichier qui existe.
     2. SYNCHRONISATION fr/en : les deux langues racontent la meme chose, donc leur
        STRUCTURE doit coincider -- meme decoupage en titres, memes tableaux, memes
        blocs de code, meme nombre de renvois. Le texte differe, la charpente non.
        C'est ce controle qui a rattrape une page anglaise affirmant que l'install
        n'exige pas les droits administrateur, alors que le francais disait l'inverse.

   Le francais est la langue MAITRESSE (D93) : un ecart se corrige en alignant
   l'anglais sur lui, jamais l'inverse.

   Codes de retour : 0 = rien a signaler ; 2 = au moins un ecart.
#>
param([switch]$Silencieux)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$doc      = Join-Path $repoRoot 'doc'
$souci    = 0

function Ecrire { param([string]$Texte, [string]$Couleur = 'Gray')
    if (-not $Silencieux) { Write-Host $Texte -ForegroundColor $Couleur } }

# --- 1. Liens morts ---------------------------------------------------------
$exclus = @('.git', 'node_modules', 'dist', 'var', 'local')
$fichiers = Get-ChildItem -Path $repoRoot -Filter '*.md' -Recurse -File |
    Where-Object { $p = $_.FullName; -not ($exclus | Where-Object { $p -like ('*' + [IO.Path]::DirectorySeparatorChar + $_ + [IO.Path]::DirectorySeparatorChar + '*') }) }

$morts = @()
foreach ($f in $fichiers) {
    $texte = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($texte, '\[[^\]]*\]\(([^)#\s]+)(?:#[^)]*)?\)')) {
        $cible = $m.Groups[1].Value
        if ($cible -match '^(https?:|mailto:)') { continue }
        $chemin = Join-Path (Split-Path $f.FullName -Parent) $cible
        if (-not (Test-Path -LiteralPath $chemin)) {
            $morts += ((Resolve-Path -LiteralPath $f.FullName -Relative) + '  ->  ' + $cible)
        }
    }
}
Ecrire ("{0} fichier(s) markdown lus." -f $fichiers.Count)
if ($morts.Count) {
    $souci = 2
    Ecrire ("{0} lien(s) mort(s) :" -f $morts.Count) 'Red'
    foreach ($x in $morts) { Ecrire ("   " + $x) 'Red' }
} else { Ecrire "Aucun lien mort." 'Green' }

# --- 2. Synchronisation fr / en ---------------------------------------------
function Get-Profil {
    param([string]$Chemin)
    $texte  = Get-Content -LiteralPath $Chemin -Raw -Encoding UTF8
    $lignes = $texte -split "`n"
    # La mention « traduit du francais » n'existe QUE cote anglais : c'est voulu, elle ne
    # compte pas comme un ecart. Elle tient sur deux lignes, dont la seconde porte le
    # renvoi -- il faut donc ecarter les deux, pas seulement celle qui s'annonce.
    $utiles = $lignes | Where-Object { $_ -notmatch 'master version' -and $_ -notmatch 'the French page' }
    [pscustomobject]@{
        Titres  = @($utiles | Where-Object { $_ -match '^#{1,4} ' }).Count
        Tableau = @($utiles | Where-Object { $_ -match '^\|' }).Count
        Code    = @($utiles | Where-Object { $_ -match '^```' }).Count
        Renvois = @([regex]::Matches(($utiles -join "`n"), '\]\(([^)\s]+)\)') |
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
    $nom = (Resolve-Path -LiteralPath $fr -Relative)
    if (-not (Test-Path -LiteralPath $en)) {
        $ecarts++; Ecrire ("SANS JUMEAU  " + $nom) 'Yellow'; continue
    }
    $a = Get-Profil -Chemin $fr
    $b = Get-Profil -Chemin $en
    $d = @()
    if ($a.Titres  -ne $b.Titres)  { $d += ("titres {0} vs {1}"            -f $a.Titres,  $b.Titres) }
    if ($a.Tableau -ne $b.Tableau) { $d += ("lignes de tableau {0} vs {1}" -f $a.Tableau, $b.Tableau) }
    if ($a.Code    -ne $b.Code)    { $d += ("blocs de code {0} vs {1}"     -f ($a.Code/2), ($b.Code/2)) }
    if ($a.Renvois -ne $b.Renvois) { $d += ("renvois {0} vs {1}"           -f $a.Renvois, $b.Renvois) }
    if ($d.Count) {
        $ecarts++
        Ecrire ("{0,-42} {1}" -f $nom, ($d -join ' | ')) 'Yellow'
    }
}
Ecrire ("{0} paire(s) fr/en comparee(s)." -f $paires.Count)
if ($ecarts) {
    if ($souci -eq 0) { $souci = 2 }
    Ecrire ("{0} paire(s) desynchronisee(s). Le francais fait foi (D93)." -f $ecarts) 'Yellow'
} else { Ecrire "Les deux langues ont la meme charpente." 'Green' }

# --- 3. Le sommaire des decisions est complet -------------------------------
#
# Il s'etait arrete a D50 et personne ne l'a vu : 48 decisions manquaient a l'appel,
# dans un fichier qui annonce « ajouter une decision = ajouter son numero a une ligne ».
# Un sommaire incomplet est pire qu'absent -- il donne l'illusion d'avoir tout lu.
$dec = Join-Path $doc 'progress/decisions.md'
if (Test-Path -LiteralPath $dec) {
    $texte  = Get-Content -LiteralPath $dec -Raw -Encoding UTF8
    $iSomm  = $texte.IndexOf('## Sommaire')
    $iPrem  = $texte.IndexOf("`n## D01")
    if ($iSomm -ge 0 -and $iPrem -gt $iSomm) {
        $sommaire = $texte.Substring($iSomm, $iPrem - $iSomm)
        $cites  = @([regex]::Matches($sommaire, '\bD\d+(?:bis)?\b') | ForEach-Object { $_.Value })
        $titres = @([regex]::Matches($texte, '(?m)^## (D\d+(?:bis)?)') | ForEach-Object { $_.Groups[1].Value }) | Select-Object -Unique
        $absents = @($titres | Where-Object { $cites -notcontains $_ })
        if ($absents.Count) {
            if ($souci -eq 0) { $souci = 2 }
            Ecrire ("{0} decision(s) absente(s) du sommaire : {1}" -f $absents.Count, ($absents -join ' ')) 'Yellow'
        } else {
            Ecrire ("Sommaire des decisions complet ({0} entrees)." -f $titres.Count) 'Green'
        }
    }
}

exit $souci
