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
    New-ModuleObject -Id 'wu-pending' -Theme 'windows-update' -Label 'Mises à jour en attente' -Status $(if ($count -gt 0) {'warn'} else {'ok'}) -Fields @(
        New-Field -Key 'pending' -Label 'Détectées (non installées)' -Value $count -Kind 'number' -Status $(if ($count -gt 0) {'warn'} else {'ok'}) -Help $help -Guide $guide -FixAction 'open-windows-update'
    ) -Actions @(
        New-Action -Id 'open-windows-update' -Label 'Ouvrir Windows Update' -Kind 'manual' -Help "Ouvre les Paramètres Windows Update pour installer manuellement. Déverrouillez (Mode MAJ) avant si nécessaire, puis re-verrouillez."
    )
}
