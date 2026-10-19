# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: accounts, config, log, paths, var
<#
    Intent: WHO IS SPEAKING TO THE SERVER: the account secret, the opening ticket worth one use and thirty seconds, and the session it leaves behind. What travels is disposable, what lasts is the session.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    Is the secret presented really this account's?

    The account's file is RE-READ, with its ACL check: if its rights have moved since it was
    laid, Get-AccountSecret throws and we refuse. A secret a third party may have read is
    worth nothing, and refusing it loudly beats accepting it in silence.
#>
function Test-AccountSecret {
    param(
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][string]$Secret
    )
    if (-not $Secret) { return $false }
    $varRoot = Get-AccountVarRoot -Account $Account
    if (-not $varRoot) { return $false }
    $sid = Get-AccountSid -Account $Account
    if (-not $sid) { return $false }
    $known = $null
    try { $known = Get-AccountSecret -VarRoot $varRoot -OwnerSid $sid } catch {
        try { Write-Log -Level 'ERROR' -Name 'session' -Message ("Secret du compte " + $Account + " refuse : " + $_.Exception.Message) } catch { }
        return $false
    }
    if (-not $known) { return $false }
    return ($known -ceq $Secret)
}

# --- Where tickets and sessions live ----------------------------------------------------
#
# In the SERVER's var, under a closed ACL: a session identifier is authentication information
# just as a secret is. The folder is laid with the same function as the secrets, and
# therefore with the same rigour.
function Get-SessionStorePath {
    param([string]$Kind = 'sessions', [string]$Backend = (Get-BackendRoot))
    $dir = Join-Path (Join-Path (Get-VarRoot -Backend $Backend) 'auth') $Kind
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
            Set-SecretFolderAcl -Path (Split-Path $dir -Parent) -OwnerSid $me
        } catch { }
    }
    return $dir
}

# AGE IS COUNTED IN SECONDS, NOT IN DATES. A date written to JSON comes back as a DateTime
# object, already converted into the local culture: "08/28/2026 20:43:31". Re-parsing it
# failed, the exception went unnoticed, and the age stayed empty -- which is to say a ticket
# NEVER expired. A number has neither culture nor surprise type.
function Get-EpochSeconds {
    return [double]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0)
}

function New-RandomId {
    $bytes = [byte[]]::new(24)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
}

# An opening ticket, valid once and for thirty seconds.
function New-OpenTicket {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $id = New-RandomId
    $file = Join-Path (Get-SessionStorePath -Kind 'tickets' -Backend $Backend) ($id + '.json')
    (@{ account = $Account; at = (Get-EpochSeconds) } | ConvertTo-Json -Compress) |
        Out-File -FilePath $file -Encoding UTF8
    return $id
}

