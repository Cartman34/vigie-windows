# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action : liste les mises a jour Windows detectees et NON installees.

   LECTURE SEULE. Sert a remplir la fenetre de choix de l'interface : on ne peut pas
   demander a l'utilisateur QUOI installer sans lui montrer la liste avec un identifiant
   stable par ligne.

   Recherche LOCALE (Online = $false), comme la sonde : aucune analyse en ligne n'est
   declenchee ici, donc aucune surprise de duree ni de trafic.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$updates = @()
try {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $searcher.Online = $false
    $res = $searcher.Search("IsInstalled=0 And IsHidden=0")
    for ($i = 0; $i -lt $res.Updates.Count; $i++) {
        $u = $res.Updates.Item($i)
        # Taille : MaxDownloadSize est en octets et vaut 0 quand la MAJ est deja telechargee.
        $taille = 0
        try { $taille = [int64]$u.MaxDownloadSize } catch { }
        $pilote = $false
        try { $pilote = ($u.Type -eq 2) } catch { }   # 2 = ushDriver
        $kb = @()
        try { foreach ($k in $u.KBArticleIDs) { $kb += "KB$k" } } catch { }
        # Deux pilotes portent souvent le MEME titre (« Lenovo System Driver Update »),
        # a la version pres. Sans element distinctif, la liste demande de choisir entre
        # deux lignes identiques. On expose donc le materiel vise et la date du pilote.
        $modele = ''
        try { if ($u.DriverModel)  { $modele = "$($u.DriverModel)" } } catch { }
        $classe = ''
        try { if ($u.DriverClass)  { $classe = "$($u.DriverClass)" } } catch { }
        $dateP = ''
        try { if ($u.DriverVerDate) { $dateP = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch { }
        # THE PROVIDER COMES FROM THE DATA, never from the title. Driver titles start with
        # the maker, a security fix's title does not: reading the name out of the text would
        # work forty-eight times out of forty-nine, which is the worst possible ratio.
        $provider = ''
        try { if ($u.DriverProvider) { $provider = "$($u.DriverProvider)" } } catch { }
        $updates += [ordered]@{
            id        = "$($u.Identity.UpdateID)"
            titre     = "$($u.Title)"
            kb        = ($kb -join ', ')
            octets    = $taille
            pilote    = $pilote
            modele    = $modele
            classe    = $classe
            dateP     = $dateP
            provider  = $provider
            groupe    = ''
            libelle   = ''
            remplacee = $false
            telecharge = [bool]$u.IsDownloaded
        }
    }
} catch {
    return @{
        message = "Impossible de lire la liste : $($_.Exception.Message)"
        result  = @{ ok = $false }
    }
}

<#
    THE GROUP IS COMPUTED ONCE THE LIST IS COMPLETE, never line by line: a maker's label
    depends on ALL the spellings seen for it. Intel writes itself three ways here, and only
    with all three in hand can "Intel Corporation" be preferred over "INTEL", which shouts.

    What is not a driver has no maker: it is Windows itself, and that forms its own group
    (D118).
#>
$seenByKey = @{}
foreach ($line in $updates) {
    if (-not $line.pilote -or -not "$($line.provider)".Trim()) { continue }
    $key = Get-VendorKey "$($line.provider)"
    if (-not $seenByKey.ContainsKey($key)) { $seenByKey[$key] = @() }
    $seenByKey[$key] += "$($line.provider)"
}
foreach ($line in $updates) {
    if (-not $line.pilote) { $line.groupe = 'Windows'; continue }
    $key = Get-VendorKey "$($line.provider)"
    $line.groupe = $(if ($key) { Get-VendorName -Key $key -Seen $seenByKey[$key] -Backend $backend }
                     else { 'Pilotes sans constructeur déclaré' })
}

<#
    TWO UPDATES FOR ONE DRIVER ARE TWO VERSIONS OF IT.

    Seen by the owner on 10/09: "Elevoc Device Extension" offered twice, 3.0.2.218 dated
    2024 and 3.0.2.308 dated 2025 -- two lines that look identical until you compare the
    dates, four such pairs in the list.

    They are put SIDE BY SIDE, newest first, and the older one is marked. It is not hidden:
    Windows offers it, and hiding it would decide in the owner's place.

    THE CLASS IS PART OF THE PAIR, and the date must actually differ. Measured the same day:
    "Intel(R) UHD Graphics" appears twice on the SAME date, once as Display and once as
    Extension -- two components of one device, not two versions of one component. Pairing on
    the model alone marked one of them old, which was simply false.

    So: same maker, same model AND same class. Equal dates supersede nothing. An update with
    no model -- a security fix -- pairs with nothing.
#>
$byModel = @{}
foreach ($line in $updates) {
    if (-not "$($line.modele)".Trim()) { continue }
    $key = "$($line.groupe)|$($line.modele)|$($line.classe)".ToLowerInvariant()
    if (-not $byModel.ContainsKey($key)) { $byModel[$key] = @() }
    $byModel[$key] += $line
}
foreach ($key in @($byModel.Keys)) {
    $family = @($byModel[$key])
    if ($family.Count -lt 2) { continue }
    $dates = @($family | ForEach-Object { "$($_.dateP)" } | Sort-Object -Unique)
    if ($dates.Count -lt 2) { continue }
    $newest = @($family | Sort-Object { "$($_.dateP)" } -Descending)[0]
    foreach ($line in $family) { if ("$($line.dateP)" -ne "$($newest.dateP)") { $line.remplacee = $true } }
}

<#
    THE MODEL NAMES THE LINE, NOT WINDOWS' TITLE.

    Seen on 10/09: three lines reading "Nahimic - MEDIA - 2.0.5.0", "… 1.1.4.0" and
    "… 2.0.4.0". They look like one thing offered three times; they are three DEVICES --
    a mirroring device, a VAD, an Easy Surround device -- and their titles carry the
    VERSION where other makers put the model.

    Inside a maker's group, repeating the maker in every title says nothing anyway. So the
    line is named by its model, and Windows' own title moves down into the detail, where
    the version it carries stays readable.
#>
foreach ($line in $updates) {
    if ($line.pilote -and "$($line.modele)".Trim()) { $line.libelle = "$($line.modele)" }
}

# THE ORDER PUTS THE TWO VERSIONS SIDE BY SIDE. The front end keeps the array's order inside
# a group, so adjacency is decided here.
$updates = @($updates | Sort-Object @{ Expression = { "$($_.groupe)" } },
                                    @{ Expression = { "$($_.modele)" } },
                                    @{ Expression = { "$($_.classe)" } },
                                    @{ Expression = { "$($_.dateP)" }; Descending = $true })

# Le verrouillage des taches (Mode MAJ) empeche l'installation : on le DIT ici plutot que
# de laisser l'installation echouer sans explication.
$verrou = $false
try { $verrou = Test-UpdateTasksAclLock } catch { }

@{
    message = "$($updates.Count) mise(s) à jour détectée(s)."
    result  = @{
        ok       = $true
        choose   = $true          # l'interface doit ouvrir une fenetre de choix
        action   = 'wu-install'   # action a appeler avec les identifiants retenus
        verrou   = $verrou
        updates  = @($updates)
    }
}
