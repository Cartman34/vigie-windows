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
    New-ModuleObject -Id 'wu-pending' -Theme 'windows-update' -Label 'Mise à jour du système' -Status 'neutral' -Fields @(
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

    $scan = $null
    try {
        $fs = Get-VarPath -Backend $backend -Kind 'cache' -File 'wu-scan.json'
        if (Test-Path $fs) { $scan = Get-Content $fs -Raw | ConvertFrom-Json }
    } catch { }
    $scanEnCours = [bool]($scan -and $scan.scanning)

    $champs = @()
    if ($scanEnCours) {
        $champs += New-Field -Key 'scan' -Label 'Analyse en ligne' -Value 'en cours…' -Kind 'text' -Status 'neutral' `
            -Help "Interrogation des serveurs Microsoft. Elle continue même si vous fermez la fenêtre."
    } elseif ($scan -and $null -ne $scan.trouvees) {
        $champs += New-Field -Key 'scan' -Label 'Dernière analyse en ligne' -Value "$([int]$scan.trouvees) trouvée(s)" -Kind 'text' `
            -Status $(if ($scan.error) {'error'} else {'ok'}) `
            -Help "Résultat de la dernière recherche lancée depuis Vigie." `
            -Guide $(if ($scan.error) { "Erreur : $($scan.error)" } else { '' })
    }
    if ($enCours) {
        # Les phases sont des identifiants techniques : elles se traduisent avant d'etre
        # montrees. « demarrage… » s'affichait tel quel, sans accent ni majuscule.
        $libellePhase = switch ("$($inst.phase)") {
            'demarrage'      { 'Démarrage…' }
            'telechargement' { 'Téléchargement…' }
            'installation'   { 'Installation…' }
            default          { 'En cours…' }
        }
        $champs += New-Field -Key 'install' -Label 'Installation' -Value $libellePhase -Kind 'text' -Status 'neutral' `
            -Help "Installation lancée depuis Vigie. Elle continue même si vous fermez la fenêtre." `
            -Guide $(if ($inst.titres) { "Mises à jour retenues :`n- " + (@($inst.titres) -join "`n- ") } else { '' })
    } elseif ($inst -and $inst.phase -eq 'termine') {
        # On rapporte le RESULTAT constate, code de retour compris (D43) -- mais le code
        # global 3 (« reussi avec erreurs ») ne dit PAS qu'une mise a jour a echoue : il
        # sort aussi quand tout s'est installe et qu'il ne manque qu'un redemarrage. On
        # tranche donc sur le detail PAR mise a jour : 4 = echec, 5 = annulee.
        # @($null) rend un tableau d'UN element nul : indexer dessus leve « Cannot index
        # into a null array ». Les entrees de cache anterieures n'ont pas de `detail`.
        $detailInst = @()
        if ($inst.detail) { $detailInst = @($inst.detail | Where-Object { $_ -and @($_).Count -ge 2 }) }
        # Un redemarrage SURVENU APRES l'installation solde le « redemarrage requis » :
        # sans cette comparaison, la mention survivait indefiniment au redemarrage
        # (constate). On compare en UTC (D44).
        $redemarrageFait = $false
        if ($inst.redemarrage -and $inst.at) {
            try {
                $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime()
                $finInst = ConvertTo-UtcDate $inst.at
                if ($finInst -and $boot -gt $finInst) { $redemarrageFait = $true }
            } catch { }
        }
        $echecs = 0
        foreach ($d in $detailInst) { if ("$($d[1])" -match '^(Échec|Annulée)') { $echecs++ } }
        $val = if ($inst.error)          { 'échec' }
               elseif ($echecs -gt 0)    { "$echecs sur $($inst.total) en échec" }
               elseif ($redemarrageFait) { 'terminée (redémarrage effectué)' }
               elseif ($inst.redemarrage){ 'installée, redémarrage requis' }
               else                      { 'terminée' }
        $st  = if ($inst.error -or $echecs -gt 0) { 'error' }
               elseif ($inst.redemarrage -and -not $redemarrageFait) { 'warn' }
               else                               { 'ok' }
        $g = @()
        if ($inst.error) { $g += "Erreur : $($inst.error)" }
        if ($inst.redemarrage -and -not $redemarrageFait) {
            $g += "Ce que c'est : les mises à jour sont installées, mais Windows doit redémarrer pour les activer. Ce n'est pas une panne."
            $g += "Ce que vous pouvez faire : redémarrer quand cela vous arrange (le bouton « Redémarrer Windows » de cette carte, ou menu Démarrer > Redémarrer). Vigie ne redémarre jamais de lui-même."
        }
        if ($echecs -gt 0) {
            $g += "Ce qui a échoué : $echecs mise(s) à jour sur $($inst.total). Le détail par mise à jour est dans le tableau ci-dessous, avec le code d'erreur Windows."
            $g += "Ce que vous pouvez faire : relancer l'installation (une seconde tentative suffit souvent), ou passer par « Ouvrir Windows Update » qui affiche le message d'erreur complet de Windows."
        }
        # Le detail PAR mise a jour, en tableau : « terminé avec erreurs » ne dit pas
        # laquelle a echoue, ce tableau si.
        $lignes = @()
        if ($detailInst.Count) { foreach ($d in $detailInst) { $lignes += ,@("$($d[0])", "$($d[1])") } }
        elseif ($inst.titres)   { foreach ($t in @($inst.titres)) { $lignes += ,@("$t", '—') } }
        $restartCountdown = Test-RestartCountdown -Backend $backend
        $champs += New-Field -Key 'install' -Label 'Dernière installation' -Value $val -Kind 'text' -Status $st `
            -Help "Résultat de la dernière installation lancée depuis Vigie." -Guide ($g -join "`n`n") `
            -FixAction $(if ($inst.redemarrage -and -not $redemarrageFait -and -not $inst.error -and $echecs -eq 0 -and -not $restartCountdown) { 'system-restart' } else { $null }) `
            -Table @{ columns = @('Mise à jour', 'Résultat'); rows = $lignes }
    }

    $actions = @()
    # Le besoin et le geste au MEME endroit : quand la derniere installation attend un
    # redemarrage, le bouton de redemarrage est disponible dans cette carte aussi (le
    # champ general « Redémarrage en attente » vit dans la carte Windows, theme system).
    if ($inst -and $inst.phase -eq 'termine' -and $inst.redemarrage) {
        if ($restartCountdown) {
            $actions += New-Action -Id 'system-restart-cancel' -Label 'Annuler le redémarrage' -Severity 'fix' `
                -BusyLabel 'Annulation…' -Confirm -Help "Annule le redémarrage programmé. Windows reste allumé."
        } else {
            $actions += New-Action -Id 'system-restart' -Label 'Redémarrer Windows' -Severity 'fix' `
                -BusyLabel 'Redémarrage programmé…' -ConfirmTwice -Kind 'confirm' `
                -Help "Redémarre Windows dans 60 secondes pour terminer les mises à jour installées. Enregistrez votre travail : toutes les applications seront fermées. Le redémarrage reste annulable pendant le délai."
        }
    }
    # Recherche EN LIGNE : la sonde ne lit que le cache local de Windows, qui peut etre
    # perime. Ce bouton interroge les serveurs -- c'est long, donc detache.
    $actions += New-Action -Id 'wu-scan' -Label 'Vérifier les mises à jour' -BusyLabel 'Recherche en ligne…' -Kind 'immediate' `
        -Help "Interroge les serveurs Microsoft (plusieurs minutes). La valeur affichée provient sinon du cache local de Windows, qui peut être périmé."
    if ($count -gt 0) {
        $actions += New-Action -Id 'wu-list-pending' -Severity 'fix' -Label 'Installer des mises à jour' -BusyLabel 'Installation des mises à jour…' -Kind 'dialog' `
            -Help "Ouvre la liste des mises à jour détectées pour choisir celles à installer. Rien ne s'installe sans votre sélection."
    }
    $actions += New-Action -Id 'open-windows-update' -Label 'Ouvrir Windows Update' -Kind 'manual' -Help "Ouvre les Paramètres Windows Update pour installer manuellement. Déverrouillez (Mode MAJ) avant si nécessaire, puis re-verrouillez."

    New-ModuleObject -Id 'wu-pending' -Theme 'windows-update' -Label 'Mise à jour du système' -Status $(if ($enCours -or $scanEnCours) {'neutral'} elseif ($count -gt 0) {'warn'} else {'ok'}) -Fields (@(
        # La resolution est l'INSTALLATION, pas l'ouverture de Windows Update. Elle reste
        # visible dans la barre d'actions : une action designee comme correctif n'en est
        # plus retiree.
        New-Field -Key 'pending' -Label 'Détectées (non installées)' -Value $count -Kind 'number' -Status $(if ($count -gt 0) {'warn'} else {'ok'}) -Help $help -Guide $guide -FixAction $(if ($count -gt 0) { 'wu-list-pending' } else { $null })
    ) + $champs) -Actions $actions -Busy:($enCours -or $scanEnCours) `
        -BusyAction $(if ($enCours) { 'wu-list-pending' } elseif ($scanEnCours) { 'wu-scan' } else { $null })
}
