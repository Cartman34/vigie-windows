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
        $updates += [ordered]@{
            id        = "$($u.Identity.UpdateID)"
            titre     = "$($u.Title)"
            kb        = ($kb -join ', ')
            octets    = $taille
            pilote    = $pilote
            telecharge = [bool]$u.IsDownloaded
        }
    }
} catch {
    return @{
        message = "Impossible de lire la liste : $($_.Exception.Message)"
        result  = @{ ok = $false }
    }
}

# Le verrouillage des taches (Mode MAJ) empeche l'installation : on le DIT ici plutot que
# de laisser l'installation echouer sans explication.
$verrou = $false
try { $verrou = Test-UpdateTasksAclLock } catch { }

@{
    message = "$($updates.Count) mise(s) a jour detectee(s)."
    result  = @{
        ok       = $true
        choose   = $true          # l'interface doit ouvrir une fenetre de choix
        action   = 'wu-install'   # action a appeler avec les identifiants retenus
        verrou   = $verrou
        updates  = @($updates)
    }
}
