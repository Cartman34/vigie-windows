# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: WRITING A VALUE ON SOMETHING THAT MAY BE A DICTIONARY OR AN OBJECT. A probe returns what it returns --
    a hashtable here, a PSCustomObject there -- and every reader that adds a field to it had to know which.
    Usage: dot-sourced by common.ps1, never run on its own. It calls nothing of the project.
#>

<#
    ONE GESTURE, WHERE THERE WERE TWO IMPLEMENTATIONS AND EIGHT COPIES.

    The state wrote `if ($x -is [IDictionary]) { ... } else { Add-Member ... }` at each of the six places it added
    a field to a card, and the accounts called a SEVENTH version living in `audit` -- one that handled objects
    only, so it would have thrown on a hashtable. That call is also what made the accounts depend on the audit,
    and through it on half the library: four of the eight circuits left in the graph ran through that one edge.

    An empty value REMOVES the key when asked: "busy = false" has nothing to say, and the field disappears by
    itself when the mark is gone. On an object the key is set to its empty value, which is what the panel reads
    as absent.
#>
function Set-ObjectValue {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name, $Value, [switch]$RemoveWhenEmpty)
    if (-not $Object) { return }
    try {
        if ($Object -is [System.Collections.IDictionary]) {
            if ($RemoveWhenEmpty -and -not ($Value -or $Value -is [array])) { $Object.Remove($Name) | Out-Null }
            else { $Object[$Name] = $Value }
        } else {
            Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value -Force
        }
    } catch { }
}
