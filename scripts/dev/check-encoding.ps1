# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-encoding.ps1 - UTF-8 PARTOUT, et du francais qui garde ses accents.
    LECTURE SEULE par defaut ; -Fix corrige ce qui est mecanique.

    POURQUOI CET OUTIL EXISTE. La consigne « tout en UTF-8 » est ancienne, et elle a ete
    enfreinte trois fois de suite en une journee : un install.ps1 sans BOM que PowerShell
    5.1 lisait en latin-1, un setup.cmd dont j'avais retire les accents ET les apostrophes
    « par prudence », des libelles ecrits sans accent parce que je n'etais pas sur. A
    chaque fois, la meme cause : je verifiais a l'oeil. Un oeil ne verifie pas un encodage.

    CE QUI EST VERIFIE

    1. L'ENCODAGE DE CHAQUE FICHIER, selon ce que son lecteur exige :

         .ps1 .psd1   UTF-8 AVEC BOM      TOUS, sans exception. Windows
                                          PowerShell 5.1 lit un fichier sans BOM dans la
                                          page ANSI : « installé » devient « installÃ© ».
                                          PowerShell 7 accepte les deux. Un fichier
                                          purement ASCII n'a rien a perdre : on ne lui
                                          impose rien -- une regle qui crie sur 90
                                          fichiers sans risque ne se fait plus ecouter.
         .cmd .bat    UTF-8 SANS BOM      cmd.exe AFFICHE le BOM tel quel, avant meme la
                                          premiere ligne. Et si le fichier contient un
                                          caractere accentue, il lui faut « chcp 65001 »
                                          en tete, sinon cmd le lit en page OEM 850.
         autres       UTF-8 SANS BOM      git, les navigateurs et les editeurs modernes.

    2. LE MOJIBAKE : « Ã© », « Ã¨ », « â€™ ». Ce sont les traces d'un texte UTF-8 relu en
       latin-1 puis re-enregistre. Le fichier est alors valide en UTF-8 et pourtant faux :
       aucune verification d'encodage seule ne le voit.

    3. LES ACCENTS ABSENTS DU TEXTE AFFICHE. On ne regarde QUE ce que l'utilisateur lit :
       les arguments de Write-Ok / Warn / Fail / Info / Detail / Step / Title, le -Message
       de Write-Log, et les lignes « echo » des .cmd. Les COMMENTAIRES restent en ASCII,
       volontairement et par convention dans ce depot : ils ne sont pas verifies.

       Le lexique ne retient que des mots TOUJOURS accentues en francais. « modifie »,
       « installe », « annule » existent sans accent (« il modifie ») : les corriger
       casserait des phrases justes. Les participes en -ee, eux, ne trompent pas.

    Usage :
      pwsh -File .\scripts\dev\check-encoding.ps1            # verdict
      pwsh -File .\scripts\dev\check-encoding.ps1 -Detail    # ou et quoi
      pwsh -File .\scripts\dev\check-encoding.ps1 -Fix       # corrige, puis reverifie

    Codes de retour : 0 = tout est conforme ; 2 = au moins un manquement.
