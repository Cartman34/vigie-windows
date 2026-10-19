# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, elevation, paths, sessions, settings
<#
    Intent: WHO MAY LAUNCH WHAT (D65): what an action requires, how it presents itself, and whether the requester is allowed. A refused action stays VISIBLE and says why -- nothing disappears from a card (D59).
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- WHERE AN ACTION RUNS: on the server, or on an account's desktop? -----------------
#
# THE PROBLEM. A server has no screen. Today it has one by accident -- fhaza's client app is
# what launches it, so inside a desktop session. The day it becomes the machine's task it
# will run in session 0: "Start-Process explorer.exe" succeeds there without ANYBODY ever
# seeing the window. The action would declare itself done, and nothing would happen on
# screen.
#
# And even today the problem already exists: if Famille asks to open a folder, it opens on
# FHAZA's desktop, because that is where the server runs.
#
# THE RULE. An action declares where it must run, at the head of its file:
#     # @execution: session    -- it runs in the REQUESTER's session
#     # @execution: serveur    -- it needs nobody (the default)
# Silence means "serveur": that is the common case, and an action that opens nothing has no
# reason to take a detour.
#
# "ADMIN" AND "SESSION" GO TOGETHER PERFECTLY WELL, contrary to what I had believed.
# Test-ActionAllowed refuses an admin action to a standard account, and to a window that does
# not say who it is, BEFORE any execution. So an admin action is only ever asked for by an
# administrator -- and an administrator's client app task runs at RunLevel Highest, hence
# elevated. It can do both.
#
# The day we want a standard account to SEE those buttons and raise an elevation request
# will be another subject: an administrator will have to be able to authorise it from the
# interface, for every instance of Vigie. Out of scope today.
function Get-ActionExecutor {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($line in (Get-Content -LiteralPath $f -TotalCount 40)) {
                if ($line -match '^\s*#\s*@execution\s*:\s*(session|serveur)') { return $Matches[1] }
            }
        }
    } catch { }
    return 'serveur'
}

# --- WHO may launch an action (D65) --------------------------------------------
# The BASE rule, chosen by the owner: Vigie allows nothing more than Windows already allows
# that account. A standard account must not obtain through Vigie what Windows refuses it --
# the application would become a means of privilege escalation.
#
# But it is a DEFAULT, not a dogma: one must be able to change one's mind about ONE precise
# action. Hence two levels:
#   1. the DECLARATION, at the head of the action's file: the rights keyword followed by admin, or by the value
#      meaning everyone; it lives beside the code it protects, and is read without running
#      the script;
#   2. the machine's POLICY, config/actions.policy.json, which can open or close an action by
#      name -- that is where the user changes their mind.
# With no declaration: `admin`. Silence opens nothing.
<#
    THE VALUE OF A RIGHT, IN ONE WORD AND IN ONE PLACE.

    The word was French until 15/10 -- the line below is the only place that still spells it -- and it is `all`
    now. Files on disk, a configuration written by hand, an installation half upgraded: any of them may still
    carry the old spelling, and none should lose its rights over it. Everything that reads a right passes through
    here, so the day the old spelling is gone, it is removed HERE and nowhere else.
#>
function ConvertTo-RightsValue {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $v = "$Value".Trim().ToLowerInvariant()
    if ($v -eq 'tous') { return 'all' }
    if (-not $v) { return 'all' }
    return $v
}

function Get-ActionRequirement {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    # 1. The machine's policy (it decides).
    try {
        $pol = Get-MachineConfigPath -File 'actions.policy.json'
        if (Test-Path -LiteralPath $pol) {
            $j = Get-Content -LiteralPath $pol -Raw -Encoding UTF8 | ConvertFrom-Json
            $v = $j.PSObject.Properties | Where-Object { $_.Name -eq $Type } | Select-Object -First 1
            if ($v -and "$($v.Value)" -match '^(admin|tous|all)$') { return (ConvertTo-RightsValue "$($v.Value)") }
        }
    } catch { }
    # 2. The action's declaration.
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($line in (Get-Content -LiteralPath $f -TotalCount 40)) {
                # The value may be followed by a comment: we stop at the word, not the line.
                # BOTH SPELLINGS, the time of the pass: `@droits:` was the keyword until 15/10, and a file that
                # still carries it must keep working -- an action nobody can read is an action that vanishes.
                if ($line -match '^\s*#\s*@(?:droits|rights)\s*:\s*(admin|tous|all)') { return (ConvertTo-RightsValue $Matches[1]) }
            }
        }
    } catch { }
    return 'admin'
}

