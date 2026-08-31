<#
    LES INCOHERENCES QUE JE NE VOIS PAS TOUT SEUL.

    Deux regles, nees le meme jour, du meme defaut : croire que je me souviens.

    1. UNE FONCTION N'EST DEFINIE QU'UNE FOIS. J'ai ecrit un Get-MachineConfigPath alors
       qu'il en existait deja un, trois mille lignes plus bas, avec un tout autre sens. La
       derniere definition gagne EN SILENCE : ma fonction n'existait pas, et l'appel
       echouait sur un parametre obligatoire qui n'etait pas le mien. Rien, nulle part,
       ne l'avait signale.

    2. UNE DECISION CITEE EXISTE. Le code renvoie a « D65 », « D99 », « D107 » -- c'est
       ce qui relie une ligne a sa raison d'etre. Un renvoi vers un numero inexistant
       envoie chercher une regle qui n'a jamais ete ecrite.

    La source de verite, c'est doc/progress/decisions.md. Pour la consulter vite :
    scripts/dev/decisions.ps1 -About "<mots>".

    Codes de retour : 0 = coherent ; 2 = au moins un manquement.
#>
[CmdletBinding()]
param([switch] $Detail)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$skipped = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')
function Test-Skipped {
    param([string]$Relative)
    foreach ($s in $skipped) {
        if ($Relative -like ($s + '/*') -or $Relative -like ('*/' + $s + '/*')) { return $true }
    }
    return $false
}
function Get-Relative {
    param([string]$Full)
    $Full.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
}

$faults = @()

# --- 1. Une fonction, une definition -----------------------------------------------------
#
# On regarde les BIBLIOTHEQUES PARTAGEES : celles que tout le monde charge ensemble, donc
# celles ou une redefinition ecrase pour de vrai. Deux scripts independants qui nomment
# chacun leur aide « Sortir » ne se marchent pas dessus, et les denoncer serait du bruit.
$libs = @()
foreach ($d in @('apps/backend-pode/lib', 'scripts/lib')) {
    $p = Join-Path $repoRoot $d
    if (Test-Path -LiteralPath $p) {
        $libs += @(Get-ChildItem -LiteralPath $p -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
    }
}
$seen = @{}
foreach ($f in $libs) {
    $rel = Get-Relative $f.FullName
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
        $n++
        if ($line -match '^\s*function\s+([A-Za-z][\w-]*)') {
            $name = $Matches[1]
            if (-not $seen.ContainsKey($name)) { $seen[$name] = @() }
            $seen[$name] += ('{0}:{1}' -f $rel, $n)
        }
    }
}
foreach ($name in ($seen.Keys | Sort-Object)) {
    if ($seen[$name].Count -gt 1) {
        $faults += ("fonction définie {0} fois — {1} : {2}" -f $seen[$name].Count, $name, ($seen[$name] -join ' , '))
    }
}

# --- 2. Une decision citee existe --------------------------------------------------------
$decisionsFile = Join-Path $repoRoot 'doc/progress/decisions.md'
$known = @{}
if (Test-Path -LiteralPath $decisionsFile) {
    foreach ($line in (Get-Content -LiteralPath $decisionsFile -Encoding UTF8)) {
        if ($line -match '^#{2,3}\s+(D\d+[a-z]*)') { $known[$Matches[1].ToUpperInvariant()] = $true }
    }
} else {
    $faults += ("fichier des décisions introuvable : " + $decisionsFile)
}

$cited = @{}
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1', '*.psd1', '*.html', '*.md' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
    if ($rel -eq 'doc/progress/decisions.md') { continue }
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $n++
        foreach ($m in [regex]::Matches($line, '\bD(\d{1,3})\b')) {
            $id = 'D' + $m.Groups[1].Value
            if ($known.ContainsKey($id)) { continue }
            $key = $id
            if (-not $cited.ContainsKey($key)) { $cited[$key] = @() }
            $cited[$key] += ('{0}:{1}' -f $rel, $n)
        }
    }
}
foreach ($id in ($cited.Keys | Sort-Object)) {
    $ou = $cited[$id]
    $extrait = if ($ou.Count -gt 3) { ($ou[0..2] -join ' , ') + (' … +' + ($ou.Count - 3)) } else { $ou -join ' , ' }
    $faults += ("décision citée mais inexistante — {0} : {1}" -f $id, $extrait)
}

# --- 3. Les cercles de comptes ne se refiltrent pas a la main -----------------------------
#
# « Where-Object { -not $_.technical } » etait recopie a SEPT endroits. Un filtre recopie
# est un filtre qu'on oublie quelque part : l'appel qui ne l'avait pas a depose un ordre
# de relance dans le dossier du compte de SERVICE, que personne ne lira jamais.
#
# Les trois cercles ont un nom (common.ps1) : Get-ComputerAccounts, Get-UserAccounts,
# Get-EnabledAccounts. On passe par eux -- sinon le jour ou la definition d'un cercle
# change, elle ne change qu'a un endroit sur sept.
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
    # common.ps1 EST l'implementation des trois cercles.
    if ($rel -eq 'apps/backend-pode/lib/common.ps1') { continue }
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $n++
        if ($line -match '^\s*#') { continue }
        # LES MOTIFS S'ECRIVENT EN MORCEAUX, sinon ce fichier se denonce lui-meme.
        #
        # ET ON NE VISE QUE LES CERCLES. Le premier jet attrapait « Get-ComptesX |
        # Where-Object { $_.name -eq ... } » -- chercher UN compte par son nom n'est pas
        # refiltrer un cercle. Seuls « technical » et « enabled » definissent les cercles.
        $marque = '$_.' + 'technical'
        $actif  = '$_.' + 'enabled'
        if ($line.Contains($marque)) {
            $faults += ("cercle de comptes recopié (utiliser Get-UserAccounts) -- {0}:{1}" -f $rel, $n)
        }
        if ($line.Contains($actif) -and ($line -match 'Accounts')) {
            $faults += ("cercle de comptes recopié (utiliser Get-EnabledAccounts) -- {0}:{1}" -f $rel, $n)
        }
    }
}

