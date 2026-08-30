<#
    vigie-update.ps1 - Met a jour Vigie, puis la relance.

    D'OU VIENT LE CODE. Trois voies, decrites dans `vigie-fetch.ps1`, qui fait tout le
    travail de recuperation :
      - poste de DEVELOPPEMENT (le depot est la) : on deploie l'etat du depot local, et
        `deploy-prod.ps1` pose au passage le tag de ce deploiement (D96) ;
      - machine INSTALLEE (pas de depot) : on telecharge la derniere version publiee sur
        GitHub, et on la deploie telle quelle -- aucun tag a poser, il existe deja ;
      - reference forcee (-Ref une branche, un tag, un commit) : on passe par un clone a
        nous, pour tester une version qui n'est pas publiee.

    L'ORDRE COMPTE. On rapporte et on VERIFIE l'archive d'abord ; on ne touche a
    l'installation qu'ensuite. Une recuperation qui echoue laisse donc la version en
    place intacte et en marche -- c'est le seul comportement acceptable pour une mise a
    jour : au pire, rien n'a bouge.

    Enchainement, sans intervention (D81 : les processus s'enchainent seuls, et le
    resultat de chaque sous-processus est LU) :
      1. vigie-fetch.ps1  -> une archive verifiee (sauf voie locale, qui fabrique et tague)
      2. deploy-prod.ps1  -> deploiement, reglages de la machine conserves
      3. scripts/tray.ps1 -Restart -> le tray relance le serveur avec le nouveau code

    Codes de retour : 0 = a jour et relancee ; 1 = rien n'a ete deploye (l'ancienne
                      version tourne toujours) ; 2 = deploiement fait, mais la relance
                      n'a pas abouti ; 3 = deja a jour, rien a faire (D77).

    Appele par l'action « Mettre a jour Vigie », sous le veilleur (D82) : ce code de
    retour finit en ligne verte ou rouge sur la carte Deploiement.
#>
param(
    # Emplacement de l'installation partagee. Defaut : celui de deploy-prod.
    [string] $Destination,

    [ValidateSet('auto', 'local', 'release', 'clone')]
    [string] $Source = 'auto',

    # Branche, tag ou commit a deployer. Force la voie « clone ».
    [string] $Ref,

    # Accepter une pre-version publiee (GitHub les exclut de « latest »).
    [switch] $PreVersions,

    # Deployer meme si ce qui est trouve n'est pas plus recent que ce qui tourne.
    [switch] $Force,

    # QUI DEMANDE. Ce script tourne detache, sous le compte du service : il n'a pas de
    # session pour le deduire. Le serveur le lui passe, car c'est dans la session de cette
    # personne que le tag de version sera pose -- dans SON depot, sous SON identite (D112).
    [string] $Requester
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
$pwsh    = (Get-Process -Id $PID).Path

<#
    ON MET A JOUR DEPUIS LE DEPOT, QUAND IL Y EN A UN.

    Lancee depuis l'installation partagee, cette mise a jour ne voyait aucun depot autour
    d'elle : elle partait donc chercher la derniere version PUBLIEE, alors que le poste a
    un depot local en avance de plusieurs commits. Sur une machine de developpement, ce
    n'est pas ce qu'on demande.

    L'ordinateur declare ou est son depot (machine.psd1), et UpdateSource dit s'il faut
    s'en servir. Si on doit s'en servir et qu'il est lisible, on lui PASSE LA MAIN : c'est
    lui qui sait fabriquer, poser le tag et deployer. Aucune recursion possible -- vu
    depuis le depot, la source, c'est lui-meme.

    S'il a disparu, ou si le compte qui execute ne peut pas le lire, la voie retombe sur
    la version publiee.
#>
# $sourceRepo, PAS $source : PowerShell ne distingue pas la casse, donc « $source »
# designait le PARAMETRE $Source -- dont le ValidateSet refuse $null. Le script mourait
# a cette ligne, avant tout le reste.
$sourceRepo = $null
try { $sourceRepo = (Get-UpdateRoute -Backend $backend).repo } catch { }
if ($sourceRepo -and ($sourceRepo.TrimEnd([char]92, [char]47) -ne $repoRoot.TrimEnd([char]92, [char]47))) {
    $relayScript = Join-Path (Join-Path $sourceRepo 'scripts') 'vigie-update.ps1'
    if (Test-Path -LiteralPath $relayScript) {
        Write-Info (Get-Label 'vigie-update.depuis-le-depot' $sourceRepo)
        $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $relayScript + '"'))
        foreach ($p in $PSBoundParameters.GetEnumerator()) {
            if ($p.Value -is [switch]) { if ($p.Value.IsPresent) { $argv += ('-' + $p.Key) } }
            else                       { $argv += @(('-' + $p.Key), ('"' + $p.Value + '"')) }
        }
        $relayRun = Start-Process -FilePath $pwsh -ArgumentList $argv -Wait -PassThru -WindowStyle Hidden
        exit $relayRun.ExitCode
    }
    Write-Warn (Get-Label 'vigie-update.depot-sans-script' $sourceRepo)
}

