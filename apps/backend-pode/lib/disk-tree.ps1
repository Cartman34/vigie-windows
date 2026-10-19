# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, paths, store, var
<#
    Intent: WALKING THE DISK ONE LEVEL AT A TIME (D60). The interface never receives a whole tree -- it asks for
    one level and asks again when the user unfolds -- because a complete tree is a JSON that grows without limit
    and a card carrying what nobody will look at. Two sources, in order: the cache of the last analysis, then a
    partial walk on demand, which is remembered so that unfolding the same folder twice does not walk it twice.
    Usage: dot-sourced by common.ps1, never run on its own. The subject is the TREE: what a disk is worth over
    time -- its free fall, its watch -- belongs to the surveillance, not here (S28).
#>

# --- THE DISK TREE, LEVEL BY LEVEL (D60, revised on 26/08) --------------------
# The interface NEVER receives the whole tree: it asks for ONE level, and asks again when the
# user unfolds. The owner's requirement -- a complete tree is a JSON that grows without
# limit, and a card carrying what nobody will look at.
#
# Two sources, in this order:
#   1. the CACHE of the last analysis (var/cache/diskscan.json): already computed, free;
#   2. a PARTIAL COMPUTATION on demand, when the level asked for lies beyond what the
#      analysis kept. Only the sub-tree asked for is then walked.
# What is computed on demand is remembered (diskscan-levels.json): unfolding the same folder
# twice does not walk it twice.
$script:SEP = [string][char]92

# The total size of a folder, in one .NET pass. Bounded in time: past that, what we have is
# returned while SAYING so (partial), rather than keeping the interface waiting.
function Measure-FolderQuick {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutMs = 8000
    )
    $opts = [System.IO.EnumerationOptions]::new()
    $opts.IgnoreInaccessible    = $true
    $opts.RecurseSubdirectories = $true
    $opts.AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
    $size = [long]0; $nb = 0; $partial = $false
    $chrono = [Diagnostics.Stopwatch]::StartNew()
    try {
        $di = [System.IO.DirectoryInfo]::new($Path)
        foreach ($f in $di.EnumerateFiles('*', $opts)) {
            $size += [long]$f.Length
            $nb++
            if (($nb % 4096) -eq 0 -and $chrono.ElapsedMilliseconds -gt $TimeoutMs) { $partial = $true; break }
        }
    } catch { }
    [pscustomobject]@{ Size = $size; Files = $nb; Partial = $partial }
}

# The DIRECT children of $Path, from the largest to the smallest.
function Get-DiskTreeLevel {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Backend = (Get-BackendRoot),
        [int]$Top = 0
    )
    $stateFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan.json'
    $State = $null
    if (Test-Path -LiteralPath $stateFile) {
        try { $State = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { }
    }
    if (-not $State -or -not $State.tree) { throw "Aucune analyse disponible : lancez d'abord l'analyse de l'espace." }

    $rootPath = if ($State.result -and $State.result.root) { "$($State.result.root)" } else { "$($State.scan.root)" }
    $total  = [long]$State.tree.s
    if ($Top -le 0) {
        $Top = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskScanTop' -Backend $Backend)
        if ($Top -le 0) { $Top = 10 }
    }

    # The path asked for must belong to the analysis: we do not explore the disk on a
    # client's request, we explore the tree already analysed.
    $plein = $Path
    try { $plein = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { }
    if (-not $plein.ToLower().StartsWith($rootPath.ToLower())) { throw "Hors de l'analyse en cours : $Path" }

    $pct = { param($o) if ($total -gt 0) { ('{0:N1}' -f ([double]$o / $total * 100)) } else { '0,0' } }

    # 1) Does the analysis cache already hold this level?
    $noeud = $State.tree
    $coupe = $rootPath.TrimEnd([char]92).Length
    $reste = $plein.Substring([Math]::Min($coupe, $plein.Length)).Trim([char]92)
    $trouve = $true
    if ($reste) {
        foreach ($pas in ($reste.Split([char]92))) {
            if (-not $pas) { continue }
            $suivant = @($noeud.k | Where-Object { "$($_.n)" -eq $pas })[0]
            if (-not $suivant) { $trouve = $false; break }
            $noeud = $suivant
        }
    }
    if ($trouve -and $noeud -and $noeud.k -and @($noeud.k).Count) {
        $enfants = @($noeud.k | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | ForEach-Object {
            [ordered]@{
                n = "$($_.n)"; path = (Join-Path $plein "$($_.n)")
                s = [long]$_.s; size = (Format-ByteSize ([long]$_.s))
                pct = (& $pct ([long]$_.s)); f = [int]$_.f; more = $true
            }
        })
        $files = @($noeud.t | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | ForEach-Object {
            [ordered]@{ n = "$($_.n)"; size = (Format-ByteSize ([long]$_.s)) }
        })
        $autres = $null
        if ($noeud.o) { $autres = [ordered]@{ c = [int]$noeud.o.c; size = (Format-ByteSize ([long]$noeud.o.s)) } }
        return [pscustomobject]@{ path = $plein; source = 'analyse'; children = $enfants; files = $files; others = $autres }
    }

    # 2) A level the analysis did not keep: a PARTIAL COMPUTATION, bounded to this folder.
    $memo = Get-VarPath -Backend $Backend -Kind 'cache' -File 'diskscan-levels.json'
    $cle  = $plein.ToLower()
    try {
        if (Test-Path -LiteralPath $memo) {
            $m = Get-Content -LiteralPath $memo -Raw | ConvertFrom-Json
            $e = $m.PSObject.Properties | Where-Object { $_.Name -eq $cle } | Select-Object -First 1
            if ($e -and $e.Value) {
                return [pscustomobject]@{ path = $plein; source = 'memoire'; children = @($e.Value.children); files = @($e.Value.files); others = $null }
            }
        }
    } catch { }

    $opts = [System.IO.EnumerationOptions]::new()
    $opts.IgnoreInaccessible    = $true
    $opts.RecurseSubdirectories = $false
    $opts.AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
    $di = $null
    try { $di = [System.IO.DirectoryInfo]::new($plein) } catch { }
    if (-not $di -or -not $di.Exists) { throw "Dossier introuvable : $plein" }

    $sous = @()
    try { $sous = @($di.EnumerateDirectories('*', $opts)) } catch { }
    $calcules = @(foreach ($d in $sous) {
        $mes = Measure-FolderQuick -Path $d.FullName
        [ordered]@{
            n = $d.Name; path = $d.FullName; s = [long]$mes.Size
            size = (Format-ByteSize ([long]$mes.Size)); pct = (& $pct ([long]$mes.Size))
            f = [int]$mes.Files; more = $true; partial = [bool]$mes.Partial
        }
    })
    $calcules = @($calcules | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending | Select-Object -First $Top)

    $fic = @()
    try {
        $fic = @($di.EnumerateFiles('*', $opts) | Sort-Object Length -Descending | Select-Object -First $Top | ForEach-Object {
            [ordered]@{ n = $_.Name; size = (Format-ByteSize ([long]$_.Length)) }
        })
    } catch { }

    try {
        Update-StateJson -Path $memo -Depth 12 -Set @{ $cle = @{ children = $calcules; files = $fic; at = (Get-Date).ToUniversalTime().ToString('s') } } | Out-Null
    } catch { }
    return [pscustomobject]@{ path = $plein; source = 'calcul'; children = $calcules; files = $fic; others = $null }
}
