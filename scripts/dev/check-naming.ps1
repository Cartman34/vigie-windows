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
$COMMENT_CEILING = 5580

# 08/10: the first slice, and above all the PROOF that makes the rest cheap. Translating a comment changes no
# behaviour -- PROVIDED only comments were translated. So the file is stripped of every comment, block and
# end-of-line alike, through the token stream rather than a regular expression, and the bare code must come back
# byte for byte identical. Nothing has to be executed: if not one line of code differs, there is nothing to prove.
# That also reaches the files an identifier rename cannot touch -- the two that open a window -- because this
# proof never runs them. The wsl module went first, 23 lines, as the sample.
<#
    THE IDENTIFIER CEILING -- RECOUNTED ON 29/09, BECAUSE THE COUNTER WAS HALF-BLIND.

    The owner read "$state.RecapVu" in code I had just delivered and asked the only question that mattered: "you allow
    yourself a lot of drift, don't you?" He was right, and the ratchet had said nothing. Three blind spots:

      - it only looked at an assignment to a bare variable, at "function Name" and at the JavaScript declarations, so
        PARAMETERS -- a param block declaring Ouvre -- and TYPED variables were never read;
      - it never looked at an assigned PROPERTY, so a state object receiving RecapVu was invisible;
      - its lexicon held sixty words, and none of mine: partie, jeu, valeur, jours, ordre, nom, duree, seuil...

    Widening it moved the count from 277 to 481 without a single name being added: the same debt, finally measured. The
    thirty-one names of the 28/09 batch were then renamed, which brings it to 450. THAT is the ceiling. It is a
    RECOUNT, not a permission: it has never been allowed to rise, and it still is not.

    07/10: three files cleared -- vigie-fetch.ps1, check-probes.ps1 and disk-scan.worker.ps1 -- and the count fell to
    404. Each one was PROVEN by running it before and after on the same input and comparing the output, because a
    rename that parses can still be wrong: the day before, renaming New-Noeud's $Chemin parameter without its -Chemin
    call site left a file that parsed and scanned one folder instead of four. No checker here catches that -- they
    read code, they do not run workers -- so a rename is now paired with an execution comparison, and the slice is
    sized by what can be run, not by what can be edited.

    07/10, same day: common.ps1 cleared of its internal names and the count falls to 296. It held 127 of the 404 --
    the library every probe and every action reads, and the one whose style every new file copies, so it is what
    REPRODUCED the debt. 108 names went; what stays is what crosses the repository: four parameters (-Chemin,
    -Comptes, -Etat) and four contract keys (echec, groupe, libelle, dejaFaite) that index.html and sentinelles.html
    read. Those change a protocol between two apps, and that is a separate decision.

    Two mechanical guards were built for it, because 10 000 lines cannot be judged by eye: one refuses to merge a
    name onto an existing one unless NO scope uses both (55 merges checked, 2 refused and renamed otherwise), and
    the renamer now fails closed -- a guard that could throw had silently emptied every variable name in the file.

    07/10, the panel's page: 296 -> 249. index.html holds no AST tool and 4 000 lines where "card" appears 140 times
    as a CSS class, an attribute and a label -- one of those forms only is code. So the page is CUT UP instead of
    searched: comments, strings, template literals with their ${}, regular-expression literals, and the rest, which
    is code. Only an identifier is renamed, never a member (x.titre, a key the back end writes) nor an object key.
    Without scope analysis the safety is elsewhere: a target name must be ABSENT from the code, so no two things can
    merge in any scope -- which forced cardEl, uiState, fieldCount rather than card, state, rows, all three taken.
    One trap found by the cutting: "u.enabled ? lignes : ..." puts a colon after a name that is a VARIABLE, and
    skipping it would have renamed the declaration and left the use hanging.

    07/10, the rest of what can be RUN: 249 -> 174. The three French parameters of the library went across the whole
    repository at once -- -Chemin, -Comptes and -Etat became -Path, -Accounts and -State in common.ps1 and in the ten
    files that called them, because a parameter is only renamed on both faces at the same time. Then the two probes,
    check-doc, install-dev and build-release, each proven by running it: the same 19 probes and 21 modules, the same
    verifier output to the character, the same 232-file archive.

    WHAT STAYS, AND WHY, SO NOBODY LOOKS FOR IT AGAIN: show-confirm.ps1 (17) and apps/client/client.ps1 (16) open a
    window. Neither can be run before and after without putting something on the owner's screen, and a rename here is
    proven by running the file -- not by the fact that it parses. They will go the day their proof does not cost him
    a window, and not before: 33 of the 121 are there.

    Same day again -- the probes, the actions, the workers and the command-line tool: 174 -> 121, each one run before
    and after on the same input, with the same 19 probes, the same 21 modules and the same Get-State. server.ps1
    keeps its five: it only ever runs as the installed server app, so its proof would be a deployment, and a
    deployment delivers, it does not check.

    07/10, the tail: 121 -> 70. Thirty files carrying one to three names each, swept with a single map applied file
    by file -- each file only ever sees the names it uses. Every one passed the scope checker first, and the two it
    refused (client.ps1, install-autostart.ps1) were left alone rather than renamed on a hunch. Proof: check-all
    identical to the character once the durations are removed, the same 19 probes, the same Get-State, and
    vigie-comptes, debug and decisions giving the same output with the same exit codes.

    WHAT IS LEFT, ALL OF IT, SO NOBODY COUNTS IT AGAIN: 33 in show-confirm.ps1 and client.ps1, which open a window;
    5 in server.ps1 and 2 in install.ps1, which only run installed; 15 contract KEYS that cross between the back end
    and the page (index.html, common.ps1, rapport.html), which are a protocol change, not a rename; and 15 scattered
    over a dozen files, each a key or a parameter of the same kind. None of them is reachable by running a file
    here, which is the rule this count now obeys.
