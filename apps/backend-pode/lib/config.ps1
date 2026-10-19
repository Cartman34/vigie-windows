# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses: log, paths, var
<#
    Intent: THE CONFIGURATION, read once and derived here: the port, the api base, the addresses the panel and the client app use, the api token, the external toolkit. A value derived from the config is computed HERE and nowhere else.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# config.psd1, which is versioned, carries THE definition of every value.
# config.local.psd1, ignored by git and optional, overrides ONLY the values that cannot be
# generic: paths belonging to one machine. See config.local.sample.psd1.
<#
    WHAT DESCRIBES THE MACHINE IS STORED ON THE MACHINE.

    config.local.psd1 announces itself as "the settings belonging to THIS MACHINE"... and
    lives IN EVERY COPY. On a development workstation the repository had one, saying "dev",
    and the shared installation had none, so it said "prod". One machine, two contradictory
    answers to "is this a development workstation?", and the installation answering NO on the
    very machine where everything is developed.

    What describes the MACHINE now lives in one place, outside every copy:
    %ProgramData%\Sowapps\Vigie\machine.psd1. All the copies read it, none of them owns it,
    and a deployment can no longer erase it.

    config.local.psd1 keeps its role -- what belongs to THIS COPY, a test port or a path to a
    toolkit -- and remains the most specific layer.
#>
# THE SERVER TASK'S NAME, once and only once. It lived in install-service.ps1, which the
# server does not load: the restart therefore could not know who owns the process it stops.
function Get-ServiceTaskName { return 'Vigie - Serveur' }

function Get-ComputerDataRoot {
    <#
        THIS COMPUTER'S FOLDER: %ProgramData%\Sowapps\Vigie.

        It depends on NO installation, and that is what matters: whatever must survive the
        replacement -- or the disappearance -- of the installed folder is stored here, never
        under the installation itself.
    #>
    $base = $env:ProgramData
    if (-not $base) { $base = Join-Path $env:SystemDrive 'ProgramData' }
    return (Join-Path (Join-Path $base 'Sowapps') 'Vigie')
}

function Get-ComputerConfigPath {
    <#
        NOT TO BE CONFUSED with Get-MachineConfigPath, which already exists further down and
        names the settings DELIVERED in the repository (config/<file>). I had reused its
        name: my definition was silently overwritten by its own, and the call failed on a
        mandatory parameter that was not mine. Two notions, two names.
    #>
    return (Join-Path (Get-ComputerDataRoot) 'machine.psd1')
}

function Get-Config {
    param([string]$Backend = (Get-BackendRoot))
    # Merged in FOUR layers (D33), from the most general to the most specific:
    #   config/common.psd1  ->  apps/<app>/config/config.psd1  ->  machine.psd1  ->  config.local.psd1
    $cfg = @{}
    $commonPath = Join-Path (Get-RepoRoot) 'config/common.psd1'
    if (Test-Path -LiteralPath $commonPath) {
        try { (Import-PowerShellDataFile -Path $commonPath).GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value } }
        catch { throw ("config/common.psd1 illisible : " + $_.Exception.Message) }
    }
    $appCfg = Import-PowerShellDataFile -Path (Join-Path $Backend 'config/config.psd1')
    foreach ($k in $appCfg.Keys) { $cfg[$k] = $appCfg[$k] }
    # THE MACHINE, before the copy: what it declares holds for all its installations.
    $computerPath = Get-ComputerConfigPath
    if (Test-Path -LiteralPath $computerPath) {
        try {
            $computerCfg = Import-PowerShellDataFile -Path $computerPath
            foreach ($k in $computerCfg.Keys) { $cfg[$k] = $computerCfg[$k] }
        } catch { throw ("machine.psd1 illisible (" + $computerPath + ") : " + $_.Exception.Message) }
    }
    $localPath = Join-Path $Backend 'config/config.local.psd1'
    if (Test-Path -LiteralPath $localPath) {
        try { $local = Import-PowerShellDataFile -Path $localPath }
        catch { throw ("config.local.psd1 illisible (" + $localPath + ") : " + $_.Exception.Message) }
        foreach ($k in $local.Keys) { $cfg[$k] = $local[$k] }
    }
    $cfg
}

<#
    DECLARING WHAT THIS MACHINE IS.

    Written by the installation and by the deployment, when they start from a REPOSITORY: it
    is a fact observed at the moment of acting, not a setting to type in. Only the keys being
    brought are overwritten -- the rest of the file belongs to whoever wrote it.
#>
function Set-ComputerConfigValue {
    param([Parameter(Mandatory)][hashtable]$Values)
    $path = Get-ComputerConfigPath
    $dir  = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cfg = [ordered]@{}
    if (Test-Path -LiteralPath $path) {
        try {
            $previous = Import-PowerShellDataFile -Path $path
            foreach ($k in $previous.Keys) { $cfg[$k] = $previous[$k] }
        } catch { }
    }
    foreach ($k in $Values.Keys) { $cfg[$k] = $Values[$k] }

    $lines = @('@{')
    $lines += "    # Ce que cette MACHINE est, pour TOUTES ses installations de Vigie."
    $lines += "    # Ecrit par Vigie au deploiement ; modifiable a la main."
    foreach ($k in $cfg.Keys) {
        $v = $cfg[$k]
        $rendered = if ($v -is [bool]) { if ($v) { '$true' } else { '$false' } }
                 elseif ($v -is [int] -or $v -is [long]) { "$v" }
                 else { "'" + ("$v" -replace "'", "''") + "'" }
        $lines += ("    {0} = {1}" -f $k, $rendered)
    }
    $lines += '}'
    [System.IO.File]::WriteAllText($path, ($lines -join [Environment]::NewLine),
                                   (New-Object System.Text.UTF8Encoding($true)))
    return $path
}

