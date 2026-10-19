# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: elevation, paths, rights, settings, var
<#
    Intent: WHAT VIGIE IS ALLOWED TO SAY, and to whom: the catalogue each module declares, the settings that switch one event off without touching the others, and the Windows toast itself -- its identity, its image, its XML.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    THE IDENTITY THE NOTIFICATIONS ARE SENT UNDER.

    A toast carries the name of the application that raised it, not the title we wrote.
    Ours is pwsh.exe, so every bubble said "PowerShell" (reported 07/09, subject S11).
    Windows reads that name from a declared identity, so we declare one.

    MACHINE-WIDE, AND ON PURPOSE. HKLM\SOFTWARE\Classes shows through HKEY_CLASSES_ROOT
    for every account, so ONE key serves every session -- and the uninstall has ONE key to
    remove. Writing it per account would mean going into the registry hive of people who
    are not logged in, on the very day we are removing Vigie.
#>
function Get-VigieToastIdentity { 'Sowapps.Vigie' }

function Get-VigieToastIdentityKey {
    'HKLM:\SOFTWARE\Classes\AppUserModelId\' + (Get-VigieToastIdentity)
}

<#
    IT IS THE SERVER APP THAT KEEPS IT TRUE, not the installer alone.

    Declaring it only from install.ps1 looked right and was not: an update runs the
    installer of the version ALREADY in place, so the very first machine to receive this
    declaration would have run an installer that knew nothing about it -- measured on 07/09,
    the key was still missing after deploying the code that writes it. Anything that only
    happens at install time reaches every machine except the ones already running.

    So the elevated server app checks it at every pass. It reads first and writes only when
    something is missing or has moved: an installation that changed folder re-declares its
    icon by itself.
#>
function Test-VigieToastIdentityDeclared {
    param([string]$InstallPath)
    try {
        $key = Get-VigieToastIdentityKey
        if (-not (Test-Path -LiteralPath $key)) { return $false }
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        if ("$($p.DisplayName)" -ne 'Vigie') { return $false }
        if ($InstallPath) {
            $ico = Join-Path (Join-Path (Join-Path (Join-Path $InstallPath 'apps') 'client') 'assets') 'ok.ico'
            if ((Test-Path -LiteralPath $ico) -and "$($p.IconUri)" -ne $ico) { return $false }
        }
        return $true
    } catch { return $false }
}

function Set-VigieToastIdentity {
    param([string]$InstallPath)
    if (Test-VigieToastIdentityDeclared -InstallPath $InstallPath) { return $true }
    $key = Get-VigieToastIdentityKey
    try {
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name 'DisplayName' -Value 'Vigie' -PropertyType String -Force | Out-Null
        # THE ICON IS THE DELIVERED ONE, and it is only declared when it is actually THERE:
        # an IconUri pointing at nothing gives a notification with no image, which is worse
        # than declaring none at all.
        if ($InstallPath) {
            $ico = Join-Path (Join-Path (Join-Path (Join-Path $InstallPath 'apps') 'client') 'assets') 'ok.ico'
            if (Test-Path -LiteralPath $ico) {
                New-ItemProperty -Path $key -Name 'IconUri' -Value $ico -PropertyType String -Force | Out-Null
            }
        }
        return $true
    } catch { return $false }
}

function Remove-VigieToastIdentity {
    $key = Get-VigieToastIdentityKey
    try {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop }
        return $true
    } catch { return $false }
}

<#
    THE NOTIFICATION DOOR -- conception : doc/progress/targeting/notifications.md.

    The client app describes an EVENT and never an display: a subject, a state, a text and
    a duration. Which tool shows it is decided here, at the moment of showing, among the
    files of apps/client/notify/ -- one per tool, ranked by their name, exactly as the game
    identification methods are (probes/gaming/identify/).

    Before this, ShowBalloonTip was called at five places. Changing tool meant rewriting
    five callers, and no tool works on every machine: the real API is unreachable from
    PowerShell 7 without going round, the recommended one lives in a SDK to install. The
    defect was not the tool chosen -- it was that there was no PLACE to change it.

    THE LAST RANK IS ALWAYS AVAILABLE, and that is what makes the rest safe: a tool can be
    added, removed or wrong without a notification ever being lost.
#>
<#
    THE IMAGE A NOTIFICATION SHOWS, AND WHY IT IS BUILT RATHER THAN DELIVERED.

    Windows picks a SMALL frame out of a .ico and blows it up: the outline comes out as a staircase, seen on
    screen on 10/09, and again on 19/10, when the owner said the quality had been good before and had become
    appalling.

    Between the two, the cause changed. A .png used to sit beside the .ico and was preferred; on 07/10 the three
    of them were deleted as "assets nothing opens", because the name is BUILT here (`$name + $extension`) and no
    checker can see a reference that no file spells out. The delivery lost its images and nobody noticed for
    twelve days.

    So the image is no longer delivered: it is DRAWN from the .ico's largest frame, once, into var/cache. The
    repository holds no image -- which is the rule that deletion was serving -- and the notification gets a real
    256-pixel picture. Nothing to regenerate by hand, nothing to forget in a release.
