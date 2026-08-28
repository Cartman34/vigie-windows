<# Sonde : LE STOCKAGE DU PC. LECTURE SEULE, rapide.

   UNE SEULE carte pour tout ce qui touche au stockage (choix utilisateur) : l'espace
   libre, les disques fixes de la machine, et le resultat de l'ANALYSE de la consommation
   -- qui est une ACTION de cette carte, pas une carte de plus.

   L'analyse elle-meme ne se fait pas ici : elle est confiee a une tache de fond
   (workers/disk-scan.worker.ps1, lancee par l'action « disk-analyze », voir D60) qui
   depose son resultat dans var/cache/diskscan.json. Cette sonde ne fait que le LIRE :
   elle reste instantanee, une sonde n'a pas le droit de faire attendre l'affichage.

   Epreuve sans attendre une vraie analyse : VIGIE_FAKE_DISKSCAN=<chemin d'un JSON> fait
   lire ce fichier a la place du cache (les donnees restent de vraies mesures). #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# --- Les disques FIXES de la machine -----------------------------------------
# Generique : le disque systeme donne le statut de la carte, les autres disques fixes
# (s'il y en a) sont listes. Rien n'est code en dur sur « C: ».
$sysLettre = "$($env:SystemDrive)"                       # « C: » sur cette machine
$disques = @()
try { $disques = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop) } catch { }
$sys = @($disques | Where-Object { $_.DeviceID -eq $sysLettre })[0]
if (-not $sys -and $disques.Count) { $sys = $disques[0] }

$freeGB  = if ($sys) { [math]::Round($sys.FreeSpace/1GB) } else { 0 }
$totGB   = if ($sys) { [math]::Round($sys.Size/1GB) } else { 0 }
$usedPct = if ($sys -and $sys.Size) { [math]::Round(($sys.Size - $sys.FreeSpace)/$sys.Size*100) } else { 0 }

# Seuil : config du module (module.psd1), surchargeable dans le menu Parametres (D57).
$threshold = [int](Get-ModuleSetting -Unit 'system' -Key 'DiskWarnGb')
if (-not $threshold) { $threshold = 60 }   # filet si la declaration disparaissait
$st = if ($freeGB -lt 20) { 'error' } elseif ($freeGB -lt $threshold) { 'warn' } else { 'ok' }

$fields = @()
$fields += New-Field -Key 'free' -Label 'Espace libre' -Value $freeGB -Kind 'number' -Unit 'Go' -Status $st `
    -Help "Espace disponible sur le disque système ($sysLettre). En dessous du seuil, risque de saturation." `
    -FixAction 'disk-cleanup' `
    -Guide 'Libérez de l''espace : lancez « Analyser l''espace » pour voir ce qui pèse, ouvrez le Nettoyage de disque, videz la corbeille, désinstallez des applications inutiles.'
$fields += New-Field -Key 'threshold' -Label 'Seuil d''alerte' -Value $threshold -Kind 'number' -Unit 'Go' -Status 'neutral' `
    -Help 'Seuil en dessous duquel on alerte. Reglable : Paramètres > Modules > Système.'
$fields += New-Field -Key 'used' -Label 'Occupation' -Value $usedPct -Kind 'number' -Unit '%' -Status 'neutral' `
    -Help "Pourcentage d'occupation du disque système ($sysLettre)."
$fields += New-Field -Key 'total' -Label 'Taille totale' -Value $totGB -Kind 'number' -Unit 'Go' -Status 'neutral' `
    -Help "Capacité totale du disque système ($sysLettre)."

