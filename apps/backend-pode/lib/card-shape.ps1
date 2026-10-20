# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: contract, format, operations, probes, rights, scheduler
<#
    Intent: WHAT A CARD GAINS BEFORE IT LEAVES, and which no probe has to know about: its freshness, the pace it
    is held back to, the operation running on it, the action named by one of its lines, and whether this account
    may launch each of its actions. Plus the card of a probe that has never produced anything, because a card is
    never missing.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    A CARD IS SOMETIMES A DICTIONARY AND SOMETIMES AN OBJECT, and writing a value on it was spelled out at each
    of the six places that write one -- six copies of the same `if ($x -is [IDictionary])`, and a seventh would
    have been written the next time. A probe returns what it returns; here it is one gesture.

    An empty value REMOVES the key on a dictionary: "busy = false" has nothing to say, and the field disappears by
    itself when the mark is gone.
#>
function Set-CardValue {
    param([Parameter(Mandatory)]$Card, [Parameter(Mandatory)][string]$Key, $Value, [switch]$RemoveWhenEmpty)
    if (-not $Card) { return }
    try {
        if ($Card -is [System.Collections.IDictionary]) {
            if ($RemoveWhenEmpty -and -not ($Value -or $Value -is [array])) { $Card.Remove($Key) | Out-Null }
            else { $Card[$Key] = $Value }
        } else {
            Add-Member -InputObject $Card -NotePropertyName $Key -NotePropertyValue $Value -Force
        }
    } catch { }
}

<#
    WHAT THE SCHEDULER KNOWS ABOUT EACH CARD, READ ONCE FOR ALL OF THEM (S16).

    A value twenty-two hours old looked exactly like a value from this second: nothing, on the card or in the
    contract, told them apart. A card now carries what is needed to know -- when the probe produced what it shows,
    when the scheduler last passed, and the interval that applies -- plus its consecutive failures, without which
    it serves its last successful value in silence.

    Read per card, this would be twenty readings of the same state file for one page.
#>
function Get-CardRefreshInfo {
    param([Parameter(Mandatory)][string]$Backend, [string]$Account = '')
    $byCard = @{}
    try {
        $state = Get-RefreshState -Backend $Backend
        $modes = @(Get-ActiveModes -Backend $Backend)
        foreach ($d in @(Get-RefreshDeclarations -Backend $Backend)) {
            $entry = $state[$d.Key]
            $info = [pscustomobject]@{
                Seconds   = (Get-RefreshInterval -Declaration $d -Modes $modes)
                # THE TICKS ARE UTC, and a date built on them is born "unspecified": handed over as is, the page
                # would read it as local time and show a two-hour gap (D44).
                EndedAt   = $(if ($entry -and [long]$entry.lastEndedAt) { ([datetime]::new([long]$entry.lastEndedAt, [DateTimeKind]::Utc)).ToString('o') } else { '' })
                Fails     = $(if ($entry) { [int]$entry.fails } else { 0 })
                LastError = $(if ($entry) { "$($entry.lastError)" } else { '' })
                # STARTED BUT NEVER FINISHED is not the same breakdown as NEVER STARTED, and both looked alike: a
                # card that stops moving, with no failure counted. So the start is said too.
                StartedAt = $(if ($entry -and [long]$entry.lastStartedAt) { ([datetime]::new([long]$entry.lastStartedAt, [DateTimeKind]::Utc)).ToString('o') } else { '' })
            }
            # A per-account card has one declaration per account: the requester's is the one that concerns it.
            if ($d.Account -and "$($d.Account)" -ne "$Account") { continue }
            foreach ($card in @($d.Cards)) {
                if (-not $card) { continue }
                if (-not $byCard.ContainsKey("$card")) { $byCard["$card"] = @() }
                $byCard["$card"] += $info
            }
        }
    } catch { }
    return $byCard
}

