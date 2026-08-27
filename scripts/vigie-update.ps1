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
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')
$backend = Join-Path $repoRoot 'apps/backend-pode'
$pwsh    = (Get-Process -Id $PID).Path

$avant = $null
try { $avant = Get-BuildStamp -Root $repoRoot } catch { }
Write-Host ("Version de depart : " +
            $(if ($avant -and $avant.version) { $avant.version } else { 'inconnue' }) +
            $(if ($avant -and $avant.commit) { " (" + $avant.commit.Substring(0, 8) + ")" } else { "" }))

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
        Write-Host "vigie-fetch.ps1 introuvable : impossible d'aller chercher une version." -ForegroundColor Red
        exit 1
    }
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $fetch, '-Source', $voie)
    if ($Ref)         { $argv += @('-Ref', $Ref) }
    if ($PreVersions) { $argv += '-PreVersions' }
    if ($Force)       { $argv += '-Force' }

    Write-Host "Recuperation..."
    # La sortie est LUE : la derniere ligne porte le chemin de l'archive. Tout le reste
    # est du recit, qu'on repete a l'ecran pour que le journal en garde la trace.
    $lignes = & $pwsh @argv 2>&1
    $codeFetch = $LASTEXITCODE
    foreach ($l in $lignes) { Write-Host $l }

    if ($codeFetch -eq 3) {
        Write-Host "Rien a faire : Vigie est deja a jour. Elle n'a pas ete redemarree." -ForegroundColor Green
        exit 3
    }
    if ($codeFetch -ne 0) {
        Write-Host ("La recuperation a echoue (code " + $codeFetch + "). RIEN n'a ete deploye : la version en place continue de tourner.") -ForegroundColor Red
        exit 1
    }
    $archive = @($lignes | Where-Object { "$_".Trim() } | Select-Object -Last 1)
    $archive = "$archive".Trim()
    if (-not $archive -or -not (Test-Path -LiteralPath $archive)) {
        Write-Host ("La recuperation dit avoir reussi, mais l'archive annoncee est introuvable : " + $archive) -ForegroundColor Red
        Write-Host "RIEN n'a ete deploye." -ForegroundColor Red
        exit 1
    }
}

# --- 2. Deploiement ------------------------------------------------------------------
$deploy = Join-Path $PSScriptRoot 'deploy-prod.ps1'
if (-not (Test-Path -LiteralPath $deploy)) {
    Write-Host "deploy-prod.ps1 introuvable." -ForegroundColor Red
    exit 1
}
$argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $deploy + '"'), '-Yes')
if ($archive)     { $argv += @('-Zip', ('"' + $archive + '"')) }
if ($Destination) { $argv += @('-Destination', ('"' + $Destination + '"')) }

Write-Host "Deploiement..."
$p = Start-Process -FilePath $pwsh -ArgumentList $argv -Wait -PassThru -WindowStyle Hidden
Write-Host ("deploy-prod a rendu le code " + $p.ExitCode + ".")
if ($p.ExitCode -ne 0) {
    Write-Host "Le deploiement a echoue : Vigie n'est PAS relancee, l'ancienne version continue de tourner." -ForegroundColor Red
    exit 1
}

# --- 3. Relance ----------------------------------------------------------------------
# Le tray relance le serveur AVEC lui (D78) : c'est ce qui charge le nouveau code.
$tray = Join-Path $PSScriptRoot 'tray.ps1'
if (-not (Test-Path -LiteralPath $tray)) {
    Write-Host "Le deploiement est fait, mais tray.ps1 est introuvable : relancez Vigie a la main." -ForegroundColor Yellow
    exit 2
}
Write-Host "Relance de Vigie..."
$r = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                                                   '-File', ('"' + $tray + '"'), '-Restart') `
                   -Wait -PassThru -WindowStyle Hidden
Write-Host ("La relance a rendu le code " + $r.ExitCode + ".")
if ($r.ExitCode -ne 0) {
    Write-Host "Le deploiement est fait, mais la relance n'a pas abouti : relancez Vigie a la main." -ForegroundColor Yellow
    exit 2
}

$apres = $null
try { $apres = Get-BuildStamp -Root $repoRoot } catch { }
Write-Host ("Vigie est a jour : " +
            $(if ($apres -and $apres.version) { $apres.version } else { 'version inconnue' }) +
            $(if ($apres -and $apres.commit) { " (" + $apres.commit.Substring(0, 8) + ")" } else { "" })) -ForegroundColor Green
exit 0
