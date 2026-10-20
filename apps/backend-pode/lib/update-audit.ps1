# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: format, log, paths, settings, updates, watches
<#
    Intent: WHAT IS WRONG WITH WINDOWS UPDATE, AND WHY: the audit that goes round the machinery -- the policy, the services, the folders, the tasks -- and the ailments it reports, each with the gesture that repairs it. Reading and diagnosis only: the lock itself is laid by updates.ps1.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

# A complete audit of the Windows Update machinery. READ ONLY, it changes nothing.
#
# Reimplemented inside the repository: the audit served to understand why a lock does not
# hold -- a repairing service, a policy overwritten, a task recreated. A diagnostic function
# that requires an absent toolkit is precisely no use when one needs it.
#
# The report goes to var/log/ (the project's convention: everything the app generates lives
# under var/), in text to be read and in JSON to be reused.
#
# ITS LINES ARE SHOWN IN THE PANEL (S04, 30/09): the action hands them back and the page lays them out preformatted.
# They are therefore INTERFACE, and carry their accents -- the report used to be written for a file, read by nobody.
function Invoke-UpdateAudit {
    param([string]$Backend = (Get-BackendRoot))
    $cat    = Get-UpdateTaskCatalog
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir    = Get-LogDir -Backend $Backend
    $txt    = Join-Path $dir "update-audit_$stamp.txt"
    $json   = Join-Path $dir "update-audit_$stamp.json"
    $lines = New-Object System.Collections.Generic.List[string]
    $rap    = [ordered]@{}
    $L   = { param($s = '') $lines.Add([string]$s) }
    $Sec = { param($t) & $L ''; & $L ('===== ' + $t + ' =====') }

    $State = Get-UpdateLockState
    $rap.at       = (Get-Date).ToString('o')
    $rap.elevated = $State.elevated
    & $L ("Audit Windows Update du " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "  (administrateur = " + $State.elevated + ")")
    if (-not $State.elevated) { & $L "ATTENTION : serveur non administrateur — une partie de l'état n'est pas lisible." }

    & $Sec 'Verrouillage'
    & $L ("   Mises à jour automatiques coupées : " + $State.autoUpdatesOff + "   (NoAutoUpdate=" + $State.noAutoUpdate + ")")
    & $L ("   Verrou de permissions (ACL)       : " + $State.aclLock)
    & $L ("   Verrou complet                    : " + $State.locked)
    $rap.lock = @{ autoUpdatesOff = $State.autoUpdatesOff; noAutoUpdate = $State.noAutoUpdate
                   aclLock = $State.aclLock; locked = $State.locked }

    & $Sec 'Édition et licence'
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        & $L ("   " + $cv.ProductName + "  (EditionID=" + $cv.EditionID + ")  build " + $cv.CurrentBuild + "." + $cv.UBR)
        $rap.edition = @{ product = "$($cv.ProductName)"; editionId = "$($cv.EditionID)"; build = "$($cv.CurrentBuild).$($cv.UBR)" }
    } catch { & $L "   (illisible)" }

    # Policies explain most of the "the lock did not hold": a value written elsewhere, by a
    # GPO or another tool, overwrites ours without a word.
    $vider = {
        param($exePath, $title)
        & $Sec $title
        $o = [ordered]@{}
        if (-not (Test-Path -LiteralPath $exePath)) { & $L '   (absente)'; return $o }
        $p = Get-ItemProperty -LiteralPath $exePath -ErrorAction SilentlyContinue
        # A key that EXISTS can return $null -- no value at all, or a reading refused without
        # elevation. And $null.PSObject.Properties.Name returns one $null element, which gets
        # through the filter and is then used as an index: seen as "the array index evaluated
        # to null". So emptiness is ruled out explicitly, rather than a list of names assumed.
        if ($null -eq $p) { & $L '   (illisible ou vide)'; return $o }
        $names = @($p.PSObject.Properties.Name | Where-Object { $_ -and ("$_" -notlike 'PS*') })
        foreach ($n in $names) { & $L ("   {0,-40} = {1}" -f $n, $p.$n); $o[$n] = $p.$n }
        if (-not $names.Count) { & $L '   (vide)' }
        return $o
    }
    $rap.policyWindowsUpdate = & $vider $cat.RegWu 'Stratégie WindowsUpdate'
    $rap.policyAu            = & $vider $cat.RegAu 'Stratégie WindowsUpdate\AU'
    $rap.ux                  = & $vider $cat.RegUx 'Réglages UX (heures actives, notifications)'

    & $Sec 'Redémarrage en attente'
    $pending = [ordered]@{}
    $pending.CBS_RebootPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $pending.WU_RebootRequired = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pending.PendingFileRename = [bool]((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
    foreach ($k in $pending.Keys) { & $L ("   {0,-22} = {1}" -f $k, $pending[$k]) }
    $rap.pendingReboot = $pending

    & $Sec 'Tâches planifiées de mise à jour'
    if (-not @($State.tasks).Count) { & $L '   (aucune lisible — accès refusé ?)' }
    foreach ($p in $cat.TaskPaths) {
        $lot = @($State.tasks | Where-Object { $_.path -eq $p })
        & $L ''
        & $L ("[" + $p + "]")
        if (-not $lot.Count) { & $L '   (aucune / accès refusé)'; continue }
        foreach ($t in $lot) { & $L ("   {0,-34} {1}" -f $t.name, $t.state) }
    }
    $rap.tasks = @($State.tasks)
    $rap.tasksDisabled = $State.tasksDisabled
    $rap.tasksReady    = $State.tasksReady

    & $Sec 'Services de mise à jour'
    $svc = @()
    foreach ($n in $cat.Services) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $s) { & $L ("   {0,-16} (absent)" -f $n); continue }
        $dem = ''
        try { $dem = "$((Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue).StartMode)" } catch { }
        & $L ("   {0,-16} statut={1,-10} démarrage={2}" -f $n, $s.Status, $dem)
        $svc += @{ name = $n; status = "$($s.Status)"; start = $dem }
    }
    # WaaSMedicSvc happily puts the machinery back to work: its start mode read from the
    # registry is more reliable than the one the service manager reports.
    try {
        $wm = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -ErrorAction SilentlyContinue).Start
        if ($null -ne $wm) { & $L ("   WaaSMedicSvc Start (registre) = " + $wm + "  (2=automatique, 3=manuel, 4=désactivé)"); $rap.waasMedicStart = $wm }
    } catch { }
    $rap.services = $svc

    & $Sec 'Contexte'
    try {
        $bootLocal = (Get-BootTime).ToLocalTime()
        & $L ("   Dernier démarrage : " + $bootLocal)
        $rap.lastBoot = "$bootLocal"
    } catch { }
    $hf = @()
    try {
        foreach ($h in (Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5)) {
            & $L ("   {0,-12} {1}" -f $h.HotFixID, $h.InstalledOn)
            $hf += @{ id = "$($h.HotFixID)"; installedOn = "$($h.InstalledOn)" }
        }
    } catch { }
    $rap.hotfixes = $hf

    $ecrit = $false
    try {
        ($lines -join "`r`n") | Out-File -FilePath $txt  -Encoding UTF8
        ($rap | ConvertTo-Json -Depth 8) | Out-File -FilePath $json -Encoding UTF8
        # D43: the report is "written" when the FILE EXISTS, not when the call has returned.
        $ecrit = (Test-Path -LiteralPath $txt) -and (Test-Path -LiteralPath $json)
    } catch {
        try { Write-Log -Backend $Backend -Name 'updateaudit' -Level 'ERROR' -Message $_.Exception.Message } catch { }
    }
    return @{ ok = $ecrit; txt = $txt; json = $json; elevated = $State.elevated; state = $State; lines = @($lines) }
}

