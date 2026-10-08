# @author Florent HAZARD <f.hazard@sowapps.com>
<# A DETACHED worker: an ONLINE search for Windows updates.

   Intent: see what Windows has not discovered yet. The `pending` probe only makes a LOCAL search (Windows
   Update's cache): it is instantaneous but sees only what Windows has already found. This analysis questions the
   servers: it takes minutes, hence the detached worker.
   Usage: it is started by the wu-scan action. The Update Mode lock stops the scans: it is lifted then LAID
   BACK, as for the installation. The user has nothing to undo by hand.
#>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { exit 1 }
. (Join-Path $Backend 'lib/common.ps1')

$restoreLock = $false
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        $restoreLock = [bool]$a.reposerVerrou
    }
} catch { }

$outFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'wu-scan.json'
function Set-Etat { param([hashtable]$Set) try { Update-StateJson -Path $outFile -Set $Set | Out-Null } catch { } }

$lockLifted = $false
$exitCode = 0
try {
    if ($restoreLock) {
        $lockLifted = Set-UpdateLock -State 'leve' -Backend $Backend
        Write-Log -Backend $Backend -Name 'wuscan' -Message (Get-Label 'wu-scan.verrou-leve' $lockLifted)
    }

    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $searcher.Online = $true      # <- toute la difference avec la sonde
    $res = $searcher.Search("IsInstalled=0 And IsHidden=0")
    $n = [int]$res.Updates.Count

    Set-Etat @{ ok = $true; trouvees = $n; error = $null
                at = (Get-Date).ToUniversalTime().ToString('o') }
    Write-Log -Backend $Backend -Name 'wuscan' -Message (Get-Label 'wu-scan.analyse-en-ligne-mise' $n)
} catch {
    Set-Etat @{ ok = $false; error = $_.Exception.Message
                at = (Get-Date).ToUniversalTime().ToString('o') }
    Write-Log -Backend $Backend -Name 'wuscan' -Level 'ERROR' -Message $_.Exception.Message
    $exitCode = 1
    Write-Output ('[X] ' + $_.Exception.Message)
} finally {
    if ($lockLifted) {
        $repose = Set-UpdateLock -State 'pose' -Backend $Backend
        Write-Log -Backend $Backend -Name 'wuscan' -Message (Get-Label 'wu-scan.verrou-repose' $repose)
        if (-not $repose) {
            Set-Etat @{ verrouNonRepose = $true }
            Write-Log -Backend $Backend -Name 'wuscan' -Level 'ERROR' -Message (Get-Label 'wu-scan.verrou-non-repose')
        }
    }
    try { Remove-ProbeCache -Names @('pending.probe.ps1','lock.probe.ps1') -Backend $Backend } catch { }
}
exit $exitCode
