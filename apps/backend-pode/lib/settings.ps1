# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: paths, rights, var
<#
    Intent: WHERE THE SETTINGS LIVE: the machine first, then the user (D65). Which modules are on (D48), what each module's parameters are worth (D57), and the catalogue that says what may be set at all.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- WHERE THE SETTINGS LIVE: MACHINE, then USER (D65) -------------------------
# The computer has several Windows accounts and each must have ITS settings.
# Three layers, from the most general to the most personal:
#   1. the VERSIONED defaults      (probes/<module>/module.psd1, Config)
#   2. the MACHINE layer           (config/*.local.* in the installation) -- so whatever was
#      already set before multi-user stays in place for everyone
#   3. the USER layer              (%LOCALAPPDATA%\Sowapps\Vigie) -- this account's own
# All three are READ, the most personal winning; writing always goes to the user layer: an
# account never modifies another's settings.
#
# An elevated process of the same account shares its LOCALAPPDATA: the elevated server and
# the client app therefore do write in the same place as the signed-in user.
<#
    AN ACCOUNT'S SETTINGS LIVE AT ITS HOME, AND THAT IS WHERE WE GO FOR THEM.

    Until now this function always returned the folder of the account that RUNS -- so the
    server's. The consequence, seen on 28/08: Famille and fhaza saw the same modules, the same
    list of ignored packages, the same notifications, because it was fhaza's configuration in
    both cases. Hiding a card for one hid it for the other.

    With -Account, THAT account's folder is read. Without it, the process's: the right
    behaviour for a local script or a task, which has no requester.

    We CREATE nothing in somebody else's profile: laying a folder at the home of someone who
    has never opened Vigie makes no sense, and the server has no reason to write there before
    they ask.
#>
function Get-AccountConfigDir {
    param([Parameter(Mandatory)][string]$Account)
    $profil = Join-Path $env:SystemDrive (Join-Path 'Users' $Account)
    if (-not (Test-PathSafe $profil)) { return $null }
    return (Join-Path (Join-Path (Join-Path (Join-Path $profil 'AppData') 'Local') 'Sowapps') 'Vigie')
}

function Get-UserConfigPath {
    param(
        [Parameter(Mandatory)][string]$File,
        # The account whose settings are wanted. By default: whoever runs.
        [string]$Account
    )
    if ($Account) {
        $d = Get-AccountConfigDir -Account $Account
        if ($d) { return (Join-Path $d $File) }
    }
    return (Join-Path (Get-UserConfigDir) $File)
}
function Get-MachineConfigPath { param([Parameter(Mandatory)][string]$File) Join-Path (Get-RepoRoot) (Join-Path 'config' $File) }

# --- Managing the modules (D48) -----------------------------------------------
# A MODULE (a unit) is a FOLDER of probes, declared by a versioned module.psd1.
# Whether it is enabled is the user's choice: config/modules.local.psd1, never versioned. A
# module switched off takes its probes out of the computation, but stays EXPOSED in the
# contract's units[] key -- otherwise the interface could no longer offer to switch it back on.
# The user layer when it exists, the machine layer otherwise (D65). The two are not MERGED:
# turning back on, for oneself, a module switched off for the machine must stay possible.
# THE REQUESTER, NOT WHOEVER RUNS. Get-ActionRequester returns the session's account when the
# request comes from an identified page, and the process's otherwise: exactly the rule wanted
# for personal settings.
function Get-UnitsLocalPath { Get-UserConfigPath -File 'modules.local.psd1' -Account (Get-ActionRequester) }