# Les AUTRES disques fixes : une ligne chacun. Absents ici (une seule machine, un seul
# disque), la boucle ne produit rien -- pas de ligne muette (D49).
foreach ($d in @($disques | Where-Object { $_.DeviceID -ne $sys.DeviceID })) {
    $libre = [math]::Round($d.FreeSpace/1GB)
    $tot   = [math]::Round($d.Size/1GB)
    $nom   = if ($d.VolumeName) { "$($d.VolumeName) ($($d.DeviceID))" } else { "$($d.DeviceID)" }
    $stD   = if ($libre -lt 20) { 'warn' } else { 'neutral' }
    $fields += New-Field -Key ("vol-" + ($d.DeviceID -replace '[^A-Za-z0-9]','')) -Label $nom `
        -Value ("$libre Go libres sur $tot Go") -Kind 'text' -Status $stD `
        -Help "Autre disque fixe de la machine." `
        -Guide $(if ($stD -eq 'warn') { 'Moins de 20 Go libres sur ce disque.' } else { $null })
}

# --- L'ANALYSE de la consommation (resultat de l'action « disk-analyze », D60) --
$fichier = if ($env:VIGIE_FAKE_DISKSCAN) { $env:VIGIE_FAKE_DISKSCAN }
           else { Get-VarPath -Backend $backend -Kind 'cache' -File 'diskscan.json' }
$etat = $null
if (Test-Path -LiteralPath $fichier) {
    try { $etat = Get-Content -LiteralPath $fichier -Raw | ConvertFrom-Json } catch { }
}
$scan = if ($etat) { $etat.scan } else { $null }

# Une tache de fond peut mourir sans rien ecrire (machine arretee, processus tue) : passe
# ce delai, son drapeau « en cours » ne veut plus rien dire et la carte tournerait sinon
# indefiniment (deja constate sur les paquets).
$DELAI_TACHE_MIN = 60
$enCours = [bool]($scan -and $scan.running)
if ($enCours -and $scan.startedAt) {
    try {
        $depuis = ((Get-Date).ToUniversalTime() - (ConvertTo-UtcDate $scan.startedAt)).TotalMinutes
        if ($depuis -gt $DELAI_TACHE_MIN) { $enCours = $false }
    } catch { }
}
$racine = if ($scan -and $scan.root) { "$($scan.root)" } else { "$sysLettre\" }

$actions = @(New-Action -Id 'disk-cleanup' -Severity 'fix' -Label 'Nettoyage de disque...' -Kind 'manual' `
    -Help "Ouvre l'outil Windows 'Nettoyage de disque' (cleanmgr). Vous choisissez quoi supprimer ; rien n'est supprimé automatiquement.")

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
    $fields += New-Field -Key 'scan-progress' -Label 'Analyse — dossiers parcourus' -Value ([int]$scan.dirs) -Kind 'number' -Status 'neutral' `
        -Help "Analyse de $racine en cours $depuisTxt." `
        -Guide (@("Dossier en cours : $($scan.current)",
                  "$([int]$scan.files) fichiers mesurés, $lus lus.",
                  "Le parcours ne modifie rien : il ne fait que lire les tailles.") -join "`n")
    $actions += New-Action -Id 'disk-analyze-stop' -Label 'Arrêter l''analyse' -Kind 'immediate' -Severity 'neutral' `
        -BusyLabel 'Arrêt…' -Help "Interrompt le parcours. Le dernier résultat complet reste affiché."
} else {
    $arbre = if ($etat) { $etat.tree } else { $null }
    if (-not $arbre) {
        $quoi = if ($scan -and $scan.canceled) { 'interrompue' } else { 'jamais lancée' }
        $fields += New-Field -Key 'scan-state' -Label 'Analyse de l''espace' -Value $quoi -Kind 'text' -Status 'neutral' `
            -Help "Lancez « Analyser l'espace » pour savoir ce qui occupe $racine." `
            -Guide "Le parcours dure de quelques secondes à quelques minutes selon le nombre de fichiers. Il lit uniquement les tailles, il ne modifie rien et vous pouvez l'arrêter à tout moment."
    } else {
        # `result` decrit l'analyse COMPLETE a laquelle l'arbre appartient ; `scan` ne dit
        # que l'etat de la derniere tache. Les confondre ferait dater l'arbre du jour d'une
        # interruption. (Filet : un cache ecrit avant cette distinction n'a que `scan`.)
        $bilan = if ($etat.result) { $etat.result } else { $scan }
        $racine = if ($bilan.root) { "$($bilan.root)" } else { $racine }
        if ($scan -and $scan.canceled) {
            $fields += New-Field -Key 'scan-canceled' -Label 'Dernière analyse' -Value 'interrompue' -Kind 'text' -Status 'neutral' `
                -Help "Vous avez arrêté la dernière analyse : le résultat affiché est celui du parcours complet précédent." `
                -FixAction 'disk-analyze'
        }
        # Date de l'analyse, en heure locale (le fichier est ecrit en UTC -- D44).
        $quand = $null
        try { $quand = (ConvertTo-UtcDate $bilan.at).ToLocalTime() } catch { }
        $ageJours = if ($quand) { [int]((Get-Date) - $quand).TotalDays } else { 0 }
        if ($quand) {
            $fields += New-Field -Key 'scan-at' -Label 'Espace analysé le' -Value ($quand.ToString('s')) -Kind 'date' -Status 'neutral' `
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
        $fields += New-Field -Key 'scan-top' -Label 'Premier niveau' -Value $plusGros -Kind 'text' -Status 'neutral' `
            -Help "Répartition de $racine au premier niveau : le plus gros dossier est affiché, le détail complet est dans le tableau." `
            -Table @{ columns = @('Dossier', 'Taille', 'Part'); rows = $lignes }

        $fields += New-Field -Key 'scan-total' -Label 'Total mesuré' -Value (Format-ByteSize $total) -Kind 'text' -Status 'neutral' `
            -Help "Somme des fichiers réellement lus. Elle peut être inférieure à l'espace occupé du disque : les dossiers protégés (System Volume Information, corbeilles d'autres comptes) ne sont pas lisibles, et les liens de jonction ne sont comptés qu'une fois."

        # 2) Les plus gros dossiers, tous niveaux confondus : le coupable est souvent profond.
        $rowsD = @()
        foreach ($d in @($etat.bigFolders)) { $rowsD += ,@("$($d.n)", (Format-ByteSize ([long]$d.s)), "$([int]$d.f)") }
        if ($rowsD.Count) {
            # La VALEUR dit le coupable ; le tableau donne le classement complet.
            $coupable = "$($etat.bigFolders[0].n) — $(Format-ByteSize ([long]$etat.bigFolders[0].s))"
            $fields += New-Field -Key 'scan-folders' -Label 'Où part la place' -Value $coupable -Kind 'text' -Status 'neutral' `
                -Help "Le dossier le plus lourd où la place se partage vraiment, tous niveaux confondus (chemins relatifs à $racine). Les dossiers dont un seul enfant explique tout le poids sont écartés : c'est l'enfant qui est montré." `
                -Table @{ columns = @('Dossier', 'Taille', 'Fichiers'); rows = $rowsD }
        }

        # 3) Les plus gros fichiers.
        $rowsF = @()
        foreach ($f in @($etat.bigFiles)) { $rowsF += ,@("$($f.n)", (Format-ByteSize ([long]$f.s))) }
        if ($rowsF.Count) {
            $nomFichier = Split-Path "$($etat.bigFiles[0].n)" -Leaf
            $fields += New-Field -Key 'scan-files' -Label 'Plus gros fichier' -Value ("$nomFichier — $(Format-ByteSize ([long]$etat.bigFiles[0].s))") -Kind 'text' -Status 'neutral' `
                -Help "Les fichiers les plus lourds rencontrés. Un fichier système (pagefile.sys, hiberfil.sys) est normal : ne le supprimez pas." `
                -Table @{ columns = @('Fichier', 'Taille'); rows = $rowsF }
        }

        if ($bilan.error) {
            $fields += New-Field -Key 'scan-warn' -Label 'Parcours incomplet' -Value "$($bilan.error)" -Kind 'text' -Status 'warn' `
                -FixAction 'disk-analyze' -Help "Le parcours s'est arrêté sur une erreur : le résultat est partiel."
        }
    }
    # L'exploration est une ACTION (choix utilisateur), pas une ligne de la carte : elle
    # ouvre une fenetre qui demande les niveaux au serveur au fur et a mesure.
    if ($arbre) {
        $actions += New-Action -Id 'disk-tree' -Label 'Explorer l''arborescence' -Kind 'dialog' -Severity 'info' `
            -Help "Parcourt les dossiers du plus gros au plus petit, niveau par niveau. Chaque niveau est demandé au moment où vous le dépliez."
    }
    $actions += New-Action -Id 'disk-analyze' -Label $(if ($arbre) { 'Relancer l''analyse' } else { 'Analyser l''espace' }) `
        -Kind 'immediate' -Severity 'info' -BusyLabel 'Analyse…' `
        -Help "Parcourt $racine et classe les dossiers par taille. Lecture seule : rien n'est supprimé."
}

New-ModuleObject -Id 'storage' -Theme 'system' -Label 'Stockage' -Status $st -Fields $fields -Actions $actions `
    -Busy:$enCours -BusyAction $(if ($enCours) { 'disk-analyze' } else { $null })
