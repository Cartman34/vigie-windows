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
    # Une tache de fond peut MOURIR sans rien ecrire (processus tue, machine arretee) ou
    # RESTER BLOQUEE. Sans peremption, son drapeau « en cours » ne retombe jamais et la
    # carte tourne indefiniment -- constate sur une mise a jour winget restee 22 minutes
    # a 0 % de CPU. Passe ce delai, on considere qu'elle ne reviendra pas.
    $DELAI_TACHE_MIN = 45
    $checking = [bool]($u -and $u.checking)
    $tacheAbandonnee = $false
    if ($checking -and $u.startedAt) {
        try {
            $depuis = ((Get-Date) - [datetime]$u.startedAt).TotalMinutes
            if ($depuis -gt $DELAI_TACHE_MIN) { $checking = $false; $tacheAbandonnee = $true }
        } catch { }
    }
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
        -Help "Version installée, détectée dans le PATH." -Guide ($vg -join "`n")

    # Champ Mises a jour.
    $majStatus = 'neutral'; $majValue = '—'; $mg2 = @()
    if (-not $supported) {
        $majValue = 'non pris en charge'
        $mg2 += "La vérification automatique des MAJ n'est pas disponible pour ce gestionnaire."
    } elseif ($checking) {
        $verbe = if ($op -eq 'upgrade') { 'Mise à jour' } else { 'Vérification' }
        $majValue = "$verbe en cours…"
        $mg2 += ("$verbe lancée" + $(if ($u.startedAt) { " le $($u.startedAt)" } else { "" }) + ".")
        if ($null -ne $u.count) { $mg2 += ("Dernier résultat connu : $([int]$u.count) MAJ.") }
    } elseif ($u -and $u.at) {
        if ($cnt -gt 0) {
            $majStatus = 'warn'; $majValue = "$cnt disponible(s)"
            foreach ($it in @($u.items)) { $mg2 += ("- " + $it) }
        } else {
            $majStatus = 'ok'; $majValue = 'à jour'
            $mg2 += "Aucune mise à jour disponible."
        }
        $mg2 += ""
        $mg2 += ("Vérifié le : " + $u.at)
        if ($tacheAbandonnee) {
            $majStatus = 'warn'
            $mg2 += "L'opération précédente ne répond plus depuis plus de $DELAI_TACHE_MIN minutes : elle est considérée comme interrompue. Relancez-la si besoin."
        }
        if ($u.reboot) { $mg2 += "Un REDÉMARRAGE est nécessaire pour terminer la dernière mise à jour." }
        if ($u.error) { $mg2 += ("Erreur lors de la vérification : " + $u.error) }
    } else {
        $majValue = 'non vérifiées'
        $mg2 += "Cliquez « Vérifier les mises à jour » : la vérification s'exécute en tâche de fond."
    }
    # Le champ MAJ pointe vers l'action d'upgrade (bouton "Mettre a jour") quand
    # des MAJ existent ET que le gestionnaire sait se mettre a jour tout seul.
    $majFieldArgs = @{
        Key = 'updates'; Label = 'Mises à jour'; Value = $majValue; Kind = 'text'; Status = $majStatus
        Help = "Nombre de mises à jour disponibles (vérifié à la demande, sans bloquer)."; Guide = ($mg2 -join "`n")
    }
    if ($cnt -gt 0 -and $upSupported -and -not $checking) { $majFieldArgs.FixAction = 'pkg-upgrade' }
    $fields += New-Field @majFieldArgs

    # Statut de la carte : neutre pendant l'operation, sinon selon les MAJ.
    $modStatus = if ($checking) { 'neutral' } elseif ($majStatus -eq 'warn') { 'warn' } else { 'ok' }

    $actions = @()
    if ($supported) {
        $actions += New-Action -Id 'pkg-check-updates' -Label 'Vérifier les mises à jour' -Kind 'immediate' `
            -Help ("Interroge " + $mg.label + " pour lister les MAJ disponibles. S'exécute en tâche de fond ; la carte s'actualise seule.")
    }
    if ($upSupported -and $cnt -gt 0 -and -not $checking) {
        $actions += New-Action -Id 'pkg-upgrade' -Label 'Mettre à jour' -Confirm -Kind 'confirm' `
            -Help ("Met à jour tous les paquets de " + $mg.label + " en tâche de fond (peut être long).")
    }

    $modules += (New-ModuleObject -Id ("pkg-" + $mg.id) -Theme 'tools' -Label $mg.label -Status $modStatus -Fields $fields -Actions $actions -Busy:$checking)
}

if (-not $modules.Count) {
    $modules += (New-ModuleObject -Id 'pkg-none' -Theme 'tools' -Label 'Gestionnaires de paquets' -Status 'neutral' -Fields @(
        New-Field -Key 'none' -Label 'Gestionnaires' -Value 'aucun détecté' -Kind 'text' -Status 'neutral' `
            -Help "Aucun gestionnaire de paquets connu trouvé dans le PATH."
    ))
}

, $modules
