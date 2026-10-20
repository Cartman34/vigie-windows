# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: floor
# @uses:
<#
    Intent: THE USER RIGHTS WINDOWS GRANTS AN ACCOUNT, through secedit: the right to log on as a batch job, which a task registered with a password needs in order to start at all. Not to be confused with rights.ps1, which says who may run which action in Vigie.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

<#
    THE RIGHT "LOG ON AS A BATCH JOB" (SeBatchLogonRight), granted or revoked through secedit. A task registered with
    a password starts only if its account holds it; the uninstall takes it back, so that no right outlives the
    account. No display here: the caller says what was done. Returns ok, changed and error.
#>
function Set-BatchLogonRight {
    param([Parameter(Mandatory)][string]$Sid, [switch]$Revoke)
    $stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $exportFile = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '.inf')
    $importFile = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '-import.inf')
    $database   = Join-Path $env:TEMP ('vigie-secpol-' + $stamp + '.sdb')
    try {
        $out = & secedit.exe /export /areas USER_RIGHTS /cfg $exportFile 2>&1
        if (-not (Test-Path -LiteralPath $exportFile)) {
            return [pscustomobject]@{ ok = $false; changed = $false; error = (@($out) -join ' ') }
        }
        $line = Get-Content -LiteralPath $exportFile | Where-Object { $_ -match '^SeBatchLogonRight' } | Select-Object -First 1
        $holders = @()
        if ($line) { $holders = @((($line -split '=', 2)[1]).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $mine = '*' + $Sid
        $has = $holders -contains $mine
        if ($Revoke) {
            if (-not $has) { return [pscustomobject]@{ ok = $true; changed = $false; error = $null } }
            $holders = @($holders | Where-Object { $_ -ne $mine })
        } else {
            if ($has) { return [pscustomobject]@{ ok = $true; changed = $false; error = $null } }
            $holders += $mine
        }
        # A MINIMAL POLICY FILE: only the line we are about.
        $content = @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1',
                     '[Privilege Rights]', ('SeBatchLogonRight = ' + ($holders -join ','))) -join [Environment]::NewLine
        [IO.File]::WriteAllText($importFile, $content, [Text.Encoding]::Unicode)
        $out = & secedit.exe /configure /db $database /cfg $importFile /areas USER_RIGHTS 2>&1
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ ok = $false; changed = $false; error = (@($out) -join ' ') } }
        return [pscustomobject]@{ ok = $true; changed = $true; error = $null }
    } catch {
        return [pscustomobject]@{ ok = $false; changed = $false; error = $_.Exception.Message }
    } finally {
        foreach ($f in @($exportFile, $importFile, $database)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}
