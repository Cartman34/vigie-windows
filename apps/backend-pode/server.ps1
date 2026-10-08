# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    Intent: the HTTP surface of the server app, and nothing else -- every route the panel
    and the client app can call, and the thirty-second timer that does what Vigie does by
    itself. The reasoning lives in the library; this file exposes it.
    Usage: read it to find what a route answers, or to add one; a route states its case and
    delegates -- a computation written here instead of in the library is in the wrong file.
    It is dot-sourced by start.ps1 inside the server's own context, never run on its own.
#>
$backend = $env:VIGIE_BACKEND
. "$backend/lib/common.ps1"
# The name of the front end's folder is written in Get-AppPath only (common.ps1).
$front   = Get-AppPath -Role 'frontend'
$cfg  = Get-Config -Backend $backend
$base = $cfg.ApiBase

Add-PodeEndpoint -Address $cfg.BindAddress -Port $cfg.Port -Protocol Http

# --- Pode logging to file (errors + requests) ---
$logDir = Get-VarPath -Backend $backend -Kind 'log'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
try {
    if (Get-Command New-PodeLogFileMethod -ErrorAction SilentlyContinue) {
        New-PodeLogFileMethod -Path $logDir -Name 'pode-error'   | Enable-PodeErrorLogging
        New-PodeLogFileMethod -Path $logDir -Name 'pode-request' | Enable-PodeRequestLogging
    } else {
        New-PodeLoggingMethod -File -Path $logDir -Name 'pode-error'   | Enable-PodeErrorLogging
        New-PodeLoggingMethod -File -Path $logDir -Name 'pode-request' | Enable-PodeRequestLogging
    }
} catch { }

# THE SESSIONS FOLDER IS COMPUTED ONCE, here, and passed to the middleware through the environment. A Pode
# middleware runs in a separate runspace: it has neither the variables nor the functions of this file. Loading
# common.ps1 there at every request would cost a full load per API call.
$env:VIGIE_AUTH_SESSIONS = Get-SessionStorePath -Kind 'sessions' -Backend $backend

# --- Security: a Bearer token OR a session cookie, plus anti-CSRF (a local origin) ---
Add-PodeMiddleware -Name 'security' -ScriptBlock {
    $req = $WebEvent.Request
    $p = $req.Url.AbsolutePath
    if ($p -notlike '/api/*') { return $true }      # the interface, or a static file
    if ($p -like '*/health')  { return $true }
    # The request for a ticket authenticates ITSELF DIFFERENTLY: through the account's secret, which it carries in
    # its body. The client app has no API token -- that is precisely what we are replacing. The route checks for
    # itself, and refuses if the secret does not match.
    if ($p -like '*/session/ticket') { return $true }

    # 1) WHO IS SPEAKING? Two proofs accepted, and one is enough.
    #
    #    - the session cookie, laid down after a ticket was consumed: the normal road for a page opened by an
    #      account's client app;
    #    - the API token, the historical road, kept as long as not every caller has moved to the cookie
    #      (diagnostics, scripts).
    $authOk = $false
    if ($req.Headers['Authorization'] -eq ("Bearer " + $env:VIGIE_TOKEN)) { $authOk = $true }
    if (-not $authOk) {
        $sid = $null
        try { $sid = (Get-PodeCookie -Name 'vigie_session').Value } catch { }
        if ($sid -and $sid -match '^[A-Za-z0-9]{8,64}$' -and $env:VIGIE_AUTH_SESSIONS) {
            $f = Join-Path $env:VIGIE_AUTH_SESSIONS ($sid + '.json')
            if (Test-Path -LiteralPath $f) { $authOk = $true }
        }
    }
    if (-not $authOk) {
        Set-PodeResponseStatus -Code 401
        return $false
    }
    # 2) Anti-CSRF: the requests that change something must come from a local origin
    $method = ("" + $WebEvent.Method).ToUpperInvariant()
    if ($method -ne 'GET' -and $method -ne 'HEAD') {
        $origin = $req.Headers['Origin']; if (-not $origin) { $origin = $req.Headers['Referer'] }
        # The PORT derives from config.psd1 (through VIGIE_PORT, laid down by start.ps1): no duplication.
        # 127.0.0.1 and localhost are NOT a copy of BindAddress: they are the white list of LOOPBACK origins,
        # deliberately fixed. Even if BindAddress changed, only a local origin must be accepted. A Pode middleware
        # runs in a separate runspace: $cfg is not visible there, hence the passing through environment variables.
        $allowed = @("http://127.0.0.1:$($env:VIGIE_PORT)", "http://localhost:$($env:VIGIE_PORT)")
        $ok = $false
        foreach ($a in $allowed) { if ($origin -and $origin.StartsWith($a)) { $ok = $true } }
        if (-not $ok) { Set-PodeResponseStatus -Code 403; return $false }
    }
    return $true
}

