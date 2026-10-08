# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    install.ps1 -- lays down the prerequisites. IDEMPOTENT. Targets PowerShell 7.

    Intent: take a computer from nothing at all to a Vigie that runs by itself -- PowerShell 7, the modules, the
    installation folder, the service account, the scheduled tasks -- and be runnable AGAIN at any time without
    doing harm, because that is also how an update is applied.

    Usage: `powershell -File .\install.ps1` (it switches itself to pwsh), or the button on the Deployment card,
    which passes -Requester and -FromAction. It logs into backend/logs/install_*.log (a transcript). The file is
    written in ASCII so that it stays readable by PowerShell 5.1 at the moment of switching to pwsh.

    The scope of the modules:
      - elevated (admin) -> AllUsers: C:\Program Files\PowerShell\Modules (visible to EVERY PowerShell 7: MSI,
                            Store, a scheduled task, elevated or not). Recommended.
      - not elevated     -> CurrentUser (the fallback).
#>
param(
    <#
        WHO IS ASKING. From the card's button the installation runs under the service's account: it has no session
        to deduce it from. The server passes it the account of the person who clicked, because it is in THEIR
        session that the version tag will be laid -- in THEIR repository, under THEIR identity (D112).
    #>

    [string] $Requester,

    # Redo the whole sequence even if the installation is already up to date.
    [switch] $Force,

    <#
        WHERE TO INSTALL. Empty = wherever it already is, otherwise the default.

        The choice happens at the FIRST installation only: afterwards the folder in place
        wins, and asking again would suggest Vigie can move from one update to the next --
        which would leave two installations on the computer.
    #>
    [string] $InstallPath,

    <#
        NO WINDOW AT THE END. The server has no desktop: a window opened from its session would show up nowhere,
        and would wait for a click nobody can give. The verdict, for its part, goes into the log as usual.
    #>

    [switch] $NoWindow,

    <#
        THE ACTION THAT STARTED ME -- WHOSE BUSY MARK IS MY OWN.

        From the card's button, the server app lays down an "an operation is running" mark BEFORE starting the
        installation, so that the card shows it and nothing else starts at the same time. The installation, for its
        part, refuses to run while an operation is under way -- and therefore found its OWN. It forbade itself, and
        returned code 5 (observed on 31/08: a failure reported with exit code 5).

        We do not remove the check: it is what prevents interrupting a disc analysis. We take out of it the one
        operation we know IS us.
    #>


    [string] $FromAction
)

$ErrorActionPreference = 'Stop'

# THE SAME DISPLAY AS EVERYWHERE. Loaded from the start, before even the switch to PowerShell 7: this first pass
# runs under 5.1, and it already displays.
. (Join-Path $PSScriptRoot 'lib/console-ui.ps1')

