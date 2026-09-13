# @author Florent HAZARD <f.hazard@sowapps.com>
<# Worker: brings the service clone back to a clean copy of the declared source.

   The maintenance of a piece the service owns alone (doc/progress/targeting/components.md). Launched by the actions
   service-clone-repair and service-clone-reset through Start-Operation: an administrator, or the agent on the
   development computer, repairs the clone without elevation of their own and leaves an audit trace.

   repair: forced fetch, then a fresh clone if git still refuses while the source answers.
   reset:  a fresh clone in every case. The old clone goes only once the new one exists. #>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { exit 1 }
. (Join-Path $Backend 'lib/common.ps1')

$mode = 'repair'
try {
    if ($ArgsB64) {
        $a = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64)) | ConvertFrom-Json
        if ("$($a.mode)" -eq 'reset') { $mode = 'reset' }
    }
} catch { }

$update = Update-ServiceClone -Backend $Backend -Reset:($mode -eq 'reset')
# The deployment card compares against the clone: the stamp of the previous synchronisation must not answer for it.
try { Remove-Item -LiteralPath (Get-VarPath -Backend $Backend -Kind 'cache' -File 'clone-sync.json') -Force -ErrorAction SilentlyContinue } catch { }

if ($update.ok) {
    Write-Output (Get-Label 'service-clone.pret' $(if ($update.recloned) { ' (recréé)' } else { '' }))
    exit 0
}
Write-Output ('[X] ' + $update.error)
exit 1
