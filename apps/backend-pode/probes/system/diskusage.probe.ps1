<# Sonde : consommation du disque -- QUI mange la place sur C:.

   Elle ne parcourt RIEN elle-meme : le parcours est une tache de fond
   (workers/disk-scan.worker.ps1, lancee par l'action « disk-analyze ») qui depose son
   resultat dans var/cache/diskscan.json. La sonde se contente de lire ce fichier, ce qui
   la garde instantanee -- une sonde n'a pas le droit de faire attendre l'affichage.

   Elle montre trois choses, de la plus utile a la plus fine :
     1. la repartition du PREMIER NIVEAU (ou part la place),
     2. les plus gros DOSSIERS tous niveaux confondus (le vrai coupable est souvent
        profond : un cache, un dossier de jeux, une sauvegarde oubliee),
     3. les plus gros FICHIERS.

   Epreuve sans attendre une vraie analyse : VIGIE_FAKE_DISKSCAN=<chemin d'un JSON> fait
   lire ce fichier a la place du cache (les donnees restent de vraies mesures). #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$fichier = if ($env:VIGIE_FAKE_DISKSCAN) { $env:VIGIE_FAKE_DISKSCAN }
           else { Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.json' }

$etat = $null
if (Test-Path -LiteralPath $fichier) {
    try { $etat = Get-Content -LiteralPath $fichier -Raw | ConvertFrom-Json } catch { }
}
$scan = if ($etat) { $etat.scan } else { $null }

# Une tache de fond peut mourir sans rien ecrire (machine arretee, processus tue) : passe
# ce delai, son drapeau « en cours » ne veut plus rien dire et la carte cesserait sinon de
# tourner indefiniment (deja constate sur les paquets).
$DELAI_TACHE_MIN = 60
$enCours = [bool]($scan -and $scan.running)
$abandonnee = $false
if ($enCours -and $scan.startedAt) {
    try {
        $depuis = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $scan.startedAt)).TotalMinutes
        if ($depuis -gt $DELAI_TACHE_MIN) { $enCours = $false; $abandonnee = $true }
    } catch { }
}

