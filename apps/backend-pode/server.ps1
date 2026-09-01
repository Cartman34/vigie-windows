# @author Florent HAZARD <f.hazard@sowapps.com>
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

# LE DOSSIER DES SESSIONS EST CALCULE UNE FOIS, ici, et passe au middleware par
# l'environnement. Un middleware Pode tourne dans un runspace separe : il n'a ni les
# variables ni les fonctions de ce fichier. Y charger common.ps1 a chaque requete
# couterait un chargement complet par appel d'API.
$env:VIGIE_AUTH_SESSIONS = Get-SessionStorePath -Kind 'sessions' -Backend $backend

# --- Securite : jeton Bearer OU cookie de session, + anti-CSRF (origine locale) ---
Add-PodeMiddleware -Name 'security' -ScriptBlock {
    $req = $WebEvent.Request
    $p = $req.Url.AbsolutePath
    if ($p -notlike '/api/*') { return $true }      # UI / statique
    if ($p -like '*/health')  { return $true }
    # La demande de ticket s'authentifie AUTREMENT : par le secret du compte, qu'elle
    # porte dans son corps. Le tray n'a pas de jeton d'API -- c'est justement ce qu'on
    # remplace. La route verifie elle-meme, et refuse si le secret ne correspond pas.
    if ($p -like '*/session/ticket') { return $true }

    # 1) QUI PARLE ? Deux preuves acceptees, et une seule suffit.
    #
    #    - le cookie de session, pose apres consommation d'un ticket : c'est la voie
    #      normale d'une page ouverte par le tray d'un compte ;
    #    - le jeton d'API, la voie historique, conservee tant que tous les appelants
    #      ne sont pas passes au cookie (diagnostics, scripts).
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

# --- Qui parle : ticket d'ouverture ------------------------------------------------------
#
# Le tray d'un compte presente SON secret -- qu'il est seul a pouvoir lire -- et recoit un
# ticket a usage unique. Il ouvre ensuite la page avec ce ticket dans l'URL. Le secret,
# lui, ne quitte jamais la machine locale et n'entre jamais dans une URL.
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
        # REFUS SANS EXPLICATION. Dire « mauvais secret » plutot que « compte inconnu »
        # renseigne qui essaie. La trace, elle, est complete cote serveur.
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

# --- API REST ---
Add-PodeRoute -Method Get -Path "$base/health" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    # QUI PARLE : expose ici, parce qu'un mecanisme d'identification qu'on ne peut pas
    # observer ne se debogue pas. « - » signifie « personne de reconnu ».
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
        # URL de l'Atelier si son serveur repond en LOCAL, sinon null. C'est le serveur
        # qui detecte : le front ne peut pas sonder un autre port proprement
        # (cross-origin), et le port de l'Atelier ne doit exister que dans SA config (D15).
        atelier = (Get-AtelierUrl)
    }
}
Add-PodeRoute -Method Get -Path "$base/state" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    # fresh=1 : RECALCULE les sondes au lieu de servir le cache. C'est ce que demande le
    # bouton « Rafraichir » de l'interface, par opposition au chargement de la page, qui
    # doit s'afficher vite et se contente du cache.
    $fresh = ("" + $WebEvent.Query['fresh']) -in @('1','true')
    # -WaitSeconds : seule la demande explicite attend son tour derriere un calcul
    # deja lance. 75 s, sous le delai de 90 s du client.
    Write-PodeJsonResponse -Value (Get-State -Backend $env:VIGIE_BACKEND -Force:$fresh -WaitSeconds $(if ($fresh) { 75 } else { 0 })) -Depth 24
}
Add-PodeRoute -Method Get -Path "$base/modules/:id" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $id = $WebEvent.Parameters['id']
    # fresh=1 : le bouton « Rafraichir » de CETTE carte. On recalcule ses sondes et on
    # ATTEND le resultat (75 s au plus, sous le delai du client) ; sans ce drapeau, le
    # chargement et le suivi d'une tache de fond se contentent du cache.
    $fresh = ("" + $WebEvent.Query['fresh']) -in @('1','true')
    $etat = if ($fresh) { Get-State -Backend $env:VIGIE_BACKEND -ForceModule $id -WaitSeconds 75 }
            else        { Get-State -Backend $env:VIGIE_BACKEND }
    $m  = $etat.modules | Where-Object { $_.id -eq $id }
    if ($m) { Write-PodeJsonResponse -Value $m -Depth 24 }
    else    { Write-PodeJsonResponse -StatusCode 404 -Value @{ error = "Module inconnu : $id" } }
}
# --- Gestion des modules (D48) : lister, activer, desactiver ------------------
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
    # Rallumer un module doit se VOIR : ses sondes n'ont plus de cache frais garanti,
    # le prochain /state les recalcule en fond comme n'importe quelle peremption.
    Write-PodeJsonResponse -Value @{ units = @(Get-UnitCatalog -Backend $env:VIGIE_BACKEND) } -Depth 6
}