#>
function Get-VigieToastImage {
    param([Parameter(Mandatory)][string]$ClientRoot, [string]$State = 'ok', [string]$Backend = (Get-BackendRoot))
    $name = switch ($State) { 'ok' { 'ok' } 'warn' { 'warn' } 'error' { 'error' } default { 'error' } }
    # A .png beside the .ico still wins, for an installation that carries one.
    foreach ($extension in @('.png', '.ico')) {
        $path = Join-Path (Join-Path $ClientRoot 'assets') ($name + $extension)
        if (-not (Test-PathSafe $path)) { continue }
        if ($extension -eq '.png') { return $path }

        # THE BIGGEST FRAME, TAKEN OUT OF THE CONTAINER. An .ico holds several sizes -- 16 to 256 here -- and
        # System.Drawing.Icon will not hand over the 256 one: asked for it, it returns the 48, because the large
        # frame is PNG-compressed inside the container and that class ignores those. Measured on 19/10.
        #
        # So the container is read directly: its directory says where each frame sits, and the bytes of the
        # largest are ALREADY a PNG. They are copied out as they are -- nothing is decoded, nothing recompressed,
        # so what the notification shows is exactly what the generator drew.
        try {
            $out = Get-VarPath -Backend $Backend -Kind 'cache' -File ('toast-' + $name + '.png')
            $fresh = (Test-PathSafe $out) -and ((Get-Item $out).LastWriteTimeUtc -ge (Get-Item $path).LastWriteTimeUtc)
            if (-not $fresh) {
                $bytes = [IO.File]::ReadAllBytes($path)
                $count = [BitConverter]::ToUInt16($bytes, 4)
                $best = $null
                for ($e = 0; $e -lt $count; $e++) {
                    $at = 6 + ($e * 16)
                    $w = [int]$bytes[$at]
                    if ($w -eq 0) { $w = 256 }        # 0 means 256: one byte cannot hold it
                    $size = [BitConverter]::ToUInt32($bytes, $at + 8)
                    $offset = [BitConverter]::ToUInt32($bytes, $at + 12)
                    if (-not $best -or $w -gt $best.Width) { $best = @{ Width = $w; Size = $size; Offset = $offset } }
                }
                # A frame that is not a PNG is a bitmap, which cannot be copied out as a file: we leave it.
                if ($best -and $best.Size -gt 8 -and $bytes[$best.Offset] -eq 0x89 -and $bytes[$best.Offset + 1] -eq 0x50) {
                    $frame = New-Object byte[] $best.Size
                    [Array]::Copy($bytes, [int]$best.Offset, $frame, 0, [int]$best.Size)
                    [IO.File]::WriteAllBytes($out, $frame)
                }
            }
            if (Test-PathSafe $out) { return $out }
        } catch { }
        # No large frame to be had: the .ico still shows something, badly, which beats showing nothing.
        return $path
    }
    return $null
}

<#
    THE LABEL THAT MAKES A NOTIFICATION REPLACE THE PREVIOUS ONE.

    Seen on screen on 10/09: four notifications about the SAME subject stacked up in the
    action centre instead of superseding one another. Windows only replaces a notification
    by another carrying the same tag, and mine carried none.

    The tag is the subject's reference -- "gaming.hogs" -- so a field going back to normal
    replaces its own alert instead of sitting next to it. Two contradictory lines about one
    subject is worse than no line at all.

    Windows caps a tag at 64 characters and refuses some of them; we keep what is plainly
    safe and cut. A subject with no reference gets none, and stacks -- which is the old
    behaviour, not a new defect.
#>
function Get-VigieToastTag {
    param([string]$Key)
    if (-not "$Key".Trim()) { return '' }
    $tag = ("$Key" -replace '[^A-Za-z0-9._-]', '-')
    if ($tag.Length -gt 64) { $tag = $tag.Substring(0, 64) }
    $tag
}

