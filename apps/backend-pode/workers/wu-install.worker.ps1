<# Worker DETACHE : telecharge puis installe les mises a jour Windows choisies.

   DETACHE volontairement : une installation dure des minutes. Si la requete HTTP la
   portait, une fermeture d'onglet ou une coupure reseau l'interromprait en plein
   telechargement. Ici le navigateur peut disparaitre, l'installation continue ; la carte
   se met a jour toute seule quand elle se termine.

   N'ecrit que dans var/cache (etat lisible par la sonde) et var/log (trace complete).
#>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

$ids = @()
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        $ids = @($a.ids)
    }
} catch { }
if (-not $ids -or $ids.Count -eq 0) { return }

$outFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'wu-install.json'

function Set-Etat {
    param([hashtable]$Set)
    try { Update-StateJson -Path $outFile -Set $Set | Out-Null } catch { }
}

try {
    Write-Log -Backend $Backend -Name 'wuinstall' -Message ("demande : " + $ids.Count + " mise(s) a jour")
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.Online = $false
    $res = $searcher.Search("IsInstalled=0 And IsHidden=0")

    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    $retenus = @()
    for ($i = 0; $i -lt $res.Updates.Count; $i++) {
        $u = $res.Updates.Item($i)
        if ($ids -notcontains "$($u.Identity.UpdateID)") { continue }
        # Le CLUF doit etre accepte avant tout telechargement, sinon Download() echoue.
        try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch { }
        [void]$coll.Add($u)
        $retenus += "$($u.Title)"
    }
    if ($coll.Count -eq 0) {
        Set-Etat @{ installing = $false; at = (Get-Date).ToUniversalTime().ToString('o')
                    error = "Aucune des mises a jour demandees n'a ete retrouvee." }
        Write-Log -Backend $Backend -Name 'wuinstall' -Level 'ERROR' -Message 'aucune correspondance'
        return
    }

    Set-Etat @{ installing = $true; phase = 'telechargement'; total = $coll.Count
                titres = @($retenus); at = (Get-Date).ToUniversalTime().ToString('o') }
    $dl = $session.CreateUpdateDownloader()
    $dl.Updates = $coll
    $rDl = $dl.Download()
    Write-Log -Backend $Backend -Name 'wuinstall' -Message ("telechargement : code " + $rDl.ResultCode)

    Set-Etat @{ installing = $true; phase = 'installation' }
    $inst = $session.CreateUpdateInstaller()
    $inst.Updates = $coll
    $rIn = $inst.Install()

    # ResultCode : 2 = reussi, 3 = reussi avec erreurs. Tout le reste est un echec.
    $ok = ($rIn.ResultCode -eq 2)
    $partiel = ($rIn.ResultCode -eq 3)
    Set-Etat @{
        installing = $false
        phase      = 'termine'
        at         = (Get-Date).ToUniversalTime().ToString('o')
        total      = $coll.Count
        titres     = @($retenus)
        ok         = $ok
        partiel    = $partiel
        redemarrage = [bool]$rIn.RebootRequired
        code       = [int]$rIn.ResultCode
        error      = $(if ($ok -or $partiel) { $null } else { "Installation en echec (code $($rIn.ResultCode))." })
    }
    Write-Log -Backend $Backend -Name 'wuinstall' -Message (
        "installation : code " + $rIn.ResultCode + " redemarrage=" + $rIn.RebootRequired)
} catch {
    Set-Etat @{ installing = $false; phase = 'termine'; ok = $false
                at = (Get-Date).ToUniversalTime().ToString('o'); error = $_.Exception.Message }
    Write-Log -Backend $Backend -Name 'wuinstall' -Level 'ERROR' -Message $_.Exception.Message
}

# La carte doit refleter le resultat sans attendre le TTL de la sonde.
try { Remove-ProbeCache -Names @('pending.probe.ps1') -Backend $Backend } catch { }