# --- Arborescence du disque, UN NIVEAU a la fois (D60 revu) -------------------
# L'interface n'embarque jamais l'arbre entier : elle demande le niveau qu'elle affiche.
# Sans `path`, c'est la racine de la derniere analyse.
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

# --- Comptes Windows autorises (D65) -----------------------------------------
# Lecture ouverte (savoir QUI a Vigie n'est pas un secret) ; ecriture reservee a un
# serveur eleve -- creer une tache pour autrui est une operation d'administration.
Add-PodeRoute -Method Get -Path "$base/users" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value @{
        # UNIQUEMENT les comptes utilisateurs (regle utilisateur) : un compte dont le
        # profil n'a jamais servi est un compte d'outil, on ne propose pas de lui donner
        # Vigie. Meme critere que la carte Comptes -- une seule definition.
        users    = @(Get-UserAccounts -Backend $env:VIGIE_BACKEND)
        # Installation lisible par les autres comptes ? Sinon l'interface doit le dire au
        # lieu de proposer une activation qui echouerait.
        # « partagee » = il existe une installation que les autres comptes peuvent lire,
        # ici ou ailleurs. C'est ce qui conditionne l'activation d'un autre compte.
        shared      = [bool](Get-SharedInstallPath)
        installPath = $(if (Get-SharedInstallPath) { Get-SharedInstallPath } else { Get-RepoRoot })
        # L'interface doit pouvoir dire POURQUOI les interrupteurs sont inertes.
        canWrite = [bool](Test-IsElevated)
        # Ce que voit une fenetre sans session. Meme ecran, meme question : qui a le droit
        # de voir quoi.
        anonymousAccess = (Get-AnonymousAccess -Backend $env:VIGIE_BACKEND)
    } -Depth 6
}

<#
    CHANGER CE QUE VOIT UNE FENETRE SANS SESSION -- ADMINISTRATEUR SEULEMENT.

    Le reglage vit dans la declaration de l'ordinateur : il vaut pour toutes les
    installations de la machine. On demande donc les memes droits que pour toute action
    qui la touche, et on le verifie ICI : un bouton grise n'est qu'un affichage.
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

# --- Parametres de modules (D57) : defaut = config, surcharge par l'utilisateur ---
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
    # Un reglage change doit se VOIR : les sondes du module sont recalculees au prochain
    # /state, sans attendre leur TTL.
    try {
        $probes = @(Get-ChildItem -Path (Join-Path (Join-Path "$env:VIGIE_BACKEND/probes" $unit)) -Filter '*.probe.ps1' -File |
                    ForEach-Object { $_.Name })
        if ($probes.Count) { Remove-ProbeCache -Names $probes -Backend $env:VIGIE_BACKEND }
    } catch { }
    Write-PodeJsonResponse -Value @{ modules = @(Get-ModuleParameterCatalog -Backend $env:VIGIE_BACKEND) } -Depth 6
}

