# @author Florent HAZARD <f.hazard@sowapps.com>
<# Sonde : UNE carte par gestionnaire de paquets detecte (presence + version + MAJ).
   LECTURE SEULE et RAPIDE. La verification des MAJ (lente/reseau) est faite a la
   demande par l'action pkg-check-updates (worker detache) ; ici on ne fait que
   LIRE var/cache/pkgupdates.json (compte, elements, etat "en cours"). #>
param()
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# Etat des MAJ / verification en cours (ecrit par l'action + le worker).
$upd = @{}
$updFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'pkgupdates.json'
if (Test-Path $updFile) {
    try { $j = Get-Content $updFile -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $upd[$p.Name] = $p.Value } } catch { }
}

<#
    WHAT THIS ACCOUNT HAS, read in its own session.

    A manager installed in a profile resolves only from that profile's PATH. Measured on 05/10: winget lives in
    `AppData\Local\Microsoft\WindowsApps` on this account, and the server app -- a service account -- did not see
    it at all; the panel showed Chocolatey and pip and said nothing about the main manager of the machine (C4 of
    `targeting/multi-account-server.md`). The inventory is taken by the `pkg-inventory` action in each account's
    session, kept per account by `Update-PkgInventory`, and read here FOR THE REQUESTER AND NOBODY ELSE.

    NO FALLING BACK ON ANOTHER ACCOUNT. The first version read the union of every account kept when the requester
    had none, and the card then showed another person's winget -- their path, their version, and, at the next step,
    their updates. The owner caught it the same day: the service account has no winget, so nothing here belongs to
    the machine. Unread is unread, and the card says so rather than borrowing an answer.

    What this process sees itself still counts, and is borrowed from nobody: a manager installed machine-wide needs
    nobody signed in to be true.
#>
$requester = Get-RequesterAccount
$inventory = @{}
$inventoryAt = @{}
if ($requester) {
    foreach ($row in @(Get-PkgInventory -Backend $backend -Account $requester)) { $inventory["$($row.Id)"] = $row }
}
# NOT YET READ IS SAID, NOT HIDDEN. The watch pass reads one account per pass, so a session that has just opened
# waits its turn -- and until then a manager living in its profile is simply absent from the panel, with nothing to
# explain the hole. A card that cannot see says it cannot see (CORE-ERRORS).
$inventoryPending = ($requester -and -not $inventory.Count)

