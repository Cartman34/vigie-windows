# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    ASK-VIGIE: ASK THE SERVER APP THE QUESTION, RATHER THAN DIGGING THROUGH WINDOWS.

    Intent: get the facts AS VIGIE SEES THEM, from a development session, without inventing a second road to
    them.
    Usage: see the examples below. Exit codes: 0 = an answer was obtained; 2 = no answer (a silent server, a
    refused secret). The message says which.

    THE PROBLEM. From an ordinary session, half of what one wants to know is UNREADABLE: querying another
    account's scheduled task answers "access denied", process owners come back empty, LastUseTime returns
    nothing. I reported that refusal four times as if it were information -- when it says nothing about the
    workstation, only about MY rights. Worse: it made me announce that a task did not exist when it was there.

    THE SOLUTION. The server app is elevated, it sees everything, and it already has a front door meant for this:
    the account's secret -> a ticket -> a session cookie. That is exactly the road the client app follows. We
    borrow it, and we obtain the facts as Vigie sees them -- with the rights of the account that asks, which is
    also the right context for judging.

    No circumvention, no elevation: this script can see nothing that the same account's client app could not see.

    EXAMPLES

        pwsh -File scripts/dev/ask-vigie.ps1 -Type accounts-details -Module accounts
        pwsh -File scripts/dev/ask-vigie.ps1 -Type accounts-details -Module accounts -Raw
        pwsh -File scripts/dev/ask-vigie.ps1 -Modules            # the state of every card
        pwsh -File scripts/dev/ask-vigie.ps1 -Modules -Fresh     # ... recomputed, without the cache
        pwsh -File scripts/dev/ask-vigie.ps1 -Modules -Module vigie-debug -Fresh   # one single card
        pwsh -File scripts/dev/ask-vigie.ps1 -Route 'history/net.latency?window=24h'
#>