$avant = $null
try { $avant = Get-BuildStamp -Root $repoRoot } catch { }
Write-Host (Get-Label 'vigie-update.version-de-depart' $(if ($avant -and $avant.version) { $avant.version } else { 'inconnue' }) $(if ($avant -and $avant.commit) { " (" + $avant.commit.Substring(0, 8) + ")" } else { "" }))

# --- 0. Quelle voie ? ----------------------------------------------------------------
#
# La voie locale garde son chemin d'origine : c'est deploy-prod, SANS -Zip, qui fabrique
# ET pose le tag. Lui passer une archive toute faite ferait sauter le tag, et le projet
# n'aurait plus de numero de version (D96).
$estDepot = $false
try {
    $estDepot = (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) -and
                [bool](Get-Command git -ErrorAction SilentlyContinue)
} catch { }

# LE CHOIX DE LA MACHINE, quand l'appelant n'impose rien. Un serveur de developpement
# peut vouloir se comporter comme une machine d'utilisateur (UpdateSource = 'release'),
# ou l'inverse : c'est un reglage de MACHINE, il vit dans config.local.psd1.
if (-not $PSBoundParameters.ContainsKey('Source')) {
    try {
        $cfg = Get-Config -Backend $backend
        $choix = "$($cfg.UpdateSource)".Trim()
        if ($choix -and @('auto','local','release','clone') -contains $choix) {
            $Source = $choix
            # On n'annonce que ce qui CHANGE quelque chose : « auto » est le defaut, il
            # n'impose rien, et l'annoncer laisse croire a un reglage particulier.
            if ($choix -ne 'auto') { Write-Host (Get-Label 'vigie-update.source-imposee-par-la' $choix) }
        }
        if (-not $Ref -and "$($cfg.UpdateRef)".Trim()) { $Ref = "$($cfg.UpdateRef)".Trim() }
    } catch { }
}

# LA CARTE ET LE BOUTON LISENT LA MEME RESOLUTION (Get-UpdateRoute) : sans cela, la carte
# annonce une reference et le bouton va chercher ailleurs.
$route = $Source
if ($route -eq 'auto') {
    if ($Ref) { $route = 'clone' }
    else {
        $resolved = $null
        try { $resolved = Get-UpdateRoute -Backend $backend } catch { }
        if ($resolved)      { $route = $resolved.route }
        elseif ($estDepot) { $route = 'local' }
        else               { $route = 'release' }
    }
}

# --- 1. Rapporter le code (sauf voie locale, qui fabrique elle-meme) ------------------
$archive = $null
<#
    LE TAG EST POSE PAR LE DEMANDEUR, AVANT DE FABRIQUER.

    Le deploiement marque une version : cette regle ne change pas. Mais ce script tourne
    sous le compte du service, qui n'a rien a ecrire dans le depot d'une personne -- git
    le refuse, et un tag sans auteur ne vaut rien. On demande donc a l'app cliente du
    demandeur de le poser chez elle ; le clone du service le verra au fetch suivant, et
    l'archive portera ce numero.

    Sans demandeur identifie, ou si sa session ne repond pas, on continue : on fabriquera
    depuis la branche, avec un numero « v0.1.29+3 ». Une mise a jour ne doit pas echouer
    parce qu'un tag n'a pas pu etre pose.