function Get-VigieToastXml {
    param(
        # AN EMPTY SUBJECT IS A CASE, NOT AN ERROR. Refused by the binder, it would throw
        # inside a tool, the door would read that as a decline and try the next rank -- one
        # by one, down to the balloon, for something we can answer in one line.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Subject,
        [string]$Body = '',
        [string]$Image,
        # WHAT A CLICK OPENS. Windows ignores a click on a toast that names no target, and the only target a script
        # can offer is a protocol -- "vigie://panel", declared by the client app for its account (28/09).
        [string]$Launch,
        [switch]$Long
    )
    if (-not $Subject) { return $null }
    # ESCAPED, ALWAYS. An application named "AT&T" or a title carrying an angle bracket
    # would otherwise produce a document that does not parse, and a lost notification.
    $xml = '<toast'
    if ($Launch) { $xml += ' activationType="protocol" launch="' + [System.Security.SecurityElement]::Escape($Launch) + '"' }
    if ($Long) { $xml += ' duration="long"' }
    $xml += '><visual><binding template="ToastGeneric">'
    $xml += '<text>' + [System.Security.SecurityElement]::Escape($Subject) + '</text>'
    if ($Body) { $xml += '<text>' + [System.Security.SecurityElement]::Escape($Body) + '</text>' }
    if ($Image -and (Test-PathSafe $Image)) {
        $uri = 'file:///' + "$Image".Replace([char]92, '/')
        $xml += '<image placement="appLogoOverride" src="' + [System.Security.SecurityElement]::Escape($uri) + '"/>'
    }
    $xml + '</binding></visual></toast>'
}

function Show-VigieNotification {
    param(
        [Parameter(Mandatory)]$Notification,
        [Parameter(Mandatory)]$Context
    )
    $folder = Join-Path $Context.ClientRoot 'notify'
    foreach ($tool in @(Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $shown = $false
        try { $shown = [bool](@(& $tool.FullName -Notification $Notification -Context $Context) | Select-Object -Last 1) } catch { $shown = $false }
        if ($shown) { return $tool.BaseName }
    }
    return $null
}

# --- Notification settings (D54) ---------------------------------------------
# THE CLIENT APP notifies when a MODULE switches state (a probe's result); the colour of its
# icon stays the state of the APPLICATION -- the two roles do not mix.
#
# Settings: one global switch plus a FINE setting per module. The global one MASKS, it does
# not overwrite: switching everything off and back on finds the fine choices intact. That is
# why the two live in separate keys.
#
# Storage: config/notifications.local.json at the root, never versioned. JSON rather than
# psd1: this file is WRITTEN by the back end -- the interface changes it through the API --
# and the client app READS it; JSON reads and writes easily on both sides.
# Writing: the user layer (D65). Reading: the user's own when it exists, the machine's
# otherwise.
function Get-NotificationSettingsPath { Get-UserConfigPath -File 'notifications.local.json' -Account (Get-ActionRequester) }
function Get-NotificationSettingsReadPath {
    foreach ($p in @((Get-NotificationSettingsPath), (Get-MachineConfigPath -File 'notifications.local.json'))) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Get-NotificationSettingsPath)
}

function Get-NotificationSettings {
    param([string]$Backend = (Get-BackendRoot))
    $s = [ordered]@{ enabled = $true; modules = [ordered]@{}; notifs = [ordered]@{} }
    $p = Get-NotificationSettingsReadPath
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $j.enabled) { $s.enabled = [bool]$j.enabled }
            if ($j.modules) { foreach ($pr in $j.modules.PSObject.Properties) { $s.modules[$pr.Name] = [bool]$pr.Value } }
            if ($j.notifs)  { foreach ($pr in $j.notifs.PSObject.Properties)  { $s.notifs[$pr.Name]  = [bool]$pr.Value } }
        } catch { }
    }
    [pscustomobject]$s
}

