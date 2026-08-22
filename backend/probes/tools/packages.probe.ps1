<# Sonde : UNE carte par gestionnaire de paquets detecte (presence + version + MAJ).
   LECTURE SEULE et RAPIDE. La verification des MAJ (lente/reseau) est faite a la
   demande par l'action pkg-check-updates (worker detache) ; ici on ne fait que
   LIRE .state/pkgupdates.json (compte, elements, etat "en cours"). #>
param()
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# Etat des MAJ / verification en cours (ecrit par l'action + le worker).
$upd = @{}
$updFile = Join-Path $backend '.state\pkgupdates.json'
if (Test-Path $updFile) {
    try { $j = Get-Content $updFile -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $upd[$p.Name] = $p.Value } } catch { }
}

$modules = @()
foreach ($mg in (Get-PackageManagerCatalog)) {
    $cmd = Get-Command $mg.id -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    $src = if ($cmd.Source) { $cmd.Source } else { $mg.id }

    # Version installee.
    $ver = 'installé'; $raw = ''
    try {
        if ($mg.verArgs.Count -gt 0 -and $cmd.Source) {
            $r = Invoke-Native -File $cmd.Source -Arguments $mg.verArgs
            if ($r.Ok -and $r.Output) {
                $raw = (($r.Output -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
                $mm = [regex]::Match($raw, '\d+(?:\.\d+)+')
                if ($mm.Success) { $ver = $mm.Value } elseif ($raw) { $ver = $raw }
            }
        }
    } catch { }

    $u           = $upd[$mg.id]
    $checking    = [bool]($u -and $u.checking)
    $op          = if ($checking -and $u.op) { "$($u.op)" } else { 'check' }
    $supported   = ($mg.updMode -ne 'none' -and @($mg.updArgs).Count -gt 0)
    $upSupported = ($null -ne $mg.upgArgs -and @($mg.upgArgs).Count -gt 0)
    $cnt         = if ($u -and $null -ne $u.count) { [int]$u.count } else { -1 }

    # Champ Version (toujours present).
    $vg = @()
    if ($raw) { $vg += $raw }
    $vg += ("Chemin : " + $src)
    $fields = @()
    $fields += New-Field -Key 'version' -Label 'Version' -Value $ver -Kind 'text' -Status 'ok' `
        -Help "Version installee, detectee dans le PATH." -Guide ($vg -join "`n")

    # Champ Mises a jour.
    $majStatus = 'neutral'; $majValue = '—'; $mg2 = @()
    if (-not $supported) {
        $majValue = 'non pris en charge'
        $mg2 += "La verification automatique des MAJ n'est pas disponible pour ce gestionnaire."
    } elseif ($checking) {
        $verbe = if ($op -eq 'upgrade') { 'Mise à jour' } else { 'Vérification' }
        $majValue = "$verbe en cours…"
        $mg2 += ("$verbe lancee" + $(if ($u.startedAt) { " le $($u.startedAt)" } else { "" }) + ".")
        if ($null -ne $u.count) { $mg2 += ("Dernier resultat connu : $([int]$u.count) MAJ.") }
    } elseif ($u -and $u.at) {
        if ($cnt -gt 0) {
            $majStatus = 'warn'; $majValue = "$cnt disponible(s)"
            foreach ($it in @($u.items)) { $mg2 += ("- " + $it) }
        } else {
            $majStatus = 'ok'; $majValue = 'à jour'
            $mg2 += "Aucune mise a jour disponible."
        }
        $mg2 += ""
        $mg2 += ("Verifie le : " + $u.at)
        if ($u.error) { $mg2 += ("Erreur lors de la verification : " + $u.error) }
    } else {
        $majValue = 'non vérifiées'
        $mg2 += "Cliquez « Verifier les mises a jour » : la verification s'execute en tache de fond."
    }
    # Le champ MAJ pointe vers l'action d'upgrade (bouton "Mettre a jour") quand
    # des MAJ existent ET que le gestionnaire sait se mettre a jour tout seul.
    $majFieldArgs = @{
        Key = 'updates'; Label = 'Mises à jour'; Value = $majValue; Kind = 'text'; Status = $majStatus
        Help = "Nombre de mises a jour disponibles (verifie a la demande, sans bloquer)."; Guide = ($mg2 -join "`n")
    }
    if ($cnt -gt 0 -and $upSupported -and -not $checking) { $majFieldArgs.FixAction = 'pkg-upgrade' }
    $fields += New-Field @majFieldArgs

    # Statut de la carte : neutre pendant l'operation, sinon selon les MAJ.
    $modStatus = if ($checking) { 'neutral' } elseif ($majStatus -eq 'warn') { 'warn' } else { 'ok' }

    $actions = @()
    if ($supported) {
        $actions += New-Action -Id 'pkg-check-updates' -Label 'Vérifier les mises à jour' -Kind 'immediate' `
            -Help ("Interroge " + $mg.label + " pour lister les MAJ disponibles. S'execute en tache de fond ; la carte s'actualise seule.")
    }
    if ($upSupported -and $cnt -gt 0 -and -not $checking) {
        $actions += New-Action -Id 'pkg-upgrade' -Label 'Mettre à jour' -Confirm -Kind 'confirm' `
            -Help ("Met a jour tous les paquets de " + $mg.label + " en tache de fond (peut etre long).")
    }

    $modules += (New-ModuleObject -Id ("pkg-" + $mg.id) -Theme 'tools' -Label $mg.label -Status $modStatus -Fields $fields -Actions $actions -Busy:$checking)
}

if (-not $modules.Count) {
    $modules += (New-ModuleObject -Id 'pkg-none' -Theme 'tools' -Label 'Gestionnaires de paquets' -Status 'neutral' -Fields @(
        New-Field -Key 'none' -Label 'Gestionnaires' -Value 'aucun détecté' -Kind 'text' -Status 'neutral' `
            -Help "Aucun gestionnaire de paquets connu trouve dans le PATH."
    ))
}

, $modules
