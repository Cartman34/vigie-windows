# @author Florent HAZARD <f.hazard@sowapps.com>
<# Worker DETACHE : telecharge puis installe les mises a jour Windows choisies.

   DETACHE volontairement : une installation dure des minutes. Si la requete HTTP la
   portait, une fermeture d'onglet ou une coupure reseau l'interromprait en plein
   telechargement. Ici le navigateur peut disparaitre, l'installation continue ; la carte
   se met a jour toute seule quand elle se termine.

   N'ecrit que dans var/cache (etat lisible par la sonde) et var/log (trace complete).
#>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { exit 1 }
. (Join-Path $Backend 'lib/common.ps1')

$ids = @()
$reposerVerrou = $false
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        $ids = @($a.ids)
        $reposerVerrou = [bool]$a.reposerVerrou
    }
} catch { }
if (-not $ids -or $ids.Count -eq 0) { Write-Output ('[X] ' + (Get-Label 'wu-install.aucun-identifiant')); exit 1 }

$outFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'wu-install.json'

# Every OperationResultCode of Windows Update gets a name: 0 not started, 1 in progress, 2 to 5 the final ones.
# "Install" never appears in a failure's name: the pending list reads it as installed.
function Get-ResultVerdict {
    param([int]$Code)
    switch ($Code) {
        0       { 'Non commencée' }
        1       { 'Inachevée' }
        2       { 'Installée' }
        3       { 'Installée avec erreurs' }
        4       { 'Échec' }
        5       { 'Annulée' }
        default { 'Résultat illisible' }
    }
}

# The latest installation entry of Windows Update's history for one update, most recent first; $null if none.
function Get-InstallHistoryEntry {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$UpdateId)
    try {
        $historySearcher = $Session.CreateUpdateSearcher()
        $count = $historySearcher.GetTotalHistoryCount()
        if ($count -le 0) { return $null }
        foreach ($entry in @($historySearcher.QueryHistory(0, [Math]::Min($count, 100)))) {
            # Operation 1 is an installation, 2 an uninstallation.
            if ("$($entry.UpdateIdentity.UpdateID)" -eq $UpdateId -and [int]$entry.Operation -eq 1) { return $entry }
        }
    } catch { }
    return $null
}

function Set-Etat {
    param([hashtable]$Set)
    try { Update-StateJson -Path $outFile -Set $Set | Out-Null } catch { }
}

