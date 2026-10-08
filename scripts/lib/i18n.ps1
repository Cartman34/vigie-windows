# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    i18n.ps1 -- THE LABELS LIVE IN lang/, NOT IN THE CODE.
    No dependency: loadable under Windows PowerShell 5.1 as well as under PowerShell 7.

    Intent: make the displayed text DATA, so that a second language is a file and not a rewrite of a hundred
    scripts.
    Usage:

        . (Join-Path $repoRoot 'scripts/lib/i18n.ps1')
        Write-Ok (Get-Label 'service.task-registered' $taskName)

    WHY THIS FILE EXISTS. The French text was written into the scripts themselves. Two consequences, and the
    second is the real one: every file needed a BOM so that 5.1 did not mangle the accents, and above all no
    second language was possible without rewriting a hundred files. Labels are DATA; they come out of the code.

    THE FORMAT IS JSON, for one reason only: it is the only one both PowerShell and the browser read without
    installing anything. So the front end and the scripts share the same file, and a label can no longer diverge
    between the two.

    THE FILE IS UTF-8 WITHOUT A BOM: that is what the JSON standard demands, and what `fetch()` expects on the
    browser side. The encoding checker knows that rule.

    THE FAILURE MODE WE REFUSE. A missing key returning an empty string would be the worst of all: the message
    would disappear with nothing to report it. Here, a missing key returns a visible marker carrying the key's
    own name, AND goes into the log. The checker `scripts/dev/check-labels.ps1` forbids delivering one.

    The holes are written "{0}", "{1}": that is PowerShell's -f operator, and it is also what the front end's
    little replacer understands. A numbered hole, and not a named one, because a translation has the right to
    change the ORDER of the pieces.
#>

# The language in force. One only for now; the day there are two, this variable is what changes, and nothing
# else.
$script:LabelLanguage = 'fr'
$script:LabelTable    = $null

function Get-LabelFilePath {
    param([string]$Language = $script:LabelLanguage)
    # The lang/ folder is at the root of the repository: two levels above scripts/lib/.
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    return (Join-Path (Join-Path $root 'lang') ($Language + '.json'))
}

# Loads the table once per session. A labels file does not change during a run; reading it again at every call
# would cost one disc access per line displayed.
function Import-Labels {
    param([switch]$Force)
    if ($script:LabelTable -and -not $Force) { return $script:LabelTable }
    $file = Get-LabelFilePath
    if (-not (Test-Path -LiteralPath $file)) {
        # WE DO NOT CRASH HERE. An installation script that dies because it cannot find its labels would be
        # absurd: it must be able to say what is wrong.
        $script:LabelTable = @{}
        return $script:LabelTable
    }
    $raw = [System.IO.File]::ReadAllText($file, (New-Object System.Text.UTF8Encoding($false)))
    $obj = $raw | ConvertFrom-Json
    $table = @{}
    foreach ($p in $obj.PSObject.Properties) { $table[$p.Name] = [string]$p.Value }
    $script:LabelTable = $table
    return $script:LabelTable
}

<#
    The label of a key, with its holes filled.

        Get-Label 'service.task-registered' 'Vigie - Serveur'

    A missing key returns a visible marker carrying the key's own name: findable, and never empty.
#>
function Get-Label {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Position = 1, ValueFromRemainingArguments)][object[]]$Values
    )
    $table = Import-Labels
    if (-not $table.ContainsKey($Key)) {
        return ('[?' + $Key + ']')
    }
    $text = $table[$Key]
    # ZERO IS NOT "NOTHING". "if ($Values -and ...)" converts an array of ONE element into the value of that
    # element: @(0) is therefore FALSE, like @('') and @($false). The consequence observed on 29/08: a line
    # reporting an exit code -- the code was 0, that is to say success, and that is exactly the line we were
    # losing. We test the NUMBER of elements, never their truth.
    if ($null -ne $Values -and $Values.Count -gt 0) {
        try { return ($text -f $Values) }
        catch {
            # A HOLE COUNTED WRONG MUST NOT BRING THE SCRIPT DOWN. We return the label raw, with its marker: the
            # checker counts the holes, that is its job.
            return ($text + ' [!trous]')
        }
    }
    return $text
}

# The keys asked for during this run that could not be found. It serves the checker, and a diagnosis when a
# message comes out as a marker.
