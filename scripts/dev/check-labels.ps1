<#
    check-labels.ps1 - AUCUNE CLÉ ABSENTE NE PART EN LIVRAISON. LECTURE SEULE.

    POURQUOI CE FICHIER EXISTE. Sortir les libellés du code a supprimé un défaut -- les
    accents perdus -- et en a créé un autre, plus sournois : une clé mal tapée ne se voit
    pas à la relecture, ne fait pas échouer l'analyse syntaxique, et n'apparaît qu'au
    moment où le message doit s'afficher. C'est-à-dire souvent pendant un incident, quand
    on a le plus besoin de lire. Ce vérificateur est la contrepartie du mécanisme : sans
    lui, le mécanisme n'aurait pas dû être adopté.

    CE QUI EST VÉRIFIÉ

    1. TOUTE CLÉ RÉCLAMÉE EXISTE. `Get-Label 'x.y'` sans « x.y » dans lang/fr.json est une
       faute bloquante. C'est le mode d'échec qu'on refusait dès le départ.

    2. LES TROUS SE CORRESPONDENT. Un libellé qui dit « {0} » et « {1} » réclame deux
       valeurs. Trop peu, et le message affiche « {1} » tel quel ; trop, et le surplus est
       ignoré en silence. On compte des deux côtés.

    3. LES LIBELLÉS ORPHELINS SONT SIGNALÉS, sans bloquer. Une clé que plus personne
       n'appelle n'est pas une faute : elle peut servir au front, ou à un chemin de code
       rare. Mais on veut la voir, sinon le fichier enfle indéfiniment.

    4. TOUTES LES LANGUES ONT LES MÊMES CLÉS. Le jour où en.json existe, une clé présente
       d'un côté et absente de l'autre est un trou de traduction.

    Usage :
      pwsh -File .\scripts\dev\check-labels.ps1
      pwsh -File .\scripts\dev\check-labels.ps1 -Detail

    Codes de retour : 0 = rien de bloquant ; 2 = au moins une clé absente ou mal remplie.
#>
param(
    [switch] $Detail
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SKIPPED = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')   # .claude : les worktrees y vivent, et un worktree est une copie du depot
$REFERENCE_LANGUAGE = 'fr'

# --- Les libellés déclarés --------------------------------------------------------------
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

# Combien de trous distincts un libellé réclame-t-il ? « {0} {1} {0} » en réclame deux.
function Get-SlotCount {
    param([string]$Text)
    $seen = @{}
    foreach ($m in [regex]::Matches($Text, '\{(\d+)\}')) { $seen[[int]$m.Groups[1].Value] = $true }
    if (-not $seen.Count) { return 0 }
    return (($seen.Keys | Measure-Object -Maximum).Maximum + 1)
}

# --- Les clés réclamées par le code -----------------------------------------------------
#
# On passe par l'arbre et non par une expression régulière : il faut COMPTER LES ARGUMENTS
# de l'appel, ce qu'un motif textuel ne sait pas faire dès qu'une valeur contient elle-même
# des parenthèses.
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
            # Une clé calculée ne se vérifie pas ici ; on la signale plutôt que de l'ignorer.
            #
            # SAUF DANS LE RESOLVEUR. show-confirm.ps1 reçoit des clés en paramètre et les
            # résout : c'est sa raison d'être, et l'y signaler reviendrait à reprocher à
            # un traducteur de traduire.
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

# --- Les cles reclamees par le front ----------------------------------------------------
#
# LE NAVIGATEUR CONSOMME LE MEME FICHIER. Ne verifier que les .ps1 laisserait la moitie des
# cles sans filet -- et c'est cote interface qu'une cle absente se voit le plus.
foreach ($h in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.html' -ErrorAction SilentlyContinue)) {
    $rel = $h.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $text = [IO.File]::ReadAllText($h.FullName, (New-Object Text.UTF8Encoding($false)))

    # UN COMMENTAIRE QUI EXPLIQUE LE MECANISME N'EST PAS UN APPEL. Le mode d'emploi ecrit
    # « data-i18n="cle" » ; le verificateur reclamait une cle nommee « cle ». On neutralise
    # les lignes de commentaire avant de chercher.
    $text = [regex]::Replace($text, '(?m)^\s*//.*$', '')

    # L('cle'), L('cle', valeur) ... et les marques du HTML statique.
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

# UNE CLE CITEE EST UNE CLE UTILISEE. Depuis que la fenetre de confirmation les recoit
# en parametre -- « -TitleKey 'install.fenetre-titre' » --, la cle n'apparait plus dans un
# appel a Get-Label. Chercher le NOM lui-meme, ou qu'il soit, evite de declarer orphelins
# des libelles bel et bien affiches.
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.html' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $body = [IO.File]::ReadAllText($f.FullName, (New-Object Text.UTF8Encoding($false)))
    foreach ($k in $reference.Keys) {
        if (-not $used.ContainsKey($k) -and $body.Contains("'" + $k + "'")) { $used[$k] = $true }
    }
}

$orphans = @($reference.Keys | Where-Object { -not $used.ContainsKey($_) })

# --- Les langues entre elles ------------------------------------------------------------
$gaps = @()
foreach ($lang in ($tables.Keys | Where-Object { $_ -ne $REFERENCE_LANGUAGE })) {
    foreach ($k in $reference.Keys) {
        if (-not $tables[$lang].ContainsKey($k)) { $gaps += ("{0} : {1}" -f $lang, $k) }
    }
    foreach ($k in $tables[$lang].Keys) {
        if (-not $reference.ContainsKey($k)) { $gaps += ("{0} : {1} (absente de {2})" -f $lang, $k, $REFERENCE_LANGUAGE) }
    }
}

# --- Les mots bannis --------------------------------------------------------------------
#
# « MACHINE » NE DIT RIEN A QUI LIT. « Le serveur de machine », « les comptes de la
# machine » : c'est notre vocabulaire de conception, pas celui de quelqu'un devant son
# ecran. On parle de « l'ordinateur », ou de « tous les comptes » -- selon ce qu'on veut
# dire, et c'est justement l'interet : le mot banni cachait deux idees differentes.
#
# L'exception est litterale : « --scope machine » est un drapeau de winget, on ne traduit
# pas une commande.
$bannis = @()
foreach ($k in ($reference.Keys | Sort-Object)) {
    $v = $reference[$k]
    if ($v -notmatch '(?i)machine') { continue }
    if ($v -match '--scope\s+machine') { continue }
    $bannis += ("{0} : « {1} »" -f $k, $v)
}
foreach ($b in $bannis) { $missing += @{ File = 'lang/fr.json'; Line = 0; Message = ("mot banni « machine » -- " + $b) } }

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
    # PAS UNE FAUTE : le front consomme le même fichier, et certains chemins de code sont
    # rares. On le dit, on ne bloque pas.
    Write-Warn ("{0} libellé(s) que plus aucun script ne réclame." -f $orphans.Count)
    if ($Detail) { foreach ($o in ($orphans | Sort-Object)) { Write-Detail $o } }
}

$failures = $missing.Count + $mismatch.Count + $gaps.Count
if ($failures) { Write-Outcome -Failures 1; exit 2 }
Write-Ok 'Toutes les clés existent, tous les trous sont remplis.'
Write-Outcome -Failures 0
exit 0