# WHAT THE USER HAS EXPLICITLY TURNED ON. Distinct from "not turned off": a module may be
# born OFF (module.psd1: DefautActif = $false), and one then has to know whether the user
# turned it on for good or simply never had an opinion.
function Get-EnabledUnits {
    <#
        A MODULE ONE ACCOUNT HAS TURNED ON IS COMPUTED, whoever asks -- and that includes nobody.

        This choice lives in the profile of whoever made it. The scheduler, which computes without anyone asking, has
        no requester: it read the service account's file, found nothing, fell back on the module's default and left
        the module out. Measured on 30/09: the two computations of the Debogage module -- turned on months earlier --
        had NEVER been started once, while both their cards were displayed as if they were fresh.

        So the answer is the union: every account's choice is read, and one "yes" is enough. Computing serves whoever
        looks, and it cannot depend on who happens to be looking.
    #>
    <#
        READ FROM THE PROFILES THEMSELVES, not from the list of accounts: establishing that list costs two seconds
        (measured 29/09) and this is asked once per module. A file that exists is an account that has an opinion.
        Kept for thirty seconds, because Get-InactiveUnits asks it ten times in a row.
    #>
    $nowTicks = [datetime]::UtcNow.Ticks
    if ($script:EnabledUnitsAt -and (($nowTicks - [long]$script:EnabledUnitsAt) / 1e7) -lt 30) {
        return @($script:EnabledUnitsCache)
    }
    $found = @()
    $seen = $false
    try {
        $users = Join-Path $env:SystemDrive 'Users'
        foreach ($dir in @(Get-ChildItem -LiteralPath $users -Directory -ErrorAction SilentlyContinue)) {
            $p = Join-Path $dir.FullName 'AppData\Local\Sowapps\Vigie\modules.local.psd1'
            if (-not (Test-PathSafe $p)) { continue }
            try { $found += @((Import-PowerShellDataFile -Path $p).Enabled | ForEach-Object { "$_" }); $seen = $true } catch { }
        }
    } catch { }
    if ($seen) {
        $script:EnabledUnitsCache = @($found | Where-Object { $_ } | Select-Object -Unique)
        $script:EnabledUnitsAt = $nowTicks
        return @($script:EnabledUnitsCache)
    }
    foreach ($p in @((Get-UnitsLocalPath), (Get-MachineConfigPath -File 'modules.local.psd1'))) {
        if (Test-Path -LiteralPath $p) {
            try { return @((Import-PowerShellDataFile -Path $p).Enabled | ForEach-Object { "$_" }) } catch { return @() }
        }
    }
    return @()
}

# Is the module active, all things considered? Three cases, in this order:
#   1. the user turned it off        -> no
#   2. the user turned it on         -> yes
#   3. nobody said anything          -> what the module declares (active, unless stated
#                                       otherwise in module.psd1)
function Test-UnitEnabled {
    param(
        [Parameter(Mandatory)][string]$UnitId,
        [string]$Backend = (Get-BackendRoot)
    )
    if ((Get-DisabledUnits) -contains $UnitId) { return $false }
    if ((Get-EnabledUnits)  -contains $UnitId) { return $true }
    $decl = @{}
    $f = Join-Path (Join-Path (Join-Path $Backend 'probes') $UnitId) 'module.psd1'
    if (Test-Path -LiteralPath $f) {
        try { $decl = Import-PowerShellDataFile -Path $f } catch { }
    }
    if ($decl.ContainsKey('DefautActif')) { return [bool]$decl.DefautActif }
    return $true
}

# The list of modules to EXCLUDE from the computation, defaults included. It is what Get-State
# consults: a module switched off costs nothing, neither computation nor card.
function Get-InactiveUnits {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    @(foreach ($d in (Get-ChildItem -Path $probesDir -Directory -ErrorAction SilentlyContinue)) {
        if (-not (Test-UnitEnabled -UnitId $d.Name -Backend $Backend)) { $d.Name }
    })
}

function Get-DisabledUnits {
    foreach ($p in @((Get-UnitsLocalPath), (Get-MachineConfigPath -File 'modules.local.psd1'))) {
        if (Test-Path -LiteralPath $p) {
            try { return @((Import-PowerShellDataFile -Path $p).Disabled | ForEach-Object { "$_" }) } catch { return @() }
        }
    }
    return @()
}

