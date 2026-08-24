<# Worker DETACHE : recherche EN LIGNE des mises a jour Windows.

   La sonde `pending` ne fait qu'une recherche LOCALE (cache de Windows Update) : elle est
   instantanee mais ne voit que ce que Windows a deja decouvert. Cette analyse-ci interroge
   les serveurs : elle prend des minutes, d'ou le worker detache.

   Le verrou du Mode MAJ coupe les analyses : il est leve puis REPOSE, comme pour
   l'installation. L'utilisateur n'a rien a defaire a la main.
#>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

$reposerVerrou = $false
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        $reposerVerrou = [bool]$a.reposerVerrou
    }
} catch { }

$outFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'wu-scan.json'
function Set-Etat { param([hashtable]$Set) try { Update-StateJson -Path $outFile -Set $Set | Out-Null } catch { } }

$verrouLeve = $false
try {
    if ($reposerVerrou) {
        $verrouLeve = Set-UpdateLock -Etat 'leve' -Backend $Backend
        Write-Log -Backend $Backend -Name 'wuscan' -Message ("verrou leve : " + $verrouLeve)
    }
    Set-Etat @{ scanning = $true; at = (Get-Date).ToUniversalTime().ToString('o') }

    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $searcher.Online = $true      # <- toute la difference avec la sonde
    $res = $searcher.Search("IsInstalled=0 And IsHidden=0")
    $n = [int]$res.Updates.Count

    Set-Etat @{ scanning = $false; ok = $true; trouvees = $n; error = $null
                at = (Get-Date).ToUniversalTime().ToString('o') }
    Write-Log -Backend $Backend -Name 'wuscan' -Message ("analyse en ligne : $n mise(s) a jour")
} catch {
    Set-Etat @{ scanning = $false; ok = $false; error = $_.Exception.Message
                at = (Get-Date).ToUniversalTime().ToString('o') }
    Write-Log -Backend $Backend -Name 'wuscan' -Level 'ERROR' -Message $_.Exception.Message
} finally {
    if ($verrouLeve) {
        $repose = Set-UpdateLock -Etat 'pose' -Backend $Backend
        Write-Log -Backend $Backend -Name 'wuscan' -Message ("verrou repose : " + $repose)
        if (-not $repose) {
            Set-Etat @{ verrouNonRepose = $true }
            Write-Log -Backend $Backend -Name 'wuscan' -Level 'ERROR' -Message 'VERROU NON REPOSE'
        }
    }
    try { Remove-ProbeCache -Names @('pending.probe.ps1','lock.probe.ps1') -Backend $Backend } catch { }
}