# --- Who is speaking: the opening ticket --------------------------------------
#
# An account's client app presents ITS OWN secret -- which it alone can read -- and receives a single-use ticket.
# It then opens the page with that ticket in the URL. The secret never leaves the local machine and never enters a
# URL.
Add-PodeRoute -Method Post -Path "$base/session/ticket" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $body = $WebEvent.Data
    $account = "$($body.account)"
    $secret  = "$($body.secret)"
    if (-not $account -or -not $secret) {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ ok = $false; message = 'Compte ou secret absent.' }
        return
    }
    if (-not (Test-AccountSecret -Account $account -Secret $secret)) {
        # A REFUSAL WITHOUT AN EXPLANATION. Saying "wrong secret" rather than "unknown account" informs whoever is
        # trying. The trace, for its part, is complete on the server side.
        try { Write-Log -Backend $env:VIGIE_BACKEND -Name 'session' -Level 'WARN' `
                        -Message ("Ticket refuse pour le compte " + $account) } catch { }
        Set-PodeResponseStatus -Code 403
        Write-PodeJsonResponse -Value @{ ok = $false }
        return
    }
    $ticket = New-OpenTicket -Account $account -Backend $env:VIGIE_BACKEND
    try { Write-Log -Backend $env:VIGIE_BACKEND -Name 'session' `
                    -Message ("Ticket delivre au compte " + $account) } catch { }
    Write-PodeJsonResponse -Value @{ ok = $true; ticket = $ticket }
}