<#
    FRESHNESS TRAVELS WITH THE CARD (S16): three moments, three different questions -- when the probe produced
    what is being read, when the scheduler last passed, and how often it is meant to.

    ONE DATE FORMAT TOWARDS THE PAGE (D44): the cache keeps "at" in whatever shape ConvertFrom-Json gave it, which
    follows the culture. We answer ISO 8601, always.

    AND WHEN THE ENTRY CARRIES NO DATE, WE ASK THE PROBE'S NEWEST STAMP rather than send nothing -- or worse, the
    year 0001, which is what an unparsable value converts to and what the accounts card was showing. A card
    holding a value has been computed; the only question is when, and the stamp of its probe answers it.
#>
function Add-CardFreshness {
    param(
        [Parameter(Mandatory)]$Card,
        [Parameter(Mandatory)][string]$Backend,
        [Parameter(Mandatory)][string]$ProbeName,
        $Entry,
        $Declaration
    )
    if (-not $Card -or -not $Card.id) { return }
    try {
        $computed = ''
        try { $u = ConvertTo-UtcDate $Entry.at; if ($u -and $u.Year -gt 1) { $computed = $u.ToString('o') } } catch { }
        if (-not $computed) {
            try {
                $u = ConvertTo-UtcDate (Get-ProbeCacheStamp -Backend $Backend -Probe $ProbeName)
                if ($u -and $u.Year -gt 1) { $computed = $u.ToString('o') }
            } catch { }
        }
        $fresh = @{ computedAt = $computed }
        if ($Declaration) {
            $fresh.seconds = [int]$Declaration.Seconds
            if ($Declaration.EndedAt) { $fresh.refreshedAt = "$($Declaration.EndedAt)" }
            if ($Declaration.StartedAt) { $fresh.startedAt = "$($Declaration.StartedAt)" }
            if ([int]$Declaration.Fails -gt 0) { $fresh.fails = [int]$Declaration.Fails; $fresh.lastError = "$($Declaration.LastError)" }
        }
        Set-CardValue -Card $Card -Key 'freshness' -Value $fresh
    } catch { }
}

<#
    "AN OPERATION IS RUNNING" IS READ NOW, NOT AT THE TIME OF THE COMPUTATION.

    A probe lays that state while it runs -- and its rendering is then served from the cache. An operation started
    AFTER that computation therefore did not show: the Deployment card stayed normal, its buttons active, while
    the update was running (seen on 31/08, the notification announcing "running for 26 s" while the card showed
    nothing).

    It is not a measurement, it is a present fact: it is read again at every response and laid over the rendering,
    whatever its age.
#>
function Add-CardBusy {
    param([Parameter(Mandatory)]$Card, [Parameter(Mandatory)][string]$Backend)
    if (-not $Card -or -not $Card.id) { return }
    $mark = Get-ModuleBusyMark -Module "$($Card.id)" -Backend $Backend
    Set-CardValue -Card $Card -Key 'busy' -Value ([bool]$mark) -RemoveWhenEmpty
    Set-CardValue -Card $Card -Key 'busyAction' -RemoveWhenEmpty `
                  -Value $(if ($mark) { $(if ("$($mark.button)") { "$($mark.button)" } else { "$($mark.action)" }) } else { $null })
    Set-CardValue -Card $Card -Key 'busyResources' -RemoveWhenEmpty `
                  -Value $(if ($mark -and $mark.resources) { @($mark.resources) } else { @() })
}

