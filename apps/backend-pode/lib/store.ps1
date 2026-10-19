# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: WRITING A JSON FILE WITHOUT LOSING WHAT SOMEONE ELSE WROTE -- an atomic read-merge-write, serialised
    by a named mutex derived from the file itself, because several writers exist at once: actions, detached
    workers, the scheduler. One single piece of code writes the files of var/cache.
    Usage: dot-sourced by common.ps1, never run on its own. It takes the path it is given and calls nothing of
    the project (S28).
#>


# Merges keys into a JSON state file (an ATOMIC read-merge-write), serialised by a named
# mutex derived from the file, so several writers -- actions, detached workers -- do not
# overwrite one another. The rule: one single piece of code writes the files of var/cache
# (netmeasure.json, pkgupdates.json, ...).
function Update-StateJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Set,
        # Serialisation depth. 8 is enough for flat states; a TREE -- the disk analysis --
        # goes past it, and ConvertTo-Json then truncates IN SILENCE.
        [int]$Depth = 8
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $leaf = (Split-Path $Path -Leaf) -replace '[^A-Za-z0-9]', '_'
    $mx = $null; $held = $false
    try {
        $mx = New-Object System.Threading.Mutex($false, "Local\VigieState_$leaf")
        try { $held = $mx.WaitOne(5000) }
        catch [System.Threading.AbandonedMutexException] { $held = $true }
        catch { $held = $false }
        $data = @{}
        if (Test-Path $Path) {
            try { $j = Get-Content $Path -Raw | ConvertFrom-Json; foreach ($pp in $j.PSObject.Properties) { $data[$pp.Name] = $pp.Value } } catch { }
        }
        foreach ($k in $Set.Keys) { $data[$k] = $Set[$k] }
        $tmp = "$Path.tmp"
        ($data | ConvertTo-Json -Depth $Depth) | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $Path -Force
        return $data
    } finally {
        if ($held -and $mx) { try { $mx.ReleaseMutex() } catch { } }
        if ($mx) { try { $mx.Dispose() } catch { } }
    }
}