#>
$CEILING = 70

# THE FILE-NAME CEILING, AT ZERO SINCE 08/10.
#
# The three that were left -- comptes.probe.ps1, vigie-comptes.ps1, vigie-diag-compte.ps1 -- were to be renamed one
# at a time because they were believed to be named in scheduled tasks already registered. Checked rather than
# assumed: every reference lives in the repository, and one of them was not in the code but in the LABELS, whose
# key carries the file name as a prefix (check-labels requires it) -- "vigie-comptes.echec" had to become
# "vigie-accounts.echec" in the same move, or the panel would lose its sentences.
#
# A consequence that is not a defect: renaming a PER-ACCOUNT probe empties its cache entries, whose key is
# "<probe>@<account>" (D109). The Accounts card therefore renders empty until the first request from an account
# rebuilds it -- seen, then verified by asking for the state as "fhaza": two fields, four actions, as before.
$FILE_CEILING = 0

# THE THIRD LANGUAGE (D41). PowerShell answers for the Windows tools -- that is what it is
# here for; everything else is PHP. Python is not forbidden, but its use must be argued and
# bounded, so a new .py file is a DECISION, never a habit.
#
# Two remained, both mine, written before a context compaction erased the rule from my memory: the icon generators.
# 07/10: the client app's icons left Python for generate-icons.ps1 and GDI+, which ships with Windows, where Pillow
# had to be installed on any machine that might redraw the mark -- and D41 says a Windows tool is written in
# PowerShell. The drawing was compared size by size against what Pillow produced: 2 to 5 of deviation out of 255,
# the mark identical to the eye on the three states.
#
# ONE REMAINS, and it is argued rather than hidden: generate-icon-font.py builds vigie-icons.ttf through fontTools.
# Converting it means writing a TrueType writer -- glyf, loca, cmap, head, hhea, hmtx, maxp, name, post, OS/2 and
# their checksums -- because neither .NET nor PHP can write a font. That is a disproportionate rewrite for a
# generator run when an icon changes, so the ceiling stands at one and the file says why in its own header.
$PYTHON_CEILING = 1

<#
    AND A FOURTH COUNT: THE WORD « tray », WHICH IS AT ZERO AND STAYS THERE (D108, S06).

    Both applications are named « l'app serveur » and « l'app cliente ». « tray » was banned from displayed text on
    29/08 and kept living in the folders, the files, the keys and the identifiers -- 37 files still carried it on
    30/09, so nobody reading the code learned the vocabulary the product uses. Everything was renamed that day:
    apps/client/, client.ps1, Get-ClientHeartbeat, client.alive, the label keys.

    check-labels refuses the ISOLATED word in what is displayed; this count refuses it EVERYWHERE ELSE -- inside a
    path, a name, an identifier -- which is exactly what check-labels lets through by design. A ceiling of zero, so
    the word cannot come back one file at a time.
#>
$TRAY_CEILING = 0

<#
    THE TERM I INVENTED AND NEVER HAD VALIDATED (D129, subject S17).

    I named the mechanism that has a task run in an account's session, then wrote that name into the code, the logs,
    the design and the operations inventory. The glossary held thirty-two words and not that one, for the plain
    reason that it had never been presented: the owner could neither read it nor refuse it.

    The validated words say which app runs the task, the way the two apps are already named. The function and the
    exchange files were renamed with them.

    A ceiling of zero, on the French term and on the identifier alike, so neither comes back one file at a time.
#>
$DESKTOP_CEILING = 0

