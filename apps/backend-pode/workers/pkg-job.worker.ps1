# @author Florent HAZARD <f.hazard@sowapps.com>
<# A single DETACHED worker: it runs one package operation ('check' or 'upgrade') for ONE manager, then refreshes
   the update count and invalidates the probe.
   Started by Start-PkgJob through Start-DetachedAction (a hidden pwsh). It writes ONLY into var/cache and
   var/log. Errors and output go through Get-PkgUpdates / Invoke-PkgUpgrade. #>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { exit 1 }
. (Join-Path $Backend 'lib/common.ps1')

# Parameters (base64 JSON): mgr + op + pkgs (the packages kept; empty does NOT mean all, D131) + account + all.
$mgr = $null; $op = 'check'; $pkgs = @(); $account = $null; $all = $false
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        $mgr = "$($a.mgr)"
        if ($a.op) { $op = "$($a.op)" }
        if ($a.pkgs) { $pkgs = @($a.pkgs | ForEach-Object { "$_" }) }
        if ($a.account) { $account = "$($a.account)" }
        if ($null -ne $a.all) { $all = [bool]$a.all }
    }
} catch { }
if (-not $mgr) { Write-Output ('[X] ' + (Get-Label 'pkg-job.gestionnaire-absent')); exit 1 }

if (-not $account) { Write-Output ('[X] ' + 'aucun compte : une operation de paquets se fait dans une session'); exit 1 }
$outFile = Get-VarPath -Backend $Backend -Kind 'cache' -File ('pkgupdates-' + $account + '.json')
$exitCode = 0
<#
    THE WORK HAPPENS IN THE ACCOUNT'S SESSION (D128), not here.

    This worker runs under the service account: it has no winget -- an MSIX package refuses to launch for an account
    it is not registered for, measured on 06/10 -- and packages installed in a profile are not its own. It keeps what
    is its: the operation, its result, the card's invalidation. The reading and the installing leave as a CLIENT
    TASK, to whoever is looking.

    The timeout is wide: updating several packages takes minutes, and nothing waits behind this process -- which is
    the whole point of an asynchronous operation.
#>
function Invoke-PkgInSession {
    param([Parameter(Mandatory)][string]$Operation, [string[]]$Packages = @())
    $timeout = if ($Operation -eq 'upgrade') { 3600 } else { 180 }
    $answer = Invoke-ClientTask -Account $account -Type 'pkg-updates' -Module ('pkg-' + $mgr) -TimeoutSec $timeout `
                                -Params @{ mgr = $mgr; op = $Operation; pkgs = @($Packages); all = $all } -Backend $Backend
    if (-not $answer) { throw "l'app cliente de $account n'a pas repondu" }
    if (-not $answer.result -or -not $answer.result.ok) { throw "$($answer.message)" }
    return $answer.result
}

try {
    $answer = Invoke-PkgInSession -Operation $op -Packages $pkgs
    $u = $answer.updates
    if ($op -eq 'upgrade') {
        $up = $answer.upgrade
        # We log what WAS DONE (the number of packages, the failures observed), not what was asked for: a package
        # can fail on its own without making the others fail.
        $detail = if ($up.count) { " paquets=$($up.count)" } else { " (tout le gestionnaire)" }
        if ($up.failed -and @($up.failed).Count) { $detail += " echecs=" + (@($up.failed) -join ',') }
        try { Write-Log -Backend $Backend -Name 'pkgupgrade' -Message (Get-Label 'pkg-job.exit-ok-reboot' $mgr $($up.exit) $($up.ok) $($up.reboot) $detail) } catch { }
        try {
            $logf = Join-Path (Get-LogDir -Backend $Backend) ("pkgupgrade_" + $mgr + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")
            "$($up.output)" | Out-File -FilePath $logf -Encoding UTF8
        } catch { }
    }
    # LET THE MANAGER CATCH ITS BREATH.
    #
    # The check that follows an update used to run within the SECOND: winget had not refreshed its inventory yet
    # and listed again the package it had just installed. Lived through on 27/08: one package updated successfully
    # ("installed correctly", code 0) and offered again two seconds later -- "I asked to install it and in return,
    # it is not installed".
    #
    # AND WE KNOW WHAT WE HAVE JUST DONE: a package whose update SUCCEEDED is not offered again, even if the
    # manager still announces it. The log is authoritative -- exit code 0 and absent from the list of failures.


    if ($op -eq 'upgrade' -and $up -and @($pkgs).Count) {
        $succeeded = @($pkgs | Where-Object { @($up.failed) -notcontains "$_" })
        if ($succeeded.Count) {
            $restants = @(@($u.pkgs) | Where-Object { $succeeded -notcontains "$($_.id)" })
            if (@($restants).Count -ne @($u.pkgs).Count) {
                $u = @{ count      = @($restants).Count
                        items      = @($restants | ForEach-Object { "$($_.titre)" })
                        pkgs       = @($restants)
                        supported  = $u.supported
                        selectable = $u.selectable }
                Write-Log -Backend $Backend -Name 'pkgupgrade' `
                          -Message (Get-Label 'pkg-job.paquet-retire-de-la' $mgr $succeeded.Count)
            }
        }
    }
    # `pkgs` (the targetable identifiers) is kept with the rest: the window of choice reads it as it stands,
    # without starting a slow check at the moment of the click.
    $state = @{ count = [int]$u.count; items = @($u.items); pkgs = @($u.pkgs); at = (Get-Date).ToString('s') }
    # A pending restart must be VISIBLE in the card: it is an action expected of the user, not a line of log.
    if ($op -eq 'upgrade' -and $up -and $up.reboot) { $state.reboot = $true }
    # Le RESULTAT de la mise a jour est conserve pour la carte : sans lui, l'operation se
    # termine en silence et l'utilisateur ne sait pas ce qui a ete fait ni si ca a marche.
    if ($op -eq 'upgrade' -and $up) {
        $state.last = @{
            at      = (Get-Date).ToString('s')
            ok      = [bool]$up.ok
            count   = if ($up.count) { [int]$up.count } else { 0 }   # 0 = tout le gestionnaire
            failed  = @($up.failed)
            reasons = $(if ($up.reasons) { $up.reasons } else { @{} })
        }
    }
    Update-StateJson -Path $outFile -Set @{ $mgr = $state } | Out-Null
    # A failed upgrade leaves by the exit code, so that the card and the notification say it.
    if ($op -eq 'upgrade' -and $up -and -not $up.ok) {
        $exitCode = 1
        Write-Output ('[X] ' + (Get-Label 'pkg-job.mise-a-jour-en-echec' $mgr))
    }
    Write-Log -Backend $Backend -Name 'pkgcheck' -Message (Get-Label 'pkg-job.maj-disponible' $mgr $op $([int]$u.count))
} catch {
    try { Update-StateJson -Path $outFile -Set @{ $mgr = @{ count = 0; items = @(); at = (Get-Date).ToString('s'); error = $_.Exception.Message } } | Out-Null } catch { }
    Write-Log -Backend $Backend -Name 'pkgcheck' -Level 'ERROR' -Message ("$mgr ($op) : " + $_.Exception.Message)
    $exitCode = 1
    Write-Output ('[X] ' + $_.Exception.Message)
}

# Rafraichissement immediat de la carte au prochain acces (sans attendre le TTL).
try { Remove-ProbeCache -Names @('packages.probe.ps1') -Backend $Backend } catch { }
exit $exitCode
