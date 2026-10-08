# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Mettre à jour | dialog | fix   -- affiche quand un champ cite cette action (D66)
# @execution: session   -- son repli interroge le gestionnaire, qui appartient a la session (D128)
<# An action: it lists ONE manager's packages to be updated, for the window of choice.

   Intent: let somebody choose what to update without paying the network's price at the moment of the click.
   READ ONLY. The twin of wu-list-pending: it returns result.choose = $true, the action to call back with the
   selection (result.action) and the list (result.updates).
   Usage: it is called by the interface when the window of choice opens. The list comes from the CACHE written by
   the last check (pkgupdates.json): the check itself is slow and uses the network. Running a winget command at
   the moment of the click would make the user wait without teaching them anything new. If the cache does not
   carry identifiers yet (a cache written by an earlier version), we read live.

   A manager that does NOT know how to target one package: the list is still displayed, but locked (everything
   ticked, nothing unticked) and the window SAYS SO. Showing an untickable list that would then be ignored would
   be a lie of the interface. #>
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$mgr = $null
if ($Params -and $Params.mgr) { $mgr = "$($Params.mgr)" }
elseif ($Module) { $mgr = ($Module -replace '^pkg-', '') }
if (-not $mgr) { return @{ message = "Gestionnaire non précisé."; result = @{ ok = $false } } }

$mg = Get-PackageManagerCatalog | Where-Object { $_.id -eq $mgr } | Select-Object -First 1
if (-not $mg) { return @{ message = "Gestionnaire inconnu : $mgr"; result = @{ ok = $false } } }

$selectable = ($null -ne $mg.upgOne -and @($mg.upgOne).Count -gt 0)
$upSupported = ($null -ne $mg.upgArgs -and @($mg.upgArgs).Count -gt 0)
if (-not $selectable -and -not $upSupported) {
    return @{ message = "Mise à jour automatique non prise en charge pour $($mg.label)."; result = @{ ok = $false } }
}

# 1) The cache of the last check.
$updates = @()
$verifieLe = ''
$outFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'pkgupdates.json'
if (Test-Path -LiteralPath $outFile) {
    try {
        $j = Get-Content $outFile -Raw | ConvertFrom-Json
        $e = $j.$mgr
        if ($e) {
            if ($e.at) { $verifieLe = "$($e.at)" }
            foreach ($p in @($e.pkgs)) {
                if (-not $p) { continue }
                $id = "$($p.id)"
                if (-not ($id -match '\S')) { continue }
                $updates += [ordered]@{ id = $id; titre = "$($p.titre)"; detail = "$($p.detail)" }
            }
        }
    } catch { }
}

# 2) A fallback: read live if the cache carries no identifier.
# THAT FALLBACK IS WHY THIS ACTION RUNS IN A SESSION: it questions the manager itself, and one installed in a
# profile answers only there (D128).
if (-not $updates.Count) {
    try {
        $u = Get-PkgUpdates -Id $mgr
        foreach ($p in @($u.pkgs)) {
            $id = "$($p.id)"
            if (-not ($id -match '\S')) { continue }
            $updates += [ordered]@{ id = $id; titre = "$($p.titre)"; detail = "$($p.detail)" }
        }
        if ($updates.Count) { $verifieLe = (Get-Date).ToString('s') }
    } catch { }
}

# A package's PREVIOUS FAILURE is repeated on ITS line: starting again without knowing would lead to the same
# result (observed with one browser: a different installation technology).
try {
    $cacheMaj = $null
    $fc = Get-VarPath -Kind 'cache' -File 'pkgupdates.json'
    if (Test-Path $fc) { $cacheMaj = (Get-Content $fc -Raw | ConvertFrom-Json).$mgr }
    if ($cacheMaj -and $cacheMaj.last -and $cacheMaj.last.failed) {
        $aRetirer = @()
        foreach ($upd in $updates) {
            if (@($cacheMaj.last.failed) -contains $upd.id) {
                $r1 = if ($cacheMaj.last.reasons) { $cacheMaj.last.reasons."$($upd.id)" } else { $null }
                # "Already up to date": we REMOVE the line instead of presenting it as a failure. Offering an
                # update that is already done, then accusing it of having failed, is two mistakes in a row --
                # observed with a browser that had updated itself through its own channel between the check and
                # the click.
                if (Test-PkgFailureIsDone -Reason $r1) { $aRetirer += $upd.id; continue }
                $avis = Get-PkgFailureAdvice -Reason $r1
                $upd.detail = ("$($upd.detail) — ÉCHEC précédent" + $(if ($avis) { ". $avis" } elseif ($r1) { " : $r1" } else { "" })).Trim(' —')
            }
        }
        if ($aRetirer.Count) { $updates = @($updates | Where-Object { $aRetirer -notcontains $_.id }) }
    }
} catch { }

# 3) The last fallback: the manager returns NO identifier at all (the 'lines' mode). We still offer the global
#    update, as one single locked and named line.
if (-not $updates.Count -and -not $selectable -and $upSupported) {
    $updates += [ordered]@{ id = '*'; titre = "Tous les paquets de $($mg.label)"; detail = '' }
}

$intro = if ($selectable) {
    "Paquets à mettre à jour. La mise à jour continue même si cette fenêtre se ferme."
} else {
    "$($mg.label) ne sait pas mettre à jour un paquet en particulier : la liste est fournie pour information et TOUS les paquets seront mis à jour. La mise à jour continue même si cette fenêtre se ferme."
}
# The AGE of the list, in plain words. It used to be displayed as JSON had read it back -- an American date
# format nobody reads here -- and nothing said it dated from the day before. Yet that is precisely what misleads:
# yesterday's list offers updates that have been done since.
if ($verifieLe) {
    $quand = $null
    try { $quand = [datetime]::Parse($verifieLe, [Globalization.CultureInfo]::InvariantCulture) } catch { }
    if ($quand) {
        $age = (Get-Date) - $quand
        $ageTxt = if ($age.TotalMinutes -lt 60) { "il y a $([int]$age.TotalMinutes) min" }
                  elseif ($age.TotalHours -lt 24) { "il y a $([int]$age.TotalHours) h" }
                  else { "il y a $([int]$age.TotalDays) j" }
        $intro += " Liste vérifiée le " + $quand.ToString('dd/MM/yyyy à HH:mm') + " ($ageTxt)."
        if ($age.TotalHours -ge 12) {
            $intro += " Elle peut être dépassée : lancez « Vérifier les mises à jour » pour la rafraîchir."
        }
    } else {
        $intro += " Liste vérifiée le $verifieLe."
    }
}

@{
    message = "$($updates.Count) paquet(s) à mettre à jour pour $($mg.label)."
    result  = @{
        ok           = $true
        choose       = $true            # l'interface doit ouvrir une fenetre de choix
        action       = 'pkg-upgrade'    # action a rappeler avec les identifiants retenus
        selection    = $selectable      # $false => cases cochees et NON decochables
        # Precochage : reglage utilisateur (Parametres > Outils & paquets), D57.
        preselect    = [bool](Get-ModuleSetting -Unit 'tools' -Key 'PreselectAllUpdates')
        confirmLabel = 'Mettre à jour'
        intro        = $intro
        vide         = "Aucun paquet à mettre à jour. « Vérifier les mises à jour » actualise une liste ancienne."
        updates      = @($updates)
    }
}
