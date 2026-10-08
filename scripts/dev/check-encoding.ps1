# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-encoding.ps1 -- UTF-8 EVERYWHERE, and French that keeps its accents.
    READ ONLY by default; -Fix repairs what is mechanical.

    Intent: stop checking an encoding by eye. The instruction "everything in UTF-8" is an old one, and it was
    broken three times in a single day: an install.ps1 with no BOM that PowerShell 5.1 read as latin-1, a
    setup.cmd from which I had removed the accents AND the apostrophes "to be safe", labels written without
    accents because I was not sure. Every time, the same cause: I was checking by eye. An eye does not check an
    encoding.

    Usage:
      pwsh -File .\scripts\dev\check-encoding.ps1            # the verdict
      pwsh -File .\scripts\dev\check-encoding.ps1 -Detail    # where and what
      pwsh -File .\scripts\dev\check-encoding.ps1 -Fix       # repair, then check again
    Exit codes: 0 = everything conforms; 2 = at least one shortfall.

    WHAT IS CHECKED

    1. THE ENCODING OF EACH FILE, according to what its reader demands:

         .ps1 .psd1   UTF-8 WITH a BOM    ALL of them, without exception. Windows PowerShell 5.1 reads a file
                                          without a BOM in the ANSI code page, and an accented word comes out
                                          mangled. PowerShell 7 accepts both. A purely ASCII file has nothing to
                                          lose: we impose nothing on it -- a rule that shouts at 90 harmless
                                          files stops being listened to.
         .cmd .bat    UTF-8 WITHOUT BOM   cmd.exe DISPLAYS the BOM as it stands, before even the first line. And
                                          if the file holds an accented character, it needs "chcp 65001" at the
                                          top, otherwise cmd reads it in the OEM 850 code page.
         others       UTF-8 WITHOUT BOM   git, the browsers and the modern editors.

    2. MOJIBAKE: the traces of a UTF-8 text read back as latin-1 then saved again. The file is then valid UTF-8
       and yet wrong: no encoding check on its own sees it.

    3. ACCENTS MISSING FROM DISPLAYED TEXT. We look ONLY at what the user reads: the arguments of Write-Ok /
       Warn / Fail / Info / Detail / Step / Title, the -Message of Write-Log, and the "echo" lines of the .cmd
       files. COMMENTS stay in ASCII, deliberately and by convention in this repository: they are not checked.

       The lexicon keeps only words that are ALWAYS accented in French. Some past participles exist without an
       accent as a present-tense verb, and correcting those would break correct sentences. The feminine ones in
       -ee, on the other hand, never mislead.
#>






