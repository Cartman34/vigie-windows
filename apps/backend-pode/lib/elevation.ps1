# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses: format, native, paths
<#
    Intent: ASKING FOR ADMINISTRATOR RIGHTS, AND EXPLAINING FIRST (D22): a window saying what is about to change and why, before any UAC prompt -- the user can refuse without a system dialog ever appearing. The window dressing lives here too.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- WHICH Windows ACCOUNTS have Vigie (D65) ----------------------------------
# The computer has several accounts; the user chooses which ones have Vigie, and may change
# their mind at any time (the requirement: "a tool must always allow changing which account
# has access").
#
# Enabling an account means laying down ITS startup scheduled task. Nothing else: the
# settings are already per account (the %LOCALAPPDATA% layer), and the runtime data follow
# the account as soon as the installation is not writable (Get-VarRoot).
#
# The run level follows the ACCOUNT, not our wishes: `Highest` for an administrator,
# `Limited` for a standard account. Giving Highest to a standard account would not work --
# and MUST not: Vigie gives nothing more than Windows does.
$script:VigieTaskPrefix = 'Vigie - '

# WHICH pwsh can ANOTHER account launch?
#
# An expensive trap, seen on 26/08: the task for "Famille" was created with
# (Get-Command pwsh).Source, which here is
# C:\Users\fhaza\AppData\Local\Microsoft\WindowsApps\pwsh.exe -- a path inside THE
# ADMINISTRATOR'S PROFILE. No other account can read that, and the Store alias points in any
# case to an MSIX package registered for the one account that installed it. So the task was
# created without an error... and never launched anything for Famille: Vigie did not start,
# with not one message.
#
# Only a MACHINE installation -- the MSI, under Program Files -- will do. It is looked for,
# and when it is missing we REFUSE to enable the account, saying what to do, rather than
# laying a task that will fail silently at every logon.
# HOW PowerShell 7 is installed for the machine. A SINGLE definition (D15): the installation
# script and the Accounts card's button run exactly the same thing.
# `--scope machine` is the essential point: without it, winget lays the MSIX package in the
# profile of whoever installs, and the other accounts cannot launch it.
function Get-SharedPwshInstallArgs {
    # --installer-type msi: WITHOUT it, winget chooses the MSIX package and tries to
    # "provision" it for every account -- an operation that fails on this machine with
    # 0x80070005 (winget's log of 26/08: ProvisionPackageOperation). And the MSI is precisely
    # what we want: it lays pwsh.exe in C:\Program Files\PowerShell\7, a real path every
    # session can launch, with no per-account registration. The MSIX, even provisioned,
    # remains a per-user package.
    @('install', '--id', 'Microsoft.PowerShell', '-e', '--scope', 'machine',
      '--installer-type', 'msi',
      '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements',
      '--silent', '--disable-interactivity')
}

function Get-SharedPwshPath {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($r in $roots) {
        $d = Join-Path $r 'PowerShell'
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $trouves = @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending |
                     ForEach-Object { Join-Path $_.FullName 'pwsh.exe' } |
                     Where-Object { Test-Path -LiteralPath $_ })
        if ($trouves.Count) { return $trouves[0] }
    }
    return $null
}

# --- Elevation: EXPLAIN before asking ----------------------------------------
# The principle (asked for explicitly by the owner, D22): we never send the UAC prompt "bare". We first show a
# window saying what is about to be changed and why the elevation is necessary, as Android does before a
# permission. The user can refuse without any system prompt appearing at all.



# Is the current process elevated? (one single wording of this test)
# The elevation test has only ONE implementation (Test-Elevated, further up). THIS name is the one the
# installation scripts use; it delegates instead of writing the same test a second time (D15). Both copies used to
# exist, and could diverge.
function Test-IsElevated { Test-Elevated }

# --- Window dressing (DWM) ---------------------------------------------------
# A dark title bar and Windows 11 rounded corners. Declared ONCE here and used everywhere (the consent window, the
# client app's menu): the P/Invoke signature must not be copied into every script.
# No effect on earlier versions of Windows: the call fails without harm.

