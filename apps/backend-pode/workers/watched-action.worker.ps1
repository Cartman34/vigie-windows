# @author Florent HAZARD <f.hazard@sowapps.com>
<# Worker: runs the work of an asynchronous operation, WAITS for its end, and reports its outcome.

   Why it exists (D82). An asynchronous action used to be launched detached and forgotten: nobody read its
   exit code. On 26/08 the "Install PowerShell 7" button failed with 0x80070005 and the interface
   showed nothing. On 12/09 a Windows Update installation launched outside this watcher announced
   itself finished the moment it started.

   What it does, and what it does not. Start-Operation launches it and writes the busy mark with
   its process id BEFORE the action answers: the mark is not written here any more. It runs the
   work -- a PowerShell worker of workers/ or an external program, output redirected to the log --
   waits for its end, writes the result where every page reads it, then clears the mark. If it dies
   before writing, Get-ModuleBusyMark turns the dead mark into a failure.
   The rules: doc/progress/targeting/operations.md, section "Le protocole des opérations asynchrones". #>
param(
    [Parameter(Mandatory)][string]$Backend,
    [Parameter(Mandatory)][string]$ArgsB64
)
$ErrorActionPreference = 'Stop'
. (Join-Path $Backend 'lib/common.ps1')

$a = $null
try {
    $a = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64)) | ConvertFrom-Json
} catch { }
# NO SILENT EXIT. Without a module there is nowhere to write a result: the mark the launcher wrote
# then names a dead process, and Get-ModuleBusyMark reports the failure.
if (-not $a -or -not $a.module) {
    Write-Log -Backend $Backend -Name 'actions' -Level 'ERROR' -Message (Get-Label 'watched-action.charge-illisible')
    exit 1
}

$module = "$($a.module)"
$label  = "$($a.label)"
$action = "$($a.action)"
$argv   = @($a.arguments)
$log    = "$($a.log)"
$probes = @($a.probes | Where-Object { "$_" })

$t0 = Get-Date
$code = -1
$failure = ''
if (-not $a.file) {
    $failure = Get-Label 'watched-action.rien-a-lancer'
} else {
    try {
        # Arguments arrive RAW from the caller -- they carry paths, hence spaces: quoting them
        # is Start-ChildProcess's job, once, for everyone (D116).
        $options = @{ Wait = $true; PassThru = $true; WindowStyle = 'Hidden' }
        if ($log) {
            $options['RedirectStandardOutput'] = $log
            $options['RedirectStandardError']  = ($log -replace '[.]log$', '.err.log')
        }
        $p = Start-ChildProcess -FilePath "$($a.file)" -Arguments $argv -Options $options
        $code = [int]$p.ExitCode
    } catch {
        $failure = "$($_.Exception.Message)"
    }
}

$seconds = [int]((Get-Date) - $t0).TotalSeconds
Set-ModuleLastRun -Module $module -Action $action -Label $label -Code $code -Seconds $seconds `
                  -Log $log -Error $failure -Backend $Backend
Clear-ModuleBusyMark -Module $module -Backend $Backend

$level = if ($code -eq 0) { 'INFO' } else { 'ERROR' }
Write-Log -Backend $Backend -Name 'actions' -Level $level `
          -Message (Get-Label 'watched-action.code-en' $label $code $seconds $(if ($failure) { " -- " + $failure }))
# The card's values changed: they are recomputed at the next display.
try { if ($probes.Count) { Remove-ProbeCache -Names $probes -Backend $Backend } } catch { }