# --- The REST API ---
Add-PodeRoute -Method Get -Path "$base/health" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    # WHO IS SPEAKING: exposed here, because an identification mechanism one cannot observe cannot be debugged. A
    # dash means "nobody recognised".
    $account = '-'
    try {
        $sid = (Get-PodeCookie -Name 'vigie_session').Value
        if ($sid) {
            $c = Get-SessionAccount -SessionId $sid -Backend $env:VIGIE_BACKEND
            if ($c) { $account = $c }
        }
    } catch { }
    Write-PodeJsonResponse -Value @{
        status  = 'ok'
        account = $account
        version = (Get-AppVersion -Backend $env:VIGIE_BACKEND)
        build   = (Get-AppBuildId -Backend $env:VIGIE_BACKEND)
        # WHEN THE STATE CACHE LAST MOVED: the panel compares it to what it holds and reads again when it
        # differs, so a computation finished by the server shows up without waiting for the next minute.
        stateStamp = (Get-StateStamp -Backend $env:VIGIE_BACKEND)
        # The Atelier's URL if its server answers LOCALLY, otherwise null. It is the server that detects: the front
        # end cannot probe another port cleanly (cross-origin), and the Atelier's port must exist in ITS OWN config
        # only (D15).
        atelier = (Get-AtelierUrl)
    }
}
Add-PodeRoute -Method Get -Path "$base/state" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    # fresh=1: RECOMPUTE the probes instead of serving the cache. This is what the interface's refresh button asks
    # for, as opposed to loading the page, which must display quickly and makes do with the cache.
    $fresh = ("" + $WebEvent.Query['fresh']) -in @('1','true')
    # -WaitSeconds: only an explicit request waits its turn behind a computation already under way. 75 s, under the
    # client's 90 s timeout.
    Write-PodeJsonResponse -Value (Get-State -Backend $env:VIGIE_BACKEND -Force:$fresh -WaitSeconds $(if ($fresh) { 75 } else { 0 })) -Depth 24
}
Add-PodeRoute -Method Get -Path "$base/modules/:id" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $id = $WebEvent.Parameters['id']
    # fresh=1: THIS card's refresh button. We recompute its probes and WAIT for the result (75 s at most, under the
    # client's timeout); without that flag, loading the page and following a background task make do with the
    # cache.
    $fresh = ("" + $WebEvent.Query['fresh']) -in @('1','true')
    $etat = if ($fresh) { Get-State -Backend $env:VIGIE_BACKEND -ForceModule $id -WaitSeconds 75 }
            else        { Get-State -Backend $env:VIGIE_BACKEND }
    $m  = $etat.modules | Where-Object { $_.id -eq $id }
    if ($m) { Write-PodeJsonResponse -Value $m -Depth 24 }
    else    { Write-PodeJsonResponse -StatusCode 404 -Value @{ error = "Module inconnu : $id" } }
}
# --- Managing the modules (D48): list, enable, disable ------------------------
Add-PodeRoute -Method Get -Path "$base/units" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value @{ units = @(Get-UnitCatalog -Backend $env:VIGIE_BACKEND) } -Depth 6
}
Add-PodeRoute -Method Post -Path "$base/units/:id" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $id = $WebEvent.Parameters['id']
    $connu = @(Get-UnitCatalog -Backend $env:VIGIE_BACKEND | Where-Object { $_.id -eq $id })
    if (-not $connu) {
        Write-PodeJsonResponse -StatusCode 404 -Value @{ error = "Module inconnu : $id" }
        return
    }
    $d = $WebEvent.Data
    if (-not $d -or $null -eq $d.enabled) {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Champ 'enabled' requis" }
        return
    }
    Set-UnitEnabled -UnitId $id -Enabled ([bool]$d.enabled)
    # Switching a module back on must SHOW: its probes no longer have a guaranteed fresh cache, and the next /state
    # recomputes them in the background like any other expiry.
    Write-PodeJsonResponse -Value @{ units = @(Get-UnitCatalog -Backend $env:VIGIE_BACKEND) } -Depth 6
}

# --- The disc tree, ONE LEVEL at a time (D60 revised) -------------------------
# The interface never embeds the whole tree: it asks for the level it is displaying. Without `path`, that is the
# root of the last analysis.
Add-PodeRoute -Method Get -Path "$base/disk/tree" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $chemin = "$($WebEvent.Query['path'])"
    try {
        if (-not $chemin) {
            $f = Get-VarPath -Backend $env:VIGIE_BACKEND -Kind 'cache' -File 'diskscan.json'
            if (-not (Test-Path -LiteralPath $f)) { throw "Aucune analyse disponible." }
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            $chemin = if ($j.result -and $j.result.root) { "$($j.result.root)" } else { "$($j.scan.root)" }
        }
        $niveau = Get-DiskTreeLevel -Path $chemin -Backend $env:VIGIE_BACKEND
        Write-PodeJsonResponse -Value $niveau -Depth 6
    } catch {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "$($_.Exception.Message)" }
    }
}

# --- The Windows accounts that are allowed (D65) ------------------------------
# Reading is open (knowing WHO has Vigie is no secret); writing is reserved to an elevated server -- creating a
# task for somebody else is an administration operation.
Add-PodeRoute -Method Get -Path "$base/users" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value @{
        # USER accounts ONLY (the owner's rule): an account whose profile has never been used is a tool's account,
        # and we do not offer to give it Vigie. The same criterion as the Accounts card -- one single definition.
        users    = @(Get-UserAccounts -Backend $env:VIGIE_BACKEND)
        # Is the installation readable by the other accounts? If not, the interface must say so instead of offering
        # an activation that would fail.
        # "shared" = there exists an installation the other accounts can read, here or elsewhere. That is what
        # governs the activation of another account.
        shared      = [bool](Get-SharedInstallPath)
        installPath = $(if (Get-SharedInstallPath) { Get-SharedInstallPath } else { Get-RepoRoot })
        # The interface must be able to say WHY the switches are inert.
        canWrite = [bool](Test-IsElevated)
        # What a window without a session sees. The same screen, the same question: who has the right to see what.
        anonymousAccess = (Get-AnonymousAccess -Backend $env:VIGIE_BACKEND)
    } -Depth 6
}

