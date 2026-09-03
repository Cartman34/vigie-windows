# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    ASK-VIGIE : POSER LA QUESTION A L'APP SERVEUR, PLUTOT QUE FOUILLER WINDOWS.

    LE PROBLEME. Depuis une session ordinaire, la moitie de ce qu'on veut savoir est
    ILLISIBLE : « schtasks /query /tn "Vigie - Famille" » repond « Acces refuse », les
    proprietaires de processus sont vides, LastUseTime ne rend rien. J'ai rapporte ce
    refus quatre fois comme s'il etait une information -- alors qu'il ne dit rien du
    poste, seulement de MES droits. Pire : il m'a fait annoncer qu'une tache n'existait
    pas alors qu'elle etait la.

    LA SOLUTION. L'app serveur est elevee, elle voit tout, et elle a deja une porte
    d'entree prevue pour ca : le secret du compte -> un ticket -> un cookie de session.
    C'est exactement le chemin que suit l'app cliente. On l'emprunte, et on obtient les
    faits TELS QUE VIGIE LES VOIT -- avec les droits du compte qui demande, ce qui est
    aussi le bon contexte pour juger.

    Aucun contournement, aucune elevation : ce script ne peut rien voir que l'app cliente
    du meme compte ne pourrait voir.

    EXEMPLES

        pwsh -File scripts/dev/ask-vigie.ps1 -Type accounts-details -Module accounts
        pwsh -File scripts/dev/ask-vigie.ps1 -Type accounts-details -Module accounts -Raw
        pwsh -File scripts/dev/ask-vigie.ps1 -Modules            # l'etat de toutes les cartes
        pwsh -File scripts/dev/ask-vigie.ps1 -Modules -Fresh     # ... recalculees, sans le cache
        pwsh -File scripts/dev/ask-vigie.ps1 -Modules -Module vigie-debug -Fresh   # une seule carte
        pwsh -File scripts/dev/ask-vigie.ps1 -Route 'history/net.latency?window=24h'

    Codes de retour : 0 = reponse obtenue ; 2 = pas de reponse (serveur muet, secret
    refuse). Le message dit lequel.