# --- Historique des mesures (etape 2 du plan) : lecture seule -----------------
Add-PodeRoute -Method Get -Path "$base/history/:measureId" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $id  = $WebEvent.Parameters['measureId']
    $win = "" + $WebEvent.Query['window']
    if (-not $win) { $win = '7d' }   # defaut du contrat
    $span = ConvertTo-HistoryWindow -Window $win
    # -StatusCode et non Set-PodeResponseStatus : ce dernier rend la page d'erreur
    # HTML de Pode et le corps JSON est perdu (constate sur les routes historiques).
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

# --- Reglages des notifications (D54) : lus/ecrits par l'interface -----------
Add-PodeRoute -Method Get -Path "$base/notifications" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $cfg = Get-NotificationSettings -Backend $env:VIGIE_BACKEND
    Write-PodeJsonResponse -Value @{
        enabled = [bool]$cfg.enabled
        modules = $cfg.modules
        notifs  = $cfg.notifs
        # Le CATALOGUE : ce que chaque module sait notifier, avec de vrais noms.
        catalog = @(Get-NotificationCatalog -Backend $env:VIGIE_BACKEND)
    } -Depth 6
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
    # Meme traitement pour le reglage FIN, notification par notification (cle
    # « <module>.<notification> ») : c'est lui qui porte les vrais noms (D54 revu).
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
        LA REPONSE PORTE L'ETAT DES OPERATIONS.

        Sans cela, la page apprend qu'une operation tourne au sondage suivant -- jusqu'a
        quatre secondes plus tard. Elle affichait donc DEUX notifications pour un seul
        clic : la sienne, puis celle du sondage qui ne reconnaissait pas encore
        l'operation (constate le 29/08 : « Mettre a jour l'installation » et « Mise a jour
        de Vigie » cote a cote).

        Le serveur SAIT ce qui tourne au moment ou il repond : le lui faire dire coute une
        lecture de dossier et supprime la course. La page se cale sur cette verite, sans
        attendre.
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

# --- CE QUI TOURNE, POUR TOUTES LES PAGES (D95) ------------------------------
# Toute page ouverte -- meme ouverte APRES le depart de l'operation -- s'accorde sur
# cet etat : les notifications ne vivent plus dans une seule fenetre.
Add-PodeRoute -Method Get -Path "$base/operations" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    Write-PodeJsonResponse -Value @{
        running = @(Get-RunningOperations -Backend $env:VIGIE_BACKEND)
        results = @(Get-RecentOperationResults -Backend $env:VIGIE_BACKEND)
    } -Depth 8
}

# --- FICHE MATERIELLE : ce qui ne bouge pas ----------------------------------
# Releve memorise sept jours (le materiel ne change pas) ; ?fresh=1 pour un neuf.
Add-PodeRoute -Method Get -Path "$base/hardware" -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $fresh = ("" + $WebEvent.Query['fresh']) -in @('1','true')
    Write-PodeJsonResponse -Value (Get-HardwareSpecs -Backend $env:VIGIE_BACKEND -Force:$fresh) -Depth 12
}

