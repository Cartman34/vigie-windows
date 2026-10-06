# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-scope.ps1 - EVERY CARD SAYS WHOSE INFORMATION IT CARRIES. READ ONLY.

    WHY THIS VERIFIER EXISTS. Information carried by a user account is fetched from that account, never from the
    service account (D128). The server app has no winget, no WSL, no Game Bar and nobody's settings. The trouble is
    that forgetting it LOOKS FINE: the card appears, the value reads plausibly, and it belongs to someone else.
    Measured on 05/10, twice in one day: the winget card did not exist at all because the service account's PATH
    never names a profile folder, and the first fix then showed one account's winget to another account's session.

    The owner's answer was a rule, not a patch: for every card -- and for every field when a card mixes the two --
    the documentation AND the code must say plainly whether what is shown comes from the machine or from the account
    looking. A rule held by vigilance is a rule already broken, so it is held here instead.

    WHAT IT DOES. It parses every probe and checks three things, naming the card each time:
      1. every `New-ModuleObject` declares `-Scope` ('machine', 'user' or 'mixed') ;
      2. a card declared 'mixed' gives every one of its `New-Field` calls its own `-Scope` ;
      3. a card declared 'machine' or 'user' does not repeat that same scope on a field -- a field only speaks when
         it departs from its card, otherwise the declaration becomes noise nobody reads ;
      4. a probe that speaks of an account -- a card scoped 'user' or 'mixed', a scope computed at run time, or any
         call to `Get-StateAccount` -- declares `PerAccount = $true` in its module.psd1. Without it the rendering
         goes into state-cache.json, which is SHARED: the first account to look leaves its answer there for all the
         others. Measured on 06/10: the packages card read the requester with no such declaration, and the winget
         card disappeared for the only account that owns winget.

    WHAT IT CANNOT DO. It does not know whether the answer is TRUE: a card declaring 'machine' while reading a
    profile is beyond a parser. What it guarantees is that someone decided, in the code, and said so.
#>
param([switch]$Detail)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')
Write-Title (Get-Label 'check-scope.titre')

$probeDir = Join-Path $repoRoot 'apps/backend-pode/probes'
$files = @(Get-ChildItem -LiteralPath $probeDir -Recurse -File -Filter '*.probe.ps1' -ErrorAction SilentlyContinue)

# THE SCOPE OF A COMMAND CALL, read from the syntax tree rather than from a regular expression: `-Scope` can be
# written on any line of a call spread over twenty, and a regular expression over lines finds the wrong call.
function Get-ScopeArgument {
    param([Parameter(Mandatory)]$Command)
    $elements = @($Command.CommandElements)
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
        if ($element.ParameterName -ne 'Scope') { continue }
        # `-Scope 'user'` puts the value in the next element; `-Scope:'user'` keeps it in the parameter itself.
        $value = $element.Argument
        if (-not $value -and ($i + 1) -lt $elements.Count) { $value = $elements[$i + 1] }
        if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $value.Value }
        # A scope computed at run time is legitimate -- a card can read a profile only when someone is signed in.
        # It is declared, which is what this verifier asks for; its value is the probe's business.
        return '(calculé)'
    }
    return $null
}

$cardsWithoutScope = @()
$mixedFieldsWithoutScope = @()
$redundantFields = @()
$personalWithoutPerAccount = @()
$cardCount = 0
$fieldCount = 0

foreach ($file in $files) {
    $rel = $file.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count) { continue }   # check-powershell owns parse errors; one verifier, one subject.

    $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    $cards = @($commands | Where-Object { "$($_.GetCommandName())" -eq 'New-ModuleObject' })
    $fields = @($commands | Where-Object { "$($_.GetCommandName())" -eq 'New-Field' })
    $fieldCount += $fields.Count

    # ONE FILE, ONE ANSWER: a probe that builds several cards declares the same scope on each, since a field cannot
    # be told which card will carry it -- they are built into one list and handed over at the end.
    $scopes = @()
    foreach ($card in $cards) {
        $cardCount++
        $scope = Get-ScopeArgument -Command $card
        if (-not $scope) {
            $cardsWithoutScope += [pscustomobject]@{ File = $rel; Line = $card.Extent.StartLineNumber }
            continue
        }
        if ($scopes -notcontains $scope) { $scopes += $scope }
    }
    if (-not $scopes.Count) { continue }

    # DOES THIS PROBE SPEAK OF AN ACCOUNT? Three signs, and any one of them is enough.
    $readsAccount = @($commands | Where-Object { "$($_.GetCommandName())" -eq 'Get-StateAccount' }).Count -gt 0
    $personal = $readsAccount -or ($scopes | Where-Object { $_ -in @('user', 'mixed', '(calculé)') }).Count -gt 0
    if ($personal) {
        $perAccount = $false
        try {
            $declaration = Join-Path (Split-Path $file.FullName -Parent) 'module.psd1'
            if (Test-Path -LiteralPath $declaration) {
                $perAccount = [bool](Import-PowerShellDataFile -LiteralPath $declaration -ErrorAction Stop).PerAccount
            }
        } catch { }
        if (-not $perAccount) { $personalWithoutPerAccount += [pscustomobject]@{ File = $rel } }
    }

    foreach ($field in $fields) {
        $fieldScope = Get-ScopeArgument -Command $field
        if ($scopes -contains 'mixed' -and -not $fieldScope) {
            $mixedFieldsWithoutScope += [pscustomobject]@{ File = $rel; Line = $field.Extent.StartLineNumber }
        }
        if ($fieldScope -and $scopes.Count -eq 1 -and $scopes[0] -eq $fieldScope) {
            $redundantFields += [pscustomobject]@{ File = $rel; Line = $field.Extent.StartLineNumber; Scope = $fieldScope }
        }
    }
}

Write-Info (Get-Label 'check-scope.comptes' $cardCount $fieldCount $files.Count)
$failed = $false

if ($cardsWithoutScope.Count) {
    $failed = $true
    Write-Fail (Get-Label 'check-scope.cartes-sans-portee' $cardsWithoutScope.Count)
    foreach ($row in $cardsWithoutScope) { Write-Detail (Get-Label 'check-scope.ligne' $row.File $row.Line) }
}
if ($mixedFieldsWithoutScope.Count) {
    $failed = $true
    Write-Fail (Get-Label 'check-scope.champs-sans-portee' $mixedFieldsWithoutScope.Count)
    foreach ($row in $mixedFieldsWithoutScope) { Write-Detail (Get-Label 'check-scope.ligne' $row.File $row.Line) }
}
if ($personalWithoutPerAccount.Count) {
    $failed = $true
    Write-Fail (Get-Label 'check-scope.sans-per-account' $personalWithoutPerAccount.Count)
    foreach ($row in $personalWithoutPerAccount) { Write-Detail (Get-Label 'check-scope.fichier' $row.File) }
}
if ($redundantFields.Count) {
    $failed = $true
    Write-Fail (Get-Label 'check-scope.champs-redondants' $redundantFields.Count)
    foreach ($row in $redundantFields) { Write-Detail (Get-Label 'check-scope.ligne-redondante' $row.File $row.Line $row.Scope) }
}

if ($failed) {
    Write-Warn (Get-Label 'check-scope.comment-faire')
    exit 2
}
Write-Ok (Get-Label 'check-scope.tout-declare')
exit 0
