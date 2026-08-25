<# Worker DETACHE : analyse de la consommation du disque.

   POURQUOI UN WORKER : parcourir un disque prend des dizaines de secondes ; la requete
   HTTP, elle, doit repondre tout de suite. L'action lance ce worker (fenetre cachee), la
   carte passe en "en cours" et suit la progression ecrite ici.

   COMMENT C'EST OPTIMISE (exigence utilisateur : l'arborescence peut etre ENORME) :
   - Un SEUL passage, en .NET (System.IO.DirectoryInfo.EnumerateFiles/Directories avec
     EnumerationOptions). Les FileInfo rendus par l'enumeration portent deja leur taille :
     aucun appel systeme supplementaire par fichier.
   - Parcours ITERATIF (pile explicite) en post-ordre : pas de recursion PowerShell, donc
     pas de limite de profondeur ni de cout d'appel.
   - RIEN n'est conserve globalement : chaque dossier remonte a son parent une SOMME, et
     le parent ne garde que les $topN plus gros enfants ; le reste est replie dans un
     cumul "autres". La memoire est donc bornee par topN^profondeur, pas par le nombre
     de fichiers du disque (des millions restent a cout memoire constant).
   - Au-dela de la profondeur demandee, on continue de MESURER mais on ne garde plus les
     noms : la somme reste juste, le detail inutile disparait.
   - Les points de jonction / liens symboliques (ReparsePoint) sont ignores : sans cela
     C:\Users\...\Application Data reboucle a l'infini et les tailles sont comptees deux
     fois. Les dossiers CACHES et SYSTEME, eux, sont bien comptes (ils pesent souvent le
     plus lourd) -- ce que le defaut de .NET ecarte, d'ou l'AttributesToSkip explicite.

   N'ecrit QUE dans var/cache/diskscan.json. Lecture seule sur le disque analyse. #>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

# --- Parametres (JSON base64) ------------------------------------------------
$racineChemin = 'C:\'
$profondeur   = 3
$topN         = 10
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        if ($a.root)  { $racineChemin = "$($a.root)" }
        if ($a.depth) { $profondeur   = [int]$a.depth }
        if ($a.top)   { $topN         = [int]$a.top }
    }
} catch { }
if ($profondeur -lt 1)  { $profondeur = 1 }
if ($profondeur -gt 6)  { $profondeur = 6 }   # au-dela, le JSON grossit sans rien apprendre
if ($topN -lt 3)        { $topN = 3 }
if ($topN -gt 30)       { $topN = 30 }

$outFile  = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan.json'
$stopFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan.stop'
# Un drapeau d'arret laisse par une analyse precedente arreterait celle-ci aussitot.
if (Test-Path -LiteralPath $stopFile) { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue }

$debut = Get-Date
Update-StateJson -Path $outFile -Set @{
    scan = @{ running = $true; root = $racineChemin; startedAt = $debut.ToUniversalTime().ToString('s')
              at = $debut.ToUniversalTime().ToString('s'); dirs = 0; files = 0; bytes = 0
              depth = $profondeur; top = $topN; current = $racineChemin }
} | Out-Null

# --- Options d'enumeration ---------------------------------------------------
$opts = [System.IO.EnumerationOptions]::new()
$opts.IgnoreInaccessible      = $true    # un dossier refuse ne fait pas echouer le parcours
$opts.RecurseSubdirectories   = $false   # la descente est PILOTEE ici (profondeur, progression)
$opts.ReturnSpecialDirectories = $false
$opts.AttributesToSkip        = [System.IO.FileAttributes]::ReparsePoint

# --- Outils ------------------------------------------------------------------
# Ne conserve que les $Max plus gros elements ; les autres sont replies dans un cumul
# (taille + nombre), qui sera dit a l'ecran : rien ne disparait en silence.
function Limit-Detail {
    param($Liste, [int]$Max, [hashtable]$Autres)
    if ($Liste.Count -le $Max) { return }
    $trie = @($Liste | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending)
    $Liste.Clear()
    for ($i = 0; $i -lt $Max; $i++) { $Liste.Add($trie[$i]) }
    for ($i = $Max; $i -lt $trie.Count; $i++) {
        $Autres.s += [long]$trie[$i].s
        $Autres.c += 1
    }
}