# Can the action be launched HERE and NOW? It returns a speaking object: the front end must
# be able to SAY why a button is inert -- an action never disappears (D59).
# What the action DISPLAYS when a field names it: label, kind, severity. Declared at the head
# of the action's file (`# @label: Text | kind | severity`), beside the rights.
# With no declaration: "Resoudre", in immediate/fix -- a speaking button beats no button
# (D66), but a precise label beats a generic word.
function Get-ActionPresentation {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot)
    )
    $label = 'Résoudre'; $kind = 'immediate'; $sev = 'fix'
    try {
        $f = Join-Path $Backend ("actions/$Type.action.ps1")
        if (Test-Path -LiteralPath $f) {
            foreach ($line in (Get-Content -LiteralPath $f -TotalCount 40)) {
                if ($line -match '^\s*#\s*@(?:libelle|label)\s*:\s*(.+)$') {
                    $bouts = @("$($Matches[1])" -split '\|' | ForEach-Object { $_.Trim() })
                    # The comment following "--" is not part of the declaration.
                    if ($bouts.Count -ge 1 -and $bouts[0]) { $label = ($bouts[0] -replace '\s*--.*$', '').Trim() }
                    if ($bouts.Count -ge 2 -and $bouts[1]) { $kind  = ($bouts[1] -replace '\s*--.*$', '').Trim() }
                    if ($bouts.Count -ge 3 -and $bouts[2]) { $sev   = ($bouts[2] -replace '\s*--.*$', '').Trim() }
                    break
                }
            }
        }
    } catch { }
    [pscustomobject]@{ label = $label; kind = $kind; severity = $sev }
}

<#
    DOES THE REQUESTER HAVE THE RIGHT? -- AND NOT: IS THE SERVER ELEVATED?

    This function used to ask the wrong question. It answered "yes" as soon as
    Test-IsElevated was true -- and the server runs UNDER AN ADMINISTRATOR SERVICE ACCOUNT,
    so always. An action marked "@rights: admin" went through for anybody: a standard
    account, and even a browser opened on the address with no identification at all. Meanwhile
    the users screen displayed "a standard account obtains no extra right: Vigie refuses it
    the administrator actions". The text promised a guard that did not exist, and the comment
    beside it described that guard as settled.

    D65 decides: by default Vigie allows nothing more than Windows already allows that
    account. An action touching the machine is therefore judged on THE REQUESTER.

    THREE REFUSALS, AND THEY DO NOT SAY THE SAME THING:
      - we do not know who is asking -- a window opened with no identification;
      - we know, and that account is not an administrator;
      - the requester has the right, but the server is not elevated: it CANNOT.

    OUTSIDE A WEB CONTEXT -- a background refresh, a script launched by hand -- the requester
    is whoever runs. Without that, anything not coming from a browser would be refused its own
    actions.
#>
<#
    IS THIS ACCOUNT AN ADMINISTRATOR? One answer, kept for as long as it holds.

    That question is asked for EVERY action of EVERY card at each build of the state -- dozens
    of times. It went through Get-AccountByName, so through the account inventory, which
    questions the scheduled tasks again at every call: 2.2 seconds a time. Measured on 31/08:
    eleven calls, 25 seconds, and a /state at 28.

    Membership of the administrators group does not change within the minute. It is kept for
    five minutes, per account. It is a READING cache: it decides nothing, it merely avoids
    asking Windows the same thing forty times in a row.
#>
$script:AdminMemo = @{}
function Test-RequesterIsAdmin {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $memo = $script:AdminMemo[$Account]
    if ($memo -and ((Get-Date) - [datetime]$memo.at).TotalMinutes -lt 5) { return [bool]$memo.admin }
    $verdict = $false
    try { $verdict = Test-LocalAccountIsAdmin -Name $Account } catch { }
    $script:AdminMemo[$Account] = @{ admin = $verdict; at = (Get-Date) }
    return $verdict
}

function Test-ActionAllowed {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Backend = (Get-BackendRoot),
        [AllowNull()][AllowEmptyString()][string]$Requester
    )
    $besoin = Get-ActionRequirement -Type $Type -Backend $Backend
    if ($besoin -ne 'admin') { return [pscustomobject]@{ allowed = $true; requirement = $besoin; reason = $null } }

    if (-not $PSBoundParameters.ContainsKey('Requester')) {
        $Requester = $(if ($WebEvent) { Get-RequesterAccount } else { Get-ProcessAccount })
    }

    if (-not $Requester) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système, et Vigie ne sait pas qui la demande. Le panneau s'ouvre depuis l'icône de Vigie."
        }
    }
    $isAdmin = Test-RequesterIsAdmin -Account $Requester -Backend $Backend

    if (-not $isAdmin) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système : elle demande un compte administrateur. Windows la refuserait de la même façon."
        }
    }
    if (-not (Test-IsElevated)) {
        return [pscustomobject]@{
            allowed = $false; requirement = 'admin'
            reason  = "Cette action modifie le système, et l'app serveur ne tourne pas avec les droits nécessaires."
        }
    }
    [pscustomobject]@{ allowed = $true; requirement = 'admin'; reason = $null }
}

function Get-StateAccount {
    if ($global:VigieStateAccount) { return $global:VigieStateAccount }
    return (Get-RequesterAccount)
}

function Get-RequesterAccount {
    try {
        if ($WebEvent) {
            $sid = $null
            try { $sid = $WebEvent.Cookies['vigie_session'].Value } catch { }
            if ($sid) {
                $account = Get-SessionAccount -SessionId $sid
                if ($account) { return $account }
            }
        }
    } catch { }
    return $null
}

function Get-ActionRequester {
    try {
        if ($WebEvent) {
            $sid = $null
            try { $sid = $WebEvent.Cookies['vigie_session'].Value } catch { }
            if ($sid) {
                $account = Get-SessionAccount -SessionId $sid
                if ($account) { return $account }
            }
        }
    } catch { }
    try {
        $name = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
        $sep = $name.LastIndexOf([char]92)
        if ($sep -ge 0) { $name = $name.Substring($sep + 1) }
        return $name
    } catch { return 'inconnu' }
}
