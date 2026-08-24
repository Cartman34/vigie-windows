<#
    server.ps1 - Endpoints et routes Pode (implementation du contrat).
    Dot-source depuis start.ps1 dans le contexte du serveur. Journalise les
    erreurs et requetes dans backend/logs/ via la journalisation Pode.
#>
$backend = $env:VIGIE_BACKEND
. "$backend/lib/common.ps1"
# Le nom du dossier du front n'est ecrit que dans Get-AppPath (common.ps1).
$front   = Get-AppPath -Role 'frontend'
$cfg  = Get-Config -Backend $backend
$base = $cfg.ApiBase

Add-PodeEndpoint -Address $cfg.BindAddress -Port $cfg.Port -Protocol Http

# --- Journalisation Pode sur fichier (erreurs + requetes) ---
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

# --- Securite : jeton Bearer + anti-CSRF (origine locale) ---
Add-PodeMiddleware -Name 'security' -ScriptBlock {
    $req = $WebEvent.Request
    $p = $req.Url.AbsolutePath
    if ($p -notlike '/api/*') { return $true }      # UI / statique
    if ($p -like '*/health')  { return $true }
    # 1) Jeton Bearer obligatoire
    if ($req.Headers['Authorization'] -ne ("Bearer " + $env:VIGIE_TOKEN)) {
        Set-PodeResponseStatus -Code 401
        return $false
    }
    # 2) Anti-CSRF : les requetes modifiantes doivent venir d'une origine locale
    $method = ("" + $WebEvent.Method).ToUpperInvariant()
    if ($method -ne 'GET' -and $method -ne 'HEAD') {
        $origin = $req.Headers['Origin']; if (-not $origin) { $origin = $req.Headers['Referer'] }
        # Le PORT derive de config.psd1 (via VIGIE_PORT, pose par start.ps1) : pas de duplication.
        # 127.0.0.1 et localhost ne sont PAS une copie de BindAddress : c'est la liste blanche
        # des origines de BOUCLAGE, volontairement fixe. Meme si BindAddress changeait, seule
        # une origine locale doit etre acceptee. Un middleware Pode tourne dans un runspace
        # separe : $cfg n'y est pas visible, d'ou le passage par les variables d'environnement.
        $allowed = @("http://127.0.0.1:$($env:VIGIE_PORT)", "http://localhost:$($env:VIGIE_PORT)")
        $ok = $false
        foreach ($a in $allowed) { if ($origin -and $origin.StartsWith($a)) { $ok = $true } }
        if (-not $ok) { Set-PodeResponseStatus -Code 403; return $false }
    }
    return $true
}

# --- API REST ---
Add-PodeRoute -Method Get -Path "$base/health" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value @{ status = 'ok'; version = (Get-AppVersion -Backend $env:VIGIE_BACKEND);
                                 build = (Get-AppBuildId -Backend $env:VIGIE_BACKEND) }
}
Add-PodeRoute -Method Get -Path "$base/state" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    # fresh=1 : RECALCULE les sondes au lieu de servir le cache. C'est ce que demande le
    # bouton « Rafraichir » de l'interface, par opposition au chargement de la page, qui
    # doit s'afficher vite et se contente du cache.
    $fresh = ("" + $WebEvent.Query['fresh']) -in @('1','true')
    # -WaitSeconds : seule la demande explicite attend son tour derriere un calcul
    # deja lance. 75 s, sous le delai de 90 s du client.
    Write-PodeJsonResponse -Value (Get-State -Backend $env:VIGIE_BACKEND -Force:$fresh -WaitSeconds $(if ($fresh) { 75 } else { 0 })) -Depth 8
}
Add-PodeRoute -Method Get -Path "$base/modules/:id" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $id = $WebEvent.Parameters['id']
    $m  = (Get-State -Backend $env:VIGIE_BACKEND).modules | Where-Object { $_.id -eq $id }
    if ($m) { Write-PodeJsonResponse -Value $m -Depth 8 }
    else    { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ error = "Module inconnu : $id" } }
}
# --- Reglages des notifications (D54) : lus/ecrits par l'interface -----------
Add-PodeRoute -Method Get -Path "$base/notifications" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value (Get-NotificationSettings -Backend $env:VIGIE_BACKEND) -Depth 4
}
Add-PodeRoute -Method Post -Path "$base/notifications" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $d = $WebEvent.Data
    $mods = $null
    if ($d -and $d.modules) {
        # Pode livre le corps JSON en DICTIONNAIRE (pas en PSCustomObject) : enumerer
        # PSObject.Properties decrirait alors le conteneur (Keys, IsReadOnly...) et non
        # les cles -- c'est arrive : le fichier portait un module « True ». On gere les
        # deux formes explicitement.
        $mods = @{}
        if ($d.modules -is [System.Collections.IDictionary]) {
            foreach ($k in @($d.modules.Keys)) { $mods["$k"] = [bool]$d.modules[$k] }
        } else {
            foreach ($pr in $d.modules.PSObject.Properties) { $mods["$($pr.Name)"] = [bool]$pr.Value }
        }
    }
    $en = if ($d -and $null -ne $d.enabled) { [bool]$d.enabled } else { $null }
    Write-PodeJsonResponse -Value (Set-NotificationSettings -Backend $env:VIGIE_BACKEND -Enabled $en -Modules $mods) -Depth 4
}