#>
$remoteLocal = $false
try { $remoteLocal = (Test-Path -LiteralPath (Join-Path (Get-UpdateRemote -Backend $backend) '.git')) } catch { }
if ($route -eq 'clone' -and $remoteLocal -and -not $Ref) {
    $poseTag = $null
    if ($Requester) {
        # Lance depuis l'interface : le demandeur a une session, le tag s'y pose.
        Write-Info (Get-Label 'vigie-update.marquage-demande' $Requester)
        try {
            $marquage = Invoke-DesktopAction -Account $Requester -Type 'tag-version' -TimeoutSec 45 -Backend $backend
            $poseTag = "$($marquage.result.tag)"
            if (-not $poseTag) { Write-Detail (Get-Label 'vigie-update.marquage-sans-tag' "$($marquage.message)") }
        } catch {
            Write-Detail (Get-Label 'vigie-update.marquage-impossible' $_.Exception.Message)
        }
    } else {
        <#
            LANCE A LA MAIN : ON EST DEJA DANS LA BONNE SESSION.

            Le tag est pose par le proprietaire du depot. Depuis l'interface, c'est
            l'action en session qui s'en charge ; depuis un terminal, celui qui tape la
            commande EST ce proprietaire -- il n'y a personne a qui deleguer.

            Sans ce cas, une mise a jour lancee en ligne de commande ne marquait plus
            aucune version : « Vigie est a jour, v0.1.29+10, mais aucun tag n'a ete cree »
            (constate le 30/08). Et si on n'est pas le proprietaire, git refuse : on le
            dit, et on continue -- une mise a jour ne rate pas pour un tag.
        #>
        $source = Get-UpdateRemote -Backend $backend
        try {
            $pose = New-DeploymentTag -RepoPath $source -Push
            if ($pose.posed) { $poseTag = $pose.tag }
            else { Write-Detail (Get-Label 'vigie-update.marquage-impossible' "$($pose.error)") }
        } catch {
            Write-Detail (Get-Label 'vigie-update.marquage-impossible' $_.Exception.Message)
        }
    }
    if ($poseTag) {
        $Ref = $poseTag
        Write-Ok (Get-Label 'vigie-update.version-marquee' $poseTag)
    }
}

if ($route -ne 'local') {
    $fetch = Join-Path $PSScriptRoot 'vigie-fetch.ps1'
    if (-not (Test-Path -LiteralPath $fetch)) {
        Write-Fail (Get-Label 'vigie-update.vigie-fetch-ps1-introuvable')
        exit 1
    }
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $fetch, '-Source', $route)
    if ($Ref)         { $argv += @('-Ref', $Ref) }
    if ($PreVersions) { $argv += '-PreVersions' }
    if ($Force)       { $argv += '-Force' }

    Write-Info (Get-Label 'vigie-update.recuperation')
    # La sortie est LUE : la derniere ligne porte le chemin de l'archive. Tout le reste
    # est du recit, qu'on repete a l'ecran pour que le journal en garde la trace.
    $lignes = & $pwsh @argv 2>&1
    $codeFetch = $LASTEXITCODE
    foreach ($l in $lignes) { Write-Host $l }

    if ($codeFetch -eq 3) {
        Write-Ok (Get-Label 'vigie-update.rien-faire-vigie-est')
        exit 3
    }
    if ($codeFetch -ne 0) {
        Write-Fail (Get-Label 'vigie-update.la-recuperation-echoue-code' $codeFetch)
        exit 1
    }
    $archive = @($lignes | Where-Object { "$_".Trim() } | Select-Object -Last 1)
    $archive = "$archive".Trim()
    if (-not $archive -or -not (Test-Path -LiteralPath $archive)) {
        Write-Fail (Get-Label 'vigie-update.la-recuperation-dit-avoir' $archive)
        Write-Fail (Get-Label 'vigie-update.rien-ete-deploye')
        exit 1
    }
}

