# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-naming.ps1 - Le code est en anglais. CLIQUET, pas grand nettoyage. LECTURE SEULE.

    La regle est ancienne (D41) : on parle francais, le code s'ecrit en anglais. Elle a
    ete enfreinte peu a peu, y compris par moi, jusqu'a 310 identifiants francais.

    Ce que ce script ne fait PAS : exiger qu'on repare tout d'un coup. Une renommade
    massive noierait `git blame` sous du bruit pour un gain nul, et casserait du code qui
    marche. Ce qu'il fait : empecher que ca EMPIRE. Le compte ne peut plus monter ; chaque
    fois qu'on baisse, on descend le plafond d'autant. C'est un cliquet : ca ne remonte pas.

    Ce qui est compte : les NOMS -- fonctions, variables, parametres -- ET LES NOMS DE
    FICHIERS. Restent en francais, volontairement : les commentaires, les libelles
    affiches, les messages de journal.

    LES NOMS DE FICHIERS ONT LEUR PROPRE CLIQUET. Le 31/08 j'ai cree « reprise.ps1 » --
    dans le meme quart d'heure ou j'ecrivais la discipline qui l'interdit. La regle etait
    ecrite, relue, recopiee : elle n'etait vérifiée nulle part, et ce script comptait les
    identifiants A L'INTERIEUR des fichiers sans jamais regarder leur nom.

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
<#
    THE FRENCH COMMENT CEILING, measured on 02/09.

    It is the legacy of a conventions page written against the intended rule (D115). We do
    not rewrite it at once -- thousands of touched lines for no gain, and a drowned git
    blame. The ratchet forbids adding any; every conversion lowers the ceiling as much.
#>
$COMMENT_CEILING = 5788
$CEILING = 289

# LE PLAFOND DES NOMS DE FICHIERS. Meme cliquet, compte separe : ceux qui restent sont
# nommes dans des taches planifiees deja posees et dans des raccourcis, donc ils se
# renomment un par un, pas d'un coup.
$FILE_CEILING = 3

$FRENCH_WORDS = @(
    'marquer','appliquer','repartir','verrou','carte','compte','tache','chemin',
    'fichier','dossier','ligne','colonne','hauteur','largeur','bouton','fenetre',
    'sonde','lisere','groupe','manquant','manquement','echec','reussi','occupe',
    'racine','cible','etat','donnee','reglage','recuperation','depot','voie',
    'piege','porteur','minuteur','puce','titre','resume','mesurer','ecrire',
    'creer','rendre','suivre','aucun','deja','avant','apres','faits','morceaux'
)

<#
    LE LEXIQUE DES NOMS DE FICHIERS est plus large que celui des identifiants : un nom de
    fichier porte souvent le GESTE (« reprise », « sauvegarde », « deploiement »), et pas
    le vocabulaire technique du code. C'est exactement ce qui est passe le 31/08 : aucun
    des mots de la liste ci-dessus n'apparaissait dans « reprise.ps1 ».

    « atelier » n'y est PAS : c'est le nom propre de l'outil de developpement (D28), pas
    un mot francais qu'on aurait laisse trainer.
#>
$FRENCH_FILE_WORDS = $FRENCH_WORDS + @(
    'reprise','essai','sauvegarde','deploiement','journal','outil','aide','demarrage',
    'arret','jour','nettoyage','verification','securite','utilisateur','parametre',
    'liste','recherche','lancement','preparation','correction','controle',
    'comptes','installation','mise','relance','affichage','langue','erreur'
)

# The COMMENT lexicon: function words, the ones no French sentence can avoid. Looking for
# technical vocabulary instead would flag English too.
# WORDS THAT ARE ALSO ENGLISH ARE NOT IN THE LEXICON. "on", "car" and "plus" were, and an
# English comment saying "on 03/09" counted as French: the ratchet then refuses the very
# conversion it exists to obtain. A word only belongs here if reading it settles the
# question.
$FRENCH_COMMENT_WORDS = @(
    'le','la','les','un','une','des','du','de','et','ou','qui','que','quoi','dont','pas',
    'pour','dans','avec','sans','sous','est','sont','etre','ete','fait','faire',
    'il','elle','nous','vous','ils','elles','ce','cette','ces','celui','celle',
    'mais','donc','quand','alors','ainsi','moins','tout','toute','tous',
    'chaque','meme','autre','deja','encore','jamais','toujours','ici','la-bas','par'
)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
$skipped   = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')   # .claude : les worktrees y vivent ; var : le clone du service aussi (D112)
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

<#
    LES NOMS DE FICHIERS. Meme lexique, meme cliquet.

    On ne regarde que ce qu'on ECRIT : scripts et bibliotheques. Les documents restent en
    francais -- c'est la langue du projet -- et les libelles aussi.
