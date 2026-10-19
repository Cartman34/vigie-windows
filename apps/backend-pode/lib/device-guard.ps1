# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: log, native, paths, store, var
<#
    Intent: VIRTUALISATION SECURITY (VBS / HVCI): what is on, what a change costs, and the key saved before touching it -- a feature switched off without a backup is a machine one cannot put back.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# --- Virtualisation security (VBS / HVCI) ---------------------------------------
# THE catalogue of this subject, defined once (D15): registry keys, value names and labels.
# The probe, the state reading and the switch all draw on them.
#
# What sets this subject apart from the Windows Update lock: a value written here only takes
# effect at the next RESTART. So there are TWO states never to be confused --
#   `configured`: what the registry asks for (what is written, verifiable at once);
#   `running`   : what Windows actually runs (it will not move before a restart).
function Get-DeviceGuardCatalog {
    $rootPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    [ordered]@{
        Root      = $rootPath
        RootReg   = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard'   # forme attendue par reg.exe
        Features  = [ordered]@{
            vbs  = [pscustomobject]@{
                Key = $rootPath; Name = 'EnableVirtualizationBasedSecurity'
                Label = 'Sécurité par virtualisation (VBS)'; Court = 'VBS'
            }
            hvci = [pscustomobject]@{
                Key = "$rootPath\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = 'Enabled'
                Label = 'Intégrité mémoire (HVCI)'; Court = 'intégrité mémoire'
            }
        }
    }
}

# The marker of switches ASKED FOR and not yet effective (var/cache). It serves two purposes:
# knowing what to display ("demandé, effectif au redémarrage") and knowing which value to
# switch to when one clicks again before having restarted.
function Get-DeviceGuardMarkerPath {
    param([string]$Backend = (Get-BackendRoot))
    Get-VarPath -Backend $Backend -Kind 'cache' -File 'deviceguard.json'
}

# The REAL and complete state of VBS / HVCI. READ ONLY.
#
# For each feature:
#   configured : the registry value (0/1), $null when the value does not exist
#   running    : what Windows runs right now (Win32_DeviceGuard)
#   requested  : what Vigie asked for and which is waiting for a restart ($null otherwise)
#   pending    : a request of Vigie's is not yet effective
#   effective  : the state to DISPLAY and the one a switch works from -- the pending request
#                if there is one, otherwise what is running. Switching from `running` while a
#                request waits would go backwards without saying so.
function Get-DeviceGuardState {
    param([string]$Backend = (Get-BackendRoot))
    $cat = Get-DeviceGuardCatalog
    $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $running = @{
        vbs  = [bool]($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2)
        hvci = [bool]($dg -and ($dg.SecurityServicesRunning -contains 2))
    }
    $marque = @{}
    try {
        $f = Get-DeviceGuardMarkerPath -Backend $Backend
        if (Test-Path -LiteralPath $f) {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $marque[$p.Name] = $p.Value }
        }
    } catch { }

    $State = [ordered]@{ elevated = (Test-Elevated); vbsStatus = $(if ($dg) { [int]$dg.VirtualizationBasedSecurityStatus } else { $null }) }
    foreach ($id in $cat.Features.Keys) {
        $f = $cat.Features[$id]
        $cfg = $null
        try {
            $v = (Get-ItemProperty -LiteralPath $f.Key -Name $f.Name -ErrorAction SilentlyContinue).$($f.Name)
            if ($null -ne $v) { $cfg = [int]$v }
        } catch { }
        $dem = $null
        try { if ($marque[$id] -and $null -ne $marque[$id].requested) { $dem = [int]$marque[$id].requested } } catch { }
        # A request that already matches what is running is no longer pending: the marker
        # goes stale on its own at the restart, with no arbitrary delay to tune.
        $pending = ($null -ne $dem -and [bool]$dem -ne $running[$id])
        $State[$id] = [ordered]@{
            label      = $f.Label
            court      = $f.Court
            configured = $cfg
            running    = $running[$id]
            requested  = $(if ($pending) { $dem } else { $null })
            pending    = $pending
            effective  = $(if ($pending) { [bool]$dem } else { $running[$id] })
        }
    }
    $State['pending'] = ($State.vbs.pending -or $State.hvci.pending)
    $State
}