# --- Values derived from the config: defined HERE and nowhere else -----------
# The address and the port exist once (config.psd1); every URL derives from them.
function Get-AppUrl {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    'http://{0}:{1}/' -f $Config.BindAddress, $Config.Port
}
function Get-ApiUrl {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    'http://{0}:{1}{2}' -f $Config.BindAddress, $Config.Port, $Config.ApiBase
}

# --- Optional external toolkit (administration scripts outside the repository) -------
# An empty or missing ToolsPath gives $null, and the actions concerned return a clear
# message instead of failing obscurely.
function Get-ToolsPath {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    if (-not $Config) { $Config = Get-Config -Backend $Backend }
    $p = [string]$Config.ToolsPath
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    (Resolve-Path -LiteralPath $p).Path
}
function Get-AdminRoot {
    param([string]$Backend = (Get-BackendRoot), [hashtable]$Config)
    $tools = Get-ToolsPath -Backend $Backend -Config $Config
    if (-not $tools) { return $null }
    Split-Path $tools -Parent
}
# The common answer when the external toolkit is not configured (written once).
# The common answer of the actions that STILL depend on a configured toolkit path.
# Since the Windows Update locking and the VBS / HVCI switches became native, the only one
# left is "open the folder" -- and its probe no longer even offers the button when the path
# is missing. This guard covers the case where the folder disappears between the card being
# displayed and the click.
function New-ToolsMissingResult {
    @{
        message = "Aucun dossier d'outillage n'est configuré. Renseignez ToolsPath dans apps/backend-pode/config/config.local.psd1 (modèle : config.local.sample.psd1)."
        result  = @{ ok = $false }
    }
}

function Get-ApiToken {
    <#
        THE SERVER'S TOKEN LIVES AT THE SERVER'S.

        Without "-VarRoot", this function returns the token of WHOEVER RUNS IT: launched by
        the installation, under the person's account, it returned fhaza's token and the
        server answered 401. The two cards the installation asked to recompute therefore
        never were (seen on 01/09).
    #>
    param([string]$Backend = (Get-BackendRoot), [string]$VarRoot)
    $dir  = Get-VarPath -Backend $Backend -VarRoot $VarRoot -Kind 'secrets'
    $file = Join-Path $dir 'api.token'
    # ITS OWN TOKEN IS HELD UNDER TARGET C7: rights set, checked at each read, reissued if a third party reached it.
    # Another account's token (-VarRoot) is only read: its rights belong to its owner.
    if (-not $VarRoot) {
        $owner = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        $token = Get-ProtectedSecretFile -Path $file -OwnerSid $owner -NewValue { [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') }
        if ($script:SecretIncident) {
            try { Write-Log -Backend $Backend -Level 'ERROR' -Name 'session' -Message ("Jeton de l'API compromis (" + $script:SecretIncident + ") : révoqué et réémis.") } catch { }
        }
        return $token
    }
    if (-not (Test-Path $file)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
        Set-Content -Path $file -Value $token -NoNewline -Encoding ASCII
    }
    (Get-Content -Path $file -Raw).Trim()
}

# --- TWO ENVIRONMENTS ON ONE MACHINE ----------------------------------------
#
# The repository (development) and the shared installation (local production) live side by
# side on a developer's workstation. Knowing WHICH one answers is no detail: a fix deployed
# in the wrong place costs an hour to understand.
#
# Two notions, not to be confused:
#   - the DECLARED environment: what the machine says it wants to be (a setting, prod by
#     default);
#   - the OBSERVED environment: where the running code REALLY comes from.
# When the two differ, that is a named fault, not a mystery.
<#
    WHAT A WINDOW THAT DOES NOT SAY WHO IT IS CAN SEE.

    Opening the address by hand -- a private window, a bookmark, another browser -- proves
    nothing: there is no session, so Vigie does not know who is looking. It served the WHOLE
    panel all the same, API token included. Any program on the workstation could therefore
    read the state of the machine, and act.

    Two behaviours, and the ADMINISTRATOR decides:
      'error' (the default) -- a page saying we do not know who you are, and nothing else:
                               no state, no token, no list of cards;
      'cards'               -- the panel, with the rights of a standard account: the actions
                               touching the machine stay refused (Test-ActionAllowed).

    The setting lives in the COMPUTER's declaration (machine.psd1): it holds for every
    installation on the machine, and only an administrator can write it.
#>
function Get-AnonymousAccess {
    param([string]$Backend = (Get-BackendRoot))
    $value = ''
    try { $value = "$((Get-Config -Backend $Backend).AnonymousAccess)".Trim().ToLowerInvariant() } catch { }
    if ($value -in @('error', 'cards')) { return $value }
    return 'error'
}