[CmdletBinding()]
param(
    [string] $Type,
    [string] $Module,
    [hashtable] $Params = @{},
    # -Modules: the state of the cards, without going through an action.
    [switch] $Modules,
    # -Route: ANY read route, written the way the contract writes it (for instance
    # "/history/net.latency?window=24h"). Without it, checking a route meant rebuilding a
    # ticket and a cookie by hand -- the very thing this script exists to avoid.
    [string] $Route,
    # -Fresh: RECOMPUTE instead of reading the cache. After an update the cards are still
    # the ones from before -- I read "v0.1.63" twice on a server already running v0.1.64 and
    # believed the deployment had changed nothing. WITH -Module, only that card is
    # recomputed: asking for all of them exceeds the server's own delay and returns 408.
    [switch] $Fresh,
    # -Raw: the raw JSON, to pipe into jq. Otherwise, a readable rendering.
    [switch] $Raw,
    [int] $Port = 0,

    # -Out: write the answer into a file, in UTF-8. Redirecting the terminal's output re-encodes it in the
    # console's code page -- the accents arrive broken and the JSON is no longer readable by a tool. So we write it
    # ourselves.
    [string] $Out
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

if (-not $Port) { $Port = [int](Get-Config -Backend $backend).Port }
$url = 'http://127.0.0.1:' + $Port

# --- 1. Does the server answer? -----------------------------------------------
if (-not (Get-PortListener -Port $Port)) {
    Write-Fail (Get-Label 'ask-vigie.personne-n-ecoute' $Port)
    exit 2
}

# --- 2. The account's secret, then the ticket ---------------------------------
# The secret lives in OUR profile, with an explicit ACL: we are the only one able to read it, and that is
# precisely what makes it prove our identity.
$account = Get-ProcessAccount
$secret = $null
try {
    $secret = Get-AccountSecret -VarRoot (Get-AccountVarRoot -Account $account) `
                                -OwnerSid (Get-AccountSid -Account $account) -Create
} catch {
    Write-Fail (Get-Label 'ask-vigie.secret-illisible' $_.Exception.Message)
    exit 2
}

<#
    WE READ THE COOKIE OURSELVES.

    Invoke-WebRequest fails on the opening address with "Unable to read data from the transport connection", while
    the SAME page without a ticket is served in 0.1 s and curl succeeds every time. What sets that route apart:
    it LAYS A COOKIE. It is .NET's parsing of it that breaks the reading of the response, not the server.

    So we switch the cookie store off (UseCookies = $false), read the Set-Cookie header by hand, and build the
    session with it. Two attempts are then enough -- the first one passes.


#>
$session = $null
$lastError = $null
foreach ($attempt in 1..3) {
    $reply = $null
    try {
        $body = @{ account = $account; secret = $secret } | ConvertTo-Json -Compress
        $reply = Invoke-RestMethod -Method Post -Uri ($url + '/api/v1/session/ticket') `
                                   -ContentType 'application/json' -Body $body `
                                   -Headers @{ Origin = $url } -TimeoutSec 10
    } catch {
        $lastError = $_.Exception.Message
        Start-Sleep -Milliseconds (400 * $attempt)
        continue
    }
    if (-not ($reply -and $reply.ok -and $reply.ticket)) {
        # The secret does not match: trying again will change nothing.
        Write-Fail (Get-Label 'ask-vigie.ticket-refuse')
        exit 2
    }

    $handler = $null; $client = $null
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseCookies = $false
        <#
            WE DO NOT FOLLOW THE REDIRECTION.

            Since the opening address redirects to the main one, the cookie arrives on the 302 response -- and if
            one follows, it is the NEXT response one reads: with no cookie sent (UseCookies = false), the server
            then answers with the "no account" page, in 403, and the cookie of the first response is lost.
            Observed on 31/08: the server app was said not to have laid a cookie (HTTP code 403) when it had laid
            one.
        #>
        $handler.AllowAutoRedirect = $false
        $client  = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(60)
        # The method is written with its TYPE: passing the bare string lets PowerShell pick an overload at random,
        # and the call fails one time in two.
        $req = New-Object System.Net.Http.HttpRequestMessage(
                    [System.Net.Http.HttpMethod]::Get, ($url + '/?t=' + $reply.ticket))
        $req.Headers.Add('Origin', $url)
        $req.Headers.ConnectionClose = $true
        # WE STOP AT THE HEADERS. The cookie is in the header; the body is 220 KB we have no use for, and it is
        # precisely its copying that breaks ("Error while copying content to a stream"). Not reading what one does
        # not want is safer than trying to read it again.
        $rep = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $brut = $null
        if ($rep.Headers.Contains('Set-Cookie')) { $brut = @($rep.Headers.GetValues('Set-Cookie')) }
        $value = $null
        foreach ($c in @($brut)) {
            if ("$c" -match 'vigie_session=([^;]+)') { $value = $Matches[1] }
        }
        if (-not $value) { throw (Get-Label 'ask-vigie.pas-de-cookie' ([int]$rep.StatusCode)) }
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $session.Cookies.Add((New-Object System.Net.Cookie('vigie_session', $value, '/', '127.0.0.1')))
        break
    } catch {
        $lastError = $_.Exception.Message
        $session = $null
        Start-Sleep -Milliseconds (400 * $attempt)
    } finally {
        if ($client)  { try { $client.Dispose() }  catch { } }
        if ($handler) { try { $handler.Dispose() } catch { } }
    }
}
if (-not $session) {
    Write-Fail (Get-Label 'ask-vigie.session-refusee' "$lastError")
    exit 2
}

# --- 3. The question ----------------------------------------------------------
try {
    if ($Route) {
        $target = $url + '/api/v1/' + $Route.TrimStart([char]47)
        $data = Invoke-RestMethod -Method Get -Uri $target `
                                  -WebSession $session -Headers @{ Origin = $url } -TimeoutSec 120
    } elseif ($Modules) {
        # "/state": the whole state, cards included. "/modules/:id" returns ONE card, and
        # "/modules" does not exist -- which is what I had written, hence a 404.
        $stateUrl = if ($Module) { $url + '/api/v1/modules/' + $Module } else { $url + '/api/v1/state' }
        if ($Fresh) { $stateUrl += '?fresh=1' }
        $data = Invoke-RestMethod -Method Get -Uri $stateUrl `
                                  -WebSession $session -Headers @{ Origin = $url } -TimeoutSec 300
    } else {
        if (-not $Type) { Write-Fail (Get-Label 'ask-vigie.quelle-question'); exit 2 }
        $payload = @{ type = $Type }
        if ($Module) { $payload.module = $Module }
        if ($Params -and $Params.Count) { $payload.params = $Params }
        $data = Invoke-RestMethod -Method Post -Uri ($url + '/api/v1/actions') `
                                  -ContentType 'application/json' `
                                  -Body ($payload | ConvertTo-Json -Depth 8 -Compress) `
                                  -WebSession $session -Headers @{ Origin = $url } -TimeoutSec 300
    }
} catch {
    # WHAT THE SERVER ANSWERED, not only the code: a bare "400" sends you looking in the wrong
    # place -- half an hour lost on 29/09 over a disk analysis that was simply still running.
    $detail = ''
    try {
        $stream = $_.Exception.Response.GetResponseStream()
        if ($stream) { $detail = (New-Object IO.StreamReader($stream)).ReadToEnd() }
    } catch { }
    if (-not $detail -and $_.ErrorDetails) { $detail = "$($_.ErrorDetails.Message)" }
    Write-Fail (Get-Label 'ask-vigie.question-refusee' ($_.Exception.Message + $(if ($detail) { ' -- ' + $detail } else { '' })))
    exit 2
}

# --- 4. The answer ------------------------------------------------------------
# -Raw returns the JSON as it stands: that is what one pipes onward. Otherwise we display something readable,
# depth included -- a ConvertTo-Json that is too shallow displays "System.Object[]", and a diagnostic tool that
# hides what it found is of no use (seen on check-naming).
$json = $data | ConvertTo-Json -Depth 12
if ($Out) {
    [System.IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok (Get-Label 'ask-vigie.reponse-ecrite' $Out)
    exit 0
}
if ($Raw) { $json; exit 0 }

Write-Title (Get-Label 'ask-vigie.titre' $account)
$json
exit 0
