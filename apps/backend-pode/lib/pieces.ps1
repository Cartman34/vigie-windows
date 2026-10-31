# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: LOADING ONLY THE PIECES ONE USES, for a process that is not the server app. `common.ps1` loads the
    fifty-six of them, which costs 62 MB of memory measured -- seventy times the 808 KB they weigh on disk,
    because PowerShell keeps the syntax tree, the compiled form and the metadata of every parameter of all 387
    functions. The server needs them all; a resident that watches for a game needs five.
    Usage: dot-sourced INSTEAD of common.ps1, then `foreach ($f in (Get-VigiePieceFiles -Pieces games, residents -LibDir $dir)) { . $f }`. Never by the
    server app, which wants everything. It reads the `@uses:` headers to pull in what those pieces need in turn,
    so a caller names what it uses and nothing else.
#>

<#
    WHAT A PIECE NEEDS IS READ FROM THE PIECE, NEVER LISTED HERE.

    A list written here would be wrong the day a piece gains a dependency, and nothing would say so -- the caller
    would simply die on a missing name, in a process nobody is watching. The `@uses:` headers are already kept
    true by check-layers, which compares them to the real calls at every delivery: this reads the same line.
#>
function Get-VigiePieceUses {
    param([Parameter(Mandatory)][string]$Piece, [Parameter(Mandatory)][string]$LibDir)
    $file = Join-Path $LibDir ($Piece + '.ps1')
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    foreach ($line in [IO.File]::ReadLines($file)) {
        if ($line -match '^[^\S\r\n]*#[^\S\r\n]*@uses:[^\S\r\n]*(.*)$') {
            $said = $Matches[1].Trim()
            if (-not $said -or $said -eq 'rien') { return @() }
            return @($said -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        # The header is at the top: past the first function, there is nothing left to read.
        if ($line -match '^function ') { break }
    }
    return @()
}

<#
    THE FLOOR IS ALWAYS LOADED, because everything leans on it and because it is what says WHERE things are: a
    piece that asks for nothing still needs to know the tree and how to write a line down.
#>
$script:VigieFloorPieces = @('paths', 'var', 'log', 'store', 'format', 'native', 'property', 'lock')

<#
    IT HANDS BACK THE LIST, IT DOES NOT LOAD IT ITSELF.

    A dot-source inside a function lands in THAT function's scope and is gone when it returns: the first version
    of this loader pulled in nine pieces and the caller saw not one of them. The caller therefore does the
    loading, which is the only place where it means anything.
#>
function Get-VigiePieceFiles {
    param(
        [Parameter(Mandatory)][string[]]$Pieces,
        [string]$LibDir = $PSScriptRoot
    )
    $wanted = [ordered]@{}
    $queue = New-Object System.Collections.Generic.Queue[string]
    foreach ($p in @($script:VigieFloorPieces + $Pieces)) { if ($p) { $queue.Enqueue($p) } }
    while ($queue.Count) {
        $piece = $queue.Dequeue()
        if ($wanted.Contains($piece)) { continue }
        $wanted[$piece] = $true
        foreach ($used in @(Get-VigiePieceUses -Piece $piece -LibDir $LibDir)) { $queue.Enqueue($used) }
    }
    # ORDER DOES NOT MATTER FOR FUNCTIONS, which resolve when they are called -- but it does for the script
    # variables a piece sets up as it loads. The floor goes first, as the facade does.
    $order = @($script:VigieFloorPieces | Where-Object { $wanted.Contains($_) })
    $order += @($wanted.Keys | Where-Object { $script:VigieFloorPieces -notcontains $_ })
    $files = @()
    foreach ($piece in $order) {
        $file = Join-Path $LibDir ($piece + '.ps1')
        if (Test-Path -LiteralPath $file) { $files += $file }
    }
    return @($files)
}