Add-PodeRoute -Method Post -Path "$base/actions" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $d = $WebEvent.Data
    if (-not $d -or -not $d.type) {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = "Champ 'type' requis" }
        return
    }
    if ($d.type -notmatch '^[a-z][a-z0-9-]{1,40}$') {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = "type d'action invalide" }
        return
    }
    $params = @{}
    if ($d.params) { $d.params.GetEnumerator() | ForEach-Object { $params[$_.Key] = $_.Value } }
    $job = Invoke-ActionById -Type $d.type -Module $d.module -Params $params -Backend $env:VIGIE_BACKEND
    if ($job.status -eq 'error') { Set-PodeResponseStatus -Code 400 }
    Write-PodeJsonResponse -Value $job -Depth 8
}

# --- UI : sert index.html en injectant le jeton (page meme origine) ---
Add-PodeRoute -Method Get -Path '/' -ScriptBlock {
    # PREMIERE ligne, comme dans toutes les autres routes. Une route Pode s'execute dans
    # son PROPRE espace d'execution : rien de ce qui est charge au demarrage du serveur
    # n'y existe. Ici le chargement etait place APRES deux appels d'aide -- la route
    # levait donc « Get-AppPath is not recognized » et rendait 500 : l'application ne
    # s'affichait pas du tout, alors que le serveur repondait.
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $front = Get-AppPath -Role 'frontend'
    $html  = Get-Content -Path (Join-Path $front 'index.html') -Raw
    $html  = $html.Replace('__API_TOKEN__', $env:VIGIE_TOKEN)
    $html  = $html.Replace('__APP_VERSION__', (Get-AppVersion -Backend $env:VIGIE_BACKEND))
    $html  = $html.Replace('__APP_BUILD__',   (Get-AppBuildId -Backend $env:VIGIE_BACKEND))
    Write-PodeTextResponse -Value $html -ContentType 'text/html; charset=utf-8'
}
Add-PodeStaticRoute -Path '/mock' -Source (Join-Path $front 'mock')

# Favicon : sert le .ico LIVRE du tray. Sans favicon, la fenetre dediee du navigateur
# (--app) affiche un globe generique dans la barre des taches -- l'application n'avait
# pas d'icone. On relit le fichier existant plutot que d'ajouter une copie de la marque
# dans le front : une seule representation (D15, D38).
Add-PodeRoute -Method Get -Path '/favicon.ico' -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $ico = Join-Path (Get-AppPath -Role 'tray') 'assets/ok.ico'
    if (-not (Test-Path -LiteralPath $ico)) { Set-PodeResponseStatus -Code 404; return }
    Write-PodeFileResponse -Path $ico -ContentType 'image/x-icon'
}