# Le verrou du Mode MAJ empeche l'installation. On le LEVE ici et on le REPOSE dans le
# finally : quoi qu'il arrive -- succes, echec, exception -- la machine retrouve l'etat dans
# lequel l'utilisateur l'avait laissee. Un verrou de securite qu'on oublie de remettre est
# pire que pas de verrou du tout.
$verrouLeve = $false
$exitCode = 0
try {
    if ($reposerVerrou) {
        $verrouLeve = Set-UpdateLock -Etat 'leve' -Backend $Backend
        Write-Log -Backend $Backend -Name 'wuinstall' -Message (Get-Label 'wu-install.verrou-leve' $verrouLeve)
        if (-not $verrouLeve) { throw "Le verrou des mises à jour n'a pas pu être levé." }
    }
    Write-Log -Backend $Backend -Name 'wuinstall' -Message (Get-Label 'wu-install.demande-mise-jour' $ids.Count)
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.Online = $false
    $res = $searcher.Search("IsInstalled=0 And IsHidden=0")

    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    $retenus = @()
    $keptIds = @()
    for ($i = 0; $i -lt $res.Updates.Count; $i++) {
        $u = $res.Updates.Item($i)
        if ($ids -notcontains "$($u.Identity.UpdateID)") { continue }
        # Le CLUF doit etre accepte avant tout telechargement, sinon Download() echoue.
        try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch { }
        [void]$coll.Add($u)
        $retenus += "$($u.Title)"
        # THE IDENTIFIER TRAVELS WITH THE TITLE. A verdict filed under a title attaches to
        # nothing: two drivers often share one, and the identifier is what the list knows.
        $keptIds += "$($u.Identity.UpdateID)"
    }
    if ($coll.Count -eq 0) { throw "Aucune des mises à jour demandées n'a été retrouvée." }
    # A REQUESTED UPDATE THE SEARCH NO LONGER FINDS IS REPORTED, never dropped: on 12/09 four were asked for, three
    # were installed or refused, and the fourth vanished from the report without a word.
    $missing = @($ids | Where-Object { $keptIds -notcontains "$_" })
    foreach ($id in $missing) { Write-Log -Backend $Backend -Name 'wuinstall' -Message (Get-Label 'wu-install.introuvable' $id) }
    Set-Etat @{ phase = 'telechargement'; total = $coll.Count
                titres = @($retenus); at = (Get-Date).ToUniversalTime().ToString('o') }
    $dl = $session.CreateUpdateDownloader()
    $dl.Updates = $coll
    $rDl = $dl.Download()
    Write-Log -Backend $Backend -Name 'wuinstall' -Message (Get-Label 'wu-install.telechargement-code' $rDl.ResultCode)

    Set-Etat @{ phase = 'installation' }
    $inst = $session.CreateUpdateInstaller()
    $inst.Updates = $coll
    $rIn = $inst.Install()

    # ResultCode : 2 = reussi, 3 = reussi avec erreurs. Tout le reste est un echec.
    $ok = ($rIn.ResultCode -eq 2)
    $partiel = ($rIn.ResultCode -eq 3)

    # « Termine avec erreurs » sans dire LAQUELLE n'apprend rien. Windows fournit un
    # resultat PAR mise a jour : on le releve et on l'expose.
    $detail = @()
    $failures = @{}
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $r = $null
        try { $r = $rIn.GetUpdateResult($i) } catch { }
        $c = if ($r) { [int]$r.ResultCode } else { -1 }
        $h = if ($r) { [int]$r.HResult } else { 0 }
        # NO FINAL VERDICT IN THE RESULT: Windows Update's history usually has it. On 12/09 the result gave nothing
        # for PowerShell 7.6.6, shown "Inconnu", while the history said failed, 0x80242008.
        if ($c -lt 2 -or $c -gt 5) {
            $entry = Get-InstallHistoryEntry -Session $session -UpdateId "$($keptIds[$i])"
            if ($entry -and [int]$entry.ResultCode -ge 2 -and [int]$entry.ResultCode -le 5) {
                $c = [int]$entry.ResultCode
                $h = [int]$entry.HResult
            }
        }
        $verdict = Get-ResultVerdict -Code $c
        if ($h -ne 0) { $verdict += (" (0x{0:X8})" -f $h) }
        $detail += ,@($retenus[$i], $verdict)
        # WHAT FAILED IS KEPT, filed by identifier. The pending list uses it to say so next
        # to the line instead of re-offering it as if nothing had happened -- and to stop
        # hiding the older version when the newest one will not install.
        if ($c -ne 2 -and $c -ne 3) { $failures["$($keptIds[$i])"] = $verdict }
        Write-Log -Backend $Backend -Name 'wuinstall' -Message (Get-Label 'wu-install.resultat' $retenus[$i] $verdict)
    }
    foreach ($id in $missing) {
        $detail += ,@("$id", 'Introuvable')
        $failures["$id"] = 'Introuvable'
    }
    Set-Etat @{
        phase      = 'termine'
        at         = (Get-Date).ToUniversalTime().ToString('o')
        total      = $ids.Count
        titres     = @($retenus)
        detail     = @($detail)
        echecs     = $failures
        ok         = $ok
        partiel    = $partiel
        redemarrage = [bool]$rIn.RebootRequired
        code       = [int]$rIn.ResultCode
        error      = $(if ($ok -or $partiel) { $null } else { "Installation en échec (code $($rIn.ResultCode))." })
    }
    Write-Log -Backend $Backend -Name 'wuinstall' -Message (Get-Label 'wu-install.installation-code-redemarrage' $rIn.ResultCode $rIn.RebootRequired)
    # THE OUTCOME LEAVES BY THE EXIT CODE, which the watcher reads, and its reason by a [X] line of the log.
    if ($failures.Count -gt 0) {
        $exitCode = 1
        Write-Output ('[X] ' + (Get-Label 'wu-install.echecs' $failures.Count $ids.Count))
    } elseif (-not ($ok -or $partiel)) {
        $exitCode = 1
        Write-Output ('[X] ' + (Get-Label 'wu-install.code-global' $rIn.ResultCode))
    }
} catch {
    Set-Etat @{ phase = 'termine'; ok = $false
                at = (Get-Date).ToUniversalTime().ToString('o'); error = $_.Exception.Message }
    Write-Log -Backend $Backend -Name 'wuinstall' -Level 'ERROR' -Message $_.Exception.Message
    $exitCode = 1
    Write-Output ('[X] ' + $_.Exception.Message)
} finally {
    if ($verrouLeve) {
        $repose = Set-UpdateLock -Etat 'pose' -Backend $Backend
        Write-Log -Backend $Backend -Name 'wuinstall' -Message (Get-Label 'wu-install.verrou-repose' $repose)
        if (-not $repose) {
            # Etat anormal : on le SIGNALE au lieu de le taire, la machine reste ouverte.
            Set-Etat @{ verrouNonRepose = $true }
            Write-Log -Backend $Backend -Name 'wuinstall' -Level 'ERROR' -Message (Get-Label 'wu-install.verrou-non-repose')
        }
    }
    # Les deux cartes doivent refleter le resultat sans attendre le TTL des sondes.
    try { Remove-ProbeCache -Names @('pending.probe.ps1','lock.probe.ps1') -Backend $Backend } catch { }
}
exit $exitCode