<#
    EVERYTHING THAT GOES WRONG WITH WINDOWS UPDATE, IN ONE PLACE.

    The card showed a number and nothing else. On 18/09, 15 updates were requested and 14 became "not found at install
    time": only a Lenovo driver was installed, and the card still read "installation réussie". A few days earlier it
    announced 46 to 48 updates where an online search found 4, and nothing recorded either figure, so neither could be
    checked afterwards. The owner asked on 20/09 that the card report every problem, one way or another.

    Every reading here is cheap: the update history is read in 35 ms, the System log through its own filter.
    Nothing is installed, nothing is hidden, nothing is repaired: the card says, the user decides.
#>
function Get-WindowsUpdateAilments {
    param(
        [string]$Backend = (Get-BackendRoot),
        # The local count the card shows, the last online scan, and the last installation run, as the probe knows them.
        [int]$LocalCount = -1,
        $Scan,
        $Install
    )
    $found = @()

    # --- What the history says: an update installed again and again, and the failures ---------
    $history = @()
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $total = $searcher.GetTotalHistoryCount()
        if ($total -gt 0) { $history = @($searcher.QueryHistory(0, [math]::Min(120, $total))) }
    } catch { }
    $recent = @($history | Where-Object { $_.Date -and $_.Date -gt (Get-Date).AddDays(-7) })
    foreach ($group in @($recent | Where-Object { $_.ResultCode -eq 2 } | Group-Object Title | Where-Object { $_.Count -ge 3 })) {
        $last = @($group.Group | Sort-Object Date -Descending)[0]
        $found += [pscustomobject]@{
            Status = 'warn'
            Label  = 'Mise à jour réinstallée en boucle'
            Detail = "$($group.Name) — installée avec succès $($group.Count) fois en sept jours, la dernière le " +
                     $last.Date.ToLocalTime().ToString('dd/MM à HH:mm') + ". Windows la repropose sans cesse : la réinstaller ne change rien."
        }
    }
    foreach ($entry in @($recent | Where-Object { $_.ResultCode -in 4, 5 })) {
        $code = ''
        try { $code = '0x{0:X8}' -f $entry.HResult } catch { }
        $found += [pscustomobject]@{
            Status = 'error'
            Label  = $(if ($entry.ResultCode -eq 5) { 'Installation annulée' } else { 'Installation en échec' })
            Detail = "$($entry.Title) — le " + $entry.Date.ToLocalTime().ToString('dd/MM à HH:mm') + $(if ($code) { ", code $code" } else { '' }) + '.'
        }
    }

    # --- What the last installation run left behind -------------------------------------------
    if ($Install -and "$($Install.phase)" -eq 'termine') {
        # @($null) IS AN ARRAY OF ONE: an installation run from before these identifiers were kept counted one missing
        # update that never existed, and the card went red for it (20/09).
        $missing = @()
        try { $missing = @($Install.introuvables | Where-Object { $_ }) } catch { }
        if ($missing.Count) {
            $found += [pscustomobject]@{
                Status = 'error'
                Label  = "Mises à jour disparues au moment d'installer"
                Detail = $(if ($missing.Count -eq 1) { "Une mise à jour demandée n'était plus servie" } else { "$($missing.Count) mises à jour demandées n'étaient plus servies" }) +
                         " par Windows quand l'installation a commencé : elles venaient du cache local, qui les gardait alors que Windows ne les propose plus. " +
                         "Une recherche en ligne remet la liste à jour."
            }
        }
    }

    # --- The local cache against the last online search ----------------------------------------
    if ($Scan -and $null -ne $Scan.trouvees -and $LocalCount -ge 0) {
        $online = [int]$Scan.trouvees
        $age = $null
        try { $age = ([datetime]::UtcNow - (ConvertTo-UtcDate $Scan.at)).TotalDays } catch { }
        if ([math]::Abs($LocalCount - $online) -ge 2) {
            $found += [pscustomobject]@{
                Status = 'warn'
                Label  = "Le cache local et l'analyse en ligne ne disent pas la même chose"
                Detail = "Le cache local de Windows en annonce $LocalCount, la dernière analyse en ligne en a trouvé $online" +
                         $(if ($null -ne $age) { ', il y a ' + [math]::Round($age) + ' jour(s)' } else { '' }) +
                         ". C'est l'analyse en ligne qui fait foi : « Recherche en ligne » remet le compte au clair."
            }
        }
    }

    # --- What Windows itself logged about its updates -------------------------------------------
    $logged = @()
    try {
        $logged = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
                                                     Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop)
    } catch { }
    if ($logged.Count) {
        $last = @($logged | Sort-Object TimeCreated -Descending)[0]
        $message = ''
        try { $message = (("$($last.Message)" -replace '\s+', ' ').Trim()) } catch { }
        if ($message.Length -gt 180) { $message = $message.Substring(0, 179) + '…' }
        <#
            THIS ONE COMES FROM THE LOG, so it obeys D127. Nothing here can check whether those failures still stand,
            so it is judged on its age -- and being declassed does NOT remove it: the line stays, and says how often
            it came back. Three failures in seven days is a state; one from a week ago is not.
        #>
        $verdict = Get-JournalFactVerdict -LastAt $last.TimeCreated -Count $logged.Count -WindowDays 7 -Still 'inconnu' -Level 'warn' `
                                          -HighlightMinutes $(try { [int](Get-ModuleSetting -Unit 'system' -Key 'EventHighlightMinutes' -Backend $Backend) } catch { 60 })
        $found += [pscustomobject]@{
            Status = $verdict.Weight
            Label  = 'Erreurs de Windows Update dans le journal Système'
            Detail = $verdict.Said + ' — ' + $verdict.Recurrence + ' (' + $last.TimeCreated.ToString('dd/MM à HH:mm') + ") : $message"
        }
    }

    <#
        AND WHAT BLOCKS IT, NAMED -- asked for on 30/09, and asked for once before that.

        "Installation en échec, 0x80073D02" tells nobody anything. Windows itself knows the answer and writes it in
        its own deployment log: the update of a Store package cannot be applied while a process is holding it, and
        event 419 NAMES the package that must be closed. Read on this computer on 29/09: Phone Link was being updated
        from 1.26072.255.0 while that very version was running.

        Event 493 is the other half: the deployment service still cannot delete some files of an old package, and it
        retries -- 376 times in seven days here, every six minutes, restarts included. That one does not resolve
        itself, so it is said too, with its rate, rather than left as background noise in a log nobody opens.

        The whole reading is one targeted query, 255 ms measured, and this card is computed every six hours.
    #>
    $deployment = @()
    $deploymentUnreadable = $null
    try {
        $deployment = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'
                                                         Id = 419, 493; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop)
    } catch {
        # "NO EVENT FOUND" IS NOT A FAILURE; anything else is -- and what cannot look says so. Silence here would
        # have read as "nothing is blocking", when in truth nobody had been able to look.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { $deploymentUnreadable = $_.Exception.Message }
    }
    if ($deploymentUnreadable) {
        $found += [pscustomobject]@{
            Status = 'warn'
            Label  = "Journal de déploiement des paquets illisible"
            Detail = "Vigie n'a pas pu lire « Microsoft-Windows-AppXDeploymentServer/Operational », qui nomme " +
                     "l'application à fermer quand une mise à jour est bloquée : $deploymentUnreadable"
        }
    }
    $highlight = try { [int](Get-ModuleSetting -Unit 'system' -Key 'EventHighlightMinutes' -Backend $Backend) } catch { 60 }

    $blocked = @($deployment | Where-Object { $_.Id -eq 419 })
    if ($blocked.Count) {
        $lastBlock = @($blocked | Sort-Object TimeCreated -Descending)[0]
        # THE PACKAGE FULL NAME IS IN THE MESSAGE. We keep the readable part: the name, without the version and the
        # publisher hash, which say nothing to whoever reads the card.
        $apps = @()
        foreach ($b in $blocked) {
            foreach ($m in [regex]::Matches("$($b.Message)", '([A-Za-z0-9\.]+)_[0-9\.]+_[a-z0-9]+__[a-z0-9]+')) {
                $name = $m.Groups[1].Value
                if ($apps -notcontains $name) { $apps += $name }
            }
        }
        <#
            AND WHOSE SESSION, because the answer differs. A package held open belongs to ONE account: the event
            carries its SID, and only the person signed in there can close the application. Saying "an open
            application blocks an update" without saying where sends everyone looking on their own desktop, including
            the three accounts that have nothing open. S02, the same shape as winget: a per-account fact reported as
            if it were a fact about the machine.
        #>
        $accounts = @()
        foreach ($b in $blocked) {
            if (-not $b.UserId) { continue }
            $who = "$($b.UserId)"
            try { $who = $b.UserId.Translate([System.Security.Principal.NTAccount]).Value } catch { }
            if ($who -and $accounts -notcontains $who) { $accounts += $who }
        }
        $verdict = Get-JournalFactVerdict -LastAt $lastBlock.TimeCreated -Count $blocked.Count -WindowDays 7 -Still 'inconnu' -Level 'warn' -HighlightMinutes $highlight
        $found += [pscustomobject]@{
            Status = $verdict.Weight
            Label  = 'Mise à jour bloquée par une application ouverte'
            Detail = $verdict.Said + ' — ' + $verdict.Recurrence + '. ' +
                     $(if ($accounts.Count -eq 1) { 'Sur le compte ' + $accounts[0] + '. ' }
                       elseif ($accounts.Count -gt 1) { 'Sur les comptes ' + ($accounts -join ', ') + '. ' }
                       else { "Windows n'a pas nommé le compte concerné. " }) +
                     $(if ($apps.Count) { 'Windows nomme ce qu''il faut fermer : ' + ($apps -join ', ') + '. ' } else { '' }) +
                     "Un paquet en cours d'utilisation ne peut pas être remplacé : la mise à jour s'applique à la " +
                     "fermeture de session ou au redémarrage, quand plus rien ne le tient."
        }
    }

    $stuck = @($deployment | Where-Object { $_.Id -eq 493 })
    if ($stuck.Count -ge 5) {
        $lastStuck = @($stuck | Sort-Object TimeCreated -Descending)[0]
        # THE RATE IS TAKEN OVER THE LAST DAY, not over the seven: the machine is off part of the week, and an average
        # spread over those gaps says one attempt every 24 minutes where the last two hours show one every six.
        $lastDay = @($stuck | Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-24) }).Count
        $verdict = Get-JournalFactVerdict -LastAt $lastStuck.TimeCreated -Count $stuck.Count -WindowDays 7 -Still 'inconnu' -Level 'warn' -HighlightMinutes $highlight
        <#
            AND WE GO AND LOOK, since the server app is the one that can. C:\Program Files\WindowsApps is closed to an
            ordinary session and open to it: naming the files, and whoever holds them, is exactly what Vigie is for
            here. The owner asked for it on 30/09: a card must offer a way forward, and more information to deal with
            the thing differently IS a way forward. Read only: the Restart Manager is asked WHO holds, never to act.
        #>
        $stuckFiles = @()
        $stuckHolders = @()
        $stuckUnreadable = $null
        try {
            # NO Test-Path GATE HERE. On this very folder it THROWS for an ordinary session -- the trap Test-PathSafe
            # exists for -- and under the default preference it answers "false", which reads as "the folder is empty".
            # The card would then have said the opposite of the truth. We read, and a refusal is said as a refusal.
            $deletedDir = Join-Path $env:ProgramFiles 'WindowsApps\Deleted'
            # BOUNDED: a card names what blocks, it does not inventory a folder. Twenty files is already more than
            # anyone reads, and the count above says how many there are.
            $stuckFiles = @(Get-ChildItem -LiteralPath $deletedDir -Recurse -File -Force -ErrorAction Stop |
                            Select-Object -First 20)
            if ($stuckFiles.Count) {
                $stuckHolders = Get-FileHolders -Path @($stuckFiles | ForEach-Object { $_.FullName })
            }
        } catch { $stuckUnreadable = $_.Exception.Message }

        $names = @($stuckFiles | ForEach-Object { $_.Name } | Select-Object -Unique -First 5)
        $who = if ($stuckUnreadable) { "Le dossier n'a pas pu être lu : $stuckUnreadable" }
               elseif (-not $stuckFiles.Count) { "Le dossier est vide : ce que Windows n'arrive pas à supprimer n'y est plus." }
               elseif ($null -eq $stuckHolders) { "Windows n'a pas voulu dire qui les tient." }
               elseif (@($stuckHolders).Count) {
                   'Tenus par : ' + ((@($stuckHolders | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" } | Select-Object -Unique)) -join ', ') + '.'
               } else { "Aucun processus ne les tient en ce moment : c'est la suppression elle-même qui échoue, pas un verrou." }
        $which = if ($names.Count) { ' Fichiers : ' + ($names -join ', ') + $(if ($stuckFiles.Count -ge 20) { ', et d''autres' } else { '' }) + '.' } else { '' }

        $found += [pscustomobject]@{
            Status = $verdict.Weight
            Label  = "Windows n'arrive pas à finir de supprimer un ancien paquet"
            Detail = $verdict.Said + ' — ' + $verdict.Recurrence +
                     $(if ($lastDay -ge 2) { ", soit une tentative toutes les " + [math]::Max(1, [int][math]::Round(1440 / $lastDay)) + " minutes depuis un jour" } else { '' }) +
                     ". Des fichiers d'un paquet désinstallé restent sous « C:\Program Files\WindowsApps\Deleted » " +
                     "et le service de déploiement réessaie sans fin." + $which + ' ' + $who
        }
    }

    return $found
}
