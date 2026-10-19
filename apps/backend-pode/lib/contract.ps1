# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses:
<#
    Intent: THE SHAPE OF WHAT THE PANEL RECEIVES -- a field, an action, a card -- built in one place so that no
    probe invents a key. The contract itself is declared in api/openapi.yaml; these factories are what makes a
    probe unable to depart from it by accident.
    Usage: dot-sourced by common.ps1, never run on its own. NOT part of the floor, measured rather than assumed:
    New-Action and New-ModuleObject ask Get-ActionResources what an action holds, which is knowledge of the
    actions, not of a shape (S28).
#>

function New-Field {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][ValidateSet('bool','number','text','date')][string]$Kind,
        [string]$Unit,
        [ValidateSet('ok','warn','error','neutral')][string]$Status,
        [string]$Help,
        [string]$FixAction,
        [string]$Guide,
        # A STRUCTURED detail: @{ columns = @('...'); rows = @(@('...'), ...) }.
        # A list of several dozen lines formatted into a string stays unreadable wherever it
        # is displayed. A table is taken in at a glance; text is not.
        [hashtable]$Table,
        # A foldable TREE (S13b/D60): @{ n; path; size; pct; k = @(...) }. A table flattens
        # what is hierarchical; a tree is walked branch by branch, which is exactly the
        # question being asked ("where is the room going?").
        $Tree,
        # THE PROGRESS OF AN OPERATION IN PROGRESS, in a block of its own under the field, only while it runs:
        # @{ phase; percent; index; total; title; itemPercent; bytesDone; bytesTotal; since } (contract Field.progress).
        [hashtable]$Progress,
        # THE REASON OF AN ALERT, one short line, carried as is into the desktop notification (CORE-ERRORS).
        [string]$Reason,
        <#
            -Scope: WHOSE INFORMATION THIS FIELD CARRIES, when it is not its card's (D128).

            'machine' or 'user'. A 'mixed' card requires one on EVERY field; on a 'machine' or
            'user' card it is written only for the exception.
        #>
        [ValidateSet('machine','user')][string]$Scope,
        # THE IDENTITY OF THE FACT STATED, when the displayed value is a rendering of it and not the fact itself.
        # Never displayed. It exists for whoever WATCHES the field: a watcher that compares values alone cannot tell
        # "the same fact, worded differently" from "a new fact". Measured on 05/10: the last session's line reads
        # the last session's line names its end time one way on the day and another way afterwards, so at the first
        # computation past midnight the client app took a twelve-hour-old session for a session that had just ended,
        # and opened its recap at 06:45. Every field whose value carries a date, a duration or any wording that
        # drifts with time owes an identity.
        [string]$Identity
    )
    $f = [ordered]@{ key = $Key; label = $Label; value = $Value; kind = $Kind }
    if ($Reason) { $f['reason'] = $Reason }
    if ($Identity) { $f['identity'] = $Identity }
    if ($Scope) { $f['scope'] = $Scope }
    if ($Unit)      { $f['unit']      = $Unit }
    if ($Status)    { $f['status']    = $Status }
    if ($Help)      { $f['help']      = $Help }
    if ($FixAction) { $f['fixAction'] = $FixAction }
    if ($Guide)     { $f['guide']     = $Guide }
    if ($Table -and $Table.rows -and @($Table.rows).Count) { $f['table'] = $Table }
    if ($Tree) { $f['tree'] = $Tree }
    if ($Progress -and $Progress.phase) { $f['progress'] = $Progress }
    [pscustomobject]$f
}
function New-Action {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        # THE CARD THAT CARRIES THIS ACTION, when the resource it takes depends on it: "pkg-choco" turns "paquets"
        # into "paquets-choco", so checking pip during an upgrade of Chocolatey stays possible. Optional: an action
        # whose resource does not depend on its card has nothing to say here.
        [string]$Module,
        [switch]$Confirm,
        [string]$Help,
        # 'dialog': opens a CHOICE window inside the application (a list to tick).
        # Distinct from 'manual', which opens EXTERNAL SOFTWARE, and from 'confirm', which
        # only asks a yes or no. The three did not look different enough on screen.
        [ValidateSet('immediate','confirm','manual','dialog')][string]$Kind,
        # SEVERITY: what the action represents, independently of the FORM it takes.
        # `kind` chooses the ICON -- how it happens: yes/no, a choice window, external
        # software; `severity` chooses the COLOUR, what it is worth:
        #   neutral = nothing at stake (grey) | info = consulting, opening (blue)
        #   fix     = it corrects something (green)
        # The two were conflated: the colour followed the form, which teaches nothing.
        [ValidateSet('neutral','info','fix')][string]$Severity,
        # The label displayed WHILE it runs. It must say what is happening -- "Mise à jour…",
        # not "En cours…". The ellipsis is RESERVED for an action under way: a label at rest
        # never carries one.
        [string]$BusyLabel,
        # TWO distinct confirmations before running. Reserved for gestures that close the
        # user's work in progress or touch the whole machine: one click too many must not be
        # enough.
        [switch]$ConfirmTwice,
        # --- WHAT A CONFIRMATION MUST SAY (D91) ---------------------------------
        # "This action modifies your system" informs nobody. Before saying yes, one wants
        # to know WHAT CHANGES on the machine, WHY one would do it, and WHETHER one can go
        # back. Surface technical details are welcome: a service name, a registry key, a
        # restart required.
        #
        #   -Impact     : what concretely changes, here and now.
        #   -Usage      : in which case one uses it (the intention).
        #   -Reversible : how to go back -- or why one cannot.
        [string]$Impact,
        [string]$Usage,
        [string]$Reversible,

        <#
            -From / -To: THE ACTION MOVES FROM ONE STATE TO ANOTHER, and it is SHOWN.

            "From v0.1.25 to v0.1.25+1" stuck at the end of a sentence reads badly and gets
            lost. Two values and an arrow are taken in at a glance -- and that is what one
            wants to know before clicking.

            -FromNote / -ToNote carry the detail under each value: a commit, a date. Both
            optional: in production the version number says enough.
        #>
        [string]$From,
        [string]$To,
        [string]$FromNote,
        [string]$ToNote,

        <#
            -Steps: WHAT IS GOING TO HAPPEN, IN ORDER.

            An asynchronous action chains several phases -- deploy, restart, check. Listing
            them in a sentence drowns them; showing them aligned says at a glance how many
            there are, and which one finishes the job.

            The last is the STATE ARRIVED AT, not a phase: it stands apart.
        #>
        [string[]]$Steps = @()
    )
    $a = [ordered]@{ id = $Id; label = $Label }
    if ($Confirm -or $ConfirmTwice) { $a['confirm'] = $true }
    if ($ConfirmTwice) { $a['confirmTwice'] = $true }
    if ($Help)    { $a['help']    = $Help }
    if ($Impact)     { $a['impact']     = $Impact }
    if ($Usage)      { $a['usage']      = $Usage }
    if ($Steps -and $Steps.Count) { $a['steps'] = @($Steps) }
    if ($From -or $To) {
        $a['transition'] = @{ from = "$From"; to = "$To"; fromNote = "$FromNote"; toNote = "$ToNote" }
    }
    if ($Reversible) { $a['reversible'] = $Reversible }
    $a['kind'] = if ($Kind) { $Kind } elseif ($Confirm) { 'confirm' } else { 'immediate' }
    # A reasonable default: opening something informs, the rest is neutral. A corrective
    # action must declare itself -- one does not guess that it repairs.
    # Default: 'info'. A button IS an action: it does something, and its icon deserves a
    # colour. Grey used to be the default, so every ordinary action looked inert; it is now
    # DECLARED, for the rare case where nothing is at stake.
    # 'fix' is declared too: one does not guess that an action repairs.
    $a['severity'] = if ($Severity) { $Severity } else { 'info' }
    # Default: the label followed by an ellipsis. Grammatically right in most cases; one
    # spells it out when the noun form reads better.
    $a['busyLabel'] = if ($BusyLabel) { $BusyLabel } else { "$Label…" }
    # WHAT THE ACTION TAKES UP (D93). The interface uses it to grey out just what it must;
    # the server is the one that really arbitrates.
    $res = @(Get-ActionResources -Type $Id -Module $Module)
    if ($res.Count) { $a['resources'] = @($res) }
    [pscustomobject]$a
}
function New-ModuleObject {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Theme,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][ValidateSet('ok','warn','error','neutral')][string]$Status,
        <#
            -Scope: WHOSE INFORMATION THIS CARD CARRIES, and it is mandatory (D128).

              'machine' -- facts about the computer, true with nobody signed in.
              'user'    -- facts about the account looking, which are read IN ITS OWN SESSION.
              'mixed'   -- both on one card; every field then declares its own.

            WHAT IT IS FOR. Information carried by a user account is fetched from that account,
            never from the service account: the server app has no winget, no WSL, no Game Bar
            and nobody's settings. Measured on 05/10: the winget card was missing from the
            panel entirely, and its first fix then showed one account's winget to another
            account's session. A per-account measurement borrowed from another account is
            wrong even when it is exact.

            WHY DECLARE IT RATHER THAN KNOW IT. Because forgetting does not show: the card
            appears, the value reads plausibly, and it belongs to someone else. Declared, the
            gap becomes mechanical -- `check-scope.ps1` refuses a card without a scope, and a
            'mixed' card one of whose fields does not declare one.
        #>
        [Parameter(Mandatory)][ValidateSet('machine','user','mixed')][string]$Scope,
        [object[]]$Fields = @(),
        [object[]]$Actions = @(),
        <#
            -Mode: A LASTING STATE OF THE CARD, which the interface shows.

            Neither an alert nor an occupancy: a CONTEXT. The Gaming card enters 'game' mode
            for as long as a game lasts, and the interface shows it -- one must see at a
            glance that a game is on, without reading a field.
        #>
        [string]$Mode,

        [switch]$Busy,
        # The identifier of the action REALLY under way. Without it the interface animates
        # every button on the card: one no longer knows which is working.
        [string]$BusyAction,
        # What the running operation takes up: without it, the interface can only block
        # everything or nothing.
        [string[]]$BusyResources = @()
    )
    # INVARIANT: a card is never MORE SERIOUS than the worst of its fields. A card reading
    # "Problème" in red with no red line in it is a contradiction the user sees at once, and
    # there is nowhere for them to go to resolve it.
    # The bound is set HERE, once, for every probe, so none can forget it any more.
    # "neutral" fields bound NOTHING: they carry no judgement, and a green card made of
    # neutral lines is perfectly legitimate.
    $rank = @{ neutral = 0; ok = 1; warn = 2; error = 3 }
    $cap = 0
    foreach ($f in @($Fields)) {
        $s = "$($f.status)"
        if ($s -and $rank.ContainsKey($s) -and $rank[$s] -gt $cap) { $cap = $rank[$s] }
    }
    $effective = $Status
    if ($cap -gt 0 -and $rank["$Status"] -gt $cap) {
        $effective = ($rank.GetEnumerator() | Where-Object { $_.Value -eq $cap }).Name
    }
    $o = [ordered]@{
        id = $Id; theme = $Theme; label = $Label; status = $effective; scope = $Scope
        fields = @($Fields); actions = @($Actions)
    }
    if ($Busy) { $o['busy'] = $true }
    if ($Busy -and $BusyAction) { $o['busyAction'] = $BusyAction }
    if ($Mode) { $o['mode'] = $Mode }
    if ($Busy) {
        $br = if ($BusyResources.Count) { @($BusyResources) } elseif ($BusyAction) { @(Get-ActionResources -Type $BusyAction -Module $Id) } else { @() }
        if ($br.Count) { $o['busyResources'] = @($br) }
    }
    [pscustomobject]$o
}