# --- 4. Une variable ne porte pas le nom d'un parametre -----------------------------------
#
# POWERSHELL IGNORE LA CASSE : « $source » et « $Source » sont LA MEME VARIABLE. Ecrire
# « $source = ... » dans un script qui declare un parametre « $Source » n'est pas une
# variable locale : c'est une AFFECTATION AU PARAMETRE. Si celui-ci porte un ValidateSet,
# le script meurt sur place, avec un message qui parle d'autre chose.
#
# Deux fois le meme jour, le 30/08, dans le meme fichier : « $source = $null » puis
# « $source = Get-UpdateRemote ». La deuxieme fois, la mise a jour est morte a la ligne
# 192 devant l'utilisateur.
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = Get-Relative $f.FullName
    if (Test-Skipped $rel) { continue }
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }

    # Le bloc param() du SCRIPT : ses noms sont ceux qui peuvent etre ecrases.
    $errors = $null; $tokens = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) { continue }
    $block = $tree.ParamBlock
    if (-not $block) { continue }
    $names = @($block.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    if (-not $names.Count) { continue }

    # Toute affectation dont le nom EGALE un parametre a la casse pres, mais s'ecrit
    # differemment : c'est le signe qu'on croyait creer une variable a soi.
    foreach ($a in $tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $left = $a.Left
        if ($left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        $used = $left.VariablePath.UserPath
        foreach ($p in $names) {
            # « -cne » : SENSIBLE A LA CASSE. Avec « -ne », la comparaison ignore la
            # casse comme le reste de PowerShell -- la regle ne pouvait jamais se
            # declencher, et je l'ai crue bonne parce qu'elle passait au vert.
            if ($used -cne $p -and $used -ieq $p) {
                $faults += ("variable « `${0} » : c'est le paramètre « `${1} » (la casse ne compte pas) -- {2}:{3}" -f
                            $used, $p, $rel, $left.Extent.StartLineNumber)
            }
        }
    }
}

# --- 5. Ce qu'une action rend a une personne ne vit pas chez le service --------------------
#
# LE DEFAUT. Une action qui rapatriait des journaux les copiait dans le var de l'APP
# SERVEUR, puis rendait ce chemin a l'utilisateur. C'etait juste le jour ou c'est ete
# ecrit : le serveur tournait alors sous le compte de la personne. Depuis qu'il tourne
# sous un compte de service (28/08), ce dossier est illisible pour tout le monde sauf lui
# -- « 62 fichiers rapatries », vrai et inutile. Le code n'avait pas bouge ; son sol, si.
#
# LA REGLE. Une action qui rend un CHEMIN dans son resultat doit l'avoir construit pour
# quelqu'un : Get-AccountVarRoot, Get-RequesterAccount, un dossier public. Si elle ne cite
# que Get-VarPath / Get-LogDir / Get-VarRoot, elle rend un chemin de service a une
# personne, et personne ne s'en apercevra avant d'essayer de l'ouvrir.
$actionsDir = Join-Path $repoRoot 'apps/backend-pode/actions'
if (Test-Path -LiteralPath $actionsDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $actionsDir -Filter '*.action.ps1' -File -ErrorAction SilentlyContinue)) {
        $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        if (-not $text) { continue }
        # Rend-elle un chemin ? On cherche « path = » dans le resultat.
        # « path = » n'importe ou, mais pas « $path = » : le premier est une cle rendue
        # a l'appelant, le second une variable de travail.
        #
        # DEUX FOIS LE MEME PIEGE DANS CETTE LIGNE. D'abord une sequence « backslash-b » ecrite depuis un
        # script Python, ou il vaut le caractere RETOUR ARRIERE : la regle cherchait un
        # caractere de controle et ne trouvait jamais rien. Ensuite une ancre de debut de
        # ligne, qui ne voyait rien des que le resultat tenait sur une seule ligne.
        # Les deux fois, le vert m'a suffi. Une regle se prouve en la faisant ECHOUER.
        # ON NE LIT PAS LES COMMENTAIRES. « GET /disk/tree?path=... », ecrit dans une
        # explication, faisait accuser une action qui ne rend aucun chemin.
        $code = [regex]::Replace($text, '(?s)<#.*?#>', '')
        $code = ($code -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        if ($code -notmatch '(?<![\w$])path\s*=') { continue }
        $duService  = ($code -match 'Get-VarPath|Get-LogDir|Get-VarRoot')
        $duDemandeur = ($code -match 'Get-AccountVarRoot|Get-RequesterAccount')
        if ($duService -and -not $duDemandeur) {
            $faults += ("action « {0} » : elle rend un chemin construit sur le var du service -- illisible depuis la session de qui la demande" -f $f.Name)
        }
    }
}

# --- Verdict -----------------------------------------------------------------------------
Write-Title 'Cohérence'
Write-Info ("{0} bibliothèque(s) partagée(s), {1} décision(s) connue(s)." -f $libs.Count, $known.Count)
if (-not $faults.Count) {
    Write-Ok "Aucune redéfinition, aucun renvoi mort."
    Write-Outcome -What 'Cohérence vérifiée'
    exit 0
}
Write-Fail ("{0} manquement(s) :" -f $faults.Count)
foreach ($x in $faults) { Write-Detail ('- ' + $x) }
Write-Outcome -What 'Cohérence vérifiée'
exit 2