$modules = @()
foreach ($mg in (Get-PackageManagerCatalog)) {
    $cmd = Get-Command $mg.id -ErrorAction SilentlyContinue
    $seen = $inventory["$($mg.id)"]
    if (-not $cmd -and -not $seen) { continue }
    $src = if ($cmd -and $cmd.Source) { $cmd.Source } elseif ($seen) { "$($seen.Source)" } else { $mg.id }

    # Version installee.
    $ver = 'installé'; $raw = ''
    try {
        if ($cmd -and $mg.verArgs.Count -gt 0 -and $cmd.Source) {
            $r = Invoke-Native -File $cmd.Source -Arguments $mg.verArgs
            if ($r.Ok -and $r.Output) {
                $raw = (($r.Output -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
                $mm = [regex]::Match($raw, '\d+(?:\.\d+)+')
                if ($mm.Success) { $ver = $mm.Value } elseif ($raw) { $ver = $raw }
            }
        }
    } catch { }
    # SEEN ONLY BY A SESSION: the version comes from there too, and the account that proves it is kept so the card
    # can say where the reading comes from instead of implying the server could see it.
    if (-not $cmd -and $seen) {
        if ("$($seen.Version)".Trim()) { $ver = "$($seen.Version)" }
        $inventoryAt["$($mg.id)"] = "$($seen.Account)"
    }

    $u           = $upd[$mg.id]
    # WHAT IS RUNNING IS SAID BY THE BUSY MARK (doc/progress/targeting/operations.md): no expiry of our own any more.
    $operation = Get-ModuleBusyMark -Module ("pkg-" + $mg.id) -Backend $backend
    $checking = [bool]$operation
    $op = if ($operation -and "$($operation.action)" -eq 'pkg-upgrade') { 'upgrade' } else { 'check' }
    $supported   = ($mg.updMode -ne 'none' -and @($mg.updArgs).Count -gt 0)
    # Deux capacites DISTINCTES : savoir tout mettre a jour, et savoir n'en cibler qu'un.
    # pip ne sait que la seconde ; scoop, npm et gem que la premiere.
    $selectable  = ($null -ne $mg.upgOne  -and @($mg.upgOne).Count  -gt 0)
    $upSupported = (($null -ne $mg.upgArgs -and @($mg.upgArgs).Count -gt 0) -or $selectable)
    $cnt         = if ($u -and $null -ne $u.count) { [int]$u.count } else { -1 }

    # Paquets IGNORES par l'utilisateur (Parametres > Modules > Outils & paquets) :
    # exclus du decompte et de la liste, mais dits dans le guide -- une exclusion
    # silencieuse finirait par faire croire qu'une MAJ n'existe pas.
    $ignores = @(Get-ModuleSetting -Unit 'tools' -Key 'IgnoredPackages' | Where-Object { "$_" -match '\S' })
    $nbIgnores = 0
    $itemsAff = @($u.items)
    if ($ignores.Count -gt 0 -and $itemsAff.Count -gt 0) {
        # Un motif peut viser la ligne AFFICHEE (« Microsoft GameInput 3.3 -> 3.4 ») ou
        # l'IDENTIFIANT ciblable (« Microsoft.GameInput ») : items et pkgs sont paralleles
        # (meme source, meme ordre), on teste les deux formes.
        $pkgsIds = @($u.pkgs)
        $garde = @()
        for ($i = 0; $i -lt $itemsAff.Count; $i++) {
            $ligne = "$($itemsAff[$i])"
            # pkgs est une liste d'OBJETS { id, titre, detail } : c'est l'id qu'on vise.
            $idPkg = if ($i -lt $pkgsIds.Count) { "$($pkgsIds[$i].id)" } else { '' }
            $vise = @($ignores | Where-Object {
                $ligne -like ('*' + $_ + '*') -or ($idPkg -and $idPkg -like $_)
            }).Count -gt 0
            if (-not $vise) { $garde += $itemsAff[$i] }
        }
        $nbIgnores = $itemsAff.Count - $garde.Count
        $itemsAff = $garde
        if ($cnt -gt 0) { $cnt = [Math]::Max(0, $cnt - $nbIgnores) }
    }

    # Champ Version (toujours present).
    $vg = @()
    if ($raw) { $vg += $raw }
    $vg += ("Chemin : " + $src)
    # WHERE THE READING COMES FROM, said rather than implied: a manager installed in a profile is invisible to the
    # server app, and the card would otherwise look like it had seen it itself.
    if ($inventoryAt["$($mg.id)"]) { $vg += ("Lu dans la session de " + $inventoryAt["$($mg.id)"] + " : ce gestionnaire est installé dans ce profil, l'app serveur ne le voit pas.") }
    if ($inventoryPending) { $vg += "Les gestionnaires installés dans votre profil ne sont pas encore lus dans votre session : ils apparaîtront d'eux-mêmes." }
    $fields = @()
    $fields += New-Field -Key 'version' -Label 'Version' -Value $ver -Kind 'text' -Status 'ok' `
        -Help $(if ($inventoryAt["$($mg.id)"]) { "Version installée, lue dans la session du compte qui l'a installé." } else { "Version installée, détectée dans le PATH." }) `
        -Guide ($vg -join "`n")

    # Champ Mises a jour.
    $majStatus = 'neutral'; $majValue = '—'; $mg2 = @()
    if (-not $supported) {
        $majValue = 'non pris en charge'
        $mg2 += "La vérification automatique des MAJ n'est pas disponible pour ce gestionnaire."
    } elseif ($checking) {
        # La carte dit EXACTEMENT ce qui tourne : quoi, sur combien, depuis quand.
        # « Mise à jour en cours... » seul laissait l'utilisateur sans reponse (constate).
        $duree = ''
        if ($u.startedAt) {
            try {
                $min = [int]((Get-Date) - [datetime]$u.startedAt).TotalMinutes
                $duree = if ($min -lt 1) { " (depuis moins d'une minute)" } else { " (depuis $min min)" }
            } catch { }
        }
        if ($op -eq 'upgrade') {
            $sel = @($u.sel)
            $majValue = if ($sel.Count -gt 0 -and $null -ne $u.count -and [int]$u.count -gt 0) {
                "$($sel.Count) sur $([int]$u.count) en cours…"
            } elseif ($sel.Count -gt 0) { "$($sel.Count) paquet(s) en cours…" }
            else { "Mise à jour en cours…" }
            if ($sel.Count -gt 0) {
                $mg2 += "Paquets en cours de mise à jour :"
                foreach ($p0 in $sel) { $mg2 += ("- " + $p0) }
            } else { $mg2 += "Mise à jour de TOUT le gestionnaire." }
            $mg2 += ("Lancée" + $(if ($u.startedAt) { " le $($u.startedAt)" } else { "" }) + $duree + ".")
        } else {
            $majValue = "Vérification en cours…"
            $mg2 += ("Vérification lancée" + $(if ($u.startedAt) { " le $($u.startedAt)" } else { "" }) + $duree + ".")
            if ($null -ne $u.count) { $mg2 += ("Dernier résultat connu : $([int]$u.count) MAJ.") }
        }
    } elseif ($u -and $u.at) {
        if ($cnt -gt 0) {
            $majStatus = 'warn'; $majValue = "$cnt disponible(s)"
            foreach ($it in $itemsAff) { $mg2 += ("- " + $it) }
        } else {
            $majStatus = 'ok'; $majValue = 'À jour'
            $mg2 += "Aucune mise à jour disponible."
        }
        if ($nbIgnores -gt 0) { $mg2 += ("($nbIgnores mise(s) à jour masquée(s) par la liste des paquets ignorés.)") }
        $mg2 += ""
        $mg2 += ("Vérifié le : " + $u.at)
        # Le resultat de la DERNIERE mise a jour reste visible : une operation qui se
        # termine en silence laisse croire qu'il ne s'est rien passe.
        if ($u.last) {
            $quoi = if ([int]$u.last.count -gt 0) { "$([int]$u.last.count) paquet(s)" } else { "tout le gestionnaire" }
            $echecs = @($u.last.failed)
            if ($echecs.Count -gt 0) {
                $majStatus = 'warn'
                $mg2 += ("Dernière mise à jour ($($u.last.at)) : $quoi, $($echecs.Count) ÉCHEC(S) :")
                foreach ($e0 in $echecs) {
                    $r0 = if ($u.last.reasons) { $u.last.reasons."$e0" } else { $null }
                    $mg2 += ("- " + $e0 + $(if ($r0) { " : " + $r0 } else { "" }))
                    $avis = Get-PkgFailureAdvice -Reason $r0
                    if ($avis) { $mg2 += ("  " + $avis) }
                }
            } elseif ([bool]$u.last.ok) {
                $mg2 += ("Dernière mise à jour ($($u.last.at)) : $quoi, réussie.")
            } else {
                $majStatus = 'warn'
                $mg2 += ("Dernière mise à jour ($($u.last.at)) : $quoi, EN ERREUR — voir le journal pkgupgrade dans var/log.")
            }
        }
        if ($u.reboot) { $mg2 += "Un REDÉMARRAGE est nécessaire pour terminer la dernière mise à jour." }
        if ($u.error) { $mg2 += ("Erreur lors de la vérification : " + $u.error) }
    } else {
        $majValue = 'Non vérifiées'
        $mg2 += "« Vérifier les mises à jour » lance la vérification, en tâche de fond."
    }
    # Le champ MAJ pointe vers l'action d'upgrade (bouton "Mettre a jour") quand
    # des MAJ existent ET que le gestionnaire sait se mettre a jour tout seul.
    $majFieldArgs = @{
        Key = 'updates'; Label = 'Mises à jour'; Value = $majValue; Kind = 'text'; Status = $majStatus
        Help = "Nombre de mises à jour disponibles (vérifié à la demande, sans bloquer)."; Guide = ($mg2 -join "`n")
    }
    if ($cnt -gt 0 -and $upSupported -and -not $checking) { $majFieldArgs.FixAction = 'pkg-list-updates' }
    $fields += New-Field @majFieldArgs
    # A failure the worker could not write itself is the protocol's result, and the card says it.
    if (-not $checking) {
        $failure = New-UnreportedFailureField -Module ("pkg-" + $mg.id) -WrittenAt $(if ($u) { $u.at } else { $null }) -Backend $backend
        if ($failure) { $fields += $failure }
    }

    # Statut de la carte : neutre pendant l'operation, sinon selon les MAJ.
    $modStatus = if ($checking) { 'neutral' } elseif ($majStatus -eq 'warn') { 'warn' } else { 'ok' }

    $actions = @()
    if ($supported) {
        $actions += New-Action -Id 'pkg-check-updates' -Label 'Vérifier les mises à jour' -BusyLabel 'Vérification…' -Kind 'immediate' `
            -Help ("Interroge " + $mg.label + " pour lister les MAJ disponibles. S'exécute en tâche de fond ; la carte s'actualise seule.")
    }
    # Le bouton ouvre la fenetre de CHOIX (comme Windows Update), il ne lance plus la mise
    # a jour sur un simple oui/non : mettre a jour « tout » sans voir quoi n'est pas un choix.
    if ($upSupported -and $cnt -gt 0 -and -not $checking) {
        $aide = if ($selectable) {
            "Ouvre la liste des paquets de " + $mg.label + " : cochez ceux à mettre à jour. La mise à jour s'exécute en tâche de fond."
        } else {
            $mg.label + " ne sait pas cibler un paquet : la liste est affichée pour information et TOUS les paquets seront mis à jour."
        }
        $actions += New-Action -Id 'pkg-list-updates' -Severity 'fix' -Label 'Mettre à jour' -BusyLabel 'Mise à jour…' -Kind 'dialog' -Help $aide
    }
    # Interface graphique du gestionnaire, UNIQUEMENT si elle est installee (Get-PkgGui le
    # verifie). Meme role que « Ouvrir Windows Update » sur la carte Windows Update.
    $gui = $null
    try { $gui = Get-PkgGui -Id $mg.id } catch { }
    if ($gui) {
        $actions += New-Action -Id 'pkg-open-gui' -Severity 'info' -Label $gui.label -Kind 'manual' -Help $gui.help
    }

    # THE SCOPE IS COMPUTED, because it depends on the manager: installed for the whole computer, it is a fact
    # about the computer; installed in a profile, it is a fact about that account, and it had to be read there.
    $modules += (New-ModuleObject -Id ("pkg-" + $mg.id) -Theme 'tools' -Label $mg.label -Scope $(if ($inventoryAt["$($mg.id)"]) { 'user' } else { 'machine' }) -Status $modStatus -Fields $fields -Actions $actions -Busy:$checking `
        -BusyAction $(if ($checking) { if ($op -eq 'upgrade') { 'pkg-list-updates' } else { 'pkg-check-updates' } } else { $null }))
}

if (-not $modules.Count) {
    $modules += (New-ModuleObject -Id 'pkg-none' -Theme 'tools' -Label 'Gestionnaires de paquets' -Scope 'machine' -Status 'neutral' -Fields @(
        New-Field -Key 'none' -Label 'Gestionnaires' -Value 'aucun détecté' -Kind 'text' -Status 'neutral' `
            -Help "Aucun gestionnaire de paquets connu trouvé dans le PATH."
    ))
}

, $modules