# Backs up the DeviceGuard key BEFORE any writing, into var/log.
# A startup setting is hard to undo by hand: we keep what it takes to go back.
function Backup-DeviceGuardKey {
    param([string]$Backend = (Get-BackendRoot))
    $cat = Get-DeviceGuardCatalog
    $f = Join-Path (Get-LogDir -Backend $Backend) ('deviceguard_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.reg')
    try {
        $r = Invoke-Native -File 'reg.exe' -Arguments @('export', $cat.RootReg, $f, '/y')
        # D43: the backup exists when the FILE is there, not when the call has returned.
        if ((Test-Path -LiteralPath $f) -and $r.Ok) { return $f }
    } catch { }
    return $null
}

# Writes the value of ONE feature. The ONLY entry point for WRITING (D15).
#
# It returns an object, where Set-UpdateLock returns a boolean, because there is nothing to
# preserve here: no existing caller, and "written" does not tell the story -- one has to tell
# "already at that value", "written, waiting for the restart" and "written but still running"
# apart, the last being a value imposed by the UEFI or by a policy. The result is READ BACK
# from the registry, never assumed (D43).
function Set-DeviceGuardFeature {
    param(
        [Parameter(Mandatory)][ValidateSet('vbs','hvci')][string]$Feature,
        [Parameter(Mandatory)][bool]$Enable,
        [string]$Backend = (Get-BackendRoot)
    )
    $cat = Get-DeviceGuardCatalog
    if (-not (Test-Elevated)) {
        try { Write-Log -Backend $Backend -Name 'deviceguard' -Level 'WARN' -Message (Get-Label 'common.refuse-le-serveur-est' $Feature) } catch { }
        return @{ ok = $false; elevated = $false }
    }
    $targetValue = [int][bool]$Enable
    $before = Get-DeviceGuardState -Backend $Backend
    $sauvegarde = Backup-DeviceGuardKey -Backend $Backend

    # The values to lay down. HVCI CANNOT run without VBS: disabling VBS while leaving memory
    # integrity asked for leaves an inconsistent configuration, which Windows sometimes
    # resolves by switching VBS back on. So both are turned off -- and it is SAID.
    # The converse is not true: enabling VBS does not enable memory integrity behind the
    # user's back; that is a separate decision with its own trade-offs.
    $toWrite = @( [pscustomobject]@{ Id = $Feature; Value = $targetValue } )
    $hvciCoupeAussi = $false
    if ($Feature -eq 'vbs' -and $targetValue -eq 0) {
        $toWrite += [pscustomobject]@{ Id = 'hvci'; Value = 0 }
        $hvciCoupeAussi = $true
    }

    $erreurs = @()
    foreach ($e in $toWrite) {
        $f = $cat.Features[$e.Id]
        try {
            # Idempotent: New-Item -Force on an existing key does not erase it, and writing
            # the same value again has no effect. Replaying the switch breaks nothing.
            if (-not (Test-Path -LiteralPath $f.Key)) { New-Item -Path $f.Key -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -Path $f.Key -Name $f.Name -Value $e.Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        } catch {
            $erreurs += "$($e.Id) : $($_.Exception.Message)"
        }
    }

    # The marker: what Vigie asked for. It is used to offer the restart, and to know which
    # value to switch back to if the user clicks again before restarting.
    try {
        $set = @{}
        foreach ($e in $toWrite) { $set[$e.Id] = @{ requested = $e.Value; at = (Get-Date).ToUniversalTime().ToString('o') } }
        Update-StateJson -Path (Get-DeviceGuardMarkerPath -Backend $Backend) -Set $set | Out-Null
    } catch { }

    # THE OBSERVATION: the REGISTRY is read back, the only state that can have changed now.
    # Reading `running` to judge would be a guaranteed false failure -- it will not move
    # before the restart. That is the difference not to miss with the Windows Update lock.
    $after = Get-DeviceGuardState -Backend $Backend
    $ecrit = ($after[$Feature].configured -eq $targetValue)
    try {
        Write-Log -Backend $Backend -Name 'deviceguard' -Message (Get-Label 'common.ecrit-configavant-configapres-actif' $Feature $targetValue $ecrit $($before[$Feature].configured) $($after[$Feature].configured) $($after[$Feature].running) $hvciCoupeAussi $sauvegarde $(if ($erreurs.Count) { ' erreurs=' + ($erreurs -join ' | ') } else { '' }))
    } catch { }

    @{
        ok             = $ecrit
        elevated       = $true
        feature        = $Feature
        value          = $targetValue
        already        = ($before[$Feature].configured -eq $targetValue)
        running        = $after[$Feature].running
        rebootNeeded   = ($after[$Feature].running -ne [bool]$targetValue)
        hvciCoupeAussi = $hvciCoupeAussi
        backup         = $sauvegarde
        errors         = @($erreurs)
        state          = $after
    }
}

# Switches ONE feature, from the user's point of view: what the card DISPLAYS (`effective`)
# is inverted, not what is running. Clicking again before restarting therefore returns to the
# starting state, instead of writing the same value twice.
#
# It returns @{ message; result } directly: the two actions differ only by the feature's
# name, and there is no reason to write that report twice (D15).
function Invoke-DeviceGuardToggle {
    param(
        [Parameter(Mandatory)][ValidateSet('vbs','hvci')][string]$Feature,
        [string]$Backend = (Get-BackendRoot)
    )
    $inv = @('vbs.probe.ps1')
    $State = Get-DeviceGuardState -Backend $Backend
    $name  = $State[$Feature].court

    if (-not $State.elevated) {
        return @{
            message = "Le serveur de Vigie n'est pas administrateur : la bascule $name est impossible. Vigie doit être relancée en administrateur (l'invite UAC s'affichera)."
            result  = @{ ok = $false }
        }
    }

    $targetValue = -not $State[$Feature].effective
    $r = Set-DeviceGuardFeature -Feature $Feature -Enable $targetValue -Backend $Backend
    $verbe = if ($targetValue) { 'activée' } else { 'désactivée' }

    if (-not $r.ok) {
        $det = if (@($r.errors).Count) { ' ' + (@($r.errors) -join ' ; ') } else { '' }
        return @{
            message = "La valeur de $name n'a pas pu être écrite dans le registre.$det"
            result  = @{ ok = $false; invalidate = $inv }
        }
    }

    $bonus = if ($r.hvciCoupeAussi) { " L'intégrité mémoire est coupée avec elle : elle ne peut pas fonctionner sans VBS." } else { '' }
    $garde = if ($r.backup) { " Sauvegarde du registre : $($r.backup)." } else { " Attention : la sauvegarde du registre n'a pas pu être écrite." }

    if (-not $r.rebootNeeded) {
        # Value written AND already matching what runs: nothing to wait for.
        return @{
            message = "$name déjà $verbe : la configuration et l'état actif concordent, aucun redémarrage nécessaire.$bonus"
            result  = @{ ok = $true; invalidate = $inv }
        }
    }
    $rappel = if ($r.already) { " Cette valeur était déjà demandée : si elle ne s'applique toujours pas après un redémarrage, elle est imposée par l'UEFI ou par une stratégie d'entreprise." } else { '' }
    @{
        message = "$name sera $verbe au prochain redémarrage de Windows — la demande est écrite, elle ne prend effet qu'au démarrage.$bonus$rappel$garde"
        result  = @{ ok = $true; invalidate = $inv }
    }
}