function Set-UnitEnabled {
    param(
        [Parameter(Mandatory)][string]$UnitId,
        [Parameter(Mandatory)][bool]$Enabled
    )
    $off = [System.Collections.Generic.List[string]]::new()
    foreach ($u in (Get-DisabledUnits)) { if ($u -ne $UnitId) { $off.Add($u) } }
    if (-not $Enabled) { $off.Add($UnitId) }
    # TURNING ON is kept too: a module born off, like Debogage, must stay on after a restart.
    # Without that second list, it would have switched itself off again.
    $on = [System.Collections.Generic.List[string]]::new()
    foreach ($u in (Get-EnabledUnits)) { if ($u -ne $UnitId) { $on.Add($u) } }
    if ($Enabled) { $on.Add($UnitId) }
    $listeOn = ($on | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $liste = ($off | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $text = "@{`n    # Choix de l'utilisateur sur les modules (D48). Fichier ecrit par l'application`n" +
             "    # (vue de gestion des modules), jamais versionne.`n" +
             "    #   Disabled : eteints a la main.`n" +
             "    #   Enabled  : allumes a la main -- utile pour ceux qui naissent eteints (debogage).`n" +
             "    Disabled = @($liste)`n    Enabled = @($listeOn)`n}`n"
    $p = Get-UnitsLocalPath
    Set-Content -LiteralPath $p -Value $text -Encoding UTF8
}

function Get-UnitCatalog {
    param([string]$Backend = (Get-BackendRoot))
    $probesDir = Join-Path $Backend 'probes'
    $off = Get-DisabledUnits
    @(foreach ($dir in (Get-ChildItem -Path $probesDir -Directory | Sort-Object Name)) {
        $decl = @{}
        $declPath = Join-Path $dir.FullName 'module.psd1'
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        $probes = @(Get-ChildItem -Path $dir.FullName -Filter '*.probe.ps1' -File)
        [pscustomobject][ordered]@{
            id          = $dir.Name
            label       = if ($decl.Label) { "$($decl.Label)" } else { $dir.Name }
            description = if ($decl.Description) { "$($decl.Description)" } else { '' }
            enabled     = (Test-UnitEnabled -UnitId $dir.Name -Backend $Backend)
            # A DEBUGGING module does not impose itself: it is born off, and the management
            # screen must be able to say so instead of suggesting a breakdown.
            offByDefault = ($decl.ContainsKey('DefautActif') -and -not [bool]$decl.DefautActif)
            probes      = @($probes | ForEach-Object { $_.Name -replace '\.probe\.ps1$', '' })
        }
    })
}

# --- Module settings (D57) ----------------------------------------------------
# The model the owner approved: the CONFIG (module.psd1, versioned) carries the DEFAULT
# values; a SETTING is the user's override, laid through the Settings menu and stored in
# config/parameters.local.json, never versioned.
# Every setting has a config value for its default -- that is the rule, not the exception.
# Writing goes to the user layer (D65).
function Get-ParametersLocalPath { Get-UserConfigPath -File 'parameters.local.json' -Account (Get-ActionRequester) }

# Reading ONE layer.
function Get-ParameterOverridesFrom {
    param([Parameter(Mandatory)][string]$Path)
    $out = @{}
    if (Test-Path -LiteralPath $Path) {
        try {
            $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($u in $j.PSObject.Properties) {
                $out[$u.Name] = @{}
                foreach ($k in $u.Value.PSObject.Properties) { $out[$u.Name][$k.Name] = $k.Value }
            }
        } catch { }
    }
    return $out
}

# Machine THEN user: the personal setting wins, key by key -- and only the keys actually set;
# the rest goes on following the machine, then the module's default.
function Get-ParameterOverrides {
    param([switch]$UtilisateurSeul)
    $out = @{}
    $couches = if ($UtilisateurSeul) { @((Get-ParametersLocalPath)) }
               else { @((Get-MachineConfigPath -File 'parameters.local.json'), (Get-ParametersLocalPath)) }
    foreach ($c in $couches) {
        $couche = Get-ParameterOverridesFrom -Path $c
        foreach ($u in $couche.Keys) {
            if (-not $out.ContainsKey($u)) { $out[$u] = @{} }
            foreach ($k in $couche[$u].Keys) { $out[$u][$k] = $couche[$u][$k] }
        }
    }
    return $out
}

# A setting's EFFECTIVE value: the user override when there is one, otherwise the module's
# config. It is THE entry point for the probes -- they never read the local file themselves.
function Get-ModuleSetting {
    param(
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][string]$Key,
        [string]$Backend = (Get-BackendRoot)
    )
    $sur = Get-ParameterOverrides
    if ($sur.ContainsKey($Unit) -and $sur[$Unit].ContainsKey($Key)) { return $sur[$Unit][$Key] }
    $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $Unit) 'module.psd1'
    if (Test-Path -LiteralPath $declPath) {
        try {
            $d = Import-PowerShellDataFile -Path $declPath
            if ($d.Config -and $d.Config.ContainsKey($Key)) { return $d.Config[$Key] }
        } catch { }
    }
    return $null
}