function New-Noeud {
    param([string]$Chemin, [string]$Nom, [int]$Prof, $Parent)
    @{ p = $Chemin; n = $Nom; d = $Prof; parent = $Parent; etat = 0
       own = [long]0; acc = [long]0; total = [long]0; files = 0; maxKid = [long]0
       kids = [System.Collections.Generic.List[hashtable]]::new()
       tops = [System.Collections.Generic.List[hashtable]]::new()
       au = @{ s = [long]0; c = 0 }; af = @{ s = [long]0; c = 0 } }
}

# --- Parcours ----------------------------------------------------------------
$racine = New-Noeud -Chemin $racineChemin -Nom $racineChemin -Prof 0 -Parent $null
$pile = [System.Collections.Generic.Stack[hashtable]]::new()
$pile.Push($racine)

# Palmares GLOBAUX (bornes) : ce que l'utilisateur cherche vraiment, "qui mange la place",
# sans avoir a deplier l'arbre niveau par niveau.
$grosDossiers = [System.Collections.Generic.List[hashtable]]::new()
$grosFichiers = [System.Collections.Generic.List[hashtable]]::new()
$PALMARES = 20

$gDirs = 0; $gFiles = 0; $gBytes = [long]0
$arret = $false; $erreur = $null
$dernierEcrit = Get-Date
$lgRacine = $racineChemin.TrimEnd('\').Length

try {
    while ($pile.Count -gt 0) {
        $n = $pile.Pop()

        if ($n.etat -eq 0) {
            # PREMIERE visite : mesurer les fichiers du dossier, empiler ses sous-dossiers.
            $n.etat = 1
            $pile.Push($n)                     # revisite APRES ses enfants (post-ordre)
            $gDirs++
            $detail = ($n.d -lt $profondeur)   # au-dela, on mesure sans garder les noms
            $di = $null
            try { $di = [System.IO.DirectoryInfo]::new($n.p) } catch { }
            if ($di) {
                try {
                    foreach ($f in $di.EnumerateFiles('*', $opts)) {
                        $taille = [long]$f.Length
                        $n.own += $taille
                        $n.files++
                        $gFiles++
                        $gBytes += $taille
                        if ($detail) {
                            $n.tops.Add(@{ n = $f.Name; s = $taille })
                            if ($n.tops.Count -gt (4 * $topN)) { Limit-Detail $n.tops $topN $n.af }
                        }
                        if ($taille -gt 0) {
                            $grosFichiers.Add(@{ n = $f.FullName; s = $taille })
                            if ($grosFichiers.Count -gt (4 * $PALMARES)) {
                                $t = @($grosFichiers | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
                                $grosFichiers.Clear(); foreach ($x in $t) { $grosFichiers.Add($x) }
                            }
                        }
                    }
                } catch { }
                try {
                    foreach ($d in $di.EnumerateDirectories('*', $opts)) {
                        $pile.Push((New-Noeud -Chemin $d.FullName -Nom $d.Name -Prof ($n.d + 1) -Parent $n))
                    }
                } catch { }
            }

            # Progression + demande d'arret : au plus une fois par seconde et demie.
            if (((Get-Date) - $dernierEcrit).TotalMilliseconds -gt 1500) {
                $dernierEcrit = Get-Date
                if (Test-Path -LiteralPath $stopFile) { $arret = $true; break }
                Update-StateJson -Path $outFile -Set @{
                    scan = @{ running = $true; root = $racineChemin
                              startedAt = $debut.ToUniversalTime().ToString('s')
                              at = (Get-Date).ToUniversalTime().ToString('s')
                              dirs = $gDirs; files = $gFiles; bytes = $gBytes
                              depth = $profondeur; top = $topN; current = $n.p }
                } | Out-Null
            }
            continue
        }

        # SECONDE visite : tous les enfants ont fini, le total est connu.
        $n.total = $n.own + $n.acc
        Limit-Detail $n.kids $topN $n.au
        Limit-Detail $n.tops $topN $n.af

        # Palmares des gros dossiers : on ne retient que les dossiers OU LA PLACE SE
        # PARTAGE. Sans ce filtre, le classement est une chaine d'ancetres qui pesent tous
        # la meme chose (Jeux > Steam > steamapps > common, 259 Go a chaque ligne) : vingt
        # lignes pour un seul renseignement. Un dossier dont un unique enfant explique
        # presque tout le poids n'apprend rien : c'est l'enfant qu'il faut montrer.
        $revelateur = ($n.total -gt 0 -and (([double]$n.maxKid / [double]$n.total) -lt 0.85))
        if ($n.d -ge 1 -and $revelateur) {
            $rel = $n.p.Substring([Math]::Min($lgRacine, $n.p.Length)).TrimStart('\')
            $grosDossiers.Add(@{ n = $rel; s = [long]$n.total; f = $n.files })
            if ($grosDossiers.Count -gt (10 * $PALMARES)) {
                $t = @($grosDossiers | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
                $grosDossiers.Clear(); foreach ($x in $t) { $grosDossiers.Add($x) }
            }
        }

        $p = $n.parent
        if ($p) {
            $p.acc   += $n.total
            $p.files += $n.files
            if ($n.total -gt $p.maxKid) { $p.maxKid = [long]$n.total }
            if ($p.d -lt $profondeur) {
                $e = @{ n = $n.n; s = [long]$n.total; f = $n.files }
                if ($n.kids.Count) { $e.k = @($n.kids) }
                if ($n.tops.Count) { $e.t = @($n.tops) }
                if ($n.au.s -gt 0) { $e.o = @{ s = [long]$n.au.s; c = $n.au.c } }
                if ($n.af.s -gt 0) { $e.of = @{ s = [long]$n.af.s; c = $n.af.c } }
                $p.kids.Add($e)
                if ($p.kids.Count -gt (4 * $topN)) { Limit-Detail $p.kids $topN $p.au }
            }
            # Le noeud a rendu sa somme : on le libere (memoire bornee).
            $n.parent = $null; $n.kids = $null; $n.tops = $null
        }
    }
} catch {
    $erreur = $_.Exception.Message
}

# --- Resultat ----------------------------------------------------------------
$fin = Get-Date
if ($arret) {
    # Un arret rend un resultat PARTIEL : on ne l'ecrit pas par-dessus le dernier resultat
    # complet, qui reste utile. On dit seulement que l'analyse a ete interrompue.
    Update-StateJson -Path $outFile -Set @{
        scan = @{ running = $false; canceled = $true; root = $racineChemin
                  startedAt = $debut.ToUniversalTime().ToString('s')
                  at = $fin.ToUniversalTime().ToString('s')
                  dirs = $gDirs; files = $gFiles; depth = $profondeur; top = $topN }
    } | Out-Null
    try { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue } catch { }
    Write-Log -Backend $Backend -Name 'diskscan' -Message ("$racineChemin : analyse interrompue apres $gDirs dossiers")
} else {
    $arbre = @{ n = $racineChemin; s = [long]($racine.own + $racine.acc); f = $racine.files
                k = @($racine.kids); t = @($racine.tops) }
    if ($racine.au.s -gt 0) { $arbre.o  = @{ s = [long]$racine.au.s; c = $racine.au.c } }
    if ($racine.af.s -gt 0) { $arbre.of = @{ s = [long]$racine.af.s; c = $racine.af.c } }
    $topDossiers = @($grosDossiers | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
    $topFichiers = @($grosFichiers | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
    # DEUX blocs distincts, et c'est voulu : `scan` = l'etat de la DERNIERE tache (en
    # cours, terminee, interrompue) ; `result` = la derniere analyse COMPLETE, celle que
    # l'arbre decrit. Les melanger faisait dater l'arbre du jour d'une interruption.
    $bilan = @{ at = $fin.ToUniversalTime().ToString('s')
                startedAt = $debut.ToUniversalTime().ToString('s')
                seconds = [int]($fin - $debut).TotalSeconds
                dirs = $gDirs; files = $gFiles; bytes = [long]$arbre.s
                root = $racineChemin; depth = $profondeur; top = $topN; error = $erreur }
    Update-StateJson -Path $outFile -Depth 24 -Set @{
        scan = @{ running = $false; canceled = $false; root = $racineChemin
                  startedAt = $debut.ToUniversalTime().ToString('s')
                  at = $fin.ToUniversalTime().ToString('s')
                  seconds = [int]($fin - $debut).TotalSeconds
                  dirs = $gDirs; files = $gFiles; bytes = [long]$arbre.s
                  depth = $profondeur; top = $topN
                  error = $erreur }
        result     = $bilan
        tree       = $arbre
        bigFolders = $topDossiers
        bigFiles   = $topFichiers
    } | Out-Null
    Write-Log -Backend $Backend -Name 'diskscan' -Message ("$racineChemin : $gDirs dossiers, $gFiles fichiers, $([int]($fin-$debut).TotalSeconds) s")
}

# La carte se rafraichit au prochain acces, sans attendre le TTL.
try { Remove-ProbeCache -Names @('disk.probe.ps1') -Backend $Backend } catch { }