$racine = if ($scan -and $scan.root) { "$($scan.root)" } else { 'C:\' }
$fields = @()
$actions = @()

if ($enCours) {
    # Dire QUOI, sur COMBIEN, DEPUIS QUAND (D50) : un « en cours… » muet n'apprend rien.
    $depuisTxt = ''
    if ($scan.startedAt) {
        try {
            $sec = [int]((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $scan.startedAt)).TotalSeconds
            $depuisTxt = if ($sec -lt 60) { "depuis $sec s" } else { "depuis $([int]($sec/60)) min" }
        } catch { }
    }
    $lus = if ($null -ne $scan.bytes) { Format-ByteSize ([long]$scan.bytes) } else { '0 o' }
    $guide = @("Dossier en cours : $($scan.current)",
               "$([int]$scan.files) fichiers mesurés, $lus lus.",
               "Le parcours ne modifie rien : il ne fait que lire les tailles.") -join "`n"
    $fields += New-Field -Key 'progress' -Label 'Dossiers parcourus' -Value ([int]$scan.dirs) -Kind 'number' -Status 'neutral' `
        -Help "Analyse de $racine en cours $depuisTxt." -Guide $guide
    $actions += New-Action -Id 'disk-analyze-stop' -Label 'Arrêter l''analyse' -Kind 'immediate' -Severity 'neutral' `
        -BusyLabel 'Arrêt…' -Help "Interrompt le parcours. Le dernier résultat complet reste affiché."
} else {
    $arbre = if ($etat) { $etat.tree } else { $null }
    if (-not $arbre) {
        $quoi = if ($abandonnee) { 'analyse interrompue' }
                elseif ($scan -and $scan.canceled) { 'analyse interrompue' }
                else { 'jamais analysé' }
        $fields += New-Field -Key 'state' -Label 'Analyse' -Value $quoi -Kind 'text' -Status 'neutral' `
            -Help "Lancez « Analyser l'espace » pour savoir ce qui occupe $racine." `
            -Guide "Le parcours dure de quelques secondes à quelques minutes selon le nombre de fichiers. Il lit uniquement les tailles, il ne modifie rien et vous pouvez l'arrêter à tout moment."
    } else {
        # `result` decrit l'analyse COMPLETE a laquelle l'arbre appartient ; `scan` ne dit
        # que l'etat de la derniere tache. Les confondre ferait dater l'arbre du jour d'une
        # interruption. (Filet : un cache ecrit avant cette distinction n'a que `scan`.)
        $bilan = if ($etat.result) { $etat.result } else { $scan }
        $racine = if ($bilan.root) { "$($bilan.root)" } else { $racine }
        # Une analyse interrompue laisse le dernier resultat complet en place : on le dit,
        # sinon l'utilisateur croit que son arret n'a servi a rien.
        if ($scan -and $scan.canceled) {
            $fields += New-Field -Key 'canceled' -Label 'Dernière analyse' -Value 'interrompue' -Kind 'text' -Status 'neutral' `
                -Help "Vous avez arrêté la dernière analyse : le résultat affiché est celui du parcours complet précédent." `
                -FixAction 'disk-analyze'
        }
        # Date de l'analyse, en heure locale (le fichier est ecrit en UTC -- D44).
        $quand = $null
        try { $quand = (ConvertTo-UtcDate $bilan.at).ToLocalTime() } catch { }
        $ageJours = if ($quand) { [int]((Get-Date) - $quand).TotalDays } else { 0 }
        # Un resultat vieux de plusieurs jours ne ment pas : il DATE. On le dit, sans
        # alerter -- ce n'est pas un probleme de la machine.
        if ($quand) {
            $fields += New-Field -Key 'at' -Label 'Analysé le' -Value ($quand.ToString('s')) -Kind 'date' -Status 'neutral' `
                -Help $(if ($ageJours -ge 7) { "Résultat vieux de $ageJours jours : relancez l'analyse pour une photo à jour." }
                        else { "Date du dernier parcours complet de $racine." }) `
                -Guide ("$([int]$bilan.dirs) dossiers et $([int]$bilan.files) fichiers parcourus en $([int]$bilan.seconds) s.")
        }

        $total = [long]$arbre.s
        $enfants = @($arbre.k | Sort-Object -Property @{ Expression = { [long]$_.s } } -Descending)

        # 1) Repartition du premier niveau : ou part la place.
        $lignes = @()
        foreach ($e in $enfants) {
            $pc = if ($total -gt 0) { [math]::Round(([double]$e.s / $total) * 100, 1) } else { 0 }
            $lignes += ,@("$($e.n)", (Format-ByteSize ([long]$e.s)), "$pc %")
        }
        if ($arbre.o -and [long]$arbre.o.s -gt 0) {
            $pc = if ($total -gt 0) { [math]::Round(([double]$arbre.o.s / $total) * 100, 1) } else { 0 }
            $lignes += ,@("$([int]$arbre.o.c) autres dossiers", (Format-ByteSize ([long]$arbre.o.s)), "$pc %")
        }
        $plusGros = if ($enfants.Count) { "$($enfants[0].n) — $(Format-ByteSize ([long]$enfants[0].s))" } else { '—' }
        $fields += New-Field -Key 'top' -Label 'Plus gros dossier' -Value $plusGros -Kind 'text' -Status 'neutral' `
            -Help "Répartition de $racine au premier niveau." `
            -Table @{ columns = @('Dossier', 'Taille', 'Part'); rows = $lignes }

        $fields += New-Field -Key 'total' -Label 'Total mesuré' -Value (Format-ByteSize $total) -Kind 'text' -Status 'neutral' `
            -Help "Somme des fichiers réellement lus. Elle peut être inférieure à l'espace occupé du disque : les dossiers protégés (System Volume Information, corbeilles d'autres comptes) ne sont pas lisibles, et les liens de jonction ne sont comptés qu'une fois."

        # 2) Les plus gros dossiers, tous niveaux confondus : le coupable est souvent profond.
        $rowsD = @()
        foreach ($d in @($etat.bigFolders)) {
            $rowsD += ,@("$($d.n)", (Format-ByteSize ([long]$d.s)), "$([int]$d.f)")
        }
        if ($rowsD.Count) {
            $fields += New-Field -Key 'folders' -Label 'Plus gros dossiers' -Value ("$($rowsD.Count) repérés") -Kind 'text' -Status 'neutral' `
                -Help "Les dossiers les plus lourds à tous les niveaux (chemins relatifs à $racine)." `
                -Table @{ columns = @('Dossier', 'Taille', 'Fichiers'); rows = $rowsD }
        }

        # 3) Les plus gros fichiers.
        $rowsF = @()
        foreach ($f in @($etat.bigFiles)) { $rowsF += ,@("$($f.n)", (Format-ByteSize ([long]$f.s))) }
        if ($rowsF.Count) {
            $fields += New-Field -Key 'files' -Label 'Plus gros fichiers' -Value ("$($rowsF.Count) repérés") -Kind 'text' -Status 'neutral' `
                -Help "Les fichiers les plus lourds rencontrés. Un fichier système (pagefile.sys, hiberfil.sys) est normal : ne le supprimez pas." `
                -Table @{ columns = @('Fichier', 'Taille'); rows = $rowsF }
        }

        if ($bilan.error) {
            $fields += New-Field -Key 'warn' -Label 'Parcours incomplet' -Value "$($bilan.error)" -Kind 'text' -Status 'warn' `
                -FixAction 'disk-analyze' -Help "Le parcours s'est arrêté sur une erreur : le résultat est partiel."
        }
    }
    $actions += New-Action -Id 'disk-analyze' -Label $(if ($arbre) { 'Relancer l''analyse' } else { 'Analyser l''espace' }) `
        -Kind 'immediate' -Severity 'info' -BusyLabel 'Analyse…' `
        -Help "Parcourt $racine et classe les dossiers par taille. Lecture seule : rien n'est supprimé."
}

# La carte ne juge RIEN : elle informe. Le seuil d'espace libre, lui, est sur la carte
# « Disque C: » -- deux cartes, deux questions distinctes.
New-ModuleObject -Id 'disk-usage' -Theme 'system' -Label 'Consommation du disque' -Status 'neutral' `
    -Fields $fields -Actions $actions -Busy:$enCours -BusyAction $(if ($enCours) { 'disk-analyze' } else { $null })
