# @author Florent HAZARD <f.hazard@sowapps.com>
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
    -Guide 'Pour libérer de l''espace : « Analyser l''espace » montre ce qui pèse, puis viennent le Nettoyage de disque, la corbeille à vider et les applications inutiles à désinstaller.'
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

# WHAT IS RUNNING IS SAID BY THE BUSY MARK (doc/progress/targeting/operations.md): no expiry of our own any more.
$enCours = [bool](Get-ModuleBusyMark -Module 'storage' -Backend $backend)
$racine = if ($scan -and $scan.root) { "$($scan.root)" } else { "$sysLettre\" }

# Destination PERMANENTE (D114) : les parametres de stockage de Windows montrent ce qui
# occupe le disque par categorie, que la carte alerte ou non.
<#
    WHERE THE SPACE WENT, WITHOUT ASKING FOR A SCAN.

    On 28/09 the disk was down to 28 GB of 952 and the card could not say why: it showed the figure of the day, the
    space analysis had never been run, and nothing compared today with last week. Two readings answer most of it,
    and both are cheap.

    THE TREND comes from the history Vigie already keeps (disk.free, one point per half-hour): it says how much was
    lost over seven days, which turns "the disk is full" into "fifty gigabytes went somewhere since Monday".

    THE VIRTUAL DISKS are looked up where they live, never by scanning the disk: WSL, Docker, Hyper-V, VirtualBox.
    They grow with what they hold and NEVER give the space back on their own -- on 28/09 the WSL disk held 150.7 GB
    for 93 GB of content. A full answer still comes from the space analysis, which the card offers.
#>
$histWindow = [TimeSpan]::FromDays(7)
$trend = $null
try { $trend = Get-MeasureHistory -Backend $backend -MeasureId 'disk.free' -Window $histWindow -MaxPoints 400 } catch { }
$trendPoints = @()
if ($trend -and $trend.points) { $trendPoints = @($trend.points) }
if ($trendPoints.Count -ge 2) {
    $first = [double]$trendPoints[0].v
    $last  = [double]$trendPoints[-1].v
    $delta = [math]::Round($last - $first)
    $depuis = $null
    try { $depuis = (ConvertTo-UtcDate $trendPoints[0].at).ToLocalTime() } catch { }
    $mot = if ($delta -lt 0) { "$([math]::Abs($delta)) Go de moins" } elseif ($delta -gt 0) { "$delta Go de plus" } else { 'stable' }
    $valeur = $mot + $(if ($depuis) { ' depuis le ' + $depuis.ToString('dd/MM') } else { '' })
    # LOSING MORE THAN WHAT IS LEFT, in a week, is the real signal: at that pace the disk is full before the end of
    # the next one.
    $trendStatus = if ($delta -lt 0 -and [math]::Abs($delta) -ge $freeGB) { 'warn' } else { 'neutral' }
    # ONE ROW PER DAY: the day the space went shows up, and that is what the question asks.
    $parJour = @{}
    foreach ($pt in $trendPoints) {
        $quand = $null
        try { $quand = (ConvertTo-UtcDate $pt.at).ToLocalTime() } catch { continue }
        $jour = $quand.ToString('dd/MM')
        if (-not $parJour.ContainsKey($jour)) { $parJour[$jour] = @{ Premier = [double]$pt.v; Dernier = [double]$pt.v; Ordre = $quand } }
        $parJour[$jour].Dernier = [double]$pt.v
    }
    $rows = @(foreach ($jour in @($parJour.Keys | Sort-Object { $parJour[$_].Ordre })) {
        $e = $parJour[$jour]
        $ecart = [math]::Round($e.Dernier - $e.Premier)
        ,@($jour, "$([math]::Round($e.Dernier)) Go", $(if ($ecart -eq 0) { '—' } elseif ($ecart -gt 0) { "+$ecart Go" } else { "$ecart Go" }))
    })
    $fields += New-Field -Key 'trend' -Label 'Évolution' -Value $valeur -Kind 'text' -Status $trendStatus `
        -Table @{ columns = @('Jour', 'Libre en fin de journée', 'Variation'); rows = $rows } `
        -Help "Ce que l'espace libre a fait sur sept jours, d'après les relevés que Vigie garde. La variation du jour dit quand la place est partie ; ce qui l'a prise se cherche avec « Analyser l'espace »."
}

# THE VIRTUAL DISKS, looked up where they live: no walk of the disk. Store packages hold theirs two levels down
# (Packages\<paquet>\LocalState\ext4.vhdx), and that walk alone took 3.1 s on 28/09 -- far too much for a card
# recomputed every five seconds. The list is therefore kept half an hour in the cache: a virtual disk does not
# appear or vanish within the minute.
$vdisks = @()
$vdiskFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'virtual-disks.json'
$vdiskCache = $null
if (Test-Path $vdiskFile) { try { $vdiskCache = Get-Content $vdiskFile -Raw | ConvertFrom-Json } catch { } }
$vdiskFresh = $false
if ($vdiskCache -and $vdiskCache.at) {
    try { $vdiskFresh = (([datetime]::UtcNow - (ConvertTo-UtcDate $vdiskCache.at)).TotalMinutes -lt 30) } catch { }
}
if ($vdiskFresh) {
    foreach ($v in @($vdiskCache.disks)) {
        if (-not $v -or -not $v.Chemin) { continue }
        $vdisks += [pscustomobject]@{ Nom = "$($v.Nom)"; Go = [double]$v.Go; Quand = (ConvertTo-UtcDate $v.Quand).ToLocalTime(); Chemin = "$($v.Chemin)" }
    }
} else {
    $vdiskRoots = @()
    foreach ($profil in @(Get-ChildItem -Path (Join-Path $env:SystemDrive 'Users') -Directory -ErrorAction SilentlyContinue)) {
        $local = Join-Path $profil.FullName 'AppData\Local'
        $vdiskRoots += [pscustomobject]@{ Path = (Join-Path $local 'Packages'); Depth = 2; Ext = @('*.vhdx') }   # WSL and Store distributions
        $vdiskRoots += [pscustomobject]@{ Path = (Join-Path $local 'Docker\wsl'); Depth = 3; Ext = @('*.vhdx') }
        $vdiskRoots += [pscustomobject]@{ Path = (Join-Path $profil.FullName 'VirtualBox VMs'); Depth = 3; Ext = @('*.vdi', '*.vmdk', '*.vhd') }
    }
    $vdiskRoots += [pscustomobject]@{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Virtual Hard Disks'); Depth = 2; Ext = @('*.vhdx', '*.vhd') }
    foreach ($racine in $vdiskRoots) {
        if (-not (Test-PathSafe $racine.Path)) { continue }
        foreach ($ext in $racine.Ext) {
            foreach ($f in @(Get-ChildItem -LiteralPath $racine.Path -Filter $ext -File -Recurse -Depth $racine.Depth -Force -ErrorAction SilentlyContinue)) {
                if ($f.Length -lt 5GB) { continue }
                $vdisks += [pscustomobject]@{ Nom = $f.Name; Go = [math]::Round($f.Length / 1GB, 1); Quand = $f.LastWriteTime; Chemin = $f.FullName }
            }
        }
    }
    try {
        Update-StateJson -Path $vdiskFile -Set @{ at = ([datetime]::UtcNow).ToString('o')
                                                  disks = @($vdisks | ForEach-Object { @{ Nom = $_.Nom; Go = $_.Go; Quand = $_.Quand.ToUniversalTime().ToString('o'); Chemin = $_.Chemin } }) } | Out-Null
    } catch { }
}
if ($vdisks.Count) {
    $vdisks = @($vdisks | Sort-Object Go -Descending)
    $sommeGo = [math]::Round((($vdisks | Measure-Object Go -Sum).Sum), 1)
    # INFORMATION, NOT AN ALERT: a large virtual disk is normal, and no button of Vigie compacts it -- compacting is
    # the user's gesture, machine stopped. What alerts is the free space and its trend, just above.
    $vdStatus = 'neutral'
    $fields += New-Field -Key 'vdisks' -Label 'Disques virtuels' -Value ("$sommeGo Go pour $($vdisks.Count) disque(s)") -Kind 'text' -Status $vdStatus `
        -Table @{ columns = @('Fichier', 'Taille', 'Écrit le', 'Emplacement')
                  rows = @(foreach ($v in @($vdisks | Select-Object -First 8)) { ,@($v.Nom, "$($v.Go) Go", $v.Quand.ToString('dd/MM HH:mm'), (Split-Path $v.Chemin -Parent)) }) } `
        -Help "Les disques des machines virtuelles (WSL, Docker, Hyper-V, VirtualBox). Ils grossissent avec ce qu'ils contiennent et ne rendent jamais la place d'eux-mêmes, même quand on efface à l'intérieur." `
        -Guide ("Un disque virtuel garde sa taille : effacer des fichiers à l'intérieur libère la place pour la machine virtuelle, pas pour Windows." + [Environment]::NewLine + [Environment]::NewLine +
                "Pour WSL : « wsl --manage <distribution> --set-sparse true » lui fait rendre la place au fur et à mesure, après « wsl --shutdown ». Pour Hyper-V : « Optimize-VHD ». Dans les deux cas, l'opération se fait machine virtuelle arrêtée, et Vigie ne la lance pas d'elle-même.")
}

$actions = @(New-Action -Id 'open-storage-settings' -Label 'Paramètres de stockage' -Kind 'manual' -Severity 'info' `
                        -Help 'Ouvre les paramètres de stockage de Windows : ce qui occupe le disque, et l''assistant de stockage.'
             New-Action -Id 'disk-cleanup' -Severity 'fix' -Label 'Nettoyage de disque...' -Kind 'manual' `
    -Help "Ouvre l'outil Windows 'Nettoyage de disque' (cleanmgr). Rien n'est supprimé sans un choix explicite dans l'outil.")

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
            -Help "« Analyser l'espace » montre ce qui occupe $racine." `
            -Guide "Le parcours dure de quelques secondes à quelques minutes selon le nombre de fichiers. Il lit uniquement les tailles, il ne modifie rien et s'arrête à tout moment."
    } else {
        # `result` decrit l'analyse COMPLETE a laquelle l'arbre appartient ; `scan` ne dit
        # que l'etat de la derniere tache. Les confondre ferait dater l'arbre du jour d'une
        # interruption. (Filet : un cache ecrit avant cette distinction n'a que `scan`.)
        $bilan = if ($etat.result) { $etat.result } else { $scan }
        $racine = if ($bilan.root) { "$($bilan.root)" } else { $racine }
        if ($scan -and $scan.canceled) {
            $fields += New-Field -Key 'scan-canceled' -Label 'Dernière analyse' -Value 'interrompue' -Kind 'text' -Status 'neutral' `
                -Help "La dernière analyse a été arrêtée : le résultat affiché est celui du parcours complet précédent." `
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
            -Help "Parcourt les dossiers du plus gros au plus petit, niveau par niveau. Chaque niveau est demandé au moment où il se déplie."
    }
    $actions += New-Action -Id 'disk-analyze' -Label $(if ($arbre) { 'Relancer l''analyse' } else { 'Analyser l''espace' }) `
        -Kind 'immediate' -Severity 'info' -BusyLabel 'Analyse…' `
        -Help "Parcourt $racine et classe les dossiers par taille. Lecture seule : rien n'est supprimé."
}

# A failure the worker could not write itself is the protocol's result, and the card says it.
if (-not $enCours) {
    $failure = New-UnreportedFailureField -Module 'storage' -WrittenAt $(if ($scan) { $scan.at } else { $null }) -Backend $backend
    if ($failure) { $fields += $failure }
}

New-ModuleObject -Id 'storage' -Theme 'system' -Label 'Stockage' -Status $st -Fields $fields -Actions $actions `
    -Busy:$enCours -BusyAction $(if ($enCours) { 'disk-analyze' } else { $null })
