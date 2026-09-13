# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    install-plan.ps1 - WHAT THE INSTALLATION WILL DO ON THIS MACHINE, computed before anything is asked.

    Why it exists. On 13/09 the window shown before elevation announced an installation during an update,
    named a folder before it was chosen and promised "a startup task for your account only" while the
    installation re-registered every task. Its gestures were written by hand. They are now read from the
    machine: an existing installation, its version, the service account, the scheduled tasks, the missing
    prerequisites. The target: doc/progress/targeting/install-update.md, in its section on the announcement
    window shown before elevation.

    It runs BEFORE elevation, possibly before PowerShell 7 exists: Windows PowerShell 5.1, no library but the
    display and its labels, and it changes nothing.

    Output: a JSON payload for show-confirm.ps1 (-PayloadFile), carrying the scenario, the title, the summary
    and the gestures. Exit codes: 10 = installation, 11 = update, 1 = no plan could be made.
#>
param(
    [string] $InstallPath = '',
    [Parameter(Mandatory)][string] $OutFile
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'console-ui.ps1')

$sep = [string][char]92
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$serviceAccount = 'VigieService'
$serverTask = 'Vigie - Serveur'

function Join-Parts {
    param([string[]]$Parts)
    $path = $Parts[0]
    for ($i = 1; $i -lt $Parts.Count; $i++) { $path = Join-Path $path $Parts[$i] }
    return $path
}

# The same markers as Get-SharedInstallPath: the declared folder first, then Program Files.
function Find-Installation {
    $candidates = @()
    try {
        $key = 'HKLM:' + $sep + (@('SOFTWARE', 'Sowapps', 'Vigie') -join $sep)
        $declared = "$((Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath)"
        if ($declared) { $candidates += $declared }
    } catch { }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $candidates += (Join-Parts @($base, 'Sowapps', 'Vigie'))
        $candidates += (Join-Path $base 'Vigie')
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Parts @($candidate, 'apps', 'tray', 'tray.ps1'))) { return $candidate }
    }
    return $null
}

function Get-Version {
    param([string]$Root)
    try {
        $build = Join-Path $Root 'BUILD'
        if (Test-Path -LiteralPath $build) {
            $stamp = Get-Content -LiteralPath $build -Raw | ConvertFrom-Json
            if ($stamp.version) { return "$($stamp.version)" }
        }
    } catch { }
    try {
        # THE WHOLE OUTPUT FIRST: cutting the pipeline after one line killed git, whose exit code then read -1.
        $lines = @(& git -C $Root describe --tags 2>$null)
        $code = $LASTEXITCODE
        $described = $lines | Select-Object -First 1
        # "v1.1.3-2-gd1f7a64" reads as "v1.1.3+2", as everywhere else in Vigie.
        if ($code -eq 0 -and $described) { return ("$described".Trim() -replace '-(\d+)-g[0-9a-f]+$', '+$1') }
    } catch { }
    return (Get-Label 'install-plan.version-inconnue')
}

try {
    $existing = Find-Installation
    $isUpdate = [bool]$existing
    $target = if ($isUpdate) { $existing } elseif ("$InstallPath".Trim()) { "$InstallPath".Trim() } else { Join-Parts @($env:ProgramFiles, 'Sowapps', 'Vigie') }
    $incoming = Get-Version -Root $repoRoot
    $source = if (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) { Get-Label 'install-plan.source-depot' $repoRoot }
              else { Get-Label 'install-plan.source-archive' $repoRoot }

    $accountExists = $false
    try { $accountExists = [bool](Get-LocalUser -Name $serviceAccount -ErrorAction Stop) } catch { }
    $tasks = @()
    try { $tasks = @(Get-ScheduledTask -TaskName 'Vigie - *' -ErrorAction Stop | ForEach-Object { "$($_.TaskName)" }) } catch { }
    $pwshMissing = -not (Test-Path -LiteralPath (Join-Parts @($env:ProgramFiles, 'PowerShell', '7', 'pwsh.exe')))
    $podeMissing = -not (Test-Path -LiteralPath (Join-Parts @($env:ProgramFiles, 'PowerShell', 'Modules', 'Pode')))

    $gestures = @()
    if ($isUpdate) {
        $gestures += Get-Label 'install-plan.arret'
        $gestures += Get-Label 'install-plan.remplacement' $target
    } else {
        $gestures += Get-Label 'install-plan.copie' $target
    }
    if ($accountExists) { $gestures += Get-Label 'install-plan.compte-repris' $serviceAccount }
    else                { $gestures += Get-Label 'install-plan.compte-cree' $serviceAccount }
    if ($isUpdate) {
        $named = @(@($serverTask) + @($tasks | Where-Object { $_ -ne $serverTask }) | Select-Object -Unique)
        $gestures += Get-Label 'install-plan.taches' ($named -join ', ')
        # WITHOUT ELEVATION, THE TASKS OF OTHER ACCOUNTS ARE HIDDEN: they are re-registered all the same, so the plan says so
        # rather than naming only what it can see.
        $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $elevated) { $gestures += Get-Label 'install-plan.taches-autres' }
    } else {
        $gestures += Get-Label 'install-plan.tache-serveur' $serverTask
        $gestures += Get-Label 'install-plan.tache-compte' ('Vigie - ' + $env:USERNAME)
    }
    if ($pwshMissing) { $gestures += Get-Label 'install-plan.pwsh' }
    if ($podeMissing) { $gestures += Get-Label 'install-plan.pode' }

    if ($isUpdate) {
        $payload = [ordered]@{
            scenario = 'mise-a-jour'
            title    = Get-Label 'install-plan.titre-maj'
            summary  = Get-Label 'install-plan.resume-maj' (Get-Version -Root $target) $incoming $source
        }
    } else {
        $payload = [ordered]@{
            scenario = 'installation'
            title    = Get-Label 'install-plan.titre'
            summary  = Get-Label 'install-plan.resume' $incoming $target
        }
    }
    $payload.changes = ($gestures -join '|')
    $payload.installPath = $target
    [IO.File]::WriteAllText($OutFile, ($payload | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
    if ($isUpdate) { exit 11 }
    exit 10
} catch {
    Write-Fail (Get-Label 'install-plan.echec' $_.Exception.Message)
    exit 1
}
