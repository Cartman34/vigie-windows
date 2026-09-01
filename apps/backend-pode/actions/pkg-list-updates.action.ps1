# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Mettre à jour | dialog | fix   -- affiche quand un champ cite cette action (D66)
<# Action : liste les paquets a mettre a jour d'UN gestionnaire, pour la fenetre de choix.

   LECTURE SEULE. Jumelle de wu-list-pending : renvoie result.choose = $true, l'action a
   rappeler avec la selection (result.action) et la liste (result.updates).

   La liste vient du CACHE ecrit par la derniere verification (pkgupdates.json) : la
   verification, elle, est lente et reseau. Relancer une commande winget au moment du clic
   ferait attendre l'utilisateur sans rien lui apprendre de neuf. Si le cache ne porte pas
   encore d'identifiants (cache ecrit par une version anterieure), on lit en direct.

   Gestionnaire qui ne sait PAS cibler un paquet : la liste est quand meme affichee, mais
   verrouillee (tout coche, rien de decochable) et la fenetre le DIT. Montrer une liste
   decochable qui serait ensuite ignoree serait un mensonge d'interface.
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

# 1) Le cache de la derniere verification.
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

# 2) Repli : lecture en direct si le cache ne porte aucun identifiant.
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

# L'ECHEC PRECEDENT d'un paquet se repete sur SA ligne : relancer sans le savoir menerait
# au meme resultat (constate avec Edge : technologie d'installation differente).
try {
    $cacheMaj = $null
    $fc = Get-VarPath -Kind 'cache' -File 'pkgupdates.json'
    if (Test-Path $fc) { $cacheMaj = (Get-Content $fc -Raw | ConvertFrom-Json).$mgr }
    if ($cacheMaj -and $cacheMaj.last -and $cacheMaj.last.failed) {
        $aRetirer = @()
        foreach ($upd in $updates) {
            if (@($cacheMaj.last.failed) -contains $upd.id) {
                $r1 = if ($cacheMaj.last.reasons) { $cacheMaj.last.reasons."$($upd.id)" } else { $null }
                # « Deja a jour » : on RETIRE la ligne au lieu de la presenter en echec.
                # Proposer une mise a jour accomplie, puis l'accuser d'avoir echoue, c'est
                # deux erreurs a la suite -- constate avec Edge, qui s'etait mis a jour par
                # son propre canal entre la verification et le clic.
                if (Test-PkgFailureIsDone -Reason $r1) { $aRetirer += $upd.id; continue }
                $avis = Get-PkgFailureAdvice -Reason $r1
                $upd.detail = ("$($upd.detail) — ÉCHEC précédent" + $(if ($avis) { ". $avis" } elseif ($r1) { " : $r1" } else { "" })).Trim(' —')
            }
        }
        if ($aRetirer.Count) { $updates = @($updates | Where-Object { $aRetirer -notcontains $_.id }) }
    }
} catch { }

# 3) Dernier repli : le gestionnaire ne rend AUCUN identifiant (mode 'lines'). On propose
#    quand meme la mise a jour globale, en une seule ligne verrouillee et nommee.
if (-not $updates.Count -and -not $selectable -and $upSupported) {
    $updates += [ordered]@{ id = '*'; titre = "Tous les paquets de $($mg.label)"; detail = '' }
}

$intro = if ($selectable) {
    "Cochez les paquets à mettre à jour. La mise à jour continue même si vous fermez cette fenêtre."
} else {
    "$($mg.label) ne sait pas mettre à jour un paquet en particulier : la liste est fournie pour information et TOUS les paquets seront mis à jour. La mise à jour continue même si vous fermez cette fenêtre."
}
# L'AGE de la liste, en francais et en clair. Elle s'affichait telle que JSON l'avait
# relue -- « 08/25/2026 10:12:03 », un format americain que personne ne lit ici -- et
# rien ne disait qu'elle datait de la veille. Or c'est justement ce qui trompe : une
# liste d'hier propose des mises a jour deja faites depuis.
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
        vide         = "Aucun paquet à mettre à jour. Lancez « Vérifier les mises à jour » si la liste vous semble ancienne."
        updates      = @($updates)
    }
}