function Set-NotificationSettings {
    param(
        [string]$Backend = (Get-BackendRoot),
        $Enabled,
        # A module -> $true/$false table. MERGED with what exists: only what changes need be
        # supplied; an absent key keeps its setting (the global never loses the fine one).
        [hashtable]$Modules,
        # A "<module>.<notification>" -> $true/$false table. Merged like the rest.
        [hashtable]$Notifs
    )
    $cur = Get-NotificationSettings -Backend $Backend
    $out = [ordered]@{ enabled = [bool]$cur.enabled; modules = [ordered]@{}; notifs = [ordered]@{} }
    foreach ($k in @($cur.modules.Keys)) { $out.modules["$k"] = [bool]$cur.modules[$k] }
    foreach ($k in @($cur.notifs.Keys))  { $out.notifs["$k"]  = [bool]$cur.notifs[$k] }
    if ($null -ne $Enabled) { $out.enabled = [bool]$Enabled }
    if ($Modules) { foreach ($k in $Modules.Keys) { $out.modules["$k"] = [bool]$Modules[$k] } }
    if ($Notifs)  { foreach ($k in $Notifs.Keys)  { $out.notifs["$k"]  = [bool]$Notifs[$k] } }
    $p = Get-NotificationSettingsPath
    $tmp = "$p.tmp"
    ($out | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $p -Force
    [pscustomobject]$out
}

# --- THE NOTIFICATION CATALOGUE (D54, revised on 26/08) -----------------------
# A notification is NOT "a card": it is a named EVENT, declared by the module. A card's own title tells nobody
# anything; the name of what happened -- a GPU running hot, for instance -- does.
# (Raised by the owner: the screen listed the cards, not the notifications.)
#
# Declared in probes/<module>/module.psd1:
#   Notifications = @(
#       @{ Key = 'gpu-temp'; Label = 'Temperature GPU elevee'
#          Field = 'gpu-temp'; Card = 'gaming'; Help = '...' }
#   )
# Key   : the setting's stable identifier, never displayed;
# Label : what the user reads;
# Card / Field : the card and the field whose CHANGE OF STATE raises the notification.
#
# A module with no declaration falls back on one notification per card: the old behaviour,
# so that nothing is lost on the way.
function Get-NotificationCatalog {
    param([string]$Backend = (Get-BackendRoot))
    @(foreach ($u in (Get-UnitCatalog -Backend $Backend)) {
        $declPath = Join-Path (Join-Path (Join-Path $Backend 'probes') $u.id) 'module.psd1'
        $decl = @{}
        if (Test-Path -LiteralPath $declPath) {
            try { $decl = Import-PowerShellDataFile -Path $declPath } catch { }
        }
        $notifs = @(foreach ($nn in @($decl.Notifications)) {
            if (-not $nn -or -not $nn.Key) { continue }
            [ordered]@{
                key   = "$($nn.Key)"
                label = "$($nn.Label)"
                help  = if ($nn.Help) { "$($nn.Help)" } else { '' }
                card  = if ($nn.Card) { "$($nn.Card)" } else { '' }
                field = if ($nn.Field) { "$($nn.Field)" } else { '' }
                # WHO can do something about it, and must they be told all the same?
                # The manifest said `Droits` and `Critique` until 15/10: both spellings are read, the English one
                # first, so a module declared either way keeps its notifications.
                rights   = $(if ($nn.Rights) { ConvertTo-RightsValue "$($nn.Rights)" }
                             elseif ($nn.Droits) { ConvertTo-RightsValue "$($nn.Droits)" } else { 'all' })
                critical = [bool]$(if ($null -ne $nn.Critical) { $nn.Critical } else { $nn.Critique })
            }
        })
        [pscustomobject][ordered]@{ unit = $u.id; label = $u.label; enabled = $u.enabled; notifications = $notifs }
    })
}

# The client app applies the rule WITHOUT redoing the reasoning: does a notification for this
# module get through? (global off means nothing; otherwise the fine setting, on by default)
function Test-NotificationAllowed {
    param(
        [Parameter(Mandatory)][string]$ModuleId,
        # The key of the notification the module declared. Absent: we judge at module level,
        # as before.
        [string]$Key,
        $Settings
    )
    if (-not $Settings) { $Settings = Get-NotificationSettings }
    if (-not [bool]$Settings.enabled) { return $false }
    # RIGHTS (the owner's rule, 26/08): one does not disturb somebody with a problem they
    # cannot solve. A notification whose resolution requires an administrator is therefore not
    # shown to a standard account...
    # ...UNLESS it is declared CRITICAL: antivirus off, firewall open, updates pending. In
    # that case the user must know, if only to report it to an administrator -- and the client
    # app tells them so explicitly.
    if ($Key -and -not (Test-IsElevated)) {
        $decl = $null
        foreach ($u in (Get-NotificationCatalog)) {
            if ($u.unit -ne $ModuleId) { continue }
            $decl = @($u.notifications | Where-Object { $_.key -eq $Key })[0]
            break
        }
        if ($decl -and "$($decl.rights)" -eq 'admin' -and -not $decl.critical) { return $false }
    }
    # The FINE setting, per notification: it wins over the module's.
    if ($Key -and $Settings.notifs) {
        $ref = "$ModuleId.$Key"
        $p = $Settings.notifs.PSObject.Properties | Where-Object { $_.Name -eq $ref } | Select-Object -First 1
        if (-not $p -and ($Settings.notifs -is [System.Collections.IDictionary]) -and $Settings.notifs.Contains($ref)) {
            return [bool]$Settings.notifs[$ref]
        }
        if ($p) { return [bool]$p.Value }
    }
    # `modules` is a DICTIONARY, never a raw JSON object -- Get-NotificationSettings
    # normalises it -- so access goes through ContainsKey. The first version questioned
    # PSObject.Properties, which on a dictionary describes the container and not the keys:
    # every fine setting was silently ignored.
    if ($Settings.modules.Contains("$ModuleId")) { return [bool]$Settings.modules["$ModuleId"] }
    return $true
}