# --- 2. Deploiement ------------------------------------------------------------------
$deploy = Join-Path $PSScriptRoot 'deploy-prod.ps1'
if (-not (Test-Path -LiteralPath $deploy)) {
    Write-Fail (Get-Label 'vigie-update.deploy-prod-ps1-introuvable')
    exit 1
}
$argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $deploy + '"'), '-Yes')
if ($archive)     { $argv += @('-Zip', ('"' + $archive + '"')) }
if ($Destination) { $argv += @('-Destination', ('"' + $Destination + '"')) }

Write-Info (Get-Label 'vigie-update.deploiement')
$p = Start-Process -FilePath $pwsh -ArgumentList $argv -Wait -PassThru -WindowStyle Hidden
Write-Info (Get-Label 'vigie-update.deploy-prod-rendu-le' $p.ExitCode)
if ($p.ExitCode -ne 0) {
    Write-Fail (Get-Label 'vigie-update.le-deploiement-echoue-vigie')
    exit 1
}

# --- 3. Relance ----------------------------------------------------------------------
#
# DEUX APPLICATIONS, DEUX RELANCES. L'app cliente se relance sur ordre ; l'app serveur se
# relance ELLE-MEME, avec ses propres droits (D65). Le commentaire disait encore que le
# tray relancait le serveur avec lui : ce n'est plus vrai depuis qu'une relance passe par
# le serveur, et la mise a jour laissait donc l'app serveur sur l'ANCIEN code.
#
# Le relanceur ATTEND la fin des operations en cours : celle qui tourne, c'est justement
# cette mise a jour. Il redemarre donc quand elle a fini, pas au milieu.
$installed = Get-SharedInstallPath
if ($installed) {
    $startScript = Join-Path (Join-Path (Join-Path $installed 'apps') 'backend-pode') 'start.ps1'
    try {
        $previousPid = Start-ServerRelauncher -StartScript $startScript -Wait -Backend $backend
        Write-Info (Get-Label 'vigie-update.app-serveur-relance' $previousPid)
    } catch {
        # Pas d'app serveur en marche : c'est le cas d'une premiere installation, et il n'y
        # a rien a relancer. On le dit sans en faire un echec.
        Write-Detail (Get-Label 'vigie-update.app-serveur-pas-relancee' $_.Exception.Message)
    }
}

$tray = Join-Path $PSScriptRoot 'tray.ps1'
if (-not (Test-Path -LiteralPath $tray)) {
    Write-Warn (Get-Label 'vigie-update.le-deploiement-est-fait')
    exit 2
}
# LES AUTRES COMPTES D'ABORD. Leur tray tourne encore avec le code d'avant ; on le
# previent avant de relancer le notre, sinon le serveur redemarre pendant qu'ils lisent.
try {
    $autres = @(Send-TrayRestartToAll)
    if ($autres.Count) { Write-Detail (Get-Label 'vigie-update.autres-trays' ($autres -join ', ')) }
} catch { }

Write-Info (Get-Label 'vigie-update.relance-de-vigie')
$r = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                                                   '-File', ('"' + $tray + '"'), '-Restart') `
                   -Wait -PassThru -WindowStyle Hidden
Write-Info (Get-Label 'vigie-update.la-relance-rendu-le' $r.ExitCode)
if ($r.ExitCode -ne 0) {
    Write-Warn (Get-Label 'vigie-update.le-deploiement-est-fait-2')
    exit 2
}

$apres = $null
try { $apres = Get-BuildStamp -Root $repoRoot } catch { }
Write-Host (Get-Label 'vigie-update.vigie-est-jour' $(if ($apres -and $apres.version) { $apres.version } else { 'version inconnue' }) $(if ($apres -and $apres.commit) { " (" + $apres.commit.Substring(0, 8) + ")" } else { "" })) -ForegroundColor Green
exit 0