#>
$fileTotal = 0
$frenchFiles = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.psm1','*.cmd','*.vbs' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($skipped | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name).ToLowerInvariant()
    foreach ($word in $FRENCH_FILE_WORDS) {
        if ($base -match ('(^|[-_.])' + $word)) { $fileTotal++; $frenchFiles += $rel; break }
    }
}

<#
    COMMENTS FOLLOW THE SAME RULE (D115).

    A comment is part of the code and is read with it, so it is written in English. The
    conventions page long said the opposite and the whole codebase complied -- hence the
    same ratchet as for identifiers, rather than a mass rewrite.

    A comment LINE counts as French as soon as it carries one word of the lexicon below.
    Displayed labels and log messages are not comments: they stay in French, and a line of
    code holding one is never counted.
#>
$commentTotal = 0
$commentPerFile = @{}
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.psd1' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($skipped | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $n = 0
    $inBlock = $false
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $trimmed = "$line".Trim()
        if ($trimmed -like '<#*') { $inBlock = $true }
        $isComment = $inBlock -or $trimmed.StartsWith('#')
        if ($trimmed -like '*#>*') { $inBlock = $false }
        if (-not $isComment) { continue }
        $lower = $trimmed.ToLowerInvariant()
        foreach ($word in $FRENCH_COMMENT_WORDS) {
            if ($lower -match ('(^|[^a-z])' + $word + '([^a-z]|$)')) { $n++; $commentTotal++; break }
        }
    }
    if ($n) { $commentPerFile[$rel] = $n }
}

# A RATCHET THAT REPORTS WITHOUT REFUSING IS NOT A RATCHET. This one said the ceiling was
# exceeded and still exited 0: I added twelve French comment lines on 03/09 and the check
# was green. The verdict waits for the end -- all three counts get said first -- but it now
# falls.
$commentExceeded = $false
Write-Info (Get-Label 'check-naming.commentaires-francais-plafond' $commentTotal $COMMENT_CEILING)
if ($commentTotal -gt $COMMENT_CEILING) {
    $commentExceeded = $true
    Write-Fail (Get-Label 'check-naming.commentaires-au-dessus' ($commentTotal - $COMMENT_CEILING))
    if ($Detail) {
        foreach ($e in ($commentPerFile.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12)) {
            Write-Detail ("{0,10}  {1}" -f $e.Value, $e.Key)
        }
    }
} elseif ($commentTotal -lt $COMMENT_CEILING) {
    Write-Ok (Get-Label 'check-naming.commentaires-en-baisse' ($COMMENT_CEILING - $commentTotal))
}

Write-Info (Get-Label 'check-naming.identifiants-francais-plafond' $total $CEILING)
Write-Info (Get-Label 'check-naming.fichiers-francais-plafond' $fileTotal $FILE_CEILING)

if ($Detail) {
    foreach ($e in ($perFile.GetEnumerator() | Sort-Object Value -Descending)) {
        Write-Info ("{0,5}  {1}" -f $e.Value, $e.Key)
    }
    # LE « -join » ETAIT HORS DE LA PARENTHESE : Get-Label recevait le tableau, et
    # affichait « System.Object[] ». Un verificateur qui compte sans pouvoir dire QUOI
    # ne sert qu'a rendre le verdict, pas a corriger.
    $liste = (($names.GetEnumerator() | Sort-Object Value -Descending |
               Select-Object -First 30 | ForEach-Object { $_.Key }) -join ', ')
    Write-Host (Get-Label 'check-naming.noms' $liste) -ForegroundColor DarkGray
}

if ($fileTotal -gt $FILE_CEILING) {
    Write-Fail (Get-Label 'check-naming.fichiers-plafond-depasse' ($fileTotal - $FILE_CEILING))
    foreach ($rel in $frenchFiles) { Write-Detail $rel }
    Write-Warn (Get-Label 'check-naming.un-fichier-se-nomme-en-anglais')
    exit 2
}
if ($fileTotal -lt $FILE_CEILING) {
    Write-Ok (Get-Label 'check-naming.fichiers-de-moins' ($FILE_CEILING - $fileTotal) $fileTotal)
}

if ($total -gt $CEILING) {
    Write-Fail (Get-Label 'check-naming.le-plafond-est-depasse' ($total - $CEILING))
    Write-Warn (Get-Label 'check-naming.les-nouveaux-noms-ecrivent')
    exit 2
}
if ($commentExceeded) { exit 2 }
if ($total -lt $CEILING) {
    Write-Ok (Get-Label 'check-naming.de-moins-que-le' ($CEILING - $total) $total)
    exit 0
}
Write-Ok (Get-Label 'check-naming.plafond-tenu-aucun-identifiant')
exit 0