$FRENCH_WORDS = @(
    'marquer','appliquer','repartir','verrou','carte','compte','tache','chemin',
    'fichier','dossier','ligne','colonne','hauteur','largeur','bouton','fenetre',
    'sonde','lisere','groupe','manquant','manquement','echec','reussi','occupe',
    'racine','cible','etat','donnee','reglage','recuperation','depot','voie',
    'piege','porteur','minuteur','puce','titre','resume','mesurer','ecrire',
    'creer','rendre','suivre','aucun','deja','avant','apres','faits','morceaux',
    'partie','parties','jeu','ferme','permis','ouvre','valeur','valeurs','toutes','noms',
    'jours','duree','attente','sortie','entree','ordre','ordres','libelle','retrait',
    'demande','demarrage','arret','vus','recue','fermeture','ouverture','plafond',
    'geneur','moyenne','nombre','taille','seuil','texte','icone','nom','lourde','utile',
    'cadence','bouchon','silencieux','fenetres','gourmand'
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
$pattern    = 'function\s+([A-Za-z][\w-]*)|\$([a-zA-Z][\w]*)\s*=|(?:let|const|var|function)\s+([a-zA-Z][\w]*)|\]\s*\$([a-zA-Z][\w]*)|\.([A-Za-z][\w]*)\s*='

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
        foreach ($g in 1..5) { if ($m.Groups[$g].Success -and $m.Groups[$g].Value) { $name = $m.Groups[$g].Value; break } }
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

# THE WORD « tray », wherever it is written: content and file name alike, over the same files as above.
$trayTotal = 0
$trayFiles = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.html','*.psd1','*.php','*.py','*.json','*.yaml','*.cmd' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($skipped | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $n = 0
    if ($rel -match '(?i)tray') { $n++ }
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    # THREE FILES STATE THE RULE, and stating it means writing the word. check-labels owns what is DISPLAYED and
    # already refuses the isolated word in lang/fr.json; this count owns everything else.
    $statesTheRule = @('scripts/dev/check-labels.ps1', 'scripts/dev/check-naming.ps1', 'lang/fr.json')
    if ($text -and $statesTheRule -notcontains $rel) {
        $n += ([regex]::Matches($text, '(?i)tray')).Count
    }
    if ($n) { $trayTotal += $n; $trayFiles += $rel }
}

# THE INVENTED TERM, wherever it is written (D129): the French words and the identifier that carried the notion.
# `desktop-heap` is Windows' own "Desktop Heap", named by Windows and not by me, so it is not counted.
$desktopTotal = 0
$desktopFiles = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.html','*.psd1','*.php','*.py','*.json','*.yaml','*.cmd','*.md' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($skipped | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    # THE PLACES THAT STATE THE RULE write the term in order to forbid it: this file, the decision that settles it,
    # the glossary entry that replaces it, and the dated records that say what was written that day.
    $statesIt = @('scripts/dev/check-naming.ps1', 'doc/progress/decisions.md',
                  'doc/en/developing/glossary.md', 'notes/subjects.md')
    if ($statesIt -contains $rel -or $rel -like 'notes/evidence/*') { continue }
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    $n = ([regex]::Matches($text, '(?i)ordres? de bureau')).Count
    $n += ([regex]::Matches($text, 'DesktopAction')).Count
    $n += ([regex]::Matches($text, "desktop-(?!heap)")).Count
    if ($n) { $desktopTotal += $n; $desktopFiles += $rel }
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
        <#
            A HEADER IS A DECLARATION, NOT PROSE. "# @droits: tous", "# @execution: session", "# @libelle: ..." are
            READ BY THE CODE -- check-operations parses them, the loader obeys them -- and their keywords are French
            by construction. Counting them meant that adding one action, header included, broke the ratchet while not
            one sentence of French had been written (29/09).
        #>
        if ($trimmed -match '^#\s*@[a-zA-Z]+\s*:') { continue }
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
$pythonExceeded = $false

# THE REPOSITORY'S PYTHON FILES, counted like the rest: on what git actually tracks.
$pythonFiles = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.py' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($skipped | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $pythonFiles += $rel
}
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
Write-Info (Get-Label 'check-naming.fichiers-python-plafond' $pythonFiles.Count $PYTHON_CEILING)
Write-Info (Get-Label 'check-naming.tray-plafond' $trayTotal $TRAY_CEILING)
Write-Info (Get-Label 'check-naming.terme-invente-plafond' $desktopTotal $DESKTOP_CEILING)
if ($pythonFiles.Count -gt $PYTHON_CEILING) {
    $pythonExceeded = $true
    Write-Fail (Get-Label 'check-naming.python-au-dessus' ($pythonFiles.Count - $PYTHON_CEILING))
    foreach ($rel in $pythonFiles) { Write-Detail $rel }
} elseif ($pythonFiles.Count -lt $PYTHON_CEILING) {
    Write-Ok (Get-Label 'check-naming.python-de-moins' ($PYTHON_CEILING - $pythonFiles.Count))
}

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
if ($trayTotal -gt $TRAY_CEILING) {
    Write-Fail (Get-Label 'check-naming.tray-au-dessus' $trayTotal)
    foreach ($rel in $trayFiles) { Write-Detail $rel }
    exit 2
}
if ($desktopTotal -gt $DESKTOP_CEILING) {
    Write-Fail (Get-Label 'check-naming.terme-invente-au-dessus' $desktopTotal)
    foreach ($rel in $desktopFiles) { Write-Detail $rel }
    exit 2
}
if ($commentExceeded -or $pythonExceeded) { exit 2 }
if ($total -lt $CEILING) {
    Write-Ok (Get-Label 'check-naming.de-moins-que-le' ($CEILING - $total) $total)
    exit 0
}
Write-Ok (Get-Label 'check-naming.plafond-tenu-aucun-identifiant')
exit 0
