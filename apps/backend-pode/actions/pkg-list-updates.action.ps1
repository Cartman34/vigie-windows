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
if ($verifieLe) { $intro += " Liste vérifiée le $verifieLe." }

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