# INVARIANT (D66): an action NAMED by a field (fixAction) must appear among the card's actions, or the interface
# has neither label nor kind to draw and the fixing button does not appear. It is completed here rather than
# obliging every probe to redeclare the action in its own bar.
function Add-CardFixActions {
    param([Parameter(Mandatory)]$Card, [Parameter(Mandatory)][string]$Backend)
    $known = @(@($Card.actions) | Where-Object { $_ -and $_.id } | ForEach-Object { "$($_.id)" })
    foreach ($field in @($Card.fields)) {
        $fa = "$($field.fixAction)"
        if (-not $fa -or $known -contains $fa) { continue }
        $pres = Get-ActionPresentation -Type $fa -Backend $Backend
        $act = New-Action -Id $fa -Label $pres.label -Kind $pres.kind -Severity $pres.severity `
                          -Help "Résolution proposée par la ligne « $($field.label) »."
        try { $Card.actions = @(@($Card.actions) + $act) } catch { }
        $known += $fa
    }
}

# Rights: every action says whether THIS account can launch it, and if not why (D65). Done once here rather than
# in each probe. Returns what the check cost, which is the figure that once took a day to find.
function Add-CardRights {
    param([Parameter(Mandatory)]$Card, [Parameter(Mandatory)][string]$Backend)
    $t = [Diagnostics.Stopwatch]::StartNew()
    foreach ($act in @($Card.actions)) {
        if (-not $act -or -not $act.id) { continue }
        $right = Test-ActionAllowed -Type "$($act.id)" -Backend $Backend
        Set-CardValue -Card $act -Key 'allowed' -Value $right.allowed
        if (-not $right.allowed) { Set-CardValue -Card $act -Key 'deniedReason' -Value $right.reason }
    }
    $t.Stop()
    return $t.Elapsed.TotalMilliseconds
}

<#
    A PROBE ALWAYS HAS ITS CARD. WITHOUT EXCEPTION.

    A card shows full, empty, or in error -- it is never missing. A probe that has never produced anything had no
    cache entry, and therefore no card: a hole in the page, whose contents nobody can guess.

    So a waiting card is returned, built on what is known without running anything at all: the folder's
    module.psd1 gives its title, the folder gives its group. It carries a value saying it is awaiting measurement,
    and its button, which is enough to fill it.

    SCOPE 'machine': this card says only that a measurement has not happened yet, which is true for everyone.
#>
function New-PendingCard {
    param([Parameter(Mandatory)][string]$ProbeFile)
    $unit = Split-Path (Split-Path $ProbeFile -Parent) -Leaf
    $label = $unit
    $theme = $unit
    try {
        $decl = Import-PowerShellDataFile -Path (Join-Path (Split-Path $ProbeFile -Parent) 'module.psd1')
        if ($decl.Label) { $label = "$($decl.Label)" }
        # THE GROUP IS DECLARED, and the folder serves as the default otherwise. "deployment" is not a group: its
        # card was read under "Comptes", and the header displayed "DEPLOYMENT" in English for want of knowing.
        if ($decl.Theme) { $theme = "$($decl.Theme)" }
    } catch { }
    $card = New-ModuleObject -Id $unit -Theme $theme -Label $label -Scope 'machine' -Status 'neutral' -Fields @() -Actions @()
    Set-CardValue -Card $card -Key 'pending' -Value $true
    return $card
}

<#
    THE CARD OF A PROBE THAT THREW.

    The failure card was called "accounts.probe.ps1" and landed under "Systeme": a file's name, in the wrong
    group. Nobody knows which card that corresponds to, and it is exactly the moment one needs to know.

    The probe's folder IS its module -- probes/<unit>/ -- and its module.psd1 carries the label displayed. That is
    used: the card keeps its place and its name, and says what failed.

    SCOPE 'machine': a probe that threw says so to everyone. The failure is the computer's, not an account's --
    and the card it replaces may have had either scope.
#>
function New-ProbeErrorCard {
    param([Parameter(Mandatory)][string]$ProbeFile, [Parameter(Mandatory)][string]$ProbeName, [string]$Message = '')
    $unit = Split-Path (Split-Path $ProbeFile -Parent) -Leaf
    $label = $unit
    try {
        $decl = Join-Path (Split-Path $ProbeFile -Parent) 'module.psd1'
        if (Test-Path -LiteralPath $decl) {
            $d = Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop
            if ($d.Label) { $label = "$($d.Label)" }
        }
    } catch { }
    return (New-ModuleObject -Id $ProbeName -Theme $unit -Label $label -Scope 'machine' -Status 'error' -Fields @(
        New-Field -Key 'error' -Label 'Erreur' -Value $Message -Kind 'text' -Status 'error'
        New-Field -Key 'probe' -Label 'Sonde' -Value $ProbeName -Kind 'text'
    ))
}
