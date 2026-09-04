# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    install.ps1 - Installe les prerequis. IDEMPOTENT. Cible PowerShell 7.
    Journalise dans backend/logs/install_*.log (transcript). Fichier en ASCII
    pour rester lisible par PowerShell 5.1 au moment de basculer en pwsh.

    Portee des modules :
      - eleve (admin)     -> AllUsers  : C:\Program Files\PowerShell\Modules
                             (visible par TOUS les PowerShell 7 : MSI, Store,
                              tache planifiee, eleve ou non). Recommande.
      - non eleve         -> CurrentUser (repli).

    Usage :  powershell -File .\install.ps1   (basculera en pwsh)
#>
param(
    <#
        QUI DEMANDE. Depuis le bouton de la carte, l'installation tourne sous le compte du
        service : elle n'a pas de session pour le deduire. Le serveur lui passe le compte de
        la personne qui a clique, car c'est dans SA session que le tag de version sera pose
        -- dans SON depot, sous SON identite (D112).
    #>
    [string] $Requester,

    # Refaire la sequence entiere meme si l'installation est deja a jour.
    [switch] $Force,

    <#
        WHERE TO INSTALL. Empty = wherever it already is, otherwise the default.

        The choice happens at the FIRST installation only: afterwards the folder in place
        wins, and asking again would suggest Vigie can move from one update to the next --
        which would leave two installations on the computer.
    #>
    [string] $InstallPath,

    <#
        PAS DE FENETRE DE FIN. Le serveur n'a pas de bureau : une fenetre ouverte depuis sa
        session ne s'afficherait nulle part, et attendrait un clic que personne ne peut
        donner. Le verdict, lui, part dans le journal comme d'habitude.
    #>
    [switch] $NoWindow,

    <#
        L'ACTION QUI M'A LANCE -- DONT LA MARQUE D'OCCUPATION EST LA MIENNE.

        Depuis le bouton de la carte, l'app serveur pose une marque « une operation
        tourne » AVANT de lancer l'installation, pour que la carte le montre et que rien
        d'autre ne demarre en meme temps. L'installation, elle, refuse de tourner pendant
        qu'une operation est en cours -- et trouvait donc la SIENNE. Elle s'interdisait
        elle-meme, et rendait le code 5 (constate le 31/08 : « ECHEC le 31/08/2026 09:27
        -- code de sortie 5 »).

        On ne supprime pas le controle : c'est lui qui empeche d'interrompre une analyse
        de disque. On en retire la seule operation dont on sait qu'elle EST nous.
    #>
    [string] $FromAction
)

$ErrorActionPreference = 'Stop'

# LE MEME AFFICHAGE QUE PARTOUT. Charge des le debut, avant meme la bascule en
# PowerShell 7 : cette premiere passe tourne sous 5.1, et elle affiche deja.
. (Join-Path $PSScriptRoot 'lib/console-ui.ps1')

# --- Cible PowerShell 7 : bascule si lance en 5.1 ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # L'interpreteur de la MACHINE d'abord : c'est celui que lanceront les taches de
    # demarrage, donc celui avec lequel il faut installer.
    $pwsh = Join-Path (Join-Path (Join-Path $env:ProgramFiles 'PowerShell') '7') 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwsh)) {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    }
    if ($pwsh) {
        Write-Info (Get-Label 'install.bascule-en-powershell')
        # LES PARAMETRES SUIVENT LA BASCULE. Sans cela, « -Requester » et « -Force » se
        # perdaient au passage en PowerShell 7, et la seconde passe ne savait plus qui avait
        # demande.
        # RAW VALUES: the call operator quotes each argument itself (D116).
        $nextArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($Requester) { $nextArgs += @('-Requester', $Requester) }
        if ($Force)     { $nextArgs += '-Force' }
        if ($NoWindow)  { $nextArgs += '-NoWindow' }
        if ($FromAction) { $nextArgs += @('-FromAction', $FromAction) }
        & $pwsh @nextArgs
        # LE CODE DE LA PASSE LANCEE EST LE NOTRE. Sans cette ligne, un echec de
        # l'installation reelle remontait en succes a l'appelant : le lanceur affichait
        # « Termine » sur une installation ratee (constate le 26/08).
        exit $LASTEXITCODE
    }
    Write-Step (Get-Label 'install.powershell-est-absent-installation')
    # L'ELEVATION est indispensable ici : une installation en portee machine sans droits
    # administrateur echoue sur « 0x80070005 : Access is denied » -- et winget ayant deja
    # retire l'eventuelle version du compte, la machine se retrouve SANS PowerShell 7
    # (vecu le 26/08). On le dit AVANT d'essayer, plutot que de laisser ce trou.
    $isAdminAccount = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $isAdminAccount = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
                        [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }
    if (-not $isAdminAccount) {
        Write-Fail (Get-Label 'install.cette-etape-doit-etre')
        Write-Detail (Get-Label 'install.double-cliquez-sur-setup')
                return
    }
    $target = Join-Path (Join-Path (Join-Path $env:ProgramFiles 'PowerShell') '7') 'pwsh.exe'

    # 1) winget, en imposant le MSI.
    #
    # Deux pieges rencontres le 26/08, dans cet ordre :
    #   - sans --installer-type msi, winget prend le MSIXBUNDLE et tente de le
    #     « provisionner » pour tous les comptes : echec 0x80070005 -- et il avait DEJA
    #     desinstalle la version du compte, la machine s'est donc retrouvee SANS
    #     PowerShell du tout ;
    #   - avec --installer-type msi, la source winget n'a AUCUN paquet MSI pour cet
    #     identifiant : elle balaie toutes les versions puis renonce (0x8a150010).
    # D'ou le repli ci-dessous. Un installateur doit ABOUTIR, pas renvoyer l'utilisateur
    # vers une page de telechargement.
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.PowerShell -e --scope machine --installer-type msi --source winget --accept-package-agreements --accept-source-agreements
    }

    # 2) Repli : le MSI publie par l'equipe PowerShell, installe pour TOUTE la machine.
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Warn (Get-Label 'install.winget-pas-de-paquet')
        try {
            # TLS 1.2 : Windows PowerShell 5.1 ne l'active pas toujours, et GitHub refuse
            # tout le reste. Sans cette ligne, le telechargement echoue sur une erreur de
            # connexion qui n'explique rien.
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
                                     -Headers @{ 'User-Agent' = 'Vigie-install' } -TimeoutSec 60
            $asset = @($rel.assets | Where-Object { $_.name -like '*-win-x64.msi' }) | Select-Object -First 1
            if (-not $asset) { throw "aucun MSI x64 dans la derniere version publiee" }
            $msi = Join-Path $env:TEMP $asset.name
            # SANS CECI, Windows PowerShell 5.1 s'enlise : le rendu de sa barre de
            # progression coute plus cher que le telechargement lui-meme, et sur 108 Mo
            # la commande semble figee de longues minutes APRES que le fichier soit
            # complet -- constate le 26/08, fichier entier sur disque et script toujours
            # en attente. C'est un defaut connu de 5.1 ; on eteint la barre.
            $ProgressPreference = 'SilentlyContinue'
            $mo  = [math]::Round(([double]$asset.size) / 1MB, 1)
            # Deja telecharge ET complet ? On ne recommence pas : une tentative
            # precedente peut avoir bute apres coup (voir ci-dessus).
            $alreadyThere = $false
            if (Test-Path -LiteralPath $msi) {
                $alreadyThere = ((Get-Item -LiteralPath $msi).Length -eq [long]$asset.size)
                if (-not $alreadyThere) { Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue }
            }
            if ($alreadyThere) {
                Write-Detail (Get-Label 'install.deja-telecharge-mo' $asset.name $mo)
            } else {
                Write-Info (Get-Label 'install.telechargement-de-mo' $asset.name $mo)
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing -TimeoutSec 900
                Write-Detail (Get-Label 'install.telechargement-termine')
            }
            Write-Info (Get-Label 'install.installation-pour-toute-la')
            # ALLUSERS=1 : installation MACHINE. /qn : sans interface, on est deja eleve.
            # /qb et non /qn : une installation de deux minutes doit se VOIR. Une barre
            # de progression vaut mieux qu'une fenetre muette dont on ne sait pas si elle
            # travaille ou si elle est bloquee.
            $mi = Start-ChildProcess -FilePath 'msiexec.exe' `
                      -Arguments @('/i', $msi, '/qb', 'ALLUSERS=1', 'ADD_PATH=1') `
                      -Options @{ Wait = $true; PassThru = $true }
            # LE RESULTAT SE LIT. 0 = installe ; 3010 = installe, redemarrage demande ;
            # 1618 = un autre installateur travaille deja ; le reste est un echec qu'il
            # faut nommer, pas passer sous silence.
            switch ([int]$mi.ExitCode) {
                0    { Write-Ok (Get-Label 'install.installation-reussie') }
                3010 { Write-Warn (Get-Label 'install.installee-windows-demande-un') }
                1618 { Write-Warn (Get-Label 'install.un-autre-installateur-windows') }
                default { Write-Fail (Get-Label 'install.msiexec-echoue-code' $mi.ExitCode) }
            }
            if ([int]$mi.ExitCode -eq 0 -or [int]$mi.ExitCode -eq 3010) {
                Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Fail (Get-Label 'install.echec-du-repli-msi' $_.Exception.Message)
        }
    }

    # 3) On CONSTATE, et on enchaine tout seul : l'utilisateur n'a pas a relancer.
    if (Test-Path -LiteralPath $target) {
        Write-Ok (Get-Label 'install.powershell-installe-pour-la' $target)
        Write-Detail (Get-Label 'install.installation-se-poursuit-avec')
        & $target -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
    Write-Fail (Get-Label 'install.powershell-pas-pu-etre')
    Write-Detail (Get-Label 'install.telechargez-le-msi-la')
    Write-Detail (Get-Label 'install.fichier-powershell-version-win')
    exit 1
}

