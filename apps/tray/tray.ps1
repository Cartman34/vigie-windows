<#
    tray.ps1 - App Vigie de la barre systeme (apps/tray).

    C'est une app A PART ENTIERE, distincte du backend : elle a son interface
    WinForms, ses icones (assets/) et son cycle de vie. Elle PILOTE le backend
    (le demarre, l'arrete, sonde sa sante) sans en faire partie.
    - Serveur Pode EN FOND (cache). Icone = STATUT DE L'APP (pas des composants) via /health :
        vert = en marche, orange = demarrage, rouge = erreur/arret. Poll leger toutes les 8 s.
    - "Afficher l'application" -> fenetre DEDIEE (Edge/Chrome en mode --app). "Ouvrir dans le navigateur" -> onglet.
    - "Relancer l'application" recharge le tray. Menu sombre. Enfants lances sans fenetre (CreateNoWindow).
    - Journalise dans logs/tray_*.log. UI en runspace STA. Instance unique.
#>
$ErrorActionPreference = 'Stop'
# URL du depot : CONSTANTE volontaire (pas un reglage) - elle ne doit pas changer facilement.
# Equivalent cote front : REPO_URL dans frontend/index.html.
$RepoUrl = 'https://github.com/Cartman34/vigie-windows'
# Le backend est une app SOEUR (apps/backend), pas le dossier courant.
$appsRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $appsRoot 'backend-pode'   # BOOTSTRAP : nom en clair, cf. common.ps1
$repoRoot = Split-Path $appsRoot -Parent
# Chaque app gere ses fichiers locaux sous SON var/ (D33) -- MAIS JAMAIS a cote du
# programme quand celui-ci vit dans Program Files (D97).
#
# C'est ici que Vigie ne demarrait pas sur un compte standard. Le chemin etait calcule a
# la main : « $PSScriptRoot/var/log ». Sur le compte administrateur, la tache tourne
# elevee, le dossier se cree dans Program Files et tout marche. Sur « Famille », niveau
# Limited, Windows refuse l'ecriture : New-Item leve, $ErrorActionPreference vaut 'Stop',
# et le script meurt AVANT que TLog n'existe. Code de retour 1, aucun journal nulle part,
# aucune trace -- exactement ce qui a ete constate le 28/08.
#
# Get-VarPath applique la regle une fois pour toutes : sur place quand c'est possible,
# dans le profil du compte sinon. On la charge donc AVANT d'ecrire quoi que ce soit.
$appsRootTmp = Split-Path $PSScriptRoot -Parent
. (Join-Path (Join-Path $appsRootTmp 'backend-pode') 'lib/common.ps1')
$trayLog = Get-VarPath -Backend $PSScriptRoot -Kind 'log' -File ('tray_' + (Get-Date -Format 'yyyyMMdd') + '.log')
function TLog($m) { try { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Out-File -FilePath $trayLog -Append -Encoding UTF8 } catch { } }
TLog "demarrage (PS $($PSVersionTable.PSVersion), $([System.Threading.Thread]::CurrentThread.GetApartmentState()))"

# UN VERROU PAR COMPTE, pas par session de bureau. Sans nom d'espace explicite, un
# mutex vit dans « Local\ », c'est-a-dire dans la session Windows -- et deux comptes
# peuvent partager une session : c'est le cas quand on lance le tray d'un autre compte
# avec runas, exactement ce qu'on fait pour deboguer. Le tray de Famille a demarre,
# vu le verrou de fhaza, et s'est retire (28/08 22:09). Le verrou porte donc desormais
# le nom du compte : chacun le sien, quelle que soit la session qui l'heberge.
<#
    C'EST LE SUCCESSEUR QUI ATTEND, PAS CELUI QUI DEMANDE.

    Quatre secondes ne suffisaient pas : lors d'une relance, l'ancienne instance ferme son
    icone, rend la main a Windows et libere son verrou -- ce qui prend parfois davantage.
    La nouvelle sortait alors sur « deja lance », le numero de processus ne changeait
    jamais, et l'installation comptait deux echecs sur une app cliente qui tournait
    (constate le 30/08).

    On attend donc ICI, dans le processus qui demarre : personne en amont n'est bloque,
    et le cas normal -- aucun predecesseur -- passe sans delai. Vingt secondes couvrent
    largement une fermeture d'icone ; au-dela, c'est qu'une instance tourne vraiment.
#>
$mutex = New-Object System.Threading.Mutex($false, ('VigieTray-' + (Get-ProcessAccount)))
if (-not $mutex.WaitOne(20000)) { TLog "deja lance (mutex) - sortie"; return }

$uiScript = {
    param($backend, $trayLog, $repoUrl, $trayRoot)
    $ErrorActionPreference = 'Continue'
    function TLog($m) { try { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Out-File -FilePath $trayLog -Append -Encoding UTF8 } catch { } }
    try {
        . (Join-Path $backend 'lib/common.ps1')
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        Add-Type -Namespace VigieNative -Name Ico -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr handle);'

        # S5 -- CHANGEMENT D'ADRESSE RESEAU, tout de suite.
        #
        # Sans cela, debrancher le cable ou changer de Wi-Fi laissait la carte Reseau
        # afficher l'ancienne adresse jusqu'a la peremption de sa sonde. Windows sait
        # dire l'instant du changement : on s'y abonne.
        #
        # L'abonnement est fait EN C#, pas par un bloc PowerShell : Windows previent sur
        # un fil du pool, ou executer du PowerShell demande un espace d'execution qui
        # n'est pas forcement disponible. Le gestionnaire natif ne fait qu'une chose,
        # poser un drapeau ; c'est la boucle d'interface (chaque seconde) qui agit.
        Add-Type -Namespace VigieNative -Name Net -MemberDefinition @'
public static volatile bool Changed = false;
public static void Watch() {
    System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged += delegate { Changed = true; };
    System.Net.NetworkInformation.NetworkChange.NetworkAvailabilityChanged += delegate { Changed = true; };
}
'@

        # Retrouver une fenetre par son titre, et la ramener au premier plan.
        # Sans cela, chaque double-clic ouvrait une fenetre de PLUS : l'application se
        # retrouvait en deux exemplaires dans la barre des taches.
        Add-Type -Namespace VigieNative -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.IntPtr lParam);
public delegate bool EnumWindowsProc(System.IntPtr hWnd, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsIconic(System.IntPtr hWnd);

// Titre EXACT attendu : le front pose « <machine> - Vigie » (document.title).
public static System.IntPtr FindBySuffix(string suffix) {
    System.IntPtr found = System.IntPtr.Zero;
    EnumWindows(delegate(System.IntPtr h, System.IntPtr p) {
        if (!IsWindowVisible(h)) return true;
        System.Text.StringBuilder sb = new System.Text.StringBuilder(512);
        if (GetWindowText(h, sb, sb.Capacity) == 0) return true;
        if (sb.ToString().EndsWith(suffix, System.StringComparison.Ordinal)) { found = h; return false; }
        return true;
    }, System.IntPtr.Zero);
    return found;
}

// SW_RESTORE = 9 : deminiaturise si besoin, puis met au premier plan.
public static bool Focus(System.IntPtr h) {
    if (h == System.IntPtr.Zero) return false;
    if (IsIconic(h)) ShowWindow(h, 9);
    return SetForegroundWindow(h);
}
'@

        $cfg       = Get-Config -Backend $backend
        $url       = Get-AppUrl -Config $cfg
        $healthUrl = (Get-ApiUrl -Config $cfg) + '/health'
        $pwsh      = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        $trayPath  = Join-Path $trayRoot 'tray.ps1'      # cette app, pas le backend
        # Starting : un demarrage a ete demande et le serveur n'a pas encore repondu.
        $state     = [hashtable]::Synchronized(@{ Proc = $null; Drawn = ''; EverUp = $false; Starting = $true; StartTicks = [datetime]::UtcNow.Ticks; Mods = @{}; ModsInit = $false; HealthKo = 0; MachineTask = $null; ElevationAsked = $false; SaidDead = $false })
        # Cache d'etat du backend : lu (jamais ecrit) par le guetteur de modules (D54).
        $stateCacheFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'state-cache.json'
        <#
            COMBIEN DE TEMPS AVANT DE DECLARER UN ECHEC DE DEMARRAGE ?

            25 secondes, jusqu'au 28/08. Or le serveur met environ SOIXANTE-CINQ secondes
            a repondre : le journal du tray montre la meme sequence a chaque lancement --
            orange pendant 22 s, puis ROUGE, puis vert une quarantaine de secondes plus
            tard. L'utilisateur voyait donc une panne a chaque demarrage, alors que tout
            se passait bien. Un signal qui crie a tort finit ignore, et le jour ou le
            serveur echoue vraiment, plus personne ne le regarde.

            ON NE DEVINE PLUS, ON REGARDE LE PROCESSUS. Tant que celui qu'on a lance est
            VIVANT, le demarrage est en cours : c'est une preuve, pas une estimation.
            S'il a disparu, c'est un echec -- et on le dit tout de suite, sans attendre
            la fin d'un delai. Le plafond ne sert plus que de garde-fou contre un serveur
            qui resterait vivant sans jamais repondre.

            Le cas du tray qui ADOPTE un serveur deja en place ($state.Proc vide) garde
            un delai, faute de processus a observer : large, parce qu'on ne sait rien.
        #>
        $startupGrace   = 120   # plafond quand on observe le processus qu'on a lance
        $startupBlind   = 90    # delai quand on n'a aucun processus a observer

        # --- Auto-reparation de la tache de demarrage -------------------------------
        # Le tray tourne ELEVE : il est le seul a pouvoir corriger sa propre tache
        # planifiee sans redemander une elevation a l'utilisateur. La tache echouait par
        # intermittence au logon (0xC0070154 : pwsh vient du Store et son paquet MSIX
        # n'est pas toujours pret a la seconde ou la session s'ouvre). Idempotent :
        # ne touche que le delai et les reprises, et seulement s'ils manquent.
        try {
            $tache = Get-ScheduledTask -TaskName 'Vigie' -ErrorAction Stop
            $aCorriger = $false
            if (-not $tache.Triggers[0].Delay) { $tache.Triggers[0].Delay = 'PT45S'; $aCorriger = $true }
            if (-not $tache.Settings.RestartCount) {
                $tache.Settings.RestartCount = 3
                $tache.Settings.RestartInterval = 'PT1M'
                $aCorriger = $true
            }
            if ($aCorriger) {
                Set-ScheduledTask -InputObject $tache | Out-Null
                TLog "tache planifiee reparee : delai PT45S + 3 reprises (echec MSIX au logon)"
            }
        } catch { TLog ("tache planifiee non reparable ici : " + $_.Exception.Message) }
        $iconHandle = [System.IntPtr]::Zero

        # --- Pilotage par ordres deposes dans var/run ----------------------------------
        # Le tray tourne ELEVE : depuis une session normale, on ne peut ni lire sa ligne
        # de commande ni signaler un objet noyau qu'il a cree. Un dossier d'ordres evite
        # ces deux obstacles, reste inspectable a l'oeil, scriptable depuis n'importe quoi,
        # et accepte de nouveaux ordres sans toucher au mecanisme.
        # Voir scripts/tray.ps1 pour le cote emetteur.
        $runDir    = Get-VarPath -Backend $trayRoot -Kind 'run'
        $heartbeat = Join-Path $runDir 'tray.alive'
        # Un arret brutal laisse des ordres non consommes : ils ne doivent pas s'appliquer
        # au demarrage suivant.
        #
        # SAUF les accuses de reception : celui que le tray precedent vient de poser est
        # justement ce que l'emetteur attend, et nous demarrons dans la seconde qui suit.
        # Les effacer d'entree, c'etait courir avec lui -- et lui faire conclure « ordre
        # non lu » sur une relance qui marchait. Un accuse perime ne gene personne :
        # l'emetteur efface le sien AVANT d'envoyer son ordre.
        Get-ChildItem -LiteralPath $runDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ne '.ack' } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $launchHidden = {
            param($file, $argv)
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $file; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            foreach ($x in $argv) { [void]$psi.ArgumentList.Add([string]$x) }
            return [System.Diagnostics.Process]::Start($psi)
        }
        <#
            LA TACHE SERVEUR TIENT-ELLE DEJA LA MACHINE ?

            C'est LA question de la migration. Tant qu'il y a un serveur par session, le
            tray de chaque compte lance le sien -- c'est le fonctionnement historique. Des
            que la tache « Vigie - Serveur » est active, un serveur unique repond a toute
            la machine : si les trays continuaient a en lancer, ils se disputeraient le
            port 47600, et le perdant mourrait sans que personne ne sache lequel repond.

            LA REPONSE EST MISE EN CACHE. L'etat d'une tache planifiee ne change pas en
            cours de session, et l'interroger toutes les huit secondes coute pour rien.

            SI ON NE PEUT PAS LIRE LA TACHE, on repond « non ». Un compte a qui Windows
            refuse la lecture ne doit pas se retrouver sans serveur du tout : on garde le
            comportement historique, qui marche.
        #>
        $machineServerActive = {
            if ($null -ne $state.MachineTask) { return $state.MachineTask }
            $actif = $false
            try {
                $t = Get-ScheduledTask -TaskName 'Vigie - Serveur' -ErrorAction Stop
                $actif = ("$($t.State)" -ne 'Disabled')
            } catch { $actif = $false }
            $state.MachineTask = $actif
            if ($actif) { TLog "tache serveur active : le tray ne lancera pas de serveur" }
            return $actif
        }

        <#
            DEMANDER AU SERVEUR DE SE RELANCER LUI-MEME.

            Il est deja eleve : il lance son successeur avec SES droits, et personne n'a
            rien a autoriser -- pas meme un compte standard. C'est la voie normale.

            Rend : 'ok' s'il a accepte, 'busy:<operation>' s'il refuse parce qu'une
            operation tourne, 'ko' s'il ne repond pas -- et c'est seulement dans ce
            dernier cas qu'on parlera d'elevation, puisqu'il n'y a plus personne pour
            se relancer.
        #>
        # LA FENETRE DE QUESTION, une seule fois pour tout le tray. Rend 0 (bouton
        # principal), 4 (troisieme issue) ou 3 (refus).
        $askWindow = {
            param($titre, $texte, $okText, $tiersText, $nonText)
            try {
                $script = Join-Path (Split-Path (Split-Path $backend -Parent) -Parent) 'scripts/lib/show-confirm.ps1'
                if (-not (Test-Path -LiteralPath $script)) { return 3 }
                $payload = Join-Path ([IO.Path]::GetTempPath()) ('vigie-tray-' + [guid]::NewGuid().ToString('N') + '.json')
                # Le texte passe par un FICHIER : en argument, ses accents seraient abimes
                # par la page de code du processus appele.
                [IO.File]::WriteAllText($payload,
                    (@{ title = "$titre"; summary = "$texte" } | ConvertTo-Json -Compress),
                    (New-Object Text.UTF8Encoding($false)))
                $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script,
                          '-Caption', 'Vigie', '-PayloadFile', $payload,
                          '-OkText', $okText, '-CancelText', $nonText, '-Note', '')
                if ($tiersText) { $argv += @('-ThirdText', $tiersText) }
                & $pwsh @argv | Out-Null
                $code = $LASTEXITCODE
                try { Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue } catch { }
                return $code
            } catch { TLog ("fenetre KO : " + $_.Exception.Message); return 3 }
        }

        $askServerRestart = {
            param([bool]$Force, [bool]$Wait)
            try {
                $token = Get-ApiToken -Backend $backend
                $body  = if ($Force)   { '{"type":"server-restart","params":{"force":true}}' }
                         elseif ($Wait) { '{"type":"server-restart","params":{"wait":true}}' }
                         else           { '{"type":"server-restart"}' }
                $rep = Invoke-RestMethod -Method Post -Uri ($url.TrimEnd('/') + '/api/v1/actions') `
                            -ContentType 'application/json' -Body $body -TimeoutSec 6 `
                            -Headers @{ Authorization = ('Bearer ' + $token); Origin = $url.TrimEnd('/') }
                if ($rep.result -and $rep.result.busy) { return ('busy:' + $rep.result.operation) }
                if ($rep.result -and $rep.result.ok)   { return 'ok' }
                return 'ko'
            } catch { return 'ko' }
        }

        $startServer = {
            if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) { return }
            # LA MACHINE S'EN CHARGE : on n'a rien a lancer, et surtout rien a disputer.
            if (& $machineServerActive) { return }

            <#
                SANS LES DROITS, ON LES DEMANDE -- MAIS UNE SEULE FOIS.

                start.ps1 exige l'elevation et se relance avec « RunAs » : sur un compte
                standard, Windows ouvre une fenetre UAC qui reclame les identifiants d'un
                administrateur. C'est le comportement voulu -- quelqu'un peut passer les
                saisir -- et le tray doit garder cette capacite.

                Ce qui n'allait pas, c'est la REPETITION : le sondage revient toutes les
                huit secondes, donc la fenetre revenait toutes les huit secondes. Une
                demande refusee ne se represente pas d'elle-meme ; elle se represente
                quand on la demande, par « Redemarrer le serveur » dans le menu.
            #>
            if (-not (Test-IsElevated)) {
                if ($state.ElevationAsked) { return }
                $state.ElevationAsked = $true
                TLog "serveur arrete : demande d'elevation (une fois)"
            }
            # Un demarrage VOULU rouvre la fenetre de tolerance : pendant $startupGrace
            # secondes, "injoignable" veut dire "demarre" (orange) et non "en panne" (rouge).
            $state.StartTicks = [datetime]::UtcNow.Ticks
            $state.Starting   = $true
            if ($pwsh) { $state.Proc = & $launchHidden $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $backend 'start.ps1')) }
        }
        # ARRETER LE SERVEUR, meme quand ce n'est pas NOTRE enfant.
        #
        # Un tray relance ADOPTE le serveur deja en place : $state.Proc est alors vide, et
        # l'ancien $stopServer ne tuait rien. Consequence mesuree le 26/08 : « Relancer
        # l'application » (et donc le redemarrage d'apres deploiement) laissait tourner
        # l'ANCIEN serveur -- le nouveau tray constatait « serveur ok » et repartait sur
        # du code perime. Repli : le processus qui ECOUTE le port, et seulement s'il s'agit
        # d'un interpreteur PowerShell -- on ne tue que ce qu'on aurait pu lancer.
        # ARRETER LE SERVEUR EST UN GESTE RARE ET DEMANDE. Cette fonction n'est plus
        # appelee que sur decision explicite de quelqu'un, quand le serveur ne repond
        # plus. Ni « Quitter », ni « Relancer l'application », ni la detection d'un
        # serveur coince n'y touchent : ils arrivent apres lui, et il sert tout le monde.
        $stopServer = {
            try { if ($state.Proc -and -not $state.Proc.HasExited) { $state.Proc.Kill(); return } } catch { }
            try {
                $c = Get-NetTCPConnection -LocalPort $cfg.Port -State Listen -ErrorAction Stop | Select-Object -First 1
                if ($c -and $c.OwningProcess) {
                    $p = Get-Process -Id ([int]$c.OwningProcess) -ErrorAction Stop
                    if (@('pwsh','powershell') -contains $p.ProcessName) {
                        TLog ("arret du serveur adopte (PID " + $p.Id + ")")
                        $p.Kill()
                    }
                }
            } catch { }
        }

        # Sortie PROPRE, seul chemin de fin de vie. Libere l'icone : un processus tue
        # laisse son icone en fantome dans la zone de notification, qui ne repond plus
        # a rien et affiche indefiniment le dernier etat connu.
        <#
            QUITTER LE TRAY QUITTE LE TRAY -- PAS LE SERVEUR.

            « Quitter » arretait le serveur. C'etait defendable quand chaque session avait
            le sien ; avec un serveur commun a la machine, quitter depuis un compte le
            coupe pour TOUS LES AUTRES. Constate le 29/08 : sortie du tray de Famille,
            serveur tue, tray de fhaza qui le relance, et une demande d'elevation au
            passage -- pour quelqu'un qui voulait juste fermer une icone.

            Le serveur est un service : il vit sa vie. Pour l'arreter ou le relancer, il y
            a « Redemarrer le serveur », qui le dit.
        #>
        $quitApp = {
            param($origine)
            TLog ("arret du tray (" + $origine + ") -- le serveur reste en marche")
            try { $icon.Visible = $false; $icon.Dispose() } catch { }
            try { Remove-Item -LiteralPath $heartbeat -Force -ErrorAction SilentlyContinue } catch { }
            [System.Windows.Forms.Application]::Exit()
        }
        <#
            RELANCER L'APPLICATION RELANCE L'APPLICATION.

            Cette fonction tuait aussi le serveur, « pour qu'il reparte avec le nouveau
            code ». Mais le serveur PRECEDE le tray : avec la tache de machine, il demarre
            avant meme qu'une session soit ouverte. Un programme lance apres ne ferme pas
            celui qui l'attendait -- et le couper depuis un compte le coupe pour tous les
            autres.

            Le serveur se relance LUI-MEME, avec ses droits, par « Redemarrer le
            serveur ». Deux gestes distincts pour deux choses distinctes.
        #>
        $relaunch = {
            try { [void](& $launchHidden $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File', $trayPath)) } catch { }
            try { $icon.Visible = $false; $icon.Dispose() } catch { }
            [System.Windows.Forms.Application]::Exit()
        }
        # Chemin de l'executable du navigateur PAR DEFAUT, lu dans l'association http de
        # l'utilisateur. C'est le seul navigateur dont on sait qu'il fonctionne sur cette
        # machine -- il est donc essaye en premier.
        $defaultBrowser = {
            try {
                $key = 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
                $progId = (Get-ItemProperty -Path $key -ErrorAction Stop).ProgId
                if (-not $progId) { return $null }
                $cmd = (Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command" -ErrorAction Stop).'(default)'
                if ($cmd -match '"([^"]+\.exe)"') { return $Matches[1] }
                if ($cmd -match '^\s*(\S+\.exe)')  { return $Matches[1] }
            } catch { }
            return $null
        }

        # Ouvre la fenetre dediee (navigateur en mode --app).
        #
        # POURQUOI ON VERIFIE AU LIEU DE FAIRE CONFIANCE A Start-Process
        # L'ancienne version prenait le PREMIER navigateur trouve sur disque, dans l'ordre
        # Edge puis Chrome. Sur cette machine, Edge est present mais NE DEMARRE PAS : le
        # processus sort en moins d'une seconde, sans fenetre et sans erreur. Start-Process
        # rendait donc la main sans lever d'exception et le journal ecrivait « openApp ok »
        # -- un mensonge, quatre signalements durant. Un double-clic ne faisait rien.
        #
        # Deux corrections : on essaie d'abord le navigateur PAR DEFAUT (celui qui marche,
        # par definition, puisque « Ouvrir dans le navigateur » fonctionnait), et surtout
        # on CONSTATE le resultat avant de le declarer. Un candidat qui meurt fait passer
        # au suivant ; si aucun ne tient, on ouvre un onglet normal plutot que rien.
        $openApp = {
            TLog "openApp demande"

            # DEJA OUVERTE ? On la ramene au premier plan au lieu d'en ouvrir une seconde.
            # Le suffixe est celui que pose le front (document.title = "<machine> - Vigie").
            $existante = [VigieNative.Win]::FindBySuffix(' — Vigie')
            if ($existante -ne [System.IntPtr]::Zero) {
                if ([VigieNative.Win]::Focus($existante)) {
                    TLog "openApp : fenetre deja ouverte, ramenee au premier plan"
                    return
                }
                TLog "openApp : fenetre trouvee mais impossible a activer - on en ouvre une"
            }

            # Le mode --app n'existe que sur les navigateurs Chromium.
            $chromium = @('chrome', 'msedge', 'brave', 'vivaldi', 'opera')
            $candidats = New-Object System.Collections.Generic.List[string]
            $parDefaut = & $defaultBrowser
            if ($parDefaut -and (Test-Path -LiteralPath $parDefaut) -and
                ($chromium -contains [IO.Path]::GetFileNameWithoutExtension($parDefaut).ToLower())) {
                $candidats.Add($parDefaut)
            }
            $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ }
            $rel   = @('Google\Chrome\Application\chrome.exe','Microsoft\Edge\Application\msedge.exe')
            foreach ($base in $bases) {
                foreach ($rp in $rel) {
                    $c = Join-Path $base $rp
                    if ((Test-Path -LiteralPath $c) -and -not $candidats.Contains($c)) { $candidats.Add($c) }
                }
            }

            foreach ($exe in $candidats) {
                $nom = [IO.Path]::GetFileNameWithoutExtension($exe)
                $avant = @(Get-Process -Name $nom -ErrorAction SilentlyContinue).Count
                try {
                    $p = Start-Process -FilePath $exe -ArgumentList "--app=$url","--window-size=1240,840" -PassThru
                } catch {
                    TLog ("openApp : " + $exe + " refuse (" + $_.Exception.Message + ")")
                    continue
                }
                Start-Sleep -Milliseconds 1500
                # Deux facons de reussir : notre processus tient, OU il a delegue a une
                # instance deja lancee -- dans ce cas il sort vite mais le navigateur a
                # gagne des processus. Ne tester que HasExited ouvrirait deux fenetres.
                $apres = @(Get-Process -Name $nom -ErrorAction SilentlyContinue).Count
                if ((-not $p.HasExited) -or ($apres -gt $avant)) {
                    TLog ("openApp OK (fenetre dediee) : " + $exe)
                    return
                }
                TLog ("openApp : " + $exe + " sort aussitot sans fenetre - candidat suivant")
            }

            TLog "openApp : aucun navigateur Chromium exploitable - repli onglet normal"
            try { Start-Process $url; TLog "openApp OK (onglet normal)" }
            catch { TLog ("openApp ECHEC : " + $_.Exception.Message) }
        }
        $openUrl     = { param($u) try { Start-Process $u } catch { TLog ("ouverture KO (" + $u + ") : " + $_.Exception.Message) } }

        <#
            OUVRIR LE PANNEAU EN DISANT QUI ON EST.

            Le tray est le seul programme a pouvoir lire le secret de SON compte. Il le
            presente au serveur, recoit un ticket a usage unique, et ouvre la page avec ce
            ticket. Le serveur l'echange contre un cookie de session : la page sait alors
            de quel compte elle vient, sans qu'aucun secret n'ait transite par l'URL ni ne
            reste lisible dans le JavaScript.

            SI QUOI QUE CE SOIT ECHOUE, ON OUVRE QUAND MEME la page sans ticket. Vigie
            reste utilisable comme avant ; c'est l'identification du compte qui manque, pas
            l'application. Refuser d'ouvrir le panneau parce que l'identification a echoue
            serait une regression pour un gain nul.
        #>
        $openBrowser = {
            # UN SEUL CHEMIN pour demander une adresse d'ouverture : Get-OpenUrl. Le geste
            # etait ecrit ici ET dans l'outil de questions, avec deja deux delais
            # d'attente differents.
            $target = $null
            try { $target = Get-OpenUrl -BaseUrl $url -TimeoutSec 5 -Backend $backend } catch { }
            if ($target) { TLog "adresse d'ouverture obtenue" } else { TLog "ouverture sans identification" ; $target = $url }
            & $openUrl $target
        }
        $openRepo    = { & $openUrl $repoUrl }

        # LE COMPTE EST DANS L'INFOBULLE. Il y a une icone par compte ouvert, et elles
        # disaient toutes « Vigie - <etat> » : impossible de savoir laquelle appartient a
        # qui. Sur une machine familiale, c'est la premiere question qu'on se pose, et
        # c'est indispensable pour deboguer un compte depuis la session d'un autre.
        $trayAccount = (Get-ProcessAccount)
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Text = (Get-Label 'tray.infobulle' $trayAccount)

        $setIcon = {
            param($status)
            # L'icone est TOUJOURS le fichier .ico livre (assets/), genere par
            # assets/generate-icons.py. C'est la SEULE representation de la marque.
            $name = switch ($status) { 'ok' { 'ok' } 'warn' { 'warn' } 'error' { 'error' } default { 'error' } }
            $icoPath = Join-Path $trayRoot ('assets\' + $name + '.ico')
            if (Test-Path $icoPath) {
                try {
                    $newIco = New-Object System.Drawing.Icon($icoPath)
                    $icon.Icon = $newIco
                    if ($script:iconObj) { try { $script:iconObj.Dispose() } catch { } }
                    $script:iconObj = $newIco
                    return
                } catch {
                    # Jamais silencieux : une icone qui change sans raison est
                    # indiagnosticable si l'echec n'est pas trace.
                    TLog ("icone : lecture KO (" + $icoPath + ") : " + $_.Exception.Message)
                }
            } else {
                TLog ("icone : fichier absent : " + $icoPath)
            }

            # --- Mode degrade -------------------------------------------------------
            # Volontairement un simple DISQUE, pas une imitation de la marque.
            # L'ancien repli redessinait la jauge en GDI+ : deux dessins de la meme
            # marque, qui avaient FINI PAR DIVERGER (aiguille partant du centre, aucune
            # graduation, epaisseurs et couleur de piste differentes). Comme l'echec de
            # lecture etait avale, le tray pouvait afficher une AUTRE marque sans que
            # personne ne le voie. Un disque uni ne trompe personne : il signale que
            # les assets manquent, tout en gardant l'information de statut (la couleur).
            $c = switch ($status) {
                'ok'    { [System.Drawing.Color]::FromArgb(63,185,80) }
                'warn'  { [System.Drawing.Color]::FromArgb(210,153,34) }
                'error' { [System.Drawing.Color]::FromArgb(248,81,73) }
                default { [System.Drawing.Color]::FromArgb(248,81,73) }
            }
            $s = 32.0
            $bmp = New-Object System.Drawing.Bitmap ([int]$s), ([int]$s)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            $pad = $s * 0.12
            $brush = New-Object System.Drawing.SolidBrush $c
            $g.FillEllipse($brush, [single]$pad, [single]$pad, [single]($s - 2*$pad), [single]($s - 2*$pad))
            $brush.Dispose()
            $g.Dispose()
            $h = $bmp.GetHicon(); $bmp.Dispose()
            $icon.Icon = [System.Drawing.Icon]::FromHandle($h)
            if ($iconHandle -ne [System.IntPtr]::Zero) { [void][VigieNative.Ico]::DestroyIcon($iconHandle) }
            $script:iconHandle = $h
        }
        & $setIcon 'warn'
        $icon.Visible = $true
        TLog "icone visible"

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $menu.ShowImageMargin = $false
        try { $menu.Font = New-Object System.Drawing.Font('Segoe UI', 9.5) } catch { }
        # --- Style Win11 : coins arrondis natifs (DWM), survol encarte arrondi ---
        # Tout echec retombe silencieusement sur le rendu par defaut : le menu reste
        # utilisable meme si le style ne s'applique pas.
        try {
            $csrc = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

// Palette du menu. Une seule definition des couleurs, partagee par la table et le rendu.
// La reference demandee est le menu de WINDOWS 11 : gris NEUTRE, pas le bleute de la
// palette Vigie. Le bleu #2b3038 livre jusqu'ici venait de mes valeurs par defaut, qui
// avaient pris le pas sur la reference.
public static class VigieMenuPalette {
  public static readonly Color Surface   = Color.FromArgb(44, 44, 44);   // #2c2c2c
  public static readonly Color Hover     = Color.FromArgb(61, 61, 61);   // #3d3d3d
  public static readonly Color Border    = Color.FromArgb(69, 69, 69);   // #454545
  public static readonly Color Separator = Color.FromArgb(64, 64, 64);   // #404040
  // Survol PLEINE LARGEUR : bande edge-to-edge, sans marge ni arrondi. C'est le rendu
  // demande. Les valeurs restent nommees pour qu'un survol encarte redevienne un simple
  // changement de constantes, sans toucher au trace.
  public const int CornerRadius = 0;   // arrondi du RECTANGLE DE SURVOL
  public const int MenuRadius   = 8;   // arrondi des COINS DU MENU (decoupe de region)
  public const int InsetX       = 0;   // marge laterale du rectangle de survol
  public const int InsetY       = 0;
  // Retrait du TEXTE dans l'item. Doit etre superieur a InsetX, sinon le texte touche
  // le bord du rectangle de survol. Win11 laisse respirer autour du libelle.
  public const int TextPadX     = 14;
  public const int TextPadY     = 7;   // ne sert QUE a fixer la hauteur de ligne
  // Libelles non cliquables (ligne d'etat) : gris attenue, lisible sur fond sombre.
  public static readonly Color TextDisabled = Color.FromArgb(154, 160, 166);
  // Couleur du LIBELLE actif. Definie ICI et nulle part ailleurs (D15) : elle etait
  // ecrite en dur a deux endroits du script, ce qui obligeait a la recopier dans
  // l Atelier -- qui la relit desormais (palette.php).
  public static readonly Color Text = Color.FromArgb(230, 237, 243);
}

public class VigieDarkColors : ProfessionalColorTable {
  public override Color ToolStripDropDownBackground { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientBegin    { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientMiddle   { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientEnd      { get { return VigieMenuPalette.Surface; } }
  public override Color MenuBorder                  { get { return VigieMenuPalette.Border; } }
  public override Color MenuItemBorder              { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelected            { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelectedGradientBegin { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelectedGradientEnd   { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemPressedGradientBegin  { get { return VigieMenuPalette.Surface; } }
  public override Color MenuItemPressedGradientEnd    { get { return VigieMenuPalette.Surface; } }
  public override Color SeparatorDark               { get { return VigieMenuPalette.Separator; } }
  public override Color SeparatorLight              { get { return VigieMenuPalette.Separator; } }
}

public class VigieMenuRenderer : ToolStripProfessionalRenderer {
  public VigieMenuRenderer() : base(new VigieDarkColors()) { this.RoundedEdges = false; }

  static GraphicsPath RoundedRect(Rectangle r, int radius) {
    int d = radius * 2;
    GraphicsPath p = new GraphicsPath();
    if (d <= 0 || r.Width <= d || r.Height <= d) { p.AddRectangle(r); return p; }
    p.AddArc(r.X, r.Y, d, d, 180, 90);
    p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
    p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
    p.CloseFigure();
    return p;
  }

  // Survol : rectangle ENCARTE et arrondi (Win11), et non une bande pleine largeur.
  protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
    if (!e.Item.Selected || !e.Item.Enabled) return;

    // L'item peut etre plus LARGE que la zone visible du menu : ses derniers pixels
    // passent sous la bordure. Un rectangle calcule sur e.Item.Size sortait donc a
    // droite et s'y faisait rogner a angle droit -- arrondi a gauche, coupe net a
    // droite. On borne la largeur a ce qui est reellement visible.
    int visible = e.ToolStrip.ClientSize.Width - e.Item.Bounds.Left;
    int largeur = Math.Min(e.Item.Size.Width, visible);

    Rectangle r = new Rectangle(
      VigieMenuPalette.InsetX,
      VigieMenuPalette.InsetY,
      largeur - VigieMenuPalette.InsetX * 2,
      e.Item.Size.Height - VigieMenuPalette.InsetY * 2);
    if (r.Width <= 0 || r.Height <= 0) return;
    SmoothingMode old = e.Graphics.SmoothingMode;
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    using (GraphicsPath path = RoundedRect(r, VigieMenuPalette.CornerRadius))
    using (SolidBrush brush = new SolidBrush(VigieMenuPalette.Hover))
      e.Graphics.FillPath(brush, path);
    e.Graphics.SmoothingMode = old;
  }

  // Placement du TEXTE, explicite.
  //
  // Le moteur de disposition des menus deroulants calcule lui-meme la boite des items :
  // regler Padding y produit un ContentRectangle incoherent (mesure : {X=-12, Y=-5,
  // Height=44} pour un item de 34 px). S'appuyer dessus revenait a se battre contre le
  // moteur -- le texte n'etait jamais centre verticalement, quatre tentatives durant.
  //
  // On ne subit plus la mise en page : on donne le rectangle de texte et on demande un
  // centrage vertical. Meme resultat pour TOUS les types d'items, y compris ceux que le
  // moteur decale (un ToolStripLabel est pose 8 px plus a droite qu'un ToolStripMenuItem).
  protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
    Size s = e.Item.Size;
    e.TextRectangle = new Rectangle(
        VigieMenuPalette.TextPadX, 0,
        Math.Max(0, s.Width - VigieMenuPalette.TextPadX * 2), s.Height);
    e.TextFormat = TextFormatFlags.Left | TextFormatFlags.VerticalCenter
                 | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix;
    // Un item desactive sert de libelle (ligne d'etat) : le gris systeme serait
    // illisible sur fond sombre.
    if (!e.Item.Enabled) e.TextColor = VigieMenuPalette.TextDisabled;
    base.OnRenderItemText(e);
  }

  // Separateur : trait fin encarte, aligne sur les marges du survol.
  protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
    Rectangle b = new Rectangle(Point.Empty, e.Item.Size);
    int y = b.Top + b.Height / 2;
    // Le separateur s'aligne sur le TEXTE, pas sur le survol : avec un survol pleine
    // largeur, un trait pleine largeur decouperait le menu en tranches.
    using (Pen pen = new Pen(VigieMenuPalette.Separator))
      e.Graphics.DrawLine(pen, b.Left + VigieMenuPalette.TextPadX, y, b.Right - VigieMenuPalette.TextPadX, y);
  }

  // Fond uni : pas de degrade, pas de bande de marge d'icone.
  protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
    using (SolidBrush brush = new SolidBrush(VigieMenuPalette.Surface))
      e.Graphics.FillRectangle(brush, e.AffectedBounds);
  }

  // Bordure geree par DWM (coins arrondis natifs) : ne rien dessiner ici.
  protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) { }
}
'@
            # System.Drawing est scinde : Color vient de System.Drawing.Primitives,
            # GraphicsPath/Graphics de System.Drawing.Common. Il faut les DEUX.
            $refs = @(
                [System.Windows.Forms.ToolStrip].Assembly.Location,
                [System.Drawing.Color].Assembly.Location,
                [System.Drawing.Drawing2D.GraphicsPath].Assembly.Location
            ) | Sort-Object -Unique
            Add-Type -TypeDefinition $csrc -ReferencedAssemblies $refs -ErrorAction Stop
            $menu.Renderer  = New-Object VigieMenuRenderer
            $menu.BackColor = [VigieMenuPalette]::Surface
            $menu.ForeColor = [VigieMenuPalette]::Text
            $menu.Padding   = New-Object System.Windows.Forms.Padding(0, 5, 0, 5)
            TLog "style menu Win11 applique"
        } catch { TLog ("style menu KO (fallback): " + $_.Exception.Message) }

        # Coins arrondis NATIFS via DWM (Windows 11). Applique a chaque ouverture :
        # idempotent, et la fenetre du menu peut recreer son handle entre deux affichages.
        # Set-WindowChrome vient de lib/common.ps1 : la signature P/Invoke n'est
        # declaree qu'a un seul endroit, partage avec la fenetre de consentement.
        # DWM d'abord (ombre et anticrenelage natifs quand il veut bien s'appliquer),
        # puis decoupe de region qui, elle, arrondit TOUJOURS : sans elle le menu reste
        # a coins carres, DWM n'arrondissant pas les fenetres sans cadre standard.
        $roundCorners = {
            try {
                Set-WindowChrome  -Handle $menu.Handle -RoundedCorners -BorderColor 0x00564C44
                Set-RoundedRegion -Control $menu -Radius ([VigieMenuPalette]::MenuRadius)
                # Trace du RESULTAT, pas de l'intention : "region appliquee" ne prouve rien,
                # seul le fait qu'un coin soit hors region prouve que l'arrondi a pris.
                $horsCoin = if ($menu.Region) {
                    -not $menu.Region.IsVisible((New-Object System.Drawing.Point(0,0)))
                } else { $false }
                TLog ("menu ouvert : {0}x{1}, region={2}, coin decoupe={3}" -f `
                      $menu.Width, $menu.Height, [bool]$menu.Region, $horsCoin)
            } catch {
                TLog ("arrondi du menu KO : " + $_.Exception.Message)
            }
        }
        $menu.add_Opened({ & $roundCorners })

        $lite = [VigieMenuPalette]::Text
        $miShow = $menu.Items.Add('Afficher l''application', $null, [System.EventHandler]{ & $openApp })
        try { $miShow.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold) } catch { }
        [void]$menu.Items.Add('Ouvrir dans le navigateur', $null, [System.EventHandler]{ & $openBrowser })
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        # Ligne d'etat : un ToolStripMenuItem DESACTIVE, pas un ToolStripLabel. Le moteur
        # de disposition pose un Label 8 px plus a droite qu'un item, d'ou un decalage
        # visible. Meme type d'item = meme geometrie, sans correction a maintenir.
        # Sa couleur attenuee est appliquee par le renderer (TextDisabled), le gris
        # systeme etant illisible sur fond sombre.
        $miInfo = New-Object System.Windows.Forms.ToolStripMenuItem('État : démarrage…')
        $miInfo.Enabled = $false
        [void]$menu.Items.Add($miInfo)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add('Relancer l''application', $null, [System.EventHandler]$relaunch)
        <#
            TROIS ISSUES QUAND UNE OPERATION TOURNE.

            Couper un deploiement en deux laisse une installation a moitie faite. On ne
            decide pas a la place de la personne : on lui dit ce qui tourne, et on lui
            laisse le choix -- ne rien faire, attendre la fin, ou forcer.

            « Attendre » ne guette pas indefiniment : au bout de dix minutes on renonce et
            on le dit. Une attente silencieuse et sans fin est un blocage deguise.
        #>
        $restartServer = {
            $r = & $askServerRestart $false $false

            if ("$r".StartsWith('busy:')) {
                $operation = "$r".Substring(5)
                $choix = & $askWindow (Get-Label 'tray.relance-operation-titre') `
                                      (Get-Label 'tray.relance-operation-texte' $operation) `
                                      (Get-Label 'tray.relance-forcer') `
                                      (Get-Label 'tray.relance-attendre') `
                                      (Get-Label 'tray.relance-rien')
                if ($choix -eq 0) { $r = & $askServerRestart $true $false }        # forcer
                elseif ($choix -eq 4) {
                    # C'EST LE SERVEUR QUI ATTEND. Il sait ce qui tourne, et son relanceur
                    # est detache : lui faire garder la question evite au tray une boucle
                    # de sondage et un delai arbitraire.
                    TLog "relance : le serveur attendra la fin de l'operation"
                    $r = & $askServerRestart $false $true
                }
                else { return }                                            # ne rien faire
            }

            if ($r -eq 'ok') {
                TLog "relance demandee au serveur (il s'en charge)"
                $state.StartTicks = [datetime]::UtcNow.Ticks
                $state.Starting   = $true
                & $setIcon 'warn'; $state.Drawn = 'warn'
                $icon.Text = (Get-Label 'tray.infobulle-etat' $trayAccount 'Démarrage…')
                $miInfo.Text = 'État : Démarrage…'
                return
            }

            # LE SERVEUR NE REPOND PAS : il n'y a plus personne pour se relancer. C'est le
            # seul cas ou l'on parle d'elevation, et on le DIT avant de la demander.
            $suite = & $askWindow (Get-Label 'tray.relance-mort-titre') `
                                  (Get-Label 'tray.relance-mort-texte') `
                                  (Get-Label 'tray.relance-mort-ok') '' `
                                  (Get-Label 'tray.relance-rien')
            if ($suite -ne 0) { return }

            # LE SEUL ENDROIT OU LE TRAY TOUCHE AU SERVEUR, et ce n'est pas le tray qui
            # decide : quelqu'un a clique, lu que le serveur ne repond plus, et accorde
            # l'elevation. Le processus vise est soit mort -- il n'y a rien a arreter --
            # soit coince, et l'arreter est alors la seule guerison.
            #
            # Partout ailleurs, la regle est sans exception : le tray ne ferme jamais le
            # serveur. Le serveur le PRECEDE -- avec la tache de machine, il demarre avant
            # qu'une session existe -- et il est commun a tous les comptes.
            $state.ElevationAsked = $false
            & $stopServer
            Start-Sleep -Milliseconds 600
            & $startServer
        }

        [void]$menu.Items.Add('Redémarrer le serveur', $null, [System.EventHandler]{
            & $restartServer
            # Retour visuel immediat : sans cela l'icone garde son etat jusqu'au prochain
            # sondage (8 s) et l'utilisateur voit un rouge qui n'a pas lieu d'etre.
            & $setIcon 'warn'; $state.Drawn = 'warn'
            $icon.Text = (Get-Label 'tray.infobulle-etat' $trayAccount 'Démarrage…'); $miInfo.Text = 'État : Démarrage…'
        })
        # Les journaux du SERVEUR : c'est ce qu'on veut voir pour diagnostiquer.
        [void]$menu.Items.Add('Ouvrir les journaux', $null, [System.EventHandler]{ Start-Process (Get-LogDir -Backend $backend) })
        <#
            « A PROPOS » MONTRE, IL NE PART PAS.

            Ce menu ouvrait directement le depot GitHub : on quittait Vigie pour un
            navigateur sans avoir rien appris d'elle. Or c'est exactement la ou l'on va
            chercher ce qu'on ne sait pas -- quelle version tourne, sous quel compte,
            depuis quel dossier. Le lien du depot y a sa place, mais comme UNE des
            informations, pas comme destination.

            La fenetre repond aux questions qu'on se pose devant un incident : quelle
            version, quel compte, quel emplacement, quel serveur. Le lien s'ouvre depuis
            la fenetre, si on le veut.
        #>
        $showAbout = {
            try {
                $version = try { Get-AppVersion -Backend $backend } catch { 'inconnue' }
                $srv = if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) {
                           (Get-Label 'tray.apropos-serveur-en-ligne' $cfg.Port)
                       } else { (Get-Label 'tray.apropos-serveur-hors-ligne') }
                $lignes = @(
                    (Get-Label 'tray.apropos-version'     $version),
                    (Get-Label 'tray.apropos-compte'      $trayAccount),
                    (Get-Label 'tray.apropos-application' (Split-Path $backend -Parent)),
                    $srv,
                    '',
                    (Get-Label 'tray.apropos-depot'       $repoUrl),
                    '',
                    (Get-Label 'tray.apropos-ouvrir-depot')
                )
                $reponse = [System.Windows.Forms.MessageBox]::Show(
                    ($lignes -join [Environment]::NewLine),
                    (Get-Label 'tray.apropos-titre'),
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($reponse -eq [System.Windows.Forms.DialogResult]::Yes) { & $openRepo }
            } catch { TLog ("a propos KO : " + $_.Exception.Message) }
        }
        $miAbout = $menu.Items.Add('À propos de Vigie', $null, [System.EventHandler]$showAbout)
        $miAbout.ToolTipText = $repoUrl
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add('Quitter', $null, [System.EventHandler]{ & $quitApp 'menu' })

        # Couleur et HAUTEUR DE LIGNE, en un seul endroit pour tous les items.
        # Le padding vertical ne sert qu'a fixer la hauteur : la POSITION du texte est
        # imposee par le renderer (OnRenderItemText), parce que le moteur de disposition
        # des menus deroulants rend Padding inexploitable pour placer le contenu.
        # Aucun padding horizontal ici : il ferait doublon avec TextPadX du renderer.
        $itemPad = New-Object System.Windows.Forms.Padding(0, [VigieMenuPalette]::TextPadY, 0, [VigieMenuPalette]::TextPadY)
        foreach ($it in $menu.Items) {
            if ($it -is [System.Windows.Forms.ToolStripMenuItem]) {
                $it.ForeColor = $lite
                $it.Padding   = $itemPad
            }
        }
        $icon.ContextMenuStrip = $menu
        # Le double-clic est trace AVANT d'agir : si rien ne se passe, le journal dit
        # si le clic a seulement atteint l'application. Sans cela, impossible de
        # distinguer un gestionnaire jamais appele d'une ouverture qui echoue.
        $icon.add_MouseDoubleClick({ TLog "double-clic sur l'icone"; & $openApp })

        & $startServer
        TLog "serveur ok"

        $poll = {
            try {
                [void](Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5 -ErrorAction Stop)
                $state.EverUp   = $true
                $state.Starting = $false
                $state.HealthKo = 0
                $state.SaidDead = $false
                $app = 'ok'; $lbl = 'En marche'
            } catch {
                # Serveur COINCE : le port repond (TCP) mais plus aucune requete n'aboutit
                # (constate le 24/08 : bug du listener Pode, tout finissait en 408). Dans ce
                # cas, relancer est la seule guerison -- et personne d'autre que le tray ne
                # peut la faire, puisque le port ouvert masque la panne. Trois echecs
                # consecutifs (~24 s) hors demarrage => on tue l'ecouteur et on repart.
                if (-not $state.Starting -and (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port)) {
                    $state.HealthKo = [int]$state.HealthKo + 1
                    # SERVEUR COINCE : le port repond, les requetes non. Le tray le
                    # CONSTATE et le dit -- il ne le tue plus. Tuer le serveur commun
                    # depuis un tray, c'est le couper pour tous les comptes, et le tray
                    # arrive apres lui. La guerison appartient a la tache serveur, qui le
                    # relance, ou a quelqu'un qui clique « Redemarrer le serveur ».
                    if ($state.HealthKo -eq 3) {
                        TLog "serveur coince (port ouvert, health muet x3) : signale, pas tue"
                        try {
                            $icon.ShowBalloonTip(8000, (Get-Label 'tray.bulle-coince-titre'),
                                                 (Get-Label 'tray.bulle-coince-texte'),
                                                 [System.Windows.Forms.ToolTipIcon]::Warning)
                        } catch { }
                    }
                }
                $elapsed = ([datetime]::UtcNow.Ticks - $state.StartTicks) / 1e7
                if ($state.Starting) {
                    # LE PROCESSUS EST-IL ENCORE LA ? C'est la seule preuve qui vaille :
                    # tant qu'il vit, le demarrage se poursuit, quel que soit le temps
                    # qu'il y met. On ne connait ce processus que si c'est NOUS qui
                    # l'avons lance -- un tray qui adopte un serveur en place n'a rien a
                    # observer, et retombe alors sur un delai, volontairement large.
                    $known = $false
                    $alive = $false
                    try {
                        if ($state.Proc) { $known = $true; $alive = (-not $state.Proc.HasExited) }
                    } catch { $known = $false }

                    if ($known -and $alive -and $elapsed -le $startupGrace) {
                        $app = 'warn';  $lbl = 'Démarrage…'
                    } elseif ($known -and -not $alive) {
                        # Il s'est arrete : inutile d'attendre la fin d'un delai pour le
                        # dire. C'est meme PLUS RAPIDE que l'ancien comportement.
                        $app = 'error'; $lbl = 'Le serveur s''est arrêté au démarrage'
                    } elseif (-not $known -and $elapsed -le $startupBlind) {
                        $app = 'warn';  $lbl = 'Démarrage…'
                    } else {
                        $app = 'error'; $lbl = 'Échec de démarrage'
                    }
                } elseif (-not (Test-IsElevated) -and $state.ElevationAsked) {
                    # L'elevation a ete demandee et refusee -- ou pas encore accordee. Ni
                    # panne ni attente : on le dit, et « Redemarrer le serveur » redemande.
                    $app = 'warn'; $lbl = 'Serveur arrêté : relance à autoriser'
                } else {
                    $app = 'error'; $lbl = 'Arrêtée / injoignable'
                    # Serveur MORT (port ferme) : le tray le relance seul. C'est le
                    # pendant du cas « coince » ci-dessus -- constate le 25/08 au matin :
                    # serveur tue, tray vivant, et personne pour redemarrer. startServer
                    # repose la fenetre de tolerance, ce qui espace naturellement les
                    # tentatives si le demarrage echoue en boucle.
                    if ($state.EverUp -and -not (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port)) {
                        # MORT : il n'y a plus personne pour se relancer. On previent par
                        # une bulle -- elle disparait seule, sans rien reclamer -- et l'on
                        # tente la relance. Si les droits manquent, l'icone reste orange et
                        # « Redemarrer le serveur » reste la, a la demande.
                        if (-not $state.SaidDead) {
                            $state.SaidDead = $true
                            TLog "serveur mort (port ferme)"
                            try {
                                $icon.ShowBalloonTip(8000, (Get-Label 'tray.bulle-mort-titre'),
                                                     (Get-Label 'tray.bulle-mort-texte'),
                                                     [System.Windows.Forms.ToolTipIcon]::Warning)
                            } catch { }
                        }
                        & $startServer
                        $app = 'warn'; $lbl = 'Redémarrage…'
                    }
                }
            }
            $miInfo.Text = "État : $lbl"
            if ($app -ne $state.Drawn) { & $setIcon $app; $state.Drawn = $app; $icon.Text = (Get-Label 'tray.infobulle-etat' $trayAccount $lbl); TLog "app=$app" }
            # Battement de coeur : c'est lui qui permet a un script de savoir si le tray
            # est vivant, sans avoir a inspecter un processus eleve.
            try {
                # UTF8 et non ASCII : l'etat contient des accents (« Démarrage… »), que
                # l'ASCII remplace par des points d'interrogation.
                Set-Content -LiteralPath $heartbeat -Encoding UTF8 -NoNewline `
                    -Value ("{0};{1};{2}" -f $PID, (Get-Date -Format 'o'), $lbl)
            } catch { }

            # --- Notifications sur bascule d'un MODULE (D54) -------------------------
            # L'icone reste le statut de l'APP ; ici on remonte les RESULTATS de sonde.
            # Lecture directe du cache d'etat du backend (fichier) : aucun appel /state,
            # donc aucun recalcul provoque -- on observe ce qui a DEJA ete calcule.
            # On ne notifie QUE sur changement (jamais de rappel repete), et jamais au
            # premier passage : au demarrage on prend l'etat comme reference, sinon
            # chaque lancement arroserait l'utilisateur de tout ce qui est deja connu.
            try {
                if (Test-Path -LiteralPath $stateCacheFile) {
                    $j = Get-Content -LiteralPath $stateCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    # On observe l'etat des CHAMPS, pas seulement des cartes : une
                    # notification est un evenement NOMME (« Temperature GPU elevee »),
                    # declare par le module. « Session de jeu » ne disait rien a personne
                    # -- signale par l'utilisateur le 26/08.
                    $vus = @{}
                    foreach ($pr in $j.PSObject.Properties) {
                        foreach ($m in @($pr.Value.module)) {
                            if (-not $m -or -not $m.id) { continue }
                            $vus["$($m.id)"] = @{ status = "$($m.status)"; label = "$($m.label)" }
                            foreach ($c in @($m.fields)) {
                                if ($c -and $c.key) { $vus["$($m.id)/$($c.key)"] = @{ status = "$($c.status)"; label = "$($c.label)" } }
                            }
                        }
                    }
                    if (-not $state.ModsInit) {
                        $state.Mods = $vus; $state.ModsInit = $true
                    } else {
                        $reglages = $null
                        $bascules = @()
                        # Le catalogue dit QUOI notifier et sous quel nom. Il est relu a
                        # chaque passage : un module rallume doit etre pris en compte.
                        $catalogue = @()
                        try { $catalogue = @(Get-NotificationCatalog -Backend $backend) } catch { }
                        foreach ($u in $catalogue) {
                            foreach ($nn in @($u.notifications)) {
                                $ref = if ($nn.card -and $nn.field) { "$($nn.card)/$($nn.field)" } else { $null }
                                if (-not $ref) { continue }
                                $avant = $state.Mods[$ref]
                                $apres = $vus[$ref]
                                if (-not $avant -or -not $apres) { continue }
                                if ($avant.status -eq $apres.status) { continue }
                                # On ne derange que pour une DEGRADATION ou un RETABLISSEMENT.
                                $interessant = ($apres.status -in @('warn','error')) -or
                                               ($apres.status -eq 'ok' -and $avant.status -in @('warn','error'))
                                if (-not $interessant) { continue }
                                if ($null -eq $reglages) { $reglages = Get-NotificationSettings -Backend $backend }
                                if (-not (Test-NotificationAllowed -ModuleId $u.unit -Key $nn.key -Settings $reglages)) { continue }
                                # Prevenu SANS pouvoir agir : on le dit, au lieu de laisser
                                # l'utilisateur devant un probleme qui lui echappe.
                                $aPrevenir = ("$($nn.rights)" -eq 'admin' -and -not (Test-IsElevated))
                                $bascules += [pscustomobject]@{ id = "$($u.unit).$($nn.key)"; label = "$($nn.label)"; de = $avant.status; vers = $apres.status; prevenir = $aPrevenir }
                            }
                        }
                        $state.Mods = $vus
                        if ($bascules.Count -gt 0) {
                            # Une seule bulle, meme pour plusieurs bascules simultanees :
                            # trois notifications d'un coup, c'est du bruit.
                            $pire  = if (@($bascules | Where-Object { $_.vers -eq 'error' }).Count) { 'error' }
                                     elseif (@($bascules | Where-Object { $_.vers -eq 'warn' }).Count) { 'warn' } else { 'ok' }
                            $tipIc = switch ($pire) { 'error' { 'Error' } 'warn' { 'Warning' } default { 'Info' } }
                            $mot   = @{ ok = 'rétabli'; warn = 'à surveiller'; error = 'en erreur'; neutral = 'sans objet' }
                            $texte = (@($bascules | ForEach-Object {
                                ("{0} : {1}" -f $_.label, $mot[$_.vers]) +
                                $(if ($_.prevenir -and $_.vers -ne 'ok') { [Environment]::NewLine + "   -> signalez-le a un administrateur" } else { '' })
                            }) -join [Environment]::NewLine)
                            $titre = if ($bascules.Count -eq 1) { 'Un module a changé d''état' } else { "$($bascules.Count) modules ont changé d'état" }
                            TLog ("notification : " + (@($bascules | ForEach-Object { "$($_.id) $($_.de)->$($_.vers)" }) -join ', '))
                            try { $icon.ShowBalloonTip(6000, $titre, $texte, [System.Windows.Forms.ToolTipIcon]::$tipIc) } catch { }
                        }
                    }
                }
            } catch { TLog ("guetteur de modules : " + $_.Exception.Message) }
        }
        $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 8000; $timer.add_Tick($poll); $timer.Start()
        $first = New-Object System.Windows.Forms.Timer; $first.Interval = 2000; $first.add_Tick({ $first.Stop(); & $poll }); $first.Start()

        # Lecture des ordres. Un simple sondage d'un dossier quasi vide : negligeable, et
        # bien plus simple a maintenir qu'un FileSystemWatcher, dont les evenements
        # arrivent sur un autre fil et devraient etre remis sur le fil d'interface.
        $commandes = {
            try {
                $stop = Join-Path $runDir 'stop'
                if (Test-Path -LiteralPath $stop) {
                    Remove-Item -LiteralPath $stop -Force -ErrorAction SilentlyContinue
                    try { Set-Content -LiteralPath (Join-Path $runDir 'stop.ack') -Value "$PID" -Encoding ASCII -NoNewline } catch { }
                    & $quitApp 'ordre stop'
                    return
                }
                $restart = Join-Path $runDir 'restart'
                if (Test-Path -LiteralPath $restart) {
                    Remove-Item -LiteralPath $restart -Force -ErrorAction SilentlyContinue
                    # ACCUSE DE RECEPTION, avant de partir. L'emetteur ne pouvait juger
                    # que sur le retour d'un NOUVEAU tray (une dizaine de secondes) :
                    # « ordre non pris en compte » melangeait donc « rien n'a lu l'ordre »
                    # et « la relance est plus lente que prevu ». Ce n'est pas le meme
                    # depannage.
                    try { Set-Content -LiteralPath (Join-Path $runDir 'restart.ack') -Value "$PID" -Encoding ASCII -NoNewline } catch { }
                    TLog "arret demande (ordre restart)"
                    & $relaunch
                    return
                }

                <#
                    LES ACTIONS QUI ONT BESOIN D'UN ECRAN.

                    Le serveur n'en a pas -- et le jour ou il devient la tache de machine,
                    il tournera en session 0, ou « Start-Process explorer.exe » reussit
                    sans que personne ne voie jamais la fenetre. Il depose donc l'ordre
                    ici, et c'est le tray qui l'execute : dans SA session, avec SES droits,
                    sur le bureau de celui qui a demande.

                    On rend compte dans un fichier « .done.json » que le serveur attend.
                    MEME EN CAS D'ECHEC : sans compte rendu, il patiente jusqu'a expiration
                    puis conclut a tort que le tray est absent.
                #>
                foreach ($ordre in @(Get-ChildItem -LiteralPath $runDir -Filter 'desktop-*.json' -File -ErrorAction SilentlyContinue |
                                     Where-Object { $_.Name -notlike '*.done.json' })) {
                    $reponse = Join-Path $runDir ($ordre.BaseName + '.done.json')
                    $sortie = @{ message = ''; result = @{ ok = $false } }
                    try {
                        $charge = Get-Content -LiteralPath $ordre.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                        Remove-Item -LiteralPath $ordre.FullName -Force -ErrorAction SilentlyContinue
                        $type = "$($charge.type)"
                        # Le meme controle que cote serveur : un identifiant simple, et
                        # rien qui ressemble a un chemin. Un dossier d'ordres est une
                        # surface d'attaque, meme dans son propre profil.
                        if ($type -notmatch '^[a-z][a-z0-9-]{1,40}$') { throw "type d'action invalide" }
                        $script = Join-Path (Join-Path $backend 'actions') ($type + '.action.ps1')
                        if (-not (Test-Path -LiteralPath $script)) { throw "action inconnue : $type" }
                        $p = @{}
                        if ($charge.params) {
                            foreach ($prop in $charge.params.PSObject.Properties) { $p[$prop.Name] = $prop.Value }
                        }
                        TLog "ordre de bureau : $type"
                        $r = & $script -Module "$($charge.module)" -Params $p
                        $sortie = @{ message = "$($r.message)"; result = $r.result }
                    } catch {
                        TLog ("ordre de bureau KO : " + $_.Exception.Message)
                        $sortie = @{ message = $_.Exception.Message; result = @{ ok = $false } }
                    }
                    try { ($sortie | ConvertTo-Json -Compress -Depth 6) | Out-File -FilePath $reponse -Encoding UTF8 } catch { }
                }
            } catch { TLog ("lecture des ordres KO : " + $_.Exception.Message) }
        }
        $cmdTimer = New-Object System.Windows.Forms.Timer
        $cmdTimer.Interval = 1000; $cmdTimer.add_Tick($commandes); $cmdTimer.Start()

        # S5 : on s'abonne, puis on regarde le drapeau a chaque seconde. Un echec ici ne
        # casse rien -- la sonde reseau se perime de toute facon d'elle-meme.
        try {
            [VigieNative.Net]::Watch()
            $netTimer = New-Object System.Windows.Forms.Timer
            $netTimer.Interval = 1000
            $netTimer.add_Tick({
                try {
                    if ([VigieNative.Net]::Changed) {
                        [VigieNative.Net]::Changed = $false
                        Remove-ProbeCache -Names @('net.probe.ps1') -Backend $backend
                        TLog "adresse reseau changee : sonde reseau perimee"
                    }
                } catch { }
            })
            $netTimer.Start()
            TLog "guetteur d'adresse reseau arme"
        } catch { TLog ("guetteur d'adresse reseau indisponible : " + $_.Exception.Message) }

        try { $icon.ShowBalloonTip(3000, 'Vigie', "Panneau lance en fond. Double-cliquez l'icone pour l'ouvrir.", [System.Windows.Forms.ToolTipIcon]::Info) } catch { }

        TLog "Application.Run"
        [System.Windows.Forms.Application]::Run()
        if ($iconHandle -ne [System.IntPtr]::Zero) { [void][VigieNative.Ico]::DestroyIcon($iconHandle) }
        TLog "sortie boucle"
    } catch { TLog ("ERREUR UI: " + $_.Exception.ToString()) }
}

$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
$ps = [PowerShell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript($uiScript).AddArgument($backend).AddArgument($trayLog).AddArgument($RepoUrl).AddArgument($PSScriptRoot)
try { $ps.Invoke() } catch { TLog ("ERREUR Invoke: " + $_.Exception.ToString()) }
foreach ($er in $ps.Streams.Error) { TLog ("STREAM ERROR: " + $er.ToString()) }
try { $rs.Close() } catch { }
try { $mutex.ReleaseMutex() } catch { }
TLog "termine"