<#
    CHANGING WHAT A WINDOW WITHOUT A SESSION SEES -- ADMINISTRATOR ONLY.

    The setting lives in the computer's declaration: it holds for every installation on the machine. So we demand
    the same rights as for any action that touches it, and we check them HERE: a greyed-out button is only a
    display.
#>
Add-PodeRoute -Method Post -Path "$base/anonymous-access" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $wanted = ''
    try { $wanted = "$($WebEvent.Data.mode)".Trim().ToLowerInvariant() } catch { }
    if ($wanted -notin @('error', 'cards')) {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Valeur attendue : « error » ou « cards »." }
        return
    }
    $who = Get-RequesterAccount
    $isAdmin = $false
    if ($who) { try { $isAdmin = [bool](Get-AccountByName -Name $who -Backend $env:VIGIE_BACKEND).admin } catch { } }
    if (-not $isAdmin -or -not (Test-IsElevated)) {
        Write-PodeJsonResponse -StatusCode 403 -Value @{ error = "Ce réglage vaut pour tout l'ordinateur : il demande un compte administrateur." }
        return
    }
    try {
        $written = Set-ComputerConfigValue -Values @{ AnonymousAccess = $wanted }
        Write-Log -Backend $env:VIGIE_BACKEND -Name 'session' `
                  -Message ("Fenetre sans session : « " + $wanted + " », decide par " + $who + " (" + $written + ")")
        Write-PodeJsonResponse -Value @{ anonymousAccess = (Get-AnonymousAccess -Backend $env:VIGIE_BACKEND) }
    } catch {
        Write-PodeJsonResponse -StatusCode 500 -Value @{ error = "$($_.Exception.Message)" }
    }
}
Add-PodeRoute -Method Post -Path "$base/users/:name" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $nom = $WebEvent.Parameters['name']
    $d = $WebEvent.Data
    if (-not $d -or $null -eq $d.enabled) {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Champ 'enabled' requis" }
        return
    }
    try {
        $target = Get-AccountByName -Name $nom -Backend $env:VIGIE_BACKEND
        if ($target -and $target.technical) {
            Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "$nom n'est pas un compte utilisateur : son profil n'a jamais servi." }
            return
        }
        Set-VigieAccountEnabled -Name $nom -Enabled ([bool]$d.enabled) -Backend $env:VIGIE_BACKEND | Out-Null
        Write-PodeJsonResponse -Value @{ users = @(Get-UserAccounts); canWrite = [bool](Test-IsElevated) } -Depth 6
    } catch {
        Write-PodeJsonResponse -StatusCode 403 -Value @{ error = "$($_.Exception.Message)" }
    }
}

# --- Module settings (D57): the default is the config, overridden by the user ---
Add-PodeRoute -Method Get -Path "$base/parameters" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value @{ modules = @(Get-ModuleParameterCatalog -Backend $env:VIGIE_BACKEND) } -Depth 6
}
Add-PodeRoute -Method Post -Path "$base/parameters/:unit" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $unit = $WebEvent.Parameters['unit']
    $d = $WebEvent.Data
    if (-not $d -or -not $d.values) {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Champ 'values' requis (cle -> valeur ; null = retour au defaut)" }
        return
    }
    $vals = @{}
    if ($d.values -is [System.Collections.IDictionary]) {
        foreach ($k in @($d.values.Keys)) { $vals["$k"] = $d.values[$k] }
    } else {
        foreach ($pr in $d.values.PSObject.Properties) { $vals["$($pr.Name)"] = $pr.Value }
    }
    try { Set-ModuleParameters -Unit $unit -Values $vals -Backend $env:VIGIE_BACKEND }
    catch {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = $_.Exception.Message }
        return
    }
    # A setting that changes must SHOW: the module's probes are recomputed at the next /state, without waiting for
    # their TTL.
    try {
        $probes = @(Get-ChildItem -Path (Join-Path (Join-Path "$env:VIGIE_BACKEND/probes" $unit)) -Filter '*.probe.ps1' -File |
                    ForEach-Object { $_.Name })
        if ($probes.Count) { Remove-ProbeCache -Names $probes -Backend $env:VIGIE_BACKEND }
    } catch { }
    Write-PodeJsonResponse -Value @{ modules = @(Get-ModuleParameterCatalog -Backend $env:VIGIE_BACKEND) } -Depth 6
}

# --- The history of the measurements: read only -------------------------------
Add-PodeRoute -Method Get -Path "$base/history/:measureId" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $id  = $WebEvent.Parameters['measureId']
    $win = "" + $WebEvent.Query['window']
    if (-not $win) { $win = '7d' }   # the contract's default
    $span = ConvertTo-HistoryWindow -Window $win
    # -StatusCode and not Set-PodeResponseStatus: the latter returns Pode's HTML error page and the JSON body is
    # lost (observed on the history routes).
    if (-not $span) {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Fenêtre invalide : « $win » (attendu <n>h ou <n>d, ex. 24h, 7d)" }
        return
    }
    $h = Get-MeasureHistory -Backend $env:VIGIE_BACKEND -MeasureId $id -Window $span -WindowLabel $win
    if ($null -eq $h) {
        Write-PodeJsonResponse -StatusCode 404 -Value @{ error = "Mesure inconnue : $id" }
        return
    }
    Write-PodeJsonResponse -Value $h -Depth 6
}

# --- Notification settings (D54): read and written by the interface -----------
Add-PodeRoute -Method Get -Path "$base/notifications" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $cfg = Get-NotificationSettings -Backend $env:VIGIE_BACKEND
    Write-PodeJsonResponse -Value @{
        enabled = [bool]$cfg.enabled
        modules = $cfg.modules
        notifs  = $cfg.notifs
        # The CATALOGUE: what each module knows how to notify, with real names.
        catalog = @(Get-NotificationCatalog -Backend $env:VIGIE_BACKEND)
    } -Depth 6
}
Add-PodeRoute -Method Post -Path "$base/notifications" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $d = $WebEvent.Data
    $mods = $null
    if ($d -and $d.modules) {
        # Pode delivers the JSON body as a DICTIONARY (not a PSCustomObject): enumerating PSObject.Properties would
        # then describe the container (Keys, IsReadOnly...) and not the keys -- it happened: the file carried a
        # module named after a boolean. We handle both forms explicitly.
        $mods = @{}
        if ($d.modules -is [System.Collections.IDictionary]) {
            foreach ($k in @($d.modules.Keys)) { $mods["$k"] = [bool]$d.modules[$k] }
        } else {
            foreach ($pr in $d.modules.PSObject.Properties) { $mods["$($pr.Name)"] = [bool]$pr.Value }
        }
    }
    # The same treatment for the FINE setting, notification by notification (the key "<module>.<notification>"):
    # that is the one carrying the real names (D54 revised).
    $nots = $null
    if ($d -and $d.notifs) {
        $nots = @{}
        if ($d.notifs -is [System.Collections.IDictionary]) {
            foreach ($k in @($d.notifs.Keys)) { $nots["$k"] = [bool]$d.notifs[$k] }
        } else {
            foreach ($pr in $d.notifs.PSObject.Properties) { $nots["$($pr.Name)"] = [bool]$pr.Value }
        }
    }
    $en = if ($d -and $null -ne $d.enabled) { [bool]$d.enabled } else { $null }
    Write-PodeJsonResponse -Value (Set-NotificationSettings -Backend $env:VIGIE_BACKEND -Enabled $en -Modules $mods -Notifs $nots) -Depth 4
}

Add-PodeRoute -Method Post -Path "$base/actions" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $d = $WebEvent.Data
    if (-not $d -or -not $d.type) {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Champ 'type' requis" }
        return
    }
    if ($d.type -notmatch '^[a-z][a-z0-9-]{1,40}$') {
        Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "type d'action invalide" }
        return
    }
    $params = @{}
    if ($d.params) { $d.params.GetEnumerator() | ForEach-Object { $params[$_.Key] = $_.Value } }
    $job = Invoke-ActionById -Type $d.type -Module $d.module -Params $params -Backend $env:VIGIE_BACKEND

    <#
        THE ANSWER CARRIES THE STATE OF THE OPERATIONS.

        Without that, the page learns an operation is running at the next poll -- up to four seconds later. So it
        displayed TWO notifications for one single click: its own, then the poll's, which did not recognise the
        operation yet (observed on 29/08, two notifications for the same update side by side).

        The server KNOWS what is running at the moment it answers: making it say so costs one folder read and
        removes the race. The page settles on that truth, without waiting.
    #>



    try {
        $etat = @{
            running = @(Get-RunningOperations -Backend $env:VIGIE_BACKEND)
            results = @(Get-RecentOperationResults -Backend $env:VIGIE_BACKEND)
        }
        $job | Add-Member -NotePropertyName 'operations' -NotePropertyValue $etat -Force
    } catch { }

    if ($job.status -eq 'error') { Write-PodeJsonResponse -StatusCode 400 -Value $job -Depth 24 }
    else { Write-PodeJsonResponse -Value $job -Depth 24 }
}

# --- WHAT IS RUNNING, FOR EVERY PAGE (D95) ------------------------------------
# Every page that is open -- even one opened AFTER the operation set off -- agrees on this state: the
# notifications no longer live inside one single window.
Add-PodeRoute -Method Get -Path "$base/operations" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value @{
        running = @(Get-RunningOperations -Backend $env:VIGIE_BACKEND)
        results = @(Get-RecentOperationResults -Backend $env:VIGIE_BACKEND)
    } -Depth 8
}

# --- THE HARDWARE SHEET: what does not move -----------------------------------
# The reading is remembered for seven days (the hardware does not change); ?fresh=1 for a new one.
Add-PodeRoute -Method Get -Path "$base/hardware" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $fresh = ("" + $WebEvent.Query['fresh']) -in @('1','true')
    Write-PodeJsonResponse -Value (Get-HardwareSpecs -Backend $env:VIGIE_BACKEND -Force:$fresh) -Depth 12
}

# --- PRINTABLE REPORTS (D86) --------------------------------------------------
# The same page for both documents, ?type=materiel|etat. It is SERVED by the server, like the panel: a file opened
# through file:// has neither a token nor the same origin, and could read nothing (D47).

Add-PodeRoute -Method Get -Path '/rapport' -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $front = Get-AppPath -Role 'frontend'
    $html  = Get-Content -Path (Join-Path $front 'rapport.html') -Raw
    $html  = $html.Replace('__API_TOKEN__', $env:VIGIE_TOKEN)
    Write-PodeTextResponse -Value $html -ContentType 'text/html; charset=utf-8'
}

# --- The interface: serves index.html, injecting the token (a same-origin page) ---
Add-PodeRoute -Method Get -Path '/' -ScriptBlock {
    # The FIRST line, as in every other route. A Pode route runs in its OWN runspace: nothing loaded when the
    # server started exists there. Here the load was placed AFTER two helper calls -- so the route threw
    # "Get-AppPath is not recognized" and returned 500: the application did not display at all, while the server
    # was answering.
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $front = Get-AppPath -Role 'frontend'

    <#
        "?t=..." IS EXCHANGED FOR A SESSION, THEN THE ADDRESS BECOMES CLEAN AGAIN.

        The opening URL is worth ONE USE ONLY -- 30 seconds, consumed at the first presentation -- and what it
        leaves behind, the session, LASTS. That is exactly the sharing we want: what travels is disposable, what
        stays is not.

        We REDIRECT to the main address as soon as the session is laid down. Without that, "?t=..." stays in the
        address bar and in the history: refreshing the page presents a ticket already consumed, and what one
        bookmarks works only once. After the redirection the bookmark is the right address, and the session
        follows.

        The cookie is HttpOnly -- out of reach of the page's JavaScript -- and SameSite=Strict, so no other site
        makes it travel. It carries a LONG lifetime, a year here: without it the cookie died when the browser
        closed, and the opening URL, being single-use, could no longer give it back. One would have lost one's
        identity by closing one's window.
    #>



    $ticket = $null
    try { $ticket = $WebEvent.Query['t'] } catch { }
    if ($ticket) {
        $account = Use-OpenTicket -Ticket $ticket -Backend $env:VIGIE_BACKEND
        if ($account) {
            $sid = New-AccountSession -Account $account -Backend $env:VIGIE_BACKEND
            <#
                THE COOKIE IS WRITTEN BY HAND, AND THAT IS DELIBERATE.

                Set-PodeCookie lays down an expiry date, which .NET serialises as "Max-Age" USING THE CURRENT
                CULTURE: on a French machine that gave a Max-Age with a comma in the number -- the attribute is then
                ignored by the browser, the cookie becomes a session cookie again and the identity was lost when the
                window closed. Measured on 31/08 in the header served.

                So we write an integer, ourselves.
            #>


            Add-PodeHeader -Name 'Set-Cookie' -Value (
                'vigie_session=' + $sid + '; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000')
            try { Write-Log -Backend $env:VIGIE_BACKEND -Name 'session' `
                            -Message ("Session ouverte pour le compte " + $account) } catch { }
        } else {
            try { Write-Log -Backend $env:VIGIE_BACKEND -Name 'session' -Level 'WARN' `
                            -Message "URL d'ouverture invalide ou périmée." } catch { }
        }
        <#
            THE TICKET LEAVES THE ADDRESS, WHATEVER HAPPENS.

            The redirection was made on success only: presented a second time, or past the thirty seconds, the
            address served the page WITH "?t=..." still in the bar. Yet what must disappear is not "the useful
            ticket", it is THE TICKET -- successful or not, valid or not, it has no business in the address, in the
            history or in a bookmark.

            So we redirect as soon as there is one, without looking at what it was worth.
        #>

        Move-PodeResponseUrl -Url '/'
        return
    }

    <#
        WITHOUT A SESSION WE DO NOT SERVE THE PANEL -- that is the default, and an administrator can decide
        otherwise (Get-AnonymousAccess).

        The panel carries the API token: serving it to a window that does not say who it is means giving the state
        of the machine, and the right to act, to any program on the workstation. Observed on 31/08 in a private
        window: everything was visible.

        The page returned instead holds no state, no token and no list of cards, and does not say what exactly is
        missing: whoever has the right to be there opens Vigie through its icon, the others learn nothing.
    #>

    if (-not (Get-RequesterAccount) -and (Get-AnonymousAccess -Backend $env:VIGIE_BACKEND) -eq 'error') {
        $refus = Join-Path $front 'no-session.html'
        if (Test-Path -LiteralPath $refus) {
            Write-PodeTextResponse -Value (Get-Content -Path $refus -Raw) -ContentType 'text/html; charset=utf-8' -StatusCode 403
            return
        }
    }

    $html  = Get-Content -Path (Join-Path $front 'index.html') -Raw
    $html  = $html.Replace('__API_TOKEN__', $env:VIGIE_TOKEN)
    $html  = $html.Replace('__APP_VERSION__', (Get-AppVersion -Backend $env:VIGIE_BACKEND))
    $html  = $html.Replace('__APP_BUILD__',   (Get-AppBuildId -Backend $env:VIGIE_BACKEND))

    # THE LABELS TRAVEL WITH THE PAGE, like the token. The other solution -- a fetch at startup -- adds a round
    # trip AND a race: the first rendering can arrive before the labels, and the screen flickers with missing-key
    # placeholders. Injected here, they are there before the first line of script.
    $labelFile = Join-Path (Split-Path (Split-Path $front -Parent) -Parent) 'lang/fr.json'
    $labelJson = if (Test-Path -LiteralPath $labelFile) {
        [System.IO.File]::ReadAllText($labelFile, (New-Object System.Text.UTF8Encoding($false)))
    } else { '{}' }
    $html  = $html.Replace('__LABELS_JSON__', $labelJson)
    Write-PodeTextResponse -Value $html -ContentType 'text/html; charset=utf-8'
}
Add-PodeStaticRoute -Path '/mock' -Source (Join-Path $front 'mock')

# Favicon: serves the client app's DELIVERED .ico. Without a favicon, the browser's dedicated window (--app) shows
# a generic globe in the task bar -- the application had no icon. We read the existing file again rather than
# adding a copy of the brand into the front end: one single rendering (D15, D38).
Add-PodeRoute -Method Get -Path '/favicon.ico' -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $ico = Join-Path (Get-AppPath -Role 'client') 'assets/ok.ico'
    if (-not (Test-Path -LiteralPath $ico)) { Set-PodeResponseStatus -Code 404; return }
    Write-PodeFileResponse -Path $ico -ContentType 'image/x-icon'
}

<#
    THE PERMANENT WATCH (CORE-WATCH). See doc/progress/targeting/surveillance.md.

    It does NOT recompute cards in a loop: it runs the READINGS the modules declare -- a cheap read, a comparable
    value -- and, when a value changes, it has the cards the module named recomputed, through the existing road.

    Without it, nothing is measured as long as nobody is looking: close every session and no notification can set
    off any more.

    IT KEEPS QUIET DURING AN INSTALLATION: the files change under its feet.

    The work is done HERE, in the timer: a reading costs a few milliseconds, and the recomputation that follows a
    change is rare by construction.
#>


Add-PodeTimer -Name 'vigie-watch' -Interval 30 -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    try {
        if (Get-InstallLockHolder) { return }
        # THE WHOLE ROUND IS WRAPPED (S14): what Vigie does by itself is seen like the rest, and a hang is found
        # even when this very timer is what is hung -- the reading is what judges.
        Invoke-WatchCycle -Backend $env:VIGIE_BACKEND -Body {
        # THE RESIDENTS FIRST: what must live beside the server is armed here, and armed again if it is dead
        # (targeting/residents.md). The first of them knows when a game starts; the sentinel that follows only
        # reads its result.
        Invoke-WatchTask -Name 'residents' -Label (Get-Label 'common.veille-residents') -MaxSeconds 10 -Backend $env:VIGIE_BACKEND -Body {
            $null = Invoke-ResidentPass -Backend $env:VIGIE_BACKEND
        }
        # THE CLIENT APPS NEXT, for the same reason as a resident: what must live beside the server is seen here, and
        # brought back when it is gone. A dead client app leaves its task reading "Running" with no process behind it,
        # and Windows then refuses every start: the account stayed without Vigie until its next session (28/09).
        Invoke-WatchTask -Name 'clients' -Label (Get-Label 'common.veille-clientes') -MaxSeconds 10 -Backend $env:VIGIE_BACKEND -Body {
            $null = Update-ClientWatch -Backend $env:VIGIE_BACKEND
        }
        $null = Invoke-WatchPass -Backend $env:VIGIE_BACKEND
        # THE NOTIFICATION IDENTITY: read before written, so this pass costs nothing once it
        # is right. Here rather than at install time alone -- an update runs the installer of
        # the version ALREADY in place, which necessarily knows nothing of what was just
        # added (measured on 07/09).
        try { $null = Set-VigieToastIdentity -InstallPath (Get-RepoRoot) } catch { }
        }
    } catch {
        try { Write-Log -Backend $env:VIGIE_BACKEND -Name 'state' -Level 'ERROR' `
                        -Message ("veille : " + $_.Exception.Message) } catch { }
    }
}
