<#
    Sonde : mises à jour en attente. LECTURE SEULE, recherche LOCALE (cache) :
    ne lance PAS d'analyse en ligne et n'installe rien (Online = $false).
    Distingue les pilotes/optionnels (que l'écran principal de Windows ne compte pas)
    et fournit la liste des titres (dépliable).
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')
$count = $null
$titles = @()
$drivers = 0
try {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $searcher.Online = $false
    $res = $searcher.Search("IsInstalled=0 And IsHidden=0")
    $count = [int]$res.Updates.Count
    for ($i = 0; $i -lt $res.Updates.Count; $i++) {
        $u = $res.Updates.Item($i)
        $titles += $u.Title
        try { if ($u.Type -eq 2) { $drivers++ } } catch { }   # 2 = ushDriver
    }
} catch { }

if ($null -eq $count) {
    New-ModuleObject -Id 'wu-pending' -Theme 'windows-update' -Label 'Mises à jour en attente' -Status 'neutral' -Fields @(
        New-Field -Key 'pending' -Label 'Détectées' -Value 'indisponible' -Kind 'text' -Status 'neutral' -Help "Recherche locale indisponible (le verrouillage coupe les analyses ; le cache peut être vide)."
    )
} else {
    $help = "Mises à jour déjà détectées et non installées (recherche LOCALE dans le cache : aucune analyse en ligne, aucune installation)."
    $note = "Pilotes/MAJ facultatives : non comptés par l'écran principal de Windows. Rien ne s'installe sans vous — pour installer, utilisez « Ouvrir Windows Update » (déverrouillez via Mode MAJ si besoin)."
    $parts = @($help)
    if ($drivers -gt 0) { $parts += "Dont $drivers pilote(s)/optionnel(s)." }
    $parts += $note
    if ($count -gt 0 -and $titles.Count) { $parts += "Liste des mises à jour détectées :`n- " + ($titles -join "`n- ") }
    $guide = ($parts -join "`n`n")
    # Etat d'une installation lancee depuis l'application (worker wu-install).
    $inst = $null
    try {
        $f = Get-VarPath -Backend $backend -Kind 'cache' -File 'wu-install.json'
        if (Test-Path $f) { $inst = Get-Content $f -Raw | ConvertFrom-Json }
    } catch { }
    $enCours = [bool]($inst -and $inst.installing)

    $champs = @()
    if ($enCours) {
        $phase = if ($inst.phase) { "$($inst.phase)" } else { 'en cours' }
        $champs += New-Field -Key 'install' -Label 'Installation' -Value "$phase…" -Kind 'text' -Status 'neutral' `
            -Help "Installation lancée depuis Vigie. Elle continue même si vous fermez la fenêtre." `
            -Guide $(if ($inst.titres) { "Mises à jour retenues :`n- " + (@($inst.titres) -join "`n- ") } else { '' })
    } elseif ($inst -and $inst.phase -eq 'termine') {
        # On rapporte le RESULTAT constate, code de retour compris (D43).
        $val = if ($inst.error) { 'échec' } elseif ($inst.partiel) { 'terminée avec erreurs' } else { 'terminée' }
        $st  = if ($inst.error) { 'error' } elseif ($inst.partiel) { 'warn' } else { 'ok' }
        $g = @()
        if ($inst.titres) { $g += "Mises à jour traitées :`n- " + (@($inst.titres) -join "`n- ") }
        if ($inst.error) { $g += "Erreur : $($inst.error)" }
        if ($inst.redemarrage) { $g += "Un REDÉMARRAGE est nécessaire pour terminer." }
        $champs += New-Field -Key 'install' -Label 'Dernière installation' -Value $val -Kind 'text' -Status $st `
            -Help "Résultat de la dernière installation lancée depuis Vigie." -Guide ($g -join "`n`n")
    }

    $actions = @()
    if ($count -gt 0) {
        $actions += New-Action -Id 'wu-list-pending' -Label 'Installer des mises à jour…' -Kind 'dialog' `
            -Help "Ouvre la liste des mises à jour détectées pour choisir celles à installer. Rien ne s'installe sans votre sélection."
    }
    $actions += New-Action -Id 'open-windows-update' -Label 'Ouvrir Windows Update' -Kind 'manual' -Help "Ouvre les Paramètres Windows Update pour installer manuellement. Déverrouillez (Mode MAJ) avant si nécessaire, puis re-verrouillez."

    New-ModuleObject -Id 'wu-pending' -Theme 'windows-update' -Label 'Mises à jour en attente' -Status $(if ($enCours) {'neutral'} elseif ($count -gt 0) {'warn'} else {'ok'}) -Fields (@(
        # FixAction pointe sur l'ouverture de Windows Update, PAS sur l'installation :
        # une action reprise comme « correctif » disparait de la barre d'actions pour se
        # replier dans la ligne du champ, ou l'utilisateur ne la trouve pas.
        New-Field -Key 'pending' -Label 'Détectées (non installées)' -Value $count -Kind 'number' -Status $(if ($count -gt 0) {'warn'} else {'ok'}) -Help $help -Guide $guide -FixAction 'open-windows-update'
    ) + $champs) -Actions $actions -Busy:$enCours
}