# --- Target PowerShell 7: switch over if started under 5.1 ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # The MACHINE's interpreter first: it is the one the start-up tasks will run, so it is the one to install
    # with.
    $pwsh = Join-Path (Join-Path (Join-Path $env:ProgramFiles 'PowerShell') '7') 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwsh)) {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    }
    if ($pwsh) {
        Write-Info (Get-Label 'install.bascule-en-powershell')
        # THE PARAMETERS FOLLOW THE SWITCH. Without this, -Requester and -Force were lost on the way into
        # PowerShell 7, and the second pass no longer knew who had asked.
        # RAW VALUES: the call operator quotes each argument itself (D116).
        $nextArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($Requester) { $nextArgs += @('-Requester', $Requester) }
        if ($Force)     { $nextArgs += '-Force' }
        if ($NoWindow)  { $nextArgs += '-NoWindow' }
        if ($FromAction) { $nextArgs += @('-FromAction', $FromAction) }
        # THE CHOSEN FOLDER CROSSES THE SWITCH TOO: it was dropped here, and the second pass installed in the default.
        if ($InstallPath) { $nextArgs += @('-InstallPath', $InstallPath) }
        & $pwsh @nextArgs
        # THE EXIT CODE OF THE PASS WE STARTED IS OURS. Without this line, a failure of the real installation came
        # back as a success to the caller: the launcher displayed "finished" on a failed installation (observed on
        # 26/08).
        exit $LASTEXITCODE
    }
    Write-Step (Get-Label 'install.powershell-est-absent-installation')
    # ELEVATION is indispensable here: an installation in machine scope without administrator rights fails on
    # "0x80070005: Access is denied" -- and since winget has already removed whatever version the account had, the
    # machine ends up WITHOUT PowerShell 7 at all (lived through on 26/08). We say so BEFORE trying, rather than
    # leaving that hole.
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

    # 1) winget, imposing the MSI.
    #
    # Two traps met on 26/08, in this order:
    #   - without --installer-type msi, winget takes the MSIXBUNDLE and tries to "provision" it for every account:
    #     failure 0x80070005 -- and it had ALREADY uninstalled the account's version, so the machine found itself
    #     with no PowerShell at all;
    #   - with --installer-type msi, the winget source has NO MSI package for that identifier: it sweeps every
    #     version then gives up (0x8a150010).
    # Hence the fallback below. An installer must GET THERE, not send the user off to a download page.

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.PowerShell -e --scope machine --installer-type msi --source winget --accept-package-agreements --accept-source-agreements
    }

    # 2) The fallback: the MSI published by the PowerShell team, installed for the WHOLE machine.
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Warn (Get-Label 'install.winget-pas-de-paquet')
        try {
            # TLS 1.2: Windows PowerShell 5.1 does not always switch it on, and GitHub refuses everything else.
            # Without this line the download fails on a connection error that explains nothing.
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
                                     -Headers @{ 'User-Agent' = 'Vigie-install' } -TimeoutSec 60
            $asset = @($rel.assets | Where-Object { $_.name -like '*-win-x64.msi' }) | Select-Object -First 1
            if (-not $asset) { throw "aucun MSI x64 dans la derniere version publiee" }
            $msi = Join-Path $env:TEMP $asset.name
            # WITHOUT THIS, Windows PowerShell 5.1 bogs down: rendering its progress bar costs more than the
            # download itself, and over 108 MB the command seems frozen for long minutes AFTER the file is complete
            # -- observed on 26/08, the whole file on disc and the script still waiting. It is a known defect of
            # 5.1; we switch the bar off.
            $ProgressPreference = 'SilentlyContinue'
            $mo  = [math]::Round(([double]$asset.size) / 1MB, 1)
            # Already downloaded AND complete? We do not start again: an earlier attempt may have stumbled
            # afterwards (see above).
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
            # ALLUSERS=1: a MACHINE installation. /qb and not /qn: an installation that takes two minutes must be
            # SEEN. A progress bar is better than a silent window of which one cannot tell whether it is working or
            # stuck.
            $mi = Start-ChildProcess -FilePath 'msiexec.exe' `
                      -Arguments @('/i', $msi, '/qb', 'ALLUSERS=1', 'ADD_PATH=1') `
                      -Options @{ Wait = $true; PassThru = $true }
            # THE RESULT IS READ. 0 = installed; 3010 = installed, a restart is asked for; 1618 = another installer
            # is already at work; anything else is a failure that must be named, not passed over in silence.
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

    # 3) We OBSERVE, and carry on by ourselves: the user has nothing to start again.
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

# The management scripts live in scripts/: the apps are in apps/.
$repoRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'   # BOOTSTRAP, cf. common.ps1
. (Join-Path $backend 'lib/common.ps1')

<#
    THE LOG BEGINS BEFORE THE FIRST STEP.

    It used to start in the middle: the computer's declaration, the source and the DEPLOYMENT happened before, so
    outside the log. On 30/08 the installation ended on "2 step(s) failed" while the file did not hold a single line
    of error -- enough to spend a long time looking for what was not in it.

    A log that begins after the beginning is useless: the beginning is precisely what one reads back when things go
    wrong.
#>

$logDir = Get-LogDir -Backend $backend
$log    = Join-Path $logDir ('install_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }

<#
    ONE INSTALLATION AT A TIME.

    Two simultaneous installations tread on each other: one stops what the other has just started, one copies while
    the other is backing up. We refuse, and we say WHO holds the lock -- otherwise "an installation is already
    under way" looks like a breakdown.

    A lock whose process no longer exists is ignored: a crash must not condemn the workstation.
#>

$verrou = Lock-Install
if (-not $verrou) {
    $qui = Get-InstallLockHolder
    Write-Title (Get-Label 'install.titre')
    # THE TIME IS READ IN LOCAL TIME. The lock stores it in UTC (a mark, not a display); as it stood it announced
    # "since 04:54" at 06:54, that is, an installation begun two hours earlier -- enough to believe in a forgotten
    # lock.
    $depuis = "$($qui.at)"
    try { $depuis = ([datetime]::Parse($qui.at)).ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss') } catch { }
    Write-Fail (Get-Label 'install.deja-en-cours' "$($qui.account)" "$($qui.pid)" $depuis)
    try { Stop-Transcript | Out-Null } catch { }
    exit 4
}


<#
    INSTALLING OR UPDATING: IT IS NOT THE SAME PIECE OF NEWS.

    The same script does both -- deliberately, it is idempotent and it is the ONLY gesture to know. But it
    announced "Installation de Vigie" even when a version was already running, without saying which one nor what
    we were heading for: one started it again without knowing whether anything was changing.

    So we look at what is in place BEFORE beginning, and we say it: where we start from, where we are going, and in
    which environment -- development or production, as DECLARED.
#>


$current = $null
try {
    $installedPath = Get-SharedInstallPath
    if ($installedPath) { $current = Get-BuildStamp -Root $installedPath }
} catch { }
$incoming = $null
try { $incoming = Get-BuildStamp -Root $repoRoot } catch { }
<#
    THE VERSION WE ARE LAYING DOWN: ONE SINGLE VALUE, FROM BEGINNING TO END.

    It was recomputed at every place that spoke of it, and each one landed on a different answer: the log announced
    "towards v0.1.37" -- the version that would be tagged -- while the closing window said "v0.1.36 to v0.1.36+8",
    read before the tag was laid. The same deployment told two stories (observed on 31/08).

    So we PREDICT it here, before beginning -- it is the tag that will be marked -- then we OBSERVE it after the
    copy, on what is really in place. The observation always wins: it is the only one that cannot be wrong.
#>


$versionPosee = $null
$isUpdate = [bool]($current -and $current.version)

# TWO CALLS WRITTEN OUT rather than a computed key: a checker cannot judge a key built at run time, and that is
# the open door to a "[?...]" in production.
if ($isUpdate) { Write-Title (Get-Label 'install.titre-maj') }
else            { Write-Title (Get-Label 'install.titre') }
if ($isUpdate) {
    # THE VERSION ANNOUNCED IS THE ONE THAT ARRIVES: "v1.1.5+3" in dev, since a deployment tags nothing (D123).
    # RUN FROM THE INSTALLATION ITSELF -- the update the server app starts -- the stamp read here is the one in place,
    # not the one coming: the log said "from v1.1.6+23 to v1.1.6+23" and installed v1.1.6+25 (18/09). The version
    # arriving is then known only once built from the repository, and it is stated after the copy.
    $runFromInstall = $false
    try { $runFromInstall = ($installedPath -and ((Resolve-Path -LiteralPath $repoRoot).Path.TrimEnd([char]92) -eq (Resolve-Path -LiteralPath $installedPath).Path.TrimEnd([char]92))) } catch { }
    if ($incoming -and $incoming.version -and -not $runFromInstall) { $versionPosee = "$($incoming.version)" }
    if ($versionPosee) { Write-Info (Get-Label 'install.de-vers' $current.version $versionPosee) }
    else               { Write-Info (Get-Label 'install.de-vers-depot' $current.version) }
}
# PROD IS THE DEFAULT, WE DO NOT ANNOUNCE IT. The application is a production one first: saying so every time
# teaches nothing. It is the development stage that deserves to be pointed out -- with what it implies: a local
# source, and versions tagged here.
if ((Get-DeclaredStage -Backend $backend) -eq 'dev') {
    Write-Info (Get-Label 'install.stage-dev')
}
Write-Step (Get-Label 'install.etape-prerequis')

# --- VIGIE INSTALLS ITSELF INTO PROGRAM FILES -------------------------------
#
# A Windows application lives in Program Files, not in the folder where the archive was unpacked. Without this
# copy, the start-up task pointed at that folder: the user had to keep it for ever, and emptying it by mistake
# broke Vigie.
#
# Three cases WHERE WE DO NOT MOVE:
#   - a git REPOSITORY: this is a development workstation, Vigie runs from the sources;
#   - we are already there: the copy would restart the script endlessly;
#   - without elevation: writing into Program Files is refused. We say so, and carry on in place rather than
#     failing -- Vigie stays usable.
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
# THIS COMPUTER'S REPOSITORY, or $null. One single definition, in the library: the question "am I inside a
# repository?" is not asked again here, and above all it no longer decides anything -- it serves ONLY to note
# where the installation comes from.
$repoLocal  = Get-LocalRepoPath -Backend $backend
$alreadyThere       = ($here.TrimEnd([char]92) -ieq $destPartagee.TrimEnd([char]92))

<#
    AN INSTALLATION STARTED FROM A REPOSITORY NOTES WHERE IT COMES FROM.

    This is a developer's FIRST gesture on a new workstation, and it runs under THEIR account, in THEIR repository.
    So we note the path of the source there, and declare that folder trusted for git.

    Without that declaration the server app -- which runs under a service account -- cannot even CLONE that
    repository: git refuses to open a folder belonging to somebody else. The "Mettre a jour" button would therefore
    fail before any first deployment, and the developer would have no way of understanding why.

    THE ENVIRONMENT IS NOT DEDUCED HERE: it is declared (config.local.psd1). Finding a repository does not make a
    workstation a development machine.
#>


<#
    THE COMPUTER'S DECLARATION ALWAYS EXISTS.

    It was written only if the installation started from a repository: elsewhere the file did not exist and the
    stage was prod by default only, with nothing to say so. A setting one sees nowhere is a setting one does not
    know how to change.

    So we write it at every installation, with the stage SPELLED OUT -- without ever touching a value already
    declared: that file belongs to whoever filled it in.
#>
<#
    WE DO NOT INTERRUPT AN OPERATION UNDER WAY.

    A disc analysis, an installation of Windows updates: stopping them halfway leaves a job half done, and that is
    exactly what the busy marks are there to avoid. We refuse, NAMING what is running.
#>

$enCours = @()
try { $enCours = @(Get-RunningOperations -Backend $backend) } catch { }
# OUR OWN MARK DOES NOT STOP US.
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
        $previousSource = ''
        try { $previousSource = "$((Get-Config -Backend $backend).SourcePath)" } catch { }
        $noteA = Set-ComputerConfigValue -Values @{ SourcePath = $repoLocal }
        Write-Detail (Get-Label 'install.source-notee' $repoLocal $noteA)
    } catch {
        Write-Warn (Get-Label 'install.source-non-notee' $_.Exception.Message)
    }
    if (Test-Elevated) {
        try {
            if (Set-GitSafeDirectory -RepoPath $repoRoot) { Write-Ok (Get-Label 'install.depot-de-confiance' $repoRoot) }
            else { Write-Detail (Get-Label 'install.depot-deja-de-confiance') }
            # THE PREVIOUS SOURCE LOSES ITS TRUST: declarations piled up, one pair per source ever used (13/09).
            if ($previousSource -and $previousSource.TrimEnd([char]92, [char]47) -ine $repoRoot.TrimEnd([char]92, [char]47)) {
                if (Remove-GitSafeDirectory -RepoPath $previousSource) { Write-Detail (Get-Label 'install.ancienne-source-retiree' $previousSource) }
            }
            # EVERY OTHER TRUST VIGIE POSED is taken back: only the declared source keeps one (14/09).
            $stale = @(Remove-StaleGitSafeDirectory -KeepPath $repoLocal)
            if ($stale.Count) { Write-Detail (Get-Label 'install.confiance-perimee-retiree' ($stale -join ', ')) }
        } catch {
            Write-Warn (Get-Label 'install.confiance-impossible' $_.Exception.Message)
        }
    } else {
        # Without elevation we cannot write the machine's git configuration. We SAY SO: that is exactly what would
        # make the update button inexplicable.
        Write-Warn (Get-Label 'install.confiance-demande-elevation')
    }
}

<#
    FROM A REPOSITORY, THE INSTALLATION DEPLOYS -- IT DOES NOT MERELY PREPARE.

    "The installation must install EVERYTHING, the app is ready afterwards." Yet started from a repository it
    copied NOTHING: it laid the tasks, announced "from v0.1.31 to v0.1.31+8"... and the shared installation stayed
    at v0.1.31. No version tagged either, since it is the deployment that lays the tag.

    So we call the update, which is the ONLY implementation of the gesture: it tags the version, builds the archive
    from the declared source, deploys, and restarts. We are running here under the person's account, in their
    repository: the tag has an author.

    Code 3 = "already up to date": that is not a failure (D77), we carry on.
#>

<#
    FETCH, STOP, BACK UP, LAY DOWN, VERIFY -- IN THAT ORDER.

    This is the target sequence (doc/progress/targeting/install-update.md). It holds for both entry points,
    `setup.cmd` and the card's button: what decides a step are FACTS -- is there an installation in place, a
    repository, which source is declared -- never who is calling.

    THE ORDER IS NOT ARBITRARY. We fetch BEFORE stopping anything at all: the building is what takes the longest,
    and Vigie has no reason to be cut off during it. We stop only afterwards, for the time it takes to lay the
    files down.
#>

<#
    WE FETCH EVEN WHEN WE ARE NOT INSIDE A REPOSITORY.

    This step fired only if the current folder was a git repository. From the card's BUTTON, the installation runs
    from the shared installation -- Program Files, no .git: so it fetched NOTHING, deployed nothing, and ended in
    success. "The app is still on 0.1.36 instead of 0.1.37" (observed on 31/08): it had never had a version to lay
    down.

    Where the code comes from is not deduced from where one starts: it is a DECLARED SETTING (D99). vigie-update
    already knows how to read it -- a clone of the declared repository, or the latest published version -- and
    knows how to say "already up to date" (code 3). We leave the decision to it.

    The one exception: a first installation from an archive laid down by hand, where there is neither a repository,
    nor a declared source, nor anything to look for.
#>

$prepared = $null
<#
    FETCHING THE VERSION TO LAY DOWN -- HERE, AND NOWHERE ELSE.

    It used to be a separate script, vigie-update.ps1, called as a child process and whose LAST LINE was read to
    learn the folder. An exit contract between two scripts of the same repository, when they make one single
    gesture: on 31/08 this script relayed to another copy of itself whose output did not come back, the
    installation read a line of information instead of a path, and fifty-six seconds of building went into the bin.
    Its disappearance had been decided; it is done.

    The step runs BEFORE any stop: building is the long part, and Vigie has no reason to be cut off during it.
#>


$aRecuperer = $false
try { $aRecuperer = [bool](Get-UpdateRoute -Backend $backend).route } catch { }
if ($aRecuperer) {
    Write-Step (Get-Label 'install.etape-recuperation')

    # THE MACHINE'S CHOICE. A development workstation may want to behave like a user's machine (UpdateSource =
    # 'release'), or the other way round.
    $updateSource = 'auto'
    $updateRef = ''
    try {
        $cfgMaj = Get-Config -Backend $backend
        $choix = "$($cfgMaj.UpdateSource)".Trim()
        if ($choix -and @('auto','release','clone') -contains $choix) {
            $updateSource = $choix
            # We announce only what CHANGES something: 'auto' is the default.
            if ($choix -ne 'auto') { Write-Detail (Get-Label 'vigie-update.source-imposee-par-la' $choix) }
        }
        if ("$($cfgMaj.UpdateRef)".Trim()) { $updateRef = "$($cfgMaj.UpdateRef)".Trim() }
    } catch { }

    # THE CARD AND THE BUTTON READ THE SAME RESOLUTION (Get-UpdateRoute): without that, the card announces one
    # reference and the button goes looking elsewhere.
    $route = $updateSource
    if ($route -eq 'auto') {
        if ($updateRef) { $route = 'clone' }
        else {
            $resolu = $null
            try { $resolu = Get-UpdateRoute -Backend $backend } catch { }
            $route = $(if ($resolu -and $resolu.route) { $resolu.route } else { 'release' })
        }
    }

    # A DEPLOYMENT TAGS NOTHING (D123): 93 tags in three weeks, one per deployment, where 10 to 20 were expected. A tag
    # marks a stable validated version, at its publication, through the action tag-version.

    # THE BUILDING stays a separate script: it has its own business -- git, the archive, checking the contents --
    # and it also serves to build a release by hand.
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
        # The output is READ: the last line carries the path of the archive. The rest is narrative, which we repeat
        # so that the log keeps a trace of it.
        $lignesFetch = & (Get-Process -Id $PID).Path @argv 2>&1
        $codeFetch = $LASTEXITCODE
        foreach ($l in $lignesFetch) {
            Write-Relayed "$l"
            try { Write-Log -Backend $backend -Name 'install' -Message "$l" -NoEcho } catch { }
        }

        if ($codeFetch -eq 3) {
            # ALREADY UP TO DATE: that is a success, and there is nothing to lay down.
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
    A FETCH THAT FAILS STOPS THE INSTALLATION.

    This fallback exists for the case "there was NOTHING to fetch": an archive extracted by hand, whose current
    folder IS the version to lay down. It also fired when the fetch had been ATTEMPTED and MISSED -- the
    installation then laid down the folder it was running from, that is, the development repository.

    Observed on 01/09: the building of v0.1.44 fails, the installation carries on, stops Vigie, backs up, copies
    the repository over the installation, observes "version laid down v0.1.43 instead of v0.1.44" and restores. All
    that work, and that risk, for a failure known twenty lines earlier.

    So we fall back only if we have attempted NOTHING.
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
        # THE CLIENT APPS ARE ASKED FIRST, and quit on their own with a line in their log; the tasks are ended and what
        # remains is stopped only for the ones that did not answer. A failure is reported, it does not stop the deployment.
        try {
            $quitClean = @(Request-ClientStop -Backend $backend)
            if ($quitClean.Count) { Write-Detail (Get-Label 'install.app-clientes-parties' ($quitClean -join ', ')) }
        } catch { }
        try {
            $stopped = @(Stop-ClientTasks -Backend $backend)
            if ($stopped.Count) { Write-Detail (Get-Label 'install.app-clientes-arretees' (($stopped | ForEach-Object { $_.name }) -join ', ')) }
        } catch { Write-Warn (Get-Label 'install.arret-app-clientes-impossible' $_.Exception.Message) }
        $hors = 0
        try { $hors = Stop-StandaloneClients } catch { }
        if ($hors -gt 0) { Write-Detail (Get-Label 'install.app-clientes-hors-tache' $hors) }

        # THE SERVER APP: if it still holds the port after the forced stop, we lay nothing down -- replacing its
        # files underneath it is exactly what we are avoiding.
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
            # AND THE IDENTITY THE NOTIFICATIONS ARE SENT UNDER, for the same reason and at
            # the same moment: it names the delivered icon, which only exists now that the
            # copy is done. A failure here costs a name on a bubble, never the install.
            try { $null = Set-VigieToastIdentity -InstallPath $destPartagee } catch { }
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
            # WHAT IS IN PLACE, READ IN PLACE: the prediction is no longer of any use.
            try {
                $stampPose = Get-BuildStamp -Root $destPartagee
                if ($stampPose -and $stampPose.version) { $versionPosee = "$($stampPose.version)" }
            } catch { }
            if ($backup) {
                # THE BACKUP EXISTS ONLY FOR AS LONG AS THE RISK DOES.
                Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
            }
            # THE BACKUPS LEFT BY EARLIER FAILED COPIES GO TOO, once a copy is valid: one stayed per version that failed,
            # a whole Vigie each, and nothing ever purged them (inventory of 13/09).
            Get-ChildItem -LiteralPath (Get-InstallBackupRoot -Backend $backend) -Directory -Filter 'installation-*' -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        } else {
            Write-Fail (Get-Label 'install.copie-invalide' $pose)
            if ($backup) {
                # A STEP OF ITS OWN: restoring is not "laying down". It is the net being spread, and that must show
                # as such in the sequence.
                Write-Step (Get-Label 'install.etape-restauration')
                try {
                    Restore-Install -Backup $backup -Destination $destPartagee
                    Write-Warn (Get-Label 'install.version-restauree')
                } catch {
                    # NO AUTOMATIC RECOVERY: we say where the backup is.
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

    # The reference AllUsers path (shared by every PS7).
    $allUsersPode = Join-Path $env:ProgramFiles 'PowerShell\Modules\Pode'

    if ($isAdmin) {
        # As an admin: we guarantee an AllUsers copy, visible to every PS7.
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

    # --- A DEPENDENCY: PowerShell 7 must be installed FOR THE MACHINE -----------
    # Vigie starts through a scheduled task, one per account. A pwsh installed for the current account alone (the
    # Store package) lives in ITS profile: the other accounts' tasks would point into a folder they cannot read. We
    # deal with it HERE, at installation time, rather than discovering it the day an account fails to start.
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

    # THE TRACE BEFORE THE RIGHTS. Laying down the event log's source demands elevation: so it happens here, once,
    # and not at the first use. Without it, a privileged action would leave a trace in a file only -- an erasable
    # one.
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

    # --- THE INSTALLATION GOES ALL THE WAY ---------------------------------------
    # "The install script is supposed to do everything": so it does not stop at the prerequisites to send the user
    # off to two other commands. It registers the automatic start and launches the application.
    #
    # It is also what REPAIRS an existing task: it is rewritten with the machine's interpreter. On 26/08 the task
    # pointed at the Store package's pwsh, deleted in the meantime -- Vigie no longer started at all, and nothing
    # said so.
    # THE MACHINE SERVICE, prepared but not enabled. One single installation: this is where the new pieces arrive,
    # and idempotence is what makes the difference between a first laying down and an update. The task is created
    # DISABLED -- nothing changes at start-up until the switch-over is made.



    $service = Join-Path (Join-Path $PSScriptRoot 'lib') 'install-service.ps1'
    if ($isAdmin -and (Test-Path -LiteralPath $service)) {
        try {
            # WE KEEP WHAT THE STEP DISPLAYS. "| Write-Host" showed it and lost it: the log of 29/08 stopped at the
            # WebView2 runtime, just before this block, while the screen showed everything that followed. A log
            # that breaks off before the interesting part is useless -- and that is precisely the part one reads
            # back when an installation went wrong.
            # WE CLOSE OUR OWN STEP BEFORE GIVING IT THE FLOOR.
            #
            # That script displays its OWN steps, in its own process. Our conclusion, for its part, arrives only
            # when the next step opens: so it fell AFTER its ones, and the laying down of the new version was left
            # with no visible conclusion (observed on 01/09).


            Close-UiStep
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $service 2>&1 |
                ForEach-Object {
                    $line = "$_"
                    Write-Relayed $line
                    try { Write-Log -Backend $backend -Name 'install' -Message $line -NoEcho } catch { }
                }
            # WE READ THE EXIT CODE. It was logged without being tested: on 28/08 the registration of the task
            # failed and the installation ended in green. A non-zero code is a FAILURE -- Write-Log ERROR counts
            # it, and the final verdict can no longer ignore it.
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
        # -Yes: we are already elevated and the user already consented by starting the installation; a second
        # explanation window would be noise.
        # THE RESULT IS READ: 0 = done, 3 = refused, anything else is a failure.
        # FOR WHOM: from the button, whoever runs is the service; the start-up task belongs to the person who
        # asked.
        $argsAuto = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $autostart, '-Yes')
        if ($Requester) { $argsAuto += @('-Account', $Requester) }
        Close-UiStep   # the same reason: it displays its own steps
        & (Get-Process -Id $PID).Path @argsAuto
        $autostartCode = $LASTEXITCODE
        <#
            THE LAUNCH LINE BELONGS TO EVERY ACCOUNT, NOT ONLY TO WHOEVER ASKED.

            A client app's task carries HOW it is started, and that changed on 29/09: it goes through a headless
            console now, so that no empty terminal shows up at logon and no flash steals the focus during a
            deployment. Rewriting only the requester's task would have left the other accounts with the old line
            until someone installed from there -- that is, on Famille, never.

            A task is re-registered, not repaired: Register-ScheduledTask -Force writes the whole definition, and it
            is idempotent by construction. What it cannot do -- an account that is not allowed a client app -- the
            script itself refuses, as it always has.
        #>
        foreach ($autre in @(Get-EnabledAccounts -Backend $backend | ForEach-Object { "$($_.name)" })) {
            if (-not $autre -or ($Requester -and $autre -ieq $Requester)) { continue }
            try {
                $argsAutre = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $autostart, '-Yes', '-Account', $autre)
                & (Get-Process -Id $PID).Path @argsAutre | Out-Null
                Write-Log -Backend $backend -Name 'install' -Message ("demarrage automatique reecrit pour " + $autre + " (code " + $LASTEXITCODE + ")")
            } catch {
                Write-Log -Backend $backend -Name 'install' -Level 'WARN' -Message ("demarrage automatique, compte " + $autre + " : " + $_.Exception.Message)
            }
        }
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
        THE OTHER ACCOUNTS' TASKS ARE REPAIRED TOO.

        The previous step registers the current account's only. The others may still point at an old location -- it
        happened on 30/08, where the task started the repository instead of the shared installation -- and nobody
        would ever fix them.

        Re-registering them is idempotent: it is the same gesture as enabling them.
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
        WE RESTART WHAT WE STOPPED.

        The other accounts' client apps were stopped so as not to replace their files underneath them; the current
        account's has just been restarted by its task. So we trigger the others -- which an administrator can do.

        A client app's task is INTERACTIVE: without a session open on that account, Windows refuses. That is not an
        error, its app will set off again at its next logon, with the new code.
    #>

    if ($stopped -and @($stopped).Count) {
        $me = Get-ProcessAccount
        $toStart = @($stopped | Where-Object { "$($_.name)" -ne $me })
        if ($toStart.Count) {
            $restarted = @(Start-ClientTasks -Accounts $toStart)
            if ($restarted.Count) { Write-Detail (Get-Label 'install.app-clientes-relancees' ($restarted -join ', ')) }
        }
    }

    <#
        THE CARD MUST NOT STAY ON THE STATE OF BEFORE.

        Two lies observed on 31/08, after a setup.cmd that had gone well: the card announced a shared installation
        at v0.1.33 while the page footer said v0.1.34 -- its rendering came from the cache, computed before the
        deployment -- and it still showed the failure of 09:27 with exit code 5, the result of an earlier attempt,
        as if it described the present state.

        So an installation that succeeds erases the last result of this gesture and has the card recomputed.
        Started from the button, it is the watcher that will write the real result in after us.

        WE CLEAN WHERE THE CARD READS. The var of an installation inside Program Files lives in the profile of the
        account that RUNS, so the SERVICE's -- not ours, while the installation runs under the person who clicked.
        So we aim at both: the service's var, and the one here for the case where Vigie is started from the
        repository.
    #>


    $failuresBeforeVerdict = Get-UiFailureCount
    if ($failuresBeforeVerdict -eq 0) {
        $varRoots = @($null)   # $null = our own var, deduced from the server app
        try {
            $serviceVar = Get-AccountVarRoot -Account (Get-ServiceAccountName)
            if ($serviceVar) { $varRoots += $serviceVar }
        } catch { }
        foreach ($varRoot in $varRoots) {
            try { Remove-ProbeCache -Names @('accounts.probe.ps1', 'deployment.probe.ps1') -Backend $backend -VarRoot $varRoot } catch { }
            try { Clear-ModuleLastRun -Module 'deployment' -Backend $backend -VarRoot $varRoot } catch { }
        }

        <#
            WE RECOMPUTE NOTHING HERE.

            The installation empties the rendering of those two cards -- it described the version from before -- and
            stops there. It is THE PAGE that asks again for a card marked as not yet measured, card by card, when
            somebody looks at it.

            I had made the installation ask for those two cards again: nobody had asked for that, and it is one more
            automatic recomputation -- exactly what was forbidden. An installation installs; it does not measure.
        #>

    }
    # THE VERDICT IS COMPUTED. Write-Outcome counts what Write-Fail and Write-Warn displayed: no installation can
    # end in green any more with a failure behind it.
    $failures = Get-UiFailureCount
    $warnings = Get-UiWarningCount
    Write-Outcome -What (Get-Label 'install.verdict') `
                  -NextStep (Get-Label 'install.verdict-panneau')

    <#
        THE LOCK IS RELEASED HERE: THE INSTALLATION IS FINISHED.

        It used to be given back after the closing window -- which waits for a click. As long as nobody closed it,
        the workstation believed itself to be installing: the card's button answered that an installation was
        already under way and returned code 4, ten minutes after everything was laid down (observed on 31/08: the
        lock held by the pwsh of 10:49, still alive, its window open).

        What follows -- the verdict displayed, a window, a log closed -- changes nothing any more. It is not the
        installation, it is its report.
    #>

    Unlock-Install

    <#
        AND A WINDOW, NOT A "PRESS ANY KEY".

        The installation is started by a double click: it must conclude like an application, not like a script. The
        window says what was done and what remains to be known; the console keeps the detail for whoever wants to
        read it.

        IF IT CANNOT BE SHOWN -- no interface, a session without a desktop -- we block nothing: the conclusion is
        already on the screen, and setup.cmd keeps its pause for the failure cases.
    #>
    try {
        $window = Join-Path $PSScriptRoot 'lib/show-confirm.ps1'
        if ((Test-Path -LiteralPath $window) -and -not $NoWindow) {
            # WE PASS THE KEYS, NOT THE TEXTS: see show-confirm.ps1, accents do not survive a command line.
            <#
                INSTALLATION OR UPDATE: THE WINDOW SAYS SO TOO.

                It announced that Vigie was installed after an update, and its text introduced the product to
                somebody who has been using it for weeks. What one wants to know in that case is what has CHANGED.
            #>

            $titleKey = if ($failures -gt 0) { 'install.fenetre-titre-echec' }
                        elseif ($warnings -gt 0) { 'install.fenetre-titre-reserve' }
                        elseif ($isUpdate) { 'install.fenetre-titre-maj' }
                        else { 'install.fenetre-titre' }
            $summaryKey = if ($failures -gt 0) { 'install.fenetre-resume-echec' }
                          elseif ($isUpdate) { 'install.fenetre-resume-maj' }
                          else { 'install.fenetre-resume' }
            # THE ESSENTIAL IS READ, THE REST UNFOLDS. What one wants to know fits in one sentence; the paths and
            # the task names serve afterwards, if something is wrong.
            # THE URL COMES FROM THE CONFIGURATION, never from a copied constant: the port is a setting, and a text
            # that repeats it ends up lying.
            $url = try { Get-AppUrl -Config (Get-Config -Backend $backend) } catch { '' }
            # The versions, from one to the other: the only detail that counts after an update.
            # THE END WINDOW CONCLUDES: setup.cmd no longer needs to hold the console open on a failure.
            try { [IO.File]::WriteAllText((Join-Path $env:TEMP 'vigie-install-concluded.flag'), (Get-Date).ToString('o')) } catch { }
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
    # WE EXIT IN FAILURE. The block merely displayed the error: the script returned 0, and the launcher carried on
    # as if all was well.
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
finally {
    # THE LOCK IS ALWAYS RELEASED, whatever the road out -- success, failure, or an exception. A forgotten lock
    # blocks every installation that follows.
    try { Unlock-Install } catch { }
    try { Stop-Transcript | Out-Null } catch { }
}
