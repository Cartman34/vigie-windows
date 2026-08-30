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
    [switch] $Force
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

    L'installation sait d'ou elle vient (Set-BuildOrigin, pose au deploiement). Si ce depot
    est encore la et lisible, on lui PASSE LA MAIN : c'est lui qui sait fabriquer, poser le
    tag et deployer. Aucune recursion possible -- vu depuis le depot, la source, c'est
    lui-meme.

    S'il a disparu, ou si le compte qui execute ne peut pas le lire, Get-SourceRepoPath rend
    $null et l'on reprend la voie normale : la version publiee.
#>
# $sourceRepo, PAS $source : PowerShell ne distingue pas la casse, donc « $source »
# designait le PARAMETRE $Source -- dont le ValidateSet refuse $null. Le script mourait
# a cette ligne, avant tout le reste.
$sourceRepo = $null
try { $sourceRepo = Get-SourceRepoPath -Backend $backend } catch { }
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

$voie = $Source
if ($voie -eq 'auto') {
    if ($Ref)          { $voie = 'clone' }
    elseif ($estDepot) { $voie = 'local' }
    else               { $voie = 'release' }
}

# --- 1. Rapporter le code (sauf voie locale, qui fabrique elle-meme) ------------------
$archive = $null
if ($voie -ne 'local') {
    $fetch = Join-Path $PSScriptRoot 'vigie-fetch.ps1'
    if (-not (Test-Path -LiteralPath $fetch)) {
        Write-Fail (Get-Label 'vigie-update.vigie-fetch-ps1-introuvable')
        exit 1
    }
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $fetch, '-Source', $voie)
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