param(
    # List every shortfall, file by file.
    [switch] $Detail,
    # Repair: rewrite with the right encoding, lay down the missing accents.
    [switch] $Fix,
    # ONLY THESE FILES, repository-relative. What a hook needs: judging the whole repository
    # to commit two files is work nobody waits for, and a check nobody waits for is a check
    # that gets bypassed. Paths that no longer exist are ignored: git also lists what a
    # commit DELETES.
    [string[]] $Files
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SKIPPED = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')   # .claude: the worktrees live there, and a worktree is a copy of the repository

# Words that are ALWAYS accented: not one of them exists without its accent in French.
# Written in lower case; the initial case of the text found is preserved.
$ACCENTED = [ordered]@{
    'deja' = 'déjà'; 'apres' = 'après'; 'tres' = 'très'; 'meme' = 'même'; 'etre' = 'être'
    'etat' = 'état'; 'etape' = 'étape'; 'echec' = 'échec'; 'echoue' = 'échoué'
    'element' = 'élément'; 'evenement' = 'événement'; 'acces' = 'accès'; 'succes' = 'succès'
    'fenetre' = 'fenêtre'; 'tache' = 'tâche'; 'systeme' = 'système'; 'probleme' = 'problème'
    'parametre' = 'paramètre'; 'reference' = 'référence'; 'resultat' = 'résultat'
    'reglage' = 'réglage'; 'reserve' = 'réserve'; 'securite' = 'sécurité'
    'priorite' = 'priorité'; 'propriete' = 'propriété'; 'unite' = 'unité'
    'operation' = 'opération'; 'recuperation' = 'récupération'; 'execution' = 'exécution'
    'elevation' = 'élévation'; 'necessaire' = 'nécessaire'; 'different' = 'différent'
    'prealable' = 'préalable'; 'prerequis' = 'prérequis'; 'present' = 'présent'
    'memoire' = 'mémoire'; 'numero' = 'numéro'; 'periode' = 'période'
    'premiere' = 'première'; 'derniere' = 'dernière'; 'maniere' = 'manière'
    'entiere' = 'entière'; 'controle' = 'contrôle'; 'arret' = 'arrêt'
    'detaille' = 'détaillé'; 'developpement' = 'développement'
    # The feminine past participles in -ee: never valid without an accent.
    'installee' = 'installée'; 'lancee' = 'lancée'; 'terminee' = 'terminée'
    'annulee' = 'annulée'; 'modifiee' = 'modifiée'; 'verifiee' = 'vérifiée'
    'echouee' = 'échouée'; 'deployee' = 'déployée'; 'enregistree' = 'enregistrée'
    'desactivee' = 'désactivée'; 'activee' = 'activée'; 'preparee' = 'préparée'
    'creee' = 'créée'; 'passee' = 'passée'; 'posee' = 'posée'; 'trouvee' = 'trouvée'
    # Added as the passes went by: every word that comes out of a partial correction lands here. A sentence half
    # accented is WORSE than the same sentence in ASCII -- it looks like an encoding defect instead of a choice.
    'deploiement' = 'déploiement'; 'deploie' = 'déploie'
    'execute' = 'exécute'; 'executer' = 'exécuter'; 'reexecute' = 'réexécute'
    'reexecutera' = 'réexécutera'; 'reexecution' = 'réexécution'
    'demarre' = 'démarre'; 'demarrer' = 'démarrer'; 'demarrage' = 'démarrage'
    'redemarre' = 'redémarre'; 'redemarrer' = 'redémarrer'; 'redemarrage' = 'redémarrage'
    'verifie' = 'vérifie'; 'verifier' = 'vérifier'; 'verification' = 'vérification'
    'telecharge' = 'télécharge'; 'telecharger' = 'télécharger'; 'telechargement' = 'téléchargement'
    'detecte' = 'détecte'; 'detection' = 'détection'; 'desactive' = 'désactive'
    'desactiver' = 'désactiver'; 'desormais' = 'désormais'; 'defaut' = 'défaut'
    'defini' = 'défini'; 'definition' = 'définition'; 'delai' = 'délai'
    'dependance' = 'dépendance'; 'depot' = 'dépôt'; 'detail' = 'détail'
    'developpe' = 'développe'; 'difficulte' = 'difficulté'; 'duree' = 'durée'
    'ecrit' = 'écrit'; 'ecriture' = 'écriture'; 'ecran' = 'écran'; 'ecoute' = 'écoute'
    'economise' = 'économise'; 'economies' = 'économies'; 'eteint' = 'éteint'
    'etendu' = 'étendu'; 'energie' = 'énergie'; 'equipe' = 'équipe'
    'equivalent' = 'équivalent'; 'eleve' = 'élevé'; 'reessayez' = 'réessayez'
    'reessayer' = 'réessayer'; 'regle' = 'règle'; 'region' = 'région'
    'regulier' = 'régulier'; 'repertoire' = 'répertoire'; 'repond' = 'répond'
    'reponse' = 'réponse'; 'requete' = 'requête'; 'reseau' = 'réseau'
    'resolu' = 'résolu'; 'reussi' = 'réussi'; 'reussite' = 'réussite'
    'revision' = 'révision'; 'peripherique' = 'périphérique'; 'precise' = 'précise'
    'precedent' = 'précédent'; 'presence' = 'présence'; 'prevu' = 'prévu'
    'procedure' = 'procédure'; 'general' = 'général'; 'generale' = 'générale'
    'generation' = 'génération'; 'serie' = 'série'; 'critere' = 'critère'
    'modele' = 'modèle'; 'schema' = 'schéma'; 'theme' = 'thème'
    'selectionne' = 'sélectionne'; 'specifique' = 'spécifique'; 'strategie' = 'stratégie'
    'ete' = 'été'; 'inchange' = 'inchangé'; 'complete' = 'complète'; 'negatif' = 'négatif'; 'interet' = 'intérêt'; 'lisere' = 'liséré'
}

# THE APOSTROPHE IS ASCII: it crosses everything, and nothing justifies removing it. I nevertheless deleted it at
# the same time as the accents, "to be safe" (28/08).
# In French the only one-letter words are two vowels: one letter among l/d/n/j/m/s/t/c followed by a vowel is
# ALWAYS an elision.
$ELISION = [regex]'(?<![\p{L}''])([ldnjmstcLDNJMSTC]) (?=[aeiouyhéèêàâîôûAEIOUYH])'

# THE PATTERNS ARE BUILT, they are not written out. A file holding the mojibake byte pair in plain sight reports
# itself at every pass: the tool was its own culprit.
$MOJIBAKE = @(
    ([char]0xC3 + [char]0xA9),   # e acute, read back as latin-1
    ([char]0xC3 + [char]0xA8),   # e grave
    ([char]0xC3 + [char]0xA0),   # a grave
    ([char]0xC3 + [char]0xA7),   # c cedilla
    ([char]0xC3 + [char]0xAA),   # e circumflex
    ([char]0xC3 + [char]0xB4),   # o circumflex
    ([char]0xE2 + [char]0x80 + [char]0x99),   # a typographic apostrophe
    ([char]0xC2 + [char]0xAB),   # an opening guillemet
    ([char]0xC2 + [char]0xBB)    # a closing guillemet
)

# DISPLAYED text, and nothing else. An unaccented comment is a convention of this repository, not a defect:
# checking it would drown the real signal.
$SHOWN_PS  = [regex]'(?m)(?:Write-(?:Ok|Warn|Fail|Info|Detail|Step|Title)|Say|Dire)\s+"([^"]*)"'
$SHOWN_MSG = [regex]'(?m)-Message\s+"([^"]*)"'
$SHOWN_CMD = [regex]'(?m)^\s*echo\s+(.+)$'

function Get-FileBytes { param([string]$Path) return [System.IO.File]::ReadAllBytes($Path) }
function Test-HasBom {
    param([byte[]]$Bytes)
    return ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
}
# Is the file valid UTF-8? A STRICT decoding throws on the first wrong byte.
function Test-IsValidUtf8 {
    param([byte[]]$Bytes)
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        [void]$strict.GetString($Bytes)
        return $true
    } catch { return $false }
}
function Get-Text {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}
function Set-Text {
    param([string]$Path, [string]$Text, [bool]$Bom)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($Bom)))
}