#>
[CmdletBinding()]
param(
    [string] $Type,
    [string] $Module,
    [hashtable] $Params = @{},
    # -Modules : l'etat des cartes, sans passer par une action.
    [switch] $Modules,
    # -Route : N'IMPORTE QUELLE ROUTE de lecture, telle qu'elle est ecrite dans le contrat
    # (ex. « /history/net.latency?window=24h »). Sans elle, verifier une route revient a
    # rebricoler un ticket et un cookie a la main -- ce que ce script existe pour eviter.
    [string] $Route,
    # -Fresh: RECOMPUTE instead of reading the cache. After an update the cards are still
    # the ones from before -- I read "v0.1.63" twice on a server already running v0.1.64 and
    # believed the deployment had changed nothing. WITH -Module, only that card is
    # recomputed: asking for all of them exceeds the server's own delay and returns 408.
    [switch] $Fresh,
    # -Raw : le JSON brut, pour enchainer avec jq. Sinon, un rendu lisible.
    [switch] $Raw,
    [int] $Port = 0,

    # -Out : ecrire la reponse dans un fichier, en UTF-8. Rediriger la sortie du terminal
    # la reencode dans la page de code de la console -- les accents arrivent casses et le
    # JSON n'est plus lisible par un outil. On ecrit donc nous-memes.
    [string] $Out
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

if (-not $Port) { $Port = [int](Get-Config -Backend $backend).Port }
$url = 'http://127.0.0.1:' + $Port

# --- 1. Le serveur repond-il ? -----------------------------------------------------------
try { $null = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop }
catch {
    Write-Fail (Get-Label 'ask-vigie.personne-n-ecoute' $Port)
    exit 2
}

# --- 2. Le secret du compte, puis le ticket ----------------------------------------------
# Le secret vit dans NOTRE profil, avec une ACL explicite : on est le seul a pouvoir le
# lire, et c'est precisement ce qui fait qu'il prouve notre identite.
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
    ON LIT LE COOKIE NOUS-MEMES.

    Invoke-WebRequest echoue sur « /?t=... » avec « Unable to read data from the transport
    connection », alors que la MEME page sans ticket se sert en 0,1 s et que curl reussit
    a tous les coups. Ce qui distingue cette route : elle POSE UN COOKIE. C'est son analyse
    par .NET qui casse la lecture de la reponse, pas le serveur.

    On desactive donc le magasin de cookies (UseCookies = $false), on lit l'en-tete
    Set-Cookie a la main, et on fabrique la session avec. Deux essais suffisent alors --
    le premier passe.
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
        # Le secret ne correspond pas : reessayer n'y changera rien.
        Write-Fail (Get-Label 'ask-vigie.ticket-refuse')
        exit 2
    }

    $handler = $null; $client = $null
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseCookies = $false
        <#
            ON NE SUIT PAS LA REDIRECTION.

            Depuis que l'adresse d'ouverture renvoie vers l'adresse principale, le cookie
            arrive sur la reponse 302 -- et si l'on suit, c'est la reponse SUIVANTE qu'on
            lit : sans cookie envoye (UseCookies = false), le serveur repond alors par la
            page « aucun compte », en 403, et le cookie de la premiere reponse est perdu.
            Constate le 31/08 : « L'app serveur n'a pas pose de cookie (code HTTP 403) »,
            alors qu'il l'avait bel et bien pose.
        #>
        $handler.AllowAutoRedirect = $false
        $client  = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(60)
        # La methode s'ecrit avec son TYPE : passer la chaine « GET » laisse PowerShell
        # choisir une surcharge au hasard, et l'appel echoue une fois sur deux.
        $req = New-Object System.Net.Http.HttpRequestMessage(
                    [System.Net.Http.HttpMethod]::Get, ($url + '/?t=' + $reply.ticket))
        $req.Headers.Add('Origin', $url)
        $req.Headers.ConnectionClose = $true
        # ON S ARRETE AUX EN-TETES. Le cookie est dans l'en-tete ; le corps fait 220 Ko
        # dont on n'a aucun usage, et c'est justement sa copie qui casse (« Error while
        # copying content to a stream »). Ne pas lire ce qu'on ne veut pas est plus sur
        # que de reessayer de le lire.
        $rep = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $brut = $null
        if ($rep.Headers.Contains('Set-Cookie')) { $brut = @($rep.Headers.GetValues('Set-Cookie')) }
        $valeur = $null
        foreach ($c in @($brut)) {
            if ("$c" -match 'vigie_session=([^;]+)') { $valeur = $Matches[1] }
        }
        if (-not $valeur) { throw (Get-Label 'ask-vigie.pas-de-cookie' ([int]$rep.StatusCode)) }
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $session.Cookies.Add((New-Object System.Net.Cookie('vigie_session', $valeur, '/', '127.0.0.1')))
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

# --- 3. La question ----------------------------------------------------------------------
try {
    if ($Route) {
        $target = $url + '/api/v1/' + $Route.TrimStart([char]47)
        $data = Invoke-RestMethod -Method Get -Uri $target `
                                  -WebSession $session -Headers @{ Origin = $url } -TimeoutSec 120
    } elseif ($Modules) {
        # "/state": the whole state, cards included. "/modules/:id" returns ONE card, and
        # "/modules" does not exist -- which is what I had written, hence a 404.
        $route = if ($Module) { $url + '/api/v1/modules/' + $Module } else { $url + '/api/v1/state' }
        if ($Fresh) { $route += '?fresh=1' }
        $data = Invoke-RestMethod -Method Get -Uri $route `
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
    Write-Fail (Get-Label 'ask-vigie.question-refusee' $_.Exception.Message)
    exit 2
}

# --- 4. La reponse -----------------------------------------------------------------------
# -Raw rend le JSON tel quel : c'est ce qu'on enchaine. Sinon on affiche de quoi lire,
# profondeur comprise -- un ConvertTo-Json trop court affiche « System.Object[] », et un
# outil de diagnostic qui cache ce qu'il a trouve ne sert a rien (vu sur check-naming).
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
