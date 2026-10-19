# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: client-app, log, operations, paths, probes, rights
<#
    Intent: EVERY ACTION LEAVES A TRACE, TWICE: in Vigie's own journal and in the Windows event log, with who asked, who ran it and what came of it. A trace written afterwards from memory is not a trace.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# What is WRONG, in plain words, ready to be displayed. $null when all is well.
# TWO NATURES OF FAULT, and only one of them repairs.
#
#   STRUCTURE: the interpreter, the path, whether it is enabled. That is corrected at once.
#   HISTORY  : the task never ran, or its last launch failed. No rewriting erases that --
#              only its next run will say.
#
# Confusing the two led to rewriting a perfectly healthy task, then announcing the same
# fault again: "rewritten, but: <exactly what we had just read>" (seen on 28/08).
# WRITING A PROPERTY THAT MAY NOT EXIST YET.
#
# An object returned by ConvertFrom-Json has a FIXED shape: its properties are the JSON's,
# and assigning another one THROWS. When that JSON is a cache written by an earlier version
# of the product, any code adding a field breaks silently -- and the stale value stays on
# screen. That is what announced "1 tache hors service" for a healthy task (28/08): the
# previous day's cache had the last word.
#
# To be used whenever writing into an object that MAY come from a cache or from an API.
function Set-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if (-not $Object) { return }
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $null -Force
    }
    $Object.$Name = $Value
}

# --- Actions ---------------------------------------------------------------
function New-JobId { [guid]::NewGuid().ToString('N').Substring(0, 12) }

# --- TRACEABILITY: every action leaves a trace, twice ------------------------
#
# "One must always be able to find and justify an action of Vigie." A trace that a deleted file makes disappear is
# not a trace: every action therefore writes ALSO into the Windows event log, where an administrator already looks
# when investigating, and from which Vigie cannot erase it.
#
# What is traced: SUCCESSFUL actions, REFUSED actions, and those that FAIL. A refusal counts as much as a success
# -- it is even the one read back after an incident.

$script:VigieEventSource = 'Vigie'
$script:VigieEventLog    = 'Application'

# Event identifiers, stable: they are what one filters on in the Event Viewer.
$script:VigieEventIds = @{ done = 1000; denied = 1001; failed = 1002 }

# The source must exist BEFORE writing, and creating it requires elevation. It is laid at installation time; here
# we merely create it if we can, and never make an action fail for a problem with the log.

function Register-VigieEventSource {
    param([switch]$Quiet)
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($script:VigieEventSource)) { return $true }
    } catch {
        # Without elevation even READING is refused: we do not know, so we assert nothing.
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-etat') -ForegroundColor DarkGray }
        return $false
    }
    try {
        [System.Diagnostics.EventLog]::CreateEventSource($script:VigieEventSource, $script:VigieEventLog)
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-source' $script:VigieEventSource) -ForegroundColor Green }
        return $true
    } catch {
        if (-not $Quiet) { Write-Host (Get-Label 'common.journal-des-evenements-source-2' $_.Exception.Message) -ForegroundColor Yellow }
        return $false
    }
}

