<#
    check-naming.ps1 - Le code est en anglais. CLIQUET, pas grand nettoyage. LECTURE SEULE.

    La regle est ancienne (D41) : on parle francais, le code s'ecrit en anglais. Elle a
    ete enfreinte peu a peu, y compris par moi, jusqu'a 310 identifiants francais.

    Ce que ce script ne fait PAS : exiger qu'on repare tout d'un coup. Une renommade
    massive noierait `git blame` sous du bruit pour un gain nul, et casserait du code qui
    marche. Ce qu'il fait : empecher que ca EMPIRE. Le compte ne peut plus monter ; chaque
    fois qu'on baisse, on descend le plafond d'autant. C'est un cliquet : ca ne remonte pas.

    Ce qui est compte : les NOMS -- fonctions, variables, parametres. Restent en francais,
    volontairement : les commentaires, les libelles affiches, les messages de journal.

    Le lexique ne retient que des mots SANS ambiguite. « source », « note », « archive »,
    « placement », « format » existent dans les deux langues : les compter punirait du
    code anglais correct.

    Usage :
      pwsh -File .\scripts\dev\check-naming.ps1            # verdict
      pwsh -File .\scripts\dev\check-naming.ps1 -Detail    # ou ils sont

    Codes de retour : 0 = le plafond est tenu ; 2 = il est depasse.
#>
param(
    # Lister les fichiers et les noms trouves.
    [switch] $Detail
)
$ErrorActionPreference = 'Stop'

# LE PLAFOND. On le baisse a chaque fois qu'on renomme, jamais on ne le monte.
$CEILING = 304

$FRENCH_WORDS = @(
    'marquer','appliquer','repartir','verrou','carte','compte','tache','chemin',
    'fichier','dossier','ligne','colonne','hauteur','largeur','bouton','fenetre',
    'sonde','lisere','groupe','manquant','manquement','echec','reussi','occupe',
    'racine','cible','etat','donnee','reglage','recuperation','depot','voie',
    'piege','porteur','minuteur','puce','titre','resume','mesurer','ecrire',
    'creer','rendre','suivre','aucun','deja','avant','apres','faits','morceaux'
)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$skipped   = @('.git', 'dist', 'node_modules', 'local')
$pattern    = 'function\s+([A-Za-z][\w-]*)|\$([a-zA-Z][\w]*)\s*=|(?:let|const|var|function)\s+([a-zA-Z][\w]*)'

$total = 0
$perFile = @{}
$names = @{}

foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.html','*.psd1' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($skipped | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    $n = 0
    foreach ($m in [regex]::Matches($text, $pattern)) {
        $name = ''
        foreach ($g in 1..3) { if ($m.Groups[$g].Success -and $m.Groups[$g].Value) { $name = $m.Groups[$g].Value; break } }
        if (-not $name) { continue }
        $lower = $name.ToLowerInvariant()
        foreach ($word in $FRENCH_WORDS) {
            if ($lower.Contains($word)) {
                $n++; $total++
                if (-not $names.ContainsKey($name)) { $names[$name] = 0 }
                $names[$name]++
                break
            }
        }
    }
    if ($n) { $perFile[$rel] = $n }
}

Write-Host ""
Write-Host ("Identifiants francais : {0}  (plafond {1})" -f $total, $CEILING) -ForegroundColor Cyan

if ($Detail) {
    Write-Host ""
    foreach ($e in ($perFile.GetEnumerator() | Sort-Object Value -Descending)) {
        Write-Host ("{0,5}  {1}" -f $e.Value, $e.Key)
    }
    Write-Host ""
    Write-Host ("Noms : " + (($names.GetEnumerator() | Sort-Object Value -Descending |
                              Select-Object -First 20 | ForEach-Object { $_.Key }) -join ', ')) -ForegroundColor DarkGray
}

Write-Host ""
if ($total -gt $CEILING) {
    Write-Host ("Le plafond est depasse de {0} : du code francais a ete AJOUTE." -f ($total - $CEILING)) -ForegroundColor Red
    Write-Host "Les nouveaux noms s'ecrivent en anglais (D41). Relancez avec -Detail pour voir ou." -ForegroundColor Yellow
    exit 2
}
if ($total -lt $CEILING) {
    Write-Host ("{0} de moins que le plafond : descendez CEILING a {1} dans ce script." -f ($CEILING - $total), $total) -ForegroundColor Green
    exit 0
}
Write-Host "Plafond tenu : aucun identifiant francais de plus." -ForegroundColor Green
exit 0
