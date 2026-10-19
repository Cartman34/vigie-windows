# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: WHERE THINGS ARE, and the one question "does this path exist?". The repository holds several apps
    plus scripts/ and doc/; those landmarks are computed here and nowhere else, so no script recomposes a
    cross-app path by hand. It knows no configuration, no state, and it never calls upwards (S28).
    Usage: dot-sourced by common.ps1, never run on its own. `$PSScriptRoot` here is lib/, exactly as it was in
    common.ps1 -- both files live there, which is why Get-BackendRoot still answers the same folder.
#>

<#
    "DOES THIS PATH EXIST?" MUST NEVER BRING A CALLER DOWN.

    Test-Path THROWS on a path whose rights are refused -- another account's profile,
    typically. Under "ErrorActionPreference = Stop" the question then takes the whole script
    with it. Seen twice on 29/08: an entire probe in error, and a restart of client apps cut
    short, both times because something asked whether a folder existed.

    A refusal of access IS NOT an answer to the question asked: we do not know whether the
    path exists, and "I do not know" is treated as "no" here -- there is nothing to be done
    with it either way.

    The repository's rule: a system call that repeats becomes a function of ours.
#>
function Test-PathSafe {
    param([string]$Path)
    if (-not $Path) { return $false }
    try { return [bool](Test-Path -LiteralPath $Path -ErrorAction Stop) } catch { return $false }
}

function Get-BackendRoot { Split-Path $PSScriptRoot -Parent }

# --- Landmarks of the tree ---------------------------------------------------
# The repository holds SEVERAL apps (apps/backend, apps/frontend, apps/client,
# apps/atelier) plus scripts/ and doc/. These landmarks are computed HERE and nowhere
# else: no script may recompose a cross-app path by hand.
function Get-RepoRoot { Split-Path (Split-Path (Get-BackendRoot) -Parent) -Parent }
function Get-AppsRoot { Split-Path (Get-BackendRoot) -Parent }
# App folder names carry their TECHNOLOGY: they are replaceable implementations
# (principle no. 1). They are written ONLY HERE; all the code goes through Get-AppPath.
# Only the bootstrap is an exception -- see the note further down.
function Get-AppPath {
    param([Parameter(Mandatory)][ValidateSet('backend','frontend','client','atelier')][string]$Role)
    $folder = switch ($Role) {
        'backend'  { 'backend-pode' }    # PowerShell + Pode
        'frontend' { 'frontend-web' }    # HTML/CSS/JS, sans framework ni build
        'client'   { 'client' }          # pas de suffixe : n'implemente aucun contrat
        'atelier'  { 'atelier' }         # idem
    }
    Join-Path (Get-AppsRoot) $folder
}

# A NOTE ON THE BOOTSTRAP: a script that must LOAD this library cannot call Get-AppPath
# yet. The backend folder's name is therefore spelled out there (client.ps1,
# scripts/*.ps1). It is unavoidable: one has to know where the library is before being
# able to use it. Those lines are marked with a comment of their own.