# Consumes a ticket: returns the account, or $null. The file is DELETED in every case -- a
# ticket presented once, valid or stale, must not be able to serve again.
function Use-OpenTicket {
    param([Parameter(Mandatory)][string]$Ticket, [string]$Backend = (Get-BackendRoot))
    if ($Ticket -notmatch '^[A-Za-z0-9]{8,64}$') { return $null }
    $file = Join-Path (Get-SessionStorePath -Kind 'tickets' -Backend $Backend) ($Ticket + '.json')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $data = $null
    try { $data = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { }
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    if (-not $data) { return $null }
    if (((Get-EpochSeconds) - [double]$data.at) -gt 30) { return $null }
    return "$($data.account)"
}

# Opens a session and returns its identifier, the one the cookie will carry.
<#
    THE OPENING URL: THE ONLY WAY TO ASK FOR ONE.

    The gesture is always the same -- read THEIR account's secret, present it to the server,
    receive a single-use address -- and it was written in two places: in the client app and in
    the question tool. Two copies, so two behaviours to keep in step: they already did not
    have the same timeout.

    ONE CAN ONLY ASK FOR ONESELF. The secret lives in the account's profile, with an explicit
    ACL: nobody else reads it, and that is precisely what makes it prove an identity. To open
    a session in another account's name, one has to be inside THEIR session.

    Returns $null if anything at all fails -- the caller then opens the page without
    identification rather than refusing to open it.
#>
function Get-OpenUrl {
    param(
        [string]$Account = (Get-ProcessAccount),
        [string]$BaseUrl,
        [int]$TimeoutSec = 10,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not $BaseUrl) { $BaseUrl = Get-AppUrl -Backend $Backend }
    $BaseUrl = $BaseUrl.TrimEnd('/')
    $secret = $null
    try {
        $secret = Get-AccountSecret -VarRoot (Get-AccountVarRoot -Account $Account) `
                                    -OwnerSid (Get-AccountSid -Account $Account) -Create
    } catch { return $null }
    if (-not $secret) { return $null }
    $body = @{ account = $Account; secret = $secret } | ConvertTo-Json -Compress
    $reply = $null
    try {
        $reply = Invoke-RestMethod -Method Post -Uri ($BaseUrl + '/api/v1/session/ticket') `
                                   -ContentType 'application/json' -Body $body `
                                   -Headers @{ Origin = $BaseUrl } -TimeoutSec $TimeoutSec
    } catch { return $null }
    if (-not ($reply -and $reply.ok -and $reply.ticket)) { return $null }
    return ($BaseUrl + '/?t=' + $reply.ticket)
}

<#
    OPENING A SESSION WITH THE SERVER APP, AND RETURNING WHAT IT TAKES TO QUESTION IT.

    The whole path, the client app's own: the account's secret -> the opening address -> the
    cookie. It was written in the question tool; the client app needs it too, to READ THE
    STATE.

    WHY IT NEEDS IT. It used to read the cache file directly -- and since the server runs
    under a service account, that file lives in THAT account's profile: the client app was
    looking at a file nobody writes, and had not raised a single notification since 28/08.
    Going through the API solves both: it sees what the server sees, with its own account's
    rights, without reading in someone else's home.

    Returns a session object usable with Invoke-RestMethod, or $null.
#>
function Open-VigieSession {
    param(
        [string]$Account = (Get-ProcessAccount),
        [string]$BaseUrl,
        [int]$TimeoutSec = 10,
        [string]$Backend = (Get-BackendRoot)
    )
    if (-not $BaseUrl) { $BaseUrl = Get-AppUrl -Backend $Backend }
    $BaseUrl = $BaseUrl.TrimEnd('/')
    $url = Get-OpenUrl -Account $Account -BaseUrl $BaseUrl -TimeoutSec $TimeoutSec -Backend $Backend
    if (-not $url) { return $null }

    $handler = $null; $client = $null
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        # WE DO NOT FOLLOW THE REDIRECTION, and we do not let .NET manage the cookies: the
        # cookie arrives on the 302 response, and the next one no longer carries it.
        $handler.UseCookies = $false
        $handler.AllowAutoRedirect = $false
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $url)
        $req.Headers.Add('Origin', $BaseUrl)
        $req.Headers.ConnectionClose = $true
        $rep = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $value = $null
        if ($rep.Headers.Contains('Set-Cookie')) {
            foreach ($c in @($rep.Headers.GetValues('Set-Cookie'))) {
                if ("$c" -match 'vigie_session=([^;]+)') { $value = $Matches[1] }
            }
        }
        if (-not $value) { return $null }
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $session.Cookies.Add((New-Object System.Net.Cookie('vigie_session', $value, '/', '127.0.0.1')))
        return $session
    } catch { return $null }
    finally {
        if ($client)  { try { $client.Dispose() } catch { } }
        if ($handler) { try { $handler.Dispose() } catch { } }
    }
}

function New-AccountSession {
    param([Parameter(Mandatory)][string]$Account, [string]$Backend = (Get-BackendRoot))
    $id = New-RandomId
    $file = Join-Path (Get-SessionStorePath -Kind 'sessions' -Backend $Backend) ($id + '.json')
    (@{ account = $Account; at = (Get-EpochSeconds) } | ConvertTo-Json -Compress) |
        Out-File -FilePath $file -Encoding UTF8
    return $id
}

<#
    THE ACCOUNT BEHIND A SESSION, or $null.

    A SESSION DOES NOT EXPIRE. It used to, after 24 hours: past that delay the window stayed
    open but belonged to nobody -- the mark naming the reader disappeared from the accounts card and the actions
    no longer knew who was asking, with nothing announcing it. What is disposable is the
    OPENING URL: 30 seconds, one single presentation. What it leaves behind, the identity,
    must last, or one has to ask for another every time on a workstation where the person has
    not changed.

    A session ends otherwise: the file is deleted, or the account stops being enabled.
#>
function Get-SessionAccount {
    param([Parameter(Mandatory)][string]$SessionId, [string]$Backend = (Get-BackendRoot))
    if ($SessionId -notmatch '^[A-Za-z0-9]{8,64}$') { return $null }
    $file = Join-Path (Get-SessionStorePath -Kind 'sessions' -Backend $Backend) ($SessionId + '.json')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $data = $null
    try { $data = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { return $null }
    return "$($data.account)"
}