# A catalogue for the interface: every module declares (module.psd1) its adjustable settings
# -- key, label, type, help -- and the current value is computed here.
function Get-ModuleParameterCatalog {
    param([string]$Backend = (Get-BackendRoot))
    # `sur` is what THIS account has set; `mach` is what is set for the machine.
    $sur  = Get-ParameterOverrides -UtilisateurSeul
    $mach = Get-ParameterOverridesFrom -Path (Get-MachineConfigPath -File 'parameters.local.json')
    @(foreach ($u in (Get-UnitCatalog -Backend $Backend)) {
        $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $u.id) 'module.psd1'
        $decl = @{}
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        if (-not $decl.Parameters) { continue }
        $params = @(foreach ($pm in @($decl.Parameters)) {
            $cle = "$($pm.Key)"
            $defaut = if ($decl.Config -and $decl.Config.ContainsKey($cle)) { $decl.Config[$cle] } else { $null }
            # What this account INHERITS if it has set nothing: the module's default, or the
            # machine's setting when there is one (D65).
            if ($mach.ContainsKey($u.id) -and $mach[$u.id].ContainsKey($cle)) { $defaut = $mach[$u.id][$cle] }
            $courant = if ($sur.ContainsKey($u.id) -and $sur[$u.id].ContainsKey($cle)) { $sur[$u.id][$cle] } else { $defaut }
            [ordered]@{
                key      = $cle
                label    = "$($pm.Label)"
                type     = if ($pm.Type) { "$($pm.Type)" } else { 'int' }
                unit     = if ($pm.Unit) { "$($pm.Unit)" } else { $null }
                help     = if ($pm.Help) { "$($pm.Help)" } else { '' }
                # Slider bounds: the interface offers a guided setting, and typing a value by
                # hand always stays possible (a number field kept in step).
                min      = if ($null -ne $pm.Min)  { [int]$pm.Min }  else { $null }
                max      = if ($null -ne $pm.Max)  { [int]$pm.Max }  else { $null }
                step     = if ($null -ne $pm.Step) { [int]$pm.Step } else { $null }
                default  = $defaut
                value    = $courant
                overridden = ($sur.ContainsKey($u.id) -and $sur[$u.id].ContainsKey($cle))
            }
        })
        [pscustomobject][ordered]@{ unit = $u.id; label = $u.label; params = $params }
    })
}

# Lays down (or removes) overrides. $null for a key means going back to the config value.
# Only the keys DECLARED by the module are accepted: a setting that is not declared has no
# interface, so it has no override either.
function Set-ModuleParameters {
    param(
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][hashtable]$Values,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = @(Get-ModuleParameterCatalog -Backend $Backend | Where-Object { $_.unit -eq $Unit })
    if (-not $cat) { throw "Module sans parametres declares : $Unit" }
    $connues = @($cat[0].params | ForEach-Object { $_.key })
    # UtilisateurSeul: the machine's values are not copied into the personal file -- they
    # would be frozen there and would no longer follow the installation.
    $sur = Get-ParameterOverrides -UtilisateurSeul
    if (-not $sur.ContainsKey($Unit)) { $sur[$Unit] = @{} }
    foreach ($k in $Values.Keys) {
        if ($connues -notcontains "$k") { throw "Parametre non declare : $Unit.$k" }
        if ($null -eq $Values[$k]) { $sur[$Unit].Remove("$k") }
        else { $sur[$Unit]["$k"] = $Values[$k] }
    }
    if ($sur[$Unit].Count -eq 0) { $sur.Remove($Unit) }
    $p = Get-ParametersLocalPath
    $tmp = "$p.tmp"
    ($sur | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $p -Force
}