#>
param(
    # Lister chaque manquement, fichier par fichier.
    [switch] $Detail,
    # Corriger : reecrire avec le bon encodage, poser les accents manquants.
    [switch] $Fix
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SKIPPED = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')   # .claude : les worktrees y vivent, et un worktree est une copie du depot

# Mots TOUJOURS accentues : aucun d'eux n'existe sans accent en francais.
# Ecrits en minuscules ; la casse initiale du texte trouve est conservee.
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
    # Participes en -ee : jamais valides sans accent.
    'installee' = 'installée'; 'lancee' = 'lancée'; 'terminee' = 'terminée'
    'annulee' = 'annulée'; 'modifiee' = 'modifiée'; 'verifiee' = 'vérifiée'
    'echouee' = 'échouée'; 'deployee' = 'déployée'; 'enregistree' = 'enregistrée'
    'desactivee' = 'désactivée'; 'activee' = 'activée'; 'preparee' = 'préparée'
    'creee' = 'créée'; 'passee' = 'passée'; 'posee' = 'posée'; 'trouvee' = 'trouvée'
    # Ajoutes au fil des passages : chaque mot qui sort d'une correction partielle vient
    # ici. Une phrase a moitie accentuee est PIRE que la meme phrase en ASCII -- elle a
    # l'air d'un defaut d'encodage au lieu d'un choix.
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

# L'APOSTROPHE EST DE L'ASCII : elle passe partout, et rien ne justifie de la retirer.
# Je l'ai pourtant supprimee en meme temps que les accents, « par prudence » (28/08).
# En francais, les seuls mots d'UNE lettre sont « a » et « y » : une lettre parmi
# l/d/n/j/m/s/t/c suivie d'une voyelle est TOUJOURS une elision.
$ELISION = [regex]'(?<![\p{L}''])([ldnjmstcLDNJMSTC]) (?=[aeiouyhéèêàâîôûAEIOUYH])'

# LES MOTIFS SE CONSTRUISENT, ils ne s'ecrivent pas. Un fichier qui contient « C3 A9 »
# en clair se denonce lui-meme a chaque passage : l'outil etait son propre coupable.
$MOJIBAKE = @(
    ([char]0xC3 + [char]0xA9),   # e accent aigu, relu en latin-1
    ([char]0xC3 + [char]0xA8),   # e accent grave
    ([char]0xC3 + [char]0xA0),   # a accent grave
    ([char]0xC3 + [char]0xA7),   # c cedille
    ([char]0xC3 + [char]0xAA),   # e accent circonflexe
    ([char]0xC3 + [char]0xB4),   # o accent circonflexe
    ([char]0xE2 + [char]0x80 + [char]0x99),   # apostrophe typographique
    ([char]0xC2 + [char]0xAB),   # guillemet ouvrant
    ([char]0xC2 + [char]0xBB)    # guillemet fermant
)

# Le texte AFFICHE, et lui seul. Un commentaire non accentue est une convention du depot,
# pas un defaut : le verifier noierait le vrai signal.
$SHOWN_PS  = [regex]'(?m)(?:Write-(?:Ok|Warn|Fail|Info|Detail|Step|Title)|Say|Dire)\s+"([^"]*)"'
$SHOWN_MSG = [regex]'(?m)-Message\s+"([^"]*)"'
$SHOWN_CMD = [regex]'(?m)^\s*echo\s+(.+)$'

function Get-FileBytes { param([string]$Path) return [System.IO.File]::ReadAllBytes($Path) }
function Test-HasBom {
    param([byte[]]$Bytes)
    return ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
}
# Le fichier est-il de l'UTF-8 valide ? Un decodage STRICT leve sur le premier octet faux.
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

# La casse du mot trouve est rendue au mot corrige : « Deja » -> « Déjà ».
# LA REGLE PLUTOT QUE LA LISTE. Un mot francais termine par consonne + « ee » est un
# participe passe feminin : « relancee », « redemarree », « transferee ». Il n'y a pas
# d'exception -- et une regle n'oublie pas un mot, contrairement a un lexique.
$FEMININE_PAST = [regex]'(?<=[\p{L}]{2})(?<![aeiouy])ee(?![\p{L}])'

function Repair-FemininePast {
    param([string]$Text)
    return $FEMININE_PAST.Replace($Text, ([char]0xE9 + 'e'))
}

function Repair-Elisions {
    param([string]$Text)
    return $ELISION.Replace($Text, '$1' + [char]0x27)
}

function Repair-Accents {
    param([string]$Text)
    foreach ($k in $ACCENTED.Keys) {
        # « $Etat » n'est pas le mot « etat », « -Detail » n'est pas « détail » : ce qui
        # suit un $ est un NOM DE VARIABLE, ce qui suit un tiret est un NOM DE PARAMETRE.
        # Les accentuer casse le code, ou pire : documente une option qui n'existe pas.
        $Text = [regex]::Replace($Text, ('(?<![\p{L}$-])' + $k + 's?(?![\p{L}])'), {
            param($m)
            # Le « s » du pluriel est rendu tel qu'il a ete trouve.
            $good = $ACCENTED[$k]
            if ($m.Value.EndsWith('s') -and -not $k.EndsWith('s')) { $good = $good + 's' }
            if ($m.Value.Substring(0, 1) -cmatch '[A-Z]') { return $good.Substring(0, 1).ToUpper() + $good.Substring(1) }
            return $good
        }, 'IgnoreCase')
    }
    return $Text
}

$issues = @()   # @{ File; Kind; Message }
$fixed  = 0

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Extension -in '.ps1', '.psd1', '.psm1', '.cmd', '.bat', '.md', '.html', '.css', '.js', '.json' }

foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }

    $bytes = Get-FileBytes $f.FullName
    if ($bytes.Length -eq 0) { continue }
    $ext   = $f.Extension.ToLowerInvariant()
    $text0 = Get-Text $f.FullName
    $text  = $text0
    # LE BOM NE SE JUSTIFIE QUE PAR UN ACCENT A PROTEGER. Sans caractere non-ASCII, un
    # .ps1 se lit pareil partout, avec ou sans.
    # TOUS LES .ps1 PORTENT LE BOM, accentues ou non. La regle precedente ne l'exigeait
    # que des fichiers deja accentues : plus juste techniquement, pire en pratique. Le
    # jour ou l'on ajoute un accent dans un fichier jusque-la ASCII, il devient
    # silencieusement non conforme. Une regle uniforme n'a pas de bord ou tomber.
    <#
        AUCUN CARACTERE DE CONTROLE DANS UNE SOURCE.

        Trois fois le 31/08, une chaine ecrite depuis un script Python a transforme un
        antislash suivi d'une lettre en caractere de controle : «  » est devenu un
        RETOUR ARRIERE dans une expression reguliere qui ne trouvait plus rien, «  » un
        SAUT DE PAGE au milieu de « System32ind.exe », « 
 » un retour a la ligne qui
        a coupe une commande en deux. Chaque fois, le fichier avait l'air normal a la
        lecture et se comportait de travers.

        Tabulation, retour chariot et saut de ligne sont normaux ; tout le reste en dessous
        de l'espace est une trace d'echappement rate. C'est mecanique, donc c'est ici que
        ca se verifie -- pas dans mon attention.
    #>
    # PAS DE REGEX ICI : on compare des CODES. La premiere version de cette regle
    # portait une classe « backslash-x-zero-zero... » qui a ete detruite par une
    # echappee de plus -- la regle est devenue « [--] » et accusait les tirets. Une
    # verification des echappements ne peut pas dependre d une echappee.
    for ($i = 0; $i -lt $text0.Length; $i++) {
        $code = [int]$text0[$i]
        if ($code -ge 32 -or $code -eq 9 -or $code -eq 10 -or $code -eq 13) { continue }
        $ligne = ($text0.Substring(0, $i) -split "`n").Count
        $issues += @{ File = $rel; Kind = 'controle'
                      Message = ("caractere de controle 0x{0:X2} ligne {1} -- un echappement a mal tourne" -f $code, $ligne) }
        break   # une par fichier suffit a le signaler
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
    # ON NE REGARDE PAS LES COMMENTAIRES. Cet outil-ci, et console-ui.ps1, CITENT du
    # mojibake pour expliquer a quoi il ressemble : un verificateur qui s'alarme de sa
    # propre documentation apprend a son lecteur a ignorer ses alarmes.
    $code = [regex]::Replace($text, '(?s)<#.*?#>', '')
    $code = [regex]::Replace($code, '(?m)^\s*(#|REM\b).*$', '')
    foreach ($m in $MOJIBAKE) {
        if ($code.Contains($m)) {
            $issues += @{ File = $rel; Kind = 'mojibake'; Message = ("contient « " + $m + " » : de l'UTF-8 relu en latin-1") }
            break
        }
    }

    # --- 3. chcp pour un .cmd accentue ---
    if ($ext -in '.cmd', '.bat') {
        $hasAccent = $text -cmatch '[^\x00-\x7F]'
        $hasChcp   = $text -match '(?im)^\s*@?chcp\s+65001'
        if ($hasAccent -and -not $hasChcp) {
            $issues += @{ File = $rel; Kind = 'chcp'; Message = 'accents sans « chcp 65001 » : cmd.exe les lira en page OEM 850' }
        }
    }

    # --- 4. Accents absents du texte affiche ---
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
                # On remplace la PHRASE ENTIERE trouvee, pas le mot : deux libelles peuvent
                # partager un mot, et un remplacement global toucherait aussi les commentaires.
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

# --- 5. Le fichier de libelles ----------------------------------------------------------
#
# LE TEXTE A DEMENAGE, LA VERIFICATION SUIT. Depuis que les libelles vivent dans lang/,
# c'est LA que les accents manquent ou reviennent : les verifier dans les .ps1 ne dirait
# plus rien. Le JSON se corrige aussi avec -Fix.
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
            foreach ($prop in ($obj.PSObject.Properties | Sort-Object Name)) {
                $v = [string]$prop.Value
                $good = Repair-Elisions (Repair-FemininePast (Repair-Accents $v))
                if ($good -cne $v) {
                    $issues += @{ File = $rel; Kind = 'accents'; Message = ('« ' + $v + ' »') }
                    $changed = $true
                }
                $out[$prop.Name] = $good
            }
            if ($Fix -and $changed) {
                [System.IO.File]::WriteAllText($lf.FullName, ($out | ConvertTo-Json -Depth 3),
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