function Set-WindowChrome {
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [switch]$DarkTitleBar,
        [switch]$RoundedCorners,
        # Border colour in COLORREF form (0x00BBGGRR). -1 = leave it alone.
        [int]$BorderColor = -1
    )
    if ($Handle -eq [IntPtr]::Zero) { return }
    try {
        if (-not ('VigieNative.Dwm' -as [type])) {
            Add-Type -Namespace VigieNative -Name Dwm -MemberDefinition '[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);' -ErrorAction Stop
        }
        # 20 = DWMWA_USE_IMMERSIVE_DARK_MODE, 33 = WINDOW_CORNER_PREFERENCE, 34 = BORDER_COLOR
        if ($DarkTitleBar)   { $v = 1; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 20, [ref]$v, 4) }
        if ($RoundedCorners) { $v = 2; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 33, [ref]$v, 4) }
        if ($BorderColor -ne -1) { $v = $BorderColor; [void][VigieNative.Dwm]::DwmSetWindowAttribute($Handle, 34, [ref]$v, 4) }
    } catch { }
}

# Where does this launch come from? Returns a descriptive string when an automated agent is detected, $null
# otherwise (started by hand).
# A security matter: a request for administrator rights that does NOT come from a click by the user must announce
# itself as such. Without that, an agent could obtain an elevation the user would believe they had triggered
# themselves.
function Get-LaunchOrigin {
    if ($env:AI_AGENT)       { return $env:AI_AGENT }
    if ($env:CLAUDECODE)     { return 'Claude Code' }
    if ($env:GITHUB_ACTIONS) { return 'GitHub Actions' }
    if ($env:TF_BUILD)       { return 'Azure Pipelines' }
    return $null
}

# Cuts a control into a rounded rectangle. Necessary for context menus: DWM (Set-WindowChrome) does NOT round
# windows without a standard frame, which leaves a menu with square corners. The region, on the other hand, always
# applies.
# The accepted price: edges without antialiasing, and the shadow cut along the outline.
function Set-RoundedRegion {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [int]$Radius = 8
    )
    try {
        if ($Radius -le 0 -or $Control.Width -le 0 -or $Control.Height -le 0) { return }
        $w = $Control.Width; $h = $Control.Height
        $d = [Math]::Min($Radius * 2, [Math]::Min($w, $h))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $d, $d, 180, 90)
        $path.AddArc($w - $d, 0, $d, $d, 270, 90)
        $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
        $path.AddArc(0, $h - $d, $d, $d, 90, 90)
        $path.CloseFigure()
        $old = $Control.Region
        $Control.Region = New-Object System.Drawing.Region($path)
        if ($old) { $old.Dispose() }
        $path.Dispose()
    } catch { }
}