function Write-VigieAudit {
    param(
        [Parameter(Mandatory)][ValidateSet('done', 'denied', 'failed')][string]$Outcome,
        [Parameter(Mandatory)][string]$Action,
        [string]$Module,
        [string]$Requester = (Get-ActionRequester),
        [string]$Rights = 'all',
        [string]$Detail,
        [int]$Milliseconds = 0,
        [string]$Backend = (Get-BackendRoot)
    )
    $outcomeLabel = switch ($Outcome) {
        'done'   { 'REUSSIE' }
        'denied' { 'REFUSEE' }
        'failed' { 'ECHEC' }
    }
    $entry = ("{0} | action={1} | module={2} | demandeur={3} | droits={4}" -f
              $outcomeLabel, $Action, $(if ($Module) { $Module } else { '-' }), $Requester, $Rights)
    if ($Milliseconds -gt 0) { $entry += (" | duree={0} ms" -f $Milliseconds) }
    if ($Detail) { $entry += (" | " + $Detail) }

    # 1. Vigie's own log: the detail, read back during troubleshooting.
    try {
        $level = if ($Outcome -eq 'failed') { 'ERROR' } elseif ($Outcome -eq 'denied') { 'WARN' } else { 'INFO' }
        Write-Log -Backend $Backend -Name 'audit' -Level $level -Message $entry
    } catch { }

    # 2. The Windows event log: the trace one can hold up.
    #
    # IT MUST NEVER MAKE THE ACTION FAIL. A log that is unavailable is a problem with the log, not a problem with
    # the action -- but it shows up in Vigie's own, otherwise one would believe the trace written when it is not.

    try {
        if ([System.Diagnostics.EventLog]::SourceExists($script:VigieEventSource)) {
            $type = switch ($Outcome) {
                'done'   { [System.Diagnostics.EventLogEntryType]::Information }
                'denied' { [System.Diagnostics.EventLogEntryType]::Warning }
                'failed' { [System.Diagnostics.EventLogEntryType]::Error }
            }
            [System.Diagnostics.EventLog]::WriteEntry(
                $script:VigieEventSource, $entry, $type, $script:VigieEventIds[$Outcome])
        }
    } catch {
        try { Write-Log -Backend $Backend -Name 'audit' -Level 'WARN' `
                        -Message (Get-Label 'common.journal-des-evenements-windows' $_.Exception.Message) } catch { }
    }
}

function Invoke-ActionById {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Module,
        [hashtable]$Params,
        [string]$Backend = (Get-BackendRoot)
    )
    # Security: accept nothing but a simple identifier (no path traversal)
    if ($Type -notmatch '^[a-z][a-z0-9-]{1,40}$') {
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = "Type d'action invalide." }
    }
    # THE REAL GUARD: a greyed-out button is only a display; the refusal counts HERE, a request being able to
    # arrive without going through the interface.
    # TRACED END TO END. This point is the only one an action goes through: it is therefore here, and nowhere else,
    # that we write who asked for what and what came out of it. A REFUSAL is traced as much as a success -- it is
    # even the one read back after an incident.
    $requester = Get-ActionRequester
    $rights    = try { (Get-ActionRequirement -Type $Type -Backend $Backend) } catch { 'all' }
    $timer    = [System.Diagnostics.Stopwatch]::StartNew()

    $droit = Test-ActionAllowed -Type $Type -Backend $Backend
    if (-not $droit.allowed) {
        Write-VigieAudit -Outcome 'denied' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("raison=" + $droit.reason) -Backend $Backend
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $droit.reason }
    }
    $file = Join-Path $Backend ("actions/$Type.action.ps1")
    $full = try { (Resolve-Path -LiteralPath $file -ErrorAction Stop).Path } catch { $null }
    $actionsDir = (Resolve-Path -LiteralPath (Join-Path $Backend 'actions')).Path
    if (-not $full -or -not $full.StartsWith($actionsDir)) {
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = "Action inconnue : $Type" }
    }
    # THE LOCK IS HERE, not in the interface (D93). A page left open can always send an action: it is the server
    # that must say no.
    # THE MODULE COUNTS: "paquets" becomes "paquets-choco" according to the card, so two different managers no
    # longer block one another (D130).
    $conflit = Test-ActionResourcesFree -Type $Type -Module $Module -Backend $Backend
    if ($conflit) {
        Write-VigieAudit -Outcome 'denied' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("ressource occupee : " + $conflit) -Backend $Backend
        return [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $conflit }
    }
    try {
        # IN WHICH SESSION? An action declared as "session" must run at the REQUESTER's, not where the server runs.
        # We have their client app run it; if it does not answer, we run it here as before rather than doing
        # nothing.
        $res = $null
        if ((Get-ActionExecutor -Type $Type -Backend $Backend) -eq 'session' -and $requester -and $requester -ne '-') {
            $relais = Invoke-ClientTask -Account $requester -Type $Type -Params $Params -Module $Module -Backend $Backend
            if ($relais) {
                $res = @{ message = "$($relais.message)"; result = $relais.result }
            } else {
                try { Write-Log -Backend $Backend -Name 'actions' -Level 'WARN' `
                                -Message ("Action " + $Type + " : l'app cliente de " + $requester + " n'a pas repondu, execution locale.") } catch { }
            }
        }
        if (-not $res) { $res = & $file -Module $Module -Params $Params }
        # Targeted cache invalidation: the probes named will be recomputed at the next /state
        try {
            $inv = if ($res -and $res.result -and $res.result.invalidate) { @($res.result.invalidate) } else { @() }
            if ($inv.Count) { Remove-ProbeCache -Names $inv -Backend $Backend }
            <#
                AND IT DOES NOT LEAVE HERE.

                "invalidate" is an INTERNAL INSTRUCTION: which probes to recompute. It was consumed here then
                returned as it stood to the browser, which does nothing with it -- names of PowerShell files in a
                JSON response, before the eyes of whoever opens the network tab (noted on 01/09). What the client
                must know are CARDS, not our files.
            #>

            if ($res -and $res.result -and $res.result.PSObject.Properties['invalidate']) {
                try {
                    if ($res.result -is [System.Collections.IDictionary]) { $res.result.Remove('invalidate') }
                    else { $res.result.PSObject.Properties.Remove('invalidate') }
                } catch { }
            }
        } catch { }
        # An action can return "ok = false" without throwing: that is a failure, and it is traced as such. Relying
        # on try/catch alone would let the polite failures through.
        $succeeded = -not ($res -and $res.result -and $res.result.PSObject.Properties['ok'] -and $res.result.ok -eq $false)
        Write-VigieAudit -Outcome $(if ($succeeded) { 'done' } else { 'failed' }) -Action $Type -Module $Module `
                         -Requester $requester -Rights $rights -Detail ("" + $res.message) `
                         -Milliseconds ([int]$timer.ElapsedMilliseconds) -Backend $Backend
        [pscustomobject]@{ jobId = (New-JobId); status = 'done'; message = $res.message; result = $res.result }
    } catch {
        Write-VigieAudit -Outcome 'failed' -Action $Type -Module $Module -Requester $requester `
                         -Rights $rights -Detail ("exception : " + $_.Exception.Message) `
                         -Milliseconds ([int]$timer.ElapsedMilliseconds) -Backend $Backend
        [pscustomobject]@{ jobId = (New-JobId); status = 'error'; message = $_.Exception.Message }
    }
}
