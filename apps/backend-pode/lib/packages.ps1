# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: client-app, native, operations, paths, probes, rights, store, var
<#
    Intent: THE PACKAGE MANAGERS, through one door: what each one can do, what it has to update, how an upgrade runs and what its failure means. One source for the probe, the update check AND the upgrade.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- Package managers (one source for the probe, the update check AND the upgrade) --
# One catalogue: id, label, version arguments, update arguments and mode, upgrade arguments.
# An empty upgArgs means no automatic update is offered for that manager.
#
# upgOne holds the arguments to update ONE package, `{pkg}` being replaced by its
# identifier. That is what makes CHOICE possible: without upgOne a manager only knows how to
# "update everything", and the interface says so rather than suggesting otherwise.
#
# gui* describes the manager's graphical interface, when it exists AND is installed.
#   guiKind 'uri' -> a protocol checked in HKEY_CLASSES_ROOT (the Store is not an .exe)
#   guiKind 'exe' -> an executable looked for in the PATH, then in guiPaths
# A button that opens an absent program is worse than no button: presence is checked at
# every pass of the probe, never assumed.
function Get-PackageManagerCatalog {
    @(
        [pscustomobject]@{ id='winget'; label='winget';       verArgs=@('--version'); updArgs=@('upgrade','--include-unknown','--disable-interactivity','--accept-source-agreements'); updMode='winget';   upgArgs=@('upgrade','--all','--silent','--include-unknown','--disable-interactivity','--accept-source-agreements','--accept-package-agreements')
                           upgOne=@('upgrade','--id','{pkg}','--silent','--disable-interactivity','--accept-source-agreements','--accept-package-agreements')
                           guiKind='uri'; guiTarget='ms-windows-store://downloadsandupdates'; guiProbe='ms-windows-store'; guiLabel='Ouvrir le Microsoft Store'
                           guiHelp="Ouvre la page « Téléchargements et mises à jour » du Microsoft Store, qui partage le catalogue de winget." }
        [pscustomobject]@{ id='choco';  label='Chocolatey';   verArgs=@('--version'); updArgs=@('outdated','-r','--nocolor');   updMode='chocor';   upgArgs=@('upgrade','all','-y')
                           upgOne=@('upgrade','{pkg}','-y')
                           guiKind='exe'; guiTarget='ChocolateyGUI.exe'; guiProbe='ChocolateyGUI'; guiLabel='Ouvrir Chocolatey GUI'
                           guiHelp="Ouvre Chocolatey GUI, l'interface graphique de Chocolatey (paquet « chocolateygui »)." }
        [pscustomobject]@{ id='scoop';  label='Scoop';        verArgs=@('--version'); updArgs=@('status');                      updMode='lines';    upgArgs=@('update','*');  upgOne=@() }
        [pscustomobject]@{ id='npm';    label='npm';          verArgs=@('-v');        updArgs=@('outdated','-g','--json');      updMode='jsonkeys'; upgArgs=@('update','-g'); upgOne=@() }
        [pscustomobject]@{ id='pnpm';   label='pnpm';         verArgs=@('-v');        updArgs=@('outdated','-g');               updMode='lines';    upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='yarn';   label='Yarn';         verArgs=@('-v');        updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='pip';    label='pip (Python)'; verArgs=@('--version'); updArgs=@('list','--outdated','--format=json'); updMode='jsonlist'; upgArgs=@();        upgOne=@('install','-U','{pkg}') }
        [pscustomobject]@{ id='pipx';   label='pipx';         verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='cargo';  label='Cargo (Rust)'; verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
        [pscustomobject]@{ id='gem';    label='RubyGems';     verArgs=@('--version'); updArgs=@('outdated');                    updMode='lines';    upgArgs=@('update');      upgOne=@() }
        [pscustomobject]@{ id='dotnet'; label='.NET SDK';     verArgs=@('--version'); updArgs=@();                             updMode='none';     upgArgs=@();              upgOne=@() }
    )
}

# The graphical interface REALLY present for a manager, or $null.
# Returns @{ target; label; help }: enough to build the button and the action.
function Get-PkgGui {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg -or -not $mg.guiKind) { return $null }
    $targetPath = $null
    switch ($mg.guiKind) {
        'uri' {
            # An unregistered protocol would open an "application not found" dialog.
            if (Test-Path -LiteralPath ("Registry::HKEY_CLASSES_ROOT\" + $mg.guiProbe)) { $targetPath = $mg.guiTarget }
        }
        'exe' {
            $c = Get-Command $mg.guiProbe -ErrorAction SilentlyContinue
            if ($c -and $c.Source) { $targetPath = $c.Source }
            else {
                $rootPath = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { 'C:\ProgramData\chocolatey' }
                foreach ($p in @((Join-Path $rootPath ('bin\' + $mg.guiTarget)), (Join-Path $rootPath ('lib\chocolateygui\tools\' + $mg.guiTarget)))) {
                    if (Test-Path -LiteralPath $p) { $targetPath = $p; break }
                }
            }
        }
    }
    if (-not $targetPath) { return $null }
    return @{ target = $targetPath; label = $mg.guiLabel; help = $mg.guiHelp }
}

# Checks the updates available from ONE manager (a slow call, over the network). Handles the
# output AND the exit code through Invoke-Native.
# Returns @{ count; items; pkgs; supported; selectable }.
#   items = DISPLAY strings, cut at 25, which fill the card's detail
#   pkgs  = the COMPLETE list @{ id; title; detail }, `id` being the identifier to hand the
#           manager to update THAT package only. Without it no choice is possible: one
#           cannot ask "which ones?" holding nothing but display labels.
function Get-PkgUpdates {
    param([Parameter(Mandatory)][string]$Id)
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $false } }
    $selectable = ($null -ne $mg.upgOne -and @($mg.upgOne).Count -gt 0)
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $selectable } }
    if ($mg.updMode -eq 'none' -or $mg.updArgs.Count -eq 0) { return @{ count = 0; items = @(); pkgs = @(); supported = $false; selectable = $selectable } }
    $count = 0; $items = @(); $pkgs = @()
    try {
        $r = Invoke-Native -File $cmd.Source -Arguments $mg.updArgs
        $out = "$($r.Output)"
        switch ($mg.updMode) {
            'jsonlist' {
                if ($out.Trim()) {
                    $j = $out | ConvertFrom-Json
                    foreach ($e in @($j)) {
                        $items += ("{0}  {1} -> {2}" -f $e.name, $e.version, $e.latest_version)
                        $pkgs  += [ordered]@{ id = "$($e.name)"; title = "$($e.name)"; detail = ("{0} -> {1}" -f $e.version, $e.latest_version) }
                    }
                    $count = $items.Count
                }
            }
            'jsonkeys' {
                if ($out.Trim() -and $out.Trim() -ne '{}') {
                    $j = $out | ConvertFrom-Json
                    foreach ($e in @($j.PSObject.Properties)) {
                        $items += ("{0} -> {1}" -f $e.Name, $e.Value.latest)
                        $pkgs  += [ordered]@{ id = "$($e.Name)"; title = "$($e.Name)"; detail = "$($e.Value.latest)" }
                    }
                    $count = $items.Count
                }
            }
            'chocor' {
                foreach ($l in (($out -split "`r?`n") | Where-Object { $_ -match '\|' })) {
                    $p = $l.Split('|')
                    $items += ("{0}  {1} -> {2}" -f $p[0], $p[1], $p[2])
                    $pkgs  += [ordered]@{ id = "$($p[0])"; title = "$($p[0])"; detail = ("{0} -> {1}" -f $p[1], $p[2]) }
                }
                $count = $items.Count
            }
            'winget' {
                $lines = @($out -split "`r?`n"); $idx = -1
                for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{3,}') { $idx = $i; break } }
                if ($idx -ge 0 -and $idx -lt ($lines.Count - 1)) {
                    # winget's columns: Name | Id | Version | Available | Source. The Id is
                    # the ONLY column one can target a package with -- the name is not unique.
                    #
                    # Cut at FIXED POSITIONS, not on "two spaces or more": winget fills each
                    # column to the width of its longest element, so a long name leaves just
                    # ONE space before the Id, and a wide version number leaves one before the
                    # next. Seen for real: splitting on spaces returned "12.0.40664.0" as the
                    # identifier of the Visual C++ Redistributable -- an update would have
                    # aimed at a package that does not exist. The column starts are read from
                    # the header line.
                    $hdr = if ($idx -ge 1) { "$($lines[$idx-1])" } else { '' }
                    $debuts = @()
                    if ($hdr.Length) {
                        if ($hdr[0] -ne ' ') { $debuts += 0 }
                        for ($k = 2; $k -lt $hdr.Length; $k++) {
                            if ($hdr[$k] -ne ' ' -and $hdr[$k-1] -eq ' ' -and $hdr[$k-2] -eq ' ') { $debuts += $k }
                        }
                    }
                    $rest = @($lines[($idx+1)..($lines.Count-1)] | Where-Object { $_.Trim() -and $_ -notmatch 'niveau|upgrade|mise' })
                    foreach ($l in $rest) {
                        $cols = @()
                        if ($debuts.Count -ge 2) {
                            for ($c = 0; $c -lt $debuts.Count; $c++) {
                                $s = $debuts[$c]
                                if ($s -ge $l.Length) { $cols += ''; continue }
                                $e = if ($c + 1 -lt $debuts.Count) { [Math]::Min($debuts[$c+1], $l.Length) } else { $l.Length }
                                $cols += $l.Substring($s, $e - $s).Trim()
                            }
                        } else {
                            # A fallback when the header is missing, on unexpected output:
                            # an approximate list beats nothing at all.
                            $cols = @(($l -split '\s{2,}') | Where-Object { $_ } | ForEach-Object { "$_".Trim() })
                        }
                        if (-not $cols.Count) { continue }
                        $name = "$($cols[0])"
                        if (-not $name) { continue }
                        $items += $name
                        # NO variable named $pid: it is a read-only automatic variable, the
                        # process id. Assigning to it raised an exception the catch swallowed,
                        # and the list came back EMPTY.
                        $ident = if ($cols.Count -ge 2) { "$($cols[1])" } else { '' }
                        if ($ident) {
                            $det = if ($cols.Count -ge 4 -and $cols[3]) { ("{0} -> {1}" -f "$($cols[2])", "$($cols[3])") } else { $ident }
                            $pkgs += [ordered]@{ id = $ident; title = $name; detail = $det }
                        }
                    }
                    $count = $items.Count
                }
            }
            'lines' {
                $items = @(($out -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch '^Name|^-{3,}|is up to date|Everything' })
                $count = $items.Count
            }
        }
    } catch { }
    # The selectable list is NOT truncated: one cannot tick what one cannot see. Only the
    # card's condensed display is.
    if ($items.Count -gt 25) { $items = @($items[0..24] + "... (+$($items.Count - 25))") }
    return @{ count = $count; items = @($items); pkgs = @($pkgs); supported = $true; selectable = $selectable }
}

# Puts a package manager's failure message IN PLAIN WORDS: what it means, and what to do.
# The tool's raw message is jargon -- "a different installation technology" evokes nothing --
# and the card must carry the explanation.
function Get-PkgFailureAdvice {
    param([string]$Reason)
    if (-not $Reason) { return $null }

    if ($Reason -match 'technologie d.installation est diff|install technology is different') {
        return ("En clair : cette application a été installée à l'origine par un autre canal " +
                "que winget (préinstallée avec Windows, installateur classique, Store...) ; winget refuse de mettre à jour par-dessus. " +
                "Que faire : réinstaller l'application depuis son installateur officiel — l'installation est " +
                "remplacée proprement, les données et profils sont conservés.")
    }
    # "Already done" is NOT a failure: winget refuses because the installed version is
    # already at least as recent. Seen with Edge, which had updated itself through its own
    # channel between the check and the click -- so Vigie offered an update already carried
    # out, then displayed it as a FAILURE. Recognising that pattern lets the line be removed
    # instead of blamed.
    if ($Reason -match 'Aucune version de package plus|No newer package versions are available|No applicable (update|upgrade) found|No available upgrade found') {
        return "En clair : c'est déjà fait — la version installée est au moins aussi récente que celle proposée. La liste datait d'avant. Rien à faire."
    }
    if ($Reason -match '0x80070005|acc.s refus|access is denied') {
        return "En clair : Windows a refusé l'accès. Que faire : réessayer ; si ça persiste, un antivirus ou un verrou de fichier bloque l'écriture."
    }
    if ($Reason -match '1603|0x80070643') {
        return "En clair : l'installateur du paquet a échoué (erreur générique MSI). Que faire : redémarrer Windows puis réessayer — c'est la cause la plus fréquente."
    }
    return $null
}

# Does the failure merely say THE WORK IS ALREADY DONE? Then the line has no business in a
# list of updates to offer.
function Test-PkgFailureIsDone {
    param([string]$Reason)
    if (-not $Reason) { return $false }
    return [bool]($Reason -match 'Aucune version de package plus|No newer package versions are available|No applicable (update|upgrade) found|No available upgrade found')
}

# Updates the packages of ONE manager (a slow, system-wide call). It inherits the server's
# elevation. Handles output and exit code. Returns @{ ok; supported; exit; output }.
#
# -Pkgs empty  -> the historical behaviour: the WHOLE manager, in one command.
# -Pkgs filled -> one command PER package (upgOne), so those only. When the manager cannot
#   target a package, the selection is ignored and the global update happens instead: which
#   is what the choice window told the user.
function Invoke-PkgUpgrade {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string[]]$Pkgs,
        # THE WHOLE MANAGER, AND IT HAS TO BE SAID (D131). This is where "upgrade --all" leaves from: an empty
        # list meant all of it, and that installed sixteen programs instead of one on 06/10. The gate sits here, as
        # close to the gesture as possible, because a mistyped parameter name upstream must never be able to open it.
        [switch]$All
    )
    $mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $mg) { return @{ ok = $false; supported = $false; output = '' } }
    $liste = @($Pkgs | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" })
    $unParUn = ($liste.Count -gt 0 -and $null -ne $mg.upgOne -and @($mg.upgOne).Count -gt 0)
    # NOTHING DESIGNATED IS NOT EVERYTHING (D131): with no package and no -All, nothing runs, and it says so.
    if (-not $liste.Count -and -not $All) {
        return @{ ok = $false; supported = $true; output = ''; count = 0; failed = @()
                  reason = "aucun paquet désigné : précisez les paquets, ou demandez explicitement tout le gestionnaire" }
    }
    if (-not $unParUn -and (-not $mg.upgArgs -or @($mg.upgArgs).Count -eq 0)) { return @{ ok = $false; supported = $false; output = '' } }
    $cmd = Get-Command $Id -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Source) { return @{ ok = $false; supported = $false; output = '' } }

    # 3010 = ERROR_SUCCESS_REBOOT_REQUIRED: the installation SUCCEEDED and asks for a
    # restart. Treating it as a failure ("ok=False") was wrong and showed an error on an
    # operation that had worked -- seen with Chocolatey.
    # 1641 = restart ALREADY triggered, the same family.
    if (-not $unParUn) {
        $r = Invoke-Native -File $cmd.Source -Arguments $mg.upgArgs
        $rebootRequired = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
        return @{ ok = ($r.Ok -or $rebootRequired); supported = $true; exit = $r.ExitCode
                  reboot = $rebootRequired; output = $r.Output; count = 0; failed = @() }
    }

    $outputs = @(); $failures = @(); $raisons = @{}; $rebootRequired = $false; $dernier = 0
    foreach ($p in $liste) {
        # .Replace rather than -replace: a package identifier ('Microsoft.VC++', 'a.b')
        # contains characters the regular-expression engine would interpret.
        $argv = @($mg.upgOne | ForEach-Object { "$_".Replace('{pkg}', $p) })
        $r = Invoke-Native -File $cmd.Source -Arguments $argv
        $rb = ($r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)
        if ($rb) { $rebootRequired = $true }
        if (-not ($r.Ok -or $rb)) {
            # The REASON for the failure: the last meaningful line of winget's output --
            # it is the one that says what to do ("a different installation technology...").
            $usefulLine = @(("$($r.Output)" -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
            $motif = if ($usefulLine) { "$usefulLine".Trim() } else { '' }
            # "Nothing newer to install" is not a failure: the package is already up to date,
            # having updated itself through its own channel since the check. Counting it as a
            # failure turned the whole operation red and showed an error on work that had
            # nothing to do -- seen with Edge.
            if (Test-PkgFailureIsDone -Reason $motif) {
                $outputs += ("=== $p (code $($r.ExitCode)) === deja a jour, ignore")
                continue
            }
            $failures += $p
            if ($motif) { $raisons[$p] = $motif }
        }
        $dernier = $r.ExitCode
        $outputs += ("=== $p (code $($r.ExitCode)) ===" + [Environment]::NewLine + "$($r.Output)")
    }
    return @{ ok = ($failures.Count -eq 0); supported = $true; exit = $dernier; reboot = $rebootRequired
              output = ($outputs -join ([Environment]::NewLine + [Environment]::NewLine))
              count = $liste.Count; failed = @($failures); reasons = $raisons }
}

# The GENERIC, non-blocking launcher of a package operation: 'check' or 'upgrade'.
# It marks the card as busy, naming the operation, starts the detached worker and hands back
# at once. One piece of code shared by both actions, so nothing is duplicated.
function Start-PkgJob {
    param(
        [Parameter(Mandatory)][string]$Mgr,
        [ValidateSet('check','upgrade')][string]$Op = 'check',
        # THE PACKAGES KEPT. An empty list no longer means "all": that takes -All (D131). See Invoke-PkgUpgrade.
        [string[]]$Pkgs,
        <#
            -All: THE WHOLE MANAGER, AND IT HAS TO BE SAID (D131).

            An empty list used to mean "all of it". On 06/10 a call passed the list under a parameter name that did
            not exist, it arrived empty, and winget received `upgrade --all`: SIXTEEN programs installed instead of
            one, among them the owner's terminal, closed with the work running inside it, and WSL, which he had kept
            for himself.

            None of it threw: every link did what it was asked. The DEFECT is the design -- an absence read as the
            widest permission. From now on, "all" is asked for.
        #>
        [switch]$All,
        # FOR WHICH ACCOUNT (D128). A manager installed in a profile answers only in that profile's session, and the
        # service account has no winget at all. Without an account there is nobody to ask, and the job is refused
        # rather than answering for the wrong person.
        [string]$Account,
        [string]$Backend = (Get-BackendRoot)
    )
    $known = Get-PackageManagerCatalog | Where-Object { $_.id -eq $Mgr } | Select-Object -First 1
    if (-not $known) { return @{ message = "Gestionnaire inconnu : $Mgr"; result = @{ ok = $false } } }
    $choisis = @($Pkgs | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" })
    # NOTHING NAMED IS NOT EVERYTHING (D131): with no package AND no -All, nothing starts.
    if ($Op -eq 'upgrade' -and -not $choisis.Count -and -not $All) {
        return @{ message = "Aucun paquet désigné : précisez les paquets, ou demandez explicitement tout le gestionnaire."
                  result = @{ ok = $false } }
    }
    $unParUn = ($choisis.Count -gt 0 -and $null -ne $known.upgOne -and @($known.upgOne).Count -gt 0)
    if ($Op -eq 'check'   -and ($known.updMode -eq 'none' -or @($known.updArgs).Count -eq 0)) {
        return @{ message = "Verification non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    if ($Op -eq 'upgrade' -and -not $unParUn -and (-not $known.upgArgs -or @($known.upgArgs).Count -eq 0)) {
        return @{ message = "Mise a jour automatique non prise en charge pour $($known.label)."; result = @{ ok = $false } }
    }
    if (-not $Account) { $Account = Get-StateAccount }
    if (-not $Account) {
        return @{ message = "Aucun compte identifié : une vérification de paquets se fait dans une session."
                  result = @{ ok = $false } }
    }
    $stateDir = Get-VarPath -Backend $Backend -Kind 'cache'
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    # ONE STORE PER ACCOUNT (D128): two accounts do not have the same packages, and a single file had each one
    # overwriting the other.
    $outFile = Join-Path $stateDir ('pkgupdates-' + $Account + '.json')
    # WHAT IS RUNNING IS SAID BY THE BUSY MARK (doc/progress/targeting/operations.md). This file keeps the
    # detail only: the last known result, and the packages retained, so the card says "1 package of 3".
    $entry = @{ op = $Op; startedAt = (Get-Date).ToString('s') }
    if ($Op -eq 'upgrade' -and $choisis.Count -gt 0) { $entry.sel = @($choisis) }
    if (Test-Path $outFile) {
        try {
            $j = Get-Content $outFile -Raw | ConvertFrom-Json; $e = $j.$Mgr
            if ($e -and $null -ne $e.count) {
                $entry.count = [int]$e.count; $entry.items = @($e.items)
                if ($e.pkgs) { $entry.pkgs = @($e.pkgs) }
            }
            if ($e -and $e.at) { $entry.at = "$($e.at)" }
            if ($e -and $e.last) { $entry.last = $e.last }
        } catch { }
    }
    Update-StateJson -Path $outFile -Set @{ $Mgr = $entry } | Out-Null
    $verb = if ($Op -eq 'upgrade') { 'Mise à jour' } else { 'Vérification' }
    $started = $false
    try {
        $started = [bool](Start-Operation -Module ("pkg-" + $Mgr) `
                              -Action $(if ($Op -eq 'upgrade') { 'pkg-upgrade' } else { 'pkg-check-updates' }) `
                              -Label ("$verb de " + $known.label) -Probes @('packages.probe.ps1') `
                              -Worker 'pkg-job.worker.ps1' -ArgsMap @{ mgr = $Mgr; op = $Op; pkgs = $choisis; account = $Account; all = [bool]$All } `
                              -Button $(if ($Op -eq 'upgrade') { 'pkg-list-updates' } else { '' }) -Backend $Backend)
    } catch { }
    if (-not $started) { return @{ message = "Impossible de lancer l'opération sur $($known.label)."; result = @{ ok = $false } } }
    $portee = if ($Op -eq 'upgrade' -and $unParUn) { " ($($choisis.Count) paquet(s) sélectionné(s))" } else { "" }
    @{
        message = "$verb de $($known.label) lancée en tâche de fond$portee."
        result  = @{ ok = $true; async = $true; module = ("pkg-" + $Mgr); invalidate = @('packages.probe.ps1') }
    }
}

<#
    WHICH PACKAGE MANAGERS EACH ACCOUNT HAS, asked of that account's own session.

    WHY. Measured on 05/10: the server app saw Chocolatey and pip, both installed machine-wide, and NOT winget,
    although this account has it. A manager installed in a profile resolves from that profile's PATH, and the service
    account's PATH never names it -- so the main manager of the machine was missing from the panel (C4 of
    `targeting/multi-account-server.md`).

    HOW. The same door WSL already uses (D113 and the client app's desktop orders): the server asks every account
    whose client app beats, through the `pkg-inventory` action, which runs in that session. One entry per account,
    refreshed at most once an hour -- a manager is not installed twice a day, and the reading costs a process launch
    per manager.
#>
function Get-PkgInventoryPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'pkg-inventory.json'
}

# THE INVENTORY OF ONE ACCOUNT, or the union of every account kept when none is named. The union is what a card
# without a requester can honestly show: "this machine has winget somewhere", with the account that proves it.
function Get-PkgInventory {
    param([string]$Backend = (Get-BackendRoot), [string]$Account)
    try {
        $path = Get-PkgInventoryPath -Backend $Backend
        if (-not (Test-PathSafe $path)) { return @() }
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $j) { return @() }
        $rows = @()
        foreach ($prop in $j.PSObject.Properties) {
            if ($Account -and "$($prop.Name)" -ne "$Account") { continue }
            foreach ($m in @($prop.Value.managers)) {
                if (-not $m -or -not $m.id) { continue }
                $rows += [pscustomobject]@{ Id = "$($m.id)"; Source = "$($m.source)"; Version = "$($m.version)"
                                            Account = "$($prop.Name)"; At = "$($prop.Value.at)" }
            }
        }
        # ONE LINE PER MANAGER: the first account that has it answers for it, and the order of accounts is stable.
        $seen = @{}
        $out = @()
        foreach ($row in @($rows | Sort-Object Account, Id)) {
            if ($seen.ContainsKey($row.Id)) { continue }
            $seen[$row.Id] = $true
            $out += $row
        }
        return @($out)
    } catch { return @() }
}

function Update-PkgInventory {
    param([string]$Backend = (Get-BackendRoot), [int]$EveryMinutes = 60)
    foreach ($held in @(Get-HeldResources -Backend $Backend)) {
        if ("$($held.resource)" -eq 'machine') { return $null }
    }
    $path = Get-PkgInventoryPath -Backend $Backend
    # ONE ACCOUNT PER PASS, the most overdue of them. Asking three accounts at once would launch eleven processes in
    # three sessions in the same second, and the gate below would hide it.
    $kept = $null
    try { if (Test-PathSafe $path) { $kept = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } } catch { }
    $candidate = $null
    $oldest = $null
    foreach ($row in @(Get-ClientWatchRows -Backend $Backend | Where-Object { $_.Status -eq 'ok' })) {
        $account = "$($row.Account)"
        if (-not $account) { continue }
        # THE GATE IS READ IN TICKS (D44): an ISO date read back from JSON is a [datetime] whose string form is local
        # and no longer parses, so a gate compared as text never holds -- it cost a client app asked every pass.
        $ticks = 0
        try { $ticks = [long]$kept.$account.atTicks } catch { }
        if ($ticks -and ([datetime]::UtcNow - [datetime]$ticks).TotalMinutes -lt $EveryMinutes) { continue }
        if ($null -eq $oldest -or $ticks -lt $oldest) { $oldest = $ticks; $candidate = $account }
    }
    if (-not $candidate) { return $null }
    $answer = $null
    try { $answer = Invoke-ClientTask -Account $candidate -Type 'pkg-inventory' -Module 'tools' -TimeoutSec 60 -Backend $Backend } catch { }
    if (-not $answer -or -not $answer.result -or -not $answer.result.ok) { return $null }
    $entry = [ordered]@{
        at       = ([datetime]::UtcNow).ToString('o')
        atTicks  = ([datetime]::UtcNow).Ticks
        managers = @($answer.result.managers)
    }
    try { Update-StateJson -Path $path -Set @{ $candidate = $entry } | Out-Null } catch { }
    # THE CARDS MUST BE RECOMPUTED: a manager that has just appeared has no card until the probe runs again.
    try { Remove-ProbeCache -Names @('packages.probe.ps1') -Backend $Backend } catch { }
    return [pscustomobject]@{ Account = $candidate; Count = @($answer.result.managers).Count }
}

function Get-VendorKey {
    param([string]$Name)
    if (-not "$Name".Trim()) { return '' }
    $key = "$Name".ToUpperInvariant()
    $key = $key -replace '\((R|TM|C)\)', ' '
    $key = $key -replace '[^A-Z0-9]+', ' '
    $key = ($key -replace '\s+', ' ').Trim()
    # SUFFIXES STACK: "Co.,Ltd" carries two. We strip while there are any, and never empty
    # the name doing so -- "Technology Ltd" must stay TECHNOLOGY.
    $again = $true
    while ($again) {
        $again = $false
        foreach ($suffix in $script:VendorSuffixes) {
            $shorter = $key -replace ('\s+' + $suffix + '$'), ''
            if ($shorter -ne $key -and $shorter.Trim()) { $key = $shorter.Trim(); $again = $true }
        }
    }
    $key
}

function Get-VendorTable {
    param([string]$Backend = (Get-BackendRoot))
    if ($null -ne $script:VendorTable) { return $script:VendorTable }
    $script:VendorTable = @{}
    $file = Join-Path (Join-Path (Split-Path (Split-Path $Backend -Parent) -Parent) 'config') 'vendor-names.json'
    if (Test-PathSafe $file) {
        try {
            $read = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($read.noms.PSObject.Properties)) {
                # THE TABLE IS INDEXED BY THE FOLDED KEY, not by what is written. Whoever
                # keeps this file copies the name AS THEY SEE IT; folding it is the code's
                # job, exactly as it folds what comes from Windows. Hand-written "A-Volute"
                # matched nothing, the key being "A VOLUTE" (10/09).
                if ("$($entry.Value.nom)".Trim()) { $script:VendorTable[(Get-VendorKey $entry.Name)] = "$($entry.Value.nom)" }
            }
        } catch { }
    }
    $script:VendorTable
}

function Get-VendorName {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Key,
        [string[]]$Seen = @(),
        [string]$Backend = (Get-BackendRoot)
    )
    $table = Get-VendorTable -Backend $Backend
    if ($Key -and $table.ContainsKey($Key)) { return $table[$Key] }
    $candidates = @($Seen | Where-Object { "$_".Trim() })
    if (-not $candidates.Count) { return $Key }
    # A SPELLING ACTUALLY SEEN, never a manufactured string. "INTEL" is the most frequent
    # one here and it SHOUTS: at equal information, mixed case wins.
    $best = $candidates | Group-Object | ForEach-Object {
        [pscustomobject]@{
            Spelling = $_.Name
            Shouts   = [bool]($_.Name -cmatch '^[^a-z]+$')
            Seen     = $_.Count
            Length   = $_.Name.Length
        }
    } | Sort-Object Shouts, @{ Expression = 'Seen'; Descending = $true }, Length
    @($best)[0].Spelling
}
