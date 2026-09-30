# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-powershell.ps1 - DO THE SCRIPTS STILL PARSE? READ ONLY, NOTHING IS EXECUTED.

    WHY THIS VERIFIER EXISTS. On 30/09, while renaming a word, the parser found that
    actions/update-mode-on.action.ps1 had not parsed since commit d1f7a64: a French apostrophe had been written
    inside a single-quoted string -- « peuvent s'installer » -- which closes the string and leaves the rest of the
    line as code. The action « Mode MAJ (deverrouiller) » could therefore never run, and NOTHING said so: the
    verifiers read markup, labels, names and the page's JavaScript, and no one read PowerShell. A file is parsed
    only when it is loaded, that is to say the day someone needs it.

    WHAT IT DOES. It hands every .ps1 and .psd1 of the repository to the PowerShell parser, without running any of
    them, and names the first error of each file with its line.
#>
param([switch]$Detail)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
Write-Title (Get-Label 'check-powershell.titre')

# dist: shipped versions, frozen; var: the service's clone (D112); local: my own workbench.
$skipped = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')
$files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1', '*.psd1' -ErrorAction SilentlyContinue |
           Where-Object {
               $rel = $_.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
               -not ($skipped | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') })
           })

$broken = @()
foreach ($f in $files) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count) {
        $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
        $broken += [pscustomobject]@{ File = $rel; Line = $errors[0].Extent.StartLineNumber; Message = $errors[0].Message }
    }
}

Write-Info (Get-Label 'check-powershell.comptes' $files.Count)
if ($broken.Count) {
    Write-Fail (Get-Label 'check-powershell.echecs' $broken.Count)
    foreach ($b in $broken) { Write-Detail (Get-Label 'check-powershell.ligne' $b.File $b.Line $b.Message) }
    Write-Warn (Get-Label 'check-powershell.comment-faire')
    exit 2
}
Write-Ok (Get-Label 'check-powershell.tout-analyse')
exit 0