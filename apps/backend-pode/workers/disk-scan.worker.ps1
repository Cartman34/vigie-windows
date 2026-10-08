# @author Florent HAZARD <f.hazard@sowapps.com>
<# A DETACHED worker: the analysis of what the disc is used by.

   Intent: walk a tree that can be ENORMOUS without ever making a request wait, and without memory growing with
   the number of files.
   Usage: the disk-analyze action starts it (in a hidden window), the card goes to "under way" and follows the
   progress written here. It writes ONLY into var/cache/diskscan.json. Read only on the disc being analysed.

   WHY A WORKER: walking a disc takes tens of seconds; the HTTP request must answer at once.

   HOW IT IS OPTIMISED (the owner's requirement: the tree can be ENORMOUS):
   - ONE single pass, in .NET (System.IO.DirectoryInfo.EnumerateFiles/Directories with EnumerationOptions). The
     FileInfo objects the enumeration returns already carry their size: not one extra system call per file.
   - An ITERATIVE walk (an explicit stack) in post-order: no PowerShell recursion, so no depth limit and no call
     cost.
   - NOTHING is kept globally: each folder passes a SUM up to its parent, and the parent keeps only its $topN
     largest children; the rest is folded into an "others" total. So the memory is bounded by topN^depth, not by
     the number of files on the disc (millions stay at a constant memory cost).
   - Beyond the depth that was asked for, we go on MEASURING but no longer keep the names: the sum stays right,
     the useless detail disappears.
   - The junction points and symbolic links (ReparsePoint) are ignored: without that, a profile's legacy
     Application Data loops for ever and the sizes are counted twice. The HIDDEN and SYSTEM folders, on the other
     hand, are counted (they are often the heaviest) -- which .NET's default sets aside, hence the explicit
     AttributesToSkip. #>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { exit 1 }
. (Join-Path $Backend 'lib/common.ps1')

# --- Parametres (JSON base64) ------------------------------------------------
$rootPath = 'C:\'
$profondeur   = 3
$topN         = 10
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        if ($a.root)  { $rootPath = "$($a.root)" }
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
# A stop flag left by an earlier analysis would stop this one at once.
if (Test-Path -LiteralPath $stopFile) { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue }

$debut = Get-Date
Update-StateJson -Path $outFile -Set @{
    scan = @{ root = $rootPath; startedAt = $debut.ToUniversalTime().ToString('s')
              at = $debut.ToUniversalTime().ToString('s'); dirs = 0; files = 0; bytes = 0
              depth = $profondeur; top = $topN; current = $rootPath }
} | Out-Null

# --- Options d'enumeration ---------------------------------------------------
$opts = [System.IO.EnumerationOptions]::new()
$opts.IgnoreInaccessible      = $true    # un dossier refuse ne fait pas echouer le parcours
$opts.RecurseSubdirectories   = $false   # la descente est PILOTEE ici (profondeur, progression)
$opts.ReturnSpecialDirectories = $false
$opts.AttributesToSkip        = [System.IO.FileAttributes]::ReparsePoint

# --- Outils ------------------------------------------------------------------
# It keeps only the $Max largest elements; the others are folded into a total (size plus count), which will be
# stated on screen: nothing disappears in silence.
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

function New-Node {
    param([string]$NodePath, [string]$NodeName, [int]$Prof, $Parent)
    @{ p = $NodePath; n = $NodeName; d = $Prof; parent = $Parent; etat = 0
       own = [long]0; acc = [long]0; total = [long]0; files = 0; maxKid = [long]0
       kids = [System.Collections.Generic.List[hashtable]]::new()
       tops = [System.Collections.Generic.List[hashtable]]::new()
       au = @{ s = [long]0; c = 0 }; af = @{ s = [long]0; c = 0 } }
}

# --- Parcours ----------------------------------------------------------------
$rootNode = New-Node -NodePath $rootPath -NodeName $rootPath -Prof 0 -Parent $null
$pile = [System.Collections.Generic.Stack[hashtable]]::new()
$pile.Push($rootNode)

# GLOBAL rankings (bounded): what the user is really looking for, "who is eating the space", without having to
# unfold the tree level by level.
$folderCandidates = [System.Collections.Generic.List[hashtable]]::new()
$fileCandidates = [System.Collections.Generic.List[hashtable]]::new()
$PALMARES = 20

$gDirs = 0; $gFiles = 0; $gBytes = [long]0
$stopped = $false; $erreur = $null
$dernierEcrit = Get-Date
$rootLen = $rootPath.TrimEnd('\').Length

try {
    while ($pile.Count -gt 0) {
        $n = $pile.Pop()

        if ($n.etat -eq 0) {
            # The FIRST visit: measure the folder's files, push its subfolders.
            $n.etat = 1
            $pile.Push($n)                     # revisite APRES ses enfants (post-ordre)
            $gDirs++
            $detail = ($n.d -lt $profondeur)   # au-dela, on mesure sans garder les noms
            $di = $null
            try { $di = [System.IO.DirectoryInfo]::new($n.p) } catch { }
            if ($di) {
                try {
                    foreach ($f in $di.EnumerateFiles('*', $opts)) {
                        $size = [long]$f.Length
                        $n.own += $size
                        $n.files++
                        $gFiles++
                        $gBytes += $size
                        if ($detail) {
                            $n.tops.Add(@{ n = $f.Name; s = $size })
                            if ($n.tops.Count -gt (4 * $topN)) { Limit-Detail $n.tops $topN $n.af }
                        }
                        if ($size -gt 0) {
                            $fileCandidates.Add(@{ n = $f.FullName; s = $size })
                            if ($fileCandidates.Count -gt (4 * $PALMARES)) {
                                $t = @($fileCandidates | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
                                $fileCandidates.Clear(); foreach ($x in $t) { $fileCandidates.Add($x) }
                            }
                        }
                    }
                } catch { }
                try {
                    foreach ($d in $di.EnumerateDirectories('*', $opts)) {
                        $pile.Push((New-Node -NodePath $d.FullName -NodeName $d.Name -Prof ($n.d + 1) -Parent $n))
                    }
                } catch { }
            }

            # Progress plus the stop request: at most once every second and a half.
            if (((Get-Date) - $dernierEcrit).TotalMilliseconds -gt 1500) {
                $dernierEcrit = Get-Date
                if (Test-Path -LiteralPath $stopFile) { $stopped = $true; break }
                Update-StateJson -Path $outFile -Set @{
                    scan = @{ root = $rootPath
                              startedAt = $debut.ToUniversalTime().ToString('s')
                              at = (Get-Date).ToUniversalTime().ToString('s')
                              dirs = $gDirs; files = $gFiles; bytes = $gBytes
                              depth = $profondeur; top = $topN; current = $n.p }
                } | Out-Null
            }
            continue
        }

        # The SECOND visit: every child has finished, the total is known.
        $n.total = $n.own + $n.acc
        Limit-Detail $n.kids $topN $n.au
        Limit-Detail $n.tops $topN $n.af

        # The ranking of the large folders: we keep only the folders WHERE THE SPACE IS SHARED OUT. Without that
        # filter, the ranking is a chain of ancestors all weighing the same thing (a game folder, then its
        # launcher, then its library, then its common folder, 259 GB on every line): twenty lines for one single
        # piece of information. A folder of which a single child explains almost all the weight teaches nothing:
        # it is the child that must be shown.
        $revelateur = ($n.total -gt 0 -and (([double]$n.maxKid / [double]$n.total) -lt 0.85))
        if ($n.d -ge 1 -and $revelateur) {
            $rel = $n.p.Substring([Math]::Min($rootLen, $n.p.Length)).TrimStart('\')
            $folderCandidates.Add(@{ n = $rel; s = [long]$n.total; f = $n.files })
            if ($folderCandidates.Count -gt (10 * $PALMARES)) {
                $t = @($folderCandidates | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
                $folderCandidates.Clear(); foreach ($x in $t) { $folderCandidates.Add($x) }
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
            # The node has passed its sum up: we release it (bounded memory).
            $n.parent = $null; $n.kids = $null; $n.tops = $null
        }
    }
} catch {
    $erreur = $_.Exception.Message
}

# --- Resultat ----------------------------------------------------------------
$fin = Get-Date
if ($stopped) {
    # A stop returns a PARTIAL result: we do not write it over the last complete result, which stays useful. We
    # only say that the analysis was interrupted.
    Update-StateJson -Path $outFile -Set @{
        scan = @{ canceled = $true; root = $rootPath
                  startedAt = $debut.ToUniversalTime().ToString('s')
                  at = $fin.ToUniversalTime().ToString('s')
                  dirs = $gDirs; files = $gFiles; depth = $profondeur; top = $topN }
    } | Out-Null
    try { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue } catch { }
    Write-Log -Backend $Backend -Name 'diskscan' -Message (Get-Label 'disk-scan.analyse-interrompue-apres-dossiers' $rootPath $gDirs)
} else {
    $arbre = @{ n = $rootPath; s = [long]($rootNode.own + $rootNode.acc); f = $rootNode.files
                k = @($rootNode.kids); t = @($rootNode.tops) }
    if ($rootNode.au.s -gt 0) { $arbre.o  = @{ s = [long]$rootNode.au.s; c = $rootNode.au.c } }
    if ($rootNode.af.s -gt 0) { $arbre.of = @{ s = [long]$rootNode.af.s; c = $rootNode.af.c } }
    $topFolders = @($folderCandidates | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
    $topFiles = @($fileCandidates | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $PALMARES)
    # TWO distinct blocks, and that is deliberate: `scan` = the state of the LAST task (under way, finished,
    # interrupted); `result` = the last COMPLETE analysis, the one the tree describes. Mixing them made the tree
    # date from the day of an interruption.
    $bilan = @{ at = $fin.ToUniversalTime().ToString('s')
                startedAt = $debut.ToUniversalTime().ToString('s')
                seconds = [int]($fin - $debut).TotalSeconds
                dirs = $gDirs; files = $gFiles; bytes = [long]$arbre.s
                root = $rootPath; depth = $profondeur; top = $topN; error = $erreur }
    Update-StateJson -Path $outFile -Depth 24 -Set @{
        scan = @{ canceled = $false; root = $rootPath
                  startedAt = $debut.ToUniversalTime().ToString('s')
                  at = $fin.ToUniversalTime().ToString('s')
                  seconds = [int]($fin - $debut).TotalSeconds
                  dirs = $gDirs; files = $gFiles; bytes = [long]$arbre.s
                  depth = $profondeur; top = $topN
                  error = $erreur }
        result     = $bilan
        tree       = $arbre
        bigFolders = $topFolders
        bigFiles   = $topFiles
    } | Out-Null
    Write-Log -Backend $Backend -Name 'diskscan' -Message (Get-Label 'disk-scan.dossiers-fichiers' $rootPath $gDirs $gFiles $([int]($fin-$debut).TotalSeconds))
}

# The card refreshes at the next access, without waiting for the TTL.
try { Remove-ProbeCache -Names @('disk.probe.ps1') -Backend $Backend } catch { }
# THE OUTCOME LEAVES BY THE EXIT CODE, read by the watcher. An analysis stopped on request is not a failure.
if ($erreur) { Write-Output ('[X] ' + $erreur); exit 1 }
exit 0