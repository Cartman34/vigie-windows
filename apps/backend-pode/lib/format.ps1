# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: shaping a value into the text a reader reads -- a size in bytes, a moment, a string going into a
    PowerShell command. Nothing here knows anything about Vigie: no path, no configuration, no state. It is the
    bottom of the floor, and it never calls upwards (S28).
    Usage: dot-sourced by common.ps1, never run on its own. A date or a size formatted anywhere else is a second
    way of doing the same thing (D15) -- and it is how an American date reached a tooltip on 12/10.
#>

# A size in bytes -> readable text (one decimal: "12,4 Go"). The single point where sizes are
# formatted: a card showing raw bytes teaches nothing.
function Format-ByteSize {
    param([Parameter(Mandatory)][long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} To' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} Go' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} Mo' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} Ko' -f ($Bytes / 1KB)) }
    return ("$Bytes o")
}

# Brings a date read from JSON back to a UTC [datetime], whatever its shape.
#
# ConvertFrom-Json sometimes converts ISO-8601 strings into [datetime] itself: depending on
# the path one receives a string or an object, and the Kind may be Utc, Local or Unspecified.
# Comparing without normalising gives an age wrong by several hours -- which is what made the
# state cache useless. So the conversion happens HERE, in one single place.
function ConvertTo-UtcDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    $d = if ($Value -is [datetime]) { $Value }
         else { [datetimeoffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
    switch ($d.Kind) {
        'Local'       { return $d.ToUniversalTime() }
        'Unspecified' { return [datetime]::SpecifyKind($d, [DateTimeKind]::Utc) }
        default       { return $d }
    }
}

<#
    THE DATE AS THE READER READS IT, AND IN ONE PLACE.

    A date formatted anywhere else is formatted under the culture of the account that RUNS -- the service's, which
    is not the reader's. The public IP tooltip announced "10/12/2026" for the 12th of October, seen by the owner on
    12/10; and `pkg-list-updates` had already repaired exactly that in its own corner, by hand, with the comment
    "an American date format nobody reads here". The fix lived in one FILE instead of one PLACE (D15).

    THE ZONE IS THE WHOLE DIFFICULTY, and this repository stores three shapes: UTC carrying its zone
    (`ToUniversalTime().ToString('o')`, the marks and the workers), UTC without it (`ToUniversalTime().ToString('s')`),
    and LOCAL without it (`(Get-Date).ToString('s')`, several actions). A moment with no zone is taken AS WRITTEN
    here, unless -AssumeUtc says it is UTC -- the caller knows what it stored.

    AND THE MIXTURE IS NOT A DEFECT, measured rather than assumed: I announced a second defect -- the local offset
    moving every age read from a zone-less write -- and it does not exist. ConvertTo-UtcDate, which feeds those
    computations, reads a STRING through `[datetimeoffset]::Parse`, which assumes the LOCAL zone when the string
    carries none; the reading is therefore right, and the measured gap is zero. It assumes UTC only for a
    `[datetime]` whose Kind is Unspecified. Two conventions in one function: worth knowing before 'repairing' one
    of them by the other, which is what I was about to do.

    Usage: Format-DateForDisplay $value [-AssumeUtc] [-Short] [-Spelled]. Nothing in, nothing out -- so a caller
    tests the result instead of guarding the call -- and a value that cannot be read comes back as it was, never
    swallowed.
#>
function Format-DateForDisplay {
    param(
        $Value,
        # The stored moment is UTC although it carries no zone: convert it to the reader's time.
        [switch]$AssumeUtc,
        [switch]$Short,
        [switch]$Spelled
    )
    if ($null -eq $Value) { return '' }
    $dt = $null
    if ($Value -is [datetime]) { $dt = $Value }
    else {
        $txt = "$Value".Trim()
        if (-not $txt) { return '' }
        $parsed = [datetime]::MinValue
        $ok = [datetime]::TryParse($txt, [Globalization.CultureInfo]::InvariantCulture,
                                   [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)
        if (-not $ok) { return "$Value" }
        $dt = $parsed
    }
    if ($dt.Kind -eq [DateTimeKind]::Unspecified -and $AssumeUtc) {
        $dt = [datetime]::SpecifyKind($dt, [DateTimeKind]::Utc)
    }
    if ($dt.Kind -eq [DateTimeKind]::Utc) { $dt = $dt.ToLocalTime() }
    $fmt = if ($Short) { 'dd/MM HH:mm' } elseif ($Spelled) { 'dd/MM/yyyy à HH:mm' } else { 'dd/MM/yyyy HH:mm' }
    return $dt.ToString($fmt, [Globalization.CultureInfo]::InvariantCulture)
}

# Escapes a string so it can be inserted into a PowerShell command (single quotes).
function ConvertTo-PSLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    "'" + $Value.Replace("'", "''") + "'"
}