# --- RAPPORTS IMPRIMABLES (D86) ---------------------------------------------
# Meme page pour les deux documents, ?type=materiel|etat. Elle est SERVIE par le
# serveur, comme le tableau de bord : un fichier ouvert en file:// n'a ni jeton ni
# meme origine, il ne pourrait rien lire (D47).
Add-PodeRoute -Method Get -Path '/rapport' -ScriptBlock {
    . "$env:VIGIE_BACKEND/lib/common.ps1"
    $front = Get-AppPath -Role 'frontend'
    $html  = Get-Content -Path (Join-Path $front 'rapport.html') -Raw
    $html  = $html.Replace('__API_TOKEN__', $env:VIGIE_TOKEN)
    Write-PodeTextResponse -Value $html -ContentType 'text/html; charset=utf-8'
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

    <#
        « ?t=... » S'ECHANGE CONTRE UNE SESSION, PUIS L'ADRESSE REDEVIENT PROPRE.

        L'URL d'ouverture ne vaut QU'UNE FOIS -- 30 secondes, consommee a la premiere
        presentation -- et ce qu'elle laisse derriere elle, la session, DURE. C'est
        exactement le partage voulu : ce qui circule est jetable, ce qui reste ne l'est
        pas.

        On REDIRIGE vers l'adresse principale des que la session est posee. Sans cela,
        « ?t=... » reste dans la barre d'adresse et dans l'historique : rafraichir la page
        represente un jeton deja consomme, et ce qu'on met en signet ne marche qu'une
        fois. Apres la redirection, le signet est la bonne adresse, et la session suit.

        Le cookie est HttpOnly -- hors de portee du JavaScript de la page -- et
        SameSite=Strict, donc aucun autre site ne le fait voyager. Il porte une duree
        LONGUE, la un an : sans elle il mourait a la fermeture du navigateur, et l'URL
        d'ouverture, a usage unique, ne pouvait plus le rendre. On aurait perdu son
        identite en fermant sa fenetre.
    #>
    $ticket = $null
    try { $ticket = $WebEvent.Query['t'] } catch { }
    if ($ticket) {
        $account = Use-OpenTicket -Ticket $ticket -Backend $env:VIGIE_BACKEND
        if ($account) {
            $sid = New-AccountSession -Account $account -Backend $env:VIGIE_BACKEND
            <#
                LE COOKIE EST ECRIT A LA MAIN, ET C'EST VOULU.

                Set-PodeCookie pose une date d'expiration, que .NET serialise en
                « Max-Age » avec la CULTURE COURANTE : sur une machine francaise, cela
                donnait « Max-Age=31535999,9865232 ». Une virgule dans un nombre --
                l'attribut est alors ignore par le navigateur, le cookie redevient un
                cookie de session et l'identite se perdait a la fermeture de la fenetre.
                Mesure le 31/08 dans l'en-tete servi.

                On ecrit donc un entier, nous-memes.
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
            LE JETON QUITTE L'ADRESSE, QUOI QU'IL ARRIVE.

            La redirection n'etait faite qu'en cas de succes : presentee une seconde fois,
            ou passe les trente secondes, l'adresse servait la page AVEC « ?t=... » encore
            dans la barre. Or ce qui doit disparaitre n'est pas « le jeton utile », c'est
            LE JETON -- reussi ou non, valide ou non, il n'a rien a faire dans l'adresse,
            dans l'historique ni dans un signet.

            On redirige donc des qu'il y en a un, sans regarder ce qu'il valait.
        #>
        Move-PodeResponseUrl -Url '/'
        return
    }

    <#
        SANS SESSION, ON NE SERT PAS LE PANNEAU -- c'est le defaut, et un administrateur
        peut en decider autrement (Get-AnonymousAccess).

        Le panneau porte le jeton d'API : le servir a une fenetre qui ne dit pas qui elle
        est, c'est donner l'etat de la machine et le droit d'agir a n'importe quel
        programme du poste. Constate le 31/08 en navigation privee : tout etait visible.

        La page rendue a la place ne contient ni etat, ni jeton, ni liste de cartes, et ne
        dit pas ce qui manque exactement : celui qui a le droit d'etre la ouvre Vigie par
        son icone, les autres n'apprennent rien.
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

    # LES LIBELLES VOYAGENT AVEC LA PAGE, comme le jeton. L'autre solution -- un fetch au
    # demarrage -- ajoute un aller-retour ET une course : le premier rendu peut arriver
    # avant les libelles, et l'ecran clignote en « [?...] ». Injectes ici, ils sont la
    # avant la premiere ligne de script.
    $labelFile = Join-Path (Split-Path (Split-Path $front -Parent) -Parent) 'lang/fr.json'
    $labelJson = if (Test-Path -LiteralPath $labelFile) {
        [System.IO.File]::ReadAllText($labelFile, (New-Object System.Text.UTF8Encoding($false)))
    } else { '{}' }
    $html  = $html.Replace('__LABELS_JSON__', $labelJson)
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