# The explanatory window. Returns $true if the user accepts to carry on.
# -AssumeYes short-circuits the display (a non-interactive run, a scheduled task).
function Show-ElevationRationale {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Summary,
        [string[]]$Changes = @(),
        # Where the launch comes from. By default: detected automatically, so that an agent cannot hide its role by
        # forgetting to declare it.
        [string]$InitiatedBy = (Get-LaunchOrigin),
        [switch]$AssumeYes
    )
    if ($AssumeYes) { return $true }

    # THE WINDOW LIVES IN scripts/lib/show-confirm.ps1, and nowhere else.
    #
    # It must be able to appear BEFORE the first elevation, when PowerShell 7 is not installed yet: it is therefore
    # written to run under Windows PowerShell 5.1 as well, and lives outside this library, which targets PS7.
    # Drawing it a second time here would have guaranteed that the two diverge at the first retouch.

    $script = $null
    try { $script = Join-Path (Get-RepoRoot) 'scripts/lib/show-confirm.ps1' } catch { }

    if ($script -and (Test-Path -LiteralPath $script)) {
        $exe = $null
        try { $exe = (Get-Process -Id $PID).Path } catch { }
        if (-not $exe) { $exe = 'powershell.exe' }
        # THE TEXT DOES NOT CROSS THE COMMAND LINE. Passed as an argument, it suffers the code page of the process
        # called: "securite" became "sIcuritI" there (observed on 29/08). These texts are BUILT -- they come from
        # the action, not from a label -- so no key designates them: they travel through a file, and only its path,
        # in ASCII, crosses the border.

        $payload = Join-Path ([IO.Path]::GetTempPath()) ('vigie-confirm-' + [guid]::NewGuid().ToString('N') + '.json')
        $data = @{ title = "$Title"; summary = "$Summary"
                   changes = ($Changes -join '|'); initiatedBy = "$InitiatedBy" }
        [System.IO.File]::WriteAllText($payload, ($data | ConvertTo-Json -Compress -Depth 4),
                                       (New-Object System.Text.UTF8Encoding($false)))
        # RAW VALUES: the call operator quotes each argument itself, so a value wrapped by
        # hand arrives WITH its quotes. The opposite of Start-Process (D116).
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script,
                  '-PayloadFile', $payload)
        try {
            & $exe @argv
            # 0 = carry on; 3 = refusal; 1 = no interface, and the script said so on the console. Anything that is
            # not 0 REFUSES: nothing is elevated without consent.
            return ($LASTEXITCODE -eq 0)
        } catch {
            Write-Host (Get-Label 'common.impossible-afficher-la-fenetre' $_.Exception.Message) -ForegroundColor Yellow
        } finally {
            # IN A "finally", not after the return: a cleanup placed after one never runs, and the file -- which
            # carries the window's text -- would stay in the temporary folder at every elevation. And "finally"
            # comes AFTER "catch": the reverse order does not parse.

            try { Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

    # Fallback: the script cannot be found (a damaged installation). We explain on the console and we REFUSE -- use
    # -Yes for a deliberately automated launch.
    $nl = [Environment]::NewLine
    Write-Host ""
    if ($InitiatedBy) {
        Write-Host (Get-Label 'common.demande-par-un-agent' $InitiatedBy) -ForegroundColor Yellow
        Write-Host (Get-Label 'common.ce-est-pas-toi') -ForegroundColor Yellow
    }
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $Summary
    if ($Changes.Count) { Write-Host (($Changes | ForEach-Object { "   - $_" }) -join $nl) }
    Write-Host (Get-Label 'common.fenetre-de-confirmation-introuvable') -ForegroundColor Yellow
    return $false
}

# Restarts THE SAME script in an elevated session, keeping its parameters, then hands back its output. One cannot
# redirect a process started with -Verb RunAs: the elevated session therefore writes into a log, which is read
# back afterwards.
# Returns the exit code of the elevated session.
function Invoke-ElevatedSelf {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$LogDir = $env:TEMP
    )
    # -WhatIf must NOT apply to the restart: it is the restarted script that must simulate its own operations.
    # Without -WhatIf:$false, -WhatIf would simulate the elevation and nothing would run -- so one would never see
    # what was about to be done.
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name  = [IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $log   = Join-Path $LogDir ('elevated_' + $name + '_' + $stamp + '.log')

    # UTF-8 IMPOSED AT BOTH ENDS. Without it the elevated session writes its log in the console's code page (850 or
    # 1252 depending on the machine) and the parent reads it back as UTF-8: an accented "Trouve" came back with its
    # accent turned into two unrelated characters (observed on 27/08). The accents are not negotiable (D41).

    $parts = @('$OutputEncoding=[Text.Encoding]::UTF8;',
               '[Console]::OutputEncoding=[Text.Encoding]::UTF8;',
               '&', (ConvertTo-PSLiteral $ScriptPath))
    foreach ($a in $Arguments) {
        if ($a -like '-*') { $parts += $a } else { $parts += (ConvertTo-PSLiteral ([string]$a)) }
    }
    $cmd = ($parts -join ' ') + ' *> ' + (ConvertTo-PSLiteral $log)

    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-Host (Get-Label 'common.pwsh-introuvable') -ForegroundColor Red; return 1 }

    try {
        # The command block travels as ONE argument -- it is full of spaces, and split by
        # the command line it would only be rejoined by luck.
        $proc = Start-ChildProcess -FilePath $pwshPath `
                    -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) `
                    -Options @{ Verb = 'RunAs'; Wait = $true; PassThru = $true
                                WindowStyle = 'Hidden'; WhatIf = $false }
    } catch {
        Write-Host (Get-Label 'common.elevation-refusee-ou-impossible' $_.Exception.Message) -ForegroundColor Yellow
        return 1
    }

    if (Test-Path -LiteralPath $log) {
        Write-Host (Get-Label 'common.compte-rendu-de-la')
        Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ }
        Write-Host (Get-Label 'common.journal' $log)
    } else {
        Write-Host (Get-Label 'common.aucune-sortie-produite-par') -ForegroundColor Yellow
    }
    return $proc.ExitCode
}