# The case of the word found is given back to the corrected word.
# THE RULE RATHER THAN THE LIST. A French word ending in a consonant plus "ee" is a feminine past participle.
# There is no exception -- and a rule does not forget a word, unlike a lexicon.
$FEMININE_PAST = [regex]'(?<=[\p{L}]{2})(?<![aeiouy])ee(?![\p{L}])'

function Repair-FemininePast {
    param([string]$Text)
    return $FEMININE_PAST.Replace($Text, ([char]0xE9 + 'e'))
}

function Repair-Elisions {
    param([string]$Text)
    return $ELISION.Replace($Text, '$1' + [char]0x27)
}

# PATTERNS ARE COMPILED ONCE, NOT PER PHRASE. Recompiling a hundred and fifty regular
# expressions for every label of a file took tens of seconds -- for identical work.
$ACCENT_PATTERNS = [ordered]@{}
foreach ($word in $ACCENTED.Keys) {
    # "$Etat" is not the word "etat", "-Detail" is not "détail": what follows a $ is a
    # VARIABLE NAME, what follows a dash is a PARAMETER NAME. Accenting them breaks the
    # code, or worse: documents an option that does not exist. A PATH SEGMENT is not a word either:
    # "implemented/operations.md" became "opérations.md" in a label on 13/09, and the path no longer existed.
    $ACCENT_PATTERNS[$word] = [regex]::new(('(?<![\p{L}$/-])' + $word + 's?(?![\p{L}/]|[.][\p{L}])'),
                                           [Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Repair-Accents {
    param([string]$Text)
    foreach ($k in $ACCENTED.Keys) {
        # NOTHING TO DO SHOWS FAST: without the word, no pass runs at all -- which is the
        # case for the vast majority of labels.
        if ($Text.IndexOf($k, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $Text = $ACCENT_PATTERNS[$k].Replace($Text, {
            param($m)
            # The plural "s" is returned exactly as it was found.
            $good = $ACCENTED[$k]
            if ($m.Value.EndsWith('s') -and -not $k.EndsWith('s')) { $good = $good + 's' }
            if ($m.Value.Substring(0, 1) -cmatch '[A-Z]') { return $good.Substring(0, 1).ToUpper() + $good.Substring(1) }
            return $good
        })
    }
    return $Text
}

# CONTROL CHARACTERS, once and for all: everything below the space except tab, carriage
# return and line feed.
$CONTROL_CHARS = @()
for ($c = 0; $c -lt 32; $c++) {
    if ($c -eq 9 -or $c -eq 10 -or $c -eq 13) { continue }
    $CONTROL_CHARS += [char]$c
}
$CONTROL_CHARS = [char[]]$CONTROL_CHARS

$issues = @()   # @{ File; Kind; Message }
$fixed  = 0

if ($Files -and $Files.Count) {
    $chosen = @()
    foreach ($given in $Files) {
        $full = $given
        if (-not [IO.Path]::IsPathRooted($full)) { $full = Join-Path $repoRoot $given }
        $item = $null
        try { $item = Get-Item -LiteralPath $full -ErrorAction Stop } catch { $item = $null }
        if ($item -and -not $item.PSIsContainer) { $chosen += $item }
    }
    $scannedFiles = @($chosen)
} else {
    $scannedFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue
}
$scannedFiles = @($scannedFiles | Where-Object { $_.Extension -in '.ps1', '.psd1', '.psm1', '.cmd', '.bat', '.md', '.html', '.css', '.js', '.json' })

foreach ($f in $scannedFiles) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }

    $bytes = Get-FileBytes $f.FullName
    if ($bytes.Length -eq 0) { continue }
    $ext   = $f.Extension.ToLowerInvariant()
    $text0 = Get-Text $f.FullName
    $text  = $text0
    # EVERY .ps1 CARRIES THE BOM, accented or not. The previous rule demanded it only of files that were already
    # accented: more accurate technically, worse in practice. The day one adds an accent to a file that was ASCII
    # until then, it silently stops conforming. A uniform rule has no edge to fall off.



    <#
        NO CONTROL CHARACTER IN A SOURCE.

        Three times on 31/08, a string written from a Python script turned a backslash followed by a letter into a
        control character: one became a BACKSPACE inside a regular expression that then found nothing, another a
        FORM FEED in the middle of a path, a third a line break that cut a command in two. Every time, the file
        looked normal when read and behaved crookedly.

        Tab, carriage return and line feed are normal; everything else below the space is the trace of a failed
        escape. It is mechanical, so this is where it is checked -- not in my attention.
    #>




    # NO REGEX HERE: we compare CODES. The first version of this rule carried a character class which was itself
    # destroyed by one escape too many -- the rule became a range of dashes and accused the dashes. A check on
    # escapes cannot depend on an escape.

    #
    # ONE CALL, NOT A LOOP. Walking character by character costs seconds, in interpreted
    # PowerShell, on a four-hundred-thousand-character file -- and that is what made the
    # pre-commit hook unusable (03/09). IndexOfAny compares the same codes, natively.
    $found = $text0.IndexOfAny($CONTROL_CHARS)
    if ($found -ge 0) {
        $code = [int]$text0[$found]
        $line = ($text0.Substring(0, $found) -split "`n").Count
        $issues += @{ File = $rel; Kind = 'controle'
                      Message = ("caractere de controle 0x{0:X2} ligne {1} -- un echappement a mal tourne" -f $code, $line) }
    }

    $wantBom = ($ext -in '.ps1', '.psd1', '.psm1')
    $hasBom  = Test-HasBom $bytes

    if (-not (Test-IsValidUtf8 $bytes)) {
        $issues += @{ File = $rel; Kind = 'encodage'; Message = "n'est pas de l'UTF-8 valide (octets d'une autre page de code)" }
        continue   # inutile d'aller plus loin : le texte lu serait faux
    }

    $newText = $text
    $rewrite = $false

    # --- 1. BOM ---
    if ($wantBom -and -not $hasBom) {
        $issues += @{ File = $rel; Kind = 'BOM'; Message = 'UTF-8 SANS BOM : PowerShell 5.1 lira les accents de travers' }
        if ($Fix) { $rewrite = $true }
    } elseif (-not $wantBom -and $hasBom) {
        $issues += @{ File = $rel; Kind = 'BOM'; Message = 'BOM en tete : cmd.exe et git ne le veulent pas ici' }
        if ($Fix) { $rewrite = $true }
    }

    # --- 2. Mojibake ---
    # WE DO NOT LOOK AT COMMENTS. This tool, and console-ui.ps1, QUOTE mojibake to explain what it looks like:
    # a checker that raises the alarm about its own documentation teaches its reader to ignore its alarms.
    $code = [regex]::Replace($text, '(?s)<#.*?#>', '')
    $code = [regex]::Replace($code, '(?m)^\s*(#|REM\b).*$', '')
    foreach ($m in $MOJIBAKE) {
        if ($code.Contains($m)) {
            $issues += @{ File = $rel; Kind = 'mojibake'; Message = ("contient « " + $m + " » : de l'UTF-8 relu en latin-1") }
            break
        }
    }

    # --- 3. chcp for an accented .cmd ---
    if ($ext -in '.cmd', '.bat') {
        $hasAccent = $text -cmatch '[^\x00-\x7F]'
        $hasChcp   = $text -match '(?im)^\s*@?chcp\s+65001'
        if ($hasAccent -and -not $hasChcp) {
            $issues += @{ File = $rel; Kind = 'chcp'; Message = 'accents sans « chcp 65001 » : cmd.exe les lira en page OEM 850' }
        }
    }

    # --- 4. Accents missing from the displayed text ---
    $shown = @()
    if ($ext -in '.ps1', '.psm1') {
        foreach ($m in $SHOWN_PS.Matches($text))  { $shown += $m }
        foreach ($m in $SHOWN_MSG.Matches($text)) { $shown += $m }
    } elseif ($ext -in '.cmd', '.bat') {
        foreach ($m in $SHOWN_CMD.Matches($text)) { $shown += $m }
    }

    foreach ($m in $shown) {
        $phrase = $m.Groups[1].Value
        $repaired = Repair-Elisions (Repair-FemininePast (Repair-Accents $phrase))
        if ($repaired -cne $phrase) {
            $kind = if ((Repair-FemininePast (Repair-Accents $phrase)) -cne $phrase) { 'accents' } else { 'apostrophes' }
            $issues += @{ File = $rel; Kind = $kind; Message = ('« ' + $phrase.Trim() + ' »') }
            if ($Fix) {
                # We replace the WHOLE SENTENCE that was found, not the word: two labels can share a word, and a
                # global replacement would touch the comments as well.
                $newText = $newText.Replace($m.Value, $m.Value.Replace($phrase, $repaired))
                $rewrite = $true
            }
        }
    }

    if ($Fix -and $rewrite) {
        Set-Text -Path $f.FullName -Text $newText -Bom $wantBom
        $fixed++
    }
}

# --- 5. The labels file -------------------------------------------------------
#
# THE TEXT HAS MOVED, THE CHECK FOLLOWS. Since the labels live in lang/, THAT is where the accents go missing or
# come back: checking them in the .ps1 files would say nothing any more. The JSON is repaired by -Fix as well.
$langDir = Join-Path $repoRoot 'lang'
if (Test-Path -LiteralPath $langDir) {
    foreach ($lf in (Get-ChildItem -LiteralPath $langDir -File -Filter '*.json')) {
        $rel = 'lang/' + $lf.Name
        $raw = [System.IO.File]::ReadAllText($lf.FullName, [System.Text.UTF8Encoding]::new($false))
        if (Test-HasBom (Get-FileBytes $lf.FullName)) {
            $issues += @{ File = $rel; Kind = 'BOM'; Message = 'BOM en tete : la norme JSON ne le veut pas, et fetch() le rend en clair' }
        }
        $obj = $null
        try { $obj = $raw | ConvertFrom-Json } catch {
            $issues += @{ File = $rel; Kind = 'encodage'; Message = 'JSON illisible : ' + $_.Exception.Message }
        }
        if ($obj) {
            $changed = $false
            $out = [ordered]@{}
            # IN THE ORDER OF THE FILE. Sorting rewrote every key for a single label fixed, and the diff of a one-word
            # correction ran to two hundred lines (13/09).
            foreach ($prop in $obj.PSObject.Properties) {
                $v = [string]$prop.Value
                $good = Repair-Elisions (Repair-FemininePast (Repair-Accents $v))
                if ($good -cne $v) {
                    $issues += @{ File = $rel; Kind = 'accents'; Message = ('« ' + $v + ' »') }
                    $changed = $true
                }
                $out[$prop.Name] = $good
            }
            if ($Fix -and $changed) {
                # ConvertTo-Json ends its lines with CRLF on Windows: the repository is LF, and the whole file
                # showed as rewritten when a single label had changed (13/09).
                [System.IO.File]::WriteAllText($lf.FullName, (($out | ConvertTo-Json -Depth 3) -replace "`r`n", "`n"),
                                               (New-Object System.Text.UTF8Encoding($false)))
                $fixed++
            }
        }
    }
}

# --- Verdict ---------------------------------------------------------------------------
Write-Title (Get-Label 'check-encoding.encodage-et-accents')

$byKind = $issues | Group-Object { $_.Kind } | Sort-Object Name
foreach ($g in $byKind) {
    Write-Info ('{0,-10} : {1}' -f $g.Name, $g.Count)
}

if ($Detail) {
    foreach ($g in $byKind) {
        Write-Step $g.Name
        foreach ($i in $g.Group) { Write-Detail ($i.File + ' -- ' + $i.Message) }
    }
}

if ($Fix) {
    if ($fixed) { Write-Ok (Get-Label 'check-encoding.fichier-reecrits-relancez-sans' $fixed) }
    else        { Write-Info (Get-Label 'check-encoding.rien-corriger-automatiquement') }
    exit 0
}

if ($issues.Count) {
    Write-Fail (Get-Label 'check-encoding.manquement-detail-pour-les' $issues.Count)
    Write-Outcome -Failures 1
    exit 2
}
Write-Ok (Get-Label 'check-encoding.utf-partout-accents-en')
Write-Outcome -Failures 0
exit 0