# Les scripts de gestion vivent dans scripts/ : les apps sont dans apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

<#
    LE JOURNAL COMMENCE AVANT LA PREMIERE ETAPE.

    Il demarrait au milieu : la declaration de l'ordinateur, la source et le DEPLOIEMENT
    se produisaient avant, donc hors journal. Le 30/08, l'installation a fini sur
    « ECHEC : 2 etape(s) » alors que le fichier ne contenait pas une seule ligne d'erreur
    -- de quoi chercher longtemps ce qui n'y etait pas.

    Un journal qui commence apres le debut ne sert a rien : c'est justement le debut qu'on
    relit quand ca se passe mal.
#>
$logDir = Get-LogDir -Backend $backend
$log    = Join-Path $logDir ('install_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }

<#
    UNE SEULE INSTALLATION A LA FOIS.

    Deux installations simultanees se marchent dessus : l'une arrete ce que l'autre vient
    de demarrer, l'une copie pendant que l'autre sauvegarde. On refuse, et on dit QUI
    tient le verrou -- sinon « une installation est deja en cours » ressemble a une panne.

    Un verrou dont le processus n'existe plus est ignore : un plantage ne doit pas
    condamner le poste.
#>
$verrou = Lock-Install
if (-not $verrou) {
    $qui = Get-InstallLockHolder
    Write-Title (Get-Label 'install.titre')
    # L'HEURE SE LIT A L'HEURE D'ICI. Le verrou la stocke en UTC (une marque, pas un
    # affichage) ; telle quelle elle annoncait « depuis 04:54 » a 06:54, soit une
    # installation commencee deux heures plus tot -- de quoi croire a un verrou oublie.
    $depuis = "$($qui.at)"
    try { $depuis = ([datetime]::Parse($qui.at)).ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss') } catch { }
    Write-Fail (Get-Label 'install.deja-en-cours' "$($qui.account)" "$($qui.pid)" $depuis)
    try { Stop-Transcript | Out-Null } catch { }
    exit 4
}


<#
    INSTALLER OU METTRE A JOUR : CE N'EST PAS LA MEME NOUVELLE.

    Le meme script fait les deux -- c'est voulu, il est idempotent et c'est le SEUL geste
    a connaitre. Mais il annoncait « Installation de Vigie » meme quand une version
    tournait deja, sans dire laquelle ni vers quoi on allait : on relancait sans savoir
    si quelque chose changeait.

    On regarde donc ce qui est en place AVANT de commencer, et on le dit : d'ou l'on
    part, ou l'on va, et dans quel environnement -- « developpement » ou « production »,
    tel qu'il est DECLARE.
#>
$current = $null
try {
    $installedPath = Get-SharedInstallPath
    if ($installedPath) { $current = Get-BuildStamp -Root $installedPath }
} catch { }
$incoming = $null
try { $incoming = Get-BuildStamp -Root $repoRoot } catch { }
<#
    LA VERSION QU'ON POSE : UNE SEULE VALEUR, DU DEBUT A LA FIN.

    Elle etait recalculee a chaque endroit qui en parlait, et chacun tombait sur une
    reponse differente : le journal annoncait « vers v0.1.37 » -- la version marquee --
    pendant que la fenetre de fin disait « v0.1.36 vers v0.1.36+8 », lue avant que le tag
    ne soit pose. Le meme deploiement racontait deux histoires (constate le 31/08).

    On la PREDIT ici, avant de commencer -- c'est le tag qui sera marque -- puis on la
    CONSTATE apres la copie, sur ce qui est reellement en place. La constatation gagne
    toujours : c'est la seule qui ne peut pas se tromper.
#>
$versionPosee = $null
$isUpdate = [bool]($current -and $current.version)

# DEUX APPELS EN CLAIR plutot qu'une cle calculee : un verificateur ne peut pas juger une
# cle construite a l'execution, et c'est la porte ouverte au « [?...] » en production.
if ($isUpdate) { Write-Title (Get-Label 'install.titre-maj') }
else            { Write-Title (Get-Label 'install.titre') }
if ($isUpdate) {
    # ON ANNONCE LA VERSION QUI SERA POSEE. « v0.1.33+13 » decrit un depot en cours de
    # route ; ce qui sera installe, en stage dev, porte le tag suivant.
    if ($incoming -and $incoming.version) {
        $versionPosee = Get-IncomingVersion -Version "$($incoming.version)" -RepoPath $repoRoot -Backend $backend
    }
    Write-Info (Get-Label 'install.de-vers' $current.version $(if ($versionPosee) { $versionPosee } else { '?' }))
}
# PROD EST LE DEFAUT, ON NE L'ANNONCE PAS. L'application est de production d'abord : le
# dire a chaque fois n'apprend rien. C'est le stage « developpement » qui merite d'etre
# signale -- avec ce qu'il implique : une source locale, et des versions marquees ici.
if ((Get-DeclaredStage -Backend $backend) -eq 'dev') {
    Write-Info (Get-Label 'install.stage-dev')
}
Write-Step (Get-Label 'install.etape-prerequis')

# --- VIGIE S'INSTALLE DANS PROGRAM FILES ------------------------------------
#
# Une application Windows vit dans Program Files, pas dans le dossier ou l'archive a
# ete decompressee. Sans cette copie, la tache de demarrage pointait sur ce dossier :
# l'utilisateur devait le garder a vie, et le vider par megarde cassait Vigie.
#
# Trois cas OU L'ON NE BOUGE PAS :
#   - un DEPOT git : c'est un poste de developpement, Vigie tourne depuis les sources ;
#   - on y est deja : la copie relancerait le script indefiniment ;
#   - sans elevation : ecrire dans Program Files est refuse. On le dit, et on continue
#     sur place plutot que d'echouer -- Vigie reste utilisable.
# WHERE TO INSTALL: what is asked for, else what is already in place, else the default.
# THE ORDER MATTERS: an existing installation wins over a path passed by mistake -- otherwise
# an update launched with a wrong argument would create a second one elsewhere.
$destDeclaree = $null
try { $destDeclaree = Get-SharedInstallPath } catch { }
$destPartagee = if ($destDeclaree) { $destDeclaree }
                elseif ("$InstallPath".Trim()) { "$InstallPath".Trim().TrimEnd([char]92) }
                else { Join-Path $env:ProgramFiles (Join-Path 'Sowapps' 'Vigie') }
<#
    A FOLDER THE OTHER ACCOUNTS CANNOT READ IS NOT AN INSTALLATION.

    Program Files is readable by everyone BY CONSTRUCTION; a chosen folder is not. Installing
    into a private folder gives a Vigie that works for you and for nobody else -- the startup
    task of every other account would fail at each session, silently.

    We say so BEFORE copying, and fall back to the default: refusing to install would punish
    the user for a choice they could not know was wrong, and letting it through would be worse.
#>
if ("$InstallPath".Trim() -and -not $destDeclaree) {
    $parentChoisi = Split-Path $destPartagee -Parent
    $lisible = $true
    if ($parentChoisi -and (Test-Path -LiteralPath $parentChoisi -ErrorAction SilentlyContinue)) {
        $lisible = [bool](Test-InstallationPartagee -Path $parentChoisi)
    }
    if (-not $lisible) {
        Write-Warn (Get-Label 'install.dossier-non-partage' $destPartagee)
        $destPartagee = Join-Path $env:ProgramFiles (Join-Path 'Sowapps' 'Vigie')
        Write-Detail (Get-Label 'install.dossier-defaut-retenu' $destPartagee)
    }
}
$here          = (Resolve-Path -LiteralPath $repoRoot).Path
# LE DEPOT DE CET ORDINATEUR, ou $null. Une seule definition, dans la bibliotheque : la
# question « suis-je dans un depot ? » ne se repose pas ici, et surtout elle ne decide plus
# de rien -- elle sert UNIQUEMENT a noter d'ou vient l'installation.
$repoLocal  = Get-LocalRepoPath -Backend $backend
$alreadyThere       = ($here.TrimEnd([char]92) -ieq $destPartagee.TrimEnd([char]92))

<#
    UNE INSTALLATION LANCEE DEPUIS UN DEPOT NOTE D'OU ELLE VIENT.

    C'est le PREMIER geste d'un developpeur sur un poste neuf, et il tourne sous SON
    compte, dans SON depot. On y note donc le chemin de la source, et on declare ce
    dossier de confiance pour git.

    Sans cette declaration, l'app serveur -- qui tourne sous un compte de service -- ne
    peut meme pas CLONER ce depot : git refuse d'ouvrir un dossier appartenant a quelqu'un
    d'autre. Le bouton « Mettre a jour » echouerait donc avant tout premier deploiement,
    et le developpeur n'aurait aucun moyen de comprendre pourquoi.

    L'ENVIRONNEMENT N'EST PAS DEDUIT ICI : il se declare (config.local.psd1). Trouver un
    depot ne fait pas d'un poste une machine de developpement.
#>
<#
    LA DECLARATION DE L'ORDINATEUR EXISTE TOUJOURS.

    Elle n'etait ecrite que si l'installation partait d'un depot : ailleurs, le fichier
    n'existait pas et le stage n'etait « prod » que par defaut, sans que rien ne le dise.
    Un reglage qu'on ne voit nulle part est un reglage qu'on ne sait pas changer.

    On l'ecrit donc a chaque installation, avec le stage EN CLAIR -- sans jamais toucher
    a une valeur deja declaree : ce fichier appartient a qui l'a rempli.
#>
<#
    ON N'INTERROMPT PAS UNE OPERATION EN COURS.

    Une analyse de disque, une installation de mises a jour Windows : les arreter au
    milieu laisse un travail a moitie fait, et c'est exactement ce que les marques
    d'occupation servent a eviter. On refuse, en NOMMANT ce qui tourne.
#>
$enCours = @()
try { $enCours = @(Get-RunningOperations -Backend $backend) } catch { }
# NOTRE PROPRE MARQUE NE NOUS ARRETE PAS.
if ($FromAction) { $enCours = @($enCours | Where-Object { "$($_.action)" -ne $FromAction }) }
if ($enCours.Count) {
    Write-Title (Get-Label 'install.titre')
    Write-Fail (Get-Label 'install.operation-en-cours' "$($enCours[0].label)")
    Unlock-Install
    try { Stop-Transcript | Out-Null } catch { }
    exit 5
}

Write-Step (Get-Label 'install.declaration-ordinateur')
try {
    $stageDeclare = Get-DeclaredStage -Backend $backend
    $noteA = Set-ComputerConfigValue -Values @{ Stage = $stageDeclare }
    Write-Detail (Get-Label 'install.stage-note' $stageDeclare $noteA)
} catch {
    Write-Warn (Get-Label 'install.declaration-impossible' $_.Exception.Message)
}

if ($repoLocal) {
    Write-Step (Get-Label 'install.source-declaree')
    try {
        $noteA = Set-ComputerConfigValue -Values @{ SourcePath = $repoLocal }
        Write-Detail (Get-Label 'install.source-notee' $repoLocal $noteA)
    } catch {
        Write-Warn (Get-Label 'install.source-non-notee' $_.Exception.Message)
    }
    if (Test-Elevated) {
        try {
            if (Set-GitSafeDirectory -RepoPath $repoRoot) { Write-Ok (Get-Label 'install.depot-de-confiance' $repoRoot) }
            else { Write-Detail (Get-Label 'install.depot-deja-de-confiance') }
        } catch {
            Write-Warn (Get-Label 'install.confiance-impossible' $_.Exception.Message)
        }
    } else {
        # Sans elevation on ne peut pas ecrire la configuration git de la machine. On le
        # DIT : c'est exactement ce qui rendrait le bouton de mise a jour inexplicable.
        Write-Warn (Get-Label 'install.confiance-demande-elevation')
    }
}

<#
    DEPUIS UN DEPOT, L'INSTALLATION DEPLOIE -- ELLE NE FAIT PAS QUE PREPARER.

    « L'installation doit TOUT installer, l'app est prete ensuite. » Or lancee depuis un
    depot, elle ne copiait RIEN : elle posait les taches, annoncait « De v0.1.31 vers
    v0.1.31+8 »... et l'installation partagee restait a v0.1.31. Aucune version marquee
    non plus, puisque c'est le deploiement qui pose le tag.

    On appelle donc la mise a jour, qui est la SEULE mise en oeuvre du geste : elle marque
    la version, fabrique l'archive depuis la source declaree, deploie, et relance. On
    tourne ici sous le compte de la personne, dans son depot : le tag a un auteur.

    Code 3 = « deja a jour » : ce n'est pas un echec (D77), on continue.
#>
<#
    RECUPERER, ARRETER, SAUVEGARDER, POSER, VERIFIER -- DANS CET ORDRE.

    C'est la sequence cible (doc/progress/targeting/install-update.md). Elle vaut pour les
    deux points d'entree, `setup.cmd` et le bouton de la carte : ce qui decide d'une etape,
    ce sont des FAITS -- y a-t-il une installation en place, un depot, quelle source est
    declaree -- jamais qui appelle.

    L'ORDRE N'EST PAS ARBITRAIRE. On recupere AVANT d'arreter quoi que ce soit : la
    fabrication est ce qui prend le plus de temps, et Vigie n'a aucune raison d'etre
    coupee pendant. On ne s'arrete qu'ensuite, le temps de poser les fichiers.
#>
<#
    ON RECUPERE MEME QUAND ON N'EST PAS DANS UN DEPOT.

    Cette etape ne se declenchait que si le dossier courant etait un depot git. Depuis le
    BOUTON de la carte, l'installation tourne depuis l'installation partagee -- Program
    Files, aucun .git : elle ne recuperait donc RIEN, ne deployait rien, et se terminait
    en succes. « L'app est toujours en 0.1.36 au lieu de 0.1.37 » (constate le 31/08) :
    elle n'avait jamais eu de version a poser.

    D'ou vient le code ne se deduit pas de l'endroit d'ou l'on lance : c'est un REGLAGE
    DECLARE (D99). vigie-update sait deja le lire -- clone du depot declare, ou derniere
    version publiee -- et sait dire « deja a jour » (code 3). On lui laisse trancher.

    Seule exception : une premiere installation depuis une archive posee a la main, ou il
    n'y a ni depot, ni source declaree, ni rien a chercher.
#>
$prepared = $null
<#
    RECUPERER LA VERSION A POSER -- ICI, ET NULLE PART AILLEURS.

    C'etait un script a part, vigie-update.ps1, appele en processus fils et dont on lisait
    la DERNIERE LIGNE pour connaitre le dossier. Un contrat de sortie entre deux scripts
    du meme depot, alors qu'ils font un seul geste : le 31/08, ce script s'est relaye vers
    une autre copie de lui-meme dont la sortie ne revenait pas, l'installation a lu une
    phrase d'information a la place d'un chemin, et cinquante-six secondes de fabrication
    sont parties a la poubelle. On avait acte sa disparition ; elle est faite.

    L'etape tourne AVANT tout arret : fabriquer est la partie longue, et Vigie n'a aucune
    raison d'etre coupee pendant.
#>
$aRecuperer = $false
try { $aRecuperer = [bool](Get-UpdateRoute -Backend $backend).route } catch { }
if ($aRecuperer) {
    Write-Step (Get-Label 'install.etape-recuperation')

    # LE CHOIX DE LA MACHINE. Un poste de developpement peut vouloir se comporter comme
    # une machine d'utilisateur (UpdateSource = 'release'), ou l'inverse.
    $updateSource = 'auto'
    $updateRef = ''
    try {
        $cfgMaj = Get-Config -Backend $backend
        $choix = "$($cfgMaj.UpdateSource)".Trim()
        if ($choix -and @('auto','release','clone') -contains $choix) {
            $updateSource = $choix
            # On n'annonce que ce qui CHANGE quelque chose : « auto » est le defaut.
            if ($choix -ne 'auto') { Write-Detail (Get-Label 'vigie-update.source-imposee-par-la' $choix) }
        }
        if ("$($cfgMaj.UpdateRef)".Trim()) { $updateRef = "$($cfgMaj.UpdateRef)".Trim() }
    } catch { }

    # LA CARTE ET LE BOUTON LISENT LA MEME RESOLUTION (Get-UpdateRoute) : sans cela, la
    # carte annonce une reference et le bouton va chercher ailleurs.
    $route = $updateSource
    if ($route -eq 'auto') {
        if ($updateRef) { $route = 'clone' }
        else {
            $resolu = $null
            try { $resolu = Get-UpdateRoute -Backend $backend } catch { }
            $route = $(if ($resolu -and $resolu.route) { $resolu.route } else { 'release' })
        }
    }

    <#
        LE TAG EST POSE PAR LE DEMANDEUR, AVANT DE FABRIQUER.

        On marque une version s'il y a des commits d'avance ET qu'on est en stage dev.
        L'installation tourne peut-etre sous le compte du service, qui n'a rien a ecrire
        dans le depot d'une personne : on demande a l'app cliente du demandeur de poser le
        tag chez elle, et le clone le verra au fetch suivant.

        Lancee a la main, il n'y a personne a qui deleguer : celui qui tape la commande EST
        le proprietaire. Et si le tag ne peut pas se poser, on continue -- une mise a jour
        ne rate pas pour un numero.
    #>
    if ($route -eq 'clone' -and (Get-DeclaredStage -Backend $backend) -eq 'dev' -and -not $updateRef) {
        $tagPose = $null
        if ($Requester) {
            Write-Detail (Get-Label 'vigie-update.marquage-demande' $Requester)
            try {
                $marquage = Invoke-DesktopAction -Account $Requester -Type 'tag-version' -TimeoutSec 45 -Backend $backend
                $tagPose = "$($marquage.result.tag)"
                if (-not $tagPose) { Write-Detail (Get-Label 'vigie-update.marquage-sans-tag' "$($marquage.message)") }
            } catch { Write-Detail (Get-Label 'vigie-update.marquage-impossible' $_.Exception.Message) }
        } else {
            $depotSource = Get-UpdateRemote -Backend $backend
            try {
                $pose = New-DeploymentTag -RepoPath $depotSource -Push
                if ($pose.posed) { $tagPose = $pose.tag }
                else { Write-Detail (Get-Label 'vigie-update.marquage-impossible' "$($pose.error)") }
            } catch { Write-Detail (Get-Label 'vigie-update.marquage-impossible' $_.Exception.Message) }
        }
        if ($tagPose) {
            $updateRef = $tagPose
            Write-Ok (Get-Label 'vigie-update.version-marquee' $tagPose)
        }
    }

    # LA FABRICATION reste un script a part : elle a sa propre affaire -- git, archive,
    # verification du contenu -- et elle sert aussi a fabriquer une release a la main.
    $archive = $null
    $fetch = Join-Path $PSScriptRoot 'vigie-fetch.ps1'
    if (-not (Test-Path -LiteralPath $fetch)) {
        Write-Fail (Get-Label 'vigie-update.vigie-fetch-ps1-introuvable')
    } else {
        # RAW VALUES: the call operator quotes each argument itself, so a value wrapped by
        # hand would arrive WITH its quotes (D116).
        $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                  '-File', $fetch, '-Source', $route)
        if ($updateRef) { $argv += @('-Ref', $updateRef) }
        if ($Force)     { $argv += '-Force' }

        Write-Detail (Get-Label 'vigie-update.recuperation')
        # La sortie est LUE : la derniere ligne porte le chemin de l'archive. Le reste est
        # du recit, qu'on repete pour que le journal en garde la trace.
        $lignesFetch = & (Get-Process -Id $PID).Path @argv 2>&1
        $codeFetch = $LASTEXITCODE
        foreach ($l in $lignesFetch) {
            Write-Relayed "$l"
            try { Write-Log -Backend $backend -Name 'install' -Message "$l" -NoEcho } catch { }
        }

        if ($codeFetch -eq 3) {
            # DEJA A JOUR : c'est un succes, et il n'y a rien a poser.
            Write-Ok (Get-Label 'install.deploiement-inutile')
        } elseif ($codeFetch -ne 0) {
            Write-Fail (Get-Label 'install.recuperation-echouee' $codeFetch)
        } else {
            $archive = "$(@($lignesFetch | Where-Object { "$_".Trim() } | Select-Object -Last 1))".Trim()
            if (-not (Test-PathSafe $archive)) {
                Write-Fail (Get-Label 'vigie-update.la-recuperation-dit-avoir' $archive)
                $archive = $null
            }
        }
    }

    if ($archive) {
        try {
            $prepared = Expand-InstallArchive -Zip $archive
            Write-Ok (Get-Label 'vigie-update.archive-prete-a-poser')
        } catch {
            Write-Fail (Get-Label 'vigie-update.extraction-impossible' $_.Exception.Message)
            $prepared = $null
        }
    }
}

<#
    UNE RECUPERATION QUI ECHOUE ARRETE L'INSTALLATION.

    Ce repli existe pour le cas « il n'y avait RIEN a recuperer » : une archive extraite a
    la main, dont le dossier courant EST la version a poser. Il se declenchait aussi quand
    la recuperation avait ete TENTEE et RATEE -- l'installation posait alors le dossier
    d'ou elle tournait, c'est-a-dire le depot de developpement.

    Constate le 01/09 : la fabrication de v0.1.44 echoue, l'installation continue, arrete
    Vigie, sauvegarde, copie le depot par-dessus l'installation, constate « version posee
    v0.1.43 au lieu de v0.1.44 » et restaure. Tout ce travail, et ce risque, pour un
    echec connu vingt lignes plus haut.

    On ne se rabat donc que si l'on n'a RIEN TENTE.
#>
if (-not $prepared -and -not $alreadyThere -and -not $aRecuperer) { $prepared = $repoRoot }
if ($aRecuperer -and -not $prepared) {
    Write-Fail (Get-Label 'install.recuperation-arrete-tout')
}
if ($prepared) {
    $stopped = @()
    $backup  = $null
    $go = $true

    Write-Step (Get-Label 'install.etape-controles')
    $poids = 0
    try { $poids = (Get-ChildItem -LiteralPath $prepared -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum } catch { }
    $refus = Test-DeploymentPossible -Destination $destPartagee -NeededBytes $poids
    if ($refus) {
        Write-Fail (Get-Label 'install.deploiement-impossible' $refus)
        $go = $false
    }

    if ($go) {
        Write-Step (Get-Label 'install.etape-arret')
        # LES APP CLIENTES : un echec est signale, il n'arrete pas le deploiement.
        try {
            $stopped = @(Stop-TrayTasks -Backend $backend)
            if ($stopped.Count) { Write-Detail (Get-Label 'install.app-clientes-arretees' (($stopped | ForEach-Object { $_.name }) -join ', ')) }
        } catch { Write-Warn (Get-Label 'install.arret-app-clientes-impossible' $_.Exception.Message) }
        $hors = 0
        try { $hors = Stop-StandaloneTrays } catch { }
        if ($hors -gt 0) { Write-Detail (Get-Label 'install.app-clientes-hors-tache' $hors) }

        # L'APP SERVEUR : si elle tient encore le port apres l'arret force, on ne pose
        # rien -- remplacer ses fichiers sous elle est exactement ce qu'on evite.
        if (Stop-ServerApp -Backend $backend) {
            Write-Detail (Get-Label 'install.app-serveur-arretee')
        } else {
            Write-Fail (Get-Label 'install.app-serveur-toujours-la')
            $go = $false
        }
    }

    if ($go -and (Test-PathSafe (Join-Path $destPartagee 'apps'))) {
        Write-Step (Get-Label 'install.etape-sauvegarde')
        try {
            $backup = Backup-Install -Source $destPartagee -Backend $backend
            Write-Detail (Get-Label 'install.sauvegarde-faite' $backup)
        } catch {
            Write-Fail (Get-Label 'install.sauvegarde-impossible' $_.Exception.Message)
            $go = $false
        }
    }

    if ($go) {
        Write-Step (Get-Label 'install.etape-copie')
        $attendue = $null
        try { $attendue = (Get-BuildStamp -Root $prepared).version } catch { }
        $pose = $null
        try { Copy-InstallFrom -Source $prepared -Destination $destPartagee }
        catch { $pose = $_.Exception.Message }
        if (-not $pose) { $pose = Test-InstallCopy -Destination $destPartagee -ExpectedVersion $attendue }

        if (-not $pose) {
            Write-Ok (Get-Label 'install.deploiement-fait')
            # WE DECLARE WHERE WE LANDED -- AFTER the copy, never before. Declaring a folder
            # we have not filled would send everyone to an empty place.
            try { Set-InstallPathDeclaration -Path $destPartagee }
            catch { Write-Warn (Get-Label 'install.declaration-chemin-echouee' $_.Exception.Message) }
            <#
                AND WHERE WE CAME FROM, so that nothing ever removes it.

                A repository was already declared (SourcePath); an extracted archive was
                declared nowhere -- and the uninstall, knowing nothing of it, could carry it
                off the day it sat where the installation was found. What the person kept on
                their disk to install Vigie is theirs, not ours.

                A TEMPORARY EXTRACTION IS NOT AN ORIGIN: what the update chain unpacks under
                var/ is ours to delete, and must not be protected.
            #>
            try {
                $origin = "$here"
                $varRoot = "$(Get-VarRoot -Backend $backend)".TrimEnd([char]92)
                if ($origin -and -not $origin.ToLowerInvariant().StartsWith($varRoot.ToLowerInvariant())) {
                    $null = Set-ComputerConfigValue -Values @{ InstallSource = $origin }
                }
            } catch { }
            # CE QUI EST EN PLACE, LU SUR PLACE : la prediction ne sert plus a rien.
            try {
                $stampPose = Get-BuildStamp -Root $destPartagee
                if ($stampPose -and $stampPose.version) { $versionPosee = "$($stampPose.version)" }
            } catch { }
            if ($backup) {
                # LA SAUVEGARDE N'EXISTE QUE LE TEMPS DU RISQUE.
                Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Fail (Get-Label 'install.copie-invalide' $pose)
            if ($backup) {
                # UNE ETAPE A PART : restaurer n'est pas « poser ». C'est le filet qui se
                # deploie, et ca doit se voir comme tel dans le deroule.
                Write-Step (Get-Label 'install.etape-restauration')
                try {
                    Restore-Install -Backup $backup -Destination $destPartagee
                    Write-Warn (Get-Label 'install.version-restauree')
                } catch {
                    # AUCUNE REPRISE AUTOMATIQUE : on dit ou est la sauvegarde.
                    Write-Fail (Get-Label 'install.restauration-echouee' $_.Exception.Message $backup)
                }
            }
        }
    }
}

try {
    $isAdmin = Test-Elevated
    $scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }
    Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-powershell-eleve-portee' $PSVersionTable.PSVersion $isAdmin $scope)

    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-du-provider-nuget')
        Install-PackageProvider -Name NuGet -Force -Scope $scope | Out-Null
    } else { Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.provider-nuget-deja-present') }

    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # Chemin AllUsers de reference (partage par tous les PS7).
    $allUsersPode = Join-Path $env:ProgramFiles 'PowerShell\Modules\Pode'

    if ($isAdmin) {
        # En admin : on garantit une copie AllUsers, visible par tous les PS7.
        if (Test-Path $allUsersPode) {
            $v = (Get-ChildItem $allUsersPode -Directory -ErrorAction SilentlyContinue | Select-Object -Last 1).Name
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-allusers-deja-present' $v)
        } else {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-de-pode-allusers')
            Install-Module Pode -Scope AllUsers -Force
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-installe-allusers')
        }
    } else {
        if (Get-Module -ListAvailable -Name Pode) {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-deja-installe' (Get-Module -ListAvailable -Name Pode | Select-Object -First 1).Version)
        } else {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.installation-de-pode-currentuser')
            Install-Module Pode -Scope CurrentUser -Force
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.pode-installe-currentuser')
        }
    }

    # --- DEPENDANCE : PowerShell 7 doit etre installe POUR LA MACHINE -----------
    # Vigie demarre par une tache planifiee, une par compte. Un pwsh installe pour le
    # seul compte courant (paquet du Store) vit dans SON profil : la tache des autres
    # comptes pointerait dans un dossier qu'ils ne peuvent pas lire. On le traite ICI,
    # a l'installation, plutot que de le decouvrir le jour ou un compte ne demarre pas.
    $pwshMachine = Get-SharedPwshPath
    if ($pwshMachine) {
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.powershell-machine-present' $pwshMachine)
    } elseif ($isAdmin -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.powershell-existe-que-pour')
        try {
            & 'winget.exe' @(Get-SharedPwshInstallArgs) | Write-Host
            $pwshMachine = Get-SharedPwshPath
        } catch { }
        if ($pwshMachine) {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.powershell-machine-installe' $pwshMachine)
        } else {
            Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.powershell-machine-installation-sans')
        }
    } else {
        Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.powershell-est-installe-que')
        Write-Detail (Get-Label 'install.faire-une-fois-en')
        Write-Detail (Get-Label 'install.winget-install-id-microsoft')
    }

    # LA TRACE AVANT LES DROITS. Poser la source du journal des evenements exige
    # l'elevation : c'est donc ici, une fois, et pas au premier usage. Sans elle, une
    # action privilegiee ne laisserait qu'une trace dans un fichier -- effacable.
    if ($isAdmin) {
        if (Register-VigieEventSource) {
            Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.journal-des-evenements-source')
        } else {
            Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.journal-des-evenements-source-2')
        }
    }

    $null = Get-ApiToken -Backend $backend
    Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.jeton-api-pret-backend')

    $wvKeys = @(
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    $wv = $false; foreach ($k in $wvKeys) { if (Test-Path $k) { $wv = $true } }
    Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.webview2-runtime' $(if ($wv) { 'présent' } else { 'absent' }))

    # --- L'INSTALLATION VA JUSQU'AU BOUT ---------------------------------------
    # « Le script d'install est cense tout faire » : il ne s'arrete donc pas aux
    # prerequis pour renvoyer l'utilisateur vers deux autres commandes. Il enregistre
    # le demarrage automatique et lance l'application.
    #
    # C'est aussi ce qui REPARE une tache existante : elle est reecrite avec
    # l'interpreteur de la machine. Le 26/08, la tache pointait vers le pwsh du paquet
    # Store, supprime entre-temps -- Vigie ne demarrait plus du tout, et rien ne le
    # disait.
    # LE SERVICE DE MACHINE, prepare mais pas active. Une seule installation : c'est ici
    # que les nouvelles pieces arrivent, et l'idempotence fait la difference entre une
    # premiere pose et une mise a jour. La tache est creee DESACTIVEE -- rien ne change au
    # demarrage tant que la bascule n'est pas faite.
    $service = Join-Path (Join-Path $PSScriptRoot 'lib') 'install-service.ps1'
    if ($isAdmin -and (Test-Path -LiteralPath $service)) {
        try {
            # ON GARDE CE QUE L'ETAPE AFFICHE. « | Write-Host » le montrait et le perdait :
            # le journal du 29/08 s'arretait a « WebView2 runtime », juste avant ce bloc,
            # alors que l'ecran, lui, montrait toute la suite. Un journal qui s'interrompt
            # avant la partie interessante ne sert a rien -- et c'est precisement celle
            # qu'on relit quand l'installation s'est mal passee.
            # ON REFERME NOTRE ETAPE AVANT DE LUI DONNER LA PAROLE.
            #
            # Ce script affiche ses PROPRES etapes, dans son propre processus. Notre
            # conclusion, elle, n'arrive qu'a l'ouverture de l'etape suivante : elle
            # tombait donc APRES les siennes, et « Pose de la nouvelle version » restait
            # sans conclusion visible (constate le 01/09).
            Close-UiStep
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $service 2>&1 |
                ForEach-Object {
                    $line = "$_"
                    Write-Relayed $line
                    try { Write-Log -Backend $backend -Name 'install' -Message $line -NoEcho } catch { }
                }
            # ON LIT LE CODE DE RETOUR. Il etait journalise sans etre teste : le 28/08,
            # l'enregistrement de la tache a echoue et l'installation a fini en vert.
            # Un code non nul est un ECHEC -- Write-Log ERROR le compte, et le verdict
            # final ne peut plus l'ignorer.
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.service-de-machine-pret')
            } else {
                Write-Log -Backend $backend -Name 'install' -Level 'ERROR' `
                          -Message (Get-Label 'install.service-de-machine-echec' $LASTEXITCODE)
            }
        } catch {
            Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message (Get-Label 'install.service-de-machine' $_.Exception.Message)
        }
    }

    $autostart = Join-Path $PSScriptRoot 'install-autostart.ps1'
    if (-not $isAdmin) {
        Write-Ok (Get-Label 'install.prerequis-installes')
        Write-Warn (Get-Label 'install.le-demarrage-automatique-demande')
        Write-Detail (Get-Label 'install.relancez-cette-installation-en')
    } elseif (Test-Path -LiteralPath $autostart) {
        Write-Step (Get-Label 'install.demarrage-automatique')
        # -Yes : on est deja eleve et l'utilisateur a deja consenti en lancant
        # l'installation ; une seconde fenetre d'explication serait du bruit.
        # LE RESULTAT SE LIT : 0 = fait, 3 = refuse, le reste est un echec.
        # POUR QUI : depuis le bouton, celui qui execute est le service ; la tache de
        # demarrage appartient a la personne qui a demande.
        $argsAuto = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $autostart, '-Yes')
        if ($Requester) { $argsAuto += @('-Account', $Requester) }
        Close-UiStep   # meme raison : il affiche ses propres etapes
        & (Get-Process -Id $PID).Path @argsAuto
        $autostartCode = $LASTEXITCODE
        Write-Log -Backend $backend -Name 'install' -Message (Get-Label 'install.demarrage-automatique-code' $autostartCode)
        switch ([int]$autostartCode) {
            0 { Write-Ok (Get-Label 'install.vigie-demarre-chaque-ouverture') }
            3 { Write-Warn (Get-Label 'install.demarrage-automatique-refuse-vigie') }
            default {
                Write-Fail (Get-Label 'install.le-demarrage-automatique-echoue' $autostartCode)
                Write-Detail (Get-Label 'install.vigie-reste-lancable-la')
            }
        }
    }

    <#
        LES TACHES DES AUTRES COMPTES SE REPARENT AUSSI.

        L'etape precedente n'enregistre que celle du compte courant. Les autres pointent
        peut-etre encore sur un ancien emplacement -- c'est arrive le 30/08, ou la tache
        lancait le depot au lieu de l'installation partagee -- et personne ne les
        corrigerait jamais.

        Les reenregistrer est idempotent : c'est le meme geste que les activer.
    #>
    $autres = @()
    try { $autres = @(Get-EnabledAccounts -Backend $backend | Where-Object { "$($_.name)" -ne (Get-ProcessAccount) }) } catch { }
    foreach ($c in $autres) {
        try {
            $null = Set-VigieAccountEnabled -Name "$($c.name)" -Enabled $true -Backend $backend
            Write-Detail (Get-Label 'install.tache-compte-reparee' "$($c.name)")
        } catch {
            Write-Warn (Get-Label 'install.tache-compte-non-reparee' "$($c.name)" $_.Exception.Message)
        }
    }

    <#
        ON REDEMARRE CE QU'ON A ARRETE.

        Les app clientes des autres comptes ont ete arretees pour ne pas remplacer leurs
        fichiers sous elles ; celle du compte courant vient d'etre relancee par sa tache.
        On declenche donc les autres -- ce qu'un administrateur peut faire.

        Une tache d'app cliente est INTERACTIVE : sans session ouverte chez ce compte,
        Windows refuse. Ce n'est pas une erreur, son app repartira a sa prochaine
        ouverture, avec le nouveau code.
    #>
    if ($stopped -and @($stopped).Count) {
        $me = Get-ProcessAccount
        $toStart = @($stopped | Where-Object { "$($_.name)" -ne $me })
        if ($toStart.Count) {
            $restarted = @(Start-TrayTasks -Accounts $toStart)
            if ($restarted.Count) { Write-Detail (Get-Label 'install.app-clientes-relancees' ($restarted -join ', ')) }
        }
    }

    <#
        LA CARTE NE DOIT PAS RESTER SUR L'ETAT D'AVANT.

        Deux mensonges constates le 31/08, apres un setup.cmd qui s'etait bien passe :
        la carte annoncait « Installation partagee v0.1.33 » alors que le pied de page
        disait v0.1.34 -- son rendu venait du cache, calcule avant le deploiement -- et
        elle affichait encore « ECHEC le 31/08/2026 09:27 -- code de sortie 5 », le
        resultat d'une tentative precedente, comme s'il decrivait l'etat actuel.

        Une installation qui reussit efface donc le dernier resultat de ce geste et fait
        recalculer la carte. Lancee depuis le bouton, c'est le veilleur qui inscrira le
        resultat reel apres nous.

        ON NETTOIE LA OU LA CARTE LIT. Le var d'une installation dans Program Files vit
        dans le profil du compte qui EXECUTE, donc celui du SERVICE -- pas le notre, alors
        que l'installation tourne sous la personne qui a clique. On vise donc les deux :
        le var du service, et celui d'ici pour le cas ou Vigie est lancee depuis le depot.
    #>
    $failuresBeforeVerdict = Get-UiFailureCount
    if ($failuresBeforeVerdict -eq 0) {
        $varRoots = @($null)   # $null = notre propre var, deduit du backend
        try {
            $serviceVar = Get-AccountVarRoot -Account (Get-ServiceAccountName)
            if ($serviceVar) { $varRoots += $serviceVar }
        } catch { }
        foreach ($varRoot in $varRoots) {
            try { Remove-ProbeCache -Names @('comptes.probe.ps1', 'deployment.probe.ps1') -Backend $backend -VarRoot $varRoot } catch { }
            try { Clear-ModuleLastRun -Module 'deployment' -Backend $backend -VarRoot $varRoot } catch { }
        }

        <#
            ON NE RECALCULE RIEN ICI.

            L'installation vide le rendu de ces deux cartes -- il decrivait la version
            d'avant -- et s'arrete la. C'est LA PAGE qui redemande une carte marquee « pas
            encore mesuree », carte par carte, quand quelqu'un la regarde.

            J'avais fait redemander ces deux cartes par l'installation : personne ne l'avait
            demande, et c'est un recalcul automatique de plus -- exactement ce qui a ete
            interdit. Une installation installe ; elle ne mesure pas.
        #>
    }
    # LE VERDICT SE CALCULE. Write-Outcome compte ce que Write-Fail et Write-Warn ont
    # affiche : aucune installation ne peut plus finir en vert avec un echec derriere elle.
    $failures = Get-UiFailureCount
    $warnings = Get-UiWarningCount
    Write-Outcome -What (Get-Label 'install.verdict') `
                  -NextStep (Get-Label 'install.verdict-panneau')

    <#
        LE VERROU SE LIBERE ICI : L'INSTALLATION EST FINIE.

        Il etait rendu apres la fenetre de fin -- qui attend un clic. Tant que personne ne
        la fermait, le poste se croyait en cours d'installation : le bouton de la carte
        repondait « une installation est deja en cours » et rendait le code 4, dix minutes
        apres que tout etait pose (constate le 31/08 : verrou tenu par le pwsh de 10:49,
        toujours vivant, fenetre ouverte).

        Ce qui suit -- le verdict affiche, une fenetre, un journal referme -- ne modifie
        plus rien. Ce n'est pas l'installation, c'est son compte rendu.
    #>
    Unlock-Install

    <#
        ET UNE FENETRE, PAS UN « APPUYEZ SUR UNE TOUCHE ».

        L'installation se lance par un double-clic : elle doit se conclure comme une
        application, pas comme un script. La fenetre dit ce qui a ete fait et ce qui
        reste a savoir ; la console garde le detail pour qui veut le lire.

        SI ELLE NE PEUT PAS S'AFFICHER -- pas d'interface, session sans bureau -- on ne
        bloque rien : la conclusion est deja a l'ecran, et setup.cmd garde son « pause »
        pour les cas d'echec.
    #>
    try {
        $window = Join-Path $PSScriptRoot 'lib/show-confirm.ps1'
        if ((Test-Path -LiteralPath $window) -and -not $NoWindow) {
            # ON PASSE LES CLES, PAS LES TEXTES : voir show-confirm.ps1, les accents ne
            # survivent pas a une ligne de commande.
            <#
                INSTALLATION OU MISE A JOUR : LA FENETRE LE DIT AUSSI.

                Elle annoncait « Vigie est installée » apres une mise a jour, et son texte
                presentait le produit a quelqu'un qui l'utilise depuis des semaines. Ce
                qu'on veut savoir dans ce cas, c'est ce qui a CHANGE.
            #>
            $titleKey = if ($failures -gt 0) { 'install.fenetre-titre-echec' }
                        elseif ($warnings -gt 0) { 'install.fenetre-titre-reserve' }
                        elseif ($isUpdate) { 'install.fenetre-titre-maj' }
                        else { 'install.fenetre-titre' }
            $summaryKey = if ($failures -gt 0) { 'install.fenetre-resume-echec' }
                          elseif ($isUpdate) { 'install.fenetre-resume-maj' }
                          else { 'install.fenetre-resume' }
            # L'ESSENTIEL SE LIT, LE RESTE SE DEPLIE. Ce qu'on veut savoir tient en une
            # phrase ; les chemins et les noms de taches servent apres, si ca cloche.
            # L'URL VIENT DE LA CONFIGURATION, jamais d'une constante recopiee : le port
            # est un reglage, et un texte qui le repete finit par mentir.
            $url = try { Get-AppUrl -Config (Get-Config -Backend $backend) } catch { '' }
            # « De v0.1.31 vers v0.1.32 » : le seul detail qui compte apres une mise a jour.
            $versions = if ($isUpdate -and $versionPosee) {
                            $current.version + ' vers ' + $versionPosee
                        } else { '' }
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $window `
                -Caption (Get-Label 'install.fenetre-bandeau') `
                -TitleKey $titleKey -SummaryKey $summaryKey -SummaryArg $versions `
                -DetailsKey 'install.fenetre-details' -DetailsArg $url `
                -OpenPath $log -OpenText (Get-Label 'install.fenetre-ouvrir-journal') `
                -OkText (Get-Label 'install.fenetre-fermer') -CancelText '' -Note '' | Out-Null
        }
    } catch { }

    if ($failures -gt 0) { try { Stop-Transcript | Out-Null } catch { }; exit 1 }
}
catch {
    Write-Log -Backend $backend -Name 'install' -Level 'ERROR' -Message (Get-Label 'install.fatal' $_.Exception.Message)
    Write-Fail ($_ | Out-String)
    # ON SORT EN ECHEC. Le bloc se contentait d'afficher l'erreur : le script rendait 0,
    # et le lanceur enchainait comme si tout allait bien.
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
finally {
    # LE VERROU SE LIBERE TOUJOURS, quel que soit le chemin de sortie -- succes, echec, ou
    # exception. Un verrou oublie bloque toutes les installations suivantes.
    try { Unlock-Install } catch { }
    try { Stop-Transcript | Out-Null } catch { }
}
